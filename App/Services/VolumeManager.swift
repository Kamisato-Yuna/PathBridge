import AppKit
import NetFS
import Observation
import PathBridgeCore
import Darwin

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
        // 仅查看内核挂载表；状态刷新不探测网络宗卷内容或请求重新挂载信息。
        // 真正打开文件时仍由 macOS 执行网络宗卷访问授权。
        if let snapshot = try? await Task.detached(priority: .utility, operation: {
            try SMBMountSnapshot.read()
        }).value {
            mounted = snapshot
        }
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
        do {
            try await connect(server: server, share: share, storageID: nil, credential: credential)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
            // 域名/IP 别名可能指向同一个现有挂载。继续由默认浏览器处理原始 SMB URL，
            // 不猜测本地目录，也不为切换账号而断开现有共享。
            return
        }
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

/// 读取已有挂载的元数据，不访问远程目录，也不将挂载源中的账号带入应用状态。
enum SMBMountSnapshot {
    static func read() throws -> [MountedShare] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count >= 0 else { throw currentError() }
        let stride = MemoryLayout<statfs>.stride
        var capacity = max(Int(count) + 8, 16)
        for attempt in 0..<3 {
            guard capacity <= Int(Int32.max) / stride else { throw POSIXError(.ENOMEM) }
            var entries = Array<statfs>(repeating: statfs(), count: capacity)
            let filled = entries.withUnsafeMutableBufferPointer { buffer in
                getfsstat(buffer.baseAddress, Int32(capacity * stride), MNT_NOWAIT)
            }
            guard filled >= 0 else { throw currentError() }
            // 查询数量和读取表之间可能出现新挂载，预留空间不足时重新读取。
            if Int(filled) >= capacity {
                guard attempt < 2 else { throw POSIXError(.EAGAIN) }
                capacity *= 2
                continue
            }
            return entries.prefix(Int(filled)).compactMap { entry -> MountedShare? in
                guard cString(entry.f_fstypename) == "smbfs",
                      let source = cString(entry.f_mntfromname),
                      let path = cString(entry.f_mntonname) else { return nil }
                return parse(source: source, mountPath: path)
            }
        }
        throw POSIXError(.EAGAIN)
    }

    static func parse(source: String, mountPath: String) -> MountedShare? {
        guard source.hasPrefix("//"), mountPath.hasPrefix("/") else { return nil }
        let body = source.dropFirst(2)
        guard let slash = body.firstIndex(of: "/") else { return nil }
        let authority = body[..<slash]
        // userinfo 可能含域名、密码或编码后的 @；先去掉原始 authority 中的全部凭据。
        let hostStart = authority.lastIndex(of: "@").map { authority.index(after: $0) } ?? authority.startIndex
        let rawHost = authority[hostStart...]
        let encodedPath = body[body.index(after: slash)...]
        var pieces = encodedPath.split(separator: "/", omittingEmptySubsequences: false)
        if pieces.last?.isEmpty == true { pieces.removeLast() }
        // 子目录挂载不能假定为共享根，否则会将用户路径指向错误目录。
        guard pieces.count == 1,
              let server = String(rawHost).removingPercentEncoding, !server.isEmpty,
              let share = String(pieces[0]).removingPercentEncoding, !share.isEmpty,
              share != ".", share != "..",
              !server.contains(where: { "/\\@?#".contains($0) }),
              !share.contains(where: { "/\\".contains($0) }),
              !server.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !share.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        // f_mntonname 是实际本地路径，不能再执行 URL 解码。
        return MountedShare(server: server, share: share, path: mountPath)
    }

    private static func cString<T>(_ value: T) -> String? {
        withUnsafeBytes(of: value) { bytes in
            guard let end = bytes.firstIndex(of: 0) else { return nil }
            return String(bytes: bytes[..<end], encoding: .utf8)
        }
    }

    private static func currentError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
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
        else if status == EEXIST {
            complete(.failure(NSError(domain: NSPOSIXErrorDomain, code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "系统报告共享已挂载。请确认是否通过另一服务器名称连接。"])))
        }
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
