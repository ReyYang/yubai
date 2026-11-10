import SwiftUI
import YubaiCore

@MainActor extension AppStore {
    var cloudAIReady: Bool {
        preferences.cloudAIEnabled && IntelligenceRuntime.isConfigured && IntelligenceRuntime.cloud.unavailableModel == nil
    }
    var organizationAIReady: Bool { preferences.cloudAIEnabled && IntelligenceRuntime.isConfigured }
    func confirmSalary(_ candidate: SalaryCandidate) {
        guard SalaryDetection.candidate(in: current)?.key == candidate.key else { return }
        if update("工资", showToast: false, { ledger in
            SalaryDetection.confirm(candidate, in: &ledger)
        }) { toast = "工资已加到会回来的账单" }
    }
    func rejectSalary(_ candidate: SalaryCandidate) {
        if update("工资", showToast: false, { SalaryDetection.dismiss(candidate, in: &$0) }) { toast = nil }
    }

}

enum LetterItem: Identifiable {
    case salary(SalaryCandidate), imports(PendingImportOrganization), bill(Occurrence), butler(ButlerCard)
    var id: String {
        switch self {
        case .salary(let value): "salary:" + value.key
        case .imports(let value): "imports:" + value.sessionCardKey
        case .bill(let value): "due:" + value.id
        case .butler(let value): value.id.uuidString
        }
    }
    var needsAction: Bool {
        switch self {
        case .salary, .imports, .bill: true
        case .butler(let card): card.importQuestion != nil || [.answerQuestion, .shortfall, .unknownInflow].contains(card.kind)
        }
    }
    var summary: String {
        switch self {
        case .salary: "这是工资吗？"
        case .imports(let value): "\(value.count) 笔没分类"
        case .bill(let value): value.title + " · " + FixedFlowPresentation.monthDay(value.date)
        case .butler(let value): value.title
        }
    }
}

@MainActor extension AppStore {
    var inboxItems: [LetterItem] {
        var result: [LetterItem] = []
        let pending = pendingOrganization
        let showsPending = pending.count > 0 && !hiddenPendingImportKeys.contains(pending.sessionCardKey)
        if showsPending { result.append(.imports(pending)) }
        if let salary = nowSalaryCandidate, !hiddenSalaryKeys.contains(salary.key) { result.append(.salary(salary)) }
        let pendingIDs = Set(pending.entryIDs)
        result += butlerVisibility.queued.filter { card in
            guard showsPending, let question = card.importQuestion, question.isFallback else { return true }
            return !Set(question.entryIDs).isSubset(of: pendingIDs)
        }.map(LetterItem.butler)
        result += funds.occurrences.filter {
            ($0.planID != nil || (!$0.inflow && $0.rentID != nil)) && Dates.day($0.date) <= Dates.day(Date()) &&
                !hiddenPendingImportKeys.contains("due:" + $0.id)
        }.map(LetterItem.bill)
        if let letter = freshLetter, letter.dismissedAt == nil { result.append(.butler(letter)) }
        return result
    }
}

struct LetterInboxChip: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let items = store.inboxItems
        if let first = items.first {
            TabNavigationLink(.inbox) { LetterInboxView() } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { inboxTitle(items.count); Text(first.summary).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize(); Spacer(minLength: 0); chevron }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { inboxTitle(items.count); Spacer(minLength: 0); chevron }
                        Text(first.summary).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    }.padding(.vertical, 8)
                }.padding(.horizontal, 16).frame(minHeight: 48).paperCardSurface(in: RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openLetterInbox")
        }
    }
    private func inboxTitle(_ count: Int) -> some View {
        HStack(spacing: 10) {
            AssistantMark(size: 20, color: YubaiColor.brandInk)
            Text("来信 · \(count) 件").yubaiFont(YubaiFont.row, weight: .medium).fixedSize()
        }
    }
    private var chevron: some View { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }

}

