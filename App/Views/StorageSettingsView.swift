import SwiftUI
import PathBridgeCore

struct StorageSettingsView: View {
    let state: AppState
    @State private var selectedID: String?
    @State private var editing: StorageMapping?
    @State private var deleting = false

    private var selected: StorageMapping? {
        state.settings.configuration.storages.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(state.settings.configuration.storages, selection: $selectedID) { mapping in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mapping.name).lineLimit(1)
                            Text(mapping.windowsDrive ?? "UNC").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "externaldrive") }
                    .tag(mapping.id)
                    .contextMenu { Button("编辑…") { editing = mapping } }
                }
                Divider()
                HStack {
                    Button { editing = StorageMapping(name: "", server: "", share: "", mountPath: "/Volumes/") } label: { Image(systemName: "plus") }.help("添加存储映射")
                    Button { deleting = true } label: { Image(systemName: "minus") }.disabled(selected == nil).help("删除存储映射及凭据")
                    Spacer()
                }.padding(10)
            }.frame(minWidth: 190, idealWidth: 210, maxWidth: 260)
            Group {
                if let selected {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "externaldrive.connected.to.line.below").font(.largeTitle).foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(selected.name).font(.title2.bold())
                                Text(state.volumes.mountPath(for: selected) == nil ? "SMB 未挂载 · 打开路径时自动连接" : "SMB 已挂载")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) {
                            row("Windows", selected.windowsDrive.map { $0 + "\\" } ?? "未指定盘符，使用 UNC")
                            row("UNC", "\\\\\(selected.server)\\\(selected.share)" + (selected.subpath.isEmpty ? "" : "\\" + selected.subpath.replacingOccurrences(of: "/", with: "\\")))
                            row("macOS", selected.mountPath)
                            if let actual = state.volumes.mountPath(for: selected), actual != selected.mountPath { row("实际位置", actual) }
                        }
                        Text("文件在 Finder 中定位，目录直接打开。仅在需要时读取剪贴板。").font(.callout).foregroundStyle(.secondary)
                        Button("编辑映射与凭据…") { editing = selected }
                        Spacer()
                    }.padding(24)
                } else {
                    ContentUnavailableView {
                        Label("连接你的存储位置", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    } description: {
                        Text("添加 Windows 盘符、SMB 共享和 macOS 路径之间的映射。也可以只映射共享内的某个目录。")
                    } actions: {
                        Button("添加映射") { editing = StorageMapping(name: "", server: "", share: "", mountPath: "/Volumes/") }
                    }
                }
            }.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editing) { mapping in StorageEditor(state: state, mapping: mapping) }
        .onAppear { if selectedID == nil { selectedID = state.settings.configuration.storages.first?.id } }
        .confirmationDialog("删除映射及其保存的账号凭据？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                guard let selected else { return }
                do {
                    var configuration = state.settings.configuration
                    configuration.storages.removeAll { $0.id == selected.id }
                    let oldCredential = try CredentialStore.read(storageID: selected.id)
                    try CredentialStore.save(nil, storageID: selected.id)
                    do { try state.save(configuration) }
                    catch {
                        try CredentialStore.save(oldCredential, storageID: selected.id)
                        throw error
                    }
                    selectedID = nil
                } catch { state.report(error) }
            }
        } message: { Text("不会删除网络文件，也不会卸载共享。") }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
