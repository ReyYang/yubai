import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private struct DSAnimationsEnabledKey: EnvironmentKey { static let defaultValue = true }
private struct DSReduceMotionOverrideKey: EnvironmentKey { static let defaultValue: Bool? = nil }

extension EnvironmentValues {
    /// Snapshot rendering freezes loops and entrances without pretending Reduce Motion is on.
    var dsAnimationsEnabled: Bool {
        get { self[DSAnimationsEnabledKey.self] }
        set { self[DSAnimationsEnabledKey.self] = newValue }
    }
    var dsReduceMotionOverride: Bool? {
        get { self[DSReduceMotionOverrideKey.self] }
        set { self[DSReduceMotionOverrideKey.self] = newValue }
    }
}

/// Interaction constants specified by the DS acceptance contract, not theme tokens.
/// Keep these here rather than inventing JSON tokens or scattering literals in components.
enum DSInteraction {
    static let reducedPressOpacity = 0.7
    static let warningFraction = 0.85
    // The generator reads the appearance scale from the float-card role usage.
    static let floatScale = DSMotion.Role.floatCard.initialScale
}

/// Item counts describe composition, not geometry.
enum DSLayout {
    static let keypadColumns = 4
    static let digitKeypadColumns = 3
    static let categoryRow = 5
    static let heroBudgets = 3
    static let weekdays = 7
    static let dayGridRows = 4
}

struct DSPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: DS.Size.tapMin, minHeight: DS.Size.tapMin)
            .contentShape(Rectangle())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? DSMotion.Press.scale : 1))
            .opacity(reduceMotion && configuration.isPressed ? DSInteraction.reducedPressOpacity : 1)
            .animation(animationsEnabled ? (reduceMotion ? DSMotion.reduceMotionAnimation : DSMotion.Press.animation) : nil, value: configuration.isPressed)
            .sensoryFeedback(DSMotion.Press.haptic, trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

private struct DSTextModifier: ViewModifier {
    let style: DS.TextStyle
    #if os(iOS)
    @ScaledMetric private var scaledSize: CGFloat
    #else
    private let scaledSize: CGFloat
    #endif

    init(_ style: DS.TextStyle) {
        self.style = style
        #if os(iOS)
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        #else
        scaledSize = style.size
        #endif
    }

    func body(content: Content) -> some View {
        let scale = scaledSize / style.size
        let font = Font.system(size: scaledSize, weight: style.weight, design: style.design)
        // Native font line height already contains leading. Add only the missing
        // part of the token's line box, including around a single line.
        #if os(iOS)
        let weight: UIFont.Weight = style.weight == .semibold ? .semibold : (style.weight == .medium ? .medium : .regular)
        let nativeLineHeight = UIFont.systemFont(ofSize: scaledSize, weight: weight).lineHeight
        #else
        let weight: NSFont.Weight = style.weight == .semibold ? .semibold : (style.weight == .medium ? .medium : .regular)
        let native = NSFont.systemFont(ofSize: scaledSize, weight: weight)
        let nativeLineHeight = native.ascender - native.descender + native.leading
        #endif
        let lineBox = style.lineHeight * scale
        let extraLeading = max(0, lineBox - nativeLineHeight)
        content.font(style.monospacedDigit ? font.monospacedDigit() : font)
            .tracking(style.tracking * scale)
            .lineSpacing(extraLeading)
            .padding(.vertical, extraLeading / 2)
            .frame(minHeight: lineBox)
    }
}

private struct DSRowEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    @State private var appeared = false
    let index: Int
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var visible: Bool { appeared || !enabled }

    func body(content: Content) -> some View {
        let role = DSMotion.Role.rowEnter
        let delay = Double(max(0, index)) * role.staggerDelay
        content.opacity(visible ? 1 : 0)
            .animation(enabled ? DSMotion.animation(role, reduceMotion: reduceMotion, property: .opacity)?.delay(delay) : nil, value: visible)
            .offset(y: reduceMotion || visible ? 0 : role.offsetY)
            .animation(enabled ? DSMotion.animation(role, reduceMotion: reduceMotion)?.delay(delay) : nil, value: visible)
            .onAppear { if !appeared { appeared = true } }
    }
}

private struct DSBreathe: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    func body(content: Content) -> some View {
        if enabled && !(reduceMotionOverride ?? systemReduceMotion) {
            PhaseAnimator(DSMotion.Loop.breathe.phases) { phase in
                content.opacity(phase)
            } animation: { _ in DSMotion.Loop.breathe.animation }
        } else { content }
    }
}

private struct DSShimmerValue { var offset: Double }
private struct DSShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var enabled
    func body(content: Content) -> some View {
        if enabled && !(reduceMotionOverride ?? systemReduceMotion) {
            let loop = DSMotion.Loop.shimmer
            content.overlay {
                GeometryReader { geometry in
                    KeyframeAnimator(initialValue: DSShimmerValue(offset: loop.phases[0]), repeating: true) { value in
                        LinearGradient(colors: [.clear, DS.Color.selected, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width)
                            .offset(x: geometry.size.width * CGFloat(value.offset))
                    } keyframes: { _ in
                        KeyframeTrack(\.offset) {
                            SpringKeyframe(loop.phases[1], spring: loop.spring, startVelocity: 0)
                            SpringKeyframe(loop.phases[1], duration: loop.hold, spring: loop.spring, startVelocity: 0)
                            MoveKeyframe(loop.phases[0])
                            SpringKeyframe(loop.phases[0], duration: loop.hold, spring: loop.spring, startVelocity: 0)
                        }
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }.clipped()
        } else { content }
    }
}

extension View {
    /// Keep the CSS box model: padding → background → clipShape → optional shadow.
    func dsSurface(_ color: Color, radius: CGFloat, padding: EdgeInsets? = nil) -> some View {
        self.padding(padding ?? EdgeInsets())
            .background(color)
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
    }
    func dsCard() -> some View {
        dsSurface(DS.Color.raised, radius: DS.Radius.m,
                  padding: EdgeInsets(top: DS.Space.s16, leading: DS.Space.s16, bottom: DS.Space.s16, trailing: DS.Space.s16))
    }
    func dsPill(_ color: Color = DS.Color.surface, padding: EdgeInsets? = nil) -> some View {
        self.padding(padding ?? EdgeInsets()).background(color).clipShape(Capsule(style: .continuous))
    }
    func dsShadow(_ shadow: DS.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    func dsText(_ style: DS.TextStyle) -> some View { modifier(DSTextModifier(style)) }
    @ViewBuilder func dsBarMaterial<S: Shape>(in shape: S) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) { glassEffect(.regular, in: shape) }
        else { background(DS.Material.bar.fallback, in: shape) }
        #else
        background(DS.Material.bar.fallback, in: shape)
        #endif
    }
    func dsFillWidth() -> some View { frame(maxWidth: .infinity, alignment: .leading) }
    func dsPressStyle() -> some View { buttonStyle(DSPressStyle()) }
    func dsBreathe() -> some View { modifier(DSBreathe()) }
    func dsShimmer() -> some View { modifier(DSShimmer()) }
    func dsRowEnter(index: Int) -> some View { modifier(DSRowEntrance(index: index)) }
}
