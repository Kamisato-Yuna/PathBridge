import AppKit
import PathBridgeCore

@MainActor
enum ClipboardService {
    static func read() throws -> String {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard urls.count == 1 else { throw AppError.message("请一次复制一个文件或文件夹。") }
            return urls[0].absoluteString
        }
        guard let text = pasteboard.string(forType: .string) else {
            throw AppError.message("剪贴板中没有路径。请先复制一个完整路径。")
        }
        return try ClipboardParser.parse(text)
    }

    static func write(_ text: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { throw AppError.message("无法写入剪贴板，请重试。") }
    }
}
