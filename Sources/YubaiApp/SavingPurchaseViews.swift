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
                    AssistantMark(size: YubaiFont.row.size).accessibilityHidden(true)
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
    @State private var recordingFromReserve = false
    @State private var waitHours = 0
    private var hidden: Bool { store.preferences.hideAmounts }
    private var assessment: PurchaseAssessment { store.purchaseAssessment(purchase) }
    private var conclusion: PurchaseVerdict { verdict?.verdict ?? assessment.verdict }
    private var reason: String { verdict?.reason ?? assessment.reason }
    private var available: Int64 { store.funds.available }
    private var availableAfter: Int64 { available - purchase.amount }
    private var reserve: Int64 { max(0, store.current.fixedSavingsTotal()) }
    private var monthEnough: Bool { availableAfter >= 0 }
    private var reserveEnough: Bool { purchase.amount <= reserve }
    private var headline: String {
        if hidden { return "金额已隐藏" }
        if monthEnough { return "这个月的钱够。" }
        return reserveEnough ? "这个月的钱不够，存着的钱够。" : "这个月的钱不够，存着的钱也不够。"
    }
    private var equivalentDays: Int? {
        let base = store.pace?.baseDaily ?? 0
        let ref = base > 0 ? base : Finance.estimatedDailyLiving(store.current, now: Date())
        guard ref > 0 else { return nil }
        return max(1, Int((Double(purchase.amount) / Double(ref)).rounded()))
    }
    private var wishTitle: String { wishID != nil ? "已放进心愿单" : "放进心愿单" }
    var body: some View {
        AssistantCard {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("余白").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                Text(headline).yubaiFont(YubaiFont.lead).accessibilityIdentifier("purchaseVerdict")
                    .accessibilityLabel(conclusion.label + "，" + headline)
                NavigationLink { PurchaseDetailsView(purchase: purchase, evidence: evidence) } label: {
                    numberRow("还能花", from: available, to: availableAfter)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("answerEvidence")
                EntryFormDivider()
                numberRow("存着的钱", from: reserve, to: reserve - purchase.amount)
                EntryFormDivider()
                daysRow
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) { actions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) { actions }
                }.lineLimit(1).padding(.top, YubaiSpace.space8)
                RememberedRows(notes: notes)
            }
        }.sheet(isPresented: $recording) {
            NavigationStack {
                QuickEntryView(prefill: QuickEntryPrefill(category: purchase.category, amount: purchase.amount, purpose: purchase.title,
                                                          fromReserve: recordingFromReserve))
            }.environment(store).appErrors().yubaiSheetBackground()
        }
        .task(id: "\(purchase.amount):" + store.profile.principles.joined(separator: "\n")) {
            waitHours = Wishlist.cooldownHours(amount: purchase.amount, fromPrinciples: store.profile.principles)
        }
    }
    private func numberRow(_ title: String, from: Int64, to: Int64) -> some View {
        AnswerComparisonRow(title: title, before: from, after: to, hide: hidden)
    }
    @ViewBuilder private var daysRow: some View {
        if let days = equivalentDays {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text("约等于日常").yubaiFont(YubaiFont.row)
                Spacer(minLength: YubaiSpace.space8)
                Text("\(days) 天").yubaiFont(YubaiFont.amount)
            }.frame(minHeight: YubaiSize.rowSingle).accessibilityElement(children: .combine)
        }
    }
    @ViewBuilder private var actions: some View {
        if monthEnough {
            Button("买了，记一笔") { recordingFromReserve = false; recording = true }.buttonStyle(PrimaryButtonStyle(compact: true))
            Button(wishTitle, action: saveWish).buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).disabled(wishID != nil)
                .accessibilityIdentifier("purchaseSaveWish").accessibilityHint(waitHours > 0 ? "加入后等待 \(waitHours) 小时" : "加入心愿单")
        } else {
            Button(wishTitle, action: saveWish).buttonStyle(PrimaryButtonStyle(compact: true)).disabled(wishID != nil)
                .accessibilityIdentifier("purchaseSaveWish").accessibilityHint(waitHours > 0 ? "加入后等待 \(waitHours) 小时" : "加入心愿单")
            if reserveEnough {
                Button("从存着的钱买") { recordingFromReserve = true; recording = true }
                    .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).accessibilityIdentifier("buyFromReserve")
            } else {
                Button("我还是要买") { recordingFromReserve = false; recording = true }
                    .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
            }
        }
    }
    private func saveWish() {
        guard wishID == nil else { return }
        let submitted = verdict ?? SubmittedPurchaseVerdict(verdict: conclusion, reason: reason, need: .unclear, boundReason: assessment.reason)
        let now = Date()
        var addedID: UUID?
        if store.update("加入心愿单", showToast: false, { ledger in
            addedID = try Wishlist.keepConsidered(fromVerdict: submitted, title: purchase.title, amount: purchase.amount, category: purchase.category,
                                     subcategory: purchase.subcategory, in: &ledger, now: now).id
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
        }.navigationTitle("依据").yubaiNavigation()
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
