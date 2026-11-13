import SwiftUI
import Observation
import UniformTypeIdentifiers
import YubaiCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import CoreImage
#endif

enum YubaiColor {
    static let white = Color.white
    static let canvas = adaptive(0xf5f1e5, 0x1f1b14)
    static let card = adaptive(0xede6d3, 0x2a251c)
    static let raised = adaptive(0xfefbea, 0x353026)
    static let keypadTray = adaptive(0xe4dac4, 0x2a251c)
    static let key = adaptive(0xfefbea, 0x4a4436)
    static let keyFn = adaptive(0xd6caaf, 0x353026)
    static let keyPressed = adaptive(0xf1e9d5, 0x353026)
    static let keyFnPressed = adaptive(0xccc0a4, 0x4a4436)
    // Solid bottom edge: radius 0, x 0, y 1; removed at touch-down.
    static let shadowKey = adaptive(0x4a4030, 0x000000, lightAlpha: 0x38 / 255.0, darkAlpha: 0x73 / 255.0)

    static let paperSheet = adaptive(0xfefbea, 0x2a251c)
    // A slightly lighter sheet, blended entirely from the existing paper/light palette.
    static func receiptPaper(for scheme: ColorScheme) -> Color {
        if scheme == .dark { return raised }
        if #available(macOS 15, *) { return paperSheet.mix(with: windowLight, by: 0.65) }
        return raised
    }
    static let paperInset = adaptive(0xede6d3, 0x353026)
    static let glassBar = adaptive(0xfefbea, 0x353026, lightAlpha: 204.0 / 255, darkAlpha: 217.0 / 255)
    static let windowLight = adaptive(0xfffdf3, 0xe9cf9f)
    static let bambooShadow = adaptive(0x2f4a2e, 0x86a884)
    static let selected = adaptive(0xffffff, 0x4a4436)
    static let label = adaptive(0x382f1f, 0xe6decb)
    static let labelMuted = adaptive(0x5a5040, 0xc2b8a3)
    static let labelSecondary = adaptive(0x6a604f, 0xa89d88)
    static let separator = adaptive(0xe0d8c9, 0x3a3428)
    static let grabber = adaptive(0xd8cfbe, 0x4a4335)
    static let borderDashed = adaptive(0xcfc3ae, 0x5a5040)
    static let brand = adaptive(0x557f53, 0x86a884)
    static let onBrand = adaptive(0xffffff, 0x1f1b14)
    static let brandInk = adaptive(0x476846, 0xcfe0c2)
    static let brandTint = adaptive(0xd6e2cc, 0x34422f)
    static let brandTintStrong = adaptive(0x2f4a2e, 0xdcebd0)
    static let brandMark = adaptive(0x6e926e, 0x86a884)
    static let brandGlyph = adaptive(0x3f6a3e, 0xa9c9a6)
    static let amberTint = adaptive(0xefe1c4, 0x4a3c24)
    static let amberInk = adaptive(0x7a5320, 0xe9cf9f)
    static let amberStrong = adaptive(0x5e3f17, 0xf3ddb3)
    static let amberDot = adaptive(0xb88443, 0xd2a867)
    static let amberMark = adaptive(0xd9b77e, 0xc9a061)
    static let seriesSoft = adaptive(0xa9be9c, 0x5e7a5b)
    static let series2 = adaptive(0x8fae88, 0x4e6a4c)
    static let series3 = adaptive(0xc3d3b8, 0x3e523c)
    static let neutralStrong = adaptive(0xc9bca3, 0x6b604d)
    static let neutralSoft = adaptive(0xddd2be, 0x4a4335)
    static let outflow = adaptive(0xb09e80, 0x8c7b5f)
    static let chartRule = adaptive(0xb9ac93, 0x6b604d)
    static let chartGuide = adaptive(0x8c806b, 0x8c806b)
    static let toggleOn = adaptive(0x557f53, 0x86a884)
    static let iconTile = adaptive(0xede6d3, 0xede6d3)
    static let iconInk = adaptive(0x3e3224, 0x3e3224)

    fileprivate static func adaptive(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }))
        #elseif os(iOS)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }))
        #endif
    }
}

enum YubaiFont {
    enum Family: Equatable { case num, serif, sans, code }
    struct Style {
        let size: CGFloat
        let lineHeight: CGFloat
        let weight: Font.Weight
        let family: Family
        var tracking: CGFloat = 0
        var relativeTo: Font.TextStyle = .body
        var design: Font.Design { switch family { case .num: .rounded; case .serif: .serif; case .sans: .default; case .code: .monospaced } }
    }
    static let entryAmount = Style(size: 48, lineHeight: 56, weight: .semibold, family: .num, tracking: -1.5, relativeTo: .largeTitle)
    static let entrySheetTitle = Style(size: 17, lineHeight: 24, weight: .semibold, family: .sans, relativeTo: .headline)
    static let destructiveAction = Style(size: 16, lineHeight: 22, weight: .medium, family: .sans, relativeTo: .headline)
    static let amountHero = Style(size: 48, lineHeight: 54, weight: .semibold, family: .num, tracking: -2, relativeTo: .largeTitle)
    static let amountDisplay = Style(size: 44, lineHeight: 50, weight: .semibold, family: .num, tracking: -1.5, relativeTo: .largeTitle)
    static let amountInput = Style(size: 38, lineHeight: 46, weight: .semibold, family: .num, tracking: -1, relativeTo: .title)
    static let amountLarge = Style(size: 30, lineHeight: 36, weight: .semibold, family: .num, tracking: -0.5, relativeTo: .title)
    static let amount = Style(size: 15, lineHeight: 20, weight: .semibold, family: .num, tracking: 0, relativeTo: .body)
    static let amountSmall = Style(size: 13, lineHeight: 18, weight: .medium, family: .num, tracking: 0, relativeTo: .footnote)
    static let amountCaption = Style(size: 12, lineHeight: 18, weight: .medium, family: .num, relativeTo: .caption)
    static let amountDay = Style(size: 18, lineHeight: 24, weight: .semibold, family: .num, tracking: -0.3, relativeTo: .headline)
    // Numeric sizes specified by the approved V3 summary tiles and donut.
    static let amountSummary = Style(size: 17, lineHeight: 24, weight: .semibold, family: .num, relativeTo: .headline)
    static let amountCard = Style(size: 20, lineHeight: 28, weight: .semibold, family: .num, relativeTo: .title3)
    static let amountDonut = Style(size: 22, lineHeight: 28, weight: .semibold, family: .num, relativeTo: .title2)
    static let amountAccount = Style(size: 24, lineHeight: 30, weight: .semibold, family: .num, relativeTo: .title2)
    static let chartValue = Style(size: 11, lineHeight: 14, weight: .medium, family: .num, tracking: 0, relativeTo: .caption2)
    static let lead = Style(size: 22, lineHeight: 32, weight: .semibold, family: .serif, tracking: 0, relativeTo: .title2)
    static let quote = Style(size: 20, lineHeight: 30, weight: .semibold, family: .serif, tracking: 0, relativeTo: .title3)
    static let heroLabel = Style(size: 17, lineHeight: 24, weight: .semibold, family: .serif, tracking: 0, relativeTo: .headline)
    static let cardTitle = Style(size: 16, lineHeight: 22, weight: .semibold, family: .serif, tracking: 0, relativeTo: .headline)
    static let month = Style(size: 17, lineHeight: 24, weight: .semibold, family: .serif, tracking: 0, relativeTo: .headline)
    static let navTitle = Style(size: 16, lineHeight: 22, weight: .bold, family: .sans, tracking: 0, relativeTo: .headline)
    static let body = Style(size: 15, lineHeight: 22, weight: .regular, family: .sans, tracking: 0, relativeTo: .body)
    static let rowTitle = Style(size: 15, lineHeight: 20, weight: .medium, family: .sans, tracking: 0, relativeTo: .body)
    static let fieldValue = Style(size: 16, lineHeight: 24, weight: .regular, family: .sans, relativeTo: .body)
    static let row = Style(size: 14, lineHeight: 20, weight: .regular, family: .sans, tracking: 0, relativeTo: .body)
    static let callout = Style(size: 13, lineHeight: 20, weight: .regular, family: .sans, tracking: 0, relativeTo: .callout)
    static let caption = Style(size: 12, lineHeight: 18, weight: .regular, family: .sans, tracking: 0, relativeTo: .caption)
    static let code = Style(size: 12, lineHeight: 18, weight: .regular, family: .code, relativeTo: .caption)
    static let receiptTime = Style(size: 11, lineHeight: 16, weight: .regular, family: .code, relativeTo: .caption2)
    static let receiptAmount = Style(size: 14, lineHeight: 20, weight: .medium, family: .code, relativeTo: .body)
    static let receiptTotal = Style(size: 22, lineHeight: 28, weight: .semibold, family: .code, relativeTo: .title2)
    static let meta = Style(size: 11, lineHeight: 16, weight: .regular, family: .sans, tracking: 0, relativeTo: .caption2)
    static let chartLabel = Style(size: 10, lineHeight: 12, weight: .regular, family: .sans, tracking: 0, relativeTo: .caption2)
    static let tabLabel = Style(size: 10, lineHeight: 12, weight: .medium, family: .sans, tracking: 0, relativeTo: .caption2)
    static let tabIcon = Style(size: 20, lineHeight: 24, weight: .regular, family: .sans, relativeTo: .title3)
    static let addIcon = Style(size: 24, lineHeight: 28, weight: .semibold, family: .sans, relativeTo: .title2)
    static let button = Style(size: 15, lineHeight: 20, weight: .medium, family: .sans, tracking: 0, relativeTo: .headline)
    static let keypadAction = Style(size: 17, lineHeight: 22, weight: .semibold, family: .sans, relativeTo: .headline)
}

private struct YubaiTextStyle: ViewModifier {
    let style: YubaiFont.Style
    var weight: Font.Weight?
    @ScaledMetric private var size: CGFloat
    init(_ style: YubaiFont.Style, weight: Font.Weight?) {
        self.style = style; self.weight = weight
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }
    func body(content: Content) -> some View {
        let scale = size / style.size
        let font = Font.system(size: size, weight: weight ?? style.weight, design: style.design)
        content.font(style.family == .num ? font.monospacedDigit() : font)
            .lineSpacing((style.lineHeight - style.size) * scale)
            .tracking(style.tracking * scale)
    }
}

extension View {
    @ViewBuilder func uiTestAccessibilityValue(_ value: @autoclosure () -> String) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { self.accessibilityValue(value()) } else { self }
        #else
        self
        #endif
    }
    @ViewBuilder func uiTestAccessibilityValue(_ value: @autoclosure () -> String, appendingTo productionValue: String) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { self.accessibilityValue(productionValue + "; " + value()) }
        else { self.accessibilityValue(productionValue) }
        #else
        self.accessibilityValue(productionValue)
        #endif
    }
    func yubaiFont(_ style: YubaiFont.Style, weight: Font.Weight? = nil) -> some View { modifier(YubaiTextStyle(style, weight: weight)) }

    /// Apply inside a Button/Menu label, after its visual background, so transparent space is tappable.
    func yubaiHitTarget(alignment: Alignment = .center) -> some View {
        frame(minWidth: YubaiSize.tapMin, minHeight: YubaiSize.tapMin, alignment: alignment)
            .contentShape(Rectangle()).contentViewportTarget()
    }

    func contentViewportTarget() -> some View { modifier(ContentViewportTarget()) }

    /// Keeps the glyph on the page edge; the transparent target extends into the page margin.
    func yubaiPageArrowTarget(edge: HorizontalEdge) -> some View {
        frame(width: YubaiSize.pageArrowGlyph, height: YubaiSize.iconButton, alignment: edge == .leading ? .leading : .trailing)
            .yubaiHitTarget()
            .padding(edge == .leading ? .leading : .trailing, -YubaiSize.pageArrowOutset)
    }
}

enum YubaiSpace {
    static let calendarGap: CGFloat = 1
    static let none: CGFloat = 0
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6 // 已停用，仅兼容
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10 // 已停用，仅兼容
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space18: CGFloat = 18 // 已停用，仅兼容
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space22: CGFloat = 22
    static let space28: CGFloat = 28

    static let insetPage = space20
    static let insetCard = space16
    static let gapSection = space24
    static let gapGroup = space12
    static let gapHeading = space8
    static let gapAction = space12
    /// Clear space above a sheet's manual header so it sits below the system grabber.
    static let sheetHeaderTop: CGFloat = 20
    static let emptyTop: CGFloat = 100
    static let messageIndent = space20 * 2
    // H1 已完成；滑动操作保留原有内缩与标签几何，不参与 4/8 网格归一。
    static let swipeActionInset: CGFloat = 6
    static let swipeLabelTrailing: CGFloat = 18
}

enum YubaiRadius {
    static let bar: CGFloat = 4
    static let control: CGFloat = 14
    static let tile: CGFloat = 0.224
    static let row: CGFloat = 18
    static let card: CGFloat = 22
    static let tabbar: CGFloat = 24
    static let full: CGFloat = 999
    static let messageTail: CGFloat = 6
}

enum YubaiSize {
    static let toastExpandedMaximumHeight: CGFloat = 320
    static let navigationCapsuleWidth: CGFloat = 244
    static let navigationTabHeight: CGFloat = 48
    static let homeEntryPillHeight: CGFloat = 52
    static let savingCardMinimum: CGFloat = 88
    static let savingIcon: CGFloat = 40
    static let receiptInset: CGFloat = 22
    static let receiptSlotHeight: CGFloat = 10
    static let receiptTearHeight: CGFloat = 7
    static let receiptRowHeight: CGFloat = 32
    static let receiptUndoWidth: CGFloat = 76
    static let receiptLineDash: CGFloat = 5
    static let firstOpenMinimum: CGFloat = 480
    static let firstOpenBrand: CGFloat = 78
    static let firstOpenRule: CGFloat = 170
    static let firstOpenBottom: CGFloat = 128
    static let sidebarMinimumWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 210
    static let sidebarMaximumWidth: CGFloat = 250
    static let calendarCellLarge: CGFloat = 144
    static let rowEstimate: CGFloat = 76
    static let quickMenuWidth: CGFloat = 262
    static let entryInlineHistory: CGFloat = 120
    static let entryInlineHistoryLarge: CGFloat = 156
    static let entrySheet: CGFloat = 724
    static let entrySheetBig: CGFloat = 792
    static let entrySheetCompact: CGFloat = 648
    static let entrySheetTransfer: CGFloat = 704
    static let sheetCorner: CGFloat = 28
    static let keypadHeight: CGFloat = 236
    // Shared page, calendar and desktop geometry.
    static let separator: CGFloat = 1
    static let unknownDot: CGFloat = 6
    static let smallGlyph: CGFloat = 18
    static let smallBadge: CGFloat = 26
    static let trayChip: CGFloat = 34
    static let sourceRow: CGFloat = 60
    static let calendarCell: CGFloat = 62
    static let fieldMinimum: CGFloat = 64
    static let chipMinimum: CGFloat = 100
    static let inlineListMaximum: CGFloat = 240
    static let dateRowMaximum: CGFloat = 300
    static let compactWindowMinimum: CGFloat = 340
    static let calendarMinimumHeight: CGFloat = 350
    static let editorMinimumHeight: CGFloat = 400
    static let editorMinimumWidth: CGFloat = 460
    static let editorIdealHeight: CGFloat = 520
    static let sheetMinimumWidth: CGFloat = 540
    static let sheetMinimumHeight: CGFloat = 600
    static let sheetIdealWidth: CGFloat = 620
    static let contentNarrow: CGFloat = 680
    static let sheetIdealHeight: CGFloat = 720
    static let calendarWide: CGFloat = 750
    static let contentMedium: CGFloat = 760
    static let desktopMinimumWidth: CGFloat = 920
    static let contentMaximum: CGFloat = 1080
    static let desktopIdealWidth: CGFloat = 1240
    static let desktopIdealHeight: CGFloat = 850
    static let sheet300: CGFloat = 300
    static let sheet440: CGFloat = 440
    static let sheet480: CGFloat = 480
    static let sheet520: CGFloat = 520
    static let sheet560: CGFloat = 560
    static let sheet640: CGFloat = 640
    static let sheet660: CGFloat = 660
    static let sheet700: CGFloat = 700
    static let sheet792: CGFloat = 792

    static let tapMin: CGFloat = 44
    static let headerHeight: CGFloat = 48
    static let headerIcon: CGFloat = 20
    static let headerIconMax: CGFloat = 32
    static let iconButton: CGFloat = 40
    static let buttonHeight: CGFloat = 52
    static let chipHeight: CGFloat = 32
    static let fieldLabel: CGFloat = 76
    static let rowSingle: CGFloat = 52
    static let rowDouble: CGFloat = 56
    static let rowIcon: CGFloat = 36
    static let segmentedHeight: CGFloat = 40
    static let segmentedPill: CGFloat = 32
    static let segmentedHitOutset = (tapMin - segmentedHeight) / 2
    static let swipeActionWidth: CGFloat = 78
    static let swipeRevealDistance = swipeActionWidth + YubaiSpace.swipeActionInset + YubaiSpace.gapAction
    static let tabBarHeight: CGFloat = 66
    static let tabSelectionHeight = tabBarHeight - YubaiSpace.space8 * 2
    static let tabSelectionRadius = tabSelectionHeight / 2
    static let tabAdd: CGFloat = 54
    static let tabIcon: CGFloat = 20
    static let pageArrowGlyph: CGFloat = 12
    static let pageArrowOutset = (tapMin - pageArrowGlyph) / 2
    static let cardActionClearance = tapMin + YubaiSpace.space4
    static let rowTextInset = rowIcon + YubaiSpace.gapGroup
    static let pillHeight: CGFloat = 28
    static let tagHeight: CGFloat = 22
    static let tabbarHeight: CGFloat = 62
    #if os(iOS)
    static let floatingTabbarHeight: CGFloat = 60
    static let floatingTabbarBottom: CGFloat = 0
    #endif
    static let barMax: CGFloat = 24
    static let lineWidth: CGFloat = 2
    static let outline: CGFloat = 1.5
    static let marker: CGFloat = 8
    static func rootBottomPadding(for destination: Destination) -> CGFloat {
        #if os(macOS)
        destination == .now ? homeEntryPillHeight + YubaiSpace.gapSection : YubaiSpace.none
        #else
        floatingTabbarHeight + floatingTabbarBottom + YubaiSpace.space12 +
            (destination == .now ? homeEntryPillHeight + YubaiSpace.space12 : YubaiSpace.none)
        #endif
    }
}

enum YubaiShadow {
    struct Token {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    static let card = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 20.0 / 255, darkAlpha: 82.0 / 255), radius: 14, x: 0, y: 10)
    static let cardNear = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 15.0 / 255, darkAlpha: 64.0 / 255), radius: 1, x: 0, y: 1)
    static let control = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 20.0 / 255, darkAlpha: 64.0 / 255), radius: 4, x: 0, y: 2)
    static let float = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 31.0 / 255, darkAlpha: 89.0 / 255), radius: 20, x: 0, y: 6)
    static let ask = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 46.0 / 255, darkAlpha: 89.0 / 255), radius: 20, x: 0, y: 6)
    static let input = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 20.0 / 255, darkAlpha: 64.0 / 255), radius: 16, x: 0, y: 4)
    static let knob = Token(color: YubaiColor.adaptive(0x000000, 0x000000, lightAlpha: 46.0 / 255, darkAlpha: 46.0 / 255), radius: 3, x: 0, y: 1)
}

extension View {
    func yubaiShadow(_ token: YubaiShadow.Token) -> some View { shadow(color: token.color, radius: token.radius, x: token.x, y: token.y) }
}

