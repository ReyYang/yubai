import SwiftUI
import YubaiCore

// MARK: Settings row

/// One 52 pt settings row: icon, name, then a value with a chevron or a switch.
struct DSSettingsRow: View {
    enum Accessory {
        case link(String)
        case toggle(Binding<Bool>)
    }
    let icon: DS.Icon?
    let name: String
    var tint: Color = DS.Color.ink2
    let accessory: Accessory
    var separator = true

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            if let icon { DSIconView(icon: icon, size: DS.Size.icon, color: tint) }
            HStack(spacing: DS.Space.s8) {
                Text(name).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink).lineLimit(1)
                Spacer(minLength: DS.Space.s8)
                switch accessory {
                case .link(let value):
                    Text(value).dsText(DS.Font.tLabel).monospacedDigit().foregroundStyle(DS.Color.ink3)
                        .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                    DSIconView(icon: .chevron, size: SettingsSpec.chevron, color: DS.Color.chevron)
                case .toggle(let isOn):
                    DSSwitch(title: name, isOn: isOn, showsTitle: false)
                }
            }
            .padding(.trailing, DS.Space.s12)
            .frame(minHeight: SettingsSpec.row)
            .overlay(alignment: .top) {
                if separator { DS.Color.separator.frame(height: DS.Stroke.hairline) }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The raised card that groups settings rows.
struct DSSettingsCard<Content: View>: View {
    var leading = SettingsSpec.cardInset
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: .zero, content: content)
            .padding(.leading, leading)
            .background(DS.Color.raised)
            .clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
    }
}

// MARK: Brand tile

/// A brand's glyph on its own colour, or a monogram on a stable chart colour.
struct DSBrandTile: View {
    enum Shape { case square, circle }
    let name: String
    var slug: String? = nil
    var size: CGFloat = SettingsSpec.rowTile
    var shape: Shape = .square
    var ring: Color? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let brand = DSBrandCatalog.resolve(name: name, slug: slug)
        let fill = brand.map { $0.color } ?? DSBrandCatalog.fallback(for: name)
        let glyphColor = (brand?.light ?? false) ? DS.Color.ink : DS.Color.onBrand
        ZStack {
            tileShape.fill(fill)
            if let brand {
                Image("Brand-" + brand.slug).renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(glyphColor)
                    .frame(width: size * SettingsSpec.glyphShare, height: size * SettingsSpec.glyphShare)
            } else {
                Text(DSBrandCatalog.monogram(name))
                    .font(.system(size: max(SettingsSpec.monogramMinimum, size * SettingsSpec.monogramShare), weight: .semibold))
                    .foregroundStyle(DS.Color.onBrand)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if brand?.dark == true && scheme == .dark { tileShape.strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
        }
        .overlay {
            if let ring { tileShape.inset(by: -DS.Stroke.focus / 2).stroke(ring, lineWidth: DS.Stroke.focus) }
        }
        .accessibilityHidden(true)
    }

    private var tileShape: AnyInsettableShape {
        switch shape {
        case .square: AnyInsettableShape(RoundedRectangle(cornerRadius: size * SettingsSpec.tileRadius, style: .continuous))
        case .circle: AnyInsettableShape(Circle())
        }
    }
}

/// Type-erased insettable shape so square and circle tiles share one view.
struct AnyInsettableShape: InsettableShape {
    private let base: any InsettableShape
    init(_ base: some InsettableShape) { self.base = base }
    func path(in rect: CGRect) -> Path { base.path(in: rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { AnyInsettableShape(base.inset(by: amount)) }
}

/// Brand lookups are cached: `BrandIcons.match` scans the whole catalog.
@MainActor enum DSBrandCatalog {
    struct Brand {
        let slug: String
        let color: Color
        let dark: Bool
        let light: Bool
    }
    private static var byName: [String: String?] = [:]
    private static var bySlug: [String: Brand] = [:]

    static func resolve(name: String, slug: String?) -> Brand? {
        let found: String?
        if let slug { found = slug }
        else if let cached = byName[name] { found = cached }
        else { found = BrandIcons.match(name)?.slug; byName[name] = found }
        return found.flatMap(brand)
    }

    static func brand(_ slug: String) -> Brand? {
        if let cached = bySlug[slug] { return cached }
        guard let icon = BrandIcons.catalog.first(where: { $0.slug == slug }),
              let rgb = rgb(icon.hex) else { return nil }
        let luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        let brand = Brand(slug: slug, color: Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b),
                          dark: luminance < SettingsSpec.darkBrandLuminance, light: luminance > SettingsSpec.lightBrandLuminance)
        bySlug[slug] = brand
        return brand
    }

    /// Default picker order, matching the canvas.
    static let featured = ["apple", "icloud", "apple-music", "apple-tv", "netflix", "spotify", "youtube", "bilibili",
                           "netease-cloud-music", "notion", "github", "claude", "dropbox", "xiaohongshu"]

    static func search(_ query: String) -> [String] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return featured.filter { brand($0) != nil } }
        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        return BrandIcons.catalog.filter { icon in
            ([icon.name] + icon.keywords).contains { $0.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil).contains(folded) }
        }.map(\.slug)
    }

    static func monogram(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? ""
    }

    static func fallback(for name: String) -> Color {
        let palette = [DS.Color.chart1, DS.Color.chart2, DS.Color.chart3, DS.Color.chart4, DS.Color.chart5]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    private static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard let hex, hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
}

// MARK: Share chips

