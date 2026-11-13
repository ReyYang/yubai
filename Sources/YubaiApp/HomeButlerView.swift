import SwiftUI
import YubaiCore

struct ButlerReceipt: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var amount: Int64?
    var nextStep: String?
    var undoLabel: String?
}

@MainActor extension AppStore {
    func answerHome(_ item: HomeTask) {
        _ = update("已回答", recordUndo: false, entryMotion: false, showToast: false) {
            HomeButler.answer(item.id, in: &$0, now: Date())
        }
    }
    func beginFirstEntry(importing: Bool = false) {
        homeEntrySession = !importing && destination == .now
        guard update("开始记账", recordUndo: false, entryMotion: false, showToast: false, {
            FirstUse.prepareForEntry(&$0, now: Date())
        }) else { return }
        sheetSource = nil; sheet = importing ? .imports : .addEntry
    }
    func stopRenewal(_ renewal: HomeRenewal) {
        guard update("停掉", entryMotion: false, showToast: false, {
            try HomeButler.stop(renewal, in: &$0, now: Date())
        }) else { return }
        let provider = renewal.plan.title.replacingOccurrences(of: "会员", with: "").replacingOccurrences(of: "年付", with: "")
        homeReceipt = ButlerReceipt(title: "以后" + renewal.plan.frequency.label + "省下", amount: renewal.amount,
                                    nextStep: "记得去\(provider) App 里取消续费", undoLabel: undoLabel)
    }
}

