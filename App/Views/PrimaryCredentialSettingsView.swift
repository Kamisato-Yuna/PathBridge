import SwiftUI

struct PrimaryCredentialSettingsView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var hasSavedCredential = false
    @State private var loaded = false
    @State private var message: String?
    @State private var errorText: String?
    @State private var deleting = false

    var body: some View {
        Form {
            Section("SMB 主凭据") {
                Text("没有保存映射专属凭据时，优先使用主凭据连接 SMB。未配置映射的 UNC / SMB 路径也会使用它。")
                    .foregroundStyle(.secondary)
                TextField("账号", text: $username, prompt: Text("DOMAIN\\username"))
                    .textContentType(.username)
                SecureField("密码", text: $password).textContentType(.password)
                HStack {
                    Label(hasSavedCredential ? "主凭据已保存" : "尚未保存主凭据", systemImage: hasSavedCredential ? "key.fill" : "key")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("删除主凭据", role: .destructive) { deleting = true }
                        .disabled(!loaded || !hasSavedCredential)
                    Button("保存主凭据", action: save)
                        .disabled(!loaded || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if let errorText { Text(errorText).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section("使用顺序") {
                Text("映射专属凭据 → 主凭据 → macOS 系统认证")
                Text("账号和密码仅保存在此 Mac 的钥匙串中，不写入 SMB 地址，不随 JSON 导入导出。已有 SMB 挂载会继续复用，更换凭据不会主动断开共享。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .textFieldStyle(.roundedBorder)
        .onAppear(perform: load)
        .onDisappear { password = "" }
        .confirmationDialog("删除主凭据？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                do {
                    try CredentialStore.savePrimary(nil)
                    username = ""; password = ""; hasSavedCredential = false
                    message = "主凭据已删除。无专属凭据时由系统请求认证。"
                    errorText = nil
                } catch { errorText = error.localizedDescription }
            }
        }
    }

    private func load() {
        do {
            let credential = try CredentialStore.readPrimary()
            username = credential?.username ?? ""
            password = credential?.password ?? ""
            hasSavedCredential = credential != nil
            loaded = true
            errorText = nil
        } catch { errorText = error.localizedDescription; loaded = false }
    }

    private func save() {
        do {
            try CredentialStore.savePrimary(PrimaryCredential(username: username.trimmingCharacters(in: .whitespaces), password: password))
            hasSavedCredential = true
            message = "主凭据已保存至钥匙串。"
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }
}
