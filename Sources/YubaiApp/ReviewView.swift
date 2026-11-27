import SwiftUI
import YubaiCore

struct ReviewView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = OverviewRenderCounts.hit("reviewBody")
        let selection = store.overviewPeriod
        let snapshot = OverviewAnalytics.review(in: store.current, selection: selection, now: store.financialNow)
        let hidden = store.preferences.hideAmounts
        VStack(alignment: .leading, spacing: .zero) {
            Button { store.reviewPeriodSheet = selection } label: {
                HStack(alignment: .firstTextBaseline, spacing: OverviewSpec.inlineGap) {
                    Text(OverviewPeriodChoice(selection).title).dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink)
                    Text(OverviewDisplay.range(snapshot.window.displayedRange)).dsText(DS.Font.tSub)
                        .monospacedDigit().foregroundStyle(DS.Color.ink3)
                    DSIconView(icon: .chevronDown, size: DS.Space.s12, color: DS.Color.ink3)
                }.lineLimit(1)
                    .padding(.leading, DS.Space.s12).padding(.trailing, OverviewSpec.pillTrailing)
                    .frame(minHeight: DS.Size.chipH).dsPill()
                    .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
            }.dsPressStyle().accessibilityIdentifier("overviewPeriod")
                .padding(.top, OverviewSpec.periodTop)

            totals(snapshot, hidden: hidden).padding(.top, OverviewSpec.totalsTop)
            // Spec-Issues 9: unsorted bills make any 多花 unreliable, so the card asks for them first.
            if let unsorted = snapshot.unsorted {
                ReviewUnsortedCard(count: unsorted.count, share: snapshot.spent > 0 ? Double(unsorted.amount) / Double(snapshot.spent) : 0) {
                    store.tabRouteRequest = .triage(snapshot.unsortedEntryIDs)
                }.padding(.top, DS.Space.s20)
            } else if let anomaly = snapshot.anomaly {
                DSAlertCard(title: anomaly.category + "多花了 " + OverviewDisplay.money(anomaly.amount - anomaly.previous, hidden: hidden),
                            subtitle: OverviewDisplay.money(anomaly.amount, hidden: hidden)
                            + " · 近 \(snapshot.anomalyBaselineCycles) 期同期平均 " + OverviewDisplay.money(anomaly.previous, hidden: hidden)) {
                    store.tabRouteRequest = .anomaly(category: anomaly.category, selection: store.overviewPeriod)
                }.accessibilityIdentifier("overviewAnomaly").padding(.top, DS.Space.s20)
            }
            if !snapshot.slices.isEmpty {
                Text("钱都去哪了").dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink3)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, OverviewSpec.sectionTop).padding(.bottom, DS.Space.s8)
                DSDonut(slices: snapshot.slices.map {
                    DSDonut.Slice(id: $0.category, name: $0.category, value: Double($0.amount),
                                  amount: OverviewDisplay.money($0.amount, hidden: hidden), isAnomaly: $0.isAnomaly,
                                  delta: hidden ? nil : $0.changePercent.map(OverviewDisplay.percent))
                }, showsShares: !hidden, hidesAmounts: hidden) { id in
                    if let category = snapshot.slices.first(where: { $0.id == id }) { open(category) }
                }.accessibilityElement(children: .contain)
                    .accessibilityIdentifier("overviewDonut")
            }
        }.dsFillWidth().accessibilityElement(children: .contain).accessibilityIdentifier("reviewPage")
    }

    private func totals(_ value: OverviewReviewSnapshot, hidden: Bool) -> some View {
        HStack(alignment: .bottom, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: OverviewSpec.headingGap) {
                Text("花了").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink2)
                Text(OverviewDisplay.money(value.spent, hidden: hidden, currency: true)).dsText(DS.Font.nHero)
                    .foregroundStyle(DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                    .accessibilityLabel(hidden ? "金额已隐藏" : OverviewDisplay.money(value.spent, hidden: false, currency: true))
                    .accessibilityIdentifier("overviewSpent")
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
                    Text("比上期同期").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                    Text(HomeDisplay.signed(value.spent - value.previousSpent, hidden: hidden))
                        .dsText(DS.Font.tPill).fontWeight(.semibold).monospacedDigit().foregroundStyle(DS.Color.ink)
                }.lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            }
            Spacer(minLength: .zero)
            VStack(alignment: .trailing, spacing: OverviewSpec.headingGap) {
                Text("攒下").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink2)
                Text(OverviewDisplay.money(value.saved, hidden: hidden)).dsText(OverviewSpec.saved)
                    .foregroundStyle(DS.Color.accentInk).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                    .accessibilityLabel(hidden ? "金额已隐藏" : OverviewDisplay.money(value.saved, hidden: false))
                    .accessibilityIdentifier("overviewSaved")
                Text((value.savedDelta < 0 ? "少攒 " : "多攒 ") + OverviewDisplay.money(abs(value.savedDelta), hidden: hidden))
                    .dsText(DS.Font.tSub).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            }
        }
    }

    private func open(_ slice: OverviewCategorySlice) {
        store.tabRouteRequest = .whereCategory(title: slice.category, categories: slice.categories, isOther: slice.isOther, selection: store.overviewPeriod)
    }
}

