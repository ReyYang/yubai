import SwiftUI
import YubaiCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum YubaiColor {
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
    static let amberStrong = adaptive(0x5c3e16, 0xf3ddb3)
    static let amberDot = adaptive(0xb88443, 0xd2a867)
    static let amberMark = adaptive(0xd2a867, 0xc9a061)
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
    func yubaiFont(_ style: YubaiFont.Style, weight: Font.Weight? = nil) -> some View { modifier(YubaiTextStyle(style, weight: weight)) }
}

enum YubaiSpace {
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space18: CGFloat = 18
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
}

enum YubaiRadius {
    static let bar: CGFloat = 4
    static let control: CGFloat = 14
    static let tile: CGFloat = 0.224
    static let row: CGFloat = 18
    static let card: CGFloat = 22
    static let tabbar: CGFloat = 24
    static let full: CGFloat = 999
}

enum YubaiSize {
    static let tapMin: CGFloat = 44
    static let headerHeight: CGFloat = 48
    static let iconButton: CGFloat = 40
    static let buttonHeight: CGFloat = 52
    static let chipHeight: CGFloat = 32
    static let pillHeight: CGFloat = 28
    static let tabbarHeight: CGFloat = 62
    static let barMax: CGFloat = 24
    static let lineWidth: CGFloat = 2
    static let marker: CGFloat = 8
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

enum YubaiMotion {
    static let durationInstant = 0.100
    static let durationQuick = 0.160
    static let durationStandard = 0.240
    static let durationWater = 0.320
    static let durationStagger = 0.060
    static let durationThink = 1.600

    static func easeOut(duration: Double) -> Animation { .timingCurve(0.2, 0, 0, 1, duration: duration) }
    static func easeIn(duration: Double) -> Animation { .timingCurve(0.4, 0, 1, 1, duration: duration) }
    static func easeInOut(duration: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: duration) }
    static let instant = easeInOut(duration: durationInstant)
    static let quick = easeInOut(duration: durationQuick)
    static let chartGrowth = easeOut(duration: durationStandard)
    static let waterRise = easeOut(duration: durationWater)
    static let stagger = easeOut(duration: durationStagger)
    static let thinkCycle = easeInOut(duration: durationThink)

    static func number(reduceMotion: Bool) -> Animation { quick }
    static func chart(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : chartGrowth }
    static func water(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : waterRise }
    static func think(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : thinkCycle }
    static func toastIn(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : chartGrowth }
    static func toastOut(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : easeIn(duration: durationQuick) }
    static func toastTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .identity }
        return .asymmetric(insertion: .offset(y: YubaiSpace.space8).combined(with: .opacity).animation(toastIn(reduceMotion: false)), removal: .opacity.animation(toastOut(reduceMotion: false)))
    }
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

private struct NumberCrossfade<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    var enabled: Bool
    func body(content: Content) -> some View {
        content.contentTransition(.opacity).animation(enabled ? YubaiMotion.number(reduceMotion: reduceMotion) : nil, value: value)
    }
}

extension View {
    func numberCrossfade<Value: Equatable>(value: Value, enabled: Bool = true) -> some View { modifier(NumberCrossfade(value: value, enabled: enabled)) }
}

struct ChartGrow<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var appeared = false
    private let appearance: Binding<Bool>?
    let content: (Double) -> Content
    init(appeared: Binding<Bool>? = nil, @ViewBuilder content: @escaping (Double) -> Content) {
        self.appearance = appeared; self.content = content
        _progress = State(initialValue: appeared?.wrappedValue == true ? 1 : 0)
    }
    var body: some View {
        content(reduceMotion ? 1 : progress)
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .onAppear {
                guard !appeared && appearance?.wrappedValue != true else { finish(); return }
                appeared = true
                if let appearance { appearance.wrappedValue = true }
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

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.button)
            .padding(.horizontal, YubaiSpace.space24).padding(.vertical, YubaiSpace.space12)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight)
            .foregroundStyle(isEnabled ? YubaiColor.onBrand : YubaiColor.labelSecondary)
            .background(isEnabled ? YubaiColor.brand : Color.clear, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.button, weight: .regular)
            .padding(.horizontal, YubaiSpace.space24).padding(.vertical, YubaiSpace.space12)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight)
            .foregroundStyle(isEnabled ? YubaiColor.label : YubaiColor.labelSecondary)
            .background(isEnabled ? YubaiColor.card : Color.clear, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1).animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}

