import SwiftUI
import YubaiCore

enum SavingCardVisibility {
    static func visible(in ledger: Ledger) -> [ButlerCard] {
        let progress = RestrainProgress.current(ledger: ledger)
        var filtered = ledger
        filtered.cards.removeAll { card in
            guard card.kind == .restrain, let areaID = card.areaID,
                  let value = progress.first(where: { $0.areaID == areaID }) else { return false }
            return value.status != .over
        }
        return ButlerCards.visible(filtered)
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
    private var enabled: Bool { configured && store.current.preferences.cloudAIEnabled && IntelligenceRuntime.cloud.unavailableModel == nil }
    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: YubaiSpace.gapGroup) {
                if prominent { AssistantMark(size: 14).accessibilityHidden(true) }
                Text(title).yubaiFont(prominent ? YubaiFont.rowTitle : YubaiFont.row)
                Spacer(minLength: YubaiSpace.none)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption)
            }.foregroundStyle(prominent ? YubaiColor.brandTintStrong : YubaiColor.brandInk)
                .padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: prominent ? YubaiSize.rowDouble : YubaiSize.rowSingle)
                .background(prominent ? YubaiColor.brandTint : YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
        }.buttonStyle(PressButtonStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.5)
            .accessibilityIdentifier("profileChatEntry")
            .onAppear { configured = IntelligenceRuntime.isConfigured }
            .sheet(isPresented: $showing) {
                NavigationStack { ProfileConversationView(openingContext: context) }.environment(store).appErrors()
                    #if os(macOS)
                    .frame(minWidth: 540, minHeight: 600)
                    #endif
            }
    }
}

struct SavingsHeader: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let now = Date()
        let month = Dates.calendar.dateInterval(of: .month, for: now)!
        let increase = Savings.summary(ledger: store.current, from: month.start, to: now, now: now).total
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
            AmountLabel(cents: Savings.total(ledger: store.current), hide: store.current.preferences.hideAmounts, role: .input, fractionDigits: 0)
            if !store.current.preferences.hideAmounts {
                Text("这个月 +" + Money.text(increase, currency: false)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
            }
        }
    }
}

struct WishlistCooldownCards: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let candidates = Wishlist.cooldownDue(store.current, now: Date())
        ForEach(candidates, id: \.dedupeKey) { candidate in
            if case .openWish(let id) = candidate.action,
               let wish = store.current.wishlist.first(where: { $0.id == id }) {
                Card(background: YubaiColor.amberTint) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(wish.createdAt), to: Dates.day(wish.coolUntil ?? Date())).day ?? 0)
                        HStack(spacing: YubaiSpace.space8) {
                            Circle().fill(YubaiColor.amberDot).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text("冷静了 \(days) 天").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk)
                        }
                        Text(wish.title + (store.current.preferences.hideAmounts ? "" : " " + Money.text(wish.amount, currency: false)) + "，还想要吗？")
                            .yubaiFont(YubaiFont.heroLabel).foregroundStyle(YubaiColor.amberStrong)
                        if !wish.purpose.isEmpty {
                            Text(store.current.preferences.hideAmounts ? "金额已隐藏" : "当时说「" + wish.purpose + "」").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
                        }
                        HStack(spacing: YubaiSpace.space8) {
                            Button("还想要") { answer(id, .keep) }
                            Button("不要了") { answer(id, .drop) }
                        }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
                    }
                }.accessibilityIdentifier("cooldownWish_" + id.uuidString)
            }
        }
    }
    private func answer(_ id: UUID, _ choice: CooldownChoice) {
        store.update("回答心愿", showToast: false) { try Wishlist.answerCooldown(id, choice: choice, in: &$0, now: Date()) }
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
                        Text(wish.title).yubaiFont(YubaiFont.rowTitle)
                        AmountLabel(cents: wish.amount, hide: store.current.preferences.hideAmounts)
                        Text("· 有点后悔").yubaiFont(YubaiFont.callout)
                    }
                    Text("要把这次的感受写进消费观吗？").yubaiFont(YubaiFont.cardTitle)
                    ProfileChatEntry(title: "和余白说说", context: .wishRegret(wish.title + " · " + (wish.followUpAnswer ?? "有点后悔")))
                    Button("不用了") { dismissed = true }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
                }
            }
        }
    }
}

struct LetterSavingsTiles: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let facts: LetterFacts
    var body: some View {
        if (facts.totalSavings ?? 0) > 0 || (facts.weeklySavings ?? 0) > 0 {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.gapGroup)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
            layout {
                tile("这周省下", facts.weeklySavings ?? 0)
                tile("一共省下", facts.totalSavings ?? 0)
            }.accessibilityIdentifier("letterSavings")
        }
    }
    private func tile(_ title: String, _ amount: Int64) -> some View {
        Card(style: .compact, background: YubaiColor.brandTint) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                AmountLabel(cents: amount, hide: store.current.preferences.hideAmounts, role: .large, ink: YubaiColor.brandTintStrong)
            }
        }
    }
}

