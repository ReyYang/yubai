import SwiftUI
import YubaiCore

struct SavingTabView: View {
    @Environment(AppStore.self) private var store
    @State private var transferDirection: SavingsTransfer.Direction?
    @State private var editingFloor = false
    @State private var settingTarget = false
    @State private var addingWish = false
    @State private var postponed = false
    @State private var monthlyIncrease: Int64?
    @State private var fundingByWish: [UUID: WishFunding] = [:]
    private var hide: Bool { store.preferences.hideAmounts }
    private var overview: ReserveOverview { store.reserve }
    private var wishes: [WishItem] { store.current.wishlist.filter { $0.status == .thinking }.sorted { $0.createdAt < $1.createdAt } }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection, topPadding: YubaiSpace.space8) {
            VStack(spacing: YubaiSpace.space12) {
                hero
                transferButtons
                floorRow
            }
            if store.current.savingRule == nil && !postponed { firstSaving }
            if !store.current.wishlist.isEmpty { wishSection }
            settingsRows
        }.accessibilityIdentifier("savingTabScroll")
            .amountPrivacy(hide)
            .navigationTitle("存钱").yubaiNavigation()
            .task(id: "\(store.ledgerRevision)-\(store.financialNow)") { await refreshFacts() }
            .sheet(isPresented: Binding(get: { transferDirection != nil }, set: { if !$0 { transferDirection = nil } })) {
                if let direction = transferDirection {
                    SavingsTransferSheet(direction: direction).environment(store).appErrors().yubaiSheetBackground().presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $editingFloor) {
                SavingsFloorSheet(initial: store.current.profile.floorAmount).environment(store).appErrors().yubaiSheetBackground().presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $settingTarget) {
                SavingsAmountEditor(field: .target, initial: 0) { value in
                    store.update("每月存") { $0.savingRule = .fixed(value) }
                }.environment(store).yubaiSheetBackground().presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $addingWish) { NavigationStack { WishEditor() }.environment(store).appErrors().yubaiSheetBackground() }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("存下了").yubaiFont(YubaiFont.cardTitle)
            AmountLabel(cents: overview.total, hide: hide, role: .hero).accessibilityIdentifier("reserveTotal")
            if let change = monthlyIncrease, store.current.savingRule != nil || overview.total != 0 {
                HStack(spacing: YubaiSpace.space4) {
                    Text("这个月").yubaiFont(YubaiFont.callout)
                    AmountLabel(cents: change, hide: hide, role: .small, sign: change >= 0 ? .inflow : .outflow, ink: YubaiColor.brandInk)
                }.foregroundStyle(YubaiColor.brandInk).accessibilityIdentifier("savingMonthlyIncrease")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var transferButtons: some View {
        HStack(spacing: YubaiSpace.space8) {
            Button("拿出来用") { transferDirection = .take }
                .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("takeSavings")
            Button("放回去") { transferDirection = .putBack }
                .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity).accessibilityIdentifier("putBackSavings")
        }
    }
    private var floorRow: some View {
        Button { editingFloor = true } label: {
            VStack(spacing: YubaiSpace.space4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) {
                        Text("想一直留着").yubaiFont(YubaiFont.callout).fixedSize()
                        Spacer(minLength: YubaiSpace.space8)
                        floorValue
                    }
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text("想一直留着").yubaiFont(YubaiFont.callout)
                        floorValue.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                if let floor = store.current.profile.floorAmount, floor > 0, !hide {
                    SavingsFloorBar(total: overview.total, floor: floor).accessibilityHidden(true)
                }
            }.frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).foregroundStyle(YubaiColor.labelSecondary).accessibilityIdentifier("editSavingsFloor")
    }
    private var floorValue: some View {
        HStack(spacing: YubaiSpace.space8) {
            if let floor = store.current.profile.floorAmount { AmountLabel(cents: floor, hide: hide, role: .small, ink: YubaiColor.labelSecondary) }
            Image(systemName: "pencil").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
        }
    }
    private var firstSaving: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("每月先存").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Text("发工资那天，先留出多少？").yubaiFont(YubaiFont.cardTitle)
                ChipFlow {
                    Button("定一个数") { settingTarget = true }.buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityIdentifier("setFirstSavingTarget")
                    Button("以后再说") { postponed = true }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.card, compact: true)).accessibilityIdentifier("postponeSavingTarget")
                }
            }
        }.accessibilityIdentifier("savingFirstRule")
    }
    private var wishSection: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            HStack {
                TabNavigationLink(.wishlist) { WishlistView() } label: { Text("心愿").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openWishlist")
                Spacer(minLength: YubaiSpace.space8)
                Button { addingWish = true } label: { Label("添一个", systemImage: "chevron.right").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk) }
                    .buttonStyle(PressButtonStyle()).yubaiHitTarget().accessibilityIdentifier("addSavingWish")
            }.padding(.horizontal, YubaiSpace.space4)
            CardRows(wishes) { wish in
                TabNavigationLink(.savingWish(wish.id)) { WishlistView(focusedWishID: wish.id) } label: { wishRow(wish) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("savingWish_" + wish.id.uuidString)
            }
        }
    }
    private func wishRow(_ wish: WishItem) -> some View {
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) { Text(wish.title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1); Spacer(minLength: YubaiSpace.space8); AmountLabel(cents: wish.amount, hide: hide) }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(wish.title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1); AmountLabel(cents: wish.amount, hide: hide) }
            }
            if let funding = fundingByWish[wish.id] {
                if funding.shortfall > 0 && !hide { ProgressLine(value: funding.progress, tint: YubaiColor.brand) }
                fundingFacts(funding).accessibilityIdentifier("savingWishFunding_" + wish.id.uuidString)
            }
        }.padding(.vertical, YubaiSpace.space12).contentShape(Rectangle())
    }
    @ViewBuilder private func fundingFacts(_ funding: WishFunding) -> some View {
        if funding.shortfall == 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space4) { Text("存下的钱够了，买完还剩").fixedSize(); fundingAmount(funding.remainingAfterPurchase).fixedSize() }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text("存下的钱够了，买完还剩"); fundingAmount(funding.remainingAfterPurchase) }
            }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
        } else {
            ChipFlow(spacing: YubaiSpace.space4, rowSpacing: YubaiSpace.space4) {
                Text("还差").yubaiFont(YubaiFont.callout)
                fundingAmount(funding.shortfall)
                if let date = funding.enoughOn, let monthly = funding.monthly {
                    Text("· 照每月存").yubaiFont(YubaiFont.callout)
                    fundingAmount(monthly)
                    Text("，" + FixedFlowPresentation.monthDay(date) + " 够").yubaiFont(YubaiFont.callout).dynamicTypeSize(...DynamicTypeSize.xxxLarge).fixedSize()
                }
            }.foregroundStyle(YubaiColor.brandInk)
        }
    }
    private func fundingAmount(_ amount: Int64) -> some View { AmountLabel(cents: amount, hide: hide, role: .small, ink: YubaiColor.brandInk) }
    @MainActor private func refreshFacts() async {
        let ledger = store.current; let now = store.financialNow
        let value = await Task.detached(priority: .userInitiated) {
            let fundings = ledger.wishlist.filter { $0.status == .thinking }.map {
                ($0.id, SavingInsights.funding(for: $0, ledger: ledger, now: now))
            }
            return (SavingInsights.monthlyIncrease(ledger, now: now), Dictionary(uniqueKeysWithValues: fundings))
        }.value
        guard !Task.isCancelled else { return }
        monthlyIncrease = value.0; fundingByWish = value.1
    }
    private var settingsRows: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                if store.current.savingRule != nil || postponed {
                    TabNavigationLink(.savingRule) { SavingsView() } label: { navigationRow("每月先存", value: monthlyValue) }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openSavings")
                    EntryFormDivider()
                }
                TabNavigationLink(.saved) { SavedView() } label: { navigationRow("余白帮你省下", value: amount2(store.butlerSaved, hide: hide)) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openButlerSaved")
                EntryFormDivider()
                TabNavigationLink(.reserve) { ReserveView() } label: { navigationRow("存取记录", value: "") }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openReserve")
            }
        }
    }
    private var monthlyValue: String {
        let value: String
        switch store.current.savingRule {
        case .fixed(let amount): value = amount2(amount, hide: hide)
        case .share(let percent): value = hide ? "••••" : savingShare(percent)
        case nil: return ""
        }
        return value + " · " + (store.funds.cycleIsPayday ? "发工资那天" : "每月 1 号")
    }
    private func navigationRow(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { Text(title).yubaiFont(YubaiFont.row).fixedSize(); Spacer(minLength: YubaiSpace.space8); Text(value).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary); chevron }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(title).yubaiFont(YubaiFont.row); HStack { Text(value).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary); Spacer(); chevron } }
        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
    }
    private var chevron: some View { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true) }
}

