import SwiftUI
import YubaiCore

struct HomeSavingCardView: View {
    @Environment(AppStore.self) private var store
    let facts: HomeSavingCard
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        TabNavigationLink(.saving) { SavingTabView() } label: {
            Card(style: .compact) {
                HStack(spacing: YubaiSpace.gapGroup) {
                    SavingJarOutline().stroke(YubaiColor.brandInk, style: StrokeStyle(lineWidth: YubaiSize.outline, lineCap: .round, lineJoin: .round))
                        .frame(width: YubaiSize.headerIcon, height: YubaiSize.headerIcon)
                        .frame(width: YubaiSize.savingIcon, height: YubaiSize.savingIcon)
                        .background(YubaiColor.brandTint, in: RoundedRectangle(cornerRadius: YubaiRadius.control)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                        if facts.started {
                            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                                Text("存下了").yubaiFont(YubaiFont.rowTitle).fixedSize()
                                Spacer(minLength: YubaiSpace.none)
                                AmountLabel(cents: facts.total, hide: hide, role: .summary).layoutPriority(1)
                            }
                            secondLine
                        } else {
                            Text("还没开始存").yubaiFont(YubaiFont.rowTitle).lineLimit(1).minimumScaleFactor(0.75)
                            Text("开始存钱").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.onBrand)
                                .padding(.horizontal, YubaiSpace.space12).padding(.vertical, YubaiSpace.space4)
                                .background(YubaiColor.brand, in: Capsule())
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                }.frame(minHeight: YubaiSize.savingCardMinimum - YubaiSpace.insetCard * 2)
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openSaving")
            .accessibilityElement(children: .ignore).accessibilityLabel(spoken).accessibilityHint("打开存钱")
    }
    @ViewBuilder private var secondLine: some View {
        switch facts.state {
        case let .wish(_, title, shortfall, progress):
            VStack(spacing: YubaiSpace.space6) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text(title).yubaiFont(YubaiFont.callout).lineLimit(1).truncationMode(.tail).accessibilityIdentifier("truncatableName")
                    Spacer(minLength: YubaiSpace.none)
                    if shortfall > 0 {
                        HStack(spacing: YubaiSpace.space4) {
                            Text("还差").yubaiFont(YubaiFont.callout).fixedSize()
                            AmountLabel(cents: shortfall, hide: hide, role: .small, ink: YubaiColor.labelSecondary)
                        }.layoutPriority(1).foregroundStyle(YubaiColor.labelSecondary)
                    } else { Text("够了").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).fixedSize() }
                }
                ProgressLine(value: hide ? 0 : progress, tint: YubaiColor.brand, track: YubaiColor.card, height: YubaiSpace.space4).accessibilityHidden(true)
            }
        case .monthly(let amount):
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("每月先存").yubaiFont(YubaiFont.callout).fixedSize()
                Spacer(minLength: YubaiSpace.none)
                AmountLabel(cents: amount, hide: hide, role: .small, ink: YubaiColor.labelSecondary)
            }.foregroundStyle(YubaiColor.labelSecondary)
        case .notStarted: EmptyView()
        }
    }
    private var spoken: String {
        let total = hide ? "金额已隐藏" : amount2(facts.total, hide: false)
        switch facts.state {
        case .notStarted: return "还没开始存，开始存钱"
        case .monthly(let amount): return "存下了 " + total + "，每月先存 " + amount2(amount, hide: hide)
        case let .wish(_, title, shortfall, _): return "存下了 " + total + "，" + title + (shortfall > 0 ? "，还差 " + amount2(shortfall, hide: hide) : "，够了")
        }
    }
}
