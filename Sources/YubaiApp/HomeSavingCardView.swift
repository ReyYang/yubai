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
                    if facts.started {
                        VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                            AdaptiveValueRow {
                                Text("存下了").yubaiFont(YubaiFont.rowTitle).fixedSize()
                            } value: {
                                AmountLabel(cents: facts.total, hide: hide, role: .summary)
                            }
                            secondLine
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                    } else { startSaving }
                }.frame(minHeight: YubaiSize.savingCardMinimum - YubaiSpace.insetCard * 2)
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openSaving")
            .accessibilityLabel(spoken).accessibilityHint("打开存钱")
    }
    private var startSaving: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) {
                Text("还没开始存").yubaiFont(YubaiFont.rowTitle).fixedSize()
                Spacer(minLength: YubaiSpace.none)
                startLabel
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("还没开始存").yubaiFont(YubaiFont.rowTitle)
                startLabel
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var startLabel: some View {
        Text("开始存钱").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.onBrand)
            .fixedSize().padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.tapMin)
            .background(YubaiColor.brand, in: Capsule())
    }
    @ViewBuilder private var secondLine: some View {
        switch facts.state {
        case let .wish(_, title, shortfall, progress):
            VStack(spacing: YubaiSpace.space6) {
                AdaptiveValueRow {
                    Text(title).yubaiFont(YubaiFont.callout).lineLimit(1).truncationMode(.tail).accessibilityIdentifier("truncatableName")
                } value: {
                    if shortfall > 0 {
                        AdaptiveValueRow(spreadsValue: false) {
                            Text("还差").yubaiFont(YubaiFont.callout).fixedSize()
                        } value: {
                            AmountLabel(cents: shortfall, hide: hide, role: .small, ink: YubaiColor.labelSecondary)
                        }.layoutPriority(1).foregroundStyle(YubaiColor.labelSecondary)
                    } else { Text("够了").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).fixedSize() }
                }
                ProgressLine(value: hide ? 0 : progress, tint: YubaiColor.brand, track: YubaiColor.card, height: YubaiSpace.space4).accessibilityHidden(true)
            }
        case .monthly(let amount):
            AdaptiveValueRow {
                Text("每月先存").yubaiFont(YubaiFont.callout).fixedSize()
            } value: {
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
