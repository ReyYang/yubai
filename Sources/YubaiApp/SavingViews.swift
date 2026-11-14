import SwiftUI
import YubaiCore

enum SavingCardVisibility {
    struct Snapshot: Equatable, Sendable {
        let queued: [ButlerCard]
        let visible: [ButlerCard]
        let collapsed: [ButlerCard]
    }
    static func snapshot(in ledger: Ledger, organizingBatchIDs: Set<UUID>, progress: [RestrainProgress]? = nil,
                         fallbackEntryCount: @escaping (ImportQuestion) -> Int) -> Snapshot {
        let queue = ButlerCards.queued(ledger, organizingBatchIDs: organizingBatchIDs, fallbackEntryCount: fallbackEntryCount)
        let progress = Dictionary(uniqueKeysWithValues: (progress ?? RestrainProgress.current(ledger: ledger)).map { ($0.areaID, $0) })
        let filtered = queue.filter { card in
            guard card.kind == .restrain, let id = card.areaID, let value = progress[id] else { return true }
            return value.status == .over
        }
        let collapse = queue.lazy.filter { $0.kind == .unknownInflow }.prefix(2).count >= 2
        return Snapshot(queued: queue, visible: Array(filtered.prefix(5)),
                        collapsed: Array(filtered.lazy.filter { !collapse || $0.kind != .unknownInflow }.prefix(5)))
    }
}

/// The same destination carries context from every invitation to revisit.
struct ProfileChatEntry: View {
    @Environment(AppStore.self) private var store
    var title = "和余白聊聊"
    var context: ProfileColdStart.OpeningContext? = nil
    var prominent = false
    @State private var showing = false
    @State private var configured = IntelligenceRuntime.isConfigured
    private var enabled: Bool { configured && store.preferences.isAIEnabled(for: .answers) && IntelligenceRuntime.cloud.unavailableModel == nil }
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: YubaiSpace.gapGroup) {
                if prominent { AssistantMark(size: YubaiFont.row.size).accessibilityHidden(true) }
                Text(title).yubaiFont(prominent ? YubaiFont.rowTitle : YubaiFont.row)
                Spacer(minLength: YubaiSpace.none)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption)
            }.foregroundStyle(prominent ? YubaiColor.brandTintStrong : YubaiColor.brandInk)
                .padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: prominent ? YubaiSize.rowDouble : YubaiSize.rowSingle)
                .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card), background: prominent ? YubaiColor.brandTint : nil)
        }.buttonStyle(PressButtonStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.5)
            .accessibilityIdentifier("profileChatEntry")
            .onAppear { configured = IntelligenceRuntime.isConfigured }
            .sheet(isPresented: $showing) {
                NavigationStack { ProfileConversationView(openingContext: context) }.environment(store).appErrors().yubaiSheetBackground()
                    #if os(macOS)
                    .frame(minWidth: YubaiSize.sheetMinimumWidth, minHeight: YubaiSize.sheetMinimumHeight)
                    #endif
            }
    }
}

struct SavingsHeader: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let increase = SavingInsights.wishSavings(store.current, now: store.financialNow).month
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("没买，省下的").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) { numbers(increase) }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) { numbers(increase) }
            }
        }.accessibilityIdentifier("wishlistSavings")
    }
    private func numbers(_ increase: Int64) -> some View {
        Group {
            AmountLabel(cents: SavingInsights.wishSavings(store.current, now: store.financialNow).total, hide: store.preferences.hideAmounts, role: .input)
            if !store.preferences.hideAmounts {
                Text("这个月 +" + AmountLabel.text(increase)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
            }
        }
    }
}

