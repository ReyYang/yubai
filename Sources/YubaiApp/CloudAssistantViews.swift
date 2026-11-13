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
    @State private var hasKey = APIKeyStore.shared.hasKeychainKey
    @State private var status = ""
    @State private var testing = false
    var body: some View {
        Page(spacing: YubaiSpace.space16, topPadding: YubaiSpace.space8) {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    HStack {
                        Text("DeepSeek").yubaiFont(YubaiFont.row)
                        Spacer(minLength: YubaiSpace.space8)
                        HStack(spacing: YubaiSpace.space4) {
                            if configured { Image(systemName: "lock") }
                            Text(configured ? "已配好" : "未配好")
                        }.yubaiFont(YubaiFont.caption).foregroundStyle(configured ? YubaiColor.brandInk : YubaiColor.amberInk)
                            .padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.pillHeight).background(configured ? YubaiColor.brandTint : YubaiColor.amberTint, in: Capsule()).fixedSize()
                    }.frame(minHeight: YubaiSize.headerHeight).accessibilityIdentifier("cloudKeyStatus")
                    if configured {
                        EntryFormDivider()
                        HStack {
                            Text("存在").yubaiFont(YubaiFont.row)
                            Spacer(minLength: YubaiSpace.space8)
                            Text(hasKey ? "本机钥匙串" : "环境变量").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        }.frame(minHeight: YubaiSize.headerHeight)
                    }
                }
            }
            if configured {
                VStack(spacing: YubaiSpace.space8) {
                    Button(testing ? "正在连接…" : "测试连接") { testConnection() }.buttonStyle(SecondaryButtonStyle()).disabled(testing)
                        .accessibilityIdentifier("testCloudKey")
                    if !status.isEmpty { statusText }
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("换一个").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.space16)
                    keyInput
                    saveButton
                }.padding(.top, YubaiSpace.space8)
                if hasKey {
                    Button("删掉密钥") { deleteKey() }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle()).padding(.top, YubaiSpace.space24)
                        .accessibilityIdentifier("deleteCloudKey")
                }
            } else {
                keyInput
                saveButton
                if !status.isEmpty { statusText }
            }
        }
            .navigationTitle("密钥").yubaiNavigation().accessibilityIdentifier("cloudKeyPage")
            .onAppear { configured = APIKeyStore.shared.isConfigured; hasKey = APIKeyStore.shared.hasKeychainKey }
            .onDisappear { key = "" }
    }
    private var keyInput: some View {
        Card(style: .list) {
            CardTextFieldRow(title: "密钥", text: $key, identifier: "cloudKeyInput", hidesValue: true, autofocus: !configured)
        }
    }
    private var saveButton: some View {
        Button("保存密钥") { saveKey() }.buttonStyle(PrimaryButtonStyle()).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("saveCloudKey")
    }
    private var statusText: some View {
        Text(status).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .center).accessibilityIdentifier("cloudKeyConnectionStatus")
    }
    @MainActor private func saveKey() {
        do { try APIKeyStore.shared.save(key); key = ""; configured = APIKeyStore.shared.isConfigured; hasKey = APIKeyStore.shared.hasKeychainKey; IntelligenceRuntime.cloud.refresh(); status = "密钥已保存" }
        catch { status = error.localizedDescription }
    }
    @MainActor private func deleteKey() {
        do { try APIKeyStore.shared.delete(); key = ""; configured = APIKeyStore.shared.isConfigured; hasKey = APIKeyStore.shared.hasKeychainKey; IntelligenceRuntime.cloud.refresh(); status = "密钥已删掉" }
        catch { status = error.localizedDescription }
    }
    @MainActor private func testConnection() {
        guard let client = DeepSeekClient.configured() else { configured = false; return }
        testing = true; status = ""
        Task {
            defer { testing = false }
            do {
                _ = try await client.chat(system: "请只回复：连接正常。", user: "你好", maxTokens: 64, thinking: false, purpose: "测试连接")
                IntelligenceRuntime.cloud.succeeded(model: client.configuration.model)
                status = "连接正常"
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
            }.frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
        }.accessibilityIdentifier("editCloudModel")
            .navigationDestination(isPresented: $editing) { CloudModelEditor() }
            .task { await fetchModels() }
    }
    private func fetchModels() async {
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { return }
        #endif
        // Opening settings during setup or before organizing an import is local.
        guard store.preferences.cloudAIEnabled,
              store.pendingOrganization.batchIDs.isEmpty else { return }
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
                CardTextFieldRow(title: "模型", text: $name, identifier: "cloudModelName", autofocus: true).autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                InlineFieldError(message: !errorText.isEmpty ? errorText : name.count > 200 || name.contains(where: { $0.isNewline }) ? "模型名字须在一行内，最多 200 字" : nil)
            }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("模型").yubaiNavigation().toolbar {
            Button("保存") {
                do { try IntelligenceRuntime.cloud.saveModel(name); dismiss() } catch { errorText = error.localizedDescription }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 200 || name.contains(where: { $0.isNewline }))
                .accessibilityIdentifier("saveCloudModel")
        }
    }
}

