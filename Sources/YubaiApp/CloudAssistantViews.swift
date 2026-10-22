import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

struct CloudModelMenu: View {
    @Environment(AppStore.self) private var store
    @State private var models = DeepSeekClient.fallbackModels
    @State private var fetchedAt: Date?
    @State private var editing = false
    var body: some View {
        Menu {
            ForEach(models, id: \.self) { model in
                Button {
                    do { try IntelligenceRuntime.cloud.saveModel(model) }
                    catch { store.error = error.localizedDescription }
                } label: {
                    Text(model)
                    if let description = description(model) { Text(description) }
                    if IntelligenceRuntime.cloud.model == model { Image(systemName: "checkmark") }
                }.accessibilityIdentifier("cloudModel_" + model)
                    .accessibilityAddTraits(IntelligenceRuntime.cloud.model == model ? .isSelected : [])
            }
            Divider()
            if let fetchedAt {
                Text("刚从 DeepSeek 取到 · " + fetchedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "zh_CN"))))
            } else { Text("内置模型") }
            Button("自己填…") { editing = true }.accessibilityIdentifier("customCloudModel")
        } label: {
            HStack(spacing: YubaiSpace.space8) {
                Text("模型").yubaiFont(YubaiFont.row); Spacer(minLength: YubaiSpace.space8)
                Text(IntelligenceRuntime.cloud.model).yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.labelSecondary)
                Image(systemName: "chevron.down").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
        }.accessibilityIdentifier("editCloudModel")
            .navigationDestination(isPresented: $editing) { CloudModelEditor() }
            .task { await fetchModels() }
    }
    private func description(_ model: String) -> String? {
        switch model {
        case "deepseek-chat": "快，日常记账和问答"
        case "deepseek-reasoner": "会多想一会，适合该不该买"
        default: nil
        }
    }
    private func fetchModels() async {
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { return }
        #endif
        guard let client = DeepSeekClient.configured() else { models = DeepSeekClient.fallbackModels; fetchedAt = nil; return }
        do {
            let result = try await client.listModels()
            guard !Task.isCancelled else { return }
            models = result; fetchedAt = Date()
        } catch {
            guard !Task.isCancelled else { return }
            models = DeepSeekClient.fallbackModels; fetchedAt = nil
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
         + Text("请到「模型」换个名字再试。"))
            .yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, YubaiSpace.space12).padding(.horizontal, YubaiSpace.space16)
            .background(YubaiColor.amberTint, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            .accessibilityIdentifier("modelUnavailable")
    }
}

private enum CloudLogText {
    static func bytes(_ bytes: Int) -> String { String(format: bytes < 10 * 1024 ? "%.1f KB" : "%.0f KB", Double(bytes) / 1024) }
    static func duration(_ milliseconds: Int) -> String { String(format: "%.1f 秒", Double(milliseconds) / 1000) }
    static func metadata(_ group: SendLogGroup) -> String {
        "\(group.requestCount) 来回 · " + bytes(group.totalBytes) + " · " + duration(group.totalDurationMilliseconds)
    }
    static func redaction(_ summary: [String: Int]) -> [(key: String, title: String)] {
        summary.keys.sorted().map { key in (key, (key == "联系人" ? "人名" : key) + " \(summary[key, default: 0])") }
    }
}