@MainActor enum YubaiMotion {
    static let durationFirstLight = 1.4
    static let windowSwayPhase = 9.0
    static let durationReceiptPrint = 0.32
    // Amount keypad: immediate color/edge feedback, no scale/opacity; release
    // eases out over durationQuick. Prepared system haptics fire at touch-down:
    // light for digits/delete, medium for operators/clear, rigid 0.5 if rejected.
    static let durationInstant = 0.100
    static let durationQuick = 0.160
    static let durationStandard = 0.240
    static let durationDraw = 0.480
    static let durationProgress = 0.320
    static let durationStagger = 0.040
    static let durationThink = 1.600
    static let durationBrandMax = 0.700
    static let durationWash = 1.200
    static let durationDismiss = 0.200
    static let durationRing = 0.600
    static let toastLifetime = 4.0
    static let saveToastDelay = 0.380
    static let pointDelay = 0.180
    static let ringDelay = 0.420
    static let settle = Animation.smooth(duration: 0.42)
    static let snappy = Animation.snappy(duration: 0.3)
    static let lively = Animation.spring(duration: 0.45, bounce: 0.25)
    static let livelySpring = Spring(duration: 0.45, bounce: 0.25)
    static let snappySpring = Spring(duration: 0.3, bounce: 0.15)
    static let durationTagHopHalf = 0.150
    static let durationSwayHalf = 0.225
    private static var session = MotionSessionState()
    static func hasAppeared(_ key: String) -> Bool { session.contains(key) }
    static func claim(_ key: String) -> Bool { session.claim(key) }

    static func easeOut(duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
    static func easeIn(duration: Double) -> Animation { .timingCurve(0.4, 0, 1, 1, duration: duration) }
    static func easeInOut(duration: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: duration) }
    static let instant = easeInOut(duration: durationInstant)
    static let quick = Animation.easeInOut(duration: durationQuick)
    static let chartGrowth = easeOut(duration: durationDraw)
    static let progressFill = easeOut(duration: durationProgress)
    static let stagger = easeOut(duration: durationStagger)
    static let thinkCycle = easeInOut(duration: durationThink)

    static func number(reduceMotion: Bool) -> Animation { reduceMotion ? quick : snappy }
    static func layout(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : settle }
    static func control(reduceMotion: Bool) -> Animation { reduceMotion ? quick : snappy }
    static func entrance(reduceMotion: Bool) -> Animation { reduceMotion ? quick : easeOut(duration: durationStandard) }
    static func dismiss(reduceMotion: Bool) -> Animation { reduceMotion ? quick : easeIn(duration: durationDismiss) }
    static func wash(reduceMotion: Bool) -> Animation { reduceMotion ? quick : easeOut(duration: durationWash) }
    static func ring(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : easeOut(duration: durationRing) }
    static func chart(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : chartGrowth }
    static func progress(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : progressFill }
    static func think(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : thinkCycle }
    static func toastIn(reduceMotion: Bool) -> Animation { reduceMotion ? quick : snappy }
    static func toastOut(reduceMotion: Bool) -> Animation { reduceMotion ? quick : easeIn(duration: durationQuick) }
    static func rise(_ distance: CGFloat, reduceMotion: Bool) -> AnyTransition { reduceMotion ? .opacity : .offset(y: distance).combined(with: .opacity) }
    static func rowTransition(reduceMotion: Bool) -> AnyTransition { reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)) }
    static func cardTransition(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(insertion: .identity, removal: (reduceMotion ? AnyTransition.opacity : .scale(scale: 0.96).combined(with: .opacity)).animation(dismiss(reduceMotion: reduceMotion)))
    }
    static func toastTransition(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(insertion: rise(YubaiSpace.gapGroup, reduceMotion: reduceMotion).animation(toastIn(reduceMotion: reduceMotion)), removal: .opacity.animation(toastOut(reduceMotion: reduceMotion)))
    }
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Transforming the label also transforms its accessibility/hit frame.
        // Keep the target stationary, including during the release animation.
        TextLinkStyle().makeBody(configuration: configuration)
    }
}

/// Small, unfilled links share a target inside the button, never outside it.
/// Font and colour belong to the label; this changes only the transparent area.
struct TextLinkStyle: ButtonStyle {
    var alignment: Alignment = .center
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fixedSize(horizontal: false, vertical: true)
            .yubaiHitTarget(alignment: alignment)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

/// A toggle is one full row, including the space between its label and switch.
/// The native representation preserves Switch semantics and the 0/1 value.
struct RowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: YubaiSpace.gapGroup) {
                configuration.label.fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: configuration.$isOn).labelsHidden().toggleStyle(.switch)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.buttonStyle(.plain).contentViewportTarget()
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label.frame(minHeight: YubaiSize.rowDouble) }
                    .toggleStyle(.switch).accessibilityElement(children: .combine)
            }
    }
}

struct SmallActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.label)
            .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
            .background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
            .opacity(configuration.isPressed ? 0.75 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

private struct NumberChange: ViewModifier {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let value: Double
    var enabled: Bool
    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion || !enabled ? .opacity : .numericText(value: value))
            .animation(enabled ? YubaiMotion.number(reduceMotion: reduceMotion) : nil, value: value)
    }
}

extension View {
    func numberTransition(value: Double, enabled: Bool = true) -> some View { modifier(NumberChange(value: value, enabled: enabled)) }
}

private struct SheetSurfaceKey: EnvironmentKey { static let defaultValue = false }
private struct RootSurfaceKey: EnvironmentKey { static let defaultValue = false }
private struct FormSurfaceKey: EnvironmentKey { static let defaultValue = false }
private struct CardContentKey: EnvironmentKey { static let defaultValue = false }
private struct ZoomNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
private struct ToastClearanceKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct ContentViewportKey: EnvironmentKey { static let defaultValue: CGRect? = nil }
extension EnvironmentValues {
    /// SwiftUI's system value is read-only; scripted tests opt in at the readers.
    var yubaiReduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil && ProcessInfo.processInfo.environment["YUBAI_UI_TEST_REDUCE_MOTION"] == "1" { return true }
        #endif
        return accessibilityReduceMotion
    }
    var yubaiSheetSurface: Bool { get { self[SheetSurfaceKey.self] } set { self[SheetSurfaceKey.self] = newValue } }
    var yubaiRootSurface: Bool { get { self[RootSurfaceKey.self] } set { self[RootSurfaceKey.self] = newValue } }
    var yubaiFormSurface: Bool { get { self[FormSurfaceKey.self] } set { self[FormSurfaceKey.self] = newValue } }
    var yubaiCardContent: Bool { get { self[CardContentKey.self] } set { self[CardContentKey.self] = newValue } }
    var yubaiZoomNamespace: Namespace.ID? { get { self[ZoomNamespaceKey.self] } set { self[ZoomNamespaceKey.self] = newValue } }
    var yubaiToastClearance: CGFloat { get { self[ToastClearanceKey.self] } set { self[ToastClearanceKey.self] = newValue } }
    var yubaiContentViewport: CGRect? { get { self[ContentViewportKey.self] } set { self[ContentViewportKey.self] = newValue } }
}

/// UIKit can retain a full AX frame for a partially clipped SwiftUI button.
/// Expose its action only after the entire target clears the fixed chrome;
/// scrolling continues to work on the enclosing scroll view.
private struct ContentViewportTarget: ViewModifier {
    @Environment(\.yubaiContentViewport) private var viewport
    @State private var inside = true
    func body(content: Content) -> some View {
        content.onGeometryChange(for: Bool.self) { geometry in
            guard let viewport else { return true }
            return viewport.insetBy(dx: -0.5, dy: -0.5).contains(geometry.frame(in: .global))
        } action: { inside = $0 }
            .allowsHitTesting(inside).accessibilityRespondsToUserInteraction(inside)
    }
}

private struct ScrollContentViewport: ViewModifier {
    @State private var viewport: CGRect?
    func body(content: Content) -> some View {
        content.environment(\.yubaiContentViewport, viewport)
            .onGeometryChange(for: CGRect.self) { geometry in
                let frame = geometry.frame(in: .global), safe = geometry.safeAreaInsets
                return CGRect(x: frame.minX + safe.leading, y: frame.minY + safe.top,
                              width: max(0, frame.width - safe.leading - safe.trailing),
                              height: max(0, frame.height - safe.top - safe.bottom))
            } action: { viewport = $0 }
            .clipped().contentShape(Rectangle())
    }
}

#if os(iOS)
struct HorizontalPan: UIGestureRecognizerRepresentable {
    var allowsSubgestures = false
    var shouldBegin: (CGFloat) -> Bool = { _ in true }
    var changed: (CGFloat) -> Void = { _ in }
    var ended: (CGFloat, CGFloat) -> Void = { _, _ in }
    var cancelled: () -> Void = {}
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(allowsSubgestures: allowsSubgestures, shouldBegin: shouldBegin) }
    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) { context.coordinator.shouldBegin = shouldBegin }
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let distance = pan.translation(in: pan.view).x
        switch pan.state {
        case .began, .changed: changed(distance)
        case .ended: ended(distance, pan.velocity(in: pan.view).x)
        case .cancelled, .failed: cancelled()
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let allowsSubgestures: Bool
        var shouldBegin: (CGFloat) -> Bool
        init(allowsSubgestures: Bool, shouldBegin: @escaping (CGFloat) -> Bool) { self.allowsSubgestures = allowsSubgestures; self.shouldBegin = shouldBegin }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let translation = pan.translation(in: pan.view)
            return abs(translation.x) > abs(translation.y) && abs(translation.x) > 0 && shouldBegin(translation.x)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer else { return false }
            if allowsSubgestures, let view = gestureRecognizer.view, scroll.isDescendant(of: view) { return false }
            // Decide direction before either the vertical list or root pager
            // begins. A vertical pan fails our direction gate immediately.
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard allowsSubgestures, let view = gestureRecognizer.view, let otherView = other.view else { return false }
            return otherView.isDescendant(of: view)
        }
    }
}
#endif

/// A stationary page surface. Data and card contents never receive this light.
struct PaperCanvas: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var showsBamboo = false
    var bambooTrigger = 0
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                YubaiColor.canvas
                if !reduceTransparency {
                    let size = geometry.size
                    // CSS 118°: the gradient line spans the full rectangular page.
                    let angle = 118.0 * Double.pi / 180
                    let dx = CGFloat(sin(angle)), dy = CGFloat(-cos(angle))
                    let length = abs(size.width * dx) + abs(size.height * dy)
                    let halfX = dx * length / max(1, size.width) / 2
                    let halfY = dy * length / max(1, size.height) / 2
                    LinearGradient(stops: [
                        .init(color: .clear, location: scheme == .dark ? 0.18 : 0.20),
                        .init(color: YubaiColor.windowLight.opacity(scheme == .dark ? 18.0 / 255 : 199.0 / 255), location: scheme == .dark ? 0.34 : 0.36),
                        .init(color: .clear, location: scheme == .dark ? 0.52 : 0.54)
                    ], startPoint: UnitPoint(x: 0.5 - halfX, y: 0.5 - halfY), endPoint: UnitPoint(x: 0.5 + halfX, y: 0.5 + halfY))
                    let radius = max(1, size.width * 1.3)
                    RadialGradient(stops: [
                        .init(color: YubaiColor.windowLight.opacity(scheme == .dark ? 20.0 / 255 : 1), location: 0),
                        .init(color: .clear, location: 0.62)
                    ], center: .topLeading, startRadius: 0, endRadius: radius)
                        .frame(width: radius, height: radius)
                        .scaleEffect(x: 1, y: size.height * 0.55 / radius, anchor: .topLeading)
                    if showsBamboo {
                        BambooShadow(trigger: bambooTrigger)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct BambooShadow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    let trigger: Int
    @ViewBuilder private var branch: some View {
        if let image = BambooRasterCache.image(scheme: scheme, scale: displayScale) {
            image.resizable().frame(width: 230 + BambooRasterCache.padding * 2, height: 299 + BambooRasterCache.padding * 2)
                .padding(-BambooRasterCache.padding)
        } else {
            BambooRasterCache.source.blur(radius: 6)
                .padding(BambooRasterCache.padding).drawingGroup()
                .padding(-BambooRasterCache.padding)
        }
    }
    var body: some View {
        Group {
            if reduceMotion { branch }
            else {
                branch.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, angle in
                    content.rotationEffect(.degrees(Double(max(-3, min(3, angle)))), anchor: UnitPoint(x: -0.04, y: 0.96))
                } keyframes: { _ in
                    SpringKeyframe(CGFloat(2.5), duration: YubaiMotion.durationSwayHalf, spring: YubaiMotion.livelySpring)
                    SpringKeyframe(CGFloat.zero, duration: YubaiMotion.durationSwayHalf, spring: YubaiMotion.livelySpring)
                }
            }
        }.rotationEffect(.degrees(-12)).scaleEffect(x: 1, y: -1)
            .opacity(scheme == .dark ? 0.12 : 0.11)
            .offset(x: 74, y: -58).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The padding retains the blur outside the original 230 × 299 alignment rect.
/// Rotation, reflection, opacity and sway remain on that original alignment rect.
@MainActor private enum BambooRasterCache {
    static let padding: CGFloat = 32
    private struct Key: Hashable { let dark: Bool; let scale: CGFloat }
    private static var images: [Key: Image] = [:]
    static var source: some View {
        Image("BambooShadow").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(YubaiColor.bambooShadow).frame(width: 230, height: 299)
    }
    #if os(iOS)
    private static let context = CIContext()
    #endif
    static func image(scheme: ColorScheme, scale: CGFloat) -> Image? {
        let key = Key(dark: scheme == .dark, scale: scale)
        if let cached = images[key] { return cached }
        #if os(iOS)
        guard scale > 0, let asset = UIImage(named: "BambooShadow"), asset.size.width > 0, asset.size.height > 0 else { return nil }
        // Resolve the dynamic token explicitly; neither template tint nor SwiftUI
        // environment resolution is left to an offscreen ImageRenderer.
        let traits = UITraitCollection(userInterfaceStyle: key.dark ? .dark : .light)
        let tint = UIColor(YubaiColor.bambooShadow).resolvedColor(with: traits)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale; format.opaque = false; format.preferredRange = .standard
        let size = CGSize(width: 230 + padding * 2, height: 299 + padding * 2)
        let fit = min(230 / asset.size.width, 299 / asset.size.height)
        let fitted = CGSize(width: asset.size.width * fit, height: asset.size.height * fit)
        let rect = CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
        let bitmap = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            asset.withTintColor(tint, renderingMode: .alwaysOriginal).draw(in: rect)
        }
        guard let pixels = bitmap.cgImage, hasVisiblePixels(pixels) else { return nil }
        let input = CIImage(cgImage: pixels)
        let blurred = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6 * scale])
        guard let output = context.createCGImage(blurred, from: input.extent), hasVisiblePixels(output) else { return nil }
        let image = Image(uiImage: UIImage(cgImage: output, scale: scale, orientation: .up)).renderingMode(.original)
        #else
        let renderer = ImageRenderer(content: source.blur(radius: 6).padding(padding).environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let bitmap = renderer.nsImage else { return nil }
        let image = Image(nsImage: bitmap)
        #endif
        images[key] = image; return image
    }
    #if os(iOS)
    /// A non-nil renderer result can still be transparent. Never retain one.
    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: 32 * 40 * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 32, height: 40, bitsPerComponent: 8, bytesPerRow: 32 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 40))
            return stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 0 }
        }
    }
    #endif
}

private struct PaperBackground: ViewModifier {
    @Environment(\.yubaiRootSurface) private var rootSurface
    @Environment(\.yubaiSheetSurface) private var inSheet
    func body(content: Content) -> some View {
        if rootSurface && !inSheet { content }
        else { content.background { PaperCanvas() } }
    }
}

/// Leave a real slot for a toast, including on older pushed List/Form pages.
/// The floating navigation is outside this modifier and keeps its position.
private struct ToastContentSlot: ViewModifier {
    @Environment(\.yubaiToastClearance) private var clearance
    @Environment(\.yubaiSheetSurface) private var inSheet
    func body(content: Content) -> some View {
        content.padding(.bottom, inSheet ? 0 : clearance)
    }
}

private struct RootPaperBackground: ViewModifier {
    @Environment(AppStore.self) private var store
    func body(content: Content) -> some View {
        content.environment(\.yubaiRootSurface, true)
            .background { PaperCanvas(showsBamboo: true, bambooTrigger: store.entrySaveTrigger) }
    }
}

#if os(iOS)
/// Style the native back item so its title, pop gesture and navigation history stay native.
private struct NavigationBackPaper: UIViewControllerRepresentable {
    @Environment(\.colorScheme) private var scheme
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.dark = scheme == .dark
        controller.applySurface()
    }
    final class Controller: UIViewController {
        var dark = false
        override func loadView() {
            view = UIView(); view.backgroundColor = .clear
            view.isUserInteractionEnabled = false; view.accessibilityElementsHidden = true
        }
        override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); applySurface() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); applySurface() }
        func applySurface() {
            guard let bar = navigationController?.navigationBar else { return }
            bar.layer.sublayers?.filter { $0.name == "yubai.headerFade" }.forEach { $0.removeFromSuperlayer() }
            guard let previous = bar.items?.dropLast().last else { return }
            let fade = CAGradientLayer()
            fade.name = "yubai.headerFade"
            fade.frame = CGRect(x: 0, y: bar.bounds.height, width: bar.bounds.width, height: 24)
            fade.colors = [UIColor(YubaiColor.canvas).cgColor, UIColor(YubaiColor.canvas).withAlphaComponent(0).cgColor]
            bar.layer.addSublayer(fade)
            bar.clipsToBounds = false
            previous.backButtonDisplayMode = .minimal
            let back = previous.backBarButtonItem ?? UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
            back.title = ""
            back.accessibilityLabel = "返回"
            // UIKit exposes the native item as BackButton on iOS 26.
            // All UI tests use this same native identifier.
            back.accessibilityIdentifier = "BackButton"
            if let bar = navigationController?.navigationBar {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(YubaiColor.canvas)
                appearance.shadowColor = .clear
                appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 16, weight: .bold)), .foregroundColor: UIColor(YubaiColor.label)]
                bar.standardAppearance = appearance; bar.scrollEdgeAppearance = appearance; bar.compactAppearance = appearance
            }
            // This customization only affects the back button, including on pushed sheet pages.
            if #available(iOS 26, *) { back.hidesSharedBackground = true }
            let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let token = YubaiShadow.control
            let image = UIGraphicsImageRenderer(size: CGSize(width: 52, height: 48)).image { renderer in
                let context = renderer.cgContext
                context.setShadow(offset: CGSize(width: token.x, height: token.y), blur: token.radius,
                                  color: UIColor(token.color).resolvedColor(with: traits).cgColor)
                UIColor(YubaiColor.raised).resolvedColor(with: traits).setFill()
                UIBezierPath(roundedRect: CGRect(x: 6, y: 4, width: 40, height: 40), cornerRadius: 20).fill()
            }.resizableImage(withCapInsets: UIEdgeInsets(top: 24, left: 26, bottom: 24, right: 26), resizingMode: .stretch)
                .withAlignmentRectInsets(UIEdgeInsets(top: 4, left: 6, bottom: 8, right: 6)).withRenderingMode(.alwaysOriginal)
            back.setBackButtonBackgroundImage(image, for: .normal, barMetrics: .default)
            back.setBackButtonBackgroundImage(image, for: .normal, barMetrics: .compact)
            previous.backBarButtonItem = back
        }
    }
}
#endif

