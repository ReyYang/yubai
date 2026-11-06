import SwiftUI
import YubaiCore

struct PurchaseQuestionsCard: View {
    let questions: [PurchaseQuestion]
    let busy: Bool
    let active: Bool
    let actionsID: String
    let dismissInput: () -> Void
    let selectionChanged: () -> Void
    let send: (String) -> Void
    let notes: [MemoryNote]
    @State private var selected: [Int: String] = [:]
    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                HStack(spacing: YubaiSpace.space8) {
                    AssistantMark(size: 14).accessibilityHidden(true)
                    Text("余白 · 该不该买").yubaiFont(YubaiFont.caption)
                }.foregroundStyle(YubaiColor.brandInk)
                ForEach(questions.indices, id: \.self) { index in
                    question(index)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) { actions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) { actions }
                }.lineLimit(1).id(actionsID)
                RememberedRows(notes: notes)
            }
        }.accessibilityIdentifier("purchaseQuestions")
            .onChange(of: selected) { _, _ in selectionChanged() }
    }
    @ViewBuilder private func question(_ index: Int) -> some View {
        if index > 0 { EntryFormDivider() }
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text(String(index + 1)).yubaiFont(YubaiFont.amount)
            Text(questions[index].text).yubaiFont(YubaiFont.body)
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { options(index) }
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) { options(index) }
        }
    }
    private var disabled: Bool { busy || !active }
    private var answerDisabled: Bool { selected.count != questions.count || disabled }
    private func options(_ index: Int) -> some View {
        ForEach(questions[index].options, id: \.self) { option in
            PurchaseOptionChip(option: option, chosen: selected[index] == option) {
                dismissInput()
                selected[index] = option
            }
                .disabled(disabled)
        }
    }
    private var actions: some View {
        Group {
            Button("就这样回答") { send(questions.indices.compactMap { selected[$0] }.joined(separator: " · ")) }
                .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(answerDisabled)
            Button("直接给结论") { send("直接给结论") }
                .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).disabled(disabled)
        }
    }
}

private struct PurchaseOptionChip: View {
    let option: String
    let chosen: Bool
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            Text(option).yubaiFont(YubaiFont.callout, weight: chosen ? .medium : .regular)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                .foregroundStyle(chosen ? YubaiColor.onBrand : YubaiColor.label)
                .background(chosen ? YubaiColor.brand : YubaiColor.raised, in: Capsule()).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

struct SavingPurchaseCard: View {
    @Environment(AppStore.self) private var store
    let purchase: PurchaseJudgment
    let verdict: SubmittedPurchaseVerdict?
    let evidence: [UUID]
    let notes: [MemoryNote]
    @State private var wishID: UUID?
    @State private var recording = false
    private var hidden: Bool { store.preferences.hideAmounts }
    private var assessment: PurchaseAssessment {
        store.purchaseAssessment(purchase)
    }
    private var conclusion: PurchaseVerdict { verdict?.verdict ?? assessment.verdict }
    private var reason: String { verdict?.reason ?? assessment.reason }
    private var ink: Color {
        switch conclusion { case .buy: YubaiColor.brandInk; case .wait: YubaiColor.amberInk; case .skip: YubaiColor.label }
    }
    private var moneyBound: Bool {
        purchase.facts["allowed_verdicts"]?.arrayValue?.compactMap(\.stringValue) == ["skip"]
    }
    private var boundReason: String { verdict?.boundReason ?? purchase.facts["bound_reason"]?.stringValue ?? assessment.reason }
    private var showsMoneyBound: Bool { moneyBound && !hidden }
    private var wishTitle: String {
        if wishID != nil { return "已放进心愿单" }
        if conclusion == .buy { return "先放进心愿单" }
        let days = Wishlist.defaultCooldownDays(amount: purchase.amount)
        return days == 0 ? "放进心愿单" : "放进心愿单 · \(days) 天后再问我"
    }
    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                heading
                Text(conclusion.label).yubaiFont(YubaiFont.lead).foregroundStyle(ink).accessibilityIdentifier("purchaseVerdict")
                Text(hidden ? "金额已隐藏" : reason).yubaiFont(YubaiFont.body)
                if showsMoneyBound { moneyBoundTag }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) { actions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) { actions }
                }.lineLimit(1).padding(.top, YubaiSpace.space8)
                EntryFormDivider()
                detailsLink
                RememberedRows(notes: notes)
            }
        }.sheet(isPresented: $recording) {
            NavigationStack { QuickEntryView(prefill: QuickEntryPrefill(category: purchase.category, amount: purchase.amount, purpose: purchase.title)) }
                .environment(store).appErrors().yubaiSheetBackground()
        }
    }
    private var heading: some View {
        HStack(spacing: YubaiSpace.space8) {
            AssistantMark(size: 14).accessibilityHidden(true)
            Text("余白 · " + purchase.title).yubaiFont(YubaiFont.caption)
            AmountLabel(cents: purchase.amount, hide: hidden, role: .small)
        }.foregroundStyle(YubaiColor.brandInk)
    }
    private var moneyBoundTag: some View {
        Text(boundReason).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
            .padding(.horizontal, YubaiSpace.space8).padding(.vertical, YubaiSpace.space4)
            .background(YubaiColor.amberTint, in: Capsule())
    }
    private var detailsLink: some View {
        NavigationLink { PurchaseDetailsView(purchase: purchase, evidence: evidence) } label: {
            HStack(spacing: YubaiSpace.space8) {
                Text(detailsTitle).multilineTextAlignment(.leading)
                Spacer(minLength: YubaiSpace.none)
                Image(systemName: "chevron.right")
            }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("answerEvidence")
    }
    private var detailsTitle: String {
        guard !hidden else { return "明细" }
        let after = purchase.facts["affordability"]?["available_after_purchase"]?["text"]?.stringValue
        return "明细" + (after.map { " · 买了以后还能花 " + $0 } ?? " · \(evidence.count) 笔")
    }
    @ViewBuilder private var actions: some View {
        if conclusion == .buy {
            Button("买了，记一笔") { recording = true }.buttonStyle(PrimaryButtonStyle(compact: true))
            Button(wishTitle, action: saveWish).buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).disabled(wishID != nil)
        } else {
            Button(wishTitle, action: saveWish).buttonStyle(PrimaryButtonStyle(compact: true)).disabled(wishID != nil)
            Button("我还是要买") { recording = true }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
        }
    }
    private func saveWish() {
        guard wishID == nil else { return }
        let submitted = verdict ?? SubmittedPurchaseVerdict(verdict: conclusion, reason: reason, need: .unclear, boundReason: assessment.reason)
        var addedID: UUID?
        if store.update("加入心愿单", showToast: false, { ledger in
            addedID = try Wishlist.add(fromVerdict: submitted, title: purchase.title, amount: purchase.amount, category: purchase.category,
                                     subcategory: purchase.subcategory, in: &ledger).id
        }) { wishID = addedID }
    }
}

