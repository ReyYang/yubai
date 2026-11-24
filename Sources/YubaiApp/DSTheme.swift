// 由 scripts/generate-design-tokens.py 从 design-tokens.json 生成，不要手改。
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum DS {
    enum Color {
        /// 页面底。整个 App 只有这一种底色。
        static let bg: SwiftUI.Color = DS.adaptive(0xF5F1E5, 0x1F1B14, lightAlpha: 1, darkAlpha: 1)
        /// 「一块」：胶囊、按钮、空格子、问余白条、键盘托盘里的块、没选中的分类圆。
        static let surface: SwiftUI.Color = DS.adaptive(0xEDE6D3, 0x2A251C, lightAlpha: 1, darkAlpha: 1)
        /// 浮起的一层：设置分组、浮动账单卡、弹出菜单、展开的抽屉。
        static let raised: SwiftUI.Color = DS.adaptive(0xFEFBEA, 0x353026, lightAlpha: 1, darkAlpha: 1)
        /// 分段控件的选中格；就地展开里当前选中的那一项。
        static let selected: SwiftUI.Color = DS.adaptive(0xFFFFFF, 0x4A4436, lightAlpha: 1, darkAlpha: 1)
        /// 列表行之间的细线，从文字开始画，不穿过图标。
        static let separator: SwiftUI.Color = DS.adaptive(0xE0D8C9, 0x3A3428, lightAlpha: 1, darkAlpha: 1)
        /// 主文字和脊柱数字（金额、还剩、几天后）。
        static let ink: SwiftUI.Color = DS.adaptive(0x382F1F, 0xE6DECB, lightAlpha: 1, darkAlpha: 1)
        /// 列表里的名字等次要正文。
        static let ink2: SwiftUI.Color = DS.adaptive(0x5A5040, 0xC2B8A3, lightAlpha: 1, darkAlpha: 1)
        /// 小字：日期、单位、总额、说明行。最小 11pt。
        static let ink3: SwiftUI.Color = DS.adaptive(0x6A604F, 0xA89D88, lightAlpha: 1, darkAlpha: 1)
        /// 列表行里的线性图标（ink-3 再淡一档，代替网页的 opacity .75）。
        static let iconQuiet: SwiftUI.Color = DS.adaptive(0x6A604F, 0xA89D88, lightAlpha: 191 / 255.0, darkAlpha: 191 / 255.0)
        /// 箭头、拖动把手、最弱的图标。
        static let chevron: SwiftUI.Color = DS.adaptive(0xB9AC93, 0x6B604D, lightAlpha: 1, darkAlpha: 1)
        /// 下一步：记一笔胶囊、键盘上的记下。一屏只有一个。
        static let accent: SwiftUI.Color = DS.adaptive(0x557F53, 0x86A884, lightAlpha: 1, darkAlpha: 1)
        /// accent 上的字和图标。
        static let onAccent: SwiftUI.Color = DS.adaptive(0xFFFFFF, 0x1F1B14, lightAlpha: 1, darkAlpha: 1)
        /// 绿色的字：+ 添加小类、今天的小圆点、文字按钮。
        static let accentInk: SwiftUI.Color = DS.adaptive(0x476846, 0xCFE0C2, lightAlpha: 1, darkAlpha: 1)
        /// 选中的分类圆、展开抽屉的图标方块、正面的结果条。
        static let accentSoft: SwiftUI.Color = DS.adaptive(0xD6E2CC, 0x34422F, lightAlpha: 1, darkAlpha: 1)
        /// 快用完的进度条。
        static let warn: SwiftUI.Color = DS.adaptive(0xB88443, 0xD2A867, lightAlpha: 1, darkAlpha: 1)
        /// 要你看一眼的字：快花完、比上期多、待报销、待 AA。
        static let warnInk: SwiftUI.Color = DS.adaptive(0x7A5320, 0xE9CF9F, lightAlpha: 1, darkAlpha: 1)
        /// 琥珀卡和标签的底。
        static let warnSoft: SwiftUI.Color = DS.adaptive(0xEFE1C4, 0x4A3C24, lightAlpha: 1, darkAlpha: 1)
        /// 琥珀卡里进度条的底。
        static let warnTrack: SwiftUI.Color = DS.adaptive(0xE2CFA8, 0x5A4A2E, lightAlpha: 1, darkAlpha: 1)
        /// 进度条和日线柱的底。
        static let track: SwiftUI.Color = DS.adaptive(0xDDD2BE, 0x4A4335, lightAlpha: 1, darkAlpha: 1)
        /// 平常的进度条。
        static let fillCalm: SwiftUI.Color = DS.adaptive(0x8FA98A, 0x5E7A5B, lightAlpha: 1, darkAlpha: 1)
        /// 键盘数字键。
        static let key: SwiftUI.Color = DS.adaptive(0xFEFBEA, 0x4A4436, lightAlpha: 1, darkAlpha: 1)
        /// 键盘功能键（⌫ + −）。
        static let keyFn: SwiftUI.Color = DS.adaptive(0xD6CAAF, 0x353026, lightAlpha: 1, darkAlpha: 1)
        /// 键盘托盘。
        static let tray: SwiftUI.Color = DS.adaptive(0xE4DAC4, 0x2A251C, lightAlpha: 1, darkAlpha: 1)
        /// 弹窗顶部的拖动条。
        static let grabber: SwiftUI.Color = DS.adaptive(0xD8CFBE, 0x4A4335, lightAlpha: 1, darkAlpha: 1)
        /// 环图第 1 段（最大的一类）。
        static let chart1: SwiftUI.Color = DS.adaptive(0x476846, 0xCFE0C2, lightAlpha: 1, darkAlpha: 1)
        /// 环图第 2 段。
        static let chart2: SwiftUI.Color = DS.adaptive(0x8FAE88, 0x86A884, lightAlpha: 1, darkAlpha: 1)
        /// 环图第 3 段。
        static let chart3: SwiftUI.Color = DS.adaptive(0xA9BE9C, 0x5E7A5B, lightAlpha: 1, darkAlpha: 1)
        /// 环图第 4 段。
        static let chart4: SwiftUI.Color = DS.adaptive(0xC9BCA3, 0x6B604D, lightAlpha: 1, darkAlpha: 1)
        /// 环图其余。
        static let chart5: SwiftUI.Color = DS.adaptive(0xDDD2BE, 0x4A4335, lightAlpha: 1, darkAlpha: 1)
        /// 弹窗和浮动卡后面的遮罩。
        static let scrim: SwiftUI.Color = DS.adaptive(0x382F1F, 0x000000, lightAlpha: 82 / 255.0, darkAlpha: 128 / 255.0)
        /// 阴影颜色（不透明度在 shadow 里给）。
        static let shadowInk: SwiftUI.Color = DS.adaptive(0x4A4030, 0x000000, lightAlpha: 1, darkAlpha: 1)

        struct Sample: Identifiable {
            let name: String
            let lightHex: String
            let darkHex: String
            let color: SwiftUI.Color
            var id: String { name }
        }
        static let all: [Sample] = [
            Sample(name: "bg", lightHex: "#F5F1E5", darkHex: "#1F1B14", color: bg),
            Sample(name: "surface", lightHex: "#EDE6D3", darkHex: "#2A251C", color: surface),
            Sample(name: "raised", lightHex: "#FEFBEA", darkHex: "#353026", color: raised),
            Sample(name: "selected", lightHex: "#FFFFFF", darkHex: "#4A4436", color: selected),
            Sample(name: "separator", lightHex: "#E0D8C9", darkHex: "#3A3428", color: separator),
            Sample(name: "ink", lightHex: "#382F1F", darkHex: "#E6DECB", color: ink),
            Sample(name: "ink-2", lightHex: "#5A5040", darkHex: "#C2B8A3", color: ink2),
            Sample(name: "ink-3", lightHex: "#6A604F", darkHex: "#A89D88", color: ink3),
            Sample(name: "icon-quiet", lightHex: "#6A604FBF", darkHex: "#A89D88BF", color: iconQuiet),
            Sample(name: "chevron", lightHex: "#B9AC93", darkHex: "#6B604D", color: chevron),
            Sample(name: "accent", lightHex: "#557F53", darkHex: "#86A884", color: accent),
            Sample(name: "on-accent", lightHex: "#FFFFFF", darkHex: "#1F1B14", color: onAccent),
            Sample(name: "accent-ink", lightHex: "#476846", darkHex: "#CFE0C2", color: accentInk),
            Sample(name: "accent-soft", lightHex: "#D6E2CC", darkHex: "#34422F", color: accentSoft),
            Sample(name: "warn", lightHex: "#B88443", darkHex: "#D2A867", color: warn),
            Sample(name: "warn-ink", lightHex: "#7A5320", darkHex: "#E9CF9F", color: warnInk),
            Sample(name: "warn-soft", lightHex: "#EFE1C4", darkHex: "#4A3C24", color: warnSoft),
            Sample(name: "warn-track", lightHex: "#E2CFA8", darkHex: "#5A4A2E", color: warnTrack),
            Sample(name: "track", lightHex: "#DDD2BE", darkHex: "#4A4335", color: track),
            Sample(name: "fill-calm", lightHex: "#8FA98A", darkHex: "#5E7A5B", color: fillCalm),
            Sample(name: "key", lightHex: "#FEFBEA", darkHex: "#4A4436", color: key),
            Sample(name: "key-fn", lightHex: "#D6CAAF", darkHex: "#353026", color: keyFn),
            Sample(name: "tray", lightHex: "#E4DAC4", darkHex: "#2A251C", color: tray),
            Sample(name: "grabber", lightHex: "#D8CFBE", darkHex: "#4A4335", color: grabber),
            Sample(name: "chart-1", lightHex: "#476846", darkHex: "#CFE0C2", color: chart1),
            Sample(name: "chart-2", lightHex: "#8FAE88", darkHex: "#86A884", color: chart2),
            Sample(name: "chart-3", lightHex: "#A9BE9C", darkHex: "#5E7A5B", color: chart3),
            Sample(name: "chart-4", lightHex: "#C9BCA3", darkHex: "#6B604D", color: chart4),
            Sample(name: "chart-5", lightHex: "#DDD2BE", darkHex: "#4A4335", color: chart5),
            Sample(name: "scrim", lightHex: "#382F1F52", darkHex: "#00000080", color: scrim),
            Sample(name: "shadow-ink", lightHex: "#4A4030", darkHex: "#000000", color: shadowInk),
        ]
    }

    struct TextStyle {
        enum Family: Equatable {
            case text, num
            var design: SwiftUI.Font.Design {
                switch self {
                case .text: .default
                case .num: .rounded
                }
            }
        }
        let size: CGFloat
        let lineHeight: CGFloat
        let weight: SwiftUI.Font.Weight
        let tracking: CGFloat
        let family: Family
        let relativeTo: SwiftUI.Font.TextStyle
        let monospacedDigit: Bool
        var design: SwiftUI.Font.Design { family.design }
    }

    enum Font {
        /// 记一笔里正在输入的金额。
        static let nEntry = TextStyle(size: 54, lineHeight: 60, weight: .semibold, tracking: -1, family: .num, relativeTo: .largeTitle, monospacedDigit: true)
        /// 浮动账单卡的金额。
        static let nDetail = TextStyle(size: 44, lineHeight: 52, weight: .semibold, tracking: -1, family: .num, relativeTo: .largeTitle, monospacedDigit: true)
        /// 每页唯一的主数字：还能花、花了、流动现金、账户余额。
        static let nHero = TextStyle(size: 40, lineHeight: 46, weight: .semibold, tracking: -1, family: .num, relativeTo: .largeTitle, monospacedDigit: true)
        /// 琥珀卡里的还剩。
        static let nTile = TextStyle(size: 26, lineHeight: 30, weight: .semibold, tracking: -0.5, family: .num, relativeTo: .title, monospacedDigit: true)
        /// 键盘数字。
        static let nKey = TextStyle(size: 22, lineHeight: 26, weight: .medium, tracking: 0, family: .num, relativeTo: .title2, monospacedDigit: true)
        /// 预算列表的脊柱（还剩多少）。
        static let nSpineLg = TextStyle(size: 20, lineHeight: 26, weight: .semibold, tracking: -0.3, family: .num, relativeTo: .title3, monospacedDigit: true)
        /// 列表脊柱：账单金额、账户余额、几天后扣。
        static let nSpine = TextStyle(size: 18, lineHeight: 22, weight: .semibold, tracking: -0.2, family: .num, relativeTo: .headline, monospacedDigit: true)
        /// 导航标题、弹窗标题、分类抽屉的大类名、完成按钮。
        static let tTitle = TextStyle(size: 17, lineHeight: 22, weight: .semibold, tracking: 0, family: .text, relativeTo: .headline, monospacedDigit: false)
        /// 列表名字（ink-2）、用途。
        static let tBody = TextStyle(size: 16, lineHeight: 22, weight: .regular, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: false)
        /// 公式行、小类行、组标题里的字。
        static let tLabel = TextStyle(size: 15, lineHeight: 20, weight: .regular, tracking: 0, family: .text, relativeTo: .subheadline, monospacedDigit: false)
        /// 文字按钮（调整、编辑、+ 添加小类）。
        static let tLabelStrong = TextStyle(size: 15, lineHeight: 20, weight: .semibold, tracking: 0, family: .text, relativeTo: .subheadline, monospacedDigit: false)
        /// 胶囊和小类芯片里的字。
        static let tPill = TextStyle(size: 14, lineHeight: 20, weight: .regular, tracking: 0, family: .text, relativeTo: .callout, monospacedDigit: false)
        /// 主数字下面的一行。
        static let tSub = TextStyle(size: 13, lineHeight: 18, weight: .regular, tracking: 0, family: .text, relativeTo: .footnote, monospacedDigit: false)
        /// 日期组标题。
        static let tSubStrong = TextStyle(size: 13, lineHeight: 18, weight: .semibold, tracking: 0, family: .text, relativeTo: .footnote, monospacedDigit: false)
        /// 列表第二行小字、总额、百分比。
        static let tCaption = TextStyle(size: 12, lineHeight: 16, weight: .regular, tracking: 0, family: .text, relativeTo: .caption, monospacedDigit: false)
        /// 行内标签（待 AA、存入）。全 App 最小字号。
        static let tTag = TextStyle(size: 11, lineHeight: 18, weight: .semibold, tracking: 0, family: .text, relativeTo: .caption2, monospacedDigit: false)
        /// 底栏两个入口的字（系统 TabView 同级）。
        static let tTab = TextStyle(size: 10, lineHeight: 12, weight: .medium, tracking: 0, family: .text, relativeTo: .caption2, monospacedDigit: false)

        struct Sample: Identifiable {
            let name: String
            let style: TextStyle
            var id: String { name }
        }
        static let all: [Sample] = [
            Sample(name: "n-entry", style: nEntry),
            Sample(name: "n-detail", style: nDetail),
            Sample(name: "n-hero", style: nHero),
            Sample(name: "n-tile", style: nTile),
            Sample(name: "n-key", style: nKey),
            Sample(name: "n-spine-lg", style: nSpineLg),
            Sample(name: "n-spine", style: nSpine),
            Sample(name: "t-title", style: tTitle),
            Sample(name: "t-body", style: tBody),
            Sample(name: "t-label", style: tLabel),
            Sample(name: "t-label-strong", style: tLabelStrong),
            Sample(name: "t-pill", style: tPill),
            Sample(name: "t-sub", style: tSub),
            Sample(name: "t-sub-strong", style: tSubStrong),
            Sample(name: "t-caption", style: tCaption),
            Sample(name: "t-tag", style: tTag),
            Sample(name: "t-tab", style: tTab),
        ]
    }

    enum Space {
        /// 字和小标记之间。
        static let s4: CGFloat = 4
        /// 胶囊之间、芯片之间。
        static let s8: CGFloat = 8
        /// 图标和名字之间；卡片之间。
        static let s12: CGFloat = 12
        /// 卡片和分组的左右外边距、卡内边距。
        static let s16: CGFloat = 16
        /// 页面左右边距（不装卡片的列表）、组与组之间。
        static let s20: CGFloat = 20
        /// 大块之间。
        static let s28: CGFloat = 28
    }

    enum Radius {
        /// 图例色块、订阅日历里的品牌小方块（只给 ≤ 18pt 的小色块）。
        static let xs: CGFloat = 4
        /// 键盘按键、图标方块、分段控件外框、输入框。
        static let s: CGFloat = 12
        /// 卡片、分组、展开的抽屉、结果条、琥珀卡、弹出菜单。
        static let m: CGFloat = 20
        /// 底部弹窗的两个顶角（.presentationCornerRadius）。
        static let sheet: CGFloat = 28
        /// 居中浮动卡的四个角。
        static let float: CGFloat = 32
        /// 胶囊、按钮、芯片、进度条、分类圆。
        static let isPill = true
    }

    enum Stroke {
        /// 列表行分隔线（与网页 1px 同为 1pt）。
        static let hairline: CGFloat = 1
        /// 设计稿 SVG 图标线宽；iOS 端换成 SF Symbols 的 symbolWeight，见 icon。
        static let icon: CGFloat = 1.6
        /// 选中的输入框描边（accent），用 strokeBorder，不用 inset 阴影。
        static let focus: CGFloat = 1.5
    }

    enum Size {
        /// 账单、流水、账户行的高度（两行时 60）。
        static let rowBill: CGFloat = 54
        /// 两行的账单行。
        static let rowBill2: CGFloat = 60
        /// 分类抽屉的大类行。
        static let rowCat: CGFloat = 60
        /// 抽屉里的小类行、触控最小高度。
        static let rowSub: CGFloat = 44
        /// 记一笔底部的胶囊（账户、时间、···）。
        static let pillH: CGFloat = 34
        /// 小类芯片、周期胶囊。
        static let chipH: CGFloat = 32
        /// 完成、整宽按钮。
        static let buttonH: CGFloat = 50
        /// 键盘按键。
        static let keyH: CGFloat = 48
        /// 底栏中间的记一笔。
        static let ctaH: CGFloat = 48
        /// 问余白条。
        static let askH: CGFloat = 44
        /// 分类圆。
        static let catCircle: CGFloat = 48
        /// 抽屉里的图标方块。
        static let iconTile: CGFloat = 36
        /// 列表图标。
        static let icon: CGFloat = 20
        /// 最小触控尺寸。
        static let tapMin: CGFloat = 44
        /// 分段控件外框到选中格的内边距；选中格圆角 = radius-s − 3。
        static let segmentedInset: CGFloat = 3
        /// 预算行的进度条高度。
        static let barCalm: CGFloat = 4
        /// 琥珀卡里的进度条高度。
        static let barAmber: CGFloat = 6
        /// 首页三个小预算的进度条高度。
        static let barMini: CGFloat = 3
        /// 首页日线柱之间的间隔。
        static let dayBarGap: CGFloat = 3
        /// 首页日线柱区域的高度。
        static let dayBarsH: CGFloat = 36
        /// 环图直径。
        static let donut: CGFloat = 136
        /// 环图环宽。
        static let donutStroke: CGFloat = 18
        /// 图例色块边长。
        static let legendSwatch: CGFloat = 10
        /// 订阅日历里的品牌小方块。
        static let brandTile: CGFloat = 18
        /// 更多菜单的宽度。
        static let menuW: CGFloat = 208
    }

    enum Shape {
        static var pill: Capsule { Capsule(style: .continuous) }
    }

    /// Exactly the four SwiftUI shadow arguments. No spread or inset.
    struct Shadow {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
        /// 只给浮在遮罩上的东西：浮动账单卡、弹出菜单。
        static let float = Shadow(color: DS.adaptive(0x4A4030, 0x000000, lightAlpha: 0.22, darkAlpha: 0.55), radius: 14, x: 0, y: 8)
        /// 分段控件的选中格。
        static let near = Shadow(color: DS.adaptive(0x4A4030, 0x000000, lightAlpha: 0.12, darkAlpha: 0.3), radius: 1, x: 0, y: 1)
        /// 键盘按键底边。
        static let key = Shadow(color: DS.adaptive(0x4A4030, 0x000000, lightAlpha: 0.12, darkAlpha: 0.3), radius: 0, x: 0, y: 1)
    }

    enum Material {
        struct Descriptor {
            let swift: String
            let fallbackName: String
            var fallback: SwiftUI.Material { .regular }
        }
        /// 底栏和问余白条所在的浮层（iOS 26 Liquid Glass）。
        static let bar = Descriptor(swift: "glassEffect", fallbackName: "regularMaterial")
    }

    enum Icon {
        static let catFood = "fork.knife"
        static let catShopping = "bag"
        static let catTransport = "tram"
        static let catHousing = "house"
        static let catGrocery = "basket"
        static let catFun = "ticket"
        static let catDaily = "shippingbox"
        static let catCoffee = "cup.and.saucer"
        static let catDigital = "powerplug"
        static let catOther = "ellipsis"
        static let acctDebit = "building.columns"
        static let acctWallet = "wallet.bifold"
        static let acctBalance = "yensign.circle"
        static let acctCredit = "creditcard"
        static let acctCash = "banknote"
        static let acctInvest = "chart.line.uptrend.xyaxis"
        static let saveFirst = "tray.and.arrow.down"
        static let floor = "checkmark.shield"
        static let subscription = "repeat"
        static let cycle = "calendar"
        static let tabHome = "house"
        static let tabOverview = "chart.bar"
        static let transfer = "arrow.left.arrow.right"
        static let reimburse = "arrow.uturn.backward"
        static let ai = "sparkles"
        static let memory = "brain"
        static let screenshot = "photo"
        static let voice = "mic"
        static let cloud = "cloud"
        static let export = "square.and.arrow.up"
        static let chevron = "chevron.right"
        static let chevronDown = "chevron.down"
        static let back = "chevron.left"
        static let close = "xmark"
        static let more = "ellipsis"
        static let add = "plus"
        static let time = "clock"
        static let search = "magnifyingglass"
        static let edit = "pencil"
        static let delete = "trash"
        static let recategorize = "tag"
        static let duplicate = "square.on.square"
        static let done = "checkmark"
        enum Weight {
            static let list: SwiftUI.Font.Weight = .regular
            static let nav: SwiftUI.Font.Weight = .medium
            static let chevron: SwiftUI.Font.Weight = .semibold
        }
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> SwiftUI.Color {
        #if os(iOS)
        return SwiftUI.Color(uiColor: UIColor(dynamicProvider: { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }))
        #elseif os(macOS)
        return SwiftUI.Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }))
        #endif
    }
}