/// Only the paper casts a shadow; rows, chips and charts remain flat.
private struct PaperCardSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.yubaiFormSurface) private var formSurface
    @Environment(\.yubaiCardContent) private var insideCard
    #if os(iOS)
    @State private var shadowRasterFailed = false
    #endif
    let shape: S
    var background: Color?
    var flat = false
    private var castsShadow: Bool { !flat && !formSurface && !insideCard }
    func body(content: Content) -> some View {
        // Cover the paper's empty space without adding a gesture or an overlay
        // above nested controls. Decorative shadows stay outside the hit area.
        content.contentShape(.interaction, shape).environment(\.yubaiCardContent, true).background {
            Group {
                if castsShadow {
                    paperWithShadow
                } else { paper }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    @ViewBuilder private var paperWithShadow: some View {
        #if os(iOS)
        if let rounded = shape as? RoundedRectangle, !shadowRasterFailed {
            highlightedPaper.background {
                PaperShadowView(shape: rounded, scheme: scheme, increasedContrast: contrast == .increased) {
                    shadowRasterFailed = true
                }
            }
        } else {
            highlightedPaper.yubaiShadow(YubaiShadow.cardNear).yubaiShadow(YubaiShadow.card)
        }
        #else
        highlightedPaper.yubaiShadow(YubaiShadow.cardNear).yubaiShadow(YubaiShadow.card)
        #endif
    }
    private var highlightedPaper: some View {
        paper.overlay {
            if contrast != .increased {
                shape.strokeBorder(Color.white.opacity(scheme == .dark ? 10.0 / 255 : 179.0 / 255), lineWidth: 1)
                    .mask(alignment: .top) { Rectangle().frame(height: 2) }
            }
        }
    }
    private var paper: some View {
        shape.fill(background ?? (formSurface ? YubaiColor.card : insideCard ? YubaiColor.paperInset : YubaiColor.paperSheet))
            .overlay { if contrast == .increased && !insideCard { shape.strokeBorder(YubaiColor.separator, lineWidth: 1) } }
    }
}

#if os(iOS)
/// SwiftUI only sees the card-sized container. The decorative overflow stays in
/// UIKit, outside both SwiftUI layout and the enclosing element's AX bounds.
@MainActor private struct PaperShadowView: UIViewRepresentable {
    @Environment(\.displayScale) private var displayScale
    let shape: RoundedRectangle
    let scheme: ColorScheme
    let increasedContrast: Bool
    let onRasterFailure: @MainActor () -> Void

    func makeUIView(context: Context) -> ShadowView { ShadowView(frame: .zero) }
    func updateUIView(_ view: ShadowView, context: Context) {
        view.shape = shape
        view.scheme = scheme
        view.scale = displayScale
        view.increasedContrast = increasedContrast
        view.onRasterFailure = onRasterFailure
        view.setNeedsLayout()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ShadowView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    final class ShadowView: UIView {
        var shape = RoundedRectangle(cornerRadius: 0)
        var scheme: ColorScheme = .light
        var scale: CGFloat = 1
        var increasedContrast = false
        var onRasterFailure: (@MainActor () -> Void)?
        private let imageView = UIImageView()
        private var padding: CGFloat = 0
        private struct RenderKey: Equatable {
            let size: CGSize; let cornerSize: CGSize; let style: String
            let dark: Bool; let scale: CGFloat; let increasedContrast: Bool
        }
        private var lastRender: RenderKey?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            clipsToBounds = false
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            imageView.contentMode = .scaleToFill
            imageView.isUserInteractionEnabled = false
            imageView.isAccessibilityElement = false
            imageView.accessibilityElementsHidden = true
            addSubview(imageView)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            // A zero-sized layout is not a rendering failure (e.g. before mount).
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
                imageView.image = nil
                lastRender = nil
                return
            }
            let key = RenderKey(size: bounds.size, cornerSize: shape.cornerSize, style: String(describing: shape.style),
                                dark: scheme == .dark, scale: scale, increasedContrast: increasedContrast)
            if key != lastRender {
                lastRender = key
                if let raster = PaperShadowCache.image(shape: shape, size: bounds.size, scheme: scheme, scale: scale, increasedContrast: increasedContrast) {
                    padding = raster.padding
                    let caps = UIEdgeInsets(top: raster.caps.top, left: raster.caps.leading,
                                            bottom: raster.caps.bottom, right: raster.caps.trailing)
                    imageView.image = raster.image.resizableImage(withCapInsets: caps, resizingMode: .stretch)
                } else {
                    imageView.image = nil
                    // Defer SwiftUI state changes until UIKit finishes layout.
                    // A failed renderer uses the original live double shadow.
                    Task { @MainActor [weak self] in
                        guard let self, self.lastRender == key, self.imageView.image == nil else { return }
                        self.onRasterFailure?()
                    }
                }
            }
            imageView.frame = bounds.insetBy(dx: -padding, dy: -padding)
        }
    }
}

@MainActor private enum PaperShadowCache {
    struct Raster { let image: UIImage; let caps: EdgeInsets; let padding: CGFloat }
    private struct Key: Hashable {
        let radiusX: CGFloat; let radiusY: CGFloat; let style: String
        let dark: Bool; let scale: CGFloat; let width: CGFloat; let height: CGFloat; let increasedContrast: Bool
    }
    private static var images: [Key: Raster] = [:]
    static func image(shape: RoundedRectangle, size: CGSize, scheme: ColorScheme, scale: CGFloat, increasedContrast: Bool) -> Raster? {
        guard size.width > 0, size.height > 0, scale > 0 else { return nil }
        let near = YubaiShadow.cardNear, far = YubaiShadow.card
        // Keep four blur radii on each side of a corner; only the constant middle
        // strips stretch. Short cards retain their full dimension so opposite
        // edges' blur kernels continue to overlap exactly as on the live shape.
        let spread = ceil(4 * (near.radius + far.radius))
        let padding = spread + ceil(max(abs(near.x) + abs(far.x), abs(near.y) + abs(far.y)))
        let edgeX = shape.cornerSize.width + spread, edgeY = shape.cornerSize.height + spread
        let width = min(size.width, edgeX * 2 + 1 / scale)
        let height = min(size.height, edgeY * 2 + 1 / scale)
        let key = Key(radiusX: shape.cornerSize.width, radiusY: shape.cornerSize.height,
                      style: String(describing: shape.style), dark: scheme == .dark, scale: scale, width: width, height: height, increasedContrast: increasedContrast)
        if let cached = images[key] { return cached }
        let extent = CGSize(width: width + padding * 2, height: height + padding * 2)
        let canvas = Canvas { context, _ in
            guard let source = context.resolveSymbol(id: 0) else { return }
            let origin = CGPoint(x: padding, y: padding)
            // Preserve the original near-then-far composition, including the
            // source alpha of the live highlight/increased-contrast stroke.
            var distant = context
            distant.addFilter(.shadow(color: far.color, radius: far.radius, x: far.x, y: far.y, options: .shadowOnly))
            distant.drawLayer { layer in
                layer.addFilter(.shadow(color: near.color, radius: near.radius, x: near.x, y: near.y))
                layer.draw(source, at: origin, anchor: .topLeading)
            }
            var close = context
            close.addFilter(.shadow(color: near.color, radius: near.radius, x: near.x, y: near.y, options: .shadowOnly))
            close.draw(source, at: origin, anchor: .topLeading)
        } symbols: {
            shape.fill(Color.black).overlay {
                if increasedContrast { shape.strokeBorder(Color.black, lineWidth: 1) }
                else {
                    shape.strokeBorder(Color.black.opacity(scheme == .dark ? 10.0 / 255 : 179.0 / 255), lineWidth: 1)
                        .mask(alignment: .top) { Rectangle().frame(height: 2) }
                }
            }.frame(width: width, height: height).tag(0)
        }.frame(width: extent.width, height: extent.height).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: canvas); renderer.scale = scale
        guard let rendered = renderer.uiImage else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = false
        format.preferredRange = .standard
        let bitmap = UIGraphicsImageRenderer(size: extent, format: format).image { _ in rendered.draw(at: .zero) }
        let caps = EdgeInsets(top: padding + (height - 1 / scale) / 2, leading: padding + (width - 1 / scale) / 2,
                             bottom: padding + (height - 1 / scale) / 2, trailing: padding + (width - 1 / scale) / 2)
        let raster = Raster(image: bitmap, caps: caps, padding: padding)
        if images.count >= 64 { images.removeAll(keepingCapacity: true) }
        images[key] = raster; return raster
    }
}
#endif

private struct FloatingSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var shadow: YubaiShadow.Token
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            if let tint { content.glassEffect(.regular.tint(tint).interactive(), in: shape) }
            else { content.glassEffect(.regular.interactive(), in: shape) }
        } else { content.background(tint ?? YubaiColor.raised, in: shape).yubaiShadow(shadow) }
    }
}

private struct ContentZoom: ViewModifier {
    @Environment(\.yubaiZoomNamespace) private var namespace
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let id: String?
    var source = false
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace, let id, !reduceMotion {
            if source { content.matchedTransitionSource(id: id, in: namespace) }
            else { content.navigationTransition(.zoom(sourceID: id, in: namespace)) }
        } else { content }
        #else
        content
        #endif
    }
}

private struct MessageEntrance: ViewModifier {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @State private var visible = false
    let user: Bool
    func body(content: Content) -> some View {
        content.opacity(user || visible ? 1 : 0).offset(y: user || reduceMotion || visible ? 0 : YubaiSpace.space8)
            .onAppear {
                guard !user else { return }
                withAnimation(YubaiMotion.entrance(reduceMotion: reduceMotion)) { visible = true }
            }
    }
}

private struct ChipSelection: ViewModifier {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let selected: Bool
    func body(content: Content) -> some View {
        content.animation(YubaiMotion.control(reduceMotion: reduceMotion), value: selected)
    }
}

extension View {
    func amountPrivacy(_ hidden: Bool) -> some View { contentTransition(.opacity).animation(YubaiMotion.quick, value: hidden) }
    func paperBackground() -> some View { modifier(PaperBackground()) }
    func yubaiSheetBackground() -> some View {
        environment(\.yubaiSheetSurface, true).environment(\.yubaiRootSurface, false)
            .environment(\.yubaiFormSurface, false)
            .environment(\.yubaiContentViewport, nil)
            .presentationBackground { PaperCanvas() }
    }
    func paperCardSurface<S: InsettableShape>(in shape: S, background: Color? = nil, flat: Bool = false) -> some View {
        modifier(PaperCardSurface(shape: shape, background: background, flat: flat))
    }
    func controlSurface<S: Shape>(in shape: S) -> some View {
        background(YubaiColor.raised, in: shape).yubaiShadow(YubaiShadow.control)
    }
    func rootScrollContentMargins(for destination: Destination, reservesNavigation: Bool = true) -> some View {
        #if os(iOS)
        // Insetting content alone still lets rows rest underneath the floating
        // controls. Keep the clipped viewport above them at every scroll offset.
        self.contentMargins(.bottom, YubaiSpace.gapGroup, for: .scrollContent)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollClipDisabled(false)
            .modifier(ScrollContentViewport())
            .padding(.bottom, reservesNavigation ? YubaiSize.rootBottomPadding(for: destination) : YubaiSpace.none)
        #else
        self.padding(.bottom, reservesNavigation ? YubaiSize.rootBottomPadding(for: destination) : YubaiSpace.none)
        #endif
    }
    func rootPageHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
        VStack(spacing: 0) {
            header().padding(.horizontal, YubaiSpace.insetPage)
                .padding(.top, YubaiSpace.gapGroup).padding(.bottom, YubaiSpace.space8)
                .frame(maxWidth: .infinity)
                .background(YubaiColor.canvas.ignoresSafeArea(edges: .top))
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain).accessibilityIdentifier("rootHeaderRegion")
                .zIndex(1)
                .overlay(alignment: .bottom) { PageFade(edge: .top).offset(y: 24) }
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped().contentShape(Rectangle())
        }.modifier(RootPaperBackground())
    }
    func pageLocalHorizontalGestures() -> some View {
        #if os(iOS)
        self.gesture(HorizontalPan(allowsSubgestures: true))
        #else
        self
        #endif
    }
    func hidesListDisclosure() -> some View {
        #if os(iOS)
        self.navigationLinkIndicatorVisibility(.hidden)
        #else
        self
        #endif
    }
    func floatingSurface<S: Shape>(in shape: S, tint: Color? = nil, shadow: YubaiShadow.Token = YubaiShadow.float) -> some View { modifier(FloatingSurface(shape: shape, tint: tint, shadow: shadow)) }
    func yubaiZoomSource(_ id: String) -> some View { modifier(ContentZoom(id: id, source: true)) }
    func yubaiZoomDestination(_ id: String?) -> some View { modifier(ContentZoom(id: id)) }
    func messageEntrance(user: Bool) -> some View { modifier(MessageEntrance(user: user)) }
    func chipSelection(_ selected: Bool) -> some View { modifier(ChipSelection(selected: selected)) }
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    var disabledBackground = Color.clear
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fixedSize(horizontal: false, vertical: true).yubaiFont(compact ? YubaiFont.callout : YubaiFont.button)
            .padding(.horizontal, compact ? YubaiSpace.space16 : YubaiSpace.gapSection).padding(.vertical, compact ? YubaiSpace.space8 : YubaiSpace.gapGroup)
            .frame(maxWidth: .infinity, minHeight: compact ? YubaiSize.rowIcon : YubaiSize.buttonHeight)
            .foregroundStyle(isEnabled ? YubaiColor.onBrand : YubaiColor.labelSecondary)
            .background(isEnabled ? YubaiColor.brand : disabledBackground, in: Capsule()).frame(minHeight: YubaiSize.tapMin).contentShape(Capsule())
            .contentViewportTarget().opacity(configuration.isPressed ? 0.75 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var background = YubaiColor.card
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(compact ? YubaiFont.callout : YubaiFont.button, weight: .regular)
            .padding(.horizontal, compact ? YubaiSpace.space16 : YubaiSpace.gapSection).padding(.vertical, compact ? YubaiSpace.space8 : YubaiSpace.gapGroup)
            .frame(maxWidth: .infinity, minHeight: compact ? YubaiSize.rowIcon : YubaiSize.buttonHeight)
            .foregroundStyle(isEnabled ? YubaiColor.label : YubaiColor.labelSecondary)
            .background(isEnabled ? background : Color.clear, in: Capsule()).frame(minHeight: YubaiSize.tapMin).contentShape(Capsule())
            .contentViewportTarget().opacity(configuration.isPressed ? 0.75 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

/// Opaque at the header/bar edge, transparent toward the scroll content.
struct PageFade: View {
    enum Edge: Equatable { case top, bottom }
    let edge: Edge
    var body: some View {
        LinearGradient(colors: edge == .top ? [YubaiColor.canvas, YubaiColor.canvas.opacity(0)] : [YubaiColor.canvas.opacity(0), YubaiColor.canvas],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: edge == .top ? 24 : 40).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct Page<Content: View>: View {
    let content: Content
    var spacing: CGFloat
    var topPadding: CGFloat
    init(spacing: CGFloat = YubaiSpace.gapSection, topPadding: CGFloat = YubaiSpace.insetPage, @ViewBuilder content: () -> Content) {
        self.content = content(); self.spacing = spacing; self.topPadding = topPadding
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, YubaiSpace.insetPage).padding(.top, topPadding)
                .padding(.bottom, YubaiSpace.gapSection)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.modifier(ScrollContentViewport()).scrollDismissesKeyboard(.interactively).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).paperBackground()
            .accessibilityElement(children: .contain)
    }
}

struct Card<Content: View>: View {
    enum Style { case standard, list, compact }
    let content: Content
    var style: Style
    var background: Color?
    init(style: Style = .standard, background: Color? = nil, @ViewBuilder content: () -> Content) {
        self.content = content(); self.style = style; self.background = background
    }
    var body: some View {
        content.environment(\.yubaiCardContent, true).padding(.horizontal, YubaiSpace.insetCard)
            .padding(.vertical, style == .list ? YubaiSpace.space4 : YubaiSpace.insetCard)
            .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(YubaiColor.label)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card), background: background)
            .accessibilityElement(children: .contain)
    }
}

/// A single list surface with lazy rows, including large ledgers and matching candidates.
struct CardRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let rows: Data
    private let rowSequence: Int
    var hasLeadingIcon: Bool
    var rowHeight: CGFloat
    let content: (Data.Element) -> Row
    init(_ rows: Data, hasLeadingIcon: Bool = false, rowHeight: CGFloat = YubaiSize.rowDouble, @ViewBuilder content: @escaping (Data.Element) -> Row) {
        self.rows = rows; self.hasLeadingIcon = hasLeadingIcon; self.rowHeight = rowHeight; self.content = content
        var sequence = Hasher()
        sequence.combine(rows.count)
        for row in rows { sequence.combine(row.id) }
        rowSequence = sequence.finalize()
    }
    var body: some View {
        Card(style: .list) {
            LazyVStack(spacing: YubaiSpace.none) {
                ForEach(rows) { row in
                    // One child per ID lets LazyVStack determine the row count
                    // without constructing every row to inspect the divider.
                    VStack(spacing: YubaiSpace.none) {
                        content(row).frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                        if row.id != rows.last?.id {
                            Rectangle().fill(YubaiColor.separator).frame(height: 1)
                                .padding(.leading, hasLeadingIcon ? YubaiSize.rowTextInset : YubaiSpace.none).accessibilityHidden(true)
                        }
                    }.transition(YubaiMotion.rowTransition(reduceMotion: reduceMotion))
                }
            }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: rowSequence)
        }
    }
}

struct SectionHeading: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var title: String
    var subtitle: String? = nil
    var amount: String? = nil
    var meta: String? = nil
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup))
        layout {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(title).yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.label)
                if let subtitle { Text(subtitle).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
            }
            if amount != nil || meta != nil {
                if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
                if let amount { Text(amount).yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.label) }
                if let meta { Text(meta).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
            }
        }
    }
}