private struct PurchaseDetailsView: View {
    @Environment(AppStore.self) private var store
    let purchase: PurchaseJudgment
    let evidence: [UUID]
    private var affordability: String? {
        purchase.facts["affordability"]?["available_after_purchase"]?["text"]?.stringValue.map { "买了以后还能花 " + $0 }
    }
    private var habit: String? {
        purchase.facts["habit"]?["average"]?["text"]?.stringValue.map { "过去 90 天，同类消费平均一次 " + $0 }
    }
    private var values: JSONValue? { purchase.facts["values"] }
    private var principles: [JSONValue] { values?["principles"]?.arrayValue ?? [] }
    private var evidenceRows: [Entry] { store.evidenceEntries(Set(evidence), activeOnly: true) }
    var body: some View {
        Page {
            Card {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    fact("付得起吗", affordability)
                    fact("和你平时比", habit)
                    SectionHeading(title: "和你在乎的比")
                    ForEach(Array(principles.enumerated()), id: \.offset) { _, row in
                        if let text = row["text"]?.stringValue ?? row.stringValue { quote(text) }
                    }
                    ForEach(["generous", "restrain"], id: \.self) { key in
                        areaQuotes(key)
                    }
                }
            }
            CardRows(evidenceRows) { entry in EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts) }
        }.navigationTitle("明细").yubaiNavigation()
    }
    private func areaQuotes(_ key: String) -> some View {
        let rows: [JSONValue] = values?[key]?.arrayValue ?? []
        return ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            if let text = row["quote"]?.stringValue, !text.isEmpty { quote(text) }
            else if let title = row["title"]?.stringValue { quote(title) }
        }
    }
    private func fact(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            Text(store.preferences.hideAmounts ? "金额已隐藏" : value ?? "没有记录").yubaiFont(YubaiFont.body)
        }
    }
    private func quote(_ text: String) -> some View {
        Text(store.preferences.hideAmounts ? "金额已隐藏" : "你写过「" + text + "」").yubaiFont(YubaiFont.body)
    }
}
