import Foundation
import Security

struct PrimaryCredential: Codable, Equatable, Sendable {
    var username: String
    var password: String
}

struct SMBCredential: Codable, Equatable, Sendable {
    var username: String
    var password: String
    var server: String
    var share: String

    func matches(server: String, share: String) -> Bool {
        self.server.caseInsensitiveCompare(server) == .orderedSame &&
        self.share.caseInsensitiveCompare(share) == .orderedSame
    }
}

enum CredentialStore {
    private static let service = "com.yuna.PathBridge.smb"

    static func read(storageID: String) throws -> SMBCredential? {
        guard let data = try readData(base(storageID)) else { return nil }
        return try JSONDecoder().decode(SMBCredential.self, from: data)
    }

    static func readPrimary() throws -> PrimaryCredential? {
        guard let data = try readData(primaryQuery) else { return nil }
        return try JSONDecoder().decode(PrimaryCredential.self, from: data)
    }

    static func savePrimary(_ credential: PrimaryCredential?) throws {
        try saveData(credential.map { try JSONEncoder().encode($0) }, username: credential?.username,
            label: "PathBridge SMB 主凭据", query: primaryQuery)
    }

    /// 映射专属凭据仅在端点匹配时使用；否则使用用户明确保存的主凭据。
    static func connectionCredential(storageID: String?, server: String, share: String) throws -> SMBCredential? {
        if let storageID, let saved = try read(storageID: storageID), saved.matches(server: server, share: share) {
            return saved
        }
        guard let primary = try readPrimary() else { return nil }
        return SMBCredential(username: primary.username, password: primary.password, server: server, share: share)
    }

    private static var primaryQuery: [CFString: Any] {
        // 使用独立 service，避免任何 Storage ID 与主凭据发生键冲突。
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service + ".primary", kSecAttrAccount: "primary"]
    }

    private static func readData(_ baseQuery: [CFString: Any]) throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw AppError.message("钥匙串凭据格式无效。") }
        return data
    }

    static func save(_ credential: SMBCredential?, storageID: String) throws {
        try saveData(credential.map { try JSONEncoder().encode($0) }, username: credential?.username,
            label: "PathBridge SMB · \(credential?.username ?? "")", query: base(storageID))
    }

    private static func saveData(_ data: Data?, username: String?, label: String, query: [CFString: Any]) throws {
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        guard let username, !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AppError.message("保存凭据时需要填写账号。")
        }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrLabel] = label
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }

    private static func base(_ id: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: id]
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "错误 \(status)"
            throw AppError.message("无法访问 PathBridge 钥匙串凭据：\(reason)")
        }
    }
}
