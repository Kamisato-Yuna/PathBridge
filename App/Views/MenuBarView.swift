import SwiftUI
import PathBridgeCore

struct MenuBarView: View {
    let state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PathBridge").font(.headline)
                    Text("让路径跨越系统").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if state.isOpening { ProgressView().controlSize(.small) }
            }
            Divider()
            Button { state.openClipboard() } label: {
                HStack {
                    Label("打开剪贴板路径", systemImage: "folder")
                    Spacer()
                    Text(state.settings.configuration.hotkey.label).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(state.isOpening)

            HStack {
                copyButton("macOS", format: .macOS)
                copyButton("Windows", format: .windowsDrive)
                copyButton("UNC", format: .unc)
            }
            .disabled(state.settings.configuration.storages.isEmpty)
            Text("从剪贴板转换并复制；Windows 优先盘符").font(.caption2).foregroundStyle(.secondary)

            Divider()
            HStack {
                Text("存储位置").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await state.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新挂载状态")
            }
            if state.settings.configuration.storages.isEmpty {
                Text("尚未添加映射。完整 UNC / SMB 路径可直接打开。").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(state.settings.configuration.storages) { mapping in
                            HStack {
                                Image(systemName: "externaldrive.connected.to.line.below")
                                Text(mapping.name).lineLimit(1)
                                Spacer()
                                let connecting = state.volumes.connectingStorageID == mapping.id
                                let mounted = state.volumes.mountPath(for: mapping) != nil
                                Circle().fill(connecting ? Color.orange : mounted ? .green : .secondary).frame(width: 6, height: 6)
                                Text(connecting ? "连接中" : mounted ? "已挂载" : "未挂载")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxHeight: 150)
            }
            if state.volumes.connectingServer != nil {
                Button("取消连接") { state.volumes.cancelMount() }
            }
            Text(state.hotkeyError ?? state.status)
                .font(.caption).foregroundStyle(state.hotkeyError == nil ? Color.secondary : .orange)
                .lineLimit(3).textSelection(.enabled)
            Divider()
            HStack {
                Button("设置…", systemImage: "gearshape") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }.keyboardShortcut(",")
                Button("关于") {
                    openWindow(id: "about")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.plain)
        }
        .padding(18).frame(width: 350)
        .task {
            while !Task.isCancelled {
                await state.refresh()
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }

    private func copyButton(_ title: String, format: PathFormat) -> some View {
        Button { state.copy(format) } label: {
            Label(title, systemImage: "doc.on.doc").frame(maxWidth: .infinity)
        }.help("复制 \(title) 路径")
    }
}