struct Page<Content: View>: View {
    let content: Content
    var spacing: CGFloat
    var hasTabBar: Bool
    init(spacing: CGFloat = YubaiSpace.space12, hasTabBar: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content(); self.spacing = spacing; self.hasTabBar = hasTabBar
    }
    private var bottomPadding: CGFloat {
        #if os(iOS)
        if hasTabBar { return 106 }
        #endif
        return YubaiSpace.space24
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, YubaiSpace.space18).padding(.top, YubaiSpace.space20)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label).background(YubaiColor.canvas)
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
        content.padding(.horizontal, style == .compact ? YubaiSpace.space16 : YubaiSpace.space18)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(YubaiColor.label)
            .background(background, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
    }
    private var verticalPadding: CGFloat {
        switch style {
        case .standard: YubaiSpace.space18
        case .list: YubaiSpace.space4
        case .compact: YubaiSpace.space16
        }
    }
}

/// A single list surface with lazy rows, including large ledgers and matching candidates.
struct CardRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let rows: Data
    let content: (Data.Element) -> Row
    init(_ rows: Data, @ViewBuilder content: @escaping (Data.Element) -> Row) { self.rows = rows; self.content = content }
    var body: some View {
        Card(style: .list) {
            LazyVStack(spacing: 0) {
                ForEach(rows) { row in
                    content(row).frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight, alignment: .leading)
                    if row.id != rows.last?.id { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
                }
            }
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
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: YubaiSpace.space10))
        layout {
            VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                Text(title).yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.label)
                if let subtitle { Text(subtitle).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted) }
            }
            if amount != nil || meta != nil {
                if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space6) }
                if let amount { Text(amount).yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.label) }
                if let meta { Text(meta).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
            }
        }
    }
}

