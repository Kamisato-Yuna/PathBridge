import Foundation

/// A configured storage location shared by Windows and macOS.
public struct StorageMapping: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var windowsDrive: String?
    public var server: String
    public var share: String
    /// A relative directory inside ``share`` used as this Storage's root.
    public var subpath: String
    public var mountPath: String

    public init(
        id: String = UUID().uuidString,
        name: String,
        windowsDrive: String? = nil,
        server: String,
        share: String,
        mountPath: String,
        subpath: String = ""
    ) {
        self.id = id
        self.name = name
        self.windowsDrive = windowsDrive
        self.server = server
        self.share = share
        self.mountPath = mountPath
        self.subpath = subpath
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, windowsDrive, server, share, subpath, mountPath
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try values.decode(String.self, forKey: .id)
        self.name = try values.decode(String.self, forKey: .name)
        self.windowsDrive = try values.decodeIfPresent(String.self, forKey: .windowsDrive)
        self.server = try values.decode(String.self, forKey: .server)
        self.share = try values.decode(String.self, forKey: .share)
        self.subpath = try values.decodeIfPresent(String.self, forKey: .subpath) ?? ""
        self.mountPath = try values.decode(String.self, forKey: .mountPath)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(windowsDrive, forKey: .windowsDrive)
        try values.encode(server, forKey: .server)
        try values.encode(share, forKey: .share)
        try values.encode(subpath, forKey: .subpath)
        try values.encode(mountPath, forKey: .mountPath)
    }
}

/// The format used when a resolved storage-relative path is rendered.
public enum PathFormat: Equatable, Sendable {
    case macOS
    case windowsDrive
    case unc
    case storage
    case smb
}

/// A path relative to one of the configured storages.
public struct ResolvedPath: Equatable, Sendable {
    public var storageID: String
    public var components: [String]

    public init(storageID: String, components: [String]) {
        self.storageID = storageID
        self.components = components
    }
}

/// Errors produced while validating mappings or converting paths.
public enum PathResolverError: Error, Equatable, LocalizedError, Sendable {
    case emptyInput
    case invalidClipboardText
    case malformedPath
    case unsupportedPathFormat
    case invalidURL
    case invalidMapping(String)
    case duplicateMapping(String)
    case mappingNotFound(String)
    case pathTraversal
    case invalidComponent(String)
    case invalidWindowsComponent(String)
    case missingWindowsDrive(String)
    case invalidResolvedPath
    case networkLocationUnknown

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "路径为空。"
        case .invalidClipboardText:
            return "剪贴板内容不是一个完整路径。"
        case .malformedPath:
            return "路径格式无效。"
        case .unsupportedPathFormat:
            return "不支持的路径格式。"
        case .invalidURL:
            return "URL 格式无效。"
        case let .invalidMapping(reason):
            return "Storage 映射无效：\(reason)"
        case let .duplicateMapping(reason):
            return "Storage 映射重复：\(reason)"
        case let .mappingNotFound(value):
            return "找不到对应的 Storage 映射：\(value)"
        case .pathTraversal:
            return "路径不能包含 .. 或其他目录穿越。"
        case let .invalidComponent(component):
            return "路径组件无效：\(component)"
        case let .invalidWindowsComponent(component):
            return "路径组件不能表示为 Windows 路径：\(component)"
        case let .missingWindowsDrive(storageID):
            return "Storage \(storageID) 没有配置 Windows 盘符。"
        case .invalidResolvedPath:
            return "ResolvedPath 无效。"
        case .networkLocationUnknown:
            return "无法从此路径确定 SMB 服务器与共享。请配置盘符映射，或复制完整 UNC 路径（\\\\服务器\\共享\\路径）。"
        }
    }
}
