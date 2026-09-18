import AppKit
import PathBridgeCore

@MainActor
final class PathBridgeAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do { AppState.shared.handleFinderCommand(try FinderCommand(url: url)) }
            catch { AppState.shared.report(error) }
        }
    }
}