/// The four 「云端能看到」 chips.
struct DSShareChips: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        var on: Bool
    }
    let items: [Item]
    var enabled = true
    var toggle: (String) -> Void = { _ in }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s8), count: SettingsSpec.shareColumns),
                  spacing: DS.Space.s8) {
            ForEach(items) { item in
                Button { toggle(item.id) } label: {
                    HStack(spacing: DS.Space.s4) {
                        DSIconView(icon: item.on ? .done : .close, size: SettingsSpec.shareMark,
                                   color: item.on ? DS.Color.accentInk : DS.Color.ink3)
                        Text(item.title).dsText(DS.Font.tSub).lineLimit(1)
                            .foregroundStyle(item.on ? DS.Color.accentInk : DS.Color.ink3)
                    }
                    .frame(maxWidth: .infinity, minHeight: SettingsSpec.shareChip)
                    .background(item.on ? DS.Color.accentSoft : .clear, in: DS.Shape.pill)
                    .overlay {
                        if !item.on { DS.Shape.pill.strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
                    }
                    .contentShape(DS.Shape.pill)
                }
                .dsPressStyle()
                .disabled(!enabled)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.on ? "能看到" : "看不到")
                .accessibilityAddTraits(item.on ? .isSelected : [])
                .accessibilityIdentifier("cloudShare_" + item.id)
            }
        }
        .opacity(enabled ? 1 : SettingsSpec.disabledOpacity)
    }
}

// MARK: Account type grid

/// 储蓄卡 / 信用卡 / 支付宝 / 微信 / 现金 / 投资.
struct DSTypeGrid: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let icon: DS.Icon
    }
    let items: [Item]
    let selection: String
    var select: (String) -> Void = { _ in }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s8), count: SettingsSpec.typeColumns),
                  spacing: DS.Space.s8) {
            ForEach(items) { item in
                let selected = item.id == selection
                Button { select(item.id) } label: {
                    VStack(spacing: DS.Space.s4) {
                        DSIconView(icon: item.icon, size: SettingsSpec.typeIcon, color: selected ? DS.Color.accentInk : DS.Color.ink2)
                        Text(item.title).dsText(selected ? DS.Font.tSubStrong : DS.Font.tSub)
                            .foregroundStyle(selected ? DS.Color.accentInk : DS.Color.ink2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: SettingsSpec.typeTile)
                    .background(selected ? DS.Color.raised : DS.Color.surface,
                                in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .strokeBorder(selected ? DS.Color.accent : .clear, lineWidth: DS.Stroke.focus)
                    }
                    .contentShape(.rect(cornerRadius: DS.Radius.s, style: .continuous))
                }
                .dsPressStyle()
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("accountType_" + item.id)
            }
        }
    }
}

// MARK: Day grid

/// 1–28 plus 每月最后一天 spanning three columns.
struct DSDayGrid: View {
    let selection: Int?
    var cellHeight = SettingsSpec.dayCell
    var identifier = "cycleDay_"
    var select: (Int) -> Void = { _ in }

    var body: some View {
        Grid(horizontalSpacing: SettingsSpec.dayGap, verticalSpacing: SettingsSpec.dayGap) {
            ForEach(0..<DSLayout.dayGridRows, id: \.self) { row in
                GridRow {
                    ForEach(1...DSLayout.weekdays, id: \.self) { column in
                        cell(row * DSLayout.weekdays + column)
                    }
                }
            }
            GridRow {
                lastDay.gridCellColumns(SettingsSpec.lastDaySpan)
            }
        }
    }

    private func cell(_ day: Int) -> some View {
        let selected = selection == day
        return Button { select(day) } label: {
            Text("\(day)").dsText(selected ? DS.Font.tTitle : DS.Font.tBody).monospacedDigit()
                .foregroundStyle(selected ? DS.Color.onAccent : DS.Color.ink)
                .frame(maxWidth: .infinity, minHeight: cellHeight)
                .background(selected ? DS.Color.accent : DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                .contentShape(.rect(cornerRadius: DS.Radius.s, style: .continuous))
        }
        .dsPressStyle()
        .accessibilityLabel("\(day) 日")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier + "\(day)")
    }

    private var lastDay: some View {
        let selected = selection == CycleStart.lastDay
        return Button { select(CycleStart.lastDay) } label: {
            Text("每月最后一天").dsText(selected ? DS.Font.tLabelStrong : DS.Font.tPill)
                .foregroundStyle(selected ? DS.Color.onAccent : DS.Color.ink)
                .frame(maxWidth: .infinity, minHeight: cellHeight)
                .background(selected ? DS.Color.accent : DS.Color.surface, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                .contentShape(.rect(cornerRadius: DS.Radius.s, style: .continuous))
        }
        .dsPressStyle()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier + "last")
    }
}

// MARK: Split bar

/// 先攒 share against what is left to spend.
struct DSSplitBar: View {
    let share: Double
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - OverviewSpec.barGap)
            let filled = width * min(1, max(0, share))
            HStack(spacing: OverviewSpec.barGap) {
                UnevenRoundedRectangle(topLeadingRadius: SettingsSpec.barRadius, bottomLeadingRadius: SettingsSpec.barRadius, style: .continuous)
                    .fill(DS.Color.accent).frame(width: filled)
                UnevenRoundedRectangle(bottomTrailingRadius: SettingsSpec.barRadius, topTrailingRadius: SettingsSpec.barRadius, style: .continuous)
                    .fill(DS.Color.track)
            }
        }
        .frame(height: SettingsSpec.previewBar)
        .accessibilityHidden(true)
    }
}