/// Exactly one of these is visible, on both home and the top of the deck.
struct HomeTaskCard: View {
    @Environment(AppStore.self) private var store
    let item: HomeTask
    var more = 0
    @State private var sortQuestionID: UUID?
    @State private var showGroups = false
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        content.navigationDestination(isPresented: $showGroups) {
            if let id = sortQuestionID { UnsortedGroupsView(questionID: id) }
        }
    }
    @ViewBuilder private var content: some View {
        switch item {
        case .payday(let due): PaydayCard(due: due, more: more)
        case .bill(let bill): BillDueCard(bill: bill, more: more)
        case .gap(let gap): GapCard(gap: gap, more: more)
        case .leftover(let saving): NewCycleCard(saving: saving, more: more)
        case .overspend(let options): OverspendRows(options: options, more: more)
        case .renewal(let renewal): renewalCard(renewal)
        case .funding(let value): fundingCard(value)
        case .savingsTopup(let offer): SavingsTopupCard(offer: offer, more: more)
        case .cooldown(let wish): cooldownCard(wish)
        case .restraint(let restraint): restraintCard(restraint)
        case .salary(let candidate): salaryCard(candidate)
        case .imports(let pending): importsCard(pending)
        case .butler(let card): confirmationCard(card)
        case .suggestion(let suggestion): ButlerSuggestionCard(suggestion: suggestion, more: more)
        case .suggestionReview(let review): ButlerSuggestionReviewCard(review: review, more: more)
        }
    }
    @ViewBuilder private func renewalCard(_ renewal: HomeRenewal) -> some View {
        if let copy = HomeTaskCopy.make(.renewal(renewal), now: store.financialNow, hidden: hide) {
            QuestionCard(eyebrow: copy.kicker, title: copy.title, more: more,
                         yesTitle: "停掉", noTitle: "留着", yesIdentifier: "stopRenewal", noIdentifier: "keepRenewal",
                         yes: { store.stopRenewal(renewal) }, no: { store.answerHome(item) })
                .accessibilityIdentifier("renewalCard")
        }
    }
    @ViewBuilder private func fundingCard(_ value: HomeFunding) -> some View {
        if let copy = HomeTaskCopy.make(.funding(value), now: store.financialNow, hidden: hide) {
            QuestionCard(eyebrow: copy.kicker, title: copy.title, more: more,
                         yesTitle: "从" + value.source.name + "转过去", noTitle: "我自己处理", yesIdentifier: "butlerTransferFunds", noIdentifier: "butlerHandleFunding",
                         yes: { _ = store.update("已记下 1 笔") { try HomeButler.transferFunding(value, in: &$0, now: Date()) } },
                         no: { store.answerHome(item) }).accessibilityIdentifier("fundingButlerCard")
        }
    }
    private func cooldownCard(_ wish: WishItem) -> some View {
        let hours = max(0, Int((wish.coolUntil ?? store.financialNow).timeIntervalSince(wish.createdAt) / 3600))
        return QuestionCard(eyebrow: "等了 \(hours) 小时 · " + wish.title, title: "", amount: wish.amount, question: "，还想买吗", more: more,
                            yesTitle: "不买了", noTitle: "买，从存着的钱出", yesIdentifier: "butlerDropWish", noIdentifier: "butlerBuyWish",
                            yes: {
            if store.update("不买了", entryMotion: false, showToast: false, {
                try Wishlist.answerCooldown(wish.id, choice: .drop, in: &$0, now: Date())
            }) { store.homeReceipt = ButlerReceipt(title: "省下", amount: wish.amount, undoLabel: store.undoLabel) }
        }, no: {
            // Recording the purchase links the wish through the existing unique
            // match path. The source choice is preserved in the entry editor.
            store.sheetSource = nil
            store.sheet = .prefilledEntry(QuickEntryPrefill(category: wish.category, amount: wish.amount, purpose: wish.title, fromReserve: true))
        }).accessibilityIdentifier("cooldownButlerCard")
    }
    private func restraintCard(_ value: HomeRestraint) -> some View {
        let title = "这个周期 " + amount2(value.amount, hide: hide) + "，平时到今天 "
        return QuestionCard(eyebrow: "想克制的 · " + value.title, title: title, amount: value.usual, more: more,
                            yesTitle: "看这 \(value.entryIDs.count) 笔", noTitle: "知道了", yesIdentifier: "butlerRestraintEntries", noIdentifier: "butlerRestraintDone",
                            yes: {
            store.answerHome(item)
            store.resetRootNavigation(); store.ledgerPreset = LedgerPreset(mode: .detail, interval: value.interval, category: value.title); store.destination = .ledger
        }, no: { store.answerHome(item) }).accessibilityIdentifier("restraintButlerCard")
    }
    private func salaryCard(_ candidate: SalaryCandidate) -> some View {
        QuestionCard(eyebrow: "固定进账 · 每月 \(candidate.dayOfMonth) 号", title: candidate.payer, amount: candidate.amount, question: "是工资吗？", more: more,
                     yesTitle: "是工资", noTitle: "不是", yesIdentifier: "confirmSalary", noIdentifier: "rejectSalary",
                     yes: { store.confirmSalary(candidate) }, no: { store.rejectSalary(candidate) }).accessibilityIdentifier("salaryCard")
    }
    private func importsCard(_ pending: PendingImportOrganization) -> some View {
        let entries = store.evidenceEntries(Set(pending.entryIDs), activeOnly: true).filter { Classification.isPending($0) }
        let total = entries.reduce(Int64(0)) { $0 + $1.amount }
        let month = pending.dates.min().map { "\(Dates.calendar.component(.month, from: $0))月导入" } ?? "导入"
        return Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                ButlerKicker(title: "没分类 · " + month, more: more)
                Text("\(entries.count) 笔还没分类，共 " + amount2(total, hide: hide)).yubaiFont(YubaiFont.butlerTitle)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("unsortedQuestionTitle")
                ChipFlow {
                    TabNavigationLink(.triage(entries.map(\.id))) { LetterTriageView(entryIDs: entries.map(\.id)) } label: { Text("逐笔整理") }
                        .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("classifyImportsManually")
                    Button("按商户整理") {
                        var id: UUID?
                        if store.update("整理分类", recordUndo: false, entryMotion: false, showToast: false, { id = HomeButler.prepareMerchantSort(pending, in: &$0) }), let id {
                            sortQuestionID = id; showGroups = true
                        }
                    }.buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("groupUnsortedByParty")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("pendingImportsCard")
    }
    private func confirmationCard(_ card: ButlerCard) -> some View {
        let amount = HomeButler.confirmationAmount(card, in: store.current)
        return Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                ButlerKicker(title: NowFormat.monthDay(card.createdAt) + " · " + HomeButler.privacyText(card.title, hidden: hide), more: more)
                Text(amount2(amount, hide: hide)).yubaiFont(YubaiFont.butlerTitle)
                if let question = card.importQuestion, !question.isFallback,
                   let batch = store.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                    ChipFlow {
                        ForEach(Array(question.options.prefix(2).enumerated()), id: \.offset) { index, option in
                            Button(HomeButler.privacyText(option.title, hidden: hide)) { store.answerImportQuestion(question, batchID: batch.id, option: index) }
                                .buttonStyle(NowCardButtonStyle(primary: index == 0)).accessibilityIdentifier("homeImportAnswer_\(question.id)_\(index)")
                        }
                        if question.options.isEmpty {
                            Button("写用途") { store.sheet = .cardQuestion(card.id) }.buttonStyle(NowCardButtonStyle(primary: true))
                        }
                    }
                } else if let question = card.importQuestion, question.isFallback {
                    ChipFlow {
                        TabNavigationLink(.triage(question.entryIDs)) { LetterTriageView(entryIDs: question.entryIDs) } label: { Text("逐笔整理") }
                            .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("quickSortUnsorted")
                        TabNavigationLink(.unsortedGroups(question.id)) { UnsortedGroupsView(questionID: question.id) } label: { Text("按商户整理") }
                            .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("groupUnsortedByParty")
                    }
                } else {
                    Button(card.kind == .unknownInflow ? "写用途" : "看这一笔") { store.performCardAction(card) }
                        .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("butlerPrimary_" + card.id.uuidString)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("butlerCard_" + card.kind.rawValue)
    }
}