private enum OverviewPeriodChoice: String, CaseIterable {
    case current, previous, custom

    init(_ selection: OverviewPeriodSelection) {
        switch selection {
        case .current: self = .current
        case .previous: self = .previous
        case .custom: self = .custom
        }
    }

    var title: String {
        switch self {
        case .current: "本期"
        case .previous: "上期"
        case .custom: "自定义"
        }
    }
}

private enum ReviewDateBox: String {
    case start, end
    var title: String { self == .start ? "开始" : "结束" }
}

private struct ReviewDateAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

struct ReviewPeriodSheetOverlay: View {
    let ledger: Ledger
    let now: Date
    let apply: (OverviewPeriodSelection) -> Void
    let close: () -> Void
    @State private var choice: OverviewPeriodChoice
    @State private var start: Date
    @State private var end: Date
    @State private var activeBox: ReviewDateBox?
    @State private var selectedBox = ReviewDateBox.start
    @State private var displayedMonth: Date
    @State private var motion: EntrySheetMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled

    init(ledger: Ledger, now: Date, selection: OverviewPeriodSelection, rememberedRange: ClosedRange<Date>?,
         settled: Bool, apply: @escaping (OverviewPeriodSelection) -> Void, close: @escaping () -> Void) {
        self.ledger = ledger
        self.now = now
        self.apply = apply
        self.close = close
        _choice = State(initialValue: OverviewPeriodChoice(selection))
        let from: Date
        let through: Date
        if case let .custom(start, end) = selection {
            from = start
            through = end
        } else {
            from = rememberedRange?.lowerBound ?? Finance.cycle(in: ledger, now: now).start
            through = rememberedRange?.upperBound ?? Dates.day(now)
        }
        _start = State(initialValue: from)
        _end = State(initialValue: through)
        _displayedMonth = State(initialValue: DSCalendarPopover.initialMonth(for: from, now: now))
        _motion = State(initialValue: EntrySheetMotion(settled: settled))
    }

    private var reduced: Bool { !animationsEnabled || (reduceMotionOverride ?? systemReduceMotion) }