struct ModelUnavailableNote: View {
    let model: String
    var body: some View {
        Text("模型「\(model)」不可用")
            .foregroundStyle(YubaiColor.amberInk)
            .yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, YubaiSpace.gapGroup).padding(.horizontal, YubaiSpace.insetCard)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row), background: YubaiColor.amberTint)
            .accessibilityHint("使用下方模型菜单选择其他模型")
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
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                SectionHeading(title: "本次打开")
                Text("\(sentCount) 次 · " + CloudLogText.bytes(sentBytes)).yubaiFont(YubaiFont.lead).accessibilityIdentifier("cloudSendSummary")
                    .accessibilityLabel("本次打开后发送 \(sentCount) 次，共 " + CloudLogText.bytes(sentBytes))
                    .accessibilityHint("发送记录只存在本机内存，关掉应用就清空；汇总图仅包含保留的记录")
            }
            if groups.isEmpty {
                EmptyState("paperplane", "还没有发送记录", action: "问余白", onAction: { store.sheet = .ask("") }).accessibilityIdentifier("emptyCloudSendLog")
            } else {
                summaryCard
                Segmented(choices: [(false, "全部"), (true, "没成功 \(groups.filter(\.hasFailure).count)")], selection: $onlyFailures).accessibilityIdentifier("cloudLogFilter")
                let visible = groups.filter { !onlyFailures || $0.hasFailure }
                CardRows(visible) { group in
                    NavigationLink { CloudSendLogDetailView(group: group) } label: { groupRow(group) }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("cloudLogGroup_" + group.id.uuidString)
                }
                if visible.isEmpty { EmptyState("checkmark", "没有没成功的记录", action: "查看全部", onAction: { onlyFailures = false }) }
            }
            Button("清空这份记录") { SendLog.shared.clear(); reload() }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("clearCloudSendLog")
        }.amountPrivacy(store.preferences.hideAmounts).navigationTitle("发给云端的内容").yubaiNavigation()
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: SendLog.didRecord).receive(on: RunLoop.main)) { _ in reload() }
    }
    private var summaryCard: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text("为了什么发").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                ForEach(purposeCounts, id: \.key) { row in
                    HStack(spacing: YubaiSpace.gapGroup) {
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
        HStack(spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(group.purpose + (store.preferences.hideAmounts || group.title == group.purpose ? "" : " · " + group.title)).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label)
                Text(ImportStatementText.time(group.startedAt) + " · " + CloudLogText.metadata(group)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                if group.hasFailure { Text(store.preferences.hideAmounts ? "这次没有成功" : group.failureReasons.joined(separator: "；")).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: YubaiSize.chipMinimum), alignment: .leading)], alignment: .leading, spacing: YubaiSpace.space8) {
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
    @State private var rawFocus: SendLogRawTarget?
    @State private var revision = 0
    @State private var rules: [String] = []
    @State private var rulesCharacters = 0
    @State private var steps: [SendLogTraceStep] = []
    private var hidden: Bool { store.preferences.hideAmounts }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.gapGroup) {
            if removed { Text("这份记录已清空或移出。").yubaiFont(YubaiFont.callout) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: YubaiSpace.space8) {
                        ForEach(Set(group.items.flatMap { [$0.model] + ($0.attempts?.compactMap(\.model) ?? []) }).sorted(), id: \.self) { Pill(text: $0, variant: .neutral, showsDot: false) }
                        Pill(text: CloudLogText.metadata(group), variant: .neutral, showsDot: false)
                    }
                }
                if !group.redactionSummary.isEmpty { CloudRedactionChips(summary: group.redactionSummary) }
                Card(style: .list) {
                    DisclosureGroup {
                        ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                            Text(hidden ? "金额已隐藏" : rule).yubaiFont(YubaiFont.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, YubaiSpace.space8)
                        }
                    } label: {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text("给云端的规则说明").yubaiFont(YubaiFont.row)
                            Spacer()
                            Text("\(rulesCharacters) 字").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }.frame(minHeight: YubaiSize.tapMin)
                    }.accessibilityIdentifier("cloudLogRules")
                }
                ForEach(steps) { step in traceRow(step) }
                if group.hasFailure {
                    InlineNote(text: hidden ? "这次没有成功" : group.failureReasons.joined(separator: "；"), style: .attention)
                }
            }
        }.safeAreaInset(edge: .bottom) {
            if !removed {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Button("看原文") { rawFocus = nil; raw = true }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("viewCloudLogRaw")
                    Button(copied ? "已拷贝" : "拷贝原文") { copyRaw() }.buttonStyle(SecondaryButtonStyle()).disabled(hidden).accessibilityIdentifier("copyCloudLogRaw")
                }.padding(YubaiSpace.insetPage).background(YubaiColor.canvas.ignoresSafeArea(edges: .bottom))
            }
        }
        .amountPrivacy(hidden).navigationTitle(group.purpose + " · " + ImportStatementText.time(group.startedAt)).yubaiNavigation()
        .task(id: revision) {
            let snapshot = group
            let preparation = Task.detached(priority: .userInitiated) {
                let rules = SendLogPresentation.rules(in: snapshot)
                return (rules, rules.reduce(0) { $0 + $1.count }, SendLogPresentation.trace(in: snapshot))
            }
            let prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
            guard !Task.isCancelled else { return }
            rules = prepared.0; rulesCharacters = prepared.1; steps = prepared.2
        }
        .sheet(isPresented: $raw) { NavigationStack { rawRequests }.environment(store).yubaiSheetBackground() }
        .onReceive(NotificationCenter.default.publisher(for: SendLog.didRecord).receive(on: RunLoop.main)) { _ in
            if let latest = SendLog.shared.groups.first(where: { $0.id == group.id }) { group = latest; copied = false; revision += 1 }
            else { removed = true; raw = false }
        }
    }
    private func traceRow(_ step: SendLogTraceStep) -> some View {
        Button { rawFocus = step.target; raw = true } label: {
            HStack(alignment: .top, spacing: YubaiSpace.gapGroup) {
                Text("\(step.id)").yubaiFont(YubaiFont.meta)
                    .foregroundStyle(step.outgoing ? YubaiColor.onBrand : YubaiColor.label)
                    .frame(width: YubaiSize.tagHeight, height: YubaiSize.tagHeight)
                    .background(step.outgoing ? YubaiColor.brand : YubaiColor.paperInset, in: Circle())
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(step.title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        ForEach(Array(step.lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: YubaiSpace.gapGroup) {
                                if !line.label.isEmpty { Text(line.label).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
                                Text(hidden ? "金额已隐藏" : line.value).yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(.vertical, YubaiSpace.gapGroup).padding(.horizontal, YubaiSpace.insetCard)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row))
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("cloudLogStep_" + String(step.id))
    }
    private var rawRequests: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
                    if hidden { Text("金额已隐藏").yubaiFont(YubaiFont.callout) }
                    else {
                        ForEach(SendLogRawPresentation.sources(in: group)) { source in
                            CloudLogRawExchange(source: source, revision: revision).id(source.id)
                        }
                    }
                }
                .padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.insetPage)
                .padding(.bottom, YubaiSpace.gapSection)
                .frame(maxWidth: YubaiSize.contentMaximum).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).yubaiFont(YubaiFont.body)
                .foregroundStyle(YubaiColor.label).paperBackground()
                .task(id: rawFocus) {
                    if let rawFocus { proxy.scrollTo(rawFocus, anchor: .top) }
                }
        }.navigationTitle("原文").yubaiNavigation().manualSheetHeader("原文", cancelTitle: "关闭", showsAction: false)
    }
    private func copyRaw() {
        guard !hidden else { return }
        let snapshot = group, expectedRevision = revision
        Task {
            let text = await Task.detached(priority: .userInitiated) { SendLogRawPresentation.copyText(in: snapshot) }.value
            guard !hidden, !removed, revision == expectedRevision else { return }
            #if os(iOS)
            UIPasteboard.general.string = text
            #elseif os(macOS)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            #endif
            copied = true
        }
    }
}

