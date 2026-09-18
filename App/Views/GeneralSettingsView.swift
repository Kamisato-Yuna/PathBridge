import SwiftUI
import ServiceManagement
import FinderSync

struct GeneralSettingsView: View {
    let state: AppState
    @State private var shortcut = HotkeyConfiguration()
    @State private var savedMessage: String?
    @State private var finderEnabled = FIFinderSyncController.isExtensionEnabled

    var body: some View {
        Form {
            Section("剪贴板快捷打开") {
                HStack {
                    Toggle("⌃ Control", isOn: $shortcut.control)
                    Toggle("⌥ Option", isOn: $shortcut.option)
                    Toggle("⇧ Shift", isOn: $shortcut.shift)
                    Toggle("⌘ Command", isOn: $shortcut.command)
                }.toggleStyle(.checkbox)
                Picker("按键", selection: $shortcut.key) {
                    ForEach(HotkeyManager.keyCodes.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(width: 200)
                HStack {
                    Text(shortcut.label).font(.system(.title3, design: .monospaced))
                    Spacer()
                    Button("恢复默认") { shortcut = HotkeyConfiguration() }
                    Button("保存快捷键") {
                        do {
                            var configuration = state.settings.configuration
                            configuration.hotkey = shortcut
                            try state.save(configuration)
                            savedMessage = "快捷键已更新"
                        } catch { state.report(error) }
                    }
                }
                Text("字母按键使用键盘物理键位，无需辅助功能权限。快捷键冲突时会提示，并保留原设置。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = state.hotkeyError ?? savedMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            Section("启动") {
                Toggle("登录时启动 PathBridge", isOn: Binding(
                    get: { state.loginStatus == .enabled || state.loginStatus == .requiresApproval },
                    set: { state.setLaunchAtLogin($0) }
                ))
                if state.loginStatus == .requiresApproval {
                    Text("需要在系统设置中允许登录项。").foregroundStyle(.orange)
                    Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("建议将签名后的应用放入“应用程序”后再启用。应用仅常驻菜单栏，不显示 Dock 图标。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Finder 扩展") {
                Label(finderEnabled ? "已启用" : "尚未启用", systemImage: finderEnabled ? "checkmark.circle.fill" : "info.circle")
                Text("在 /Volumes 下的文件或目录上右键，使用 PathBridge 复制 macOS、Windows、UNC 或 SMB 路径。支持多选批量复制。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("管理 Finder 扩展") { FIFinderSyncController.showExtensionManagementInterface() }
            }
            Section("软件更新") {
                UpdateSettingsView(checker: state.updates)
            }
            Section("配置文件") {
                Text(state.settings.fileURL.path).font(.caption).textSelection(.enabled)
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([state.settings.fileURL]) }
                if let error = state.settings.loadError { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onAppear { shortcut = state.settings.configuration.hotkey }
        .onChange(of: state.settings.configuration.hotkey) { _, newValue in shortcut = newValue }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            finderEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}