/// 存着的钱的一行进出：日期、名字、带符号的金额。
struct ReserveLineRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let line: ReserveLine
    let hide: Bool
    private var title: String {
        if line.paybackID != nil { return "这个月存的" }
        if !line.title.isEmpty { return line.title }
        switch line.kind {
        case .monthly: return "这个月存的"
        case .leftover: return "剩下的"
        case .cover: return "补超支"
        case .adjust: return "调整"
        case .income, .purchase: return "存下的钱"
        case .transfer(_, let direction): return direction == .take ? "拿出来用" : "放回去"
        }
    }
    private var dateText: String { FixedFlowPresentation.monthDay(line.date) }
    private var amountView: some View {
        AmountLabel(cents: line.amount, hide: hide, role: .amount, sign: line.amount >= 0 ? .inflow : .outflow,
                    ink: line.amount >= 0 ? YubaiColor.brandInk : YubaiColor.label)
    }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        layout {
            Text(dateText).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                .frame(minWidth: textSize.isAccessibilitySize ? YubaiSpace.none : YubaiSize.rowDouble, alignment: .leading)
            Text(title).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            amountView
        }.frame(minHeight: YubaiSize.rowDouble).accessibilityElement(children: .combine)
            .accessibilityLabel(dateText + "，" + title + "，" + (hide ? "金额已隐藏" : AmountLabel.text(line.amount, sign: .automatic)))
    }
}

private struct SavingsFloorBar: View {
    let total: Int64
    let floor: Int64
    private var maximum: Double { Double(max(1, max(total, floor))) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(YubaiColor.separator).frame(height: YubaiSpace.space4)
                Capsule().fill(YubaiColor.brand.opacity(0.45)).frame(width: geometry.size.width * min(1, max(0, Double(total) / maximum)), height: YubaiSpace.space4)
                Rectangle().fill(YubaiColor.label).frame(width: YubaiSize.separator, height: YubaiSpace.space16)
                    .offset(x: min(geometry.size.width - YubaiSize.separator, geometry.size.width * Double(floor) / maximum))
            }.frame(height: YubaiSpace.space16)
        }.frame(height: YubaiSpace.space16)
    }
}
