import Foundation
import Observation

@MainActor @Observable
final class SettingsStore {
    private(set) var configuration = AppConfiguration()
    private(set) var loadError: String?
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PathBridge/configuration.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let loaded = try Self.decode(Data(contentsOf: self.fileURL))
            configuration = loaded
        } catch {
            loadError = "无法读取配置，原文件已保留：\(error.localizedDescription)"
        }
    }

    nonisolated static func decode(_ data: Data) throws -> AppConfiguration {
        let result = try JSONDecoder().decode(AppConfiguration.self, from: data)
        try result.validate()
        return result
    }

    nonisolated static func encode(_ configuration: AppConfiguration) throws -> Data {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(configuration)
    }

    func save(_ configuration: AppConfiguration) throws {
        let data = try Self.encode(configuration)
        // Do not silently overwrite a malformed existing configuration.
        guard loadError == nil else {
            throw AppError.message("请先在 Finder 中备份或移走损坏的配置，再重新启动 PathBridge。\n\(fileURL.path)")
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        self.configuration = configuration
    }
}
