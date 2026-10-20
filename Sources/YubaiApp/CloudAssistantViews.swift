import SwiftUI
import YubaiCore

struct CloudAISettingsSection: View {
    @State private var key = ""
    @State private var configured = APIKeyStore.shared.isConfigured
    @State private var status = ""
    @State private var testing = false
    var body: some View {
        Section("DeepSeek 密钥") {
            Text(configured ? "已配置" : "未配置").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            SecureField("DeepSeek API 密钥", text: $key).autocorrectionDisabled().privacySensitive()
            Button("保存或替换密钥") { saveKey() }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("删除密钥", role: .destructive) { deleteKey() }
            Text("密钥仅保存在本机钥匙串，不进入账本或备份。删除后，开发环境仍可使用环境变量中的密钥。")
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            Button(testing ? "正在连接…" : "测试连接") { testConnection() }.disabled(!configured || testing)
            if !status.isEmpty { Text(status).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted) }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            .onAppear { configured = APIKeyStore.shared.isConfigured }
            .onDisappear { key = "" }
    }
    @MainActor private func saveKey() {
        do { try APIKeyStore.shared.save(key); key = ""; configured = APIKeyStore.shared.isConfigured; IntelligenceRuntime.cloud.refresh(); status = "密钥已保存。" }
        catch { status = error.localizedDescription }
    }
    @MainActor private func deleteKey() {
        do { try APIKeyStore.shared.delete(); key = ""; configured = APIKeyStore.shared.isConfigured; IntelligenceRuntime.cloud.refresh(); status = "钥匙串中的密钥已删除。" }
        catch { status = error.localizedDescription }
    }
    @MainActor private func testConnection() {
        guard let client = DeepSeekClient.configured() else { configured = false; return }
        testing = true; status = ""
        Task {
            defer { testing = false }
            do {
                _ = try await client.chat(system: "请只回复：连接正常。", user: "你好", maxTokens: 16, purpose: "测试连接")
                IntelligenceRuntime.cloud.succeeded(model: client.configuration.model)
                status = "连接正常。"
            } catch { IntelligenceRuntime.cloud.failed(error, model: client.configuration.model); status = error.localizedDescription }
        }
    }
}

struct CloudModelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = IntelligenceRuntime.cloud.model
    @State private var errorText = ""
    var body: some View {
        Form {
            Section("模型") {
                TextField("模型名字", text: $name).autocorrectionDisabled().accessibilityIdentifier("cloudModelName")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                if !errorText.isEmpty { Text(errorText).foregroundStyle(YubaiColor.amberInk) }
            }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("模型").yubaiNavigation().toolbar {
            Button("保存") {
                do { try IntelligenceRuntime.cloud.saveModel(name); dismiss() }
                catch { errorText = error.localizedDescription }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveCloudModel")
        }
    }
}

struct ModelUnavailableNote: View {
    let model: String
    var body: some View {
        (Text("模型「\(model)」现在用不了。").foregroundColor(YubaiColor.amberInk).fontWeight(.medium)
         + Text("DeepSeek 可能改名或下线了它。问余白和整理先停下，账本和计算不受影响。点「模型」换一个名字再试。"))
            .yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, YubaiSpace.space12).padding(.horizontal, YubaiSpace.space16)
            .background(YubaiColor.amberTint, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            .accessibilityIdentifier("modelUnavailable")
    }
}

struct CloudSendLogView: View {
    @State private var items: [SendLogItem] = []
    var body: some View {
        Page {
            Text("仅保留本次打开应用期间最近 50 次发送。正文已脱敏，每条最多显示约 4 KB。")
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            if items.isEmpty { Card { Text("还没有发送记录。").yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted) } }
            ForEach(items) { item in
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                        Text(item.purpose).yubaiFont(YubaiFont.rowTitle)
                        Text("\(Dates.text(item.time, time: true)) · \(item.model) · \(item.byteSize) 字节")
                            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        Text(item.requestText).yubaiFont(YubaiFont.caption).textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("发给云端的内容").yubaiNavigation().onAppear { items = SendLog.shared.items }
            .toolbar { Button("刷新") { items = SendLog.shared.items } }
    }
}