private struct CloudLogRawExchange: View {
    let source: SendLogRawSource
    let revision: Int
    @State private var document: SendLogRawDocument?
    private var outgoing: Bool { source.target.outgoing }
    private var title: String {
        let title = outgoing ? "发出" : "云端回"
        guard let number = source.target.attemptNumber else { return title }
        let model = source.item.attempts?.first { $0.number == number }?.model
        let suffix = model.flatMap { $0 == source.item.model ? nil : " · " + $0 } ?? ""
        return title + " · 第 \(number) 次" + suffix
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            step(source.number, title: title, outgoing: outgoing)
            if let document {
                if let rules = document.rules { CloudLogRawRules(rules: rules) }
                if outgoing { Text("资料").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                CloudLogRawSections(sections: document.sections, outgoing: outgoing)
            } else { ProgressView() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier((outgoing ? "cloudLogRequest_" : "cloudLogResponse_") + source.item.id.uuidString)
        .task(id: revision) {
            do {
                let prepared = try await SendLogRawPresentation.load(source)
                try Task.checkCancellation()
                document = prepared
            } catch { }
        }
    }
    private func step(_ number: Int, title: String, outgoing: Bool) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(number.formatted()).yubaiFont(YubaiFont.code)
                .foregroundStyle(outgoing ? YubaiColor.onBrand : YubaiColor.label)
                .frame(width: YubaiSize.tagHeight, height: YubaiSize.tagHeight)
                .background(outgoing ? YubaiColor.brand : YubaiColor.paperInset, in: Circle())
            Text(title).yubaiFont(YubaiFont.callout, weight: .medium)
        }
    }
}