struct AmountLabel: View {
    enum Role {
        case hero, display, input, large, amount, small, chart
        var font: YubaiFont.Style {
            switch self {
            case .hero: YubaiFont.amountHero
            case .display: YubaiFont.amountDisplay
            case .input: YubaiFont.amountInput
            case .large: YubaiFont.amountLarge
            case .amount: YubaiFont.amount
            case .small: YubaiFont.amountSmall
            case .chart: YubaiFont.chartValue
            }
        }
    }
    enum Sign { case automatic, inflow, outflow, none }
    @Environment(\.dynamicTypeSize) private var textSize
    let cents: Int64
    var large = false
    var hide = false
    var role: Role? = nil
    var sign: Sign = .automatic
    var currency: Bool? = nil
    var fractionDigits: Int? = nil
    private var resolvedRole: Role { role ?? (large ? .display : .amount) }
    private var decimals: Int {
        if let fractionDigits { return fractionDigits == 0 ? 0 : 2 }
        return resolvedRole == .amount || resolvedRole == .input ? 2 : 0
    }
    private var text: String { Self.text(cents, sign: sign, currency: currency ?? (resolvedRole == .hero), decimals: decimals) }
    var body: some View {
        let font = textSize.isAccessibilitySize && (resolvedRole == .hero || resolvedRole == .display) ? YubaiFont.amountLarge : resolvedRole.font
        Text(hide ? "••••" : text).yubaiFont(font).foregroundStyle(YubaiColor.label)
            .minimumScaleFactor(0.55).lineLimit(1)
            .accessibilityLabel(hide ? "金额已隐藏" : Self.text(cents, sign: sign, currency: currency ?? (resolvedRole == .hero), decimals: 2))
            .numberCrossfade(value: cents, enabled: !hide).animation(nil, value: hide)
    }
    fileprivate static func text(_ cents: Int64, sign: Sign = .automatic, currency: Bool = false, decimals: Int = 0) -> String {
        let magnitude = cents.magnitude
        let units = magnitude / 100 + (decimals == 0 && magnitude % 100 >= 50 ? 1 : 0)
        let digits = String(units)
        let grouped = digits.enumerated().map { index, digit in (index > 0 && (digits.count - index) % 3 == 0 ? "," : "") + String(digit) }.joined()
        let prefix: String
        switch sign { case .automatic: prefix = cents < 0 ? "−" : ""; case .inflow: prefix = "+"; case .outflow: prefix = "−"; case .none: prefix = "" }
        let fraction = magnitude % 100
        let currencyText = currency ? "¥" : ""
        let fractionText = fraction < 10 ? "0" + String(fraction) : String(fraction)
        let suffix = decimals == 0 ? "" : "." + fractionText
        return prefix + currencyText + grouped + suffix
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
        HStack(spacing: YubaiSpace.space6) {
            if showsDot { Circle().fill(variant == .amber ? YubaiColor.amberDot : YubaiColor.brandMark).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(text).yubaiFont(height < YubaiSize.pillHeight ? YubaiFont.meta : YubaiFont.caption)
            if showsChevron { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta, weight: .medium).accessibilityHidden(true) }
        }.padding(.horizontal, height < YubaiSize.pillHeight ? YubaiSpace.space8 : YubaiSpace.space12)
            .padding(.vertical, YubaiSpace.space2).frame(minHeight: height).foregroundStyle(ink).background(background, in: Capsule())
    }
}

struct EntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var entry: Entry
    var hideAmount = false
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "M月d日"
        return formatter
    }()
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space12))
        layout {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(entry.title).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label).lineLimit(textSize.isAccessibilitySize ? nil : 1)
                Text("\(dateText) · \(entry.category) · \(store.current.accountName(entry.accountID))")
                    .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).lineLimit(textSize.isAccessibilitySize ? nil : 1)
                if entry.nature.uncertain { Pill(text: "待明确", variant: .amber, height: 20) }
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space6) }
            AmountLabel(cents: entry.amount, hide: hideAmount, sign: entry.nature.inflow ? .inflow : .outflow)
                .layoutPriority(1)
        }.padding(.vertical, YubaiSpace.space8).frame(minHeight: YubaiSize.buttonHeight).contentShape(Rectangle())
    }
    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(entry.date) { return "今天 " + entry.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))) }
        if calendar.isDateInYesterday(entry.date) { return "昨天" }
        return Self.dateFormatter.string(from: entry.date)
    }
}

struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("完成") { dismiss() }.yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.brandInk).frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("closeSheet") }
}

