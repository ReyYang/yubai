import SwiftUI
import YubaiCore

/// 现在：还能花、管家说的一件事、接下来七天和最近记录。
struct NowView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    private var homeHero: HomeHero { store.homeHero }

    private var hide: Bool { store.preferences.hideAmounts }

    var body: some View {
        Group {
            if homeHero.isFirstOpen { FirstOpenView().transition(.opacity) }
            else { regularPage.transition(.opacity) }
        }.animation(reduceMotion ? nil : .easeInOut(duration: YubaiMotion.durationFirstLight), value: homeHero.isFirstOpen)
            .navigationTitle("现在").yubaiNavigation().amountPrivacy(hide)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
    private var regularPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8).padding(.bottom, YubaiSpace.gapSection)
                    .frame(maxWidth: YubaiSize.contentMaximum).frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("nowScroll")
                .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
                .rootScrollContentMargins().rootTabScroll(.now)
                .rootPageHeader { RootHeader(title: "现在") }
                .task(id: store.receiptFeedbackTrigger) {
                    let trigger = store.receiptFeedbackTrigger
                    guard !store.receiptEntryIDs.isEmpty else { return }
                    do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                    withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { proxy.scrollTo("dailyReceipt", anchor: .bottom) }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    if store.receiptFeedbackTrigger == trigger { store.receiptEntryIDs = [] }
                }
        }
    }

    // MARK: Page

    private var content: some View {
        let items = store.inboxItems
        let saving = store.homeSaving
        let pace = store.pace
        return VStack(alignment: .leading, spacing: YubaiSpace.none) {
            hero(pace)
            slot(items)
            if homeHero.hasSalaryPlan || saving.started || !store.salaryPromptDue {
                HomeSavingCardView(facts: saving).padding(.top, YubaiSpace.gapGroup)
            }
            upcoming(items)
            recent
        }
    }

    // MARK: Hero

    private func horizonText(_ pace: CyclePace?) -> String {
        guard let pace else { return store.sortedEntries.isEmpty ? "还没有账" : "这个月" }
        if store.funds.cycleIsPayday && Dates.day(pace.start) == Dates.day(store.financialNow) { return "今天发工资" }
        if let late = pace.lateDays { return late == 0 ? "今天发工资" : "工资晚了 \(late) 天" }
        let days = "还有 \(pace.daysLeft) 天"
        if textSize.isAccessibilitySize || !store.funds.cycleIsPayday { return days }
        return NowFormat.monthDay(Dates.addDays(1, to: pace.end)) + "发工资 · " + days
    }

    private func hero(_ pace: CyclePace?) -> some View {
        let facts = homeHero
        let horizon = facts.hasSalaryPlan ? horizonText(pace) : ""
        let spoken = facts.title + "，" + (hide ? "金额已隐藏" : amount2(facts.amount, hide: false))
        return VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            if facts.hasSalaryPlan {
                TabNavigationLink(.formula) { FormulaView() } label: {
                    heroContents(facts, horizon: horizon, disclosure: true)
                }.buttonStyle(PressButtonStyle()).yubaiZoomSource("funds").accessibilityIdentifier("fundsFormula")
                    .accessibilityLabel(spoken).accessibilityHint("点开看怎么算")
                if let daily = pace?.daily { dailyRow(daily) }
            } else { heroContents(facts, horizon: horizon, disclosure: false) }
        }
    }
    private func heroContents(_ facts: HomeHero, horizon: String, disclosure: Bool) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            heroTitle(facts.title, horizon)
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                AmountLabel(cents: facts.amount, hide: hide, role: .hero, ink: facts.title == "多花了" ? YubaiColor.amberInk : YubaiColor.label)
                    .accessibilityIdentifier("availableFunds")
                if disclosure { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func heroTitle(_ headline: String, _ horizon: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text(headline).yubaiFont(YubaiFont.heroLabel).fixedSize()
                Text(horizon).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(headline).yubaiFont(YubaiFont.heroLabel)
                Text(horizon).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            }
        }
    }

    private func dailyRow(_ daily: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text("日均").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: daily, hide: hide, role: .summary, currency: false)
        }.accessibilityElement(children: .combine)
            .accessibilityLabel("日均 " + (hide ? "金额已隐藏" : amount2(daily, hide: false))).accessibilityIdentifier("dailyPace")
    }

    // MARK: Card slot

    @ViewBuilder private func slot(_ items: [HomeTask]) -> some View {
        Group {
            if store.salaryPromptDue {
                QuestionCard(eyebrow: "想知道还能花多少", title: "每月几号发工资，发多少", more: items.count,
                             yesTitle: "填一下", noTitle: "以后再说", yesIdentifier: "setupFirstSalary", noIdentifier: "deferFirstSalary",
                             yes: { store.sheetSource = nil; store.sheet = .paydaySetup }, no: {
                    _ = store.update("以后再说", recordUndo: false, entryMotion: false, showToast: false) {
                        FirstUse.deferSalarySetup(&$0, now: store.financialNow)
                    }
                }).accessibilityIdentifier("firstSalaryCard")
            } else if let receipt = store.homeReceipt {
                ButlerReceiptRow(receipt: receipt)
                    .task(id: receipt.id) {
                        #if DEBUG && targetEnvironment(simulator)
                        if UITestSupport.keepsUndoReceipt { return }
                        #endif
                        do { try await Task.sleep(for: .seconds(6)) } catch { return }
                        if store.homeReceipt?.id == receipt.id { store.homeReceipt = nil }
                    }
            } else if (store.organizingPendingImports || store.organizingBatchID != nil) && (items.first?.id.hasPrefix("imports:") ?? true) {
                ImportBusyRow(pending: store.pendingOrganization)
            } else if let first = items.first {
                HomeTaskCard(item: first, more: items.count - 1)
            }
        }.padding(.top, YubaiSpace.gapGroup + YubaiSpace.space2)
    }

    // MARK: 接下来 7 天

    private func upcomingRows(_ items: [LetterItem]) -> [Occurrence] {
        let due = store.paydayDue
        let carded = Set(items.compactMap { item -> String? in if case .bill(let bill) = item { return bill.id }; return nil })
        return HomeButler.upcoming(store.current, now: store.financialNow).filter { occurrence in
            guard !carded.contains(occurrence.id) else { return false }
            if occurrence.inflow, occurrence.planID != nil, occurrence.planID == due?.planID { return false }
            return true
        }
    }

    @ViewBuilder private func upcoming(_ items: [LetterItem]) -> some View {
        let rows = upcomingRows(items)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("接下来 7 天").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    Spacer(minLength: YubaiSpace.gapGroup)
                    TabNavigationLink(.fixedFlows) { FixedFlowsView() } label: {
                        HStack(spacing: YubaiSpace.space2) {
                            Text("全部")
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget(alignment: .trailing)
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openFixedFlows")
                }.padding(.horizontal, YubaiSpace.space4)
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NowUpcomingRow(row: row)
                            if index < rows.count - 1 { Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator) }
                        }
                    }
                }
            }.padding(.top, YubaiSpace.gapSection - YubaiSpace.space2)
        }
    }

    // MARK: 今天记的

    private var recent: some View {
        HomeReceiptView(receipt: store.dailyReceipt)
            .id("dailyReceipt").padding(.top, YubaiSpace.gapSection - YubaiSpace.space2)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: store.receiptFeedbackTrigger)
    }
}