/// Labels and money retain their fonts; the value gets its own line before
/// either side is squeezed. The stacked value can wrap even at accessibility5.
struct AdaptiveValueRow<Label: View, Value: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var spreadsValue = true
    @ViewBuilder let label: () -> Label
    @ViewBuilder let value: () -> Value
    var body: some View {
        if textSize.isAccessibilitySize { stacked }
        else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    label().fixedSize()
                    if spreadsValue { Spacer(minLength: YubaiSpace.space8) }
                    value().fixedSize()
                }
                stacked
            }
        }
    }
    private var stacked: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            label().frame(maxWidth: .infinity, alignment: .leading)
            value().fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AmountLabel: View {
    enum Role {
        case hero, display, input, large, amount, small, day, chart, summary, card, donut, account
        var font: YubaiFont.Style {
            switch self {
            case .hero: YubaiFont.amountHero
            case .display: YubaiFont.amountDisplay
            case .input: YubaiFont.amountInput
            case .large: YubaiFont.amountLarge
            case .amount: YubaiFont.amount
            case .small: YubaiFont.amountSmall
            case .day: YubaiFont.amountDay
            case .chart: YubaiFont.chartValue
            case .summary: YubaiFont.amountSummary
            case .card: YubaiFont.amountCard
            case .donut: YubaiFont.amountDonut
            case .account: YubaiFont.amountAccount
            }
        }
    }
    enum Sign { case automatic, inflow, outflow, none }
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let cents: Int64
    var large = false
    var hide = false
    var role: Role? = nil
    var sign: Sign = .automatic
    var currency: Bool? = nil
    var ink: Color = YubaiColor.label
    private var resolvedRole: Role { role ?? (large ? .display : .amount) }
    private var text: String { Self.text(cents, sign: sign, currency: currency ?? (resolvedRole == .hero)) }
    private var numericValue: Double {
        switch sign { case .automatic: Double(cents) / 100; case .inflow, .none: abs(Double(cents)) / 100; case .outflow: -abs(Double(cents)) / 100 }
    }
    var body: some View {
        let font = resolvedRole.font
        Group {
            if hide { Text("••••").transition(.opacity) }
            else { Text(text).numberTransition(value: numericValue).transition(.opacity) }
        }.yubaiFont(font).foregroundStyle(ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(hide ? "金额已隐藏" : text)
            .animation(YubaiMotion.quick, value: hide)
    }
    static func text(_ cents: Int64, sign: Sign = .automatic, currency: Bool = false) -> String {
        let magnitude = cents.magnitude
        let units = magnitude / 100
        let digits = String(units)
        let grouped = digits.enumerated().map { index, digit in (index > 0 && (digits.count - index) % 3 == 0 ? "," : "") + String(digit) }.joined()
        let prefix: String
        switch sign { case .automatic: prefix = cents < 0 ? "−" : ""; case .inflow: prefix = "+"; case .outflow: prefix = "−"; case .none: prefix = "" }
        let fraction = magnitude % 100
        let currencyText = currency ? "¥" : ""
        let fractionText = fraction < 10 ? "0" + String(fraction) : String(fraction)
        return prefix + currencyText + grouped + "." + fractionText
    }
}

struct Pill: View {
    enum Variant { case brand, amber, neutral }
    var text: String
    var variant: Variant = .brand
    var height: CGFloat = YubaiSize.pillHeight
    var showsDot = true
    var showsChevron = false
    private var ink: Color { switch variant { case .brand: YubaiColor.brandInk; case .amber: YubaiColor.amberInk; case .neutral: YubaiColor.labelMuted } }
    private var background: Color { switch variant { case .brand: YubaiColor.brandTint; case .amber: YubaiColor.amberTint; case .neutral: YubaiColor.raised } }
    var body: some View {
        HStack(spacing: YubaiSpace.space8) {
            if showsDot { Circle().fill(variant == .amber ? YubaiColor.amberDot : YubaiColor.brandMark).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(text).yubaiFont(height < YubaiSize.pillHeight ? YubaiFont.meta : YubaiFont.caption)
            if showsChevron { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta, weight: .medium).accessibilityHidden(true) }
        }.padding(.horizontal, height < YubaiSize.pillHeight ? YubaiSpace.space8 : YubaiSpace.gapGroup)
            .padding(.vertical, YubaiSpace.space4).frame(minHeight: height).foregroundStyle(ink).background(background, in: Capsule()).contentShape(Capsule())
    }
}

struct EntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @State private var highlighted = true
    var entry: Entry
    var hideAmount = false
    var metadata: String? = nil
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "M月d日"
        return formatter
    }()
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        layout {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(spacing: YubaiSpace.space8) {
                    Text(entry.displayTitle).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label).lineLimit(1).truncationMode(.tail)
                    if entry.hasNoCaptureCategory { Pill(text: "没分类", variant: .amber, height: 20, showsDot: false) }
                    if metadata != nil && entry.nature.uncertain { Pill(text: "没写用途", variant: .amber, height: 20, showsDot: false) }
                }
                Text(metadata ?? "\(dateText) · \(Classification.displayCategory(entry.category)) · \(store.accountName(entry.accountID))")
                    .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).lineLimit(textSize.isAccessibilitySize ? nil : 1)
                if metadata == nil && entry.nature.uncertain { Pill(text: "没写用途", variant: .amber, height: 20) }
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
            AmountLabel(cents: entry.amount, hide: hideAmount, sign: entry.nature.inflow ? .inflow : .outflow)
                .layoutPriority(1)
        }.padding(.vertical, YubaiSpace.space4).frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
            .background(store.freshEntryIDs.contains(entry.id) && highlighted ? YubaiColor.brandTint : .clear)
            .task(id: store.freshEntryIDs.contains(entry.id)) {
                guard store.freshEntryIDs.contains(entry.id), YubaiMotion.claim("new-row-" + entry.id.uuidString) else { highlighted = false; return }
                withAnimation(YubaiMotion.wash(reduceMotion: reduceMotion)) { highlighted = false }
            }
    }
    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(entry.date) { return "今天 " + entry.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))) }
        if calendar.isDateInYesterday(entry.date) { return "昨天" }
        return Self.dateFormatter.string(from: entry.date)
    }
}

struct EntryLink: View {
    @Environment(AppStore.self) private var store
    let entry: Entry
    var hideAmount = false
    var editable = false
    var metadata: String? = nil
    var body: some View {
        if editable {
            Button { store.sheetSource = nil; store.sheet = .editEntry(entry.id) } label: {
                EntryRow(entry: entry, hideAmount: hideAmount, metadata: metadata)
            }.buttonStyle(PressButtonStyle())
        } else {
            NavigationLink {
                EntryDetailView(entryID: entry.id)
            } label: {
                EntryRow(entry: entry, hideAmount: hideAmount)
            }.buttonStyle(PressButtonStyle())
        }
    }
}

/// Monochrome paper and cloth; the small tag is separated with its host surface color.
struct BrandMark: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    var size: CGFloat = 43
    var background = YubaiColor.canvas
    var jumpTrigger = 0
    private var tag: some View {
        RoundedRectangle(cornerRadius: size / 24)
            .fill(.foreground)
            .overlay { RoundedRectangle(cornerRadius: size / 24).stroke(background, lineWidth: size / 24) }
            .frame(width: size * 4.2 / 24, height: size * 3 / 24)
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            let outline = RoundedRectangle(cornerRadius: size * 5.2 / 24)
            outline.fill(.foreground)
                .mask(alignment: .trailing) { Rectangle().frame(width: size * 6 / 24) }
                .frame(width: size * 18 / 24, height: size * 18 / 24).offset(x: size * 3 / 24, y: size * 3 / 24)
            outline.stroke(.foreground, lineWidth: size * (size >= 40 ? 1.6 : 1.8) / 24)
                .frame(width: size * 18 / 24, height: size * 18 / 24).offset(x: size * 3 / 24, y: size * 3 / 24)
            Group {
                if reduceMotion { tag }
                else {
                    tag.keyframeAnimator(initialValue: CGFloat.zero, trigger: jumpTrigger) { content, y in
                        content.offset(y: y)
                    } keyframes: { _ in
                        SpringKeyframe(CGFloat(-1.5), duration: YubaiMotion.durationTagHopHalf, spring: YubaiMotion.snappySpring)
                        SpringKeyframe(CGFloat.zero, duration: YubaiMotion.durationTagHopHalf, spring: YubaiMotion.snappySpring)
                    }
                }
            }.offset(x: size * 13.4 / 24, y: size * 6.4 / 24)
        }.frame(width: size, height: size).accessibilityElement(children: .ignore).accessibilityLabel("余白")
    }
}

struct PaperClothOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 5.2, height: 5.2))
        path.move(to: CGPoint(x: 15, y: 3)); path.addLine(to: CGPoint(x: 15, y: 6.4))
        path.move(to: CGPoint(x: 15, y: 9.4)); path.addLine(to: CGPoint(x: 15, y: 21))
        path.addRoundedRect(in: CGRect(x: 13.4, y: 6.4, width: 4.2, height: 3), cornerSize: CGSize(width: 1, height: 1))
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale))
    }
}

struct NowTabGlyph: View {
    var size: CGFloat
    var selected: Bool
    var body: some View {
        PaperClothOutline().stroke(.foreground, style: StrokeStyle(lineWidth: size * (selected ? 1.9 : 1.6) / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct AssistantMark: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    var size: CGFloat = 26
    var color = YubaiColor.brandGlyph
    var thinking = false
    private var leaf: some View {
        ZStack {
            BambooLeaf().fill(color)
            Path { path in
                path.move(to: CGPoint(x: size * 3.2 / 24, y: size * 15.5 / 24))
                path.addLine(to: CGPoint(x: size * 1.6 / 24, y: size * 17.2 / 24))
            }.stroke(color, style: StrokeStyle(lineWidth: size * 1.6 / 24, lineCap: .round))
        }
    }
    var body: some View {
        Group {
            if thinking && !reduceMotion {
                leaf.phaseAnimator([false, true]) { content, right in
                    content.rotationEffect(.degrees(right ? 6 : -6), anchor: UnitPoint(x: 3.2 / 24, y: 15.5 / 24))
                } animation: { _ in YubaiMotion.easeInOut(duration: YubaiMotion.durationThink / 2) }
            } else { leaf.transaction { $0.animation = nil; $0.disablesAnimations = true } }
        }.frame(width: size, height: size)
            .transaction { if !thinking || reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isImage)
            .accessibilityLabel(thinking ? "余白正在思考" : "余白")
    }
}

private struct BambooLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addCurve(to: CGPoint(x: 6.6, y: -3.9), control1: CGPoint(x: 1.2, y: -1.4), control2: CGPoint(x: 2.7, y: -3.7))
        path.addCurve(to: CGPoint(x: 19.5, y: 2), control1: CGPoint(x: 11.7, y: -2.7), control2: CGPoint(x: 16.8, y: 0.2))
        path.addCurve(to: CGPoint(x: 6.2, y: 3), control1: CGPoint(x: 16.4, y: 2.3), control2: CGPoint(x: 11.3, y: 3.9))
        path.addCurve(to: .zero, control1: CGPoint(x: 2.7, y: 2.9), control2: CGPoint(x: 1, y: 1.2))
        path.closeSubpath()
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(rotationAngle: -38 * .pi / 180))
            .applying(CGAffineTransform(translationX: 3.2, y: 15.5))
            .applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale))
    }
}

struct InlineNote: View {
    enum Style { case footnote, explanation, attention, reminder, inline }
    var text: String
    var style: Style = .footnote
    var detail: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var secondaryAction: String? = nil
    var onSecondaryAction: (() -> Void)? = nil
    var body: some View {
        Group {
            switch style {
            case .footnote:
                Text(text).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            case .explanation:
                Text(text).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(YubaiSpace.insetCard).paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            case .attention:
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(text).yubaiFont(YubaiFont.row, weight: .medium).foregroundStyle(YubaiColor.amberStrong)
                    if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
                    if action != nil || secondaryAction != nil {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.space8) { actions }
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) { actions }
                        }.padding(.top, YubaiSpace.gapAction)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.insetCard)
                    .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row), background: YubaiColor.amberTint)
            case .reminder, .inline:
                HStack(spacing: YubaiSpace.space8) {
                    Circle().fill(YubaiColor.amberDot).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(text).yubaiFont(YubaiFont.callout).foregroundStyle(style == .reminder ? YubaiColor.amberStrong : YubaiColor.labelMuted)
                    Spacer(minLength: YubaiSpace.space4)
                    if let action, let onAction {
                        Button(action, action: onAction).yubaiFont(YubaiFont.callout).foregroundStyle(style == .reminder ? YubaiColor.amberInk : YubaiColor.brandInk).frame(minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle())
                    }
                }.padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: style == .reminder ? YubaiSize.rowSingle : YubaiSize.rowDouble)
                    .background(style == .reminder ? YubaiColor.amberTint : Color.clear, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var actions: some View {
        if let action, let onAction {
            Button(action: onAction) {
                Text(action).yubaiFont(YubaiFont.callout, weight: .medium).padding(.horizontal, YubaiSpace.gapGroup)
                    .frame(minHeight: YubaiSize.chipHeight).foregroundStyle(YubaiColor.amberStrong).background(YubaiColor.raised, in: Capsule())
                    .frame(minHeight: YubaiSize.tapMin).contentShape(Capsule())
            }.buttonStyle(PressButtonStyle())
        }
        if let secondaryAction, let onSecondaryAction {
            Button(secondaryAction, action: onSecondaryAction).yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup)
                .frame(minHeight: YubaiSize.tapMin).foregroundStyle(YubaiColor.amberInk).buttonStyle(PressButtonStyle())
        }
    }
}

enum EmptyStateKind: String, CaseIterable {
    case ledger, saving, wish, bills, assistant, profile, memories, frequent, budget, search
    var title: String {
        switch self {
        case .ledger: "还没有账"
        case .saving: "先定每月存多少"
        case .wish: "想要的东西写在这里"
        case .bills: "房租、话费、会员"
        case .assistant: "问一句试试"
        case .profile: "钱该怎么花，你说了算"
        case .memories: "聊过的会记在这里"
        case .frequent: "常记的会自己出现"
        case .budget: "给一类定个数"
        case .search: "没有找到"
        }
    }
    var action: String? {
        switch self {
        case .ledger: "记一笔"
        case .saving: "开始存钱"
        case .wish: "写一个心愿"
        case .bills: "加一张账单"
        case .assistant: nil
        case .profile: "写一句"
        case .memories: "去聊一句"
        case .frequent: "自己加一个"
        case .budget: "定一个"
        case .search: "清掉筛选"
        }
    }
    var secondary: String? { switch self { case .ledger: "导入"; case .search: "看全部时间"; default: nil } }
    static let questions = ["这个月哪里花多了", "我买得起这台相机吗", "帮我记一笔 午饭 28"]
}

/// One empty-state layout for every page, including missing/deleted records.
struct EmptyState: View {
    var kind: EmptyStateKind
    var title: String
    var action: String?
    var onAction: (() -> Void)?
    var secondary: String?
    var onSecondary: (() -> Void)?
    var onExample: ((String) -> Void)?
    var actionIdentifier: String
    var secondaryIdentifier: String
    var titleIdentifier: String = ""
    init(_ kind: EmptyStateKind, title: String? = nil, actionIdentifier: String = "", secondaryIdentifier: String = "", titleIdentifier: String = "",
         onAction: (() -> Void)? = nil, onSecondary: (() -> Void)? = nil, onExample: ((String) -> Void)? = nil) {
        self.kind = kind; self.title = title ?? kind.title; self.action = kind.action; self.secondary = kind.secondary
        self.onAction = onAction; self.onSecondary = onSecondary; self.onExample = onExample
        self.actionIdentifier = actionIdentifier; self.secondaryIdentifier = secondaryIdentifier
        self.titleIdentifier = titleIdentifier
    }
    // Custom facts use the same ghost and serif line as the named page presets.
    init(_ icon: String, _ title: String, action: String? = nil, actionIdentifier: String = "", onAction: (() -> Void)? = nil) {
        self.kind = icon == "calendar" ? .bills : icon == "heart" ? .wish : icon == "text.book.closed" ? .memories : .ledger
        self.title = title; self.action = action; self.onAction = onAction
        self.actionIdentifier = actionIdentifier; self.secondaryIdentifier = ""
    }
    var body: some View {
        VStack(spacing: YubaiSpace.gapSection) {
            if kind == .assistant {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    ForEach(Array(EmptyStateKind.questions.enumerated()), id: \.offset) { index, question in
                        Button { onExample?(question) } label: {
                            Text(question).yubaiFont(YubaiFont.callout).fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, YubaiSpace.space12).padding(.vertical, YubaiSpace.space8)
                                .background(YubaiColor.raised, in: Capsule()).yubaiShadow(YubaiShadow.control)
                                .yubaiHitTarget(alignment: .leading)
                        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("askSuggestion_\(index)")
                    }
                }.frame(maxWidth: 280, minHeight: 156, alignment: .leading)
                    .frame(maxWidth: .infinity)
            } else if kind == .search {
                Image(systemName: "magnifyingglass").yubaiFont(YubaiFont.amountHero)
                    .foregroundStyle(YubaiColor.separator).frame(height: 156).accessibilityHidden(true)
            } else {
                EmptyGhostDrawing(kind: kind).frame(maxWidth: 240).frame(height: 156).accessibilityHidden(true)
            }
            Text(title).yubaiFont(YubaiFont.cardTitle).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(titleIdentifier)
            if (action != nil && onAction != nil) || (secondary != nil && onSecondary != nil) {
                ChipFlow {
                    if let action, let onAction {
                        Button(action, action: onAction).buttonStyle(PrimaryButtonStyle(compact: true))
                            .accessibilityIdentifier(actionIdentifier.isEmpty ? "emptyAction_" + kind.rawValue : actionIdentifier)
                    }
                    if let secondary, let onSecondary {
                        Button(secondary, action: onSecondary).buttonStyle(SecondaryButtonStyle(background: YubaiColor.card, compact: true))
                            .accessibilityIdentifier(secondaryIdentifier.isEmpty ? "emptySecondary_" + kind.rawValue : secondaryIdentifier)
                    }
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, YubaiSpace.gapSection)
            .accessibilityElement(children: .contain).accessibilityIdentifier("emptyState_" + kind.rawValue)
    }
}

/// Native, token-colored drawings of the future content, on the same warm paper.
private struct EmptyGhostDrawing: View {
    let kind: EmptyStateKind
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / 156)
            context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 156 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let dash = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
            func box(_ rect: CGRect, radius: CGFloat = 14, paper: Bool = false) {
                let path = Path(roundedRect: rect, cornerRadius: radius)
                if paper { context.fill(path, with: .color(YubaiColor.raised)) }
                context.stroke(path, with: .color(YubaiColor.separator), style: dash)
            }
            func line(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, brand: Bool = false) {
                let path = Path(roundedRect: CGRect(x: x, y: y, width: width, height: 7), cornerRadius: 4)
                context.fill(path, with: .color(brand ? YubaiColor.brand : YubaiColor.paperInset))
            }
            switch kind {
            case .ledger:
                box(CGRect(x: 12, y: 12, width: 216, height: 132), paper: true)
                for i in 0..<3 {
                    let y = CGFloat(28 + i * 38)
                    box(CGRect(x: 25, y: y, width: 26, height: 26), radius: 8)
                    line(62, y + 9, CGFloat(70 - i * 10)); line(171, y + 9, 42)
                }
            case .saving:
                var jar = Path(); jar.move(to: CGPoint(x: 101, y: 20)); jar.addLine(to: CGPoint(x: 139, y: 20))
                jar.move(to: CGPoint(x: 106, y: 20)); jar.addLine(to: CGPoint(x: 106, y: 36))
                jar.addCurve(to: CGPoint(x: 88, y: 60), control1: CGPoint(x: 89, y: 40), control2: CGPoint(x: 88, y: 50))
                jar.addLine(to: CGPoint(x: 88, y: 116)); jar.addQuadCurve(to: CGPoint(x: 102, y: 130), control: CGPoint(x: 88, y: 130))
                jar.addLine(to: CGPoint(x: 138, y: 130)); jar.addQuadCurve(to: CGPoint(x: 152, y: 116), control: CGPoint(x: 152, y: 130))
                jar.addLine(to: CGPoint(x: 152, y: 60)); jar.addQuadCurve(to: CGPoint(x: 134, y: 36), control: CGPoint(x: 152, y: 41))
                jar.addLine(to: CGPoint(x: 134, y: 20))
                context.stroke(jar, with: .color(YubaiColor.separator), style: StrokeStyle(lineWidth: 2, dash: [5, 6]))
                line(88, 108, 64, brand: true)
            case .wish:
                box(CGRect(x: 25, y: 47, width: 190, height: 60), paper: true)
                line(40, 63, 86); line(40, 86, 160); line(40, 86, 12, brand: true)
            case .bills:
                box(CGRect(x: 12, y: 30, width: 216, height: 96), paper: true)
                for i in 0..<21 {
                    let day = i + 8, x = CGFloat(34 + (i % 7) * 29), y = CGFloat(51 + (i / 7) * 27)
                    let text = Text(String(day)).font(.system(size: YubaiFont.chartLabel.size, design: YubaiFont.chartLabel.design)).foregroundColor(YubaiColor.labelMuted)
                    context.draw(text, at: CGPoint(x: x, y: y))
                    if day == 20 { context.stroke(Path(roundedRect: CGRect(x: x - 12, y: y - 12, width: 24, height: 24), cornerRadius: 8), with: .color(YubaiColor.brand), style: dash) }
                }
            case .profile:
                context.draw(Text("“ ”").font(.system(size: 48, design: .serif)).foregroundColor(YubaiColor.separator), at: CGPoint(x: 120, y: 68))
                var rule = Path(); rule.move(to: CGPoint(x: 42, y: 105)); rule.addLine(to: CGPoint(x: 198, y: 105))
                context.stroke(rule, with: .color(YubaiColor.separator), style: dash)
            case .memories:
                for i in 0..<3 {
                    let x: CGFloat = i == 1 ? 20 : 34, y = CGFloat(21 + i * 43), width: CGFloat = i == 1 ? 200 : 180
                    box(CGRect(x: x, y: y, width: width, height: 34), paper: true)
                    line(x + 14, y + 14, CGFloat(110 - i * 15))
                }
            case .frequent:
                for i in 0..<5 {
                    let x: CGFloat = i == 4 ? 86 : (i % 2 == 0 ? 35 : 118), y = CGFloat(33 + (i / 2) * 38)
                    box(CGRect(x: x, y: y, width: i == 3 ? 84 : 70, height: 29), radius: 15)
                }
            case .budget:
                box(CGRect(x: 12, y: 43, width: 216, height: 70), paper: true)
                line(27, 61, 186); line(27, 86, 186)
                var marker = Path(); marker.move(to: CGPoint(x: 161, y: 53)); marker.addLine(to: CGPoint(x: 161, y: 81))
                context.stroke(marker, with: .color(YubaiColor.brand), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            case .assistant, .search: break
            }
        }
    }
}

