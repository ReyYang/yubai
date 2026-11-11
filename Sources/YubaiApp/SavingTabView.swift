import SwiftUI
import YubaiCore

/// 存钱：存下的钱、每月存、最近进出、心愿单。
struct SavingTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    private var hide: Bool { store.preferences.hideAmounts }
    private var overview: ReserveOverview { store.reserve }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
                hero
                monthlyRow
                recentSection
                wishSection
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.rootScrollContentMargins().rootTabScroll(.saving)
            .rootPageHeader { RootHeader(title: "存钱") }
            .amountPrivacy(hide).accessibilityIdentifier("savingTabScroll")
            .navigationTitle("存钱").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }

    // MARK: 存下的
    private var hero: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: YubaiSpace.gapGroup))
        return VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text("存下的").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            layout {
                AmountLabel(cents: overview.total, hide: hide, role: .hero, ink: YubaiColor.label)
                    .accessibilityIdentifier("reserveTotal")
                if overview.setAside > 0 {
                    Text("这个月已存进 " + amount2(overview.setAside, hide: hide)).yubaiFont(YubaiFont.callout)
                        .foregroundStyle(YubaiColor.brandInk)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 每月存
    private var monthlyRow: some View {
        TabNavigationLink(.savingRule) { SavingsView(backTitle: "存钱") } label: {
            Card(style: .list) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    Text("每月存").yubaiFont(YubaiFont.rowTitle)
                    Spacer(minLength: YubaiSpace.space8)
                    Text(monthlyValue).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    chevron
                }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openSavings")
            .accessibilityLabel("每月存，" + monthlyValue)
    }
    private var monthlyValue: String {
        if hide { return "••••" }
        switch store.current.savingRule {
        case .fixed(let value): return amount2(value, hide: false)
        case .share(let percent): return savingShare(percent)
        case nil: return "还没设"
        }
    }

    // MARK: 最近进出
    @ViewBuilder private var recentSection: some View {
        let lines = Array(overview.lines.prefix(3))
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                sectionHeading("最近进出") {
                    TabNavigationLink(.reserve) { ReserveView() } label: { more }
                        .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openReserve")
                }
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            ReserveLineRow(line: line, hide: hide).accessibilityIdentifier("reserveLine_\(index)")
                            if index < lines.count - 1 { EntryFormDivider() }
                        }
                    }
                }
            }
        }
    }

    // MARK: 心愿单
    private var wishSection: some View {
        let wishes = wishRows
        return VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            sectionHeading("心愿单") {
                TabNavigationLink(.wishlist) { WishlistView() } label: { more }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openWishlist")
            }
            if !wishes.isEmpty {
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(Array(wishes.enumerated()), id: \.element.id) { index, wish in
                            wishRow(wish)
                            if index < wishes.count - 1 { EntryFormDivider() }
                        }
                    }
                }
            }
        }
    }
    private var wishRows: [WishItem] {
        let now = Date()
        let thinking = store.current.wishlist.filter { $0.status == .thinking }
        let due = Set(Wishlist.cooldownDue(store.current, now: now).compactMap { candidate -> UUID? in
            if case .openWish(let id) = candidate.action { return id }
            return nil
        })
        let sorted = thinking.sorted { lhs, rhs in
            let l = due.contains(lhs.id), r = due.contains(rhs.id)
            return l != r ? l : lhs.createdAt > rhs.createdAt
        }
        return Array(sorted.prefix(3))
    }
    private func wishRow(_ wish: WishItem) -> some View {
        TabNavigationLink(.wishlist) { WishlistView() } label: {
            HStack(spacing: YubaiSpace.gapGroup) {
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Text(wish.title).yubaiFont(YubaiFont.rowTitle)
                    Text(wishSubtitle(wish)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                AmountLabel(cents: wish.amount, hide: hide, role: .amount)
                chevron
            }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle())
    }
    private func wishSubtitle(_ wish: WishItem) -> String {
        let now = Date()
        let days = max(0, Dates.calendar.dateComponents([.day], from: Dates.day(wish.createdAt), to: Dates.day(now)).day ?? 0)
        guard let until = wish.coolUntil else { return "放了 \(days) 天" }
        if until <= now { return "放了 \(days) 天 · 该回头看了" }
        let remaining = max(1, Dates.calendar.dateComponents([.day], from: Dates.day(now), to: Dates.day(until)).day ?? 1)
        return "还有 \(remaining) 天"
    }

    // MARK: 小件
    private func sectionHeading<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
            Spacer(minLength: YubaiSpace.space8)
            trailing()
        }.padding(.horizontal, YubaiSpace.space4)
    }
    private var more: some View {
        HStack(spacing: YubaiSpace.space4) {
            Text("全部")
            Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta)
        }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
            .frame(minWidth: YubaiSize.tapMin, minHeight: YubaiSize.tapMin, alignment: .trailing).contentShape(Rectangle())
    }
    private var chevron: some View {
        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
    }
}

/// 存着的钱的一行进出：日期、名字、带符号的金额。
struct ReserveLineRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let line: ReserveLine
    let hide: Bool
    private var title: String {
        if !line.title.isEmpty { return line.title }
        switch line.kind {
        case .monthly: return "这个月存的"
        case .leftover: return "剩下的"
        case .cover: return "补超支"
        case .adjust: return "调整"
        case .income, .purchase: return "存着的钱"
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
                .frame(minWidth: textSize.isAccessibilitySize ? 0 : 56, alignment: .leading)
            Text(title).yubaiFont(YubaiFont.row).frame(maxWidth: .infinity, alignment: .leading)
            amountView
        }.frame(minHeight: YubaiSize.rowDouble).accessibilityElement(children: .combine)
            .accessibilityLabel(dateText + "，" + title + "，" + (hide ? "金额已隐藏" : AmountLabel.text(line.amount, sign: .automatic)))
    }
}
