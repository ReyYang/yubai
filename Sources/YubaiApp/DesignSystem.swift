import SwiftUI
import Charts
import YubaiCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum YubaiColor {
    static let white = Color.white
    static let canvas = adaptive(0xf5f1e5, 0x1f1b14)
    static let card = adaptive(0xede6d3, 0x2a251c)
    static let raised = adaptive(0xfefbea, 0x353026)
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
    static let toggleOn = adaptive(0x817665, 0x8c806b)
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
    enum Family: Equatable { case num, serif, sans }
    struct Style {
        let size: CGFloat
        let lineHeight: CGFloat
        let weight: Font.Weight
        let family: Family
        var tracking: CGFloat = 0
        var relativeTo: Font.TextStyle = .body
        var design: Font.Design { switch family { case .num: .rounded; case .serif: .serif; case .sans: .default } }
    }
    static let amountHero = Style(size: 48, lineHeight: 54, weight: .semibold, family: .num, tracking: -2, relativeTo: .largeTitle)
    static let amountDisplay = Style(size: 44, lineHeight: 50, weight: .semibold, family: .num, tracking: -1.5, relativeTo: .largeTitle)
    static let amountInput = Style(size: 38, lineHeight: 46, weight: .semibold, family: .num, tracking: -1, relativeTo: .title)
    static let amountLarge = Style(size: 30, lineHeight: 36, weight: .semibold, family: .num, tracking: -0.5, relativeTo: .title)
    static let amount = Style(size: 15, lineHeight: 20, weight: .semibold, family: .num, tracking: 0, relativeTo: .body)
    static let amountSmall = Style(size: 13, lineHeight: 18, weight: .medium, family: .num, tracking: 0, relativeTo: .footnote)
    static let amountDay = Style(size: 18, lineHeight: 24, weight: .semibold, family: .num, tracking: -0.3, relativeTo: .headline)
    // Numeric sizes specified by the approved V3 summary tiles and donut.
    static let amountSummary = Style(size: 17, lineHeight: 24, weight: .semibold, family: .num, relativeTo: .headline)
    static let amountCard = Style(size: 20, lineHeight: 28, weight: .semibold, family: .num, relativeTo: .title3)
    static let amountDonut = Style(size: 22, lineHeight: 28, weight: .semibold, family: .num, relativeTo: .title2)
    static let amountAccount = Style(size: 24, lineHeight: 30, weight: .semibold, family: .num, relativeTo: .title2)
    static let chartValue = Style(size: 11, lineHeight: 14, weight: .medium, family: .num, tracking: 0, relativeTo: .caption2)
    static let welcome = Style(size: 40, lineHeight: 48, weight: .semibold, family: .serif, tracking: 0, relativeTo: .largeTitle)
    static let lead = Style(size: 22, lineHeight: 32, weight: .semibold, family: .serif, tracking: 0, relativeTo: .title2)
    static let quote = Style(size: 20, lineHeight: 30, weight: .semibold, family: .serif, tracking: 0, relativeTo: .title3)
    static let heroLabel = Style(size: 17, lineHeight: 24, weight: .semibold, family: .serif, tracking: 0, relativeTo: .headline)
    static let cardTitle = Style(size: 16, lineHeight: 22, weight: .semibold, family: .serif, tracking: 0, relativeTo: .headline)
    static let month = Style(size: 17, lineHeight: 24, weight: .semibold, family: .serif, tracking: 0, relativeTo: .headline)
    static let navTitle = Style(size: 15, lineHeight: 20, weight: .medium, family: .sans, tracking: 0, relativeTo: .headline)
    static let body = Style(size: 15, lineHeight: 22, weight: .regular, family: .sans, tracking: 0, relativeTo: .body)
    static let rowTitle = Style(size: 15, lineHeight: 20, weight: .medium, family: .sans, tracking: 0, relativeTo: .body)
    static let row = Style(size: 14, lineHeight: 20, weight: .regular, family: .sans, tracking: 0, relativeTo: .body)
    static let callout = Style(size: 13, lineHeight: 20, weight: .regular, family: .sans, tracking: 0, relativeTo: .callout)
    static let caption = Style(size: 12, lineHeight: 18, weight: .regular, family: .sans, tracking: 0, relativeTo: .caption)
    static let meta = Style(size: 11, lineHeight: 16, weight: .regular, family: .sans, tracking: 0, relativeTo: .caption2)
    static let chartLabel = Style(size: 10, lineHeight: 12, weight: .regular, family: .sans, tracking: 0, relativeTo: .caption2)
    static let tabLabel = Style(size: 10, lineHeight: 12, weight: .medium, family: .sans, tracking: 0, relativeTo: .caption2)
    static let tabIcon = Style(size: 20, lineHeight: 24, weight: .regular, family: .sans, relativeTo: .title3)
    static let addIcon = Style(size: 24, lineHeight: 28, weight: .semibold, family: .sans, relativeTo: .title2)
    static let button = Style(size: 15, lineHeight: 20, weight: .medium, family: .sans, tracking: 0, relativeTo: .headline)
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
            .contentShape(Rectangle())
    }

    /// Keeps the glyph on the page edge; the transparent target extends into the page margin.
    func yubaiPageArrowTarget(edge: HorizontalEdge) -> some View {
        frame(width: YubaiSize.pageArrowGlyph, height: YubaiSize.iconButton, alignment: edge == .leading ? .leading : .trailing)
            .yubaiHitTarget()
            .padding(edge == .leading ? .leading : .trailing, -YubaiSize.pageArrowOutset)
    }
}

enum YubaiSpace {
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

    static let insetPage = space20
    static let insetCard = space16
    static let gapSection = space24
    static let gapGroup = space12
    static let gapHeading = space8
    static let gapAction = space12
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
    static let tapMin: CGFloat = 44
    static let headerHeight: CGFloat = 48
    static let headerIcon: CGFloat = 22
    static let headerIconMax: CGFloat = 32
    static let iconButton: CGFloat = 40
    static let buttonHeight: CGFloat = 52
    static let chipHeight: CGFloat = 32
    static let rowSingle: CGFloat = 48
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
    static let floatingTabbarHeight = tabBarHeight
    static let floatingTabbarBottom: CGFloat = 8
    #endif
    static let barMax: CGFloat = 24
    static let lineWidth: CGFloat = 2
    static let marker: CGFloat = 8
    #if os(macOS)
    static let rootBottomPadding: CGFloat = 106
    #else
    static let rootBottomPadding: CGFloat = floatingTabbarHeight + floatingTabbarBottom + YubaiSpace.gapGroup
    #endif
}

enum YubaiShadow {
    struct Token {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    static let float = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 31.0 / 255, darkAlpha: 89.0 / 255), radius: 20, x: 0, y: 6)
    static let ask = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 46.0 / 255, darkAlpha: 89.0 / 255), radius: 20, x: 0, y: 6)
    static let input = Token(color: YubaiColor.adaptive(0x4a4030, 0x000000, lightAlpha: 20.0 / 255, darkAlpha: 64.0 / 255), radius: 16, x: 0, y: 4)
    static let knob = Token(color: YubaiColor.adaptive(0x000000, 0x000000, lightAlpha: 46.0 / 255, darkAlpha: 46.0 / 255), radius: 3, x: 0, y: 1)
}

extension View {
    func yubaiShadow(_ token: YubaiShadow.Token) -> some View { shadow(color: token.color, radius: token.radius, x: token.x, y: token.y) }
}

