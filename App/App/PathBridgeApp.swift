import SwiftUI

@main
struct PathBridgeApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra("PathBridge", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            MenuBarView(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("关于 PathBridge", id: "about") {
            VStack(spacing: 14) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 44)).foregroundStyle(.tint)
                Text("PathBridge").font(.title.bold())
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知")")
                Text("让路径跨越系统").foregroundStyle(.secondary)
                Link("GitHub · Kamisato-Yuna/PathBridge",
                     destination: URL(string: "https://github.com/Kamisato-Yuna/PathBridge")!)
                Link("MIT License", destination: URL(string: "https://github.com/Kamisato-Yuna/PathBridge/blob/main/LICENSE")!)
                Text("Copyright © 2026 Yuna Kamisato").font(.caption).foregroundStyle(.secondary)
            }
            .padding(32).frame(width: 380)
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