struct CloudSendLogView: View {
    @Environment(AppStore.self) private var store
    @State private var groups: [SendLogGroup] = []
    @State private var onlyFailures = false
    @State private var sentCount = 0
    @State private var sentBytes = 0
    private var purposeCounts: [(key: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in groups.flatMap(\.items) { counts[SendLogPresentation.purpose(item.purpose), default: 0] += 1 }
        return counts.map { (key: $0.key, count: $0.value) }.sorted { $0.count == $1.count ? $0.key < $1.key : $0.count > $1.count }
    }
    private var redactions: [String: Int] {
        var result: [String: Int] = [:]
        for group in groups { for (key, count) in group.redactionSummary { result[key, default: 0] += count } }
        return result
    }
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text("本次打开后发了 \(sentCount) 次，共 " + CloudLogText.bytes(sentBytes)).yubaiFont(YubaiFont.lead).accessibilityIdentifier("cloudSendSummary")
                Text("只存在本机内存，关掉应用就清空").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
            if groups.isEmpty {
                Card { Text("还没有发送记录。").yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted).accessibilityIdentifier("emptyCloudSendLog") }
            } else {
                summaryCard
                Segmented(choices: [(false, "全部"), (true, "没成功 \(groups.filter(\.hasFailure).count)")], selection: $onlyFailures).accessibilityIdentifier("cloudLogFilter")
                let visible = groups.filter { !onlyFailures || $0.hasFailure }
                CardRows(visible) { group in
                    NavigationLink { CloudSendLogDetailView(group: group) } label: { groupRow(group) }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("cloudLogGroup_" + group.id.uuidString)
                }
                if visible.isEmpty { Text("没有没成功的记录。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
                if groups.reduce(0, { $0 + $1.requestCount }) < sentCount {
                    Text("较早的记录已移出；按保留的记录汇总。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
            Button("清空这份记录") { SendLog.shared.clear(); reload() }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("clearCloudSendLog")
        }.amountPrivacy(store.current.preferences.hideAmounts).navigationTitle("发给云端的内容").yubaiNavigation()
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: SendLog.didRecord).receive(on: RunLoop.main)) { _ in reload() }
    }
    private var summaryCard: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space10) {
                Text("为了什么发").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                ForEach(purposeCounts, id: \.key) { row in
                    HStack(spacing: YubaiSpace.space10) {
                        Text(row.key).yubaiFont(YubaiFont.callout).frame(width: YubaiSize.tapMin * 2, alignment: .leading)
                        GeometryReader { geometry in
                            Capsule().fill(YubaiColor.neutralSoft)
                            Capsule().fill(row.key == purposeCounts.first?.key ? YubaiColor.brand : YubaiColor.series2)
                                .frame(width: geometry.size.width * CGFloat(row.count) / CGFloat(max(1, purposeCounts.first?.count ?? 1)))
                        }.frame(height: YubaiSpace.space8).accessibilityHidden(true)
                        Text("\(row.count)").yubaiFont(YubaiFont.amountSmall).frame(minWidth: YubaiSize.barMax, alignment: .trailing)
                    }.accessibilityElement(children: .combine)
                }
                Divider().overlay(YubaiColor.separator)
                Text("发之前换掉了").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                if redactions.isEmpty { Text("这份记录里没有替换项").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                else { CloudRedactionChips(summary: redactions) }
            }
        }
    }
    private func groupRow(_ group: SendLogGroup) -> some View {
        HStack(spacing: YubaiSpace.space10) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(group.purpose + (store.current.preferences.hideAmounts || group.title == group.purpose ? "" : " · " + group.title)).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label)
                Text(ImportStatementText.time(group.startedAt) + " · " + CloudLogText.metadata(group)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                if group.hasFailure { Text(store.current.preferences.hideAmounts ? "这次没有成功" : group.failureReasons.joined(separator: "；")).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if group.hasFailure { Circle().fill(YubaiColor.amberDot).frame(width: YubaiSize.marker, height: YubaiSize.marker).accessibilityHidden(true) }
            Image(systemName: "chevron.right").foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
        }.padding(.vertical, YubaiSpace.space8).contentShape(Rectangle())
    }
    private func reload() {
        groups = SendLog.shared.groups; sentCount = SendLog.shared.totalCount; sentBytes = SendLog.shared.totalSentByteSize
    }
}

private struct CloudRedactionChips: View {
    let summary: [String: Int]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: YubaiSpace.space6) {
            ForEach(CloudLogText.redaction(summary), id: \.key) { row in Pill(text: row.title, showsDot: false) }
        }
    }
}