private struct ToastIntrinsicWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct ToastAvailableWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ToastNaturalHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct Toast: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var expanded = false
    @State private var naturalHeight: CGFloat = 0
    @State private var intrinsicWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    var text: String
    var undoTitle = "撤销"
    var onUndo: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var messageIdentifier = "toastMessage"
    var undoIdentifier = "undoLastChange"
    private var truncated: Bool { availableWidth > 0 && intrinsicWidth > availableWidth + 0.5 }
    private var hasChevron: Bool { truncated || expanded }
    private var timerKey: String { text + "-\(expanded)-\(visible)-\(phase)" }
    var body: some View {
        ZStack { if visible { surface } }
            .task(id: text) {
                expanded = false
                withAnimation(YubaiMotion.toastIn(reduceMotion: reduceMotion)) { visible = true }
                #if os(iOS)
                AccessibilityNotification.Announcement(text + (onUndo == nil ? "" : "，可撤销")).post()
                #endif
            }
            .task(id: timerKey) {
                guard visible, !expanded, phase == .active else { return }
                #if DEBUG && targetEnvironment(simulator)
                if onUndo != nil && UITestSupport.keepsUndoReceipt { return }
                #endif
                do { try await Task.sleep(for: .seconds(onUndo == nil ? 4 : 6)) } catch { return }
                guard !Task.isCancelled, !expanded else { return }
                dismiss()
            }
    }
    private var surface: some View {
        HStack(alignment: expanded ? .top : .center, spacing: YubaiSpace.space8) {
            HStack(alignment: expanded ? .top : .center, spacing: YubaiSpace.space8) {
                    if expanded {
                        ScrollView {
                            message
                        }.frame(height: min(max(YubaiFont.body.lineHeight, naturalHeight), YubaiSize.toastExpandedMaximumHeight))
                            .scrollBounceBehavior(.basedOnSize)
                    } else { message }
                    if hasChevron {
                        Button(action: toggle) {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").yubaiFont(YubaiFont.caption)
                                .foregroundStyle(YubaiColor.labelSecondary)
                        }.buttonStyle(TextLinkStyle()).accessibilityIdentifier("expandToast")
                            .accessibilityLabel(expanded ? "关闭提示" : "展开完整提示")
                            .accessibilityValue(expanded ? "已展开" : "")
                            .accessibilityHint("也可以点提示文字或向下划关闭")
                    }
            }.frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("toastBody")
            if let onUndo {
                Button(undoTitle, action: onUndo).yubaiFont(YubaiFont.row, weight: .semibold).foregroundStyle(YubaiColor.brandInk)
                    .padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.tapMin)
                    .background(YubaiColor.brandTint, in: Capsule()).fixedSize().yubaiHitTarget().buttonStyle(PressButtonStyle())
                    .accessibilityIdentifier(undoIdentifier)
            }
        }.padding(.leading, YubaiSpace.insetCard).padding(.trailing, YubaiSpace.space8).padding(.vertical, YubaiSpace.space4)
            .frame(minHeight: YubaiSize.buttonHeight).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.row)).yubaiShadow(YubaiShadow.card)
            .padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.gapGroup)
            .transition(YubaiMotion.toastTransition(reduceMotion: reduceMotion))
            .onPreferenceChange(ToastNaturalHeight.self) { naturalHeight = $0 }
            .onPreferenceChange(ToastIntrinsicWidth.self) { intrinsicWidth = $0 }
            .onPreferenceChange(ToastAvailableWidth.self) { availableWidth = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: YubaiSpace.gapGroup).onEnded { value in
                if value.translation.height > YubaiSpace.gapSection { dismiss() }
            })
    }
    private var message: some View {
        Text(text).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            .lineLimit(expanded ? nil : 1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ToastAvailableWidth.self, value: proxy.size.width)
                        .preference(key: ToastNaturalHeight.self, value: proxy.size.height)
                }
            }
            .background(alignment: .leading) {
                Text(text).yubaiFont(YubaiFont.body).lineLimit(1).fixedSize().hidden().accessibilityHidden(true)
                    .background { GeometryReader { proxy in Color.clear.preference(key: ToastIntrinsicWidth.self, value: proxy.size.width) } }
            }.onTapGesture(perform: toggle).accessibilityAction { toggle() }
            .accessibilityLabel(text).accessibilityIdentifier(messageIdentifier)
    }
    private func toggle() {
        if expanded || !truncated { dismiss() }
        else { withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { expanded = true } }
    }
    private func dismiss() {
        withAnimation(YubaiMotion.toastOut(reduceMotion: reduceMotion)) { visible = false; onDismiss?() }
    }
}

extension View {
    func appErrors() -> some View { modifier(AppErrorPresenter()) }
    func numericInput() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad).background { NumberKeyboardAccessory().frame(width: 0, height: 0) }
        #else
        self
        #endif
    }
    func editorForm() -> some View {
        self.formStyle(.grouped).scrollContentBackground(.hidden).paperBackground()
            .modifier(ScrollContentViewport())
            .environment(\.yubaiFormSurface, true)
            .environment(\.defaultMinListRowHeight, YubaiSize.rowSingle).scrollDismissesKeyboard(.interactively)
            .yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).tint(YubaiColor.brand).buttonStyle(TextLinkStyle())
    }
    func yubaiNavigation() -> some View {
        self.modifier(ToastContentSlot()).paperBackground().tint(YubaiColor.brandInk)
            .environment(\.yubaiRootSurface, false).environment(\.yubaiFormSurface, false)
            #if os(iOS)
            .background { NavigationBackPaper().frame(width: YubaiSpace.none, height: YubaiSpace.none) }
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(YubaiColor.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            #elseif os(macOS)
            .toolbarBackground(YubaiColor.canvas, for: .windowToolbar).toolbarBackground(.visible, for: .windowToolbar)
            #endif
    }
}

private struct AppErrorPresenter: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var identity = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { if !store.errorHosts.contains(identity) { store.errorHosts.append(identity) } }
            .onDisappear { store.errorHosts.removeAll { $0 == identity } }
            .alert("需要留意", isPresented: Binding(get: { store.error != nil && store.errorHosts.last == identity }, set: { value in if !value && store.errorHosts.last == identity { store.error = nil } })) {
                #if os(iOS)
                if (store.error ?? "").contains("权限") || (store.error ?? "").contains("授权") {
                    Button("去设置") { if let settings = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(settings) }; store.error = nil }
                }
                #endif
                if store.loadFailure != nil { Button("恢复账本") { store.error = nil; store.sheet = .history } }
                Button("知道了", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

struct SuggestionChips: View {
    let values: [String]
    var selected: String? = nil
    var identifierPrefix = "suggestion_"
    let choose: (String) -> Void
    var body: some View {
        ChipFlow(rowSpacing: YubaiSpace.gapGroup) { chips }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var chips: some View {
        ForEach(values, id: \.self) { value in
            CategoryChoiceChip(title: value, selected: selected == value) { choose(value) }
                .accessibilityIdentifier(identifierPrefix + value)
        }
    }
}

struct CategoryChoiceChip: View {
    let title: String
    var selected = false
    var outlined = false
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).yubaiFont(prominent ? YubaiFont.button : YubaiFont.callout, weight: prominent ? .semibold : nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                .foregroundStyle(selected ? YubaiColor.onBrand : (outlined ? YubaiColor.brandInk : YubaiColor.label))
                .background(selected ? YubaiColor.brand : (outlined ? Color.clear : YubaiColor.raised), in: Capsule())
                .overlay { if outlined { Capsule().strokeBorder(YubaiColor.brand, lineWidth: YubaiSize.separator) } }
                .frame(minHeight: YubaiSize.tapMin).contentShape(Capsule())
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ChipFlow: Layout {
    var spacing: CGFloat = YubaiSpace.space8
    var rowSpacing: CGFloat = YubaiSpace.space8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? .infinity, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        var frames: [CGRect] = []
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(width, ideal.width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + rowSpacing; rowHeight = 0 }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            usedWidth = max(usedWidth, x + size.width); rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}

struct LocalSourcePill: View {
    @State private var details = false
    var body: some View {
        Button { details = true } label: { Pill(text: "本机", variant: .neutral, showsDot: false) }
            .buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin)
            .accessibilityLabel("在本机读取，没有发给云端").accessibilityHint("查看来源详情")
            .popover(isPresented: $details) {
                VStack(spacing: YubaiSpace.gapGroup) {
                    LabeledContent("读取", value: "本机")
                    LabeledContent("云端发送", value: "0 行")
                }.yubaiFont(YubaiFont.callout).padding(YubaiSpace.insetPage).presentationCompactAdaptation(.popover)
            }
    }
}

struct SystemSettingsButton: View {
    enum Pane { case speech, notifications }
    @Environment(\.openURL) private var openURL
    let title: String
    let pane: Pane
    var body: some View {
        Button(title) {
            #if os(iOS)
            let address = pane == .notifications ? UIApplication.openNotificationSettingsURLString : UIApplication.openSettingsURLString
            if let url = URL(string: address) { openURL(url) }
            #elseif os(macOS)
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            #endif
        }.frame(minHeight: YubaiSize.tapMin).accessibilityHint("打开系统设置，调整余白的权限")
    }
}

struct EmptyAccountState: View {
    let add: () -> Void
    var body: some View {
        VStack(spacing: YubaiSpace.gapSection) {
            PaperClothOutline().stroke(YubaiColor.borderDashed, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .frame(width: 120, height: 120).accessibilityHidden(true)
            Button("添加第一个账户", action: add).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("addFirstAccount")
        }.frame(maxWidth: .infinity).padding(.vertical, YubaiSpace.gapSection)
            .accessibilityElement(children: .contain).accessibilityLabel("还没有账户")
    }
}

extension Nature {
    var entryLabel: String { paired ? "转账" : (inflow ? "收入" : "支出") }
}

struct HomeEntryPill: View {
    let title: String
    let action: () -> Void
    let quick: () -> Void
    var body: some View {
        HStack(spacing: YubaiSpace.space8) {
            Image(systemName: "plus").yubaiFont(YubaiFont.tabIcon, weight: .semibold)
            Text(title).yubaiFont(YubaiFont.fieldValue, weight: .semibold)
        }.foregroundStyle(YubaiColor.onBrand)
            .padding(.leading, YubaiSpace.space22).padding(.trailing, YubaiSpace.space28)
            .frame(height: YubaiSize.homeEntryPillHeight)
            .background { Capsule().fill(YubaiColor.brand).yubaiShadow(YubaiShadow.ask) }
            .contentShape(Capsule()).onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.4, perform: quick)
            .accessibilityElement(children: .ignore).accessibilityAddTraits(.isButton)
            .accessibilityLabel(title).accessibilityIdentifier("addEntry")
            .accessibilityAction(.default, action).accessibilityAction(named: "常用", quick)
            #if os(iOS)
            .accessibilityShowsLargeContentViewer { Label(title, systemImage: "plus") }
            #endif
    }
}

/// Header glyphs keep a 40pt circle and a 44pt hit target at every text size.
struct HeaderIconButton<Icon: View>: View {
    let action: () -> Void
    let icon: (CGFloat) -> Icon
    init(action: @escaping () -> Void, @ViewBuilder icon: @escaping (CGFloat) -> Icon) {
        self.action = action; self.icon = icon
    }
    var body: some View {
        let iconSize = YubaiSize.headerIcon
        let side = YubaiSize.iconButton
        Button(action: action) {
            icon(iconSize).accessibilityHidden(true)
                .frame(width: side, height: side).controlSurface(in: Circle())
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle())
    }
}

extension YubaiFont {
    static let savingsHero = Style(size: 40, lineHeight: 48, weight: .semibold, family: .num, tracking: -1.5, relativeTo: .largeTitle)
}

struct RoundPressStyle: ButtonStyle {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiHitTarget().opacity(configuration.isPressed ? 0.75 : 1)
            .animation(configuration.isPressed ? YubaiMotion.instant : (reduceMotion ? YubaiMotion.quick : YubaiMotion.lively), value: configuration.isPressed)
    }
}

struct ProposalCard: View {
    @Environment(AppStore.self) private var store
    let title: String
    let lines: [String]
    let primaryTitle: String
    var secondaryTitle = "不改了"
    var canConfirm = true
    let confirm: () -> Void
    let cancel: () -> Void
    @State private var expanded = false
    var body: some View {
        Card(style: .compact, background: YubaiColor.brandTint) {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(spacing: YubaiSpace.space8) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白的建议").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                Text(title).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.brandTintStrong)
                ForEach(Array((expanded ? lines : Array(lines.prefix(3))).enumerated()), id: \.offset) { _, line in
                    Text(line).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                }
                if lines.count > 3 && !expanded {
                    Button("还有 \(lines.count - 3) 项 ›") { expanded = true }.frame(minHeight: YubaiSize.tapMin).yubaiFont(YubaiFont.callout)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space8) { actions }
                    VStack(spacing: YubaiSpace.space8) { actions }
                }.padding(.top, YubaiSpace.gapAction)
            }
        }
    }
    private var actions: some View {
        Group {
            if store.preferences.hideAmounts {
                Button("显示金额") { store.update("显示金额", recordUndo: false) { $0.preferences.hideAmounts = false } }
                    .buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityHint("显示金额后可核对并确认修改")
            } else {
                Button(primaryTitle, action: confirm).buttonStyle(PrimaryButtonStyle(compact: true)).disabled(!canConfirm)
            }
            Button(secondaryTitle, action: cancel).buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
        }
    }
}

struct AssistantCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(YubaiSpace.insetCard).frame(maxWidth: .infinity, alignment: .leading)
            .paperCardSurface(in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 22), background: YubaiColor.paperSheet, flat: true)
    }
}

#if os(iOS)
/// A native input accessory avoids competing with the form's FocusState or duplicating keyboard toolbar items.
private struct NumberKeyboardAccessory: UIViewRepresentable {
    func makeUIView(context: Context) -> Anchor { Anchor(frame: .zero) }
    func updateUIView(_ view: Anchor, context: Context) { DispatchQueue.main.async { view.install() } }
    final class Anchor: UIView {
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; accessibilityElementsHidden = true }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() { super.didMoveToWindow(); DispatchQueue.main.async { self.install() } }
        func install() {
            func fields(_ view: UIView) -> [UITextField] {
                if let field = view as? UITextField { return [field] }
                return view.subviews.flatMap(fields)
            }
            var host = superview
            for _ in 0..<8 {
                guard let container = host else { return }
                let numeric = fields(container).filter { [.decimalPad, .numberPad, .asciiCapableNumberPad].contains($0.keyboardType) }
                if !numeric.isEmpty {
                    for field in numeric where field.inputAccessoryView?.accessibilityIdentifier != "numberKeyboardDone" {
                        let toolbar = UIToolbar(); toolbar.autoresizingMask = [.flexibleWidth]; toolbar.accessibilityIdentifier = "numberKeyboardDone"; toolbar.sizeToFit()
                        let done = UIBarButtonItem(title: "完成", style: .done, target: Target.shared, action: #selector(Target.finish))
                        done.setTitleTextAttributes([.foregroundColor: UIColor(YubaiColor.brandInk), .font: UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 16, weight: .medium))], for: .normal)
                        toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
                        field.inputAccessoryView = toolbar
                        if field.isFirstResponder { field.reloadInputViews() }
                    }
                    return
                }
                host = container.superview
            }
        }
    }
    @MainActor final class Target: NSObject {
        static let shared = Target()
        @objc func finish() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}
#endif

// MARK: - Round 45 shell

/// 金额文字，永远两位小数；隐藏金额时只留圆点。拼接文案用，单独显示金额用 `AmountLabel`。
func amount2(_ cents: Int64, hide: Bool) -> String { hide ? "••••" : AmountLabel.text(cents) }

/// 钱罐：24 格坐标系里的描边，粗细随选中态变化（和 `PaperClothOutline` 同一套写法）。
struct SavingJarOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 8.5, y: 2.8, width: 7, height: 3), cornerSize: CGSize(width: 1, height: 1))
        path.addRoundedRect(in: CGRect(x: 5.5, y: 6.4, width: 13, height: 14.8), cornerSize: CGSize(width: 4.4, height: 4.4))
        path.move(to: CGPoint(x: 9.5, y: 13.2)); path.addLine(to: CGPoint(x: 14.5, y: 13.2))
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale))
    }
}

/// 三个标签页的图标：底栏和 macOS 侧栏共用。
struct DestinationGlyph: View {
    let destination: Destination
    var selected = false
    var size: CGFloat = YubaiSize.tabIcon
    var body: some View {
        glyph.frame(width: size, height: size).accessibilityHidden(true)
    }
    @ViewBuilder private var glyph: some View {
        switch destination {
        case .now: Image(systemName: "clock").font(.system(size: size, weight: selected ? .medium : .regular))
        case .ledger: NowTabGlyph(size: size, selected: selected)
        case .yubai: Image(systemName: "leaf.fill").font(.system(size: size, weight: selected ? .medium : .regular))
        }
    }
}

/// 三个根页共用的页头：左边眼睛（显示/隐藏金额），右边设置，中间标题。
struct RootHeader: View {
    @Environment(AppStore.self) private var store
    let title: String
    private var iconSize: CGFloat { YubaiSize.headerIcon }
    private var side: CGFloat { YubaiSize.iconButton }
    var body: some View {
        HStack(spacing: YubaiSpace.none) {
            amountToggle
            Text(title).yubaiFont(YubaiFont.navTitle).lineLimit(1).frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("rootHeaderTitle")
            settingsLink
        }.frame(minHeight: YubaiSize.headerHeight)
            .accessibilityElement(children: .contain)
            // Safe-area headers can escape a hidden NavigationStack's AX
            // boundary. Hide the header at its own boundary as well.
            .accessibilityHidden(store.destination.title != title)
    }
    private var amountToggle: some View {
        Button { store.update("切换金额显示", recordUndo: false) { $0.preferences.hideAmounts.toggle() } } label: {
            icon(store.preferences.hideAmounts ? "eye.slash" : "eye")
        }.buttonStyle(PressButtonStyle())
            .accessibilityLabel(store.preferences.hideAmounts ? "显示金额" : "隐藏金额").accessibilityIdentifier("toggleAmountVisibility")
    }
    private var settingsLink: some View {
        TabNavigationLink(.settings) { SettingsView() } label: {
            icon("slider.horizontal.3")
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("设置").accessibilityIdentifier("openSettings")
    }
    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: iconSize)).accessibilityHidden(true)
            .frame(width: side, height: side).controlSurface(in: Circle()).yubaiHitTarget()
    }
}

// MARK: - Round 45 shared components

