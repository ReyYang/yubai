import SwiftUI
import YubaiCore

private func partShare(_ value: Int) -> String {
    let names = ["零", "一", "两", "三", "四", "五", "六", "七", "八", "九", "十"]
    return (names.indices.contains(value) ? names[value] : String(value)) + "成"
}

extension YubaiFont {
    static let partBalance = Style(size: 14, lineHeight: 20, weight: .semibold, family: .num, relativeTo: .footnote)
}

/// 算式页下方那块：预算一览。只给想管的几类设了数才有；「改」进预算页。
struct SpendingPartsCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let hide = store.preferences.hideAmounts
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            heading
            if !store.current.spendingParts.isEmpty { card(SpendingParts.summary(store.current), hide: hide) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("spendingPartsCard")
    }
    private var heading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("预算").yubaiFont(YubaiFont.caption, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
            Spacer(minLength: YubaiSpace.space8)
            TabNavigationLink(.budget) { BudgetView() } label: {
                HStack(spacing: YubaiSpace.space4) {
                    Text("改")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget(alignment: .trailing)
            }.buttonStyle(PressButtonStyle()).accessibilityLabel("改预算").accessibilityIdentifier("openSpendingParts")
        }.padding(.horizontal, YubaiSpace.insetCard)
    }
    private func card(_ summary: SpendingPartsSummary, hide: Bool) -> some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                ForEach(summary.parts) { value in
                    row(name: value.part.name, remaining: value.remaining, overflow: value.overflow, allowance: value.allowance, hide: hide)
                }
                row(name: "没分的", remaining: max(0, summary.unassigned), overflow: max(0, -summary.unassigned), allowance: nil, hide: hide)
            }
        }.accessibilityElement(children: .contain)
    }
    private func row(name: String, remaining: Int64, overflow: Int64, allowance: Int64?, hide: Bool) -> some View {
        let over = overflow > 0
        let progress = allowance.map { $0 > 0 ? Double(remaining) / Double($0) : 0 } ?? 1
        let value = over ? overflow : remaining
        let prefix: String = over ? "多 " : "剩 "
        let limit: String = allowance.map { " / " + amount2($0, hide: hide) } ?? ""
        let amountText: String = prefix + amount2(value, hide: hide) + limit
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            Text(name).yubaiFont(YubaiFont.row).frame(minWidth: 56, alignment: .leading)
            ProgressLine(value: over || allowance == nil ? 1 : progress, tint: over || allowance == nil ? YubaiColor.neutralStrong : YubaiColor.brand,
                         track: YubaiColor.neutralSoft, height: 6)
            Text(amountText).yubaiFont(YubaiFont.partBalance).fixedSize(horizontal: true, vertical: false)
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle, alignment: .leading)
            .accessibilityElement(children: .ignore).accessibilityLabel(name + (over ? "，多花" : "，剩余") + amount2(value, hide: hide))
    }
}

/// 旧入口保留：设置里还在用。内容就是预算页。
struct SpendingPartsView: View {
    var backTitle = "账本"
    var body: some View { BudgetView() }
}