private struct CloudLogRawCard<Content: View>: View {
    var outgoing = true
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(.horizontal, YubaiSpace.insetCard).padding(.vertical, YubaiSpace.space8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row))
    }
}

private struct CloudLogRawRules: View {
    let rules: SendLogRawPresentation.Rules
    @State private var expanded = false
    var body: some View {
        if !rules.text.isEmpty {
            Text("给云端的规则说明").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            CloudLogRawCard {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    if expanded { CloudLogRawText(text: rules.text) }
                    else {
                        Text(rules.preview).yubaiFont(YubaiFont.row).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    CloudLogRawSeparator()
                    Button { expanded.toggle() } label: {
                        CloudLogRawDisclosure(title: "全文 \(rules.count.formatted()) 字", expanded: expanded, color: YubaiColor.brand)
                    }.buttonStyle(.plain).accessibilityValue(expanded ? "已展开" : "已折叠")
                }
            }
        }
    }
}

private struct CloudLogRawSections: View {
    let sections: [SendLogRawSection]
    let outgoing: Bool
    var body: some View {
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                if let title = section.title {
                    Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
                switch section.body {
                case .groups(let groups): CloudLogRawGroups(groups: groups)
                case .fields(let fields):
                    CloudLogRawCard(outgoing: outgoing) { CloudLogRawTree(fields: fields) }
                case .array(let name, let values):
                    CloudLogRawCard(outgoing: outgoing) {
                        CloudLogRawArray(name: name, values: values, showsHeading: false, indentElements: false)
                    }
                case .text(let text):
                    CloudLogRawCard(outgoing: outgoing) {
                        CloudLogRawText(text: text)
                    }
                }
            }
        }
    }
}