    var body: some View {
        let _ = OverviewRenderCounts.hit("periodSheetBody")
        OverviewSheet(title: "选周期", motion: motion, close: close) {
            VStack(spacing: DS.Space.s12) {
                DSPeriodOptionGroup(options: options, selection: choice.rawValue, onSelect: selectOption)
                if choice == .custom {
                    HStack(spacing: DS.Space.s8) {
                        dateBox(.start, date: start)
                        Text("–").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                            .frame(width: DS.Size.icon).accessibilityHidden(true)
                        dateBox(.end, date: end)
                    }
                    quickRanges
                    DSButton("看这段") { commit(.custom(start: start, end: end)) }
                        .accessibilityIdentifier("overviewPeriodApply")
                }
            }.padding(.horizontal, DS.Space.s20)
                .padding(.bottom, OverviewSpec.periodBottom)
        }
        .accessibilityHidden(activeBox != nil)
        .overlayPreferenceValue(ReviewDateAnchor.self) { anchor in
            if let activeBox, let anchor { calendar(activeBox, at: anchor) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewPeriodSheet")
    }

    private var options: [DSPeriodOptionGroup.Option] {
        [
            .init(id: OverviewPeriodChoice.current.rawValue, title: OverviewPeriodChoice.current.title,
                  range: OverviewDisplay.range(OverviewAnalytics.periodWindow(selection: .current, in: ledger, now: now).displayedRange)),
            .init(id: OverviewPeriodChoice.previous.rawValue, title: OverviewPeriodChoice.previous.title,
                  range: OverviewDisplay.range(OverviewAnalytics.periodWindow(selection: .previous, in: ledger, now: now).displayedRange)),
            .init(id: OverviewPeriodChoice.custom.rawValue, title: OverviewPeriodChoice.custom.title,
                  range: choice == .custom ? nil : OverviewDisplay.range(start...end))
        ]
    }

    private func selectOption(_ id: String) {
        switch OverviewPeriodChoice(rawValue: id) {
        case .current: commit(.current)
        case .previous: commit(.previous)
        case .custom:
            withAnimation(reduced ? nil : DSMotion.smoothAnimation) { choice = .custom }
        case nil: break
        }
    }

    private func dateBox(_ box: ReviewDateBox, date: Date) -> some View {
        Button {
            displayedMonth = DSCalendarPopover.initialMonth(for: date, now: now)
            selectedBox = box
            activeBox = box
        } label: {
            VStack(alignment: .leading, spacing: OverviewSpec.headingGap) {
                Text(box.title).dsText(OverviewSpec.tiny).foregroundStyle(DS.Color.ink3)
                Text(OverviewDisplay.date(date)).dsText(DS.Font.tLabelStrong).monospacedDigit()
                    .foregroundStyle(DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            }.padding(.horizontal, DS.Space.s12)
                .frame(maxWidth: .infinity, minHeight: OverviewSpec.dateBoxHeight, alignment: .leading)
                .dsSurface(DS.Color.raised, radius: DS.Radius.s)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .strokeBorder(selectedBox == box ? DS.Color.accent : DS.Color.separator,
                                      lineWidth: selectedBox == box ? DS.Stroke.focus : DS.Stroke.hairline)
                        .allowsHitTesting(false)
                }
        }.dsPressStyle().accessibilityIdentifier("overviewDate_" + box.rawValue)
            .anchorPreference(key: ReviewDateAnchor.self, value: .bounds) { activeBox == box ? $0 : nil }
    }

    private var quickRanges: some View {
        HStack(spacing: DS.Space.s8) {
            quickRange("近 3 期", .lastThreeCycles, id: "lastThreeCycles")
            quickRange("今年", .thisYear, id: "thisYear")
            quickRange("去年同期", .samePeriodLastYear, id: "samePeriodLastYear")
            Spacer(minLength: .zero)
        }
    }

    private func quickRange(_ title: String, _ range: OverviewQuickRange, id: String) -> some View {
        Button {
            guard case let .custom(first, last) = range.selection(in: ledger, now: now) else { return }
            start = first
            end = last
            activeBox = nil
        } label: {
            Text(title).dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink2)
                .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .padding(.horizontal, DS.Space.s12)
                .frame(minHeight: DS.Size.chipH)
                .overlay(DS.Shape.pill.strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
                .frame(minHeight: DS.Size.tapMin)
                .contentShape(Rectangle())
        }.dsPressStyle().accessibilityIdentifier("overviewQuick_" + id)
    }

    private func calendar(_ box: ReviewDateBox, at anchor: Anchor<CGRect>) -> some View {
        GeometryReader { geometry in
            let rect = geometry[anchor]
            let width = min(EntrySpec.calendarWidth, geometry.size.width)
            let offset = min(max(0, rect.midX - width * EntrySpec.midpoint), geometry.size.width - width)
            let height = max(0, rect.minY - EntrySpec.calendarGap)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { activeBox = nil }.accessibilityHidden(true)
                ViewThatFits(in: .vertical) {
                    calendarContent(box)
                    ScrollView { calendarContent(box) }.scrollIndicators(.hidden)
                }.frame(width: width, height: height, alignment: .bottom)
                    .offset(x: offset)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { activeBox = nil }
                    .accessibilityIdentifier("overviewCalendar")
            }
        }
    }

    private func calendarContent(_ box: ReviewDateBox) -> some View {
        DSCalendarPopover(date: box == .start ? start : end, now: now, displayedMonth: $displayedMonth, canRepeat: false) { date in
            if box == .start { start = date; end = max(start, end) }
            else { end = date; start = min(start, end) }
            activeBox = nil
        }
    }

    private func commit(_ selection: OverviewPeriodSelection) {
        motion.close(reduced: reduced, sealed: true) {
            apply(selection)
            close()
        }
    }
}

/// Canvas Extra.dc.html 全景 · 兜底类最大: count and share on the left, 去整理 on a raised pill.
private struct ReviewUnsortedCard: View {
    let count: Int
    let share: Double
    let organize: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: .zero) {
                Text("\(count) 笔还没分类").dsText(DS.Font.tBody).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(DS.Color.warnStrong)
                Text("占本期 " + share.formatted(.percent.precision(.fractionLength(0)))).dsText(DS.Font.tSub).monospacedDigit()
                    .foregroundStyle(DS.Color.warnInk)
            }.dsFillWidth()
            Button(action: organize) {
                Text("去整理").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.warnStrong)
                    .padding(.horizontal, DS.Space.s16).frame(height: OverviewSpec.organizeHeight)
                    .dsPill(DS.Color.raised)
                    .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
            }.dsPressStyle().fixedSize().accessibilityIdentifier("overviewOrganize")
        }
        .padding(.horizontal, DS.Space.s16).padding(.vertical, OverviewSpec.alertVertical)
        .dsSurface(DS.Color.warnSoft, radius: DS.Radius.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overviewUnsorted")
    }
}
