import SwiftUI
import PathBridgeCore

struct UpdateSettingsView: View {
    @Bindable var checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("自动检查更新（每天一次）", isOn: $checker.automaticallyChecks)
            HStack {
                Button(checker.isChecking ? "正在检查…" : "检查更新") {
                    Task { await checker.check() }
                }.disabled(checker.isChecking)
                if checker.isChecking { ProgressView().controlSize(.small) }
                if let update = checker.available {
                    Link("下载 \(update.version)", destination: update.url)
                }
            }
            Text(checker.message).font(.caption).foregroundStyle(.secondary)
            if let date = checker.lastChecked {
                Text("上次成功检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("从 GitHub Releases 检查正式版本；不发送路径或凭据。下载后由你手动安装。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
