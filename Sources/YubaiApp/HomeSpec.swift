import OSLog
import SwiftUI

enum HomeSpec {
    // design-v2 canvas Main.dc.html 长按菜单, Spec-Gestures, Spec-Motion
    static let menuCardHeight: CGFloat = 64 // Main.dc.html 长按菜单 lifted row
    static let menuGap: CGFloat = 10 // Main.dc.html 长按菜单 row-to-menu gap
    static let menuLift: CGFloat = 1.02 // Spec-Gestures 长按 行放大到 1.02
    static let menuScale: CGFloat = 0.94 // Spec-Motion 长按菜单 scale 0.94 → 1
    static let longPress = 0.45 // Spec-Gestures 按住 0.45 秒
    static let swipeIcon: CGFloat = 20 // Main.dc.html 左滑删除 icon

    static let heroLabelGap: CGFloat = 2 // canvas Home.dc.html: 还能花 label
    static let heroDailyBottom: CGFloat = 5 // canvas Home.dc.html: daily allowance
    static let chevron: CGFloat = 14 // canvas Home.dc.html: hero chevron
    static let navIcon: CGFloat = 22 // canvas Home.dc.html: settings and tab icons
    static let barRadius: CGFloat = 2 // canvas Home.dc.html: daily bar corners
    static let barFloor: CGFloat = 3 // canvas Home.dc.html: absent and zero days
    static let barGuide: CGFloat = 13 // canvas Home.dc.html: even pace line
    static let fixtureBarMaximum: Int64 = 130_000 // canvas Home.dc.html: daily scale
    static let fixtureBarWarning: Int64 = 90_000 // canvas Home.dc.html: daily warn
    static let statusHeight: CGFloat = 40 // canvas Home.dc.html: status pill
    static let statusButton: CGFloat = 30 // canvas Home.dc.html: status action
    static let gap6: CGFloat = 6 // canvas Home.dc.html: inline tag and tab spacing
    static let askInset: CGFloat = 14 // canvas Home.dc.html: ask bar leading
    static let tile32: CGFloat = 32 // canvas Home.dc.html: search handoff
    static let statusBottom: CGFloat = 112 // canvas Home.dc.html: running capsule
    static let statusDots: CGFloat = 5 // canvas Home.dc.html: running dots diameter
    static let statusDotOpacities = [1.0, 0.6, 0.3] // canvas Home.dc.html: running dots
    static let statusDotGap: CGFloat = 3 // canvas Home.dc.html: running dots gap
    static let pillBadgeHeight: CGFloat = 22 // canvas Home.dc.html: DeepSeek badge
    static let oftenWidth: CGFloat = 240 // canvas Home.dc.html: 常用 menu width
    static let oftenBottom: CGFloat = 106 // canvas Home.dc.html: 常用 menu bottom edge above the screen bottom
    static let oftenRow: CGFloat = 48 // canvas Home.dc.html: 常用 menu rows
    static let oftenBand: CGFloat = 6 // canvas Home.dc.html: band above 编辑常用
    static let oftenRows = 4 // canvas Home.dc.html: up to four 常用 rows
    static let searchBorder: CGFloat = 1.5 // canvas Home.dc.html: focused search field
    static let tabWidth: CGFloat = 64 // canvas Review.dc.html: centered side tabs
    static let tabIconGap: CGFloat = 2 // canvas Review.dc.html: tab icon and label gap
    static let entryWidth: CGFloat = 124 // canvas Home.dc.html: central CTA
    static let tabHeight: CGFloat = 62 // canvas Home.dc.html: bottom bar
    static let segmentedWidth: CGFloat = 200 // canvas Review.dc.html: overview segmented control
    static let numberMinimumScale: CGFloat = 0.65 // canvas Home.dc.html: worst-case numbers stay visible

