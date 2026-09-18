import AppKit
import NetFS
import Observation
import PathBridgeCore

struct MountedShare: Sendable {
    let server: String
    let share: String
    let path: String

    func matches(_ mapping: StorageMapping) -> Bool {
        server.caseInsensitiveCompare(mapping.server) == .orderedSame &&
        share.caseInsensitiveCompare(mapping.share) == .orderedSame
    }
}

@MainActor @Observable
final class VolumeManager {
    private(set) var mounted: [MountedShare] = []
    private(set) var connectingStorageID: String?
    private(set) var connectingServer: String?
    private var request: MountRequest?

    func refresh() async {
        mounted = await Task.detached(priority: .utility) {
            let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
            return urls.compactMap { url -> MountedShare? in
                guard let remote = NetFSCopyURLForRemountingVolume(url as CFURL)?.takeRetainedValue() as URL?,
                      remote.scheme?.lowercased() == "smb", let server = remote.host,
                      let share = remote.pathComponents.dropFirst().first else { return nil }
                return MountedShare(server: server, share: share, path: url.path)
            }
        }.value
    }

    func mountPath(for mapping: StorageMapping) -> String? {
        guard let root = mounted.first(where: { $0.matches(mapping) })?.path else { return nil }
        return mapping.subpath.split(separator: "/").reduce(root) { $0 + "/" + $1 }
    }

    func ensureMounted(_ mapping: StorageMapping) async throws -> String {
        await refresh()
        if let path = mountPath(for: mapping) { return path }
        let credential = try CredentialStore.connectionCredential(storageID: mapping.id, server: mapping.server, share: mapping.share)
        try await connect(server: mapping.server, share: mapping.share, storageID: mapping.id, credential: credential)
        guard let path = mountPath(for: mapping) else {
            throw AppError.message("系统已完成连接，但尚未找到匹配的 SMB 挂载。请在 Finder 中确认服务器与共享名称后重试。")
        }
        return path
    }

    /// 未映射路径仍交给默认浏览器打开；存在主凭据时先用 NetFS 连接共享根。
    func prepareUnmappedURL(_ url: URL) async throws {
        let validated = try PathResolver(mappings: []).smbURL(for: url.absoluteString)
        guard let server = validated.host, let share = validated.pathComponents.dropFirst().first else {
            throw AppError.message("SMB 地址无效。")
        }
        await refresh()
        if mounted.contains(where: { $0.server.caseInsensitiveCompare(server) == .orderedSame &&
            $0.share.caseInsensitiveCompare(share) == .orderedSame }) { return }
        guard let credential = try CredentialStore.connectionCredential(storageID: nil, server: server, share: share) else { return }
        try await connect(server: server, share: share, storageID: nil, credential: credential)
    }

    private func connect(server: String, share: String, storageID: String?, credential: SMBCredential?) async throws {
        guard request == nil else { throw AppError.message("正在连接共享，请稍后再试。") }
        var components = URLComponents()
        components.scheme = "smb"
        components.host = server
        components.path = "/" + share
        guard let url = components.url else { throw AppError.message("SMB 地址无效。") }
        let pending = MountRequest()
        request = pending
        connectingStorageID = storageID
        connectingServer = server
        defer { request = nil; connectingStorageID = nil; connectingServer = nil }
        try await pending.mount(url, credential: credential)
        await refresh()
    }

    func cancelMount() { request?.cancel() }
}

/// NetFS owns authentication UI. A request always resumes its continuation once,
/// including timeout/cancel (NetFS itself does not invoke the completion on cancel).
@MainActor
private final class MountRequest {
    private var requestID: AsyncRequestID?
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?

    func mount(_ url: URL, credential: SMBCredential?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let options = NSMutableDictionary(dictionary: [kNAUIOptionKey: kNAUIOptionAllowUI])
            let status = NetFSMountURLAsync(url as CFURL, nil, credential?.username as CFString?, credential?.password as CFString?, options, nil, &requestID, .main) { [weak self] status, _, _ in
                Task { @MainActor in self?.finish(status: status) }
            }
            if status != 0 { finish(status: status); return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(90)) } catch { return }
                self?.cancel(message: "连接 SMB 超时，请检查网络或 VPN 后重试。")
            }
        }
    }

    func cancel(message: String = "已取消连接。") {
        if let requestID { NetFSMountURLCancel(requestID) }
        complete(.failure(AppError.message(message)))
    }

    private func finish(status: Int32) {
        if status == 0 { complete(.success(())) }
        else if status == -128 { complete(.failure(AppError.message("已取消 SMB 身份认证。"))) }
        else { complete(.failure(AppError.message("SMB 连接失败（\(status)）。请检查网络、共享名称与访问权限。"))) }
    }

    private func complete(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        requestID = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(with: result)
    }
}