/// 现在页的一问两答卡：眉标、标题（名字 + 金额 + 问句）、两个答案；同时有几件事时右上角写「还有 N 件」。
struct QuestionCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let eyebrow: String
    let title: String
    var amount: Int64? = nil
    var question = ""
    var amber = false
    var more = 0
    var onMore: (() -> Void)? = nil
    var evidenceTitle: String? = nil
    var onEvidence: (() -> Void)? = nil
    var titleIdentifier = ""
    let yesTitle: String
    let noTitle: String
    var yesIdentifier = ""
    var noIdentifier = ""
    let yes: () -> Void
    let no: () -> Void
    private var headline: String {
        var parts = [title]
        if let amount { parts.append(amount2(amount, hide: store.preferences.hideAmounts)) }
        if !question.isEmpty { parts.append(question) }
        return parts.joined(separator: " ")
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                topLine
                Text(headline).yubaiFont(YubaiFont.butlerTitle).foregroundStyle(YubaiColor.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(titleIdentifier)
                answers.padding(.top, YubaiSpace.space4)
            }
        }.accessibilityElement(children: .contain)
    }
    private var topLine: some View { ButlerKicker(title: eyebrow, more: more, evidenceTitle: evidenceTitle, onEvidence: onEvidence) }
    private var answers: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            Button(yesTitle, action: yes).buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier(yesIdentifier)
            if !noTitle.isEmpty { Button(noTitle, action: no).buttonStyle(NowCardButtonStyle(primary: false)).accessibilityIdentifier(noIdentifier) }
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.none) }
        }
    }
}

/// 一行结果：左边标签，右边「a → b」之类的数；不够宽时上下排。可琥珀。
struct ResultBar: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let label: String
    let value: String
    var amber = false
    var identifier = ""
    /// 「a → b」两位小数。
    static func change(_ from: Int64, _ to: Int64, hide: Bool) -> String {
        amount2(from, hide: hide) + " → " + amount2(to, hide: hide)
    }
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: YubaiSpace.gapGroup))
        layout {
            Text(label).yubaiFont(YubaiFont.callout).foregroundStyle(amber ? YubaiColor.amberInk : YubaiColor.labelMuted)
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
            Text(value).yubaiFont(YubaiFont.amountSmall, weight: .semibold).foregroundStyle(amber ? YubaiColor.amberStrong : YubaiColor.brandInk)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
        }.padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.rowIcon, alignment: .leading)
            .background(amber ? YubaiColor.amberTint : YubaiColor.brandTint, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
            .accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
    }
}

struct AmountPreset: Identifiable, Equatable {
    var id: String
    var title: String
    var amount: Int64
    var identifier = ""
}
struct AmountSheetRow: Identifiable, Equatable {
    var label: String
    var value: String
    var amber = false
    var id: String { label }
}

/// 半屏记金额：标题、取消、两颗现成数、大金额、最多两行结果、数字键盘。
/// 超支补法、发工资、账单付了、算式页就地改共用。金额状态由调用方的 `EntryKeypad` 持有。
/// Numeric sheets keep the title and its monetary fact beside the keypad.
struct AmountSheetHeader: View {
    let title: String
    var subtitle: String? = nil
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            ManualSheetHeader(title: title, showsAction: false, cancelIdentifier: "amountSheetCancel", cancel: cancel, action: {}, preservesCancelIdentifier: true)
            if let subtitle { Text(subtitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
        }
    }
}

/// Measure uncompressed content independently of the presented height. Keeping
/// the keypad in the same VStack avoids the safe-area-inset/detent feedback
/// loop that reduced a sheet to just its keypad on the simulator.
struct KeypadSheet<Content: View, Footer: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var contentHeight: CGFloat = YubaiSize.sheet440
    @State private var footerHeight: CGFloat = YubaiSize.keypadHeight
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content().fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, YubaiSpace.insetPage)
                    .padding(.top, YubaiSpace.sheetHeaderTop).padding(.bottom, YubaiSpace.gapGroup)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { contentHeight = $0 } }
            }.scrollBounceBehavior(.basedOnSize).modifier(ScrollContentViewport())
            footer().fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { footerHeight = $0 } }
        }.presentationDetents(textSize.isAccessibilitySize ? [.large] : [.height(contentHeight + footerHeight), .large])
            .accessibilityElement(children: .contain)
    }
}

struct AmountEntrySheet<Accessory: View>: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    var subtitle: String? = nil
    var presets: [AmountPreset] = []
    @Binding var keypad: EntryKeypad
    var rows: [AmountSheetRow] = []
    let primaryTitle: String
    var primaryIdentifier = "amountSheetDone"
    var canSave = true
    var primaryAboveKeypad = false
    var cancel: (() -> Void)? = nil
    let save: () -> Void
    let accessory: Accessory
    @State private var selected: Bool

    init(title: String, subtitle: String? = nil, presets: [AmountPreset] = [], keypad: Binding<EntryKeypad>,
         rows: [AmountSheetRow] = [], primaryTitle: String, primaryIdentifier: String = "amountSheetDone",
         canSave: Bool = true, startsSelected: Bool = true, primaryAboveKeypad: Bool = false, cancel: (() -> Void)? = nil, save: @escaping () -> Void,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.subtitle = subtitle; self.presets = presets; _keypad = keypad; self.rows = Array(rows.prefix(2))
        self.primaryTitle = primaryTitle; self.primaryIdentifier = primaryIdentifier; self.canSave = canSave; self.primaryAboveKeypad = primaryAboveKeypad
        self.cancel = cancel; self.save = save; self.accessory = accessory()
        _selected = State(initialValue: startsSelected)
    }
    var body: some View {
        KeypadSheet {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                header
                if !presets.isEmpty { presetRow }
                amountDisplay
                ForEach(rows) { row in ResultBar(label: row.label, value: row.value, amber: row.amber) }
                accessory
            }
        } footer: {
                VStack(spacing: YubaiSpace.none) {
                    if primaryAboveKeypad {
                        Button(primaryTitle, action: save).buttonStyle(PrimaryButtonStyle())
                            .disabled(!canSave).accessibilityIdentifier(primaryIdentifier)
                            .padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.gapGroup)
                    }
                    AmountKeypad(keypad: $keypad, amountSelected: $selected, canSave: canSave,
                                 primaryTitle: primaryTitle, primaryIdentifier: primaryIdentifier, save: save, showsPrimary: !primaryAboveKeypad)
                }.accessibilityElement(children: .contain)
        }
            .accessibilityElement(children: .contain)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            #endif
    }
    private var header: some View {
        AmountSheetHeader(title: title, subtitle: subtitle, cancel: { if let cancel { cancel() } else { dismiss() } })
    }
    private var presetRow: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
        return layout { ForEach(presets) { preset in presetButton(preset) } }
    }
    private func presetButton(_ preset: AmountPreset) -> some View {
        let on = keypad.amount == preset.amount
        return Button {
            keypad = EntryKeypad(amount: preset.amount); selected = true
        } label: {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(preset.title).yubaiFont(YubaiFont.caption)
                Text(amount2(preset.amount, hide: store.preferences.hideAmounts)).yubaiFont(YubaiFont.amountSummary)
            }.foregroundStyle(on ? YubaiColor.raised : YubaiColor.label)
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
                .background(on ? YubaiColor.label : YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier(preset.identifier)
    }
    private var amountDisplay: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.none) {
            if let expression = keypad.expressionText {
                Text(expression).yubaiFont(YubaiFont.amount).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("entryKeypadExpression")
            }
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                if primaryAboveKeypad { Spacer(minLength: 0) }
                Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                Text(keypad.groupedResultText).yubaiFont(YubaiFont.entryAmount)
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                    .padding(.horizontal, 6)
                if !primaryAboveKeypad { EntryAmountCursor() }
                Spacer(minLength: 0)
            }.frame(minHeight: YubaiSize.rowDouble)
        }.accessibilityElement(children: .ignore).accessibilityLabel("金额").accessibilityValue(keypad.resultText)
            .accessibilityIdentifier("amountSheetAmount")
    }
}
extension AmountEntrySheet where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, presets: [AmountPreset] = [], keypad: Binding<EntryKeypad>,
         rows: [AmountSheetRow] = [], primaryTitle: String, primaryIdentifier: String = "amountSheetDone",
         canSave: Bool = true, startsSelected: Bool = true, primaryAboveKeypad: Bool = false, cancel: (() -> Void)? = nil, save: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, presets: presets, keypad: keypad, rows: rows, primaryTitle: primaryTitle,
                  primaryIdentifier: primaryIdentifier, canSave: canSave, startsSelected: startsSelected, primaryAboveKeypad: primaryAboveKeypad, cancel: cancel,
                  save: save) { EmptyView() }
    }
}

/// 分类格：图标在上、字在下。三态：普通 / 描边（建议，只提示不选中）/ 选中。
struct IconGridCell: View {
    enum Mode: Equatable { case normal, outlined, selected }
    let title: String
    let symbol: String
    var mode: Mode = .normal
    var identifier = ""
    var hintValue = "建议"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: YubaiSpace.space2) {
                Image(systemName: symbol).font(.system(size: 17)).frame(height: YubaiSize.headerIcon).accessibilityHidden(true)
                Text(title).yubaiFont(YubaiFont.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(mode == .selected ? YubaiColor.onBrand : YubaiColor.label)
                .padding(.vertical, YubaiSpace.space8).padding(.horizontal, YubaiSpace.space4)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin + YubaiSpace.space8)
                .background(mode == .selected ? YubaiColor.brand : YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                .overlay {
                    if mode == .outlined {
                        RoundedRectangle(cornerRadius: YubaiRadius.control).strokeBorder(YubaiColor.brand, lineWidth: 1.5)
                    }
                }.contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(title)
            .accessibilityValue(mode == .outlined ? hintValue : "")
            .accessibilityAddTraits(mode == .selected ? .isSelected : [])
            .accessibilityIdentifier(identifier)
    }
}

/// 整行等宽的分段；短选项保持横排，每项可点区域至少 44pt。
struct Segmented<Value: Hashable>: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Namespace private var selectionNamespace
    let choices: [(Value, String)]
    @Binding var selection: Value
    var identifier: ((Value) -> String)? = nil
    var background = YubaiColor.card
    var body: some View {
        let layout = textSize.isAccessibilitySize && choices.contains(where: { $0.1.count > 3 }) ? AnyLayout(VStackLayout(spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space4))
        layout {
            ForEach(choices.indices, id: \.self) { index in segment(choices[index].0, title: choices[index].1) }
        }.padding(YubaiSpace.space4)
            .background(background, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            .animation(YubaiMotion.control(reduceMotion: reduceMotion), value: selection)
    }
    private func segment(_ value: Value, title: String) -> some View {
        let on = selection == value
        return Button { selection = value } label: {
            Text(title).yubaiFont(YubaiFont.row, weight: on ? .semibold : .regular)
                .dynamicTypeSize(...(title.count <= 3 ? DynamicTypeSize.xxxLarge : .accessibility5)).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(on ? YubaiColor.label : YubaiColor.labelSecondary)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin)
                .background { if on { selectedSurface } }
                .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier(identifier?(value) ?? "")
    }
    @ViewBuilder private var selectedSurface: some View {
        if reduceMotion { RoundedRectangle(cornerRadius: YubaiRadius.control).fill(YubaiColor.raised) }
        else { RoundedRectangle(cornerRadius: YubaiRadius.control).fill(YubaiColor.raised).matchedGeometryEffect(id: "selection", in: selectionNamespace) }
    }
}

/// 细进度线（0…1）。首启清单、心愿单等待。
struct ProgressLine: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let value: Double
    var tint = YubaiColor.brand
    var track = YubaiColor.neutralSoft
    var height: CGFloat = YubaiSpace.space4
    private var clamped: Double { min(1, max(0, value)) }
    var body: some View {
        Capsule().fill(track).frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(tint).frame(width: proxy.size.width * clamped)
                }
            }
            .animation(YubaiMotion.progress(reduceMotion: reduceMotion), value: clamped)
            .accessibilityElement(children: .ignore).accessibilityValue("\(Int((clamped * 100).rounded()))%")
    }
}

struct ManualSheetHeader: View {
    @Environment(\.yubaiSheetSurface) private var inSheet
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    var actionTitle = "保存"
    var actionImage: String? = nil
    var primary = true
    var showsAction = true
    var enabled = true
    var cancelTitle = "取消"
    var actionIdentifier: String? = nil
    var cancelIdentifier = "cancelManualSheet"
    let cancel: () -> Void
    let action: () -> Void
    var subtitle: String? = nil
    var subtitleIdentifier = ""
    var subtitleAction: (() -> Void)? = nil
    var preservesCancelIdentifier = false
    private var titleView: some View {
        Group {
            if let subtitle, let subtitleAction {
                Button(action: subtitleAction) {
                    VStack(spacing: 2) {
                        titleText
                        HStack(spacing: 2) {
                            Text(subtitle).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.down").font(.system(size: 9))
                        }.yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.brandInk)
                    }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.accessibilityIdentifier(subtitleIdentifier)
            } else { titleText }
        }
    }
    private var titleText: some View {
        Text(title).yubaiFont(["记一笔", "改一笔", "改这笔"].contains(title) ? YubaiFont.entrySheetTitle : YubaiFont.navTitle).lineLimit(1)
    }
    private var cancelButton: some View {
        Button(action: cancel) {
            Text(cancelTitle).yubaiFont(YubaiFont.body).fixedSize()
                .padding(.horizontal, 16).frame(minHeight: 36).background(YubaiColor.card, in: Capsule())
                .frame(minHeight: 44).contentShape(Capsule())
        }.accessibilityIdentifier(!preservesCancelIdentifier && cancelIdentifier == "cancelManualSheet" && cancelTitle != "取消" ? "closeSheet" : cancelIdentifier)
    }
    @ViewBuilder private var actionButton: some View {
        if showsAction {
            Button(action: action) {
                HStack(spacing: 8) { if let actionImage { Image(systemName: actionImage) }; Text(actionTitle).fixedSize() }
                    .yubaiFont(YubaiFont.body, weight: primary ? .medium : .regular)
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .foregroundStyle(primary ? YubaiColor.onBrand : YubaiColor.label)
                    .background(primary ? YubaiColor.brand : YubaiColor.card, in: Capsule())
                    .yubaiHitTarget()
            }.disabled(!enabled).opacity(enabled ? 1 : 0.4)
                .accessibilityIdentifier(actionIdentifier ?? (actionTitle == "导入" ? "importFromEntry" : "saveManualSheet"))
        } else { Color.clear.frame(width: 64, height: 36).accessibilityHidden(true) }
    }
    var body: some View {
        Group {
            if textSize.isAccessibilitySize { stackedHeader }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        cancelButton.frame(width: 96, alignment: .leading)
                        titleView.frame(maxWidth: .infinity)
                        actionButton.frame(width: 96, alignment: .trailing)
                    }
                    stackedHeader
                }
            }
        }.frame(minHeight: 48).padding(.top, inSheet ? YubaiSpace.sheetHeaderTop : 0).buttonStyle(PressButtonStyle())
            .background(YubaiColor.canvas)
            .overlay(alignment: .bottom) { PageFade(edge: .top).offset(y: 24) }
    }
    private var stackedHeader: some View {
        VStack(spacing: 4) {
            titleView
            ViewThatFits(in: .horizontal) {
                HStack { cancelButton; Spacer(); actionButton }
                VStack(spacing: 8) { cancelButton; actionButton }
            }
        }
    }
}

/// The native field's AX frame must include the same transparent space that
/// focuses the field. A SwiftUI frame alone leaves a 20pt UIKit text-field node.
private struct MinimumInputTarget: ViewModifier {
    let identifier: String
    let focus: FocusState<Bool>.Binding
    @State private var bounds = CGRect.zero
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin)
            .contentShape(Rectangle()).onTapGesture { focus.wrappedValue = true }
            .contentViewportTarget()
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bounds = $0 }
            #if os(iOS)
            .background { NativeInputTarget(identifier: identifier, bounds: bounds).allowsHitTesting(false) }
            #endif
    }
}

private extension View {
    func minimumInputTarget(identifier: String, focus: FocusState<Bool>.Binding) -> some View {
        modifier(MinimumInputTarget(identifier: identifier, focus: focus))
    }
}

#if os(iOS)
private struct NativeInputTarget: UIViewRepresentable {
    let identifier: String
    let bounds: CGRect
    func makeUIView(context: Context) -> Anchor { Anchor(frame: .zero) }
    func updateUIView(_ view: Anchor, context: Context) {
        view.identifier = identifier
        // Also update when a scroll changes the field's screen coordinates.
        view.setNeedsLayout()
        DispatchQueue.main.async { view.install() }
    }
    final class Anchor: UIView {
        var identifier = ""
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false; accessibilityElementsHidden = true
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() { super.layoutSubviews(); install() }
        override func didMoveToWindow() { super.didMoveToWindow(); install() }
        func install() {
            guard window != nil, bounds.height >= YubaiSize.tapMin else { return }
            func inputs(in view: UIView) -> [UIView] {
                if view is UITextField || view is UITextView { return [view] }
                return view.subviews.flatMap { inputs(in: $0) }
            }
            var parent = superview
            for _ in 0..<8 {
                guard let host = parent else { return }
                let fields = inputs(in: host)
                if let field = fields.first(where: { $0.accessibilityIdentifier == identifier }) ?? (fields.count == 1 ? fields.first : nil) {
                    field.accessibilityIdentifier = identifier
                    field.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(self.bounds, in: self)
                    return
                }
                if fields.count > 1 { return }
                parent = host.superview
            }
        }
    }
}
#endif

/// The single form input: card row, fixed label column, focus and inline errors.
struct CardTextFieldRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    @Binding var text: String
    var placeholder = ""
    var identifier = ""
    var multiline = false
    var numeric = false
    var hidesValue = false
    var leading: AnyView? = nil
    var trailing: AnyView? = nil
    var focus: FocusState<Bool>.Binding? = nil
    var autofocus = false
    var error: String? = nil
    var submit: (() -> Void)? = nil
    @FocusState private var localFocus: Bool
    private var fieldFocus: FocusState<Bool>.Binding { focus ?? $localFocus }
    private var stacks: Bool { multiline || textSize.isAccessibilitySize }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            let layout = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space2))
            layout {
                if !title.isEmpty {
                    Text(title).yubaiFont(YubaiFont.body)
                        .foregroundStyle(error != nil ? YubaiColor.amberInk : fieldFocus.wrappedValue ? YubaiColor.brandInk : YubaiColor.label)
                        .frame(width: stacks ? nil : YubaiSize.fieldLabel, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: YubaiSpace.space8) {
                    if let leading { leading }
                    input.textFieldStyle(.plain).yubaiFont(YubaiFont.fieldValue)
                        .focused(fieldFocus).submitLabel(.done)
                        .onSubmit { submit?(); fieldFocus.wrappedValue = false }
                        .accessibilityLabel(title.isEmpty ? placeholder : title).accessibilityIdentifier(identifier)
                        .minimumInputTarget(identifier: identifier, focus: fieldFocus)
                    if let trailing { trailing }
                }
            }.frame(minHeight: YubaiSize.buttonHeight)
            if let error { InlineFieldError(message: error) }
        }.padding(.vertical, stacks ? YubaiSpace.space8 : YubaiSpace.none)
            .task { if autofocus { fieldFocus.wrappedValue = true } }
    }
    @ViewBuilder private var input: some View {
        if hidesValue {
            SecureField(placeholder, text: $text).autocorrectionDisabled().privacySensitive()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        else if numeric { TextField(placeholder, text: $text).numericInput() }
        else { TextField(placeholder, text: $text, axis: multiline ? .vertical : .horizontal).lineLimit(multiline ? 1...6 : 1...1) }
    }
}