@MainActor enum YubaiMotion {
    static let durationInstant = 0.100
    static let durationQuick = 0.160
    static let durationStandard = 0.240
    static let durationDraw = 0.480
    static let durationWater = 0.320
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
    static let durationWobbleHalf = 0.225
    private static var session = MotionSessionState()
    static func hasAppeared(_ key: String) -> Bool { session.contains(key) }
    static func claim(_ key: String) -> Bool { session.claim(key) }

    static func easeOut(duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
    static func easeIn(duration: Double) -> Animation { .timingCurve(0.4, 0, 1, 1, duration: duration) }
    static func easeInOut(duration: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: duration) }
    static let instant = easeInOut(duration: durationInstant)
    static let quick = Animation.easeInOut(duration: durationQuick)
    static let chartGrowth = easeOut(duration: durationDraw)
    static let waterRise = easeOut(duration: durationWater)
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
    static func water(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : waterRise }
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
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

struct SmallActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.label)
            .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
            .background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
            .opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

private struct NumberChange: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

struct ChartGrow<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    let key: String
    let content: (Double) -> Content
    init(key: String, @ViewBuilder content: @escaping (Double) -> Content) {
        self.key = key; self.content = content
        _progress = State(initialValue: YubaiMotion.hasAppeared(key) ? 1 : 0)
    }
    var body: some View {
        content(reduceMotion ? 1 : progress)
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .onAppear {
                guard YubaiMotion.claim(key) else { finish(); return }
                withAnimation(YubaiMotion.chart(reduceMotion: reduceMotion)) { progress = 1 }
            }
            .onDisappear { finish() }
            .onChange(of: reduceMotion) { _, reduced in if reduced { finish() } }
    }
    private func finish() {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 1 }
    }
}

struct ChartSegments<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: [Double]
    let key: String
    let count: Int
    let content: ([Double]) -> Content
    init(key: String, count: Int, @ViewBuilder content: @escaping ([Double]) -> Content) {
        self.key = key; self.count = min(6, max(1, count)); self.content = content
        _progress = State(initialValue: Array(repeating: YubaiMotion.hasAppeared(key) ? 1 : 0, count: 6))
    }
    var body: some View {
        content(reduceMotion ? Array(repeating: 1, count: 6) : progress)
            .onAppear {
                guard YubaiMotion.claim(key), !reduceMotion else { finish(); return }
                for index in 0..<6 {
                    withAnimation(YubaiMotion.chart(reduceMotion: false)?.delay(Double(min(index, count - 1)) * YubaiMotion.durationStagger)) { progress[index] = 1 }
                }
            }
            .onDisappear { finish() }
            .onChange(of: reduceMotion) { _, reduced in if reduced { finish() } }
    }
    private func finish() {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { progress = Array(repeating: 1, count: 6) }
    }
}

private struct SheetSurfaceKey: EnvironmentKey { static let defaultValue = false }
private struct ZoomNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    var yubaiSheetSurface: Bool { get { self[SheetSurfaceKey.self] } set { self[SheetSurfaceKey.self] = newValue } }
    var yubaiZoomNamespace: Namespace.ID? { get { self[ZoomNamespaceKey.self] } set { self[ZoomNamespaceKey.self] = newValue } }
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

private struct PaperBackground: ViewModifier {
    @Environment(\.yubaiSheetSurface) private var inSheet
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *), inSheet { content }
        else {
            #if os(iOS)
            content.background(YubaiColor.canvas.ignoresSafeArea())
            #else
            content.background(YubaiColor.canvas)
            #endif
        }
    }
}

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

struct GlassGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if #available(iOS 26, macOS 26, *) { GlassEffectContainer(spacing: YubaiSpace.gapGroup) { content } }
        else { content }
    }
}

private struct ContentZoom: ViewModifier {
    @Environment(\.yubaiZoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    let selected: Bool
    func body(content: Content) -> some View {
        content.scaleEffect(reduceMotion ? 1 : scale).onChange(of: selected) { _, selected in
            guard selected, !reduceMotion else { return }
            scale = 0.94
            Task { @MainActor in
                await Task.yield()
                withAnimation(YubaiMotion.control(reduceMotion: reduceMotion)) { scale = 1 }
            }
        }
    }
}

extension View {
    func amountPrivacy(_ hidden: Bool) -> some View { contentTransition(.opacity).animation(YubaiMotion.quick, value: hidden) }
    func paperBackground() -> some View { modifier(PaperBackground()) }
    func rootScrollContentMargins() -> some View {
        #if os(iOS)
        self.contentMargins(.bottom, YubaiSize.rootBottomPadding, for: .scrollContent)
            .scrollEdgeEffectHidden(true, for: .bottom)
            // Root headers live outside this clipped scrolling body.
            .clipped()
        #else
        self.safeAreaPadding(.bottom, YubaiSize.rootBottomPadding)
        #endif
    }
    func rootPageHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
        VStack(spacing: YubaiSpace.none) {
            header()
                .padding(.horizontal, YubaiSpace.insetPage)
                .padding(.top, YubaiSpace.gapGroup).padding(.bottom, YubaiSpace.gapSection)
                .background(YubaiColor.canvas)
            self
                .overlay(alignment: .top) {
                    LinearGradient(colors: [YubaiColor.canvas, YubaiColor.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: YubaiSpace.space8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
        }
    }
    func pageLocalHorizontalGestures() -> some View {
        #if os(iOS)
        self.gesture(HorizontalPan(allowsSubgestures: true))
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
        configuration.label.yubaiFont(compact ? YubaiFont.callout : YubaiFont.button)
            .padding(.horizontal, compact ? YubaiSpace.space16 : YubaiSpace.gapSection).padding(.vertical, compact ? YubaiSpace.space8 : YubaiSpace.gapGroup)
            .frame(maxWidth: .infinity, minHeight: compact ? YubaiSize.rowIcon : YubaiSize.buttonHeight)
            .foregroundStyle(isEnabled ? YubaiColor.onBrand : YubaiColor.labelSecondary)
            .background(isEnabled ? YubaiColor.brand : disabledBackground, in: Capsule()).frame(minHeight: YubaiSize.tapMin)
            .opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
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
            .background(isEnabled ? background : Color.clear, in: Capsule()).frame(minHeight: YubaiSize.tapMin)
            .opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
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
        }.scrollDismissesKeyboard(.interactively).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).paperBackground()
    }
}

struct Card<Content: View>: View {
    enum Style { case standard, list, compact }
    let content: Content
    var style: Style
    var background: Color
    init(style: Style = .standard, background: Color = YubaiColor.card, @ViewBuilder content: () -> Content) {
        self.content = content(); self.style = style; self.background = background
    }
    var body: some View {
        content.padding(.horizontal, YubaiSpace.insetCard)
            .padding(.vertical, style == .list ? YubaiSpace.space4 : YubaiSpace.insetCard)
            .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(YubaiColor.label)
            .background(background, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
    }
}

/// A single list surface with lazy rows, including large ledgers and matching candidates.
struct CardRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rows: Data
    var hasLeadingIcon: Bool
    var rowHeight: CGFloat
    let content: (Data.Element) -> Row
    init(_ rows: Data, hasLeadingIcon: Bool = false, rowHeight: CGFloat = YubaiSize.rowDouble, @ViewBuilder content: @escaping (Data.Element) -> Row) {
        self.rows = rows; self.hasLeadingIcon = hasLeadingIcon; self.rowHeight = rowHeight; self.content = content
    }
    var body: some View {
        Card(style: .list) {
            LazyVStack(spacing: YubaiSpace.none) {
                ForEach(rows) { row in
                    content(row).frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading).transition(YubaiMotion.rowTransition(reduceMotion: reduceMotion))
                    if row.id != rows.last?.id {
                        Rectangle().fill(YubaiColor.separator).frame(height: 1)
                            .padding(.leading, hasLeadingIcon ? YubaiSize.rowTextInset : YubaiSpace.none).accessibilityHidden(true)
                    }
                }
            }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: rows.map(\.id))
        }
    }
}