private struct CloudLogRawGroups: View {
    let groups: [SendLogRawGroup]
    @State private var expanded = false
    @State private var visibleCount = SendLogRawPresentation.renderPageSize
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            if SendLogRawPresentation.initiallyCollapsed(count: groups.count) {
                CloudLogRawCard {
                    Button { expanded.toggle() } label: {
                        CloudLogRawDisclosure(title: SendLogRawPresentation.arrayTitle("groups", count: groups.count), expanded: expanded)
                    }.buttonStyle(.plain)
                }
            }
            if !SendLogRawPresentation.initiallyCollapsed(count: groups.count) || expanded {
                ForEach(Array(groups.prefix(visibleCount).enumerated()), id: \.offset) { _, group in
                    CloudLogRawCard {
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup) {
                                Text(group.party).yubaiFont(YubaiFont.rowTitle)
                                Spacer(minLength: YubaiSpace.none)
                                Text(group.detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            }
                            CloudLogRawTree(fields: group.fields)
                        }.textSelection(.enabled)
                    }
                }
                if visibleCount < groups.count {
                    Button("展开") { visibleCount += SendLogRawPresentation.renderPageSize }.buttonStyle(TextLinkStyle(alignment: .leading))
                }
            }
        }
    }
}

/// Keep the recursive boundary type-erased so nested objects do not produce an
/// infinitely recursive SwiftUI body type. Every value remains available.
private struct CloudLogRawTree: View {
    let fields: [SendLogRawField]
    @State private var visibleCount = SendLogRawPresentation.renderPageSize
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.none) {
            ForEach(Array(fields.prefix(visibleCount).enumerated()), id: \.element.id) { index, field in
                if index > 0 { CloudLogRawSeparator() }
                CloudLogRawFieldRow(field: field).padding(.vertical, YubaiSpace.space4)
            }
            if visibleCount < fields.count {
                Button("展开") { visibleCount += SendLogRawPresentation.renderPageSize }.buttonStyle(TextLinkStyle(alignment: .leading))
            }
        }
    }
}

private struct CloudLogRawFieldRow: View {
    let field: SendLogRawField
    var body: some View {
        switch field.value {
        case .object(let object) where !object.isEmpty:
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                key(field.name)
                CloudLogRawIndent { AnyView(CloudLogRawTree(fields: SendLogRawPresentation.fields(in: object))) }
            }
        case .array(let values):
            if !SendLogRawPresentation.initiallyCollapsed(values), values.allSatisfy(SendLogRawPresentation.isScalar) {
                row(name: "\(field.name) · \(values.count) 项", values: values)
            } else {
                CloudLogRawArray(name: field.name, values: values)
            }
        default: row(name: field.name, values: [field.value])
        }
    }
    private func key(_ name: String) -> some View {
        Text(name).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.code).foregroundStyle(YubaiColor.labelSecondary).textSelection(.enabled)
    }
    private func row(name: String, values: [JSONValue]) -> some View {
        HStack(alignment: .top, spacing: YubaiSpace.gapGroup) {
            key(name).frame(width: YubaiSize.rowDouble * 2, alignment: .leading)
            CloudLogRawScalars(values: values).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CloudLogRawArray: View {
    let name: String
    let values: [JSONValue]
    var showsHeading = true
    var indentElements = true
    @State private var expanded = false
    @State private var visibleCount = SendLogRawPresentation.renderPageSize
    private var collapsible: Bool { SendLogRawPresentation.initiallyCollapsed(values) }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            if collapsible {
                Button { expanded.toggle() } label: {
                    CloudLogRawDisclosure(title: "\(name) · \(values.count) 项", expanded: expanded)
                }.buttonStyle(.plain).accessibilityValue(expanded ? "已展开" : "已折叠")
            } else if showsHeading {
                Text("\(name) · \(values.count) 项").yubaiFont(YubaiFont.code).foregroundStyle(YubaiColor.labelSecondary)
            }
            if !collapsible || expanded {
                if values.allSatisfy(SendLogRawPresentation.isScalar) {
                    CloudLogRawScalars(values: Array(values.prefix(visibleCount)))
                } else {
                    ForEach(Array(values.prefix(visibleCount).enumerated()), id: \.offset) { index, value in
                        if index > 0 { CloudLogRawSeparator() }
                        if indentElements { CloudLogRawIndent { element(value) } }
                        else { element(value) }
                    }
                }
                if visibleCount < values.count {
                    Button("展开") { visibleCount += SendLogRawPresentation.renderPageSize }.buttonStyle(TextLinkStyle(alignment: .leading))
                }
            }
        }
    }
    private func element(_ value: JSONValue) -> AnyView {
        switch value {
        case .object(let fields) where !fields.isEmpty:
            AnyView(CloudLogRawTree(fields: SendLogRawPresentation.fields(in: fields)))
        case .array(let values): AnyView(CloudLogRawArray(name: "", values: values))
        default: AnyView(CloudLogRawScalars(values: [value]))
        }
    }
}

