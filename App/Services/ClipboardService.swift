import AppKit
import PathBridgeCore

@MainActor
enum ClipboardService {
    static func read() throws -> String {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return try choose(urls.map(\.absoluteString))
        }
        guard let text = pasteboard.string(forType: .string) else {
            throw AppError.message("剪贴板中没有路径。请先复制一个完整路径。")
        }
        return try path(in: text)
    }

    static func path(in text: String) throws -> String {
        try choose(ClipboardParser.candidates(in: text))
    }

    private static func choose(_ candidates: [String]) throws -> String {
        guard !candidates.isEmpty else { throw AppError.message("没有识别到完整路径。") }
        if candidates.count == 1 { return candidates[0] }
        let alert = NSAlert()
        alert.messageText = "选择要使用的路径"
        alert.informativeText = "识别到 \(candidates.count) 条路径。请选择一条继续。"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 580, height: 28))
        picker.addItems(withTitles: candidates)
        for (item, path) in zip(picker.itemArray, candidates) { item.toolTip = path }
        alert.accessoryView = picker
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { throw CancellationError() }
        return candidates[picker.indexOfSelectedItem]
    }

    static func write(_ text: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { throw AppError.message("无法写入剪贴板，请重试。") }
    }
}
