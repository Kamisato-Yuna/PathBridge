import SwiftUI
import UniformTypeIdentifiers
import PathBridgeCore

struct SettingsView: View {
    let state: AppState
    @State private var importPresented = false
    @State private var exportPresented = false
    @State private var pendingImport: AppConfiguration?
    @State private var showImportConfirmation = false

    var body: some View {
        TabView {
            StorageSettingsView(state: state)
                .tabItem { Label("存储映射", systemImage: "externaldrive") }
            ConverterView(state: state)
                .tabItem { Label("路径转换", systemImage: "arrow.left.arrow.right") }
            GeneralSettingsView(state: state)
                .tabItem { Label("通用", systemImage: "gearshape") }
            PrimaryCredentialSettingsView()
                .tabItem { Label("主凭据", systemImage: "key") }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 540)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("PathBridge 1.0 · 配置中不包含密码").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("导入配置…") { importPresented = true }
                Button("导出配置…") { exportPresented = true }
            }.padding(.horizontal, 24).padding(.bottom, 16)
        }
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try SettingsStore.decode(Data(contentsOf: url))
                showImportConfirmation = true
            } catch { state.report(error) }
        }
        .fileExporter(isPresented: $exportPresented, document: ConfigurationDocument(configuration: state.settings.configuration), contentType: .json, defaultFilename: "PathBridge-config") { result in
            if case .failure(let error) = result { state.report(error) }
        }
        .confirmationDialog("替换当前配置？", isPresented: $showImportConfirmation, titleVisibility: .visible) {
            Button("替换配置") {
                guard let pendingImport else { return }
                do { try state.save(pendingImport) } catch { state.report(error) }
                self.pendingImport = nil
            }
        } message: {
            Text("将导入 \(pendingImport?.storages.count ?? 0) 个 Storage 和快捷键设置。密码不会导入；现有钥匙串凭据仅在 Storage ID 和服务器、共享均匹配时使用。")
        }
        .task {
            while !Task.isCancelled {
                await state.refresh()
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }
}

struct ConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var configuration: AppConfiguration

    init(configuration: AppConfiguration) { self.configuration = configuration }
    init(configuration: ReadConfiguration) throws {
        self.configuration = try SettingsStore.decode(configuration.file.regularFileContents ?? Data())
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try SettingsStore.encode(self.configuration))
    }
}
