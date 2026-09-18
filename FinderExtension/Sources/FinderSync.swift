import AppKit
import FinderSync
import PathBridgeCore
import Darwin
import OSLog

final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "com.yuna.PathBridge.FinderExtension", category: "Finder")
    override init() {
        super.init()
        updateDirectories()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateDirectories), name: name, object: nil)
        }
    }

    @objc private func updateDirectories() {
        // Finder 不会将 /Volumes 的监听自动延伸到每个挂载的文件系统。
        // 直接读取内核挂载表，避免为注册菜单而访问网络宗卷。
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count >= 0 else { return }
        let capacity = Int(count) + 16
        guard capacity <= Int(Int32.max) / MemoryLayout<statfs>.stride else { return }
        var entries = Array<statfs>(repeating: statfs(), count: capacity)
        let filled = entries.withUnsafeMutableBufferPointer {
            getfsstat($0.baseAddress, Int32(capacity * MemoryLayout<statfs>.stride), MNT_NOWAIT)
        }
        guard filled >= 0 else { return }
        var roots: Set<URL> = [URL(fileURLWithPath: "/Volumes", isDirectory: true)]
        for entry in entries.prefix(min(Int(filled), capacity)) {
            let path: String? = withUnsafeBytes(of: entry.f_mntonname) { bytes in
                guard let end = bytes.firstIndex(of: 0) else { return nil }
                return String(bytes: bytes[..<end], encoding: .utf8)
            }
            if let path, path.hasPrefix("/Volumes/") {
                roots.insert(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        FIFinderSyncController.default().directoryURLs = roots
        logger.notice("Registered \(roots.count) Finder directory roots")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let urls: [URL]
        if menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForSidebar {
            urls = controller.targetedURL().map { [$0] } ?? []
        } else {
            urls = controller.selectedItemURLs() ?? []
        }
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return nil }
        let paths = urls.map(\.path)
        logger.notice("Finder menu requested for \(paths.count) items")
        let menu = NSMenu(title: "PathBridge")
        for (index, entry) in [
            ("复制 macOS 路径", FinderAction.copyMacOS),
            ("复制 Windows 路径", .copyWindows),
            ("复制 UNC 路径", .copyUNC),
            ("复制 SMB 地址", .copySMB),
            ("在 Finder 中打开", .open)
        ].enumerated() {
            let (title, action) = entry
            guard (try? FinderCommand(action: action, paths: paths)) != nil else { continue }
            let item = NSMenuItem(title: title, action: #selector(performCommand(_:)), keyEquivalent: "")
            item.target = self
            // Finder 会重建菜单项，representedObject 不会跨进程传回。
            item.tag = index + ((menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForSidebar) ? 100 : 0)
            menu.addItem(item)
        }
        guard !menu.items.isEmpty else { return nil }
        let root = NSMenu()
        let parent = NSMenuItem(title: "PathBridge", action: nil, keyEquivalent: "")
        parent.submenu = menu
        root.addItem(parent)
        return root
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        let actions: [FinderAction] = [.copyMacOS, .copyWindows, .copyUNC, .copySMB, .open]
        let index = sender.tag % 100
        guard actions.indices.contains(index) else { return }
        let controller = FIFinderSyncController.default()
        let urls = sender.tag >= 100 ? (controller.targetedURL().map { [$0] } ?? []) : (controller.selectedItemURLs() ?? [])
        guard urls.allSatisfy(\.isFileURL),
              let command = try? FinderCommand(action: actions[index], paths: urls.map(\.path)),
              let url = try? command.url() else { NSSound.beep(); return }
        if !NSWorkspace.shared.open(url) { NSSound.beep() }
    }
}