struct LetterInboxView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let items = store.inboxItems
        Page(spacing: 24, topPadding: 16) {
            section("要你处理", items: items.filter(\.needsAction))
            section("看看就好", items: items.filter { !$0.needsAction })
        }.safeAreaInset(edge: .top, spacing: 0) { LedgerPageHeader(title: "来信", backTitle: "账本").padding(.horizontal, 20) }
            .navigationTitle("来信").yubaiNavigation().accessibilityIdentifier("letterInbox")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
    @ViewBuilder private func section(_ title: String, items: [LetterItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) { Text(title); Text("\(items.count)") }
                    .yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, 16)
                ForEach(items) { item in itemView(item) }
            }
        }
    }
    @ViewBuilder private func itemView(_ item: LetterItem) -> some View {
        switch item {
        case .imports(let pending):
            LetterDismissCard(onDismiss: { store.hiddenPendingImportKeys.insert(pending.sessionCardKey); return true }) { _ in
                PendingImportsCard(pending: pending)
            }
        case .salary(let salary):
            LetterDismissCard(onDismiss: { store.hiddenSalaryKeys.insert(salary.key); return true }) { _ in SalaryCard(candidate: salary) }
        case .bill(let bill):
            LetterDismissCard(onDismiss: { store.hiddenPendingImportKeys.insert("due:" + bill.id); return true }) { _ in
                LetterBillCard(bill: bill)
            }
        case .butler(let card):
            if let question = card.importQuestion,
               let batch = store.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                LetterDismissCard(onDismiss: { store.dismissCard(card.id) }) { _ in
                    ImportQuestionCard(question: question, batchID: batch.id, cardID: card.id)
                }
            } else { ButlerCardView(card: card) }
        }
    }
}

private struct LetterBillCard: View {
    @Environment(AppStore.self) private var store
    let bill: Occurrence
    @State private var editingAmount = false
    private var intoFixedSavings: Bool { bill.planID.flatMap { id in store.plans.first { $0.id == id } }?.intoFixedSavings == true }
    private var amountText: String { store.preferences.hideAmounts ? "••••" : Money.text(bill.amount, currency: false) }
    var body: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                Text((bill.inflow ? "要收 · " : "要付 · ") + FixedFlowPresentation.monthDay(bill.date))
                    .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, 24)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { title.fixedSize(); amount.fixedSize() }
                    VStack(alignment: .leading, spacing: 4) { title; amount }
                }
                if bill.inflow && intoFixedSavings {
                    Label("到账放进存着不动", systemImage: "lock").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk)
                }
                if bill.planID != nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { actions }
                        VStack(alignment: .leading, spacing: 8) { actions }
                    }
                    if bill.inflow {
                        Button("还没到") { store.hiddenPendingImportKeys.insert("due:" + bill.id) }.buttonStyle(NowCardButtonStyle())
                            .accessibilityIdentifier("notYetReceived_" + bill.id)
                    }
                } else {
                    TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: { Text("会回来的账单").yubaiFont(YubaiFont.callout) }
                        .buttonStyle(NowCardButtonStyle())
                }
            }
        }.accessibilityIdentifier("dueBills")
            .sheet(isPresented: $editingAmount) {
                NavigationStack {
                    FixedFlowSettlementEditor(title: bill.title, amount: Money.input(bill.amount)) { value in settle(value) }
                        .environment(store).appErrors()
                }.presentationDragIndicator(.visible).yubaiSheetBackground()
                    #if os(iOS)
                    .presentationDetents([.large])
                    #endif
            }
    }
    private var title: some View { Text(bill.title).yubaiFont(YubaiFont.cardTitle) }
    private var amount: some View {
        AmountLabel(cents: bill.amount, hide: store.preferences.hideAmounts, role: .summary, sign: bill.inflow ? .inflow : .outflow, ink: bill.inflow ? YubaiColor.brandInk : YubaiColor.label)
    }
    private var actions: some View {
        Group {
            Button((bill.inflow ? "收到了 " : "付了 ") + amountText) { _ = settle() }.buttonStyle(NowCardButtonStyle(primary: true))
                .accessibilityIdentifier("settleLetterBill_" + bill.id)
            Button("金额不一样") { editingAmount = true }.buttonStyle(NowCardButtonStyle())
                .accessibilityIdentifier("editLetterBillAmount_" + bill.id)
        }
    }
    private func settle(_ override: Int64? = nil) -> Bool {
        guard let id = bill.planID else { return false }
        return FixedFlowCheck.record(planID: id, occurrence: bill.date, title: bill.title, amount: override ?? bill.amount, inflow: bill.inflow, store: store, override: override)
    }
}

