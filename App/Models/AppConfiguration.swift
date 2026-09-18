import Foundation
import PathBridgeCore

struct HotkeyConfiguration: Codable, Equatable, Sendable {
    var key = "O"
    var command = true
    var option = true
    var control = false
    var shift = false

    var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key
    }
}

struct AppConfiguration: Codable, Equatable, Sendable {
    var version = 1
    var storages: [StorageMapping] = []
    var hotkey = HotkeyConfiguration()

    func validate() throws {
        guard version == 1 else { throw AppError.message("不支持此配置版本：\(version)。") }
        try MappingValidator.validate(storages)
        guard HotkeyManager.keyCodes[hotkey.key] != nil,
              hotkey.command || hotkey.option || hotkey.control else {
            throw AppError.message("快捷键需要 ⌘、⌥ 或 ⌃ 中的至少一个修饰键，以及一个字母或数字。")
        }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}
