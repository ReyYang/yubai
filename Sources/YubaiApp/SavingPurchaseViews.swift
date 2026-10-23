import SwiftUI
import YubaiCore

struct PurchaseQuestionsCard: View {
    let questions: [PurchaseQuestion]
    let busy: Bool
    let active: Bool
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
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) { actions }
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) { actions }
                }
                RememberedRows(notes: notes)
            }
        }.accessibilityIdentifier("purchaseQuestions")
    }
    private func options(_ index: Int) -> some View {
        ForEach(questions[index].options, id: \.self) { option in
            let chosen = selected[index] == option
            Button { selected[index] = option } label: {
                Text(option).yubaiFont(YubaiFont.callout, weight: chosen ? .medium : .regular)
                    .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                    .foregroundStyle(chosen ? YubaiColor.onBrand : YubaiColor.label)
                    .background(chosen ? YubaiColor.brand : YubaiColor.raised, in: Capsule()).yubaiHitTarget()
            }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(chosen ? .isSelected : []).disabled(busy || !active)
        }
    }
    private var actions: some View {
        Group {
            Button("就这样回答") { send(questions.indices.compactMap { selected[$0] }.joined(separator: " · ")) }
                .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(selected.count != questions.count || busy || !active)
            Button("直接给结论") { send("直接给结论") }
                .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).disabled(busy || !active)
        }
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
    private var hidden: Bool { store.current.preferences.hideAmounts }
    private var assessment: PurchaseAssessment {
        Finance.assessPurchase(store.current, amount: purchase.amount, title: purchase.title, category: purchase.category, subcategory: purchase.subcategory)
    }
    private var conclusion: PurchaseVerdict { verdict?.verdict ?? assessment.verdict }
    private var reason: String { verdict?.reason ?? assessment.reason }
    private var ink: Color {
        switch conclusion { case .buy: YubaiColor.brandInk; case .wait: YubaiColor.amberInk; case .skip: YubaiColor.label }
    }
    private var moneyBound: Bool {
        purchase.facts["allowed_verdicts"]?.arrayValue?.compactMap(\.stringValue) == ["skip"]
    }
    private var wishTitle: String {
        if wishID != nil { return "已放进心愿单" }
        if conclusion == .buy { return "先放进心愿单" }
        let days = Wishlist.defaultCooldownDays(amount: purchase.amount)
        return days == 0 ? "放进心愿单" : "放进心愿单 · \(days) 天后再问我"
    }
    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(spacing: YubaiSpace.space8) {
                    AssistantMark(size: 14).accessibilityHidden(true)
                    Text("余白 · " + purchase.title).yubaiFont(YubaiFont.caption)
                    AmountLabel(cents: purchase.amount, hide: hidden, role: .small)
                }.foregroundStyle(YubaiColor.brandInk)
                Text(conclusion.label).yubaiFont(YubaiFont.lead).foregroundStyle(ink).accessibilityIdentifier("purchaseVerdict")
                Text(hidden ? "金额已隐藏" : reason).yubaiFont(YubaiFont.body)
                if moneyBound, !hidden {
                    Text(verdict?.boundReason ?? purchase.facts["bound_reason"]?.stringValue ?? assessment.reason)
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
                        .padding(.horizontal, YubaiSpace.space8).padding(.vertical, YubaiSpace.space4)
                        .background(YubaiColor.amberTint, in: Capsule())
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) { actions }
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) { actions }
                }.padding(.top, YubaiSpace.space8)
                EntryFormDivider()
                NavigationLink {
                    PurchaseDetailsView(purchase: purchase, evidence: evidence)
                } label: {
                    HStack(spacing: YubaiSpace.space8) {
                        Text(detailsTitle).multilineTextAlignment(.leading)
                        Spacer(minLength: YubaiSpace.none)
                        Image(systemName: "chevron.right")
                    }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).frame(minHeight: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("answerEvidence")
                RememberedRows(notes: notes)
            }
        }.sheet(isPresented: $recording) {
            NavigationStack { QuickEntryView(prefill: QuickEntryPrefill(category: purchase.category, amount: purchase.amount, purpose: purchase.title)) }
                .environment(store).appErrors()
        }
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
    var body: some View {
        Page {
            Card {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    fact("付得起吗", purchase.facts["affordability"]?["available_after_purchase"]?["text"]?.stringValue.map { "买了以后还能花 " + $0 })
                    fact("和你平时比", purchase.facts["habit"]?["average"]?["text"]?.stringValue.map { "过去 90 天，同类消费平均一次 " + $0 })
                    let values = purchase.facts["values"]
                    let principles = values?["principles"]?.arrayValue ?? []
                    SectionHeading(title: "和你在乎的比")
                    ForEach(Array(principles.enumerated()), id: \.offset) { _, row in
                        if let text = row["text"]?.stringValue ?? row.stringValue { quote(text) }
                    }
                    ForEach(["generous", "restrain"], id: \.self) { key in
                        ForEach(Array((values?[key]?.arrayValue ?? []).enumerated()), id: \.offset) { _, row in
                            if let text = row["quote"]?.stringValue, !text.isEmpty { quote(text) }
                            else if let title = row["title"]?.stringValue { quote(title) }
                        }
                    }
                }
            }
            let rows = store.sortedEntries.filter { evidence.contains($0.id) && $0.deletedAt == nil }
            CardRows(rows) { entry in EntryLink(entry: entry, hideAmount: store.current.preferences.hideAmounts) }
        }.navigationTitle("明细").yubaiNavigation()
    }
    private func fact(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            Text(store.current.preferences.hideAmounts ? "金额已隐藏" : value ?? "没有记录").yubaiFont(YubaiFont.body)
        }
    }
    private func quote(_ text: String) -> some View {
        Text(store.current.preferences.hideAmounts ? "金额已隐藏" : "你写过「" + text + "」").yubaiFont(YubaiFont.body)
    }
}
