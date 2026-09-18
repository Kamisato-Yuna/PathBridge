import AppKit
import Observation
import PathBridgeCore
import ServiceManagement

@MainActor @Observable
final class AppState {
    static let shared = AppState()
    let updates = UpdateChecker()
    let settings = SettingsStore()
    let volumes = VolumeManager()
    private let hotkeys = HotkeyManager()
    private(set) var isOpening = false
    private(set) var status = "复制路径，然后按 ⌥⌘O"
    private(set) var hotkeyError: String?
    private(set) var loginStatus = SMAppService.mainApp.status

    init() {
        status = "复制路径，然后按 \(settings.configuration.hotkey.label)"
        hotkeys.action = { [weak self] in self?.openClipboard() }
        do { try hotkeys.register(settings.configuration.hotkey) }
        catch { hotkeyError = error.localizedDescription }
        if let error = settings.loadError { status = error }
    }

    func save(_ configuration: AppConfiguration) throws {
        try configuration.validate()
        let old = settings.configuration.hotkey
        try hotkeys.register(configuration.hotkey)
        do { try settings.save(configuration) }
        catch {
            do { try hotkeys.register(old) }
            catch { hotkeyError = error.localizedDescription }
            throw error
        }
        hotkeyError = nil
    }

    func refresh() async {
        await volumes.refresh()
        loginStatus = SMAppService.mainApp.status
    }

    func resolver() -> PathResolver {
        PathResolver(mappings: settings.configuration.storages)
    }

    func resolve(_ input: String) throws -> ResolvedPath {
        let text = try ClipboardParser.parse(input)
        let fileURL = URLComponents(string: text)
        let localPath = text.hasPrefix("/Volumes/") ? text :
            (fileURL?.scheme == "file" && (fileURL?.host == nil || fileURL?.host == "" || fileURL?.host == "localhost") ? fileURL?.path : nil)
        if let localPath {
            let actual = settings.configuration.storages.compactMap { mapping -> StorageMapping? in
                guard let path = volumes.mountPath(for: mapping) else { return nil }
                var copy = mapping
                copy.mountPath = path
                return copy
            }.sorted { $0.mountPath.count > $1.mountPath.count }
            for mapping in actual {
                if let result = try? PathResolver(mappings: [mapping]).resolve(text) { return result }
            }
            if volumes.mounted.contains(where: { localPath == $0.path || localPath.hasPrefix($0.path + "/") }) {
                throw PathResolverError.mappingNotFound(localPath)
            }
        }
        return try resolver().resolve(text)
    }

    func render(_ path: ResolvedPath, as format: PathFormat) throws -> String {
        guard format == .macOS,
              var mapping = settings.configuration.storages.first(where: { $0.id == path.storageID }),
              let actualPath = volumes.mountPath(for: mapping) else {
            return try resolver().render(path, as: format)
        }
        mapping.mountPath = actualPath
        return try PathResolver(mappings: [mapping]).render(path, as: format)
    }

    func unmappedSMBURL(_ input: String) throws -> URL {
        do { return try resolver().smbURL(for: input) }
        catch PathResolverError.networkLocationUnknown {
            let text = try ClipboardParser.parse(input)
            let lower = text.lowercased()
            // 已挂载但未配置的 macOS 路径，可以使用系统确认的共享来源。
            if text.hasPrefix("/Volumes/") || lower.hasPrefix("file:///") || lower.hasPrefix("file://localhost/") {
                for mounted in volumes.mounted.sorted(by: { $0.path.count > $1.path.count }) {
                    let mapping = StorageMapping(id: "mounted", name: mounted.share, server: mounted.server,
                        share: mounted.share, mountPath: mounted.path)
                    let resolver = PathResolver(mappings: [mapping])
                    if let resolved = try? resolver.resolve(text),
                       let url = URL(string: try resolver.render(resolved, as: .smb)) { return url }
                }
            }
            throw PathResolverError.networkLocationUnknown
        }
    }

