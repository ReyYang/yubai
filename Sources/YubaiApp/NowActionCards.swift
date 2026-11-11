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
    case payday(Payday.Due), bill(Occurrence), leftover(CycleSaving), gap(Reconciliation.Gap)
    case salary(SalaryCandidate), imports(PendingImportOrganization), butler(ButlerCard)
    var id: String {
        switch self {
        case .payday(let value): "payday:" + Dates.text(value.occurrence)
        case .bill(let value): "due:" + value.id
        case .leftover(let value): "leftover:" + Dates.text(value.cycleStart)
        case .gap(let value): "gap:" + Dates.text(value.lastRecorded)
        case .salary(let value): "salary:" + value.key
        case .imports(let value): "imports:" + value.sessionCardKey
        case .butler(let value): value.id.uuidString
        }
    }
    var needsAction: Bool {
        switch self {
        case .payday, .bill, .leftover, .gap, .salary, .imports: true
        case .butler(let card): card.importQuestion != nil || [.answerQuestion, .shortfall, .unknownInflow].contains(card.kind)
        }
    }
    /// The five kinds that may take the single expanded card slot on the 现在 page, in priority order.
    var takesHomeSlot: Bool {
        switch self {
        case .payday, .bill, .leftover, .gap, .imports: true
        case .salary, .butler: false
        }
    }
    var summary: String {
        switch self {
        case .payday(let value): value.title + "到了吗?"
        case .bill(let value): value.title + " · " + FixedFlowPresentation.monthDay(value.date)
        case .leftover: "上个周期"
        case .gap(let value): "\(value.days) 天没记了"
        case .salary: "这是工资吗？"
        case .imports(let value): "\(value.count) 笔没分类"
        case .butler(let value): value.title
        }
    }
}

@MainActor extension AppStore {
    /// Everything waiting for the person, most urgent first: 工资到账 > 账单到期 > 新周期小结 > 几天没记 > 导入待看, then the rest.
    var inboxItems: [LetterItem] {
        var result: [LetterItem] = []
        let due = paydayDue
        if let due, !isSnoozed("payday-" + Dates.text(due.occurrence)) { result.append(.payday(due)) }
        let today = Dates.day(Date())
        result += funds.occurrences.filter { occurrence in
            guard occurrence.planID != nil || (!occurrence.inflow && occurrence.rentID != nil) else { return false }
            guard Dates.day(occurrence.date) <= today, !hiddenPendingImportKeys.contains("due:" + occurrence.id) else { return false }
            if occurrence.inflow, occurrence.planID == due?.planID { return false }
            return !isSnoozed("bill-" + occurrence.id)
        }.map(LetterItem.bill)
        if let leftover = pendingLeftover, !isSnoozed("leftover-" + Dates.text(leftover.cycleStart)) { result.append(.leftover(leftover)) }
        if let gap = recordGap, !isSnoozed("gap-" + Dates.text(gap.lastRecorded), forever: true) { result.append(.gap(gap)) }
        let pending = pendingOrganization
        let showsPending = pending.count > 0 && !hiddenPendingImportKeys.contains(pending.sessionCardKey)
        if showsPending { result.append(.imports(pending)) }
        if let salary = nowSalaryCandidate, !hiddenSalaryKeys.contains(salary.key) { result.append(.salary(salary)) }
        let pendingIDs = Set(pending.entryIDs)
        result += butlerVisibility.queued.filter { card in
            guard showsPending, let question = card.importQuestion, question.isFallback else { return true }
            return !Set(question.entryIDs).isSubset(of: pendingIDs)
        }.map(LetterItem.butler)
        if let letter = freshLetter, letter.dismissedAt == nil { result.append(.butler(letter)) }
        // Cards that take the slot come first even when a butler card was queued ahead of them.
        return result.filter(\.takesHomeSlot) + result.filter { !$0.takesHomeSlot }
    }
}

struct LetterInboxChip: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let items = store.inboxItems
        if let first = items.first {
            TabNavigationLink(.todo) { TodoView() } label: {
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
            Text("待处理 · \(count) 件").yubaiFont(YubaiFont.row, weight: .medium).fixedSize()
        }
    }
    private var chevron: some View { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }

}