/// The card and dividers stay in CardRows. Only the full-width row content moves.
/// An offset preserves its layout proposal; revealing an action never narrows text.
struct SwipeActionRow<Content: View>: View {
    let offset: CGFloat
    let revealed: Bool
    let title: String
    let tint: Color
    let ink: Color
    let weight: Font.Weight
    let actionIdentifier: String
    let action: () -> Void
    let content: Content
    init(offset: CGFloat, revealed: Bool, title: String, tint: Color, ink: Color, weight: Font.Weight = .semibold,
         actionIdentifier: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.offset = offset; self.revealed = revealed; self.title = title; self.tint = tint; self.ink = ink; self.weight = weight
        self.actionIdentifier = actionIdentifier; self.action = action; self.content = content()
    }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: offset)
            .background(alignment: .trailing) {
                Button(action: action) {
                    Text(title)
                        #if os(iOS)
                        .frame(width: YubaiSize.swipeActionWidth).frame(maxHeight: .infinity)
                        .background(tint, in: RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous))
                        #endif
                }.buttonStyle(.plain).yubaiFont(YubaiFont.callout, weight: weight).foregroundStyle(ink)
                    #if os(iOS)
                    .padding(.vertical, YubaiSpace.swipeActionInset).padding(.trailing, YubaiSpace.swipeActionInset)
                    #else
                    .frame(width: YubaiSize.swipeRevealDistance - YubaiSpace.gapAction).frame(maxHeight: .infinity).background(tint)
                    #endif
                    .opacity(offset < 0 ? 1 : 0).allowsHitTesting(offset < 0)
                    // Hide the complete action wrapper, including the AX node made by its identifier.
                    .accessibilityIdentifier(actionIdentifier).accessibilityHidden(!revealed)
            }.clipped().contentShape(Rectangle())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let font = textSize.isAccessibilitySize && (resolvedRole == .hero || resolvedRole == .display) ? YubaiFont.amountLarge : resolvedRole.font
        Group {
            if hide { Text("••••").transition(.opacity) }
            else { Text(text).numberTransition(value: numericValue).transition(.opacity) }
        }.yubaiFont(font).foregroundStyle(ink)
            .minimumScaleFactor(resolvedRole == .summary || resolvedRole == .donut ? 0.25 : 0.55).lineLimit(1)
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
            .padding(.vertical, YubaiSpace.space4).frame(minHeight: height).foregroundStyle(ink).background(background, in: Capsule())
    }
}

struct EntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    Text(entry.displayTitle).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label).lineLimit(textSize.isAccessibilitySize ? nil : 1)
                    if entry.hasNoCaptureCategory { Pill(text: "没分类", variant: .amber, height: 20, showsDot: false) }
                    if metadata != nil && entry.nature.uncertain { Pill(text: "没写用途", variant: .amber, height: 20, showsDot: false) }
                }
                Text(metadata ?? "\(dateText) · \(Classification.displayCategory(entry.category)) · \(store.current.accountName(entry.accountID))")
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

struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("完成") { dismiss() }.yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.brandInk).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("closeSheet") }
}

struct BrandMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var risen = true
    enum Variant { case tile, mark }
    var size: CGFloat = 43
    var variant: Variant = .tile
    var color: Color? = nil
    var bands = 3
    var wobbleTrigger = 0
    var moment: String? = nil
    var body: some View {
        let geometry = WaterGeometry(size: size, variant: variant, bands: bands)
        let ink = color ?? (variant == .tile ? YubaiColor.iconInk : YubaiColor.label)
        ZStack {
            if variant == .tile { RoundedRectangle(cornerRadius: size * YubaiRadius.tile).fill(YubaiColor.iconTile) }
            MarkCircle(radius: geometry.ringRadius).stroke(ink, lineWidth: geometry.stroke * size / 100)
            ForEach(0..<geometry.count, id: \.self) { index in
                WaterBand(index: index, geometry: geometry).fill(ink)
                    .modifier(WaterWobble(trigger: wobbleTrigger, index: index))
                    .offset(y: reduceMotion || risen ? 0 : YubaiSpace.gapSection)
                    .opacity(risen ? 1 : 0)
                    .animation(YubaiMotion.water(reduceMotion: reduceMotion)?.delay(Double(index) * YubaiMotion.durationStagger), value: risen)
                    .clipShape(MarkCircle(radius: geometry.clipRadius))
            }
        }.frame(width: size, height: size).accessibilityElement(children: .ignore).accessibilityLabel("余白")
            .task {
                guard let moment, YubaiMotion.claim(moment), !reduceMotion else { return }
                var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
                withTransaction(transaction) { risen = false }; await Task.yield()
                guard !Task.isCancelled else { risen = true; return }; risen = true
            }.onDisappear { risen = true }
    }
}

private struct WaterWobble: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: Int
    let index: Int
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion { content }
        else {
            content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { band, y in band.offset(y: y) } keyframes: { _ in
                LinearKeyframe(CGFloat.zero, duration: Double(index) * YubaiMotion.durationStagger)
                SpringKeyframe(CGFloat(5), duration: YubaiMotion.durationWobbleHalf, spring: YubaiMotion.livelySpring)
                SpringKeyframe(CGFloat.zero, duration: YubaiMotion.durationWobbleHalf, spring: YubaiMotion.livelySpring)
            }
        }
    }
}

private struct WaterGeometry {
    let size: CGFloat
    let variant: BrandMark.Variant
    let bands: Int
    var maxBands: Int {
        if size <= 16 { return 1 }
        if size <= 32 { return 2 }
        return 6
    }
    var count: Int { max(0, min(bands, maxBands)) }
    var ringRadius: CGFloat { variant == .tile ? 34 : 44 }
    var clipRadius: CGFloat {
        if variant == .mark { return 36 }
        if size <= 16 { return 25 }
        return size <= 32 ? 27 : 30
    }
    var stroke: CGFloat {
        if size <= 16 { return 11 }
        return size <= 32 || variant == .mark ? 8 : 4
    }
    var bandHeight: CGFloat {
        if size <= 16 { return 20 }
        return size <= 32 || variant == .mark ? 9 : 5
    }
    func bandY(_ index: Int) -> CGFloat {
        if size <= 16 { return 56 }
        if size <= 32 { return 70 - CGFloat(index) * 16 }
        return variant == .mark ? 84 - CGFloat(index) * 16 : 72 - CGFloat(index) * 9.5
    }
}

private struct MarkCircle: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        return Path(ellipseIn: CGRect(x: rect.midX - radius * scale, y: rect.midY - radius * scale, width: radius * 2 * scale, height: radius * 2 * scale))
    }
}