/// 现在 · 预算：想管住某一类花销时只给那几类设数，其余都在「没分的」里。分类预算是个打算，不是红线。
struct BudgetView: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var newName = ""
    @State private var categoryPart: SpendingPart?
    @State private var amountPart: SpendingPart?
    @State private var keypad = EntryKeypad()
    @State private var proposal: [SpendingPart]?
    @State private var manual = false
    private var budget: Int64 { store.pace?.budget ?? store.funds.available }

    var body: some View {
        let parts = store.current.spendingParts
        let suggested = proposal ?? []
        Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.gapGroup) {
            if parts.isEmpty && !manual && !suggested.isEmpty { proposalContent(suggested) } else { regularContent }
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("spendingPartsPage")
            .navigationTitle("预算").yubaiNavigation()
            .alert("加一项", isPresented: $adding) {
                TextField("", text: $newName).accessibilityLabel("名字")
                Button("取消", role: .cancel) {}
                Button("好", action: addPart).disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newName.count > 100)
            }
            .sheet(item: $categoryPart) { part in categorySheet(part) }
            .sheet(item: $amountPart) { part in amountSheet(part) }
            .task(id: store.ledgerRevision) {
                guard store.current.spendingParts.isEmpty else { proposal = nil; return }
                let ledger = store.current
                let value = await Task.detached { SpendingParts.proposal(ledger: ledger, now: Date()) }.value
                guard !Task.isCancelled else { return }
                proposal = value
            }
    }

    // MARK: 第一次分预算
    private func proposalContent(_ suggested: [SpendingPart]) -> some View {
        let hide = store.preferences.hideAmounts
        let used = suggested.reduce(Int64(0)) { $0 + ($1.amount ?? 0) }
        let start = store.formula.cycleStart
        let first = Dates.calendar.component(.month, from: Dates.addMonths(-3, to: start))
        let last = Dates.calendar.component(.month, from: Dates.addMonths(-1, to: start))
        return VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            HStack(alignment: .firstTextBaseline) {
                Text("按前三个月的花法").yubaiFont(YubaiFont.caption, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                Spacer(minLength: YubaiSpace.space8)
                Text("\(first) 月 – \(last) 月").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.padding(.horizontal, YubaiSpace.insetCard)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(suggested) { part in
                        partTitleRow(part, trailing: amount2(part.amount ?? 0, hide: hide)).accessibilityIdentifier("startPart_" + part.name)
                        Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true)
                    }
                    unassignedRow(text: amount2(max(0, budget - used), hide: hide), over: false)
                }
            }
            Button("就这样分") { accept(suggested) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("acceptProposal")
            Button("自己分") { manual = true }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("splitMyself")
        }
    }
    private func partTitleRow(_ part: SpendingPart, trailing: String) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            partTitle(part)
            Spacer(minLength: YubaiSpace.space8)
            Text(trailing).yubaiFont(YubaiFont.amountSummary).fixedSize(horizontal: true, vertical: false)
        }.padding(.vertical, YubaiSpace.space8).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
    }
    private func partTitle(_ part: SpendingPart) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(part.name).yubaiFont(YubaiFont.rowTitle)
            Text(part.categories.map { Classification.displayCategory($0) }.joined(separator: "、")).yubaiFont(YubaiFont.meta)
                .foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private func unassignedRow(text: String, over: Bool) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text("没分的").yubaiFont(YubaiFont.row)
            Spacer(minLength: YubaiSpace.space8)
            Text((over ? "多 " : "剩 ") + text).yubaiFont(YubaiFont.amountSummary).fixedSize(horizontal: true, vertical: false)
        }.foregroundStyle(YubaiColor.labelSecondary).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
    }
    private func accept(_ suggested: [SpendingPart]) {
        store.update("预算", showToast: false) { ledger in
            ledger.spendingParts = suggested
            ledger.partsMode = .amount
        }
    }

    // MARK: 预算
    private var regularContent: some View {
        let summary = SpendingParts.summary(store.current)
        let hide = store.preferences.hideAmounts
        return VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            VStack(spacing: YubaiSpace.none) {
                Text("这个周期能花").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: budget, hide: hide, role: .display, currency: true)
            }.frame(maxWidth: .infinity).padding(.bottom, YubaiSpace.space4).accessibilityElement(children: .combine)
                .accessibilityIdentifier("budgetTotal")
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(summary.parts) { value in
                        partRow(value, hide: hide)
                        Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true)
                    }
                    unassignedRow(text: amount2(abs(summary.unassigned), hide: hide), over: summary.unassigned < 0)
                }
            }
            Button { newName = ""; adding = true } label: {
                HStack(spacing: YubaiSpace.space8) { Image(systemName: "plus").accessibilityHidden(true); Text("加一项") }
            }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("addBudgetPart")
        }
    }
    private func partRow(_ value: SpendingPartBalance, hide: Bool) -> some View {
        let part = value.part
        let over = value.overflow > 0
        let progress = value.allowance > 0 ? Double(value.remaining) / Double(value.allowance) : 0
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.gapGroup) { titleButton(part); Spacer(minLength: YubaiSpace.space8); amountControl(part, hide: hide) }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { titleButton(part); amountControl(part, hide: hide) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    ProgressLine(value: over ? 1 : progress, tint: over ? YubaiColor.neutralStrong : YubaiColor.brand, track: YubaiColor.neutralSoft, height: 6)
                    leftText(value, hide: hide)
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    ProgressLine(value: over ? 1 : progress, tint: over ? YubaiColor.neutralStrong : YubaiColor.brand, track: YubaiColor.neutralSoft, height: 6)
                    leftText(value, hide: hide)
                }
            }
        }.padding(.vertical, YubaiSpace.space12).contentShape(Rectangle())
            .contextMenu { partMenu(part) }
            .accessibilityAction(named: "删掉") { remove(part) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("budgetPart_" + part.name)
    }
    private func leftText(_ value: SpendingPartBalance, hide: Bool) -> some View {
        let over = value.overflow > 0
        return HStack(spacing: YubaiSpace.space4) {
            Text(over ? "多" : "剩").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: over ? value.overflow : value.remaining, hide: hide, role: .small)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func titleButton(_ part: SpendingPart) -> some View {
        Button { categoryPart = part } label: {
            HStack(spacing: YubaiSpace.space8) {
                partTitle(part)
                if part.categories.isEmpty { Image(systemName: "plus").foregroundStyle(YubaiColor.brandInk).accessibilityHidden(true) }
            }.frame(minHeight: YubaiSize.tapMin, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(part.name + "，改分类").accessibilityIdentifier("budgetCategory_" + part.id.uuidString)
    }
    @ViewBuilder private func amountControl(_ part: SpendingPart, hide: Bool) -> some View {
        if store.current.partsMode == .amount {
            Button {
                keypad = EntryKeypad(amount: part.amount ?? 0); amountPart = part
            } label: {
                AmountLabel(cents: part.amount ?? 0, hide: hide, role: .summary)
                    .padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin)
                    .background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: YubaiRadius.control)).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityLabel(part.name + "的预算")
                .accessibilityIdentifier("budgetAmount_" + part.name)
        } else {
            Menu {
                let other = store.current.spendingParts.filter { $0.id != part.id }.compactMap(\.share).reduce(0, +)
                ForEach(1...10, id: \.self) { share in
                    Button(partShare(share)) { update(part) { $0.share = share } }.disabled(other + share > 10)
                        .accessibilityLabel("把" + part.name + "分为" + partShare(share))
                }
            } label: {
                Text(part.share.map(partShare) ?? "—").yubaiFont(YubaiFont.amountSummary)
                    .padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin)
                    .background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: YubaiRadius.control)).contentShape(Rectangle())
            }.accessibilityLabel(part.name + "的成数，" + (part.share.map(partShare) ?? "未分配"))
        }
    }
    @ViewBuilder private func partMenu(_ part: SpendingPart) -> some View {
        ForEach(part.categories, id: \.self) { category in
            Button("移出" + Classification.displayCategory(category)) { update(part) { $0.categories.removeAll { $0 == category } } }
        }
        Button("删掉", role: .destructive) { remove(part) }.accessibilityLabel("删掉" + part.name)
    }

    // MARK: 弹窗
    private func amountSheet(_ part: SpendingPart) -> some View {
        AmountEntrySheet(title: part.name, keypad: $keypad, primaryTitle: "好", canSave: keypad.amount != nil, save: {
            guard let cents = keypad.resolve() else { return }
            update(part) { $0.amount = cents }
            amountPart = nil
        }).presentationDragIndicator(.visible).yubaiSheetBackground()
            #if os(iOS)
            .presentationDetents([.height(520), .large])
            #endif
    }
    private func categorySheet(_ part: SpendingPart) -> some View {
        NavigationStack {
            Page(topPadding: YubaiSpace.space8) {
                CategoryPicker(income: false, style: .sections) { choice, addition in
                    if store.update("预算", showToast: false, { ledger in
                        if let addition { try addition.apply(to: &ledger) }
                        SpendingParts.assign(category: choice.category, to: part.id, in: &ledger)
                    }) { categoryPart = nil; return true }
                    return false
                }
            }.manualSheetHeader("分类", showsAction: false, cancel: { categoryPart = nil })
        }.environment(store).appErrors().yubaiSheetBackground().presentationDetents([.medium, .large])
    }

    // MARK: 改动
    private func addPart() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let part = SpendingPart(name: name, amount: 0)
        if store.update("预算", showToast: false, { $0.spendingParts.append(part) }) { categoryPart = part }
    }
    private func update(_ part: SpendingPart, _ edit: (inout SpendingPart) -> Void) {
        store.update("预算", showToast: false) { ledger in
            if let i = ledger.spendingParts.firstIndex(where: { $0.id == part.id }) { edit(&ledger.spendingParts[i]) }
        }
    }
    private func remove(_ part: SpendingPart) {
        store.update("预算", showToast: false) { ledger in
            ledger.spendingParts.removeAll { $0.id == part.id }; ledger.partCarry[part.id] = nil
        }
    }
}