private struct CloudLogRawScalars: View {
    let values: [JSONValue]
    @ScaledMetric(relativeTo: .caption) private var codeSize = YubaiFont.code.size
    var body: some View {
        if values.contains(where: { value in
            if case .string(let text) = value { return text.utf8.count > SendLogRawPresentation.textChunkSize }
            return false
        }) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    CloudLogRawText(text: SendLogRawPresentation.scalarText(value))
                }
            }
        } else {
            values.enumerated().reduce(Text("")) { text, element in
                Text("\(text)\(element.offset == 0 ? "" : "、")\(scalar(element.element))")
            }.yubaiFont(YubaiFont.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scalar(_ value: JSONValue) -> Text {
        let text = Text(SendLogRawPresentation.scalarText(value))
        switch value {
        case .number, .bool:
            return text.font(.system(size: codeSize, weight: YubaiFont.code.weight, design: YubaiFont.code.design))
                .foregroundColor(YubaiColor.brand)
        case .null: return text.foregroundColor(YubaiColor.labelSecondary)
        default: return text.foregroundColor(YubaiColor.label)
        }
    }
}

/// Reuses the existing text/disclosure appearance; each Text has a bounded size.
private struct CloudLogRawText: View {
    let text: String
    @State private var chunks: [String] = []
    @State private var visibleCount = 1
    var body: some View {
        LazyVStack(alignment: .leading, spacing: YubaiSpace.space4) {
            ForEach(Array(chunks.prefix(visibleCount).enumerated()), id: \.offset) { _, chunk in
                Text(chunk).yubaiFont(YubaiFont.row).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if visibleCount < chunks.count {
                Button { visibleCount += SendLogRawPresentation.renderPageSize } label: {
                    CloudLogRawDisclosure(title: "展开", expanded: false, color: YubaiColor.brand)
                }.buttonStyle(.plain)
            }
        }
        .task(id: text) {
            let preparation = Task.detached(priority: .userInitiated) { SendLogRawPresentation.textChunks(text) }
            let prepared = await withTaskCancellationHandler { await preparation.value } onCancel: { preparation.cancel() }
            guard !Task.isCancelled else { return }
            chunks = prepared
        }
    }
}

private struct CloudLogRawIndent<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(.leading, YubaiSpace.gapGroup)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { YubaiColor.separator.frame(width: YubaiSize.lineWidth) }
            .padding(.leading, YubaiSpace.space4)
    }
}

private struct CloudLogRawDisclosure: View {
    let title: String
    let expanded: Bool
    var color = YubaiColor.labelSecondary
    var body: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(title).yubaiFont(YubaiFont.code)
            Spacer(minLength: YubaiSpace.none)
            Image(systemName: expanded ? "chevron.down" : "chevron.right").yubaiFont(YubaiFont.caption)
        }.foregroundStyle(color).contentShape(Rectangle()).yubaiHitTarget()
    }
}

private struct CloudLogRawSeparator: View {
    var body: some View { YubaiColor.separator.frame(height: YubaiSize.lineWidth / 2).accessibilityHidden(true) }
}