private struct WaterBand: Shape {
    var index: Int
    var geometry: WaterGeometry
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        let x: CGFloat = geometry.variant == .tile ? 10 : 0
        var path = Path()
        path.addRect(CGRect(x: rect.midX + (x - 50) * scale, y: rect.midY + (geometry.bandY(index) - 50) * scale, width: (100 - 2 * x) * scale, height: geometry.bandHeight * scale))
        return path
    }
}

struct WaterLevelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleBands = 0
    @State private var appeared = false
    var filledBands: Int
    var totalBands: Int
    var size: CGFloat
    var showsTile: Bool
    var moment: String
    init(filledBands: Int, totalBands: Int = 6, size: CGFloat = 168, showsTile: Bool = false, moment: String = "water-level") {
        self.filledBands = filledBands; self.totalBands = totalBands; self.size = size; self.showsTile = showsTile; self.moment = moment
    }
    init(progress: Double, totalBands: Int = 6, size: CGFloat = 168, showsTile: Bool = false, moment: String = "water-level") {
        let geometry = WaterGeometry(size: size, variant: .tile, bands: totalBands)
        let count = max(1, geometry.count)
        let clampedProgress: Double = progress.isFinite ? min(1, max(0, progress)) : 0
        let filledBands = Int((clampedProgress * Double(count)).rounded(.down))
        self.init(filledBands: filledBands, totalBands: count, size: size, showsTile: showsTile, moment: moment)
    }
    private var geometry: WaterGeometry { WaterGeometry(size: size, variant: .tile, bands: max(1, min(6, totalBands))) }
    private var target: Int { max(0, min(geometry.count, filledBands)) }
    var body: some View {
        ZStack {
            if showsTile { RoundedRectangle(cornerRadius: size * YubaiRadius.tile).fill(YubaiColor.iconTile) }
            MarkCircle(radius: geometry.ringRadius).stroke(showsTile ? YubaiColor.iconInk : YubaiColor.label, lineWidth: geometry.stroke * size / 100)
            ForEach(0..<geometry.count, id: \.self) { index in
                WaterBand(index: index, geometry: geometry).fill(YubaiColor.grabber).clipShape(MarkCircle(radius: geometry.clipRadius))
                WaterBand(index: index, geometry: geometry).fill(YubaiColor.brand)
                    .offset(y: reduceMotion || index < visibleBands ? 0 : YubaiSpace.gapSection)
                    .opacity(index < (reduceMotion ? target : visibleBands) ? 1 : 0)
                    .animation(YubaiMotion.water(reduceMotion: reduceMotion)?.delay(Double(min(index, 5)) * YubaiMotion.durationStagger), value: visibleBands)
                    .clipShape(MarkCircle(radius: geometry.clipRadius))
            }
        }.frame(width: size, height: size)
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .accessibilityElement(children: .ignore).accessibilityLabel("水位，共 \(geometry.count) 格，已填 \(target) 格")
            .onAppear { if appeared || !YubaiMotion.claim(moment) { finish() } else { appeared = true; visibleBands = target } }
            .onChange(of: target) { _, value in if appeared { visibleBands = value } else { finish() } }
            .onChange(of: reduceMotion) { _, reduced in if reduced { finish() } }
            .onDisappear { finish() }
    }
    private func finish() {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { visibleBands = target }
    }
}

struct AssistantMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 26
    var color = YubaiColor.brandGlyph
    var thinking = false
    private var stroke: CGFloat {
        let weight: CGFloat
        if size <= 16 { weight = 11 }
        else if size <= 24 { weight = 9 }
        else if size <= 32 { weight = 8 }
        else { weight = 7 }
        return weight * size / 100
    }
    private var wave: some View { AssistantWave().stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)) }
    var body: some View {
        ZStack {
            MarkCircle(radius: 40).stroke(color, lineWidth: stroke)
            if thinking && !reduceMotion {
                wave.phaseAnimator([false, true]) { content, up in content.offset(y: (up ? -3 : 3) * size / 100) } animation: { _ in
                    YubaiMotion.easeInOut(duration: YubaiMotion.durationThink / 2)
                }
            } else { wave.transaction { $0.animation = nil; $0.disablesAnimations = true } }
        }.frame(width: size, height: size)
            .transaction { if !thinking || reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .accessibilityElement(children: .ignore).accessibilityLabel(thinking ? "余白正在思考" : "余白")
    }
}

private struct AssistantWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 22, y: 52))
        path.addCurve(to: CGPoint(x: 41, y: 52), control1: CGPoint(x: 29, y: 43), control2: CGPoint(x: 36, y: 43))
        path.addCurve(to: CGPoint(x: 60, y: 52), control1: CGPoint(x: 46, y: 61), control2: CGPoint(x: 53, y: 61))
        path.addCurve(to: CGPoint(x: 79, y: 52), control1: CGPoint(x: 67, y: 43), control2: CGPoint(x: 72, y: 43))
        let scale = min(rect.width, rect.height) / 100
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: rect.midX - 50 * scale, ty: rect.midY - 50 * scale))
    }
}

