import SwiftUI
import PathBridgeCore

struct StorageEditor: View {
    let state: AppState
    @State var mapping: StorageMapping
    @Environment(\.dismiss) private var dismiss
    @State private var drive = ""
    @State private var saveCredential = false
    @State private var username = ""
    @State private var password = ""
    @State private var originalCredential: SMBCredential?
    @State private var credentialLoaded = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("存储映射").font(.title2.bold())
            Form {
                TextField("名称", text: $mapping.name, prompt: Text("例如：渲染输出"))
                TextField("Windows 盘符（可选）", text: $drive, prompt: Text("R:"))
                TextField("SMB 服务器", text: $mapping.server, prompt: Text("server.example.com"))
                TextField("共享名称", text: $mapping.share, prompt: Text("share"))
                TextField("共享内子目录（可选）", text: $mapping.subpath, prompt: Text("RenderOutput"))
                TextField("macOS 映射根目录", text: $mapping.mountPath, prompt: Text("/Volumes/share/RenderOutput"))
                Button("根据共享生成 macOS 路径") {
                    mapping.mountPath = "/Volumes/" + mapping.share + (mapping.subpath.isEmpty ? "" : "/" + mapping.subpath.replacingOccurrences(of: "\\", with: "/"))
                }
                Divider()
                Toggle("将账号凭据保存在钥匙串", isOn: $saveCredential)
                if saveCredential {
                    TextField("账号", text: $username, prompt: Text("DOMAIN\\username"))
                        .textContentType(.username)
                    SecureField("密码", text: $password).textContentType(.password)
                }
            }
            .textFieldStyle(.roundedBorder)
            Text("未保存专属凭据时使用主凭据；主凭据也未保存时由 macOS 请求认证。密码仅存于本机钥匙串，不随配置导出。更换服务器或共享后需重新填写专属凭据。").font(.caption).foregroundStyle(.secondary)
            if let errorText { Text(errorText).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction).disabled(!credentialLoaded)
            }
        }
        .padding(24).frame(width: 570)
        .onAppear {
            drive = mapping.windowsDrive ?? ""
            do {
                originalCredential = try CredentialStore.read(storageID: mapping.id)
                if let originalCredential, originalCredential.matches(server: mapping.server, share: mapping.share) {
                    saveCredential = true
                    username = originalCredential.username
                    password = originalCredential.password
                }
                credentialLoaded = true
            } catch { errorText = error.localizedDescription }
        }
        .onChange(of: mapping.server) { _, _ in clearCredentialsForChangedServer() }
        .onChange(of: mapping.share) { _, _ in clearCredentialsForChangedServer() }
    }

    private func clearCredentialsForChangedServer() {
        guard let originalCredential,
              !originalCredential.matches(server: mapping.server, share: mapping.share) else { return }
        saveCredential = false
        username = ""
        password = ""
    }

    private func save() {
        do {
            mapping.name = mapping.name.trimmingCharacters(in: .whitespaces)
            mapping.server = mapping.server.trimmingCharacters(in: .whitespaces)
            mapping.share = mapping.share.trimmingCharacters(in: .whitespaces)
            mapping.subpath = mapping.subpath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let letter = drive.trimmingCharacters(in: .whitespaces).uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ":/\\"))
            mapping.windowsDrive = letter.isEmpty ? nil : letter + ":"
            var configuration = state.settings.configuration
            if let index = configuration.storages.firstIndex(where: { $0.id == mapping.id }) {
                configuration.storages[index] = mapping
            } else { configuration.storages.append(mapping) }
            try configuration.validate()
            let credential = saveCredential ? SMBCredential(username: username, password: password, server: mapping.server, share: mapping.share) : nil
            if credential != originalCredential { try CredentialStore.save(credential, storageID: mapping.id) }
            do { try state.save(configuration) }
            catch {
                if credential != originalCredential {
                    do { try CredentialStore.save(originalCredential, storageID: mapping.id) }
                    catch { throw AppError.message("配置未保存，凭据恢复失败，请重新编辑凭据：\(error.localizedDescription)") }
                }
                throw error
            }
            password = ""
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}