struct BrandMark: View {
    enum Variant { case tile, mark }
    var size: CGFloat = 43
    var variant: Variant = .tile
    var color: Color? = nil
    var bands = 3
    var body: some View {
        let geometry = WaterGeometry(size: size, variant: variant, bands: bands)
        let ink = color ?? (variant == .tile ? YubaiColor.iconInk : YubaiColor.label)
        ZStack {
            if variant == .tile { RoundedRectangle(cornerRadius: size * YubaiRadius.tile).fill(YubaiColor.iconTile) }
            MarkCircle(radius: geometry.ringRadius).stroke(ink, lineWidth: geometry.stroke * size / 100)
            ForEach(0..<geometry.count, id: \.self) { index in
                WaterBand(index: index, geometry: geometry).fill(ink).clipShape(MarkCircle(radius: geometry.clipRadius))
            }
        }.frame(width: size, height: size).accessibilityElement(children: .ignore).accessibilityLabel("余白")
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
    init(filledBands: Int, totalBands: Int = 6, size: CGFloat = 168, showsTile: Bool = false) {
        self.filledBands = filledBands; self.totalBands = totalBands; self.size = size; self.showsTile = showsTile
    }
    init(progress: Double, totalBands: Int = 6, size: CGFloat = 168, showsTile: Bool = false) {
        let geometry = WaterGeometry(size: size, variant: .tile, bands: totalBands)
        let count = max(1, geometry.count)
        let clampedProgress: Double = progress.isFinite ? min(1, max(0, progress)) : 0
        let filledBands = Int((clampedProgress * Double(count)).rounded(.down))
        self.init(filledBands: filledBands, totalBands: count, size: size, showsTile: showsTile)
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
                    .offset(y: reduceMotion || index < visibleBands ? 0 : size * 0.4)
                    .opacity(index < (reduceMotion ? target : visibleBands) ? 1 : 0)
                    .animation(YubaiMotion.water(reduceMotion: reduceMotion)?.delay(Double(min(index, 5)) * YubaiMotion.durationStagger), value: visibleBands)
                    .clipShape(MarkCircle(radius: geometry.clipRadius))
            }
        }.frame(width: size, height: size)
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .accessibilityElement(children: .ignore).accessibilityLabel("水位，共 \(geometry.count) 格，已填 \(target) 格")
            .onAppear { if appeared { finish() } else { appeared = true; visibleBands = target } }
            .onChange(of: target) { _, value in visibleBands = value }
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
            .accessibilityElement(children: .ignore).accessibilityLabel(thinking ? "余白助手正在思考" : "余白助手")
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
    var available: Int64
    var payable: Int64
    var reserved: Int64
    var attentionCount = 0
    var hideAmount = false
    var title = "还能自在支配"
    var onDetails: (() -> Void)? = nil
    var onAttention: (() -> Void)? = nil
    var body: some View {
        ChartGrow { progress in VStack(alignment: .leading, spacing: YubaiSpace.space16) {
            if let onDetails { Button(action: onDetails) { amounts(progress) }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("fundsFormula").accessibilityHint("打开计算依据") }
            else { amounts(progress) }
            if attentionCount > 0 {
                if let onAttention {
                    Button(action: onAttention) { attention }.buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin)
                } else { attention }
            }
        }.foregroundStyle(YubaiColor.label).animation(nil, value: hideAmount) }
    }
    private func amounts(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space10) {
            summary
            if !hideAmount {
                composition(progress).padding(.top, YubaiSpace.space8)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: YubaiSpace.space10) { legends }
                    VStack(alignment: .leading, spacing: YubaiSpace.space6) { legends }
                }
            }
        }.contentShape(Rectangle())
    }
    @ViewBuilder private var legends: some View {
        legend("余白", available, YubaiColor.brand)
        legend("要付", payable, YubaiColor.neutralStrong)
        legend("预留", reserved, YubaiColor.neutralSoft)
    }
    private var summary: some View {
        HStack(alignment: .bottom, spacing: YubaiSpace.space12) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(title).yubaiFont(YubaiFont.heroLabel)
                AmountLabel(cents: available, hide: hideAmount, role: .hero)
            }
            Spacer(minLength: 0)
            BrandMark(size: 48).padding(.bottom, YubaiSpace.space6).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private var attention: some View { Pill(text: "\(attentionCount) 件小事需要留意", variant: .amber, showsChevron: onAttention != nil) }
    private func composition(_ progress: Double) -> some View {
        let values = [max(0, Double(available)), max(0, Double(payable)), max(0, Double(reserved))]
        let total = values.reduce(0, +)
        let colors = [YubaiColor.brand, YubaiColor.neutralStrong, YubaiColor.neutralSoft]
        let indices = values.indices.filter { values[$0] > 0 }
        return GeometryReader { geometry in
            let width = max(0, geometry.size.width - CGFloat(max(0, indices.count - 1)) * YubaiSpace.space2)
            HStack(spacing: YubaiSpace.space2) {
                ForEach(indices, id: \.self) { index in
                    let ratio: Double = total > 0 ? values[index] / total : 0
                    let animatedRatio: Double = ratio * progress
                    colors[index].frame(width: width * CGFloat(animatedRatio))
                }
            }.frame(maxWidth: .infinity, alignment: .leading).background(total == 0 ? YubaiColor.neutralSoft : Color.clear).clipShape(Capsule())
        }.frame(height: YubaiSpace.space12 + YubaiSpace.space2).accessibilityElement(children: .ignore)
            .accessibilityLabel("余白 \(AmountLabel.text(available))，要付 \(AmountLabel.text(payable))，预留 \(AmountLabel.text(reserved))")
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
                    .padding(YubaiSpace.space16).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            case .attention:
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(text).yubaiFont(YubaiFont.row, weight: .medium).foregroundStyle(YubaiColor.amberStrong)
                    if let detail { Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberInk) }
                    if action != nil || secondaryAction != nil {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: YubaiSpace.space8) { actions }
                            VStack(alignment: .leading, spacing: YubaiSpace.space4) { actions }
                        }.padding(.top, YubaiSpace.space6)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.space16)
                    .background(YubaiColor.amberTint, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            case .reminder, .inline:
                HStack(spacing: YubaiSpace.space8) {
                    Circle().fill(YubaiColor.amberDot).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(text).yubaiFont(YubaiFont.callout).foregroundStyle(style == .reminder ? YubaiColor.amberStrong : YubaiColor.labelMuted)
                    Spacer(minLength: YubaiSpace.space4)
                    if let action, let onAction {
                        Button(action, action: onAction).yubaiFont(YubaiFont.callout).foregroundStyle(style == .reminder ? YubaiColor.amberInk : YubaiColor.brandInk).frame(minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle())
                    }
                }.padding(.horizontal, YubaiSpace.space16).frame(minHeight: style == .reminder ? YubaiSize.tapMin : 58)
                    .background(style == .reminder ? YubaiColor.amberTint : Color.clear, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var actions: some View {
        if let action, let onAction {
            Button(action, action: onAction).yubaiFont(YubaiFont.callout, weight: .medium).padding(.horizontal, YubaiSpace.space12)
                .frame(minHeight: YubaiSize.chipHeight).foregroundStyle(YubaiColor.amberStrong).background(YubaiColor.raised, in: Capsule())
                .frame(minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle())
        }
        if let secondaryAction, let onSecondaryAction {
            Button(secondaryAction, action: onSecondaryAction).yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.space12)
                .frame(minHeight: YubaiSize.tapMin).foregroundStyle(YubaiColor.amberInk).buttonStyle(PressButtonStyle())
        }
    }
}

