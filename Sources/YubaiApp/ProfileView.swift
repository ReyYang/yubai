import SwiftUI
import YubaiCore

private enum ProfileSheet: Identifiable {
    case area(ProfileArea, ProfileStance), principle(String?), conversation
    var id: String { String(describing: self) }
}

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var sheet: ProfileSheet?
    @State private var editing = false
    @State private var configured = IntelligenceRuntime.isConfigured
    private var profile: SpendingProfile { store.profile }
    private var canChat: Bool { configured && store.preferences.isAIEnabled(for: .answers) && IntelligenceRuntime.cloud.unavailableModel == nil }
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            ForEach(store.current.pendingChanges.filter(\.isProfileOnly)) { change in
                ProfileProposalCard(change: change, confirm: { store.apply(change, label: "修改消费观") }, secondaryTitle: "不改了") {
                    store.update("修改消费观") { ledger in
                        ledger.pendingChanges.removeAll { $0.id == change.id }
                        for i in ledger.cards.indices where ledger.cards[i].action == .confirmChangeSet(change.id) { ledger.cards[i].dismissedAt = Date() }
                    }
                }
            }
            areas(profile.restrain, stance: .restrain, title: "想克制的")
            areas(profile.generous, stance: .generous, title: "愿意多花的")
            principles
            memories
            chat
        }.navigationTitle("我的消费观").yubaiNavigation().accessibilityIdentifier("profilePage")
            .toolbar { Button(editing ? "完成" : "编辑") { editing.toggle() }.frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("editProfile") }
            .onAppear { configured = IntelligenceRuntime.isConfigured }
            .onChange(of: store.current.id) { _, _ in sheet = nil }
            .sheet(item: $sheet) { item in
                NavigationStack {
                    switch item {
                    case .area(let area, let stance): ProfileAreaEditor(area: area, stance: stance)
                    case .principle(let old): ProfilePrincipleEditor(original: old)
                    case .conversation: ProfileConversationView()
                    }
                }.environment(store).tint(YubaiColor.brandInk).appErrors().yubaiSheetBackground()
                    #if os(macOS)
                    .frame(minWidth: 540, minHeight: 600)
                    #endif
            }
    }

    // MARK: 余白记得的、聊聊
    private var memories: some View {
        let count = "\(store.current.memories.count) 条"
        return NavigationLink { MemoryView() } label: {
            Card(style: .list) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("余白记得的").yubaiFont(YubaiFont.rowTitle)
                    Spacer(minLength: YubaiSpace.space8)
                    Text(count).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    chevron
                }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
            }
        }.hidesListDisclosure().buttonStyle(PressButtonStyle()).accessibilityIdentifier("openMemories").accessibilityLabel("余白记得的，" + count)
    }
    @ViewBuilder private var chat: some View {
        if canChat {
            Button { sheet = .conversation } label: { chatRow }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("profileChatEntry")
        } else {
            NavigationLink { IntelligencePrivacyView() } label: { chatRow }
                .hidesListDisclosure().buttonStyle(PressButtonStyle()).accessibilityIdentifier("profileChatEntry")
                .accessibilityHint("打开智能与隐私，配置密钥、开启云端智能或选择模型")
        }
    }
    private var chatRow: some View {
        Card(style: .list, background: canChat ? YubaiColor.brandTint : YubaiColor.amberTint) {
            HStack(spacing: YubaiSpace.gapGroup) {
                AssistantMark(size: YubaiSpace.insetCard, color: canChat ? YubaiColor.brand : YubaiColor.amberDot)
                Text("和余白聊聊").yubaiFont(YubaiFont.rowTitle)
                Spacer()
                if !canChat {
                    Text(!configured ? "还没配密钥" : (!store.preferences.isAIEnabled(for: .answers) ? "云端智能没开" : "模型不可用")).yubaiFont(YubaiFont.caption)
                }
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta)
            }.foregroundStyle(canChat ? YubaiColor.brandTintStrong : YubaiColor.amberInk).frame(minHeight: YubaiSize.rowDouble)
        }
    }
    private var chevron: some View {
        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
    }

    // MARK: 三栏
    private func areas(_ rows: [ProfileArea], stance: ProfileStance, title: String) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            Text(title).yubaiFont(YubaiFont.cardTitle).padding(.horizontal, YubaiSpace.space4)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(rows) { area in
                        areaRow(area, stance: stance)
                        EntryFormDivider()
                    }
                    addRow(label: "添加" + title) { sheet = .area(ProfileArea(title: ""), stance) }
                }
            }
        }
    }
    private func areaRow(_ area: ProfileArea, stance: ProfileStance) -> some View {
        HStack(alignment: .center, spacing: YubaiSpace.gapGroup) {
            Button { sheet = .area(area, stance) } label: {
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Text(area.title).yubaiFont(YubaiFont.row)
                    if showsNote(area, stance: stance) {
                        Text(area.note).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).multilineTextAlignment(.leading)
                    }
                }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("profileArea_" + area.id.uuidString)
            if editing { Menu {
                Button("编辑") { sheet = .area(area, stance) }
                Button("删掉") {
                    edit { $0.generous.removeAll { $0.id == area.id }; $0.restrain.removeAll { $0.id == area.id } }
                }
            } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("编辑或删除" + area.title) }
        }
    }
    private func addRow(label: String, identifier: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: YubaiSpace.space8) {
                Image(systemName: "plus").yubaiFont(YubaiFont.callout)
                Text("添加").yubaiFont(YubaiFont.row)
                Spacer(minLength: YubaiSpace.none)
            }.foregroundStyle(YubaiColor.brandInk).frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
    private func showsNote(_ area: ProfileArea, stance: ProfileStance) -> Bool {
        guard !area.note.isEmpty else { return false }
        guard stance == .restrain, let limit = area.softLimit else { return true }
        let note = area.note.hasPrefix(area.title) ? String(area.note.dropFirst(area.title.count)) : area.note
        return normalizedLimit(note) != normalizedLimit(limit.text)
    }
    private func normalizedLimit(_ text: String) -> String {
        var result = text
        for part in [".00", "最多", "¥", "￥", "元", " ", "\n", "·", "，", "。"] {
            result = result.replacingOccurrences(of: part, with: "")
        }
        return result
    }
    private var principles: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            Text("原则").yubaiFont(YubaiFont.cardTitle).padding(.horizontal, YubaiSpace.space4)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(profile.principles, id: \.self) { text in
                        principleRow(text)
                        EntryFormDivider()
                    }
                    addRow(label: "添加原则", identifier: "addPrinciple") { sheet = .principle(nil) }
                }
            }
        }
    }
    private func principleRow(_ text: String) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Button { sheet = .principle(text) } label: {
                Text(text).yubaiFont(YubaiFont.row).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("profilePrinciple_" + text)
            if editing {
                Menu {
                    Button("编辑") { sheet = .principle(text) }
                    Button("删掉") { edit { $0.principles.removeAll { $0 == text } } }
                } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("编辑或删除原则：" + text)
            }
        }
    }
    private func edit(_ change: (inout SpendingProfile) -> Void) {
        store.update("修改消费观") { ledger in
            let old = ledger.profile; change(&ledger.profile); ledger.profile.stamp(changedFrom: old, at: Date())
        }
    }
}

