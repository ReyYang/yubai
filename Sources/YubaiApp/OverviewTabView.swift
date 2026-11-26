import SwiftUI
import YubaiCore

enum OverviewSegment: String, CaseIterable {
    case review = "复盘", assets = "资产"
}

struct OverviewTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiRootNavigationHeight) private var tabHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = OverviewRenderCounts.hit("overviewBody")
        VStack(spacing: .zero) {
            DSSegmented(options: OverviewSegment.allCases.map(\.rawValue), selection: Binding(
                get: { store.overviewSegment.rawValue },
                set: { if let segment = OverviewSegment(rawValue: $0) { store.overviewSegment = segment } }
            ), identifierPrefix: "overviewSegment_")
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .frame(height: DS.Size.tapMin)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: .zero) {
                        Color.clear.frame(height: .zero).id("overviewTop").accessibilityHidden(true)
                        switch store.overviewSegment {
                        case .review: ReviewView()
                        case .assets: AssetsView()
                        }
                    }
                    .padding(.horizontal, DS.Space.s20)
                    .padding(.bottom, tabHeight)
                }
                .accessibilityIdentifier("overviewScroll")
                .onChange(of: store.overviewSegment) { proxy.scrollTo("overviewTop", anchor: .top) }
                .onChange(of: store.rootScrollRequest[.insights, default: 0]) {
                    withAnimation(reduceMotion ? nil : DSMotion.smoothAnimation) { proxy.scrollTo("overviewTop", anchor: .top) }
                }
            }
        }
        .background(DS.Color.bg.ignoresSafeArea())
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

enum OverviewDisplay {
    static func money(_ amount: Int64, hidden: Bool, currency: Bool = false) -> String {
        HomeDisplay.money(amount, hidden: hidden, currency: currency).replacingOccurrences(of: "-", with: "−")
    }

    static func range(_ range: ClosedRange<Date>) -> String {
        OverviewAnalytics.monthDay(range.lowerBound) + " – " + OverviewAnalytics.monthDay(range.upperBound)
    }

    static func date(_ date: Date) -> String {
        String(Dates.calendar.component(.year, from: date)) + "." + OverviewAnalytics.monthDay(date)
    }

    static func day(_ date: Date, now: Date) -> String {
        if Dates.day(date) == Dates.day(now) { return "今天" }
        if Dates.day(date) == Dates.addDays(-1, to: Dates.day(now)) { return "昨天" }
        return OverviewAnalytics.monthDay(date)
    }

    static func percent(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        return (rounded < 0 ? "−" : rounded > 0 ? "+" : "") + "\(abs(rounded))%"
    }

    static func share(_ amount: Int64, of total: Int64) -> String {
        (total > 0 ? Double(amount) / Double(total) : 0).formatted(.percent.precision(.fractionLength(0)))
    }
}

struct OverviewNavigationBar: View {
    let title: String
    var edit: (() -> Void)? = nil
    var add: (() -> Void)? = nil
    var addLabel = "添加"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Text(title).dsText(DS.Font.tTitle).lineLimit(1)
                .frame(minHeight: DS.Size.tapMin)
                .padding(.horizontal, OverviewSpec.accountNavWing)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    DSIconView(icon: .back, size: HomeSpec.navIcon, color: DS.Color.ink)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                        .contentShape(Rectangle())
                }.dsPressStyle().accessibilityLabel("返回").accessibilityIdentifier("BackButton")
                Spacer(minLength: .zero)
                if let add {
                    Button(action: add) {
                        DSIconView(icon: .add, size: DS.Size.icon, color: DS.Color.accentInk)
                            .frame(width: DS.Size.tapMin, height: DS.Size.tapMin).contentShape(Rectangle())
                    }.dsPressStyle().accessibilityLabel(addLabel).accessibilityIdentifier("navAdd")
                }
                if let edit {
                    Button(action: edit) {
                        Text("编辑").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk)
                            .padding(.horizontal, DS.Space.s12)
                            .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
                    }.dsPressStyle().accessibilityIdentifier("editAccount")
                }
            }.padding(.horizontal, DS.Space.s8)
        }.foregroundStyle(DS.Color.ink)
    }
}

struct OverviewBillRow: View {
    let entry: Entry
    let amount: String
    let date: String
    let tint: Color
    var swatch: Color? = nil
    let separator: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            DSListRow(icon: nil, name: entry.displayTitle, amount: amount, separator: separator,
                      amountColor: tint, inline: .init(date: date, swatch: swatch))
                .contentShape(Rectangle())
        }.dsPressStyle().accessibilityIdentifier("overviewBill_" + entry.id.uuidString)
    }
}

struct OverviewSheet<Content: View>: View {
    let title: String
    let motion: EntrySheetMotion
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled

    private var reduced: Bool { !animationsEnabled || (reduceMotionOverride ?? systemReduceMotion) }

    var body: some View {
        let _ = OverviewRenderCounts.hit("overviewSheetBody")
        ZStack(alignment: .bottom) {
            EntryScrimView(motion: motion, color: DS.Color.scrim, close: dismiss)
                .ignoresSafeArea()
            VStack(spacing: .zero) {
                VStack(spacing: .zero) {
                    EntryGrabber()
                    Text(title).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: OverviewSpec.sheetHeader, alignment: .leading)
                        .padding(.horizontal, DS.Space.s20)
                        .accessibilityAddTraits(.isHeader)
                }.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: EntrySpec.dragMinimum, coordinateSpace: .global)
                        .onChanged { motion.drag($0) }
                        .onEnded { motion.release($0, reduced: reduced, onClose: close) })
                ViewThatFits(in: .vertical) {
                    VStack(spacing: .zero, content: content)
                    ScrollView { VStack(spacing: .zero, content: content) }.scrollIndicators(.hidden)
                }
            }
            .background(DS.Color.bg)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: DS.Radius.sheet, topTrailingRadius: DS.Radius.sheet, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, dismiss)
            .modifier(EntrySheetPositionModifier(motion: motion, reduced: reduced, onClose: close, tracksOverview: true))
        }.ignoresSafeArea(edges: .bottom)
    }

    private func dismiss() { motion.close(reduced: reduced, onClose: close) }
}

#if DEBUG
#Preview("全景 · 复盘") {
    RootView().environment(AppStore(overviewFixture: .review))
}

#Preview("全景 · 资产") {
    RootView().environment(AppStore(overviewFixture: .assets))
}
#endif
