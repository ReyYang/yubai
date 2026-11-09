import SwiftUI
import YubaiCore

private enum ProfileSheet: Identifiable {
    case area(ProfileArea, ProfileStance), principle(String?), goal(Goal?), conversation
    var id: String { String(describing: self) }
}

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: ProfileSheet?
    @State private var editing = false
    @State private var configured = IntelligenceRuntime.isConfigured
    private var profile: SpendingProfile { store.profile }
    private var canChat: Bool { configured && store.preferences.cloudAIEnabled && IntelligenceRuntime.cloud.unavailableModel == nil }
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
            if editing {
                areas(profile.generous, stance: .generous, title: "愿意多花的")
                principles
                goals
            } else {
                if profile.generous.isEmpty && profile.principles.isEmpty {
                    areas([], stance: .generous, title: "愿意多花的")
                } else {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                        SectionHeading(title: "愿意多花的")
                        Card {
                            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                                ChipFlow {
                                    ForEach(profile.generous) { area in
                                        Text(area.title).yubaiFont(YubaiFont.callout).lineLimit(1).truncationMode(.tail)
                                            .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8).background(YubaiColor.raised, in: Capsule())
                                    }
                                }
                                ForEach(profile.principles, id: \.self) { text in Text(text).yubaiFont(YubaiFont.cardTitle) }
                            }
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: YubaiSpace.gapGroup) { savings }
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) { savings }
                }
                habits
            }
            memories
            if canChat {
                Button { sheet = .conversation } label: { chatRow }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("profileChatEntry")
            } else {
                NavigationLink { IntelligencePrivacyView() } label: { chatRow }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("profileChatEntry")
                    .accessibilityHint("打开智能与隐私，配置密钥、开启云端智能或选择模型")
            }
        }.navigationTitle("我的消费观").yubaiNavigation()
            .toolbar { Button(editing ? "完成" : "编辑") { editing.toggle() }.frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("editProfile") }
            .onAppear { configured = IntelligenceRuntime.isConfigured }
            .onChange(of: store.current.id) { _, _ in sheet = nil }
            .sheet(item: $sheet) { item in
                NavigationStack {
                    switch item {
                    case .area(let area, let stance): ProfileAreaEditor(area: area, stance: stance)
                    case .principle(let old): ProfilePrincipleEditor(original: old)
                    case .goal(let goal): GoalEditor(goal: goal, updateLabel: "修改消费观")
                    case .conversation: ProfileConversationView()
                    }
                }.environment(store).tint(YubaiColor.brandInk).appErrors().yubaiSheetBackground()
                    #if os(macOS)
                    .frame(minWidth: 540, minHeight: 600)
                    #endif
            }
    }
    private var memories: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: "余白记得的")
            Card(style: .list) {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    ForEach(Array(store.current.memories.sorted {
                        $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
                    }.prefix(2))) { note in
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                            Text(note.text).yubaiFont(YubaiFont.row)
                            Text(Dates.text(note.updatedAt) + " · " + note.source.label)
                                .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }
                    }
                    NavigationLink { MemoryView() } label: {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text("全部 \(store.current.memories.count) 条").yubaiFont(YubaiFont.row)
                            Spacer(minLength: YubaiSpace.space8)
                            Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                    }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openMemories")
                }
            }
        }
    }
    private var chatRow: some View {
        Card(style: .list, background: canChat ? YubaiColor.brandTint : YubaiColor.amberTint) {
            HStack(spacing: YubaiSpace.gapGroup) {
                AssistantMark(size: YubaiSpace.insetCard, color: canChat ? YubaiColor.brand : YubaiColor.amberDot)
                Text("和余白聊聊").yubaiFont(YubaiFont.rowTitle)
                Spacer()
                if !canChat {
                    Text(!configured ? "还没配密钥" : (!store.preferences.cloudAIEnabled ? "云端智能没开" : "模型不可用")).yubaiFont(YubaiFont.caption)
                }
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta)
            }.foregroundStyle(canChat ? YubaiColor.brandTintStrong : YubaiColor.amberInk).frame(minHeight: YubaiSize.rowDouble)
        }
    }
    @ViewBuilder private var savings: some View {
        ForEach(store.current.goals) { goal in
            Button { sheet = .goal(goal) } label: {
                Card(style: .compact) { VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text("为 " + goal.title + " 存").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    Text(store.preferences.hideAmounts ? "••••" : Money.text(goal.reserved, currency: false) + " / " + Money.text(goal.target, currency: false)).yubaiFont(YubaiFont.amountCard)
                } }
            }.buttonStyle(PressButtonStyle())
        }
    }
    private func areas(_ rows: [ProfileArea], stance: ProfileStance, title: String) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: title)
            if rows.isEmpty {
                Card {
                    Button { sheet = .area(ProfileArea(title: ""), stance) } label: {
                        Label("添加", systemImage: "plus").yubaiFont(YubaiFont.row)
                            .frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle)
                            .overlay { RoundedRectangle(cornerRadius: YubaiRadius.control).stroke(YubaiColor.borderDashed, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                            .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
                    }.buttonStyle(PressButtonStyle()).accessibilityLabel("添加" + title)
                }
            } else {
                CardRows(rows) { area in
                    areaRow(area, stance: stance)
                }
            }
            if editing && !rows.isEmpty { Button("添加" + title) { sheet = .area(ProfileArea(title: ""), stance) }.frame(minHeight: YubaiSize.tapMin) }
        }
    }
    private func areaRow(_ area: ProfileArea, stance: ProfileStance) -> some View {
        HStack(alignment: .top, spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(area.title).yubaiFont(YubaiFont.rowTitle)
                if showsNote(area, stance: stance) {
                    Text(area.note).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                }
                if stance == .restrain { areaUsage(area) }
            }
            Spacer(minLength: YubaiSpace.none)
            if editing { Menu {
                Button("编辑") { sheet = .area(area, stance) }
                Button("删掉") {
                    edit { $0.generous.removeAll { $0.id == area.id }; $0.restrain.removeAll { $0.id == area.id } }
                }
            } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("编辑或删除" + area.title) }
        }.padding(.vertical, YubaiSpace.space8)
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
    @ViewBuilder private func areaUsage(_ area: ProfileArea) -> some View {
        if !store.preferences.hideAmounts {
            Text(usage(area)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            if let progress = progress(area) {
                SavingProgressBar(ratio: progress, amber: progress >= 0.8, showsOvershoot: true).accessibilityLabel(area.title + " · " + usage(area))
            }
        }
    }
    private func progress(_ area: ProfileArea) -> Double? {
        RestrainProgress.current(ledger: store.current).first { $0.areaID == area.id }?.ratio
    }
    private func usage(_ area: ProfileArea) -> String {
        let value = area.usage(in: store.current)
        let count = area.softLimit?.perWeekCount.map { "本周第 \(value.weekCount) 次 · 你写的最多 \($0) 次" } ?? "本周 \(value.weekCount) 次"
        let amount = area.softLimit?.perMonthAmount.map { "本月 " + Money.text(value.monthAmount) + " · 你写的最多 " + Money.text($0) } ?? "本月 " + Money.text(value.monthAmount)
        return count + " · " + amount
    }
    private var principles: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: "原则")
            ForEach(profile.principles, id: \.self) { text in
                principleCard(text)
            }
            Button("添加原则") { sheet = .principle(nil) }.accessibilityIdentifier("addPrinciple")
        }
    }
    private func principleCard(_ text: String) -> some View {
        Card {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(text).yubaiFont(YubaiFont.body)
                Spacer(minLength: YubaiSpace.none)
                Menu {
                    Button("编辑") { sheet = .principle(text) }
                    Button("删掉") { edit { $0.principles.removeAll { $0 == text } } }
                } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("编辑或删除原则：" + text)
            }
        }
    }
    private var goals: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: "在存钱")
            CardRows(store.current.goals) { goal in
                goalRow(goal)
            }
            Button("添加存钱的事") { sheet = .goal(nil) }
        }
    }
    private func goalRow(_ goal: Goal) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("为 " + goal.title + " 存").yubaiFont(YubaiFont.rowTitle)
                Text("已存 " + Money.text(goal.reserved) + " / " + Money.text(goal.target)).yubaiFont(YubaiFont.amountSmall)
                if let date = goal.dueDate { Text("期待在 " + Dates.text(date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                if !goal.note.isEmpty { Text(goal.note).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            }
            Spacer(minLength: YubaiSpace.none)
            Menu {
                Button("调整存钱") { sheet = .goal(goal) }
                Button("删掉") { store.update("修改消费观") { $0.goals.removeAll { $0.id == goal.id } } }
            } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("调整或移除" + goal.title)
        }.padding(.vertical, YubaiSpace.space8)
    }
    private var habits: some View {
        let lines = ProfileHabits.summary(store.current)
        return VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            SectionHeading(title: "你常花的", meta: "近 90 天")
            if lines.isEmpty {
                Card {
                    VStack(spacing: YubaiSpace.gapGroup) {
                        ForEach(0..<3) { index in
                            HStack(spacing: YubaiSpace.gapGroup) {
                                DashedPlaceholder().frame(width: YubaiSize.rowDouble)
                                DashedPlaceholder().frame(maxWidth: .infinity).padding(.trailing, CGFloat(index) * YubaiSpace.gapSection)
                            }
                        }
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel("近 90 天没有消费记录")
            }
            if !lines.isEmpty {
                CardRows(lines) { line in
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        HStack(spacing: YubaiSpace.gapGroup) { Text(line.title).yubaiFont(YubaiFont.rowTitle); Pill(text: line.kind == .category ? "分类" : "商户", variant: .neutral) }
                        Text(store.preferences.hideAmounts ? "••••" : "共 " + Money.text(line.total) + " · 每周 " + String(format: "%.1f", line.countPerWeek) + " 次 · 平均 " + Money.text(line.average))
                            .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    }.padding(.vertical, YubaiSpace.space8)
                }
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
                TextField("名称", text: $title)
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
                title = area.title; categories = Set(area.match.categories.map { store.current.resolveCategory($0) })
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
    var body: some View {
        Form {
            Section("提醒") {
                TextField("提醒", text: $text, axis: .vertical).accessibilityIdentifier("principleText")
                SuggestionChips(values: ["超过 2,000 等 48 小时", "每天用得上的，愿意多花", "买之前先看看家里有没有"]) { text = $0 }
            }
        }
            .editorForm().navigationTitle("原则").yubaiNavigation()
            .onAppear { text = original ?? "" }
            .manualSheetHeader("原则", actionTitle: "保存", enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               actionIdentifier: "savePrinciple", action: {
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