/// 待处理：要你处理的在上，看看就好的在下；每张卡一个问题，最多两个答案。
struct TodoView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let items = store.inboxItems
        Page(spacing: 24, topPadding: 16) {
            section("要你处理", items: items.filter(\.needsAction))
            section("看看就好", items: items.filter { !$0.needsAction })
        }.safeAreaInset(edge: .top, spacing: 0) { LedgerPageHeader(title: "待处理", backTitle: "现在").padding(.horizontal, 20) }
            .navigationTitle("待处理").yubaiNavigation().accessibilityIdentifier("letterInbox")
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
        case .payday(let due):
            LetterDismissCard(onDismiss: { store.snooze("payday-" + Dates.text(due.occurrence)); return true }) { _ in PaydayCard(due: due) }
        case .bill(let bill):
            LetterDismissCard(onDismiss: { store.snooze("bill-" + bill.id); return true }) { _ in BillDueCard(bill: bill, inTodo: true) }
        case .leftover(let saving):
            LetterDismissCard(onDismiss: { store.snooze("leftover-" + Dates.text(saving.cycleStart)); return true }) { _ in NewCycleCard(saving: saving) }
        case .gap(let gap):
            LetterDismissCard(onDismiss: { store.snooze("gap-" + Dates.text(gap.lastRecorded), forever: true); return true }) { _ in GapCard(gap: gap) }
        case .imports(let pending):
            LetterDismissCard(onDismiss: { store.hiddenPendingImportKeys.insert(pending.sessionCardKey); return true }) { _ in
                PendingImportsCard(pending: pending)
            }
        case .salary(let salary):
            LetterDismissCard(onDismiss: { store.hiddenSalaryKeys.insert(salary.key); return true }) { _ in SalaryCard(candidate: salary) }
        case .butler(let card):
            if card.kind == .weeklyLetter {
                WeeklyReviewRow(card: card)
            } else if let question = card.importQuestion,
               let batch = store.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                LetterDismissCard(onDismiss: { store.dismissCard(card.id) }) { _ in
                    ImportQuestionCard(question: question, batchID: batch.id, cardID: card.id)
                }
            } else { ButlerCardView(card: card) }
        }
    }
}

/// Source compatibility for the route and header that still say "inbox".
typealias LetterInboxView = TodoView

/// 看看就好：周回顾一行，点进去是周回顾页。
private struct WeeklyReviewRow: View {
    let card: ButlerCard
    private var range: String {
        guard let facts = card.letter else { return "" }
        return NowFormat.monthDay(Dates.addDays(-6, to: facts.weekEnding)) + " – " + NowFormat.monthDay(facts.weekEnding)
    }
    var body: some View {
        TabNavigationLink(.weekly(card.id)) { LetterDetailView(cardID: card.id) } label: {
            Card(style: .compact) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("周回顾").yubaiFont(YubaiFont.cardTitle)
                    Spacer(minLength: YubaiSpace.space8)
                    Text(range).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                }.frame(minHeight: YubaiSize.rowSingle)
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("weeklyReviewRow")
    }
}

extension PendingImportOrganization {
    var sessionCardKey: String { batchIDs.map(\.uuidString).sorted().joined(separator: ":") }
}

private struct SalaryCard: View {
    @Environment(AppStore.self) private var store
    let candidate: SalaryCandidate
    private var eyebrow: String { "每月 \(candidate.dayOfMonth) 号 · 已到账 \(candidate.recentDates.count) 次" }
    var body: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(eyebrow).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, 28)
                Text("这是工资吗?").yubaiFont(YubaiFont.cardTitle)
                HStack(spacing: YubaiSpace.space8) {
                    Text(candidate.payer).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).lineLimit(1)
                    AmountLabel(cents: candidate.amount, hide: store.preferences.hideAmounts, role: .small)
                }
                HStack(spacing: YubaiSpace.space8) {
                    Button("是工资") { store.confirmSalary(candidate) }.buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("confirmSalary")
                    Button("不是") { store.rejectSalary(candidate) }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("rejectSalary")
                }.padding(.top, YubaiSpace.space4)
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
    private var eyebrow: String {
        "没分类 · " + (pending.dates.first.map { "\(Dates.calendar.component(.month, from: $0))月导入" } ?? "")
    }
    var body: some View {
        let total = entries.reduce(Int64(0)) { $0 + $1.amount }
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(eyebrow).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).padding(.trailing, 28)
                Text("\(pending.count) 笔还没分类").yubaiFont(YubaiFont.cardTitle)
                Text("共 " + amount2(total, hide: store.preferences.hideAmounts)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
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
                    HStack(spacing: YubaiSpace.space8) {
                        TabNavigationLink(.triage(pending.entryIDs)) { LetterTriageView(entryIDs: pending.entryIDs) } label: { Text("一笔笔过") }
                            .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("classifyImportsManually")
                        Button("交给余白") {
                            if store.organizationAIReady { store.startOrganizingPendingImports() } else { store.sheet = .intelligencePrivacy }
                        }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("organizeImports")
                    }.padding(.top, YubaiSpace.space4)
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
