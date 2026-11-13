import SwiftUI
import YubaiCore

private func partShare(_ value: Int) -> String {
    let names = ["零", "一", "两", "三", "四", "五", "六", "七", "八", "九", "十"]
    return (names.indices.contains(value) ? names[value] : String(value)) + "成"
}


/// 现在 · 预算：想管住某一类花销时只给那几类设数，其余都在「没分的」里。分类预算是个打算，不是红线。
struct BudgetView: View {
    var initialCategory: String? = nil
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var newName = ""
    @State private var categoryPart: SpendingPart?
    @State private var amountPart: SpendingPart?
    @State private var keypad = EntryKeypad()
    @State private var proposal: [SpendingPart]?
    @State private var manual = false
    @State private var openedCategory = false
    @State private var addedPart: SpendingPart?
    private var budget: Int64 { store.pace?.budget ?? store.funds.available }

    var body: some View {
        let parts = store.current.spendingParts
        let suggested = proposal ?? []
        Page(spacing: YubaiSpace.gapGroup, topPadding: YubaiSpace.gapGroup) {
            if parts.isEmpty && !manual {
                EmptyState(.budget, actionIdentifier: "addBudgetPart", onAction: { newName = ""; manual = true; if suggested.isEmpty { adding = true } })
            } else if parts.isEmpty && !suggested.isEmpty { proposalContent(suggested) }
            else { regularContent }
        }.amountPrivacy(store.preferences.hideAmounts).accessibilityIdentifier("spendingPartsPage")
            .navigationTitle("预算").yubaiNavigation()
            .sheet(isPresented: $adding, onDismiss: { categoryPart = addedPart; addedPart = nil }) { newPartSheet }
            .sheet(item: $categoryPart) { part in categorySheet(part) }
            .sheet(item: $amountPart) { part in amountSheet(part) }
            .onAppear {
                guard !openedCategory, let category = initialCategory else { return }
                openedCategory = true; manual = true
                let part = store.current.spendingParts.first { $0.categories.contains(category) }
                    ?? SpendingPart(name: Classification.displayCategory(category), amount: 0, categories: [category])
                keypad = EntryKeypad(amount: part.amount ?? 0); amountPart = part
            }
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
                        Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator).accessibilityHidden(true)
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
            Text(part.name).yubaiFont(YubaiFont.rowTitle).lineLimit(1).truncationMode(.tail)
            Text(part.categories.map { Classification.displayCategory($0) }.joined(separator: "、")).yubaiFont(YubaiFont.meta)
                .foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private func unassignedRow(text: String, over: Bool) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text("没分的").yubaiFont(YubaiFont.row)
            Spacer(minLength: YubaiSpace.space8)
            Text((over ? "多 " : "剩 ") + text).yubaiFont(YubaiFont.amountSummary).fixedSize(horizontal: false, vertical: true)
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
                        Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator).accessibilityHidden(true)
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
                    ProgressLine(value: over ? 1 : progress, tint: over ? YubaiColor.neutralStrong : YubaiColor.brand, track: YubaiColor.neutralSoft, height: YubaiSize.unknownDot)
                    leftText(value, hide: hide)
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    ProgressLine(value: over ? 1 : progress, tint: over ? YubaiColor.neutralStrong : YubaiColor.brand, track: YubaiColor.neutralSoft, height: YubaiSize.unknownDot)
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
            store.update("预算") { ledger in
                if let index = ledger.spendingParts.firstIndex(where: { $0.id == part.id }) { ledger.spendingParts[index].amount = cents }
                else { var added = part; added.amount = cents; ledger.spendingParts.append(added) }
                ledger.partsMode = .amount
            }
            amountPart = nil
        }).presentationDragIndicator(.visible).yubaiSheetBackground()

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
    private var newPartSheet: some View {
        NavigationStack {
            Page(topPadding: YubaiSpace.space8) {
                Card(style: .list) { CardTextFieldRow(title: "名字", text: $newName, identifier: "budgetPartName", autofocus: true) }
            }.manualSheetHeader("加一项", actionTitle: "好", enabled: !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && newName.count <= 100,
                                actionIdentifier: "saveBudgetPart", cancel: { adding = false }, action: addPart)
        }.environment(store).yubaiSheetBackground().presentationDetents([.medium, .large])
    }
    private func addPart() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let part = SpendingPart(name: name, amount: 0)
        if store.update("预算", showToast: false, { $0.spendingParts.append(part) }) { addedPart = part; adding = false }
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