struct LetterSubscriptionCard: View {
    @Environment(AppStore.self) private var store
    let candidates: [SubscriptionCandidate]
    let letterDate: Date
    @State private var answered: [String: SubscriptionAnswer] = [:]
    private var currentCandidates: [SubscriptionCandidate] { SubscriptionCheck.candidates(ledger: store.current) }
    var body: some View {
        Card(style: .list) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text("这些还在用吗？").yubaiFont(YubaiFont.heroLabel).padding(.vertical, YubaiSpace.gapGroup)
                ForEach(candidates) { candidate in
                    EntryFormDivider()
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                Text(candidate.title).yubaiFont(YubaiFont.rowTitle)
                                Text(schedule(candidate)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            AmountLabel(cents: candidate.amount, hide: store.current.preferences.hideAmounts)
                        }
                        if let status = status(candidate) {
                            Text(status).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        } else {
                            HStack(spacing: YubaiSpace.space8) {
                                Button("还在用") { answer(candidate, .stillUsing) }
                                Button("停掉") { answer(candidate, .stop) }
                            }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
                        }
                    }.padding(.vertical, YubaiSpace.gapGroup)
                }
            }
        }.accessibilityIdentifier("letterSubscriptions")
    }
    private func status(_ candidate: SubscriptionCandidate) -> String? {
        if let choice = answered[candidate.id] { return choice == .stop ? "已停掉" : "还在用" }
        if let id = candidate.planID, store.current.plans.first(where: { $0.id == id })?.stoppedAt != nil { return "已停掉" }
        if store.current.plans.contains(where: { plan in
            plan.stoppedAt != nil && CategoryMemory.key(plan.title) == CategoryMemory.key(candidate.title)
                && (candidate.planID == plan.id || candidate.entryIDs.contains { id in store.current.entries.first { $0.id == id }?.accountID == plan.accountID })
        }) { return "已停掉" }
        if let month = store.current.subscriptionChecks[candidate.id], month >= String(Dates.text(letterDate).prefix(7)) { return "已回答" }
        if currentCandidates.contains(candidate) { return nil }
        return "已变更"
    }
    private func schedule(_ candidate: SubscriptionCandidate) -> String {
        let date = candidate.planID.flatMap { id in store.current.plans.first { $0.id == id }?.dueDate }
            ?? candidate.entryIDs.compactMap { id in store.current.entries.first { $0.id == id }?.date }.last
        guard let date else { return candidate.frequency.label }
        switch candidate.frequency {
        case .monthly: return "每月 \(Dates.calendar.component(.day, from: date)) 日"
        case .weekly: return "每周" + date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "zh_CN")))
        default: return candidate.frequency.label + " · " + FixedFlowPresentation.monthDay(date)
        }
    }
    private func answer(_ candidate: SubscriptionCandidate, _ choice: SubscriptionAnswer) {
        if store.update("回答订阅", showToast: false, { try SubscriptionCheck.answer(candidate, choice: choice, in: &$0) }) { answered[candidate.id] = choice }
    }
}

struct SavingProgressBar: View {
    let ratio: Double
    var amber = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(YubaiColor.neutralSoft)
                Capsule().fill(amber ? YubaiColor.amberDot : YubaiColor.brand).frame(width: geometry.size.width * min(1, max(0, ratio)))
            }
        }.frame(height: YubaiSpace.space4).accessibilityHidden(true)
    }
}

struct RestrainNearRow: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let progress = RestrainProgress.current(ledger: store.current).filter({ progress in
            let key = "restrain:\(progress.areaID):\(ButlerCards.isoWeek(Date()))"
            return progress.status == .near && !ButlerCards.isMuted(key, in: store.current)
                && store.current.cards.first(where: { $0.dedupeKey == key })?.dismissedAt == nil
        }).sorted(by: { $0.ratio > $1.ratio }).first {
            NavigationLink { ProfileView() } label: {
                HStack(spacing: YubaiSpace.gapGroup) {
                    VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                        Text(progress.title + " · " + usage(progress)).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label)
                        Text(limit(progress)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    SavingProgressBar(ratio: progress.ratio, amber: true).frame(width: YubaiSize.iconButton + YubaiSpace.gapSection)
                }.padding(.horizontal, YubaiSpace.insetCard).padding(.vertical, YubaiSpace.space8).frame(minHeight: YubaiSize.rowDouble)
                    .background(YubaiColor.amberTint, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("restrainNear")
        }
    }
    private func countLeads(_ p: RestrainProgress) -> Bool {
        guard let count = p.perWeekCount else { return false }
        let ratio = count == 0 ? (p.weekCount > 0 ? Double.infinity : 0) : Double(p.weekCount) / Double(count)
        return ratio >= p.ratio
    }
    private func usage(_ p: RestrainProgress) -> String {
        countLeads(p) ? "本周第 \(p.weekCount) 次" : "本月 " + (store.current.preferences.hideAmounts ? "••••" : Money.text(p.monthAmount))
    }
    private func limit(_ p: RestrainProgress) -> String {
        if countLeads(p), let count = p.perWeekCount { return "你写的最多 \(count) 次" }
        return "你写的最多 " + (store.current.preferences.hideAmounts ? "••••" : Money.text(p.perMonthAmount ?? 0))
    }
}