struct WishlistCooldownCards: View {
    @Environment(AppStore.self) private var store
    private var wishes: [WishItem] {
        Wishlist.cooldownDue(store.current, now: Dates.now).compactMap { candidate in
            guard case .openWish(let id) = candidate.action else { return nil }
            return store.current.wishlist.first { $0.id == id }
        }
    }
    @State private var recording: WishItem?
    var body: some View {
        ForEach(wishes) { wish in CooldownWishCard(wish: wish, record: { recording = $0 }) }
            .sheet(item: $recording) { wish in
                NavigationStack { QuickEntryView(prefill: QuickEntryPrefill(category: wish.category, amount: wish.amount, purpose: wish.title)) }
                    .environment(store).appErrors().yubaiSheetBackground()
            }
    }
}

private struct CooldownWishCard: View {
    @Environment(AppStore.self) private var store
    let wish: WishItem
    let record: (WishItem) -> Void
    private var question: String {
        let amount: String = store.preferences.hideAmounts ? "" : " " + Money.text(wish.amount, currency: false)
        return wish.title + amount + "，还想要吗？"
    }
    private var purpose: String {
        store.preferences.hideAmounts ? "金额已隐藏" : "当时说「" + wish.purpose + "」"
    }
    var body: some View {
        Card(background: YubaiColor.amberTint) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                heading
                Text(question).yubaiFont(YubaiFont.heroLabel).foregroundStyle(YubaiColor.amberStrong)
                if !wish.purpose.isEmpty { Text(purpose).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
                actions
            }
        }.accessibilityIdentifier("cooldownWish_" + wish.id.uuidString)
    }
    private var heading: some View {
        HStack(spacing: YubaiSpace.space8) {
            Circle().fill(YubaiColor.amberDot).frame(width: YubaiSize.unknownDot, height: YubaiSize.unknownDot).accessibilityHidden(true)
            Text("冷静了 " + WishWaitText.duration(from: wish.createdAt, to: wish.coolUntil ?? wish.createdAt))
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
        }
    }
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { cooldownButtons }
            VStack(spacing: YubaiSpace.space8) { cooldownButtons }
        }
    }
    private var cooldownButtons: some View {
        Group {
            Button("还想要") { if answer(.keep) { record(wish) } }
                .buttonStyle(PrimaryButtonStyle(compact: true)).frame(maxWidth: .infinity).accessibilityIdentifier("cooldownKeep")
            Button("不要了") { answer(.drop) }
                .buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true)).frame(maxWidth: .infinity).accessibilityIdentifier("cooldownDrop")
        }
    }
    @discardableResult private func answer(_ choice: CooldownChoice) -> Bool {
        store.update("回答心愿", showToast: false) { try Wishlist.answerCooldown(wish.id, choice: choice, in: &$0, now: Dates.now) }
    }
}

enum WishWaitText {
    static func remaining(until: Date, now: Date) -> String {
        let hours = max(1, Int(ceil(until.timeIntervalSince(now) / 3600)))
        return hours < 24 ? "\(hours) 小时" : "\(Int(ceil(Double(hours) / 24))) 天"
    }
    static func duration(from: Date, to: Date) -> String {
        let hours = max(0, Int((to.timeIntervalSince(from) / 3600).rounded()))
        if hours < 24 { return "\(hours) 小时" }
        let components = Dates.calendar.dateComponents([.day, .hour, .minute], from: from, to: to)
        if components.hour == 0 && components.minute == 0 { return "\(max(0, components.day ?? 0)) 天" }
        return "\(hours) 小时"
    }
}

struct WishRegretEntry: View {
    @Environment(AppStore.self) private var store
    let wish: WishItem
    @State private var dismissed = false
    var body: some View {
        if !dismissed {
            Card {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    HStack(spacing: YubaiSpace.space8) {
                        Text(wish.title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle)
                        AmountLabel(cents: wish.amount, hide: store.preferences.hideAmounts)
                        Text("· 有点后悔").yubaiFont(YubaiFont.callout)
                    }
                    ProfileChatEntry(title: "写进消费观", context: .wishRegret(wish.title + " · " + (wish.followUpAnswer ?? "有点后悔")))
                    Button("收起") { dismissed = true }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
                }
            }
        }
    }
}

