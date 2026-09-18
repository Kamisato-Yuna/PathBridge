import Foundation

public enum FinderAction: String, CaseIterable, Sendable {
    case open, copyMacOS, copyWindows, copyUNC, copySMB
}

public enum FinderCommandError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case invalidSelection
    case invalidPath
    case tooLong

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Finder 操作链接无效。"
        case .invalidSelection: return "打开操作请选择一个项目；复制操作请选择 1 至 100 个项目。"
        case .invalidPath: return "Finder 操作只接受 /Volumes 下的完整本地路径，且不能包含目录跳转或控制字符。"
        case .tooLong: return "所选路径过长，请减少选择的项目。"
        }
    }
}

/// Finder 扩展与主应用之间的路径消息，仅负责校验和编码，不访问文件或凭据。
public struct FinderCommand: Sendable, Equatable {
    public let action: FinderAction
    public let paths: [String]

    private static let maximumURLBytes = 128 * 1024

    public init(action: FinderAction, paths: [String]) throws {
        guard (1...100).contains(paths.count), action != .open || paths.count == 1 else {
            throw FinderCommandError.invalidSelection
        }
        // 在创建编码副本前限制输入；编码后的 URL 还会单独检查。
        var bytes = 0
        for path in paths {
            bytes += path.utf8.count
            guard bytes <= Self.maximumURLBytes else { throw FinderCommandError.tooLong }
            try Self.validate(path)
        }
        self.action = action
        self.paths = paths
        _ = try url()
    }

    public init(url: URL) throws {
        guard url.absoluteString.utf8.count <= Self.maximumURLBytes else {
            throw FinderCommandError.tooLong
        }
        guard url.baseURL == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "pathbridge",
              components.percentEncodedHost?.lowercased() == "finder",
              components.percentEncodedPath.isEmpty,
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let items = components.queryItems,
              items.count <= 101 else {
            throw FinderCommandError.invalidURL
        }
        var action: FinderAction?
        var paths: [String] = []
        for item in items {
            guard let value = item.value else { throw FinderCommandError.invalidURL }
            switch item.name {
            case "action":
                guard action == nil, let parsed = FinderAction(rawValue: value) else {
                    throw FinderCommandError.invalidURL
                }
                action = parsed
            case "path": paths.append(value)
            default: throw FinderCommandError.invalidURL
            }
        }
        guard let action else { throw FinderCommandError.invalidURL }
        try self.init(action: action, paths: paths)
    }

    public func url() throws -> URL {
        var components = URLComponents()
        components.scheme = "pathbridge"
        components.host = "finder"
        components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)]
            + paths.map { URLQueryItem(name: "path", value: $0) }
        guard let result = components.url else { throw FinderCommandError.invalidURL }
        guard result.absoluteString.utf8.count <= Self.maximumURLBytes else {
            throw FinderCommandError.tooLong
        }
        return result
    }

    private static func validate(_ path: String) throws {
        guard path.hasPrefix("/Volumes/"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw FinderCommandError.invalidPath
        }
        var parts = path.dropFirst("/Volumes/".count).split(separator: "/", omittingEmptySubsequences: false)
        // Finder 的目录路径可以有末尾斜杠，但中间的空组件不能被静默归一化。
        if parts.last?.isEmpty == true { parts.removeLast() }
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw FinderCommandError.invalidPath
        }
    }
}