struct HeroCard: View {
    @Environment(AppStore.self) private var store
    @State private var displayedAvailable: Int64?
    var available: Int64
    var payable: Int64
    var reserved: Int64
    var attentionCount = 0
    var hideAmount = false
    var title = "还能花"
    var horizon: String? = nil
    var onDetails: (() -> Void)? = nil
    var onAttention: (() -> Void)? = nil
    private var waterBands: Int {
        let cash = Double(available) + Double(payable) + Double(reserved)
        return cash > 0 ? Int((min(1, max(0, Double(available) / cash)) * 6).rounded(.down)) : 0
    }
    var body: some View {
        ChartGrow(key: "hero-composition") { progress in VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            if let onDetails { Button(action: onDetails) { amounts(progress) }.buttonStyle(PressButtonStyle()).yubaiZoomSource("funds").accessibilityIdentifier("fundsFormula").accessibilityHint("还能花是怎么算的") }
            else { amounts(progress) }
            if attentionCount > 0 {
                if let onAttention {
                    Button(action: onAttention) { attention }.buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin)
                } else { attention }
            }
        }.foregroundStyle(YubaiColor.label) }
            .onAppear { displayedAvailable = available }
            .onChange(of: available) { _, value in if !store.pendingEntrySave || store.sheet == nil { displayedAvailable = value } }
            .onChange(of: store.entrySaveTrigger) { _, _ in displayedAvailable = available }
    }
    private func amounts(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            summary
            if !hideAmount {
                composition(progress).padding(.top, YubaiSpace.space8)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.gapGroup) { legends }
                    VStack(alignment: .leading, spacing: YubaiSpace.space8) { legends }
                }
            }
        }.contentShape(Rectangle())
    }
    @ViewBuilder private var legends: some View {
        legend("还能花", available, YubaiColor.brand)
        legend("要付", payable, YubaiColor.neutralStrong)
        legend("日常开销", reserved, YubaiColor.neutralSoft)
    }
    private var summary: some View {
        HStack(alignment: .bottom, spacing: YubaiSpace.gapGroup) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text(title).yubaiFont(YubaiFont.heroLabel).fixedSize()
                    if let horizon { Text(horizon).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                }
                AmountLabel(cents: displayedAvailable ?? available, hide: hideAmount, role: .hero)
            }
            Spacer(minLength: YubaiSpace.none)
            BrandMark(size: 44, bands: waterBands, wobbleTrigger: store.entrySaveTrigger, moment: "hero-water").padding(.bottom, YubaiSpace.space8).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private var attention: some View { Pill(text: "\(attentionCount) 件小事需要留意", variant: .amber, showsChevron: onAttention != nil) }
    private func composition(_ progress: Double) -> some View {
        let values = [max(0, Double(available)), max(0, Double(payable)), max(0, Double(reserved))]
        let total = values.reduce(0, +)
        let colors = [YubaiColor.brand, YubaiColor.neutralStrong, YubaiColor.neutralSoft]
        let indices = values.indices.filter { values[$0] > 0 }
        return GeometryReader { geometry in
            let width = max(0, geometry.size.width - CGFloat(max(0, indices.count - 1)) * YubaiSpace.space4)
            HStack(spacing: YubaiSpace.space4) {
                ForEach(indices, id: \.self) { index in
                    let ratio: Double = total > 0 ? values[index] / total : 0
                    let animatedRatio: Double = ratio * progress
                    colors[index].frame(width: width * CGFloat(animatedRatio))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).background(total == 0 ? YubaiColor.neutralSoft : Color.clear).clipShape(Capsule())
        }.frame(height: YubaiSpace.gapGroup).accessibilityElement(children: .ignore)
            .accessibilityLabel("还能花 \(AmountLabel.text(available))，要付 \(AmountLabel.text(payable))，日常开销 \(AmountLabel.text(reserved))")
    }
    private func legend(_ title: String, _ cents: Int64, _ color: Color) -> some View {
        HStack(spacing: YubaiSpace.space4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: YubaiSize.marker, height: YubaiSize.marker).accessibilityHidden(true)
            Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: cents, role: .small)
        }
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
                    .padding(YubaiSpace.insetCard).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
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
                    .background(YubaiColor.amberTint, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
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
            Button(action, action: onAction).yubaiFont(YubaiFont.callout, weight: .medium).padding(.horizontal, YubaiSpace.gapGroup)
                .frame(minHeight: YubaiSize.chipHeight).foregroundStyle(YubaiColor.amberStrong).background(YubaiColor.raised, in: Capsule())
                .frame(minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle())
        }
        if let secondaryAction, let onSecondaryAction {
            Button(secondaryAction, action: onSecondaryAction).yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup)
                .frame(minHeight: YubaiSize.tapMin).foregroundStyle(YubaiColor.amberInk).buttonStyle(PressButtonStyle())
        }
    }
}

struct EmptyState: View {
    var icon: String
    var title: String
    var message: String?
    var action: String? = nil
    var onAction: (() -> Void)?
    var showsPlaceholder: Bool
    init(_ icon: String, _ title: String, _ message: String? = nil, showsPlaceholder: Bool = true, action: String? = nil, onAction: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.message = message; self.showsPlaceholder = showsPlaceholder; self.action = action; self.onAction = onAction
    }
    var body: some View {
        VStack(spacing: YubaiSpace.gapGroup) {
            if showsPlaceholder {
                Circle().stroke(YubaiColor.borderDashed, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .frame(width: YubaiSize.iconButton * 3, height: YubaiSize.iconButton * 3).accessibilityHidden(true)
            }
            VStack(spacing: YubaiSpace.space8) {
                Text(title).yubaiFont(YubaiFont.lead).foregroundStyle(YubaiColor.label)
                if let message, !message.isEmpty { Text(message).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).frame(maxWidth: 410) }
            }.multilineTextAlignment(.center)
            if let action, let onAction { Button(action, action: onAction).buttonStyle(PrimaryButtonStyle()) }
        }.frame(maxWidth: .infinity).padding(.vertical, YubaiSpace.gapSection).padding(.horizontal, YubaiSpace.insetPage)
    }
}

struct Toast: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    var text: String
    var undoTitle = "撤销"
    var onUndo: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var body: some View {
        // A concrete host must exist before visible becomes true. An empty Group has no
        // child on which to run the task that inserts the receipt in the first place.
        ZStack { if visible { surface } }
            .task(id: text) {
                withAnimation(YubaiMotion.toastIn(reduceMotion: reduceMotion)) { visible = true }
                #if DEBUG && targetEnvironment(simulator)
                if onUndo != nil && UITestSupport.keepsUndoReceipt { return }
                #endif
                do { try await Task.sleep(for: .seconds(YubaiMotion.toastLifetime)) } catch { return }
                withAnimation(YubaiMotion.toastOut(reduceMotion: reduceMotion)) { visible = false; onDismiss?() }
            }
    }
    private var surface: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(text).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("toastMessage")
            if let onUndo {
                Text("·").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).accessibilityHidden(true)
                Button(undoTitle, action: onUndo).yubaiFont(YubaiFont.row, weight: .semibold).foregroundStyle(YubaiColor.brandInk)
                    .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle())
                    .accessibilityIdentifier("undoLastChange")
            }
            if let onDismiss {
                Button { withAnimation(YubaiMotion.toastOut(reduceMotion: reduceMotion)) { visible = false; onDismiss() } } label: {
                    Image(systemName: "xmark").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("关闭提示")
            }
        }.padding(.leading, YubaiSpace.insetCard).padding(.trailing, YubaiSpace.space8).padding(.vertical, YubaiSpace.space4)
            .frame(minHeight: YubaiSize.buttonHeight).background(YubaiColor.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(YubaiColor.separator, lineWidth: 1) }.yubaiShadow(YubaiShadow.float)
            .padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.gapGroup)
            .transition(YubaiMotion.toastTransition(reduceMotion: reduceMotion))
            .gesture(DragGesture(minimumDistance: YubaiSpace.gapGroup).onEnded { value in
                if value.translation.height > YubaiSpace.gapSection { withAnimation(YubaiMotion.toastOut(reduceMotion: reduceMotion)) { visible = false; onDismiss?() } }
            })
    }
}