private struct ProfileAreaEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var area: ProfileArea
    var stance: ProfileStance
    @State private var title = ""
    @State private var categories = Set<String>()
    @State private var keywords: [String] = []
    @State private var keywordInput = ""
    @State private var note = ""
    @State private var weekly = ""
    @State private var monthly = ""
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                TextField("名称", text: $title).accessibilityIdentifier("profileAreaTitle")
                if title.isEmpty { InlineFieldError(message: "填写名称") }
                SuggestionChips(values: ["外卖", "学习", "旅行"], selected: title) { title = $0 }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("关键词").yubaiFont(YubaiFont.row)
                    ChipFlow {
                        ForEach(keywords, id: \.self) { word in
                            SuggestionChip(value: word + " ×", selected: true) { keywords.removeAll { $0 == word } }
                                .accessibilityLabel("移除关键词" + word)
                        }
                    }
                    HStack(spacing: YubaiSpace.space8) {
                        TextField("添加关键词", text: $keywordInput).onSubmit(addKeyword)
                        Button("添加", action: addKeyword).disabled(keywordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    SuggestionChips(values: ["美团", "饿了么", "奶茶", "打车"].filter { !keywords.contains($0) }) { keywords.append($0) }
                }
                DisclosureGroup("更多") { TextField("说明", text: $note, axis: .vertical) }
            }
            Section("相关分类") {
                ForEach(store.current.selectableCategories.filter { !$0.income }) { category in
                    Toggle(category.name, isOn: Binding(get: { categories.contains(category.name) }, set: { value in
                        if value { categories.insert(category.name) } else { categories.remove(category.name) }
                    })).tint(YubaiColor.toggleOn)
                }
            }
            if stance == .restrain {
                Section("上限") {
                    TextField("每周次数", text: $weekly).numericInput().accessibilityHint("空着表示不限次数")
                    InlineFieldError(message: !weekly.isEmpty && Int(weekly).map({ (0...10000).contains($0) }) != true ? "每周次数须为 0 至 10,000 的整数" : nil)
                    TextField("每月金额", text: $monthly).numericInput().accessibilityHint("单位元，空着表示不限金额")
                    InlineFieldError(message: !monthly.isEmpty && (try? Money.parse(monthly)) == nil ? "填写有效金额" : nil)
                }
            }
        }.editorForm().navigationTitle(stance == .restrain ? "想克制的" : "愿意多花的").yubaiNavigation()
            .manualSheetHeader(stance == .restrain ? "想克制的" : "愿意多花的", actionTitle: "保存", enabled: validationError == nil, action: save)
            .onAppear {
                guard !loaded else { return }; loaded = true
                title = area.title; categories = Set(area.match.categories.map { store.current.resolveCategory($0, income: false) })
                keywords = area.match.keywords; note = area.note
                weekly = area.softLimit?.perWeekCount.map { String($0) } ?? ""; monthly = area.softLimit?.perMonthAmount.map { Money.input($0) } ?? ""
            }
    }
    private var validationError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "填写名称" }
        if !weekly.isEmpty && Int(weekly).map({ (0...10000).contains($0) }) != true { return "每周次数须为 0 至 10,000 的整数" }
        if !monthly.isEmpty && (try? Money.parse(monthly)) == nil { return "填写有效金额" }
        return nil
    }
    private func addKeyword() {
        let words = keywordInput.components(separatedBy: CharacterSet(charactersIn: "、,，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for word in words where !keywords.contains(word) { keywords.append(word) }
        keywordInput = ""
    }
    private func save() {
        do {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw YubaiError.invalid("给这个领域起个名字吧。") }
            let countText = weekly.trimmingCharacters(in: .whitespacesAndNewlines)
            let count: Int? = countText.isEmpty ? nil : Int(countText)
            guard countText.isEmpty || count.map({ (0...10000).contains($0) }) == true else { throw YubaiError.invalid("每周次数请填 0 至 10,000 的整数。") }
            let amount: Int64? = monthly.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try Money.parse(monthly)
            addKeyword()
            let words = keywords
            var updated = area; updated.title = clean; updated.note = note
            updated.match = AreaMatch(categories: categories.sorted(), keywords: words, subcategories: area.match.subcategories)
            updated.softLimit = stance == .restrain && (count != nil || amount != nil) ? SoftLimit(perWeekCount: count, perMonthAmount: amount) : nil
            if store.update("修改消费观", { ledger in
                let old = ledger.profile
                ledger.profile.generous.removeAll { $0.id == updated.id }; ledger.profile.restrain.removeAll { $0.id == updated.id }
                if stance == .generous { ledger.profile.generous.append(updated) } else { ledger.profile.restrain.append(updated) }
                ledger.profile.stamp(changedFrom: old, at: Date())
            }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}

private struct ProfilePrincipleEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var original: String?
    @State private var text = ""
    @FocusState private var focused: Bool
    private var clean: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
            TextField("超过多少钱要等一等？", text: $text, axis: .vertical).focused($focused).yubaiFont(YubaiFont.body)
                .padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.buttonHeight)
                .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card)).accessibilityIdentifier("principleText")
            ChipFlow(rowSpacing: YubaiSpace.gapGroup) {
                ForEach(["超过 2,000 等 48 小时", "每天用得上的，愿意多花", "买之前先看看家里有没有"], id: \.self) { value in
                    SuggestionChip(value: value, identifier: "principleSuggestion_" + value) { text = value }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup)
            .paperBackground().yubaiNavigation().navigationTitle(original == nil ? "加一条原则" : "原则")
            .onAppear { text = original ?? ""; focused = true }
            .manualSheetHeader(original == nil ? "加一条原则" : "原则", actionTitle: "保存", enabled: !clean.isEmpty,
                               actionIdentifier: "savePrinciple", action: {
                if store.update("修改消费观", { ledger in
                    let old = ledger.profile
                    if let original, let i = ledger.profile.principles.firstIndex(of: original) { ledger.profile.principles[i] = clean }
                    else { ledger.profile.principles.append(clean) }
                    ledger.profile.stamp(changedFrom: old, at: Date())
                }) { dismiss() }
            })
    }
}

struct ProfileProposalCard: View {
    @Environment(AppStore.self) private var store
    let change: ChangeSet
    let confirm: () -> Void
    let secondaryTitle: String
    let secondary: () -> Void
    var body: some View {
        ProposalCard(title: store.preferences.hideAmounts ? "余白想这样改" : change.reason, lines: store.preferences.hideAmounts ? [] : change.preview(in: store.current, showPreviousValues: true),
                     primaryTitle: "改好这 \(change.items.count) 项", secondaryTitle: secondaryTitle, canConfirm: !store.preferences.hideAmounts, confirm: confirm, cancel: secondary)
    }
}