/// Both entry forms keep the choice in their draft. Category reassignment is
/// committed with the entry, so cancelling either form leaves the ledger alone.
struct SpendingPartPicker: View {
    @Environment(AppStore.self) private var store
    let ledger: Ledger
    let category: String
    @Binding var partID: UUID?
    @Binding var remember: Bool
    var allowsRemember = true
    var body: some View {
        let summary = SpendingParts.summary(ledger)
        let selected = selectedPartID
        ScrollView {
            VStack(spacing: 12) {
                Text("花在哪一份").yubaiFont(YubaiFont.entrySheetTitle).frame(height: 32).padding(.top, 12)
                VStack(spacing: 0) {
                    ForEach(summary.parts) { value in
                        choice(value.part.name, id: value.id, remaining: value.remaining, selected: selected)
                        Rectangle().fill(YubaiColor.separator).frame(height: 1)
                    }
                    choice("没分的", id: nil, remaining: summary.unassigned, selected: selected)
                }.padding(.horizontal, 16).paperCardSurface(in: RoundedRectangle(cornerRadius: 22))
                if allowsRemember {
                    Toggle(Classification.displayCategory(category) + "以后都记到这份", isOn: $remember)
                        .yubaiFont(YubaiFont.body).tint(YubaiColor.brand).frame(minHeight: 52).padding(.horizontal, 16)
                        .paperCardSurface(in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityLabel(Classification.displayCategory(category) + "以后都记到选中的分项")
                }
            }.padding(.horizontal, 20).padding(.bottom, 34)
        }.paperBackground().yubaiSheetBackground().presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private var selectedPartID: UUID? {
        var sample = Entry(amount: 0, accountID: UUID(), title: category, category: category)
        sample.partID = partID
        return SpendingParts.part(for: sample, in: ledger)?.id
    }
    private func choice(_ name: String, id: UUID?, remaining: Int64, selected: UUID?) -> some View {
        Button { partID = id ?? SpendingPart.unassignedID } label: {
            HStack(spacing: 12) {
                Text(name).yubaiFont(YubaiFont.row, weight: selected == id ? .semibold : .regular)
                Spacer()
                Text("剩 " + (store.preferences.hideAmounts ? "••••" : Money.text(remaining, currency: false)))
                    .yubaiFont(YubaiFont.partBalance).foregroundStyle(YubaiColor.labelSecondary)
                Image(systemName: "checkmark").foregroundStyle(YubaiColor.brand).frame(width: 18).opacity(selected == id ? 1 : 0)
            }.frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(name + "，剩余" + (store.preferences.hideAmounts ? "金额已隐藏" : Money.text(remaining)))
            .accessibilityAddTraits(selected == id ? .isSelected : [])
    }
}