struct LetterSubscriptionCard: View {
    @Environment(AppStore.self) private var store
    let candidates: [SubscriptionCandidate]
    let letterDate: Date
    @State private var answered: [String: SubscriptionAnswer] = [:]
    private var currentCandidates: [SubscriptionCandidate] { store.subscriptionCandidates }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            Text("这些还在用吗？").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                .padding(.horizontal, YubaiSpace.space4)
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(candidates) { candidate in
                        subscriptionRow(candidate)
                        if candidate.id != candidates.last?.id { EntryFormDivider() }
                    }
                }
            }
        }.accessibilityIdentifier("letterSubscriptions")
    }
    private func subscriptionRow(_ candidate: SubscriptionCandidate) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            subscriptionHeading(candidate)
            subscriptionActions(candidate)
        }.padding(.vertical, YubaiSpace.gapGroup)
    }
    private func subscriptionHeading(_ candidate: SubscriptionCandidate) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(candidate.title).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                Text(schedule(candidate)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            AmountLabel(cents: candidate.amount, hide: store.preferences.hideAmounts)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(candidate.title).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                Text(schedule(candidate)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: candidate.amount, hide: store.preferences.hideAmounts)
            }
        }
    }
    @ViewBuilder private func subscriptionActions(_ candidate: SubscriptionCandidate) -> some View {
        if let status = status(candidate) {
            Text(status).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
        } else {
            ChipFlow {
                Button("还在用") { answer(candidate, .stillUsing) }
                    .accessibilityIdentifier("keepWeeklySubscription_" + candidate.id)
                Button("停掉") { answer(candidate, .stop) }
                    .accessibilityIdentifier("stopWeeklySubscription_" + candidate.id)
            }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
        }
    }
    private func status(_ candidate: SubscriptionCandidate) -> String? {
        if let choice = answered[candidate.id] { return choice == .stop ? "已停掉" : "还在用" }
        if let id = candidate.planID, store.plans.first(where: { $0.id == id })?.stoppedAt != nil { return "已停掉" }
        if store.plans.contains(where: { stoppedPlan($0, matches: candidate) }) { return "已停掉" }
        if let month = store.current.subscriptionChecks[candidate.id], month >= String(Dates.text(letterDate).prefix(7)) { return "已回答" }
        if currentCandidates.contains(candidate) { return nil }
        return "已变更"
    }
    private func stoppedPlan(_ plan: Plan, matches candidate: SubscriptionCandidate) -> Bool {
        guard plan.stoppedAt != nil, CategoryMemory.key(plan.title) == CategoryMemory.key(candidate.title) else { return false }
        if candidate.planID == plan.id { return true }
        return candidate.entryIDs.contains { id in
            store.current.entries.first { $0.id == id }?.accountID == plan.accountID
        }
    }
    private func schedule(_ candidate: SubscriptionCandidate) -> String {
        guard let date = scheduleDate(candidate) else { return candidate.frequency.label }
        switch candidate.frequency {
        case .monthly: return "每月 \(Dates.calendar.component(.day, from: date)) 日"
        case .weekly: return "每周" + date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))
        default: return candidate.frequency.label + " · " + FixedFlowPresentation.monthDay(date)
        }
    }
    private func scheduleDate(_ candidate: SubscriptionCandidate) -> Date? {
        if let id = candidate.planID, let plan = store.plans.first(where: { $0.id == id }) { return plan.dueDate }
        let dates: [Date] = candidate.entryIDs.compactMap { id in store.current.entries.first { $0.id == id }?.date }
        return dates.last
    }
    private func answer(_ candidate: SubscriptionCandidate, _ choice: SubscriptionAnswer) {
        if store.update("回答订阅", showToast: false, { try SubscriptionCheck.answer(candidate, choice: choice, in: &$0) }) { answered[candidate.id] = choice }
    }
}