struct ButlerKicker: View {
    let title: String
    var more = 0
    var evidenceTitle: String? = nil
    var onEvidence: (() -> Void)? = nil
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
                Spacer(minLength: YubaiSpace.none)
                evidenceLink
                if more > 0 { MoreLink(count: more).fixedSize() }
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true)
                evidenceLink
                if more > 0 { MoreLink(count: more) }
            }
        }
    }
    @ViewBuilder private var evidenceLink: some View {
        if let evidenceTitle, let onEvidence {
            Button(evidenceTitle, action: onEvidence).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.brandInk)
                .fixedSize().yubaiHitTarget().buttonStyle(PressButtonStyle()).accessibilityIdentifier("butlerAIEvidence")
        }
    }
}

struct ButlerReceiptRow: View {
    @Environment(AppStore.self) private var store
    let receipt: ButlerReceipt
    var body: some View {
        Card(style: .compact) {
            HStack(spacing: YubaiSpace.space8) {
                Image(systemName: "checkmark").font(.system(size: YubaiFont.callout.size, weight: .semibold)).foregroundStyle(YubaiColor.brandInk)
                    .frame(width: YubaiSize.pillHeight, height: YubaiSize.pillHeight).background(YubaiColor.brandTint, in: Circle()).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Text(receipt.title + (receipt.amount.map { " " + amount2($0, hide: store.preferences.hideAmounts) } ?? ""))
                        .yubaiFont(YubaiFont.rowTitle, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    if let next = receipt.nextStep { Text(next).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if store.undoLabel == receipt.undoLabel, receipt.undoLabel != nil {
                    Button("撤销") { store.undo(); store.homeReceipt = nil }
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget()
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("undoButlerReceipt")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("butlerReceipt")
    }
}

struct TodoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deck = ButlerDeck()
    private var items: [HomeTask] { store.inboxItems }
    private var ids: [String] { items.map(\.id) }
    private var top: HomeTask? { deck.ids.first.flatMap { id in items.first { $0.id == id } } }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            if let top {
                HomeTaskCard(item: top)
                    .id(top.id)
                    .background(alignment: .bottom) {
                        ForEach(1..<min(3, deck.ids.count), id: \.self) { depth in
                            RoundedRectangle(cornerRadius: YubaiRadius.card).fill(YubaiColor.paperSheet)
                                .frame(height: YubaiSize.sourceRow).padding(.horizontal, CGFloat(depth) * YubaiSpace.space12)
                                .offset(y: CGFloat(depth) * YubaiSpace.space16).yubaiShadow(YubaiShadow.card).accessibilityHidden(true)
                        }
                    }
                    .padding(.bottom, CGFloat(min(2, max(0, deck.ids.count - 1))) * YubaiSpace.space16)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                    .gesture(DragGesture(minimumDistance: YubaiSpace.space24).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > YubaiSize.tapMin else { return }
                        cycle(backwards: value.translation.width > 0)
                    })
                    .accessibilityAction(named: "先看下一件") { cycle() }
                    .accessibilityAction(named: "上一件") { cycle(backwards: true) }
                VStack(spacing: YubaiSpace.gapGroup) {
                    HStack(spacing: YubaiSpace.space8) {
                        ForEach(Array(deck.ids.enumerated()), id: \.element) { index, _ in
                            Circle().fill(index == deck.position ? YubaiColor.label : YubaiColor.separator).frame(width: YubaiSize.unknownDot, height: YubaiSize.unknownDot)
                        }
                    }.accessibilityElement(children: .ignore).accessibilityLabel("第 \(deck.position + 1) 件，共 \(deck.ids.count) 件")
                        .accessibilityIdentifier("butlerDeckPosition")
                    Button("先看下一件") { cycle() }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                        .yubaiHitTarget().buttonStyle(PressButtonStyle()).accessibilityIdentifier("butlerDeckNext")
                }.frame(maxWidth: .infinity)
            }
        }.navigationTitle("还有 \(items.count) 件").yubaiNavigation().accessibilityIdentifier("letterInbox")
            .onChange(of: ids, initial: true) { _, value in
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { deck.reconcile(value) }
                if let focus = store.butlerFocusID { deck.focus(focus); store.butlerFocusID = nil }
                if value.isEmpty { dismiss() }
            }
    }
    private func cycle(backwards: Bool = false) { withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { deck.cycle(backwards: backwards) } }
}

typealias LetterInboxView = TodoView