extension View {
    func appErrors() -> some View { modifier(AppErrorPresenter()) }
    func numericInput() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
    func editorForm() -> some View {
        self.formStyle(.grouped).scrollContentBackground(.hidden).paperBackground()
            .environment(\.defaultMinListRowHeight, YubaiSize.rowSingle).scrollDismissesKeyboard(.interactively)
            .yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).tint(YubaiColor.brand).buttonStyle(.automatic)
    }
    func yubaiNavigation() -> some View {
        self.paperBackground().tint(YubaiColor.brandInk)
            #if os(iOS)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
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
                Button("知道了", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

struct WelcomeView: View {
    private enum Field: Hashable { case balance, name }
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = "微信零钱"
    @State private var amount = ""
    @State private var customName = false
    @FocusState private var focusedField: Field?
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.insetCard) {
                    BrandMark(size: YubaiSize.iconButton + YubaiSpace.gapSection)
                        .padding(.top, YubaiSpace.gapSection + YubaiSpace.space8)
                    Text("余白").yubaiFont(YubaiFont.welcome)
                    Card {
                        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                            Text("现在手里有").yubaiFont(YubaiFont.heroLabel)
                            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                                Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                                TextField("0.00", text: $amount).numericInput().yubaiFont(YubaiFont.amountDisplay)
                                    .focused($focusedField, equals: .balance)
                                    .accessibilityLabel("现在手里的余额，元").accessibilityIdentifier("accountBalance")
                            }
                            ChipFlow {
                                ForEach(["微信零钱", "支付宝", "招行储蓄卡"], id: \.self) { value in
                                    SuggestionChip(value: value, selected: !customName && name == value) { name = value; customName = false }
                                }
                                SuggestionChip(value: "＋ 别的", selected: customName) { name = ""; customName = true; focusedField = .name }
                                    .accessibilityIdentifier("welcomeOtherAccount")
                            }.padding(.top, YubaiSpace.space8)
                            if customName {
                                TextField("名称", text: $name).accessibilityIdentifier("accountName")
                                    .focused($focusedField, equals: .name)
                                    .accessibilityLabel("账户名称")
                            }
                        }
                    }.padding(.top, YubaiSpace.gapSection).id("welcomeBalanceCard")
                        .accessibilityElement(children: .contain).accessibilityIdentifier("welcomeBalanceCard")
                }.frame(maxWidth: 610, alignment: .leading).frame(maxWidth: .infinity)
                    .padding(YubaiSpace.insetPage)
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("welcomeScroll")
                .onGeometryChange(for: CGSize.self) { geometry in
                    // The inset can change the safe viewport without changing the scroll frame.
                    CGSize(width: geometry.size.width,
                           height: geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom)
                } action: { _ in revealBalanceCard(using: proxy) }
                .task(id: focusedField) {
                    await Task.yield()
                    revealBalanceCard(using: proxy)
                }
                .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
                    Button("开始", action: start).buttonStyle(PrimaryButtonStyle(disabledBackground: YubaiColor.brandTint))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (try? Money.parse(amount, allowNegative: true)) == nil)
                        .accessibilityIdentifier("startLedger")
                        .padding(YubaiSpace.insetPage).background(YubaiColor.canvas)
                }
        }.yubaiNavigation().toolbar { Button("恢复备份") { store.sheet = .backup } }
    }
    private func revealBalanceCard(using proxy: ScrollViewProxy) {
        guard focusedField != nil else { return }
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) {
            proxy.scrollTo("welcomeBalanceCard", anchor: .bottom)
        }
    }
    private func start() {
        do {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw YubaiError.invalid("请给账户起一个名称。") }
            guard !store.current.accounts.contains(where: { $0.name == clean }) else { throw YubaiError.invalid("已有同名账户，请使用容易区分的名称。") }
            let cents = try Money.parse(amount, allowNegative: true)
            let kind: AccountKind = ["微信零钱", "支付宝"].contains(clean) ? .cash : .bank
            let account = Account(name: clean, kind: kind, balance: cents, at: Date(), reconciled: true)
            store.update("建立账本") { ledger in
                ledger.accounts.append(account)
                ledger.preferences.onboardingComplete = true
            }
        } catch { store.error = error.localizedDescription }
    }
}

/// Suggestions are controls; their content becomes the user's editable value.
struct SuggestionChips: View {
    let values: [String]
    var selected: String? = nil
    var identifierPrefix = "suggestion_"
    let choose: (String) -> Void
    var body: some View {
        ChipFlow { chips }
    }
    private var chips: some View {
        ForEach(values, id: \.self) { value in
            SuggestionChip(value: value, selected: selected == value, identifier: identifierPrefix + value) { choose(value) }
        }
    }
}

struct SuggestionChip: View {
    let value: String
    var selected = false
    var identifier = ""
    let choose: () -> Void
    var body: some View {
        Button(action: choose) {
            Text(value).yubaiFont(YubaiFont.caption)
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                .foregroundStyle(selected ? YubaiColor.onBrand : YubaiColor.label)
                .background(selected ? YubaiColor.brand : YubaiColor.raised, in: Capsule())
                .frame(minHeight: YubaiSize.tapMin)
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(identifier)
    }
}

struct ChipFlow: Layout {
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
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + YubaiSpace.space8; rowHeight = 0 }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            usedWidth = max(usedWidth, x + size.width); rowHeight = max(rowHeight, size.height)
            x += size.width + YubaiSpace.space8
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

struct DashedPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: YubaiRadius.bar)
            .stroke(YubaiColor.borderDashed, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: YubaiSpace.gapGroup).accessibilityHidden(true)
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
            let size = YubaiSize.tapMin * 2
            let geometry = WaterGeometry(size: size, variant: .mark, bands: 3)
            ZStack {
                MarkCircle(radius: geometry.ringRadius).stroke(YubaiColor.borderDashed, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(0..<geometry.count, id: \.self) { index in
                    WaterBand(index: index, geometry: geometry).stroke(YubaiColor.borderDashed, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .clipShape(MarkCircle(radius: geometry.clipRadius))
                }
            }.frame(width: size, height: size).accessibilityHidden(true)
            Button("添加第一个账户", action: add).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("addFirstAccount")
        }.frame(maxWidth: .infinity).padding(.vertical, YubaiSpace.gapSection)
            .accessibilityElement(children: .contain).accessibilityLabel("还没有账户")
    }
}

extension Nature {
    var entryLabel: String { paired ? "转账" : (inflow ? "收入" : "支出") }
}

/// Answer data is built from a read tool in YubaiCore; animation never changes labels.
struct AnswerChartView: View {
    let chart: AnswerChart
    private var domain: ClosedRange<Double> {
        let values = chart.points.map { Double($0.cents) / 100 }
        return min(0, values.min() ?? 0)...max(1, values.max() ?? 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            Text(chart.title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            ChartSegments(key: "answer-chart-\(chart.kind)-\(chart.title)", count: chart.kind == .bar ? chart.points.count : 1) { progress in
                Chart {
                    ForEach(Array(chart.points.enumerated()), id: \.offset) { index, point in
                        if chart.kind == .bar {
                            BarMark(x: .value("分类", point.label), y: .value("金额", Double(point.cents) / 100 * progress[min(index, 5)]))
                                .foregroundStyle(YubaiColor.brand)
                        } else {
                            LineMark(x: .value("日期", point.label), y: .value("金额", Double(point.cents) / 100))
                                .foregroundStyle(YubaiColor.brand).lineStyle(StrokeStyle(lineWidth: YubaiSize.lineWidth))
                        }
                    }
                }.chartYScale(domain: domain).chartYAxis(.hidden).chartLegend(.hidden)
                    .chartPlotStyle { plot in plot.mask(alignment: .leading) { GeometryReader { geometry in
                        Rectangle().frame(width: geometry.size.width * (chart.kind == .bar ? 1 : progress[0]))
                    } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel().foregroundStyle(YubaiColor.labelSecondary).font(.system(size: YubaiFont.chartLabel.size))
                    } }.frame(height: 180)
                    .accessibilityLabel(chart.title + "。" + chart.points.map { $0.label + "，" + Money.text($0.cents) }.joined(separator: "；"))
            }
        }
    }
}

struct AddEntryButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "plus").font(.system(size: 26, weight: .medium)).foregroundStyle(YubaiColor.onBrand).accessibilityHidden(true)
            .frame(width: 62, height: 62).floatingSurface(in: Circle(), tint: YubaiColor.brand, shadow: YubaiShadow.ask)
        }.buttonStyle(RoundPressStyle())
            .accessibilityLabel("记一笔").accessibilityIdentifier("addEntry")
    }
}

