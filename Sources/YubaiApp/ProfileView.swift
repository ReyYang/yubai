import SwiftUI
import YubaiCore

private enum ProfileSheet: Identifiable {
    case area(ProfileArea, ProfileStance), principle(String?), goal(Goal?), conversation
    var id: String { String(describing: self) }
}

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: ProfileSheet?
    @State private var floor = ""
    @State private var editing = false
    @State private var configured = IntelligenceRuntime.isConfigured
    private var profile: SpendingProfile { store.current.profile }
    private var empty: Bool { profile.generous.isEmpty && profile.restrain.isEmpty && profile.principles.isEmpty && profile.floorAmount == nil }
    private var canChat: Bool { configured && store.current.preferences.cloudAIEnabled }
    var body: some View {
        Page(topPadding: 8) {
            ForEach(store.current.pendingChanges.filter(\.isProfileOnly)) { change in
                ProfileProposalCard(change: change, confirm: { store.apply(change, label: "修改消费观") }, secondaryTitle: "不用了") {
                    store.update("修改消费观") { ledger in
                        ledger.pendingChanges.removeAll { $0.id == change.id }
                        for i in ledger.cards.indices where ledger.cards[i].action == .confirmChangeSet(change.id) { ledger.cards[i].dismissedAt = Date() }
                    }
                }
            }
            if empty {
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                        Text("慢慢知道，什么值得。").yubaiFont(YubaiFont.lead)
                        Text("这里留着你想怎样花钱。可以自己写，也可以和余白聊几句。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        if canChat { Button("和余白聊几句") { sheet = .conversation }.buttonStyle(PrimaryButtonStyle()) }
                    }
                }
            }
            if !canChat { Text("在设置中填写 DeepSeek 密钥并开启云端智能后，就能和余白聊几句。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            areas(profile.restrain, stance: .restrain, title: "想克制的")
            if editing {
                areas(profile.generous, stance: .generous, title: "愿意多花的")
                principles
                floorSection
                goals
            } else {
                if !profile.generous.isEmpty || !profile.principles.isEmpty {
                    SectionHeading(title: "愿意多花的 · 原则")
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 6) {
                                ForEach(profile.generous) { area in
                                    Text(area.title).yubaiFont(YubaiFont.callout).padding(.horizontal, 12).padding(.vertical, 6).background(YubaiColor.raised, in: Capsule())
                                }
                            }
                            ForEach(profile.principles, id: \.self) { text in Text(text).yubaiFont(YubaiFont.cardTitle) }
                        }
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) { savings }
                    VStack(alignment: .leading, spacing: 10) { savings }
                }
                NavigationLink {
                    Page { habits }.navigationTitle("你常花的").yubaiNavigation()
                } label: {
                    Card(style: .compact, background: YubaiColor.raised) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("你常花的 · 来自账本").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                            Text(habitSummary + " ›").yubaiFont(YubaiFont.row)
                        }
                    }
                }.buttonStyle(PressButtonStyle())
            }
        }.navigationTitle("我的消费观").yubaiNavigation()
            .toolbar { Button(editing ? "完成" : "编辑") { editing.toggle() }.frame(minHeight: 44).accessibilityIdentifier("editProfile") }
            .onAppear { configured = IntelligenceRuntime.isConfigured; loadFloor() }
            .onChange(of: store.current.profile.floorAmount) { _, _ in loadFloor() }
            .onChange(of: store.current.id) { _, _ in sheet = nil; loadFloor() }
            .sheet(item: $sheet) { item in
                NavigationStack {
                    switch item {
                    case .area(let area, let stance): ProfileAreaEditor(area: area, stance: stance)
                    case .principle(let old): ProfilePrincipleEditor(original: old)
                    case .goal(let goal): GoalEditor(goal: goal, updateLabel: "修改消费观")
                    case .conversation: ProfileConversationView()
                    }
                }.environment(store).tint(YubaiColor.brandInk).appErrors()
                    #if os(macOS)
                    .frame(minWidth: 540, minHeight: 600)
                    #endif
            }
    }
    private var habitSummary: String {
        if store.current.preferences.hideAmounts { return "金额已隐藏" }
        let lines = ProfileHabits.summary(store.current).filter { $0.kind == .category }.prefix(3)
        return lines.isEmpty ? "有了消费记录，再一起看看。" : lines.map { $0.title + " " + Money.text($0.total, currency: false) }.joined(separator: " · ")
    }
    @ViewBuilder private var savings: some View {
        if let floor = profile.floorAmount {
            Card(style: .compact) { VStack(alignment: .leading, spacing: 2) {
                Text("始终留着").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: floor, hide: store.current.preferences.hideAmounts, role: .card)
            } }
        }
        ForEach(store.current.goals) { goal in
            Button { sheet = .goal(goal) } label: {
                Card(style: .compact) { VStack(alignment: .leading, spacing: 2) {
                    Text("为" + goal.title + "存").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    Text(store.current.preferences.hideAmounts ? "••••" : Money.text(goal.reserved, currency: false) + " / " + Money.text(goal.target, currency: false)).yubaiFont(YubaiFont.amountCard)
                } }
            }.buttonStyle(PressButtonStyle())
        }
    }
    private func areas(_ rows: [ProfileArea], stance: ProfileStance, title: String) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: title)
            if rows.isEmpty { Text("还没有写下，想到时再添。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            CardRows(rows) { area in
                HStack(alignment: .top, spacing: YubaiSpace.space12) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                        Text(area.title).yubaiFont(YubaiFont.rowTitle)
                        if !area.note.isEmpty { Text(area.note).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
                        if stance == .restrain {
                            if let limit = area.softLimit, !limit.text.isEmpty { Text(limit.text).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted) }
                            if !store.current.preferences.hideAmounts {
                                Text(usage(area)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                                if let progress = progress(area) {
                                    ProgressView(value: progress).tint(YubaiColor.brand).accessibilityLabel(area.title + "柔性提醒进度")
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if editing { Menu {
                        Button("编辑") { sheet = .area(area, stance) }
                        Button("删除", role: .destructive) {
                            edit { $0.generous.removeAll { $0.id == area.id }; $0.restrain.removeAll { $0.id == area.id } }
                        }
                    } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("编辑或删除" + area.title) }
                }.padding(.vertical, YubaiSpace.space8)
            }
            if editing { Button("添加" + title) { sheet = .area(ProfileArea(title: ""), stance) }.frame(minHeight: 44) }
        }
    }
    private func progress(_ area: ProfileArea) -> Double? {
        let usage = area.usage(in: store.current)
        if let count = area.softLimit?.perWeekCount, count > 0 { return min(1, Double(usage.weekCount) / Double(count)) }
        if let amount = area.softLimit?.perMonthAmount, amount > 0 { return min(1, Double(usage.monthAmount) / Double(amount)) }
        return nil
    }
    private func usage(_ area: ProfileArea) -> String {
        let value = area.usage(in: store.current)
        let count = area.softLimit?.perWeekCount.map { "本周 \(value.weekCount) / \($0) 次" } ?? "本周 \(value.weekCount) 次"
        let amount = area.softLimit?.perMonthAmount.map { "本月 " + Money.text(value.monthAmount) + " / " + Money.text($0) } ?? "本月 " + Money.text(value.monthAmount)
        return count + " · " + amount
    }
    private var principles: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: "原则")
            ForEach(profile.principles, id: \.self) { text in
                Card {
                    HStack {
                        Text(text).yubaiFont(YubaiFont.body)
                        Spacer(minLength: 0)
                        Menu {
                            Button("编辑") { sheet = .principle(text) }
                            Button("删除", role: .destructive) { edit { $0.principles.removeAll { $0 == text } } }
                        } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("编辑或删除原则：" + text)
                    }
                }
            }
            Button("添加原则") { sheet = .principle(nil) }.accessibilityIdentifier("addPrinciple")
        }
    }
    private var goals: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: "想为什么存钱")
            CardRows(store.current.goals) { goal in
                HStack {
                    VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                        Text(goal.title).yubaiFont(YubaiFont.rowTitle)
                        Text("已留 " + Money.text(goal.reserved) + " / " + Money.text(goal.target)).yubaiFont(YubaiFont.amountSmall)
                        if let date = goal.dueDate { Text("期待在 " + Dates.text(date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                        if !goal.note.isEmpty { Text(goal.note).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("调整目标") { sheet = .goal(goal) }
                        Button("释放预留并移除", role: .destructive) { store.update("修改消费观") { $0.goals.removeAll { $0.id == goal.id } } }
                    } label: { Image(systemName: "ellipsis").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }.accessibilityLabel("调整或移除" + goal.title)
                }.padding(.vertical, YubaiSpace.space8)
            }
            Button("添加目标") { sheet = .goal(nil) }
        }
    }
    private var floorSection: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: "始终留着的底线")
            Card {
                VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                    TextField("底线金额（元）", text: $floor).numericInput().yubaiFont(YubaiFont.amountInput).accessibilityLabel("始终留着的底线金额")
                    Text("计算可动用时会先留出这笔钱").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)

                    Button("保存底线") {
                        do { let amount = try Money.parse(floor); edit { $0.floorAmount = amount } }
                        catch { store.error = error.localizedDescription }
                    }
                }
            }
        }
    }
    private var habits: some View {
        let lines = ProfileHabits.summary(store.current)
        return VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            SectionHeading(title: "你常花的", subtitle: "来自账本")
            Text("近 90 天 · 按消费金额排列，同额时看频次。分类与商户会重叠，金额不能相加。商户按账单原始名称归组。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            if lines.isEmpty { Text("有了消费记录，再一起看看。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
            CardRows(lines) { line in
                VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                    HStack { Text(line.title).yubaiFont(YubaiFont.rowTitle); Pill(text: line.kind == .category ? "分类" : "商户", variant: .neutral) }
                    Text("共 " + Money.text(line.total) + " · 每周 " + String(format: "%.1f", line.countPerWeek) + " 次 · 平均 " + Money.text(line.average)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }.padding(.vertical, YubaiSpace.space8)
            }
        }
    }
    private func loadFloor() { floor = Money.input(profile.floorAmount ?? 0) }
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
    @State private var keywords = ""
    @State private var note = ""
    @State private var weekly = ""
    @State private var monthly = ""
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                TextField("例如：外卖、学习、旅行", text: $title)
                TextField("说明（可选）", text: $note, axis: .vertical)
                TextField("关键词，用顿号或逗号分开", text: $keywords, axis: .vertical)
                Text("任一分类或关键词符合，就计入这个领域。关键词会查找标题、用途和备注。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
            Section("相关分类，可多选") {
                ForEach(store.current.categories.filter { !$0.income }) { category in
                    Toggle(category.name, isOn: Binding(get: { categories.contains(category.name) }, set: { value in
                        if value { categories.insert(category.name) } else { categories.remove(category.name) }
                    })).tint(YubaiColor.toggleOn)
                }
            }
            if stance == .restrain {
                Section("柔性提醒，可以留空") {
                    TextField("每周最多几次", text: $weekly).numericInput()
                    TextField("每月金额（元）", text: $monthly).numericInput()
                    Text("只是帮你留意，不是不能越过的规定。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }
            }
        }.editorForm().navigationTitle(stance == .restrain ? "想克制的" : "愿意多花的").yubaiNavigation()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                title = area.title; categories = Set(area.match.categories.map { store.current.resolveCategory($0) })
                keywords = area.match.keywords.joined(separator: "、"); note = area.note
                weekly = area.softLimit?.perWeekCount.map { String($0) } ?? ""; monthly = area.softLimit?.perMonthAmount.map { Money.input($0) } ?? ""
            }
    }
    private func save() {
        do {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw YubaiError.invalid("给这个领域起个名字吧。") }
            let countText = weekly.trimmingCharacters(in: .whitespacesAndNewlines)
            let count: Int? = countText.isEmpty ? nil : Int(countText)
            guard countText.isEmpty || count.map({ (0...10000).contains($0) }) == true else { throw YubaiError.invalid("每周次数请填 0 至 10,000 的整数。") }
            let amount: Int64? = monthly.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try Money.parse(monthly)
            let words = keywords.components(separatedBy: CharacterSet(charactersIn: "、,，\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            var updated = area; updated.title = clean; updated.note = note
            updated.match = AreaMatch(categories: categories.sorted(), keywords: words)
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
        Form { Section("给自己的一句提醒") { TextField("例如：超过 2,000 等 48 小时", text: $text, axis: .vertical).accessibilityIdentifier("principleText") } }
            .editorForm().navigationTitle("原则").yubaiNavigation()
            .onAppear { text = original ?? "" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    if store.update("修改消费观", { ledger in
                        let old = ledger.profile
                        if let original, let i = ledger.profile.principles.firstIndex(of: original) { ledger.profile.principles[i] = clean }
                        else { ledger.profile.principles.append(clean) }
                        ledger.profile.stamp(changedFrom: old, at: Date())
                    }) { dismiss() }
                }.accessibilityIdentifier("savePrinciple") }
            }
    }
}

struct ProfileProposalCard: View {
    @Environment(AppStore.self) private var store
    let change: ChangeSet
    let confirm: () -> Void
    let secondaryTitle: String
    let secondary: () -> Void
    var body: some View {
        ProposalCard(title: store.current.preferences.hideAmounts ? "等你核对的修改" : change.reason, lines: store.current.preferences.hideAmounts ? ["金额已隐藏，请显示金额后核对完整提案。"] : change.preview(in: store.current, showPreviousValues: true),
                     primaryTitle: "记下这些", secondaryTitle: secondaryTitle, canConfirm: !store.current.preferences.hideAmounts, confirm: confirm, cancel: secondary)
    }
}
