import SwiftUI
import PathBridgeCore

struct AboutView: View {
    @Bindable var checker: UpdateChecker

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("PathBridge")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("让路径跨越系统")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("版本 \(UpdateChecker.currentVersion)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            HStack(spacing: 12) {
                Link(destination: ReleaseUpdate.repositoryURL) {
                    Label("GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .help("在浏览器中打开 PathBridge 仓库")
                Link(destination: ReleaseUpdate.repositoryURL.appendingPathComponent("blob/main/LICENSE")) {
                    Label("MIT 许可", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .help("查看 MIT 开源许可")
            }
            .buttonStyle(.bordered).controlSize(.large)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("软件更新", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(checker.isChecking ? "检查中…" : "检查更新") {
                        Task { await checker.check() }
                    }
                    .disabled(checker.isChecking)
                }
                Toggle(isOn: $checker.automaticallyChecks) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("自动检查更新").font(.subheadline)
                        Text("每天检查一次").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch).controlSize(.small)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if checker.isChecking { ProgressView().controlSize(.mini) }
                        Text(checker.isChecking ? "正在获取最新版本…" : checker.message)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let update = checker.available {
                        Link("下载 \(update.version) ↗", destination: update.url)
                            .font(.subheadline.weight(.medium))
                    }
                    if let date = checker.lastChecked {
                        Text("上次检查 · \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

            Text("© 2026 Yuna Kamisato")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28).padding(.vertical, 28)
        .frame(width: 400)
    }
}