/// Search has its own rounded surface; it is not a labeled form row.
struct SearchInput: View {
    @Binding var text: String
    var placeholder = "搜索"
    var identifier = ""
    var label = "搜索"
    var focus: FocusState<Bool>.Binding? = nil
    var showsCancel = false
    var cancelIdentifier = ""
    var cancel: () -> Void = {}
    @FocusState private var localFocus: Bool
    private var fieldFocus: FocusState<Bool>.Binding { focus ?? $localFocus }
    var body: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            HStack(spacing: YubaiSpace.space8) {
                Image(systemName: "magnifyingglass").foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                TextField(placeholder, text: $text).textFieldStyle(.plain).yubaiFont(YubaiFont.fieldValue)
                    .focused(fieldFocus).submitLabel(.search).accessibilityLabel(label).accessibilityIdentifier(identifier)
                    .minimumInputTarget(identifier: identifier, focus: fieldFocus)
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(YubaiColor.labelMuted).yubaiHitTarget() }
                        .accessibilityLabel("清空搜索").accessibilityIdentifier(identifier + "Clear")
                }
            }.padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.buttonHeight)
                .background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                .overlay { if fieldFocus.wrappedValue { RoundedRectangle(cornerRadius: YubaiRadius.control).strokeBorder(YubaiColor.brand, lineWidth: YubaiSize.lineWidth) } }
            if showsCancel {
                Button("取消") { fieldFocus.wrappedValue = false; cancel() }.yubaiFont(YubaiFont.body).fixedSize().yubaiHitTarget()
                    .accessibilityIdentifier(cancelIdentifier)
            }
        }.buttonStyle(PressButtonStyle())
    }
}

/// A row icon describes its category; an unknown category is a neutral dot.
struct LedgerCategoryIcon: View {
    @Environment(AppStore.self) private var store
    let category: String
    var pending = false
    var income: Bool? = nil
    var body: some View {
        Group {
            if pending { Circle().fill(YubaiColor.labelSecondary).frame(width: 6, height: 6) }
            else {
                let name = category.components(separatedBy: " · ").first ?? category
                Image(systemName: store.current.categories.first { $0.name == name && (income == nil || $0.income == income) }?.symbol ?? "square.grid.2x2")
                    .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
            }
        }.accessibilityHidden(true)
    }
}

struct EntryFormRow<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(title).yubaiFont(YubaiFont.body).fixedSize()
                Spacer(minLength: YubaiSpace.none)
                content.fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.body).fixedSize()
                content.frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(.vertical, 8)
        }.frame(minHeight: YubaiSize.rowSingle).yubaiFont(YubaiFont.body)
    }
}

struct EntryFormDivider: View {
    var body: some View { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
}


/// Shared by quick entry, entry editing and fixed-flow amounts.
struct AmountKeypad: View {
    @Binding var keypad: EntryKeypad
    @Binding var amountSelected: Bool
    let canSave: Bool
    let primaryTitle: String
    let primaryIdentifier: String
    let save: () -> Void
    var showsPrimary = true
    var embedded = false
    var receiptVisible = false
    var receiptDeadline: Date? = nil
    var interaction: () -> Void = {}
    @StateObject private var feedback = AmountKeypadFeedback()
    // The keys never grow with Dynamic Type; the amount above them is what scales.
    private let keyHeight: CGFloat = 48
    private let rows = [["1", "2", "3", "⌫"], ["4", "5", "6", "+"], ["7", "8", "9", "−"]]

    init(keypad: Binding<EntryKeypad>, amountSelected: Binding<Bool> = .constant(false), canSave: Bool,
         primaryTitle: String, primaryIdentifier: String, save: @escaping () -> Void, embedded: Bool = false, showsPrimary: Bool = true,
         receiptVisible: Bool = false, receiptDeadline: Date? = nil, interaction: @escaping () -> Void = {}) {
        _keypad = keypad; _amountSelected = amountSelected; self.canSave = canSave
        self.primaryTitle = primaryTitle; self.primaryIdentifier = primaryIdentifier; self.save = save; self.embedded = embedded; self.showsPrimary = showsPrimary
        self.receiptVisible = receiptVisible; self.receiptDeadline = receiptDeadline; self.interaction = interaction
    }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let keyWidth = max(0, (geometry.size.width - 18) / 4)
                VStack(spacing: 6) {
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: 6) { ForEach(rows[row], id: \.self) { key in
                            AmountKeypadKey(key: key, keypad: $keypad, amountSelected: $amountSelected, feedback: feedback, height: keyHeight, interaction: interaction)
                                .frame(width: keyWidth)
                        } }
                    }
                    HStack(spacing: 6) {
                        AmountKeypadKey(key: ".", keypad: $keypad, amountSelected: $amountSelected, feedback: feedback, height: keyHeight, interaction: interaction)
                            .frame(width: keyWidth)
                        AmountKeypadKey(key: "0", keypad: $keypad, amountSelected: $amountSelected, feedback: feedback, height: keyHeight, interaction: interaction)
                            .frame(width: showsPrimary ? keyWidth : keyWidth * 3 + 12)
                        if showsPrimary {
                        if receiptVisible {
                            EntrySaveReceipt(deadline: receiptDeadline).frame(width: keyWidth * 2 + 6, height: keyHeight)
                        } else { Button(action: save) {
                            Text(primaryTitle).yubaiFont(YubaiFont.keypadAction)
                                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center).frame(maxWidth: .infinity).frame(minHeight: keyHeight)
                        }.buttonStyle(AmountKeyButtonStyle(primary: true, pressing: { if $0 { feedback.press("记下", accepted: true) } }))
                            .frame(width: keyWidth * 2 + 6).opacity(canSave ? 1 : 0.4).disabled(!canSave)
                            .accessibilityIdentifier(primaryIdentifier)
                        }
                        }
                    }
                }
            }.frame(height: keyHeight * 4 + 6 * 3)
        }.padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 8)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .background {
                if !embedded {
                    UnevenRoundedRectangle(topLeadingRadius: YubaiRadius.card, topTrailingRadius: YubaiRadius.card)
                        .fill(YubaiColor.keypadTray).ignoresSafeArea(edges: .bottom)
                }
            }
            .accessibilityElement(children: .contain).accessibilityLabel("数字键盘")
            .onAppear { feedback.prepare() }
    }
}

private struct AmountKeypadKey: View {
    let key: String
    @Binding var keypad: EntryKeypad
    @Binding var amountSelected: Bool
    let feedback: AmountKeypadFeedback
    var height: CGFloat = 52
    var interaction: () -> Void = {}
    @State private var holdTask: Task<Void, Never>?
    @State private var deletedOnTouch = false
    private var selected: Bool { keypad.pendingOperator == key }
    var body: some View {
        Button {
            interaction()
            if deletedOnTouch { deletedOnTouch = false; return }
            keypad.press(key, replacingAmount: amountSelected); amountSelected = false
        } label: {
            Group {
                if key == "⌫" { Image(systemName: "delete.left") }
                else { Text(key) }
            }.yubaiFont(YubaiFont.amountAccount, weight: .regular)
                .frame(maxWidth: .infinity).frame(height: height)
        }.buttonStyle(AmountKeyButtonStyle(function: ["⌫", "+", "−"].contains(key), selected: selected, pressing: pressChanged))
            .accessibilityLabel(key == "⌫" ? "删除一位" : key == "+" ? "加" : key == "−" ? "减" : key == "." ? "小数点" : key)
            .accessibilityIdentifier("keypad_" + key).accessibilityAddTraits(selected ? .isSelected : [])
            .onDisappear { holdTask?.cancel() }
    }
    private func pressChanged(_ pressed: Bool) {
        holdTask?.cancel()
        guard pressed else { DispatchQueue.main.async { deletedOnTouch = false }; return }
        interaction()
        deletedOnTouch = false
        var next = keypad; next.press(key, replacingAmount: amountSelected)
        feedback.press(key, accepted: next != keypad)
        guard key == "⌫" else { return }
        deletedOnTouch = true; keypad = next; amountSelected = false
        guard keypad.expression != "0" else { return }
        holdTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            var count = 0
            while !Task.isCancelled {
                keypad.press("⌫"); feedback.deletion(); count += 1
                if keypad.expression == "0" { break }
                do { try await Task.sleep(for: .milliseconds(max(45, 150 - count * 15))) } catch { return }
            }
        }
    }
}

private struct AmountKeyButtonStyle: ButtonStyle {
    var primary = false
    var secondary = false
    var function = false
    var selected = false
    var pressing: (Bool) -> Void = { _ in }
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill = primary ? (pressed ? YubaiColor.brandInk : YubaiColor.brand)
            : pressed ? (function ? YubaiColor.keyFnPressed : YubaiColor.keyPressed)
            : selected ? YubaiColor.brandTint : (function ? YubaiColor.keyFn : YubaiColor.key)
        return configuration.label
            .foregroundStyle(primary ? YubaiColor.onBrand : (selected || secondary) ? YubaiColor.brandInk : YubaiColor.label)
            .background(fill, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: YubaiRadius.control).strokeBorder(YubaiColor.brand, lineWidth: 1.5) }
            }
            .shadow(color: primary || selected || pressed ? .clear : YubaiColor.shadowKey, radius: 0, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
            .contentViewportTarget()
            .animation(pressed ? nil : .easeOut(duration: YubaiMotion.durationQuick), value: pressed)
            .onChange(of: pressed) { _, value in pressing(value) }
    }
}

@MainActor private final class AmountKeypadFeedback: ObservableObject {
    #if os(iOS)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let completion = UINotificationFeedbackGenerator()
    #endif
    func prepare() {
        #if os(iOS)
        light.prepare(); medium.prepare(); rigid.prepare(); completion.prepare()
        #endif
    }
    func press(_ key: String, accepted: Bool) {
        #if os(iOS)
        if !accepted { rigid.impactOccurred(intensity: 0.5); rigid.prepare() }
        else if key == "+" || key == "−" { medium.impactOccurred(); medium.prepare() }
        else { light.impactOccurred(); light.prepare() }
        #endif
    }
    func success() {
        #if os(iOS)
        completion.notificationOccurred(.success); completion.prepare()
        #endif
    }
    func deletion() {
        #if os(iOS)
        light.impactOccurred(); light.prepare()
        #endif
    }
}

/// A single button keeps the entire amount accessible and avoids decimalPad.
struct EditableAmountDisplay: View {
    let amount: String
    let keypad: EntryKeypad
    let presented: Bool
    let selected: Bool
    let identifier: String
    let open: () -> Void
    var hide = false
    var ink: Color? = nil
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: YubaiSpace.none) {
                if presented && !hide, let expression = keypad.expressionText {
                    Text(expression).yubaiFont(YubaiFont.amount).foregroundStyle(YubaiColor.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("entryKeypadExpression")
                }
                amountLine
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).contentViewportTarget().foregroundStyle(YubaiColor.label)
            .accessibilityLabel("金额").accessibilityValue(hide ? "金额已隐藏" : presented ? keypad.groupedResultText : EntryKeypad(amount: (try? Money.parse(amount)) ?? 0).groupedResultText)
            .accessibilityIdentifier(identifier)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: AmountEditorFrame.self, value: proxy.frame(in: .named("amountEditor")))
                }
            }
    }
    private var amountLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
            Text(hide ? "••••" : presented ? keypad.groupedResultText : ((try? Money.parse(amount)).map { EntryKeypad(amount: $0).groupedResultText } ?? "0.00"))
                .yubaiFont(YubaiFont.entryAmount).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                .foregroundStyle(ink ?? YubaiColor.label)
                .padding(.horizontal, YubaiSpace.space4)

            if presented && !hide { EntryAmountCursor() }
            Spacer(minLength: YubaiSpace.none)
        }.frame(minHeight: YubaiSize.rowDouble)
    }
}

private struct AmountEditorFrame: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct AmountEditorOutsideTap: ViewModifier {
    let presented: Bool
    let finish: () -> Void
    @State private var amountFrame = CGRect.zero
    func body(content: Content) -> some View {
        content.contentShape(Rectangle()).coordinateSpace(name: "amountEditor")
            .onPreferenceChange(AmountEditorFrame.self) { amountFrame = $0 }
            .simultaneousGesture(SpatialTapGesture().onEnded { event in
                if presented && !amountFrame.contains(event.location) { finish() }
            })
    }
}

extension View {
    func finishAmountOnOutsideTap(presented: Bool, finish: @escaping () -> Void) -> some View {
        modifier(AmountEditorOutsideTap(presented: presented, finish: finish))
    }
}

struct EntryRepeatChip: View {
    var selected: Bool
    var value: String
    var opensPlan = false
    var inTray = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(value + (opensPlan ? " ›" : "")).yubaiFont(YubaiFont.callout, weight: selected ? .medium : .regular)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: inTray ? 34 : YubaiSize.chipHeight)
                .background(inTray ? YubaiColor.keyFn : selected ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entryRepeat")
            .accessibilityLabel("重复").accessibilityValue(value).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The four entry surfaces use this form; their state and commit operations stay with their owners.
struct EntryForm<Content: View>: View {
    let title: String
    var actionTitle = "好"
    var actionImage: String? = nil
    var primary = true
    var showsAction = true
    var enabled = true
    var actionIdentifier: String? = nil
    var scrollIdentifier = "entryFormScroll"
    var cancelTitle = "取消"
    var cancelIdentifier = "cancelManualSheet"
    let cancel: () -> Void
    let save: () -> Void
    var headerSubtitle: String? = nil
    var subtitleAction: (() -> Void)? = nil
    var compactHeader = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            ManualSheetHeader(title: title, actionTitle: actionTitle, actionImage: actionImage, primary: primary,
                              showsAction: showsAction, enabled: enabled, cancelTitle: cancelTitle, actionIdentifier: actionIdentifier,
                              cancelIdentifier: cancelIdentifier, cancel: cancel, action: save,
                              subtitle: headerSubtitle, subtitleIdentifier: "entrySessionSummary", subtitleAction: subtitleAction,
                              preservesCancelIdentifier: headerSubtitle != nil)
                .dynamicTypeSize(...(compactHeader ? DynamicTypeSize.xxxLarge : .accessibility5))
                .padding(.horizontal, YubaiSpace.insetPage)
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup, content: content)
                    .padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup).padding(.bottom, compactHeader ? 0 : YubaiSpace.gapSection)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.modifier(ScrollContentViewport()).scrollDismissesKeyboard(.interactively).accessibilityElement(children: .contain).accessibilityIdentifier(scrollIdentifier)
        }.accessibilityElement(children: .contain)
    }
}

struct EntryDateRow: View {
    @Binding var date: Date
    var showsTime = false
    private var today: Date { Date() }
    private func choose(_ day: Date) {
        let c = Dates.calendar
        date = c.date(bySettingHour: c.component(.hour, from: date), minute: c.component(.minute, from: date), second: c.component(.second, from: date), of: day)!
    }
    var body: some View {
        EntryFormRow(title: showsTime ? "时间" : "日期") {
            EntryChipLayout(spacing: 6, rowSpacing: 6) {
                dayChip("今天", day: today)
                dayChip("昨天", day: Dates.addDays(-1, to: today))
                EntryDateChip(date: $date, iconOnly: true)
                if showsTime { EntryDateChip(date: $date, time: true) }
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: 300, alignment: .trailing)
        }
    }
    private func dayChip(_ title: String, day: Date) -> some View {
        let selected = Dates.calendar.isDate(date, inSameDayAs: day)
        return Button { choose(day) } label: {
            Text(title).fixedSize().yubaiFont(YubaiFont.callout)
                .padding(.horizontal, 12).frame(height: 32)
                .background(selected ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }.yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EntryAmountCursor: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @State private var visible = true
    var body: some View {
        Rectangle().fill(YubaiColor.brand).frame(width: 2, height: 34)
            .opacity(visible || reduceMotion ? 1 : 0).accessibilityHidden(true)
            .task(id: reduceMotion) {
                visible = true; guard !reduceMotion else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    visible.toggle()
                }
            }
    }
}


struct InlineFieldError: View {
    let message: String?
    var body: some View {
        if let message {
            Text(message).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
                .padding(.leading, 16).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("inlineFieldError")
        }
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.fixedSize(horizontal: false, vertical: true).yubaiFont(YubaiFont.destructiveAction)
            .foregroundStyle(YubaiColor.amberInk).frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? YubaiColor.keyPressed : YubaiColor.card, in: Capsule())
            .contentShape(Capsule()).contentViewportTarget()
    }
}


/// Shared text field and send styling; callers supply screenshot and voice controls.
struct ChatInputBar<Leading: View, Accessory: View>: View {
    @Binding var text: String
    var placeholder: String
    var accessibilityLabel: String
    var inputID: String
    var sendID: String
    var enabled = true
    var busy = false
    var showSend = true
    var focus: FocusState<Bool>.Binding? = nil
    var send: () -> Void
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var accessory: () -> Accessory
    @FocusState private var localFocus: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: YubaiSpace.space8) {
            leading().frame(height: YubaiSize.iconButton)
            HStack(spacing: YubaiSpace.none) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .focused(focus ?? $localFocus)
                    .lineLimit(1...5).yubaiFont(YubaiFont.navTitle, weight: .regular)
                    .padding(.vertical, YubaiSpace.gapGroup)
                    .accessibilityIdentifier(inputID).accessibilityLabel(accessibilityLabel)
                    .minimumInputTarget(identifier: inputID, focus: focus ?? $localFocus)
            }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                .onTapGesture { (focus ?? $localFocus).wrappedValue = true }
            accessory().frame(height: YubaiSize.iconButton)
            if showSend {
                Button(action: send) {
                    Image(systemName: "arrow.up").fontWeight(.semibold)
                        .frame(width: YubaiSize.iconButton, height: YubaiSize.iconButton)
                        .foregroundStyle(Color.white).background(YubaiColor.brand, in: Circle())
                        .yubaiHitTarget()
                }.accessibilityLabel("发送").accessibilityIdentifier(sendID)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.disabled(!enabled || busy).padding(YubaiSpace.space8).frame(minHeight: YubaiSize.buttonHeight)
            .fixedSize(horizontal: false, vertical: true)
            .buttonStyle(PressButtonStyle()).floatingSurface(in: Capsule(), shadow: YubaiShadow.input)
            .opacity(enabled ? 1 : 0.6)
    }
}


private struct EntrySaveReceipt: View {
    let deadline: Date?
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: deadline == nil)) { context in
            Label("已记下", systemImage: "checkmark").yubaiFont(YubaiFont.keypadAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(YubaiColor.brandInk)
                .background {
                    GeometryReader { proxy in
                        YubaiColor.brandTint
                            .overlay(alignment: .leading) {
                                YubaiColor.brand.opacity(0.22)
                                    .frame(width: proxy.size.width * ContinuousEntrySession.receiptFraction(deadline: deadline, at: context.date))
                            }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: YubaiRadius.control))
        }.accessibilityElement(children: .ignore).accessibilityLabel("已记下")
            .accessibilityIdentifier("entrySavedReceipt")
    }
}


/// 月历：今天描边，未来日期变灰但仍可选；拆分可传入原差额的日期范围。
struct EntryCalendarView: View {
    @Binding var selection: Date
    let today: Date
    var bounds: ClosedRange<Date>? = nil
    var identifier = "entryCalendar"
    var customHeader: ((Binding<Date>) -> AnyView)? = nil
    @State private var month: Date
    @ScaledMetric(relativeTo: .callout) private var dayWidth = YubaiSize.tapMin