/// Shared scaling keeps the eye and assistant glyphs inside matching circles.
struct HeaderIconButton<Icon: View>: View {
    @ScaledMetric(relativeTo: .body) private var scaledSize = YubaiSize.headerIcon
    let action: () -> Void
    let icon: (CGFloat) -> Icon
    init(action: @escaping () -> Void, @ViewBuilder icon: @escaping (CGFloat) -> Icon) {
        self.action = action; self.icon = icon
    }
    var body: some View {
        let iconSize = min(max(scaledSize, YubaiSize.headerIcon), YubaiSize.headerIconMax)
        let side = max(YubaiSize.iconButton, iconSize + YubaiSpace.space8 * 2)
        Button(action: action) {
            icon(iconSize).accessibilityHidden(true)
                .frame(width: side, height: side).floatingSurface(in: Circle())
                .yubaiHitTarget()
        }.buttonStyle(PressButtonStyle())
    }
}

struct AskToolbarButton: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        HeaderIconButton(action: { store.present(.ask(""), from: "ask") }) { size in
            AssistantMark(size: size, color: YubaiColor.brandInk)
        }.yubaiZoomSource("ask")
            .accessibilityLabel("问余白").accessibilityIdentifier("askYubai")
    }
}

struct TabRootHeader: View {
    @Environment(AppStore.self) private var store
    let title: String
    var showsAmountVisibility = false
    var body: some View {
        GlassGroup {
            ZStack {
                Text(title).yubaiFont(YubaiFont.navTitle).accessibilityIdentifier("rootHeaderTitle")
                HStack(spacing: YubaiSpace.gapGroup) {
                    if showsAmountVisibility {
                        HeaderIconButton(action: { store.update("切换金额显示", recordUndo: false) { $0.preferences.hideAmounts.toggle() } }) { size in
                            Image(systemName: store.current.preferences.hideAmounts ? "eye.slash" : "eye")
                                .font(.system(size: size))
                        }.accessibilityLabel(store.current.preferences.hideAmounts ? "显示金额" : "隐藏金额")
                            .accessibilityIdentifier("toggleAmountVisibility")
                    } else { Color.clear.frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin) }
                    Spacer(); AskToolbarButton()
                }
            }.frame(minHeight: YubaiSize.headerHeight)
        }
    }
}

private struct RoundPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(configuration.isPressed ? YubaiMotion.instant : (reduceMotion ? YubaiMotion.quick : YubaiMotion.lively), value: configuration.isPressed)
    }
}

struct Segmented<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    let choices: [(Value, String)]
    @Binding var selection: Value
    var background = YubaiColor.card
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: YubaiSpace.none)) : AnyLayout(HStackLayout(spacing: YubaiSpace.none))
        layout {
            ForEach(choices.indices, id: \.self) { i in
                let value = choices[i].0
                Button { selection = value } label: {
                    Text(choices[i].1).yubaiFont(YubaiFont.callout, weight: selection == value ? .medium : .regular)
                        .foregroundStyle(selection == value ? YubaiColor.label : YubaiColor.labelSecondary).transaction { $0.animation = nil }
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.segmentedPill).fixedSize(horizontal: false, vertical: true).background {
                            if selection == value {
                                if reduceMotion { RoundedRectangle(cornerRadius: YubaiRadius.control).fill(YubaiColor.raised).transition(.opacity) }
                                else { RoundedRectangle(cornerRadius: YubaiRadius.control).fill(YubaiColor.raised).matchedGeometryEffect(id: "selection", in: selectionNamespace) }
                            }
                        }.yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }.padding(.horizontal, YubaiSpace.space4)
            .background {
                RoundedRectangle(cornerRadius: YubaiRadius.row).fill(background)
                    .padding(.vertical, YubaiSize.segmentedHitOutset).allowsHitTesting(false)
            }.fixedSize(horizontal: false, vertical: true)
            .animation(YubaiMotion.control(reduceMotion: reduceMotion), value: selection)
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
                HStack(spacing: YubaiSpace.space8) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白想这样改").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
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
            if store.current.preferences.hideAmounts {
                Button("显示金额") { store.update("显示金额", recordUndo: false) { $0.preferences.hideAmounts = false } }
                    .buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityHint("显示金额后可核对并确认修改")
            } else {
                Button(primaryTitle, action: confirm).buttonStyle(PrimaryButtonStyle(compact: true)).disabled(!canConfirm)
            }
            Button(secondaryTitle, action: cancel).buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised, compact: true))
        }
    }
}

private struct ChartReveal: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - YubaiSpace.gapSection, width: rect.width * min(1, max(0, progress)), height: rect.height + YubaiSpace.gapSection * 2))
    }
}