    func copy(_ format: PathFormat) {
        Task {
            do {
                await volumes.refresh()
                let output = try convertedPath(ClipboardService.read(), as: format)
                try ClipboardService.write(output)
                status = "已复制：\(output)"
            } catch { report(error) }
        }
    }

    func convertedPath(_ input: String, as format: PathFormat) throws -> String {
        do {
            let path = try resolve(input)
            let hasDrive = settings.configuration.storages.first(where: { $0.id == path.storageID })?.windowsDrive != nil
            return try render(path, as: format == .windowsDrive && !hasDrive ? .unc : format)
        } catch PathResolverError.mappingNotFound {
            if format == .macOS, input.hasPrefix("/Volumes/") { return input }
            let url = try unmappedSMBURL(input)
            if format == .smb { return url.absoluteString }
            guard format == .unc || format == .windowsDrive,
                  let server = url.host, let share = url.pathComponents.dropFirst().first else {
                throw PathResolverError.mappingNotFound(input)
            }
            let mapping = StorageMapping(id: "mounted", name: share, server: server,
                                         share: share, mountPath: "/Volumes/" + share)
            let resolver = PathResolver(mappings: [mapping])
            return try resolver.render(resolver.resolve(url.absoluteString), as: .unc)
        }
    }

    func handleFinderCommand(_ command: FinderCommand) {
        if command.action == .open {
            openPath(command.paths[0])
            return
        }
        let format: PathFormat
        switch command.action {
        case .copyMacOS: format = .macOS
        case .copyWindows: format = .windowsDrive
        case .copyUNC: format = .unc
        case .copySMB: format = .smb
        case .open: return
        }
        Task {
            do {
                await volumes.refresh()
                let outputs = try command.paths.map { try convertedPath($0, as: format) }
                try ClipboardService.write(outputs.joined(separator: "\n"))
                status = "已从 Finder 复制 \(outputs.count) 条路径"
            } catch { report(error) }
        }
    }

    func openClipboard() {
        guard !isOpening else { return }
        let input: String
        do { input = try ClipboardService.read() } catch { report(error); return }
        openPath(input)
    }

    func openPath(_ input: String) {
        guard !isOpening else { return }
        isOpening = true
        status = "正在解析路径…"
        Task {
            defer { isOpening = false }
            do {
                await volumes.refresh()
                let resolved: ResolvedPath
                do { resolved = try resolve(input) }
                catch PathResolverError.mappingNotFound {
                    let url = try unmappedSMBURL(input)
                    status = "正在连接 \(url.host ?? "SMB")…"
                    try await volumes.prepareUnmappedURL(url)
                    guard NSWorkspace.shared.open(url) else {
                        throw AppError.message("系统默认文件浏览器无法打开此 SMB 地址，请检查 SMB 默认处理程序。")
                    }
                    status = "已交给默认文件浏览器：\(url.absoluteString)"
                    return
                }
                guard let mapping = settings.configuration.storages.first(where: { $0.id == resolved.storageID }) else {
                    throw AppError.message("找不到对应的 Storage 映射。")
                }
                status = "正在连接 \(mapping.name)…"
                let mountPath = try await volumes.ensureMounted(mapping)
                let target = resolved.components.reduce(URL(fileURLWithPath: mountPath, isDirectory: true)) {
                    $0.appendingPathComponent($1)
                }
                let kind = try await Task.detached(priority: .userInitiated) {
                    try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
                }.value
                if kind {
                    guard NSWorkspace.shared.open(target) else { throw AppError.message("Finder 无法打开此目录。") }
                } else {
                    guard NSWorkspace.shared.selectFile(target.path, inFileViewerRootedAtPath: "") else {
                        throw AppError.message("Finder 无法定位此文件，请确认共享仍然可用。")
                    }
                }
                status = kind ? "已打开目录：\(target.lastPathComponent)" : "已在 Finder 中定位文件：\(target.lastPathComponent)"
            } catch { report(error) }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { report(error) }
        loginStatus = SMAppService.mainApp.status
    }

    func report(_ error: Error) {
        if error is CancellationError { status = "已取消"; return }
        status = error.localizedDescription
        let alert = NSAlert()
        alert.messageText = "PathBridge"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