    static let formulaTop: CGFloat = 14 // canvas Budget.dc.html: formula card
    static let formulaSign: CGFloat = 14 // canvas Budget.dc.html: formula signs
    static let formulaAmount: CGFloat = 104 // canvas Budget.dc.html: formula number column
    static let budgetTileGap: CGFloat = 10 // canvas Budget.dc.html: amber cards
    static let calmTop: CGFloat = 18 // canvas Budget.dc.html: calm rows
    static let budgetRow: CGFloat = 62 // canvas Budget.dc.html: calm and draggable rows
    static let amountPill: CGFloat = 40 // canvas Budget.dc.html: budget edit pill height
    static let amountPillWidth: CGFloat = 112 // canvas Budget.dc.html: budget edit pill width
    static let sheetGrabberWidth: CGFloat = 36 // canvas Budget.dc.html: budget amount sheet grabber, Stage A shape
    static let dismissalDistance: CGFloat = 110 // canvas Bill.dc.html: floating card drag dismissal

    static let billCenterInset: CGFloat = 24 // canvas Bill.dc.html: name and effect inset
    static let billCardTop: CGFloat = 6 // canvas Bill.dc.html: floating card upper inset
    static let recoveryTop: CGFloat = 22 // canvas Bill.dc.html: recovery card gap
    static let effectHeight: CGFloat = 34 // canvas Bill.dc.html: effect pill
    static let personHeight: CGFloat = 56 // canvas Bill.dc.html: AA receipt row
    static let menuTop: CGFloat = 48 // canvas Bill.dc.html: menu offset
    static let routeIcon: CGFloat = 15 // canvas Bill.dc.html: route pill icon
    static let galleryWidth: CGFloat = 440 // canvas Home.dc.html: standalone DS capture width
    static let galleryContentWidth: CGFloat = 350 // canvas Home.dc.html: isolated example content

    // canvas Home.dc.html: status action and short tags
    static let smallStrong = DS.TextStyle(size: 13, lineHeight: 18, weight: .semibold, tracking: 0, family: .text, relativeTo: .footnote, monospacedDigit: false)
    // canvas Home.dc.html: overspend prefix
    static let tinyStrong = DS.TextStyle(size: 11, lineHeight: 15, weight: .semibold, tracking: 0, family: .text, relativeTo: .caption2, monospacedDigit: false)
    // canvas Home.dc.html: budget amount
    static let headerNumber = DS.TextStyle(size: 15, lineHeight: 20, weight: .medium, tracking: 0, family: .num, relativeTo: .body, monospacedDigit: true)
    // canvas Home.dc.html: DeepSeek badge
    static let pillBadge = DS.TextStyle(size: 11, lineHeight: 18, weight: .regular, tracking: 0, family: .text, relativeTo: .caption2, monospacedDigit: false)
    // canvas Home.dc.html: 常用 menu amounts
    static let oftenAmount = DS.TextStyle(size: 16, lineHeight: 22, weight: .regular, tracking: 0, family: .num, relativeTo: .body, monospacedDigit: true)
    // canvas Home.dc.html: search handoff text
    static let medium = DS.TextStyle(size: 15, lineHeight: 20, weight: .medium, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: false)
    // canvas Bill.dc.html: name
    static let billName = DS.TextStyle(size: 16, lineHeight: 22, weight: .regular, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: false)
    // canvas Bill.dc.html: route pills and receipt action
    static let routeName = DS.TextStyle(size: 14, lineHeight: 20, weight: .semibold, tracking: 0, family: .text, relativeTo: .subheadline, monospacedDigit: false)
    // canvas Bill.dc.html: outstanding amount
    static let receiptAmount = DS.TextStyle(size: 22, lineHeight: 26, weight: .semibold, tracking: 0, family: .num, relativeTo: .title2, monospacedDigit: true)
    // canvas Bill.dc.html: 完成
    static let doneText = DS.TextStyle(size: 17, lineHeight: 22, weight: .semibold, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: false)
}

enum HomeRenderCounts {
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.arguments.contains("-YubaiLogHomeRenderCounts")
    private static let logger = Logger(subsystem: "app.yubai.personal", category: "HomeRenderCounts")
    @MainActor private static var counts: [String: Int] = [:]
    #endif

    @MainActor static func increment(_ body: String) {
        #if DEBUG
        guard enabled else { return }
        counts[body, default: 0] += 1
        logger.log("\(body, privacy: .public)=\(counts[body, default: 0], privacy: .public)")
        #endif
    }
}
