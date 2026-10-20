import SwiftUI
import YubaiCore

struct CloudAISettingsSection: View {
    @Environment(AppStore.self) private var store
    @State private var key = ""
    @State private var configured = APIKeyStore.shared.isConfigured
    @State private var status = ""
    @State private var testing = false
    var body: some View {
        Section("智能辅助") {
            Toggle("使用云端智能（DeepSeek）", isOn: Binding(get: { store.current.preferences.cloudAIEnabled }, set: { value in
                store.update("保存云端 AI 偏好") { $0.preferences.cloudAIEnabled = value }
            })).tint(YubaiColor.toggleOn)
            Text("金额、账户与资金性质由本机计算。开启后，会把脱敏的用途摘要发送到 DeepSeek；离线或请求失败时保留本机结果。")
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            Text(configured ? "已配置" : "未配置").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            SecureField("DeepSeek API 密钥", text: $key).autocorrectionDisabled().privacySensitive()
            Button("保存或替换密钥") { saveKey() }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("删除密钥", role: .destructive) { deleteKey() }
            Text("密钥仅保存在本机钥匙串，不进入账本或备份。删除后，开发环境仍可使用环境变量中的密钥。")
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            Button(testing ? "正在连接…" : "测试连接") { testConnection() }.disabled(!configured || testing)
            if !status.isEmpty { Text(status).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted) }
            NavigationLink("发给云端的内容") { CloudSendLogView() }
            NavigationLink("问余白") { AskYubaiView() }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            .onAppear { configured = APIKeyStore.shared.isConfigured }
            .onDisappear { key = "" }
    }
    @MainActor private func saveKey() {
        do { try APIKeyStore.shared.save(key); key = ""; configured = APIKeyStore.shared.isConfigured; status = "密钥已保存。" }
        catch { status = error.localizedDescription }
    }
    @MainActor private func deleteKey() {
        do { try APIKeyStore.shared.delete(); key = ""; configured = APIKeyStore.shared.isConfigured; status = "钥匙串中的密钥已删除。" }
        catch { status = error.localizedDescription }
    }
    @MainActor private func testConnection() {
        guard let client = DeepSeekClient.configured() else { configured = false; return }
        testing = true; status = ""
        Task {
            defer { testing = false }
            do {
                _ = try await client.chat(system: "请只回复：连接正常。", user: "你好", maxTokens: 16, purpose: "测试连接")
                status = "连接正常。"
            } catch { status = error.localizedDescription }
        }
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
