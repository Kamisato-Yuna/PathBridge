import SwiftUI

@main
struct PathBridgeApp: App {
    @NSApplicationDelegateAdaptor(PathBridgeAppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("PathBridge", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            MenuBarView(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("关于 PathBridge", id: "about") {
            AboutView(checker: state.updates)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("PathBridge 设置", id: "settings") {
            SettingsView(state: state)
        }
        .defaultSize(width: 820, height: 590)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