struct ForecastChart: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineProgress: Double = 0
    @State private var pointVisible = false
    @State private var endpointVisible = false
    @State private var appeared = false
    @State private var visible = false
    @State private var ringVisible = false
    @State private var ringProgress: CGFloat = 0
    @GestureState private var scrubbing = false
    @State private var selectedDay: Date?
    @State private var accessibleDay: Date?
    @State private var selectionTrigger = 0
    let funds: Funds
    var height: CGFloat = 150
    private var lowPoint: ForecastPoint? { funds.points.min(by: { $0.conservative < $1.conservative }) }
    private var selectedPoint: ForecastPoint? { funds.points.first { $0.date == selectedDay } }
    private var horizon: String {
        funds.payday == nil ? "接下来 \(funds.horizonDays) 天" : "到 " + funds.horizonEnd.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                SectionHeading(title: "现金会怎么走", meta: selectedDay.map { $0.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) } ?? horizon)
                if store.current.preferences.hideAmounts {
                    Text("金额已隐藏").yubaiFont(YubaiFont.callout)
                } else {
                    forecastPlot
                }
            }
        }.pageLocalHorizontalGestures()
    }
    private var forecastPlot: some View {
        let visit = store.overviewVisit; let active = store.destination == .overview && appeared && visible; let reduced = reduceMotion
        return Chart {
            ForEach(funds.points) { point in
                LineMark(x: .value("日期", point.date), y: .value("还能花", Double(point.conservative) / 100))
                    .interpolationMethod(.stepEnd).foregroundStyle(YubaiColor.brand)
            }
            RuleMark(y: .value("零点", 0))
                .foregroundStyle(YubaiColor.chartRule).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let point = selectedPoint {
                RuleMark(x: .value("选中日期", point.date)).foregroundStyle(YubaiColor.chartGuide)
                PointMark(x: .value("日期", point.date), y: .value("还能花", Double(point.conservative) / 100))
                    .foregroundStyle(YubaiColor.brand)
            }
            if let last = funds.points.last {
                PointMark(x: .value("日期", last.date), y: .value("还能花", Double(last.conservative) / 100))
                    .foregroundStyle(YubaiColor.brand).symbolSize(0)
                    .annotation(position: .top, alignment: .trailing, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        AmountLabel(cents: last.conservative, role: .chart).fixedSize().opacity(reduceMotion || endpointVisible ? 1 : 0)
                    }
            }
        }.chartYAxis(.hidden).chartLegend(.hidden)
            .chartXScale(range: .plotDimension(padding: YubaiSpace.space8))
            .chartYScale(range: .plotDimension(padding: YubaiSpace.insetCard))
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month()) } }
            .chartPlotStyle { plot in plot.mask(ChartReveal(progress: reduceMotion ? 1 : lineProgress)) }
            .chartOverlay { proxy in forecastOverlay(proxy) }.frame(height: height)
            .accessibilityElement(children: .ignore).accessibilityLabel(chartDescription)
            .accessibilityValue(accessibleDay.flatMap { date in funds.points.first { $0.date == date } }.map(readoutDescription) ?? "")
            .accessibilityHint("上下轻扫逐天查看")
            .accessibilityAdjustableAction { direction in
                guard !funds.points.isEmpty else { return }
                let current = funds.points.firstIndex { $0.date == accessibleDay } ?? 0
                let next: Int
                switch direction {
                case .increment: next = min(funds.points.count - 1, current + 1)
                case .decrement: next = max(0, current - 1)
                @unknown default: return
                }
                let date = funds.points[next].date
                if accessibleDay != date { accessibleDay = date; selectionTrigger &+= 1 }
            }
            .accessibilityIdentifier("forecastChart")
            .onGeometryChange(for: Bool.self) { geometry in
                let bounds = CGRect(origin: .zero, size: geometry.size)
                return !bounds.isEmpty && (geometry.bounds(of: .scrollView)?.intersects(bounds) ?? true)
            } action: { visible = $0 }
            .onChange(of: scrubbing) { _, active in if !active { endScrub() } }
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: selectionTrigger)
            #endif
            .task(id: "\(visit)-\(active)-\(reduced)") { await playForecast(visit: visit, active: active, reduced: reduced) }
            .onAppear { appeared = true }
            .onDisappear { appeared = false; finishForecast() }
    }
    private func forecastOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(scrubGesture(proxy, geometry: geometry))
                if let point = funds.points.last, let plot = proxy.plotFrame,
                   let x = proxy.position(forX: point.date), let y = proxy.position(forY: Double(point.conservative) / 100) {
                    let frame = geometry[plot]
                    Circle().fill(YubaiColor.brand).frame(width: YubaiSize.marker, height: YubaiSize.marker)
                        .opacity(reduceMotion || endpointVisible ? 1 : 0)
                        .offset(y: reduceMotion || endpointVisible ? 0 : -YubaiSpace.space8)
                        .position(x: frame.minX + x, y: frame.minY + y).allowsHitTesting(false)
                }
                if let point = lowPoint, point.conservative < 0,
                   let plotFrame = proxy.plotFrame, let x = proxy.position(forX: point.date), let y = proxy.position(forY: Double(point.conservative) / 100) {
                    let frame = geometry[plotFrame]
                    let ink = YubaiColor.amberDot
                    ZStack {
                        if ringVisible && !reduceMotion {
                            Circle().stroke(ink, lineWidth: 1).frame(width: YubaiSize.marker * (1 + ringProgress * 2.2), height: YubaiSize.marker * (1 + ringProgress * 2.2))
                                .opacity(0.7 * (1 - ringProgress))
                        }
                        Circle().fill(ink).frame(width: YubaiSize.marker, height: YubaiSize.marker)
                            .opacity(reduceMotion || pointVisible ? 1 : 0).offset(y: reduceMotion || pointVisible ? 0 : -YubaiSpace.space8)
                    }.position(x: frame.minX + x, y: frame.minY + y).allowsHitTesting(false)
                }
                if let point = selectedPoint, let plot = proxy.plotFrame, let x = proxy.position(forX: point.date) {
                    let frame = geometry[plot]
                    let width = min(260, geometry.size.width)
                    readout(point).frame(width: width)
                        .position(x: min(geometry.size.width - width / 2, max(width / 2, frame.minX + x)), y: frame.minY + 48)
                        .transition(.opacity).allowsHitTesting(false)
                }
            }
        }.accessibilityHidden(true)
    }
    private func scrubGesture(_ proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: YubaiMotion.durationDismiss, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($scrubbing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag?) = value, let plot = proxy.plotFrame else { return }
                let frame = geometry[plot]
                let x = min(frame.width, max(0, drag.location.x - frame.minX))
                guard let date: Date = proxy.value(atX: x),
                      let point = funds.points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) else { return }
                if selectedDay != point.date { selectedDay = point.date; selectionTrigger &+= 1 }
            }
            .onEnded { _ in endScrub() }
    }
    private func playForecast(visit: Int, active: Bool, reduced: Bool) async {
        guard !Task.isCancelled, active else { return }
        guard store.forecastMotion.claim(visit, reduceMotion: reduced) else { finishForecast(); return }
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { lineProgress = 0; pointVisible = false; endpointVisible = false; ringVisible = false; ringProgress = 0 }
        do {
            try await Task.sleep(for: .seconds(YubaiMotion.durationStagger))
            withAnimation(YubaiMotion.chart(reduceMotion: false)) { lineProgress = 1 }
            try await Task.sleep(for: .seconds(YubaiMotion.pointDelay))
            withAnimation(YubaiMotion.control(reduceMotion: false)) { pointVisible = true }
            try await Task.sleep(for: .seconds(YubaiMotion.ringDelay - YubaiMotion.pointDelay))
            if (lowPoint?.conservative ?? 0) < 0 {
                ringVisible = true
                withAnimation(YubaiMotion.ring(reduceMotion: false)) { ringProgress = 1 }
            }
            try await Task.sleep(for: .seconds(YubaiMotion.durationDraw - YubaiMotion.ringDelay))
            withAnimation(YubaiMotion.control(reduceMotion: false)) { endpointVisible = true }
        } catch {}
    }
    private func finishForecast() {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { lineProgress = 1; pointVisible = true; endpointVisible = true; ringVisible = false; ringProgress = 1 }
    }
    private func endScrub() { withAnimation(YubaiMotion.quick) { selectedDay = nil } }
    private func dayLabel(_ point: ForecastPoint) -> String {
        point.date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) + " · "
            + point.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
    }
    private func events(_ point: ForecastPoint) -> [String] {
        let items = funds.occurrences.filter { Dates.day($0.date) == point.date }
        let shortfall = point.conservative < 0 ? "比留着的少 " + Money.text(-point.conservative, currency: false) : ""
        let lines = items.map { $0.title + " " + ($0.inflow ? "+" : "−") + Money.text($0.amount, currency: false) }
        guard !shortfall.isEmpty else { return lines }
        if lines.isEmpty { return [shortfall] }
        return lines.enumerated().map { $0.offset == 0 ? $0.element + " · " + shortfall : $0.element }
    }
    private func readout(_ point: ForecastPoint) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(dayLabel(point)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            AmountLabel(cents: point.conservative, role: .card)
            ForEach(Array(events(point).enumerated()), id: \.offset) { _, event in
                Text(event).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelMuted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.gapGroup)
            .background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
    }
    private func readoutDescription(_ point: ForecastPoint) -> String {
        dayLabel(point) + "，还能花 " + Money.text(point.conservative) + "。" + events(point).joined(separator: "；")
    }
    private var chartDescription: String {
        guard let first = funds.points.first, let last = funds.points.last,
              let low = funds.points.min(by: { $0.conservative < $1.conservative }) else { return "还没有预测明细" }
        return "还能花从 \(Money.text(first.conservative)) 起，\(Dates.text(low.date)) 最低 \(Money.text(low.conservative))，\(Dates.text(last.date)) \(Money.text(last.conservative))。"
    }
}

struct AssistantCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(YubaiSpace.insetCard).frame(maxWidth: .infinity, alignment: .leading)
            .background(YubaiColor.card, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 22, bottomTrailingRadius: 22, topTrailingRadius: 22))
    }
}