extension PendingImportOrganization {
    var sessionCardKey: String { batchIDs.map(\.uuidString).sorted().joined(separator: ":") }
}

private struct SalaryCard: View {
    @Environment(AppStore.self) private var store
    let candidate: SalaryCandidate
    var body: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: 10) {
                Text("这是工资吗？ · " + (candidate.recentDates.last.map(FixedFlowPresentation.monthDay) ?? ""))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, 28)
                HStack(spacing: 6) {
                    AmountLabel(cents: candidate.amount, hide: store.preferences.hideAmounts, role: .summary, sign: .inflow)
                    Text("· " + store.accountName(candidate.accountID)).yubaiFont(YubaiFont.row, weight: .semibold)
                }
                HStack(spacing: 8) {
                    Button("是工资") { store.confirmSalary(candidate) }.buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("confirmSalary")
                    Button("不是") { store.rejectSalary(candidate) }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("rejectSalary")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("salaryCard")
    }
}

struct LetterEntryInset: View {
    @Environment(AppStore.self) private var store
    let entries: [Entry]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.prefix(3))) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayTitle).yubaiFont(YubaiFont.row)
                        Text(ImportStatementText.balanceDate(entry.date)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    }
                    Spacer(minLength: 4)
                    AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, sign: entry.nature.inflow ? .inflow : .outflow)
                }.frame(minHeight: 48)
                if entry.id != entries.prefix(3).last?.id { EntryFormDivider() }
            }
        }.padding(.horizontal, 12).background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PendingImportsCard: View {
    @Environment(AppStore.self) private var store
    let pending: PendingImportOrganization
    private var entries: [Entry] { store.evidenceEntries(Set(pending.entryIDs), activeOnly: true).filter { Classification.isPending($0) } }
    private var busy: Bool { store.organizingPendingImports || store.organizingBatchID != nil }
    var body: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: 10) {
                Text("没分类 · " + (pending.dates.first.map { "\(Dates.calendar.component(.month, from: $0))月导入" } ?? ""))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, 28)
                Text("\(pending.count) 笔还没分类").yubaiFont(YubaiFont.cardTitle)
                LetterEntryInset(entries: entries)
                if entries.count > 3 { Text("还有 \(entries.count - 3) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                if let error = pending.batchIDs.compactMap({ store.organizationErrors[$0] }).first {
                    Text(error).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk).accessibilityIdentifier("organizeError")
                }
                if busy {
                    HStack {
                        ProgressView()
                        if let progress = store.organizationProgress { Text(progress.countText).yubaiFont(YubaiFont.caption).accessibilityIdentifier("organizeProgress") }
                        Spacer()
                        Button("停下") { store.stopOrganizingImports() }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("stopOrganizing")
                    }
                } else {
                    HStack(spacing: 8) {
                        TabNavigationLink(.triage(pending.entryIDs)) { LetterTriageView(entryIDs: pending.entryIDs) } label: { Text("一笔笔过") }
                            .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("classifyImportsManually")
                        Button("交给余白") {
                            if store.organizationAIReady { store.startOrganizingPendingImports() } else { store.sheet = .intelligencePrivacy }
                        }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("organizeImports")
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("pendingImportsCard")
            #if DEBUG && targetEnvironment(simulator)
            .uiTestAccessibilityValue(UITestSupport.importRequestState(in: store.current))
            #endif
    }
}

struct NowCardButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: .medium).padding(.horizontal, 16).frame(minHeight: 40)
            .foregroundStyle(primary ? YubaiColor.onBrand : YubaiColor.label)
            .background(primary ? YubaiColor.brand : YubaiColor.raised, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}
