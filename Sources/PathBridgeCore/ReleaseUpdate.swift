import Foundation

/// Release 标签使用 vMAJOR.MINOR.PATCH 或 MAJOR.MINOR.PATCH；仅检查稳定版本。
public struct ReleaseVersion: Comparable, Sendable {
    private let components: [Int]

    public init?(_ value: String) {
        let version = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0", let number = Int(part) else { return nil }
            numbers.append(number)
        }
        components = numbers
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct ReleaseUpdate: Equatable, Sendable {
    public let version: String
    public let url: URL

    public static let repositoryURL = URL(string: "https://github.com/Kamisato-Yuna/PathBridge")!
    public static let releasesURL = repositoryURL.appendingPathComponent("releases")
    public static let endpoint = URL(string: "https://api.github.com/repos/Kamisato-Yuna/PathBridge/releases/latest")!

    /// nil 表示尚无正式 Release，或远端版本不高于本地版本。
    public static func evaluate(data: Data, statusCode: Int, currentVersion: String) throws -> ReleaseUpdate? {
        guard let current = ReleaseVersion(currentVersion) else { throw UpdateError.invalidCurrentVersion }
        if statusCode == 404 { return nil }
        if statusCode == 403 || statusCode == 429 { throw UpdateError.rateLimited }
        guard statusCode == 200 else { throw UpdateError.http(statusCode) }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        guard let remote = ReleaseVersion(release.tagName) else { throw UpdateError.invalidTag }
        guard remote > current else { return nil }
        // 下载入口只指向本项目的 HTTPS Release 页面。
        guard let url = URL(string: release.htmlURL), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.path.hasPrefix("/Kamisato-Yuna/PathBridge/releases/tag/") else {
            throw UpdateError.invalidURL
        }
        return ReleaseUpdate(version: release.tagName, url: url)
    }

    public static func check(currentVersion: String) async throws -> ReleaseUpdate? {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PathBridge/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        return try evaluate(data: data, statusCode: response.statusCode, currentVersion: currentVersion)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease
    }
}

private enum UpdateError: LocalizedError {
    case invalidCurrentVersion, rateLimited, http(Int), invalidTag, invalidURL, invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion: "无法识别当前应用版本。"
        case .rateLimited: "GitHub 请求受限，请稍后重试。"
        case .http(let code): "检查更新失败（HTTP \(code)）。"
        case .invalidTag: "Release 版本标签应为 v主版本.次版本.修订号。"
        case .invalidURL: "Release 页面地址无效。"
        case .invalidResponse: "GitHub 返回了无效响应。"
        }
    }
}
