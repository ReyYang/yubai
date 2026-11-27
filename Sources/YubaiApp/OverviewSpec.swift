import OSLog
import SwiftUI

enum OverviewSpec {
    static let periodTop: CGFloat = 10 // canvas Review.dc.html: period pill below segmented control
    static let inlineGap: CGFloat = 6 // canvas Review.dc.html: period pill and Assets.dc.html cash labels
    static let pillTrailing: CGFloat = 10 // canvas Review.dc.html: period pill trailing inset
    static let totalsTop: CGFloat = 18 // canvas Review.dc.html: totals above anomaly card
    static let headingGap: CGFloat = 2 // canvas Review.dc.html: title to number
    static let sectionTop: CGFloat = 22 // canvas Review.dc.html: donut section and ReviewDrill.dc.html small categories
    static let alertVertical: CGFloat = 14 // canvas Review.dc.html: anomaly card vertical inset
    static let alertSubtitleGap: CGFloat = 3 // canvas Review.dc.html: anomaly subtitle gap
    static let legendGap: CGFloat = 10 // canvas Review.dc.html: legend and ReviewDrill.dc.html bill columns
    static let legendAmountWidth: CGFloat = 76 // canvas Review.dc.html: legend and drill amount spine
    // design-v2 canvas Main.dc.html 全景图例: grid 10 / 1fr / 56 / 92, column gap 12, row 48, hairline from the name
    static let legendGridGap: CGFloat = 12
    static let organizeHeight: CGFloat = 36 // Extra.dc.html 全景 · 兜底类最大: 去整理 pill
    static let legendDeltaColumn: CGFloat = 56
    static let legendAmountColumn: CGFloat = 92
    static let legendRow: CGFloat = 48
    static let legendNameGap: CGFloat = 8
    static let legendGridAmount = DS.TextStyle(size: 18, lineHeight: 22, weight: .semibold, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: true)
    static let donutGap: CGFloat = 1.5 // canvas Review.dc.html: arc gap measured along the center line
    static let donutInset = DS.Size.donutStroke / 2 // canvas Review.dc.html: keep stroke inside DS ring diameter
    static let donutCenterline = DS.Size.donut - DS.Size.donutStroke // canvas Review.dc.html: circumference for arc gaps
    static let sheetHeader: CGFloat = 48 // canvas Review-Period.dc.html: sheet heading
    static let optionHeight: CGFloat = 48 // canvas Review-Period.dc.html: option row
    static let dateBoxHeight: CGFloat = 52 // canvas Review-Period.dc.html: date boxes
    static let periodBottom: CGFloat = 34 // canvas Review-Period.dc.html: primary button bottom clearance
    static let drillTop: CGFloat = 10 // canvas ReviewDrill.dc.html: detail hero inset
    static let drillBarHeight: CGFloat = 12 // canvas ReviewDrill.dc.html: subcategory split
    static let barGap: CGFloat = 2 // canvas ReviewDrill.dc.html and Assets.dc.html: stacked segment separation
    static let drillRowHeight: CGFloat = 48 // canvas ReviewDrill.dc.html: subcategory rows and budget link
    static let drillBillsTop: CGFloat = 18 // canvas ReviewDrill.dc.html: bills section
    static let budgetInset: CGFloat = 14 // canvas ReviewDrill.dc.html: budget link horizontal inset
    static let assetsBarHeight: CGFloat = 14 // canvas Assets.dc.html: liquid cash split
    static let assetsBarTop: CGFloat = 14 // canvas Assets.dc.html: gap above liquid cash split
    static let accountRowHeight: CGFloat = 56 // canvas Assets.dc.html: account rows
    static let investRowHeight: CGFloat = 52 // canvas Assets.dc.html: investment rows
    static let investButtonInset: CGFloat = 14 // canvas Assets.dc.html: secondary capsule padding
    static let accountActionHeight: CGFloat = 48 // canvas Account.dc.html: reconcile and transfer controls
    static let accountPrimaryShare: CGFloat = 2.0 / 3.0 // canvas Account.dc.html: 2:1 action grid
    static let accountNavWing: CGFloat = 72 // canvas Account.dc.html: equal navigation side columns
    static let chartHeight: CGFloat = 84 // canvas Account.dc.html: plot height
    static let chartStroke: CGFloat = 2 // canvas Account.dc.html: balance line and endpoint ring
    static let chartAreaOpacity = 0.12 // canvas Account.dc.html: area tint
    static let chartEndDot: CGFloat = 8 // canvas Account.dc.html: endpoint diameter
    static let chartHighlightDot: CGFloat = 6 // canvas Account.dc.html: highlight diameter
    static let chartVerticalInset: CGFloat = 6 // canvas Account.dc.html: plot edge clearance
    static let chartHorizontalInset: CGFloat = 2 // canvas Account.dc.html: x-axis endpoint inset
    static let valuationBoxHeight: CGFloat = 64 // canvas Account-Reconcile.dc.html: pair of balance boxes
    static let valuationBoxVertical: CGFloat = 10 // canvas Account-Reconcile.dc.html: balance box inset
    static let valuationApplyTop: CGFloat = 14 // canvas Account-Reconcile.dc.html: gap before apply
    static let valuationTrayHeight: CGFloat = 280 // canvas Account-Reconcile.dc.html: keypad tray including bottom safe area
    static let disabledOpacity = 0.4 // canvas Account-Reconcile.dc.html: zero difference apply state

    // canvas Review.dc.html: 攒下 amount
    static let saved = DS.TextStyle(size: 22, lineHeight: 28, weight: .semibold, tracking: 0, family: .text, relativeTo: .title2, monospacedDigit: true)
    // canvas Review.dc.html: legend amount
    static let legendAmount = DS.TextStyle(size: 16, lineHeight: 22, weight: .semibold, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: true)
    // canvas Account.dc.html: axis labels and Review-Period.dc.html: date field caption
    static let tiny = DS.TextStyle(size: 11, lineHeight: 14, weight: .regular, tracking: 0, family: .text, relativeTo: .caption2, monospacedDigit: true)
    // canvas Account-Reconcile.dc.html: difference
    static let difference = DS.TextStyle(size: 28, lineHeight: 34, weight: .bold, tracking: -0.5, family: .text, relativeTo: .title, monospacedDigit: true)
}

@MainActor enum OverviewRenderCounts {
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.arguments.contains("-YubaiLogOverviewRenderCounts")
    private static let logger = Logger(subsystem: "app.yubai.personal", category: "OverviewRenderCounts")
    private static var counts: [String: Int] = [:]
    #endif

    static func hit(_ part: String) {
        #if DEBUG
        guard enabled else { return }
        counts[part, default: 0] += 1
        logger.notice("\(part, privacy: .public)=\(counts[part, default: 0], privacy: .public)")
        #endif
    }
}