    init(selection: Binding<Date>, today: Date, bounds: ClosedRange<Date>? = nil, identifier: String = "entryCalendar",
         customHeader: ((Binding<Date>) -> AnyView)? = nil) {
        _selection = selection; self.today = today; self.bounds = bounds; self.identifier = identifier
        self.customHeader = customHeader
        _month = State(initialValue: Dates.calendar.dateInterval(of: .month, for: selection.wrappedValue)!.start)
    }
    private var monthTitle: String {
        "\(Dates.calendar.component(.year, from: month))年\(Dates.calendar.component(.month, from: month))月"
    }
    private var leading: Int { (Dates.calendar.component(.weekday, from: month) + 5) % 7 }
    private var count: Int { Dates.calendar.range(of: .day, in: .month, for: month)?.count ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            if let customHeader { customHeader($month) } else { monthHeader }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(dayWidth), spacing: YubaiSpace.space4), count: 7), spacing: YubaiSpace.space4) {
                    ForEach(Array(["一", "二", "三", "四", "五", "六", "日"].enumerated()), id: \.offset) { _, day in
                        Text(day).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).frame(width: dayWidth).frame(minHeight: YubaiSize.tapMin)
                    }
                    ForEach(0..<(leading + count), id: \.self) { index in
                        if index < leading { Color.clear.frame(width: dayWidth, height: dayWidth).accessibilityHidden(true) }
                        else { dayButton(Dates.addDays(index - leading, to: month)) }
                    }
                }.frame(minWidth: dayWidth * 7 + YubaiSpace.space4 * 6)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
    private var monthHeader: some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(monthTitle).yubaiFont(YubaiFont.rowTitle, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: YubaiSpace.space8)
            monthButton(-1, symbol: "chevron.left", label: "上个月")
            monthButton(1, symbol: "chevron.right", label: "下个月")
        }
    }
    private func monthButton(_ offset: Int, symbol: String, label: String) -> some View {
        Button { month = Dates.addMonths(offset, to: month) } label: {
            Image(systemName: symbol).yubaiFont(YubaiFont.callout)
                .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(label)
            .accessibilityIdentifier(identifier + (offset < 0 ? "Previous" : "Next"))
    }
    private func dayButton(_ day: Date) -> some View {
        let selected = Dates.calendar.isDate(day, inSameDayAs: selection)
        let current = Dates.calendar.isDate(day, inSameDayAs: today)
        let future = day > Dates.day(today)
        let allowed = bounds.map { day >= Dates.day($0.lowerBound) && day <= Dates.day($0.upperBound) } ?? true
        return Button { choose(day) } label: {
            Text("\(Dates.calendar.component(.day, from: day))").yubaiFont(YubaiFont.row)
                .foregroundStyle(selected ? YubaiColor.canvas : future || !allowed ? YubaiColor.labelSecondary : YubaiColor.label)
                .frame(width: dayWidth, height: dayWidth)
                .background { if selected { Circle().fill(YubaiColor.label) } }
                .overlay { if current { Circle().strokeBorder(YubaiColor.brand, lineWidth: YubaiSize.lineWidth) } }
                .contentShape(Circle())
        }.buttonStyle(PressButtonStyle()).disabled(!allowed).opacity(allowed ? 1 : 0.4)
            .accessibilityLabel(FixedFlowPresentation.monthDay(day)).accessibilityValue(future ? "未来" : "")
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(identifier + "Day_" + Dates.text(day))
    }
    private func choose(_ day: Date) {
        let calendar = Dates.calendar
        selection = calendar.date(bySettingHour: calendar.component(.hour, from: selection), minute: calendar.component(.minute, from: selection),
                                  second: calendar.component(.second, from: selection), of: day) ?? day
    }
}

/// Monetary form values use the shared large readout and keypad, in the current
/// card. Expanding a row never presents a second sheet above an editor.
private struct MoneyInputFocusKey: EnvironmentKey {
    static let defaultValue = MoneyInputFocus()
}
@Observable private final class MoneyInputFocus { var active: UUID? }
private extension EnvironmentValues {
    var moneyInputFocus: MoneyInputFocus {
        get { self[MoneyInputFocusKey.self] }
        set { self[MoneyInputFocusKey.self] = newValue }
    }
}

struct MoneyInputRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.moneyInputFocus) private var inputFocus
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    @Binding var text: String
    var identifier = ""
    var currencySymbol = "¥"
    var allowNegative = false
    var trailing: AnyView? = nil
    var leadingLabel: AnyView? = nil
    @State private var identity = UUID()
    @State private var keypad = EntryKeypad()
    @State private var selected = true
    private var value: Int64 { (try? Money.parse(text, allowNegative: allowNegative)) ?? 0 }
    private var editing: Bool { inputFocus.active == identity }
    private var hidden: Bool { store.preferences.hideAmounts && !editing }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            valueRow
            if editing {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text(currencySymbol).yubaiFont(YubaiFont.amountAccount)
                    Text(keypad.groupedResultText).yubaiFont(YubaiFont.entryAmount).fixedSize(horizontal: false, vertical: true)
                    EntryAmountCursor()
                }.accessibilityIdentifier(identifier + "Amount")
                AmountKeypad(keypad: $keypad, amountSelected: $selected,
                             canSave: keypad.amount != nil && (allowNegative || (keypad.amount ?? -1) >= 0),
                             primaryTitle: "好", primaryIdentifier: identifier + "Done", save: { inputFocus.active = nil }, embedded: true)
            }
        }.onChange(of: keypad) { _, value in
            if editing, let amount = value.amount, allowNegative || amount >= 0 { text = Money.input(amount) }
        }.onDisappear { if editing { inputFocus.active = nil } }
    }
    @ViewBuilder private var valueRow: some View {
        if let leadingLabel {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
            layout {
                leadingLabel.frame(maxWidth: .infinity, alignment: .leading)
                valueButton
            }.frame(minHeight: YubaiSize.rowDouble)
        } else { EntryFormRow(title: title) { valueButton } }
    }
    private var valueButton: some View {
        HStack(spacing: YubaiSpace.space8) {
            Button(action: activate) {
                Text(hidden ? "••••" : currencySymbol + " " + AmountLabel.text(value)).yubaiFont(YubaiFont.amount)
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(1).frame(minHeight: YubaiSize.tapMin)
                    .contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier)
                .accessibilityLabel(title.isEmpty ? "金额" : title).accessibilityValue(hidden ? "金额已隐藏" : AmountLabel.text(value))
            if let trailing { trailing }
        }
    }
    private func activate() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        keypad = EntryKeypad(amount: value); selected = true
        inputFocus.active = editing ? nil : identity
    }
}

/// All confirmation sheets use the same content-sized surface and amber action.
struct ConfirmationSheet<Actions: View>: View {
    @Environment(\.dismiss) private var dismiss
    @State private var measuredHeight: CGFloat = 300
    let title: String
    var consequence: String? = nil
    var cancelIdentifier = "cancelConfirmation"
    @ViewBuilder let actions: Actions
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text(title).yubaiFont(YubaiFont.navTitle).fixedSize(horizontal: false, vertical: true)
                if let consequence { Text(consequence).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelSecondary) }
                actions
                Button("取消") { dismiss() }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier(cancelIdentifier)
            }.fixedSize(horizontal: false, vertical: true).padding(YubaiSpace.insetPage).padding(.top, YubaiSpace.sheetHeaderTop)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { measuredHeight = $0 } }
        }.scrollBounceBehavior(.basedOnSize).modifier(ScrollContentViewport())
            .yubaiSheetBackground().presentationDetents([.height(measuredHeight), .large]).presentationDragIndicator(.visible)
    }
}

struct SettingsRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    var detail: String? = nil
    var chevron = true
    var body: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
            layout {
                Text(title).yubaiFont(YubaiFont.body).fixedSize(horizontal: false, vertical: true)
                if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
                if let detail { Text(detail).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if chevron { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true) }
        }.frame(minHeight: YubaiSize.buttonHeight).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

struct EntryDateChip: View {
    @Binding var date: Date
    var time = false
    var iconOnly = false
    var inTray = false
    var allowsFuture = true
    var identifier = ""
    @State private var picking = false
    @State private var latestDate = Date()
    var body: some View {
        Button { latestDate = Date(); picking = true } label: {
            Group {
                if iconOnly { Image(systemName: "calendar").frame(width: YubaiSize.headerIcon) }
                else if inTray && !time { Label(ManualBookkeeping.dayLabel(date), systemImage: "calendar").fixedSize() }
                else { Text(time ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ManualBookkeeping.dayLabel(date)).fixedSize() }
            }
                .yubaiFont(time ? YubaiFont.amountSmall : YubaiFont.callout)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: inTray ? YubaiSize.trayChip : YubaiSize.chipHeight).background(inTray ? YubaiColor.keyFn : YubaiColor.raised, in: Capsule())
                .yubaiHitTarget()
        }.accessibilityLabel(iconOnly ? "选别的日子" : time ? "时间" : "日期").accessibilityValue(time ? date.formatted(.dateTime.hour().minute()) : ManualBookkeeping.dayLabel(date))
            .accessibilityIdentifier(identifier.isEmpty ? (time ? "entryTimeChip" : "entryDatePicker") : identifier).buttonStyle(PressButtonStyle()).sheet(isPresented: $picking) {
                ScrollView {
                    if time {
                        DatePicker("时间", selection: $date, in: Date.distantPast...(allowsFuture ? Date.distantFuture : latestDate), displayedComponents: .hourAndMinute)
                            .labelsHidden().accessibilityIdentifier("entryTimePicker")
                    } else {
                        EntryCalendarView(selection: $date, today: latestDate, bounds: allowsFuture ? nil : Date.distantPast...latestDate)
                    }
                }.padding(YubaiSpace.insetCard).transaction { $0.animation = nil }
                    .manualSheetHeader(time ? "时间" : "日期", actionTitle: "好", actionIdentifier: "entryDateDone", cancel: { picking = false }, action: { picking = false })
                    .yubaiSheetBackground().presentationDetents([.medium, .large])
            }
    }
}


/// A recurring day-of-month is a number from 1–31, independent of the current
/// month's length; actual dated occurrences use EntryCalendarView.
struct MonthDayChoices: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var selection: Int
    var identifier: String
    var choose: (Int) -> Void = { _ in }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: YubaiSpace.space8), count: textSize.isAccessibilitySize ? 4 : 7), spacing: YubaiSpace.space8) {
            ForEach(1...31, id: \.self) { value in
                Button { selection = value; choose(value) } label: {
                    Text("\(value)").yubaiFont(YubaiFont.callout).lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin)
                        .foregroundStyle(selection == value ? YubaiColor.onBrand : YubaiColor.label)
                        .background(selection == value ? YubaiColor.brand : YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("每月 \(value) 号")
                    .accessibilityAddTraits(selection == value ? .isSelected : []).accessibilityIdentifier(identifier + "\(value)")
            }
        }
    }
}

/// Chips wrap at their intrinsic width, including at accessibility text sizes.
struct EntryChipLayout: Layout {
    var spacing: CGFloat = YubaiSpace.space8
    var rowSpacing: CGFloat = YubaiSpace.gapGroup
    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (CGSize, [CGRect]) {
        var x: CGFloat = .zero; var y: CGFloat = .zero; var rowHeight: CGFloat = .zero; var frames: [CGRect] = []
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, ideal.width), height: nil))
            // 32pt chips in 44pt targets already contribute 12pt of visible space.
            let targetOutset = YubaiSize.tapMin - YubaiSize.chipHeight
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + max(YubaiSpace.none, rowSpacing - targetOutset); rowHeight = 0 }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width ?? 354).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(subviews, width: bounds.width).1
        for (index, view) in subviews.enumerated() {
            let frame = frames[index]
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}


private struct NativeRowsHeight: PreferenceKey {
    static let defaultValue: [AnyHashable: CGFloat] = [:]
    static func reduce(value: inout [AnyHashable: CGFloat], nextValue: () -> [AnyHashable: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
/// A self-sizing native List provides swipe actions inside an existing paper card.
struct NativeCardRows<Item: Identifiable, Row: View>: View where Item.ID: Hashable {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row
    @State private var heights: [AnyHashable: CGFloat] = [:]
    @ScaledMetric private var estimatedHeight: CGFloat = YubaiSize.rowEstimate
    init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) { self.items = items; self.row = row }
    var body: some View {
        List(items) { item in
            row(item).fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, YubaiSpace.space4)
                .background { GeometryReader { geometry in Color.clear.preference(key: NativeRowsHeight.self, value: [AnyHashable(item.id): geometry.size.height]) } }
                .listRowInsets(EdgeInsets(top: YubaiSpace.none, leading: YubaiSpace.space16, bottom: YubaiSpace.none, trailing: YubaiSpace.space16))
                .listRowBackground(YubaiColor.paperSheet).listRowSeparatorTint(YubaiColor.separator)
        }.listStyle(.plain).scrollContentBackground(.hidden).scrollDisabled(true)
            .frame(height: items.reduce(CGFloat(0)) { $0 + max(44, heights[AnyHashable($1.id)] ?? estimatedHeight) })
            .clipShape(RoundedRectangle(cornerRadius: YubaiRadius.card))
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
            .onPreferenceChange(NativeRowsHeight.self) { value in if value != heights { heights = value } }
    }
}

private struct ManualSheetTop: ViewModifier {
    @Environment(\.yubaiSheetSurface) private var inSheet
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    let enabled: Bool
    let primary: Bool
    let cancelTitle: String
    let showsAction: Bool
    let actionIdentifier: String?
    let cancelAction: (() -> Void)?
    let action: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if !inSheet && !showsAction { content }
        else { content.manualSheetNavigation().safeAreaInset(edge: .top, spacing: YubaiSpace.none) {
            ManualSheetHeader(title: title, actionTitle: actionTitle, primary: primary, showsAction: showsAction, enabled: enabled,
                              cancelTitle: cancelTitle, actionIdentifier: actionIdentifier,
                              cancel: { if let cancelAction { cancelAction() } else { dismiss() } }, action: action)
                .padding(.horizontal, YubaiSpace.insetPage)
        } }
    }
}
extension View {
    func manualSheetHeader(_ title: String, actionTitle: String = "好", primary: Bool = true, enabled: Bool = true, cancelTitle: String = "取消",
                           showsAction: Bool = true, actionIdentifier: String? = nil, cancel: (() -> Void)? = nil,
                           action: @escaping () -> Void = {}) -> some View {
        modifier(ManualSheetTop(title: title, actionTitle: actionTitle, enabled: enabled, primary: primary, cancelTitle: cancelTitle,
                                showsAction: showsAction, actionIdentifier: actionIdentifier, cancelAction: cancel, action: action))
    }
}


extension YubaiFont {
    static let partBalance = Style(size: YubaiFont.row.size, lineHeight: 20, weight: .semibold, family: .num, relativeTo: .footnote)
}

extension YubaiFont {
    static let butlerTitle = Style(size: YubaiFont.entrySheetTitle.size, lineHeight: 24, weight: .semibold, family: .sans, relativeTo: .headline)
}

// MARK: - Round 47 home paper and window

/// Existing bamboo silhouette, shared by the first wall and the daily receipt.
struct BrandBambooShadow: View {
    var opacity = 0.11
    var body: some View {
        Image("BambooShadow").renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(YubaiColor.bambooShadow).blur(radius: 5).opacity(opacity)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct FirstWindowWall: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                LinearGradient(colors: [YubaiColor.card, YubaiColor.keypadTray], startPoint: .topLeading, endPoint: .bottomTrailing)
                window(size)
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
                    let angle = reduceMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate / YubaiMotion.windowSwayPhase) * 2
                    BrandBambooShadow(opacity: scheme == .dark ? 0.14 : 0.20)
                        .frame(width: size.width * 1.02, height: size.height * 0.54)
                        .rotationEffect(.degrees(8 + angle), anchor: .bottomLeading)
                        .position(x: size.width * 0.27, y: size.height * 0.49)
                    BrandBambooShadow(opacity: 0.13)
                        .frame(width: size.width * 0.60, height: size.height * 0.35)
                        .scaleEffect(x: -1, y: 1).rotationEffect(.degrees(-18 - angle))
                        .position(x: size.width * 0.70, y: size.height * 0.27)
                }
            }.frame(width: size.width, height: size.height).clipped()
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
    private func window(_ size: CGSize) -> some View {
        let pane = Path { p in
            p.move(to: CGPoint(x: -30, y: size.height * 0.24))
            p.addLine(to: CGPoint(x: size.width * 0.77, y: size.height * 0.15))
            p.addLine(to: CGPoint(x: size.width * 0.77, y: size.height * 0.72))
            p.addLine(to: CGPoint(x: -30, y: size.height * 0.81)); p.closeSubpath()
        }
        return pane.fill(YubaiColor.windowLight.opacity(scheme == .dark ? 0.10 : 0.92))
            .overlay {
                Path { p in
                    for y in [0.43, 0.62] {
                        p.move(to: CGPoint(x: -30, y: size.height * y))
                        p.addLine(to: CGPoint(x: size.width * 0.80, y: size.height * (y - 0.09)))
                    }
                    p.move(to: CGPoint(x: size.width * 0.35, y: size.height * 0.16))
                    p.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.79))
                }.stroke(YubaiColor.keypadTray.opacity(0.9), lineWidth: 9).clipShape(pane)
            }.blur(radius: 1.4)
    }
}

struct ReceiptTornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: .zero); p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        let count = max(1, Int(rect.width / 6)), step = rect.width / CGFloat(count)
        for index in (0..<count).reversed() {
            p.addLine(to: CGPoint(x: CGFloat(index) * step + step / 2, y: rect.maxY))
            p.addLine(to: CGPoint(x: CGFloat(index) * step, y: 1))
        }
        p.closeSubpath(); return p
    }
}

struct ReceiptRule: View {
    var dotted = false
    var body: some View {
        GeometryReader { geometry in
            Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: geometry.size.width, y: 0)) }
                .stroke(YubaiColor.label.opacity(dotted ? 0.30 : 0.38), style: StrokeStyle(lineWidth: 1, dash: dotted ? [YubaiSize.separator, YubaiSpace.space2] : [YubaiSize.receiptLineDash, YubaiSpace.space4]))
        }.frame(height: 1).accessibilityHidden(true)
    }
}

/// A swipe is local to this row, so undo never restores an unrelated ledger snapshot.
struct ReceiptSwipeRow<Content: View>: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let enabled: Bool
    let identifier: String
    let undo: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var revealed = false
    var body: some View {
        ZStack(alignment: .trailing) {
            if revealed && enabled {
                Button(action: undo) {
                    Text("撤销").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(width: YubaiSize.receiptUndoWidth, height: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier)
            }
            content().background(YubaiColor.receiptPaper(for: scheme))
                .offset(x: revealed && enabled ? -YubaiSize.receiptUndoWidth : 0)
                #if os(iOS)
                .gesture(HorizontalPan(shouldBegin: { _ in enabled }, ended: { distance, _ in
                    withAnimation(YubaiMotion.control(reduceMotion: reduceMotion)) { revealed = distance < -20 }
                }))
                #else
                .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                    guard enabled, abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(YubaiMotion.control(reduceMotion: reduceMotion)) { revealed = value.translation.width < -20 }
                })
                #endif
        }.clipped().contentShape(Rectangle()).accessibilityActions { if enabled { Button("撤销这一笔", action: undo) } }
    }
}

private struct ReceiptPrint: ViewModifier {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let highlighted: Bool
    let trigger: Int
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion { content }
        else {
            content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { line, offset in
                line.offset(y: highlighted ? offset : 0).opacity(highlighted ? 1 - Double(offset) / 24 : 1)
            } keyframes: { _ in
                MoveKeyframe(CGFloat(12))
                SpringKeyframe(CGFloat.zero, duration: YubaiMotion.durationReceiptPrint, spring: YubaiMotion.livelySpring)
            }
        }
    }
}
extension View {
    func receiptPrint(highlighted: Bool, trigger: Int) -> some View {
        modifier(ReceiptPrint(highlighted: highlighted, trigger: trigger))
    }
}