struct EmptyState: View {
    var icon: String
    var title: String
    var message: String
    var action: String? = nil
    var onAction: (() -> Void)?
    init(_ icon: String, _ title: String, _ message: String, action: String? = nil, onAction: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.message = message; self.action = action; self.onAction = onAction
    }
    var body: some View {
        VStack(spacing: YubaiSpace.space16) {
            Circle().stroke(YubaiColor.borderDashed, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])).frame(width: 120, height: 120).accessibilityHidden(true)
            VStack(spacing: YubaiSpace.space6) {
                Text(title).yubaiFont(YubaiFont.lead).foregroundStyle(YubaiColor.label)
                Text(message).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).frame(maxWidth: 410)
            }.multilineTextAlignment(.center)
            if let action, let onAction { Button(action, action: onAction).buttonStyle(PrimaryButtonStyle()) }
        }.frame(maxWidth: .infinity).padding(.vertical, YubaiSpace.space24).padding(.horizontal, YubaiSpace.space18)
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
        Group { if visible { surface } }
            .transaction { if reduceMotion { $0.animation = nil } }
            .task(id: text) {
                withAnimation(YubaiMotion.toastIn(reduceMotion: reduceMotion)) { visible = true }
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                withAnimation(YubaiMotion.toastOut(reduceMotion: reduceMotion)) { visible = false; onDismiss?() }
            }
    }
    private var surface: some View {
        HStack(spacing: YubaiSpace.space12) {
            Text(text).yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).frame(maxWidth: .infinity, alignment: .leading)
            if let onUndo {
                Button(undoTitle, action: onUndo).yubaiFont(YubaiFont.row, weight: .medium).foregroundStyle(YubaiColor.brandInk)
                    .padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle())
            }
            if let onDismiss {
                Button { withAnimation(YubaiMotion.toastOut(reduceMotion: reduceMotion)) { visible = false; onDismiss() } } label: {
                    Image(systemName: "xmark").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("关闭提示")
            }
        }.padding(.leading, YubaiSpace.space18).padding(.trailing, YubaiSpace.space8).padding(.vertical, YubaiSpace.space4)
            .frame(minHeight: YubaiSize.buttonHeight).background(YubaiColor.raised, in: Capsule()).yubaiShadow(YubaiShadow.float)
            .padding(.horizontal, YubaiSpace.space18).padding(.bottom, YubaiSpace.space12)
            .transition(YubaiMotion.toastTransition(reduceMotion: reduceMotion))
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
        self.formStyle(.grouped).scrollContentBackground(.hidden).background(YubaiColor.canvas)
            .environment(\.defaultMinListRowHeight, YubaiSize.buttonHeight).scrollDismissesKeyboard(.interactively)
            .yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label).tint(YubaiColor.brand).buttonStyle(.automatic)
    }
    func yubaiNavigation() -> some View {
        self.background(YubaiColor.canvas).tint(YubaiColor.brandInk)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(YubaiColor.canvas, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
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
    @Environment(AppStore.self) private var store
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: YubaiSpace.space24) {
                BrandMark(size: 88).padding(.top, YubaiSpace.space24)
                Text("余白").yubaiFont(YubaiFont.welcome)
                Text("把钱理清，\n把生活留给自己。").yubaiFont(YubaiFont.lead).fixedSize(horizontal: false, vertical: true)
                Text("余额不等于可花的钱。余白把散落的账单、未来要付的钱和真正想做的事，放在同一处。") .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted)
                VStack(alignment: .leading, spacing: YubaiSpace.space16) {
                    feature("wallet.bifold", "一份可信的账本", "导入微信、支付宝与银行卡账单，自动整理，随时纠正。")
                    feature("calendar", "从今天安排未来", "先留出房租、还款和目标，再看此刻有多少余地。")
                    feature("lock.shield", "数据留在你手里", "无需注册，离线可用，可导出和加密备份。")
                }.padding(.vertical, YubaiSpace.space10)
                Button("开始我的账本") { store.update("建立账本") { $0.preferences.onboardingComplete = true }; store.sheet = .account(nil) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("startLedger")
                Button("先看看示例账本") { store.startDemo() }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("openDemo")
                Text("示例数据与你的账本完全分开。所有示例金额都是虚构的。") .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            }.frame(maxWidth: 610, alignment: .leading).frame(maxWidth: .infinity).padding(.bottom, YubaiSpace.space24)
        }.yubaiNavigation().toolbar { Button("恢复备份") { store.sheet = .backup } }
    }
    func feature(_ symbol: String, _ title: String, _ text: String) -> some View { HStack(alignment: .top, spacing: YubaiSpace.space12) { Circle().fill(YubaiColor.brandMark).frame(width: YubaiSize.marker, height: YubaiSize.marker).padding(.top, YubaiSpace.space6).accessibilityHidden(true); VStack(alignment: .leading, spacing: YubaiSpace.space4) { Text(title).yubaiFont(YubaiFont.rowTitle); Text(text).yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.labelMuted).fixedSize(horizontal: false, vertical: true) } } }
}