/// 接下来 7 天里的一行：日期、名字、金额、右边的勾。
private struct NowUpcomingRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let row: Occurrence
    private var hide: Bool { store.preferences.hideAmounts }
    private var estimated: Bool {
        guard let id = row.planID, !row.inflow else { return false }
        return store.plans.first { $0.id == id }?.estimated == true
    }
    private var checkable: Bool { row.planID != nil && !row.inflow }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        layout {
            Text(NowFormat.monthDay(row.date)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                .frame(minWidth: textSize.isAccessibilitySize ? nil : YubaiSize.rowDouble, alignment: .leading).fixedSize()
            if let planID = row.planID, !row.inflow {
                TabNavigationLink(.billDetail(planID)) { BillDetailView(planID: planID) } label: {
                    Text(row.title).yubaiFont(YubaiFont.body).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("formulaBill_" + planID.uuidString)
            } else {
                Text(row.title).yubaiFont(YubaiFont.body).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: YubaiSpace.space8) {
                if estimated && !hide { Text("约").yubaiFont(YubaiFont.amount) }
                AmountLabel(cents: row.amount, hide: hide, sign: row.inflow ? .inflow : .outflow, ink: row.inflow ? YubaiColor.brandInk : YubaiColor.label)
                    .fixedSize(horizontal: true, vertical: false)
                if checkable, let planID = row.planID {
                    BillCheck(planID: planID, occurrence: Dates.day(row.date)).frame(minWidth: YubaiSize.tapMin, minHeight: YubaiSize.tapMin)
                }
            }
        }.padding(.vertical, YubaiSpace.space4).frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle, alignment: .leading)
            .accessibilityElement(children: .contain)
    }
}
