import SwiftUI
import PathBridgeCore

struct ConverterView: View {
    let state: AppState
    @State private var input = ""
    @State private var outputs: [(String, String)] = []
    @State private var errorText: String?
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("同一个位置，不同的路径").font(.title2.bold())
            Text("输入路径或含有路径的聊天文本即可预览；多条路径会提示选择，无需连接 SMB。").foregroundStyle(.secondary)
            TextField("O:\\Project\\file.hip 或包含路径的文字", text: $input, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder).onSubmit(convert)
            HStack {
                Button("读取剪贴板") {
                    do { input = try ClipboardService.read(); convert() }
                    catch { errorText = error.localizedDescription }
                }
                Button("转换", action: convert).buttonStyle(.borderedProminent).disabled(input.isEmpty)
                if let copied { Text(copied).font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            ForEach(outputs, id: \.0) { title, value in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("复制") {
                            do { try ClipboardService.write(value); copied = "已复制 \(title)" }
                            catch { errorText = error.localizedDescription }
                        }.buttonStyle(.borderless)
                    }
                    Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
            }
            if let errorText { Text(errorText).foregroundStyle(.red).textSelection(.enabled) }
            Spacer()
        }.padding(24)
    }

    private func convert() {
        outputs = []; errorText = nil; copied = nil
        do { input = try ClipboardService.path(in: input) }
        catch is CancellationError { return }
        catch { errorText = error.localizedDescription; return }
        do {
            let resolved = try state.resolve(input)
            for (name, format) in [("macOS", PathFormat.macOS), ("Windows 盘符", .windowsDrive), ("UNC", .unc), ("Storage", .storage), ("SMB", .smb)] {
                if format == .windowsDrive,
                   state.settings.configuration.storages.first(where: { $0.id == resolved.storageID })?.windowsDrive == nil { continue }
                outputs.append((name, try state.render(resolved, as: format)))
            }
        } catch PathResolverError.mappingNotFound {
            do { outputs = [("SMB（未配置映射）", try state.unmappedSMBURL(input).absoluteString)] }
            catch { errorText = error.localizedDescription }
        } catch { errorText = error.localizedDescription }
    }
}