private struct CloudSendLogDetailView: View {
    @Environment(AppStore.self) private var store
    @State var group: SendLogGroup
    @State private var raw = false
    @State private var copied = false
    @State private var removed = false
    private var hidden: Bool { store.current.preferences.hideAmounts }
    var body: some View {
        Page(spacing: YubaiSpace.space12, topPadding: YubaiSpace.space10) {
            if removed { Text("这份记录已清空或移出。").yubaiFont(YubaiFont.callout) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: YubaiSpace.space6) {
                        ForEach(Set(group.items.map(\.model)).sorted(), id: \.self) { Pill(text: $0, variant: .neutral, showsDot: false) }
                        Pill(text: CloudLogText.metadata(group), variant: .neutral, showsDot: false)
                    }
                }
                if !group.redactionSummary.isEmpty { CloudRedactionChips(summary: group.redactionSummary) }
                Card(style: .list) {
                    DisclosureGroup {
                        ForEach(Array(SendLogPresentation.rules(in: group).enumerated()), id: \.offset) { _, rule in
                            Text(hidden ? "金额已隐藏" : rule).yubaiFont(YubaiFont.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, YubaiSpace.space8)
                        }
                    } label: {
                        HStack {
                            Text("给云端的规则说明").yubaiFont(YubaiFont.row)
                            Spacer()
                            Text("\(SendLogPresentation.rules(in: group).reduce(0) { $0 + $1.count }) 字").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }.frame(minHeight: YubaiSize.tapMin)
                    }.accessibilityIdentifier("cloudLogRules")
                }
                ForEach(SendLogPresentation.trace(in: group)) { step in traceRow(step) }
                if group.hasFailure {
                    InlineNote(text: hidden ? "这次没有成功" : group.failureReasons.joined(separator: "；"), style: .attention)
                }
            }
        }.safeAreaInset(edge: .bottom) {
            if !removed {
                HStack(spacing: YubaiSpace.space10) {
                    Button("看原文") { raw = true }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("viewCloudLogRaw")
                    Button(copied ? "已拷贝" : "拷贝原文") { copyRaw(); copied = true }.buttonStyle(SecondaryButtonStyle()).disabled(hidden).accessibilityIdentifier("copyCloudLogRaw")
                }.padding(YubaiSpace.space18).background(YubaiColor.canvas)
            }
        }
        .amountPrivacy(hidden).navigationTitle(group.purpose + " · " + ImportStatementText.time(group.startedAt)).yubaiNavigation()
        .sheet(isPresented: $raw) { NavigationStack { rawRequests }.environment(store) }
        .onReceive(NotificationCenter.default.publisher(for: SendLog.didRecord).receive(on: RunLoop.main)) { _ in
            if let latest = SendLog.shared.groups.first(where: { $0.id == group.id }) { group = latest; copied = false }
            else { removed = true; raw = false }
        }
    }
    private func traceRow(_ step: SendLogTraceStep) -> some View {
        HStack(alignment: .top, spacing: YubaiSpace.space10) {
            Text("\(step.id)").yubaiFont(YubaiFont.meta)
                .foregroundStyle(step.outgoing ? YubaiColor.onBrand : YubaiColor.label)
                .frame(width: YubaiSize.tagHeight, height: YubaiSize.tagHeight)
                .background(step.outgoing ? YubaiColor.brand : YubaiColor.card, in: Circle())
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(step.title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                    ForEach(Array(step.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: YubaiSpace.space10) {
                            if !line.label.isEmpty { Text(line.label).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
                            Text(hidden ? "金额已隐藏" : line.value).yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(.vertical, YubaiSpace.space10).padding(.horizontal, YubaiSpace.space16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(step.outgoing ? YubaiColor.raised : YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            }
        }.accessibilityIdentifier("cloudLogStep_" + String(step.id))
    }
    private var rawRequests: some View {
        Page {
            if hidden { Text("金额已隐藏").yubaiFont(YubaiFont.callout) }
            else {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    Text("第 \(index + 1) 次发出").yubaiFont(YubaiFont.rowTitle)
                    Text(item.requestText).yubaiFont(YubaiFont.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("cloudLogRequest_" + String(index + 1))
                }
            }
        }.navigationTitle("原文").yubaiNavigation().toolbar { CloseButton() }
    }
    private func copyRaw() {
        guard !hidden else { return }
        let text = group.items.enumerated().map { "第 \($0.offset + 1) 次发出\n" + $0.element.requestText }.joined(separator: "\n\n")
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
