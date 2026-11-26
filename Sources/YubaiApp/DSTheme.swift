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
        /// 开关滑块，深浅色都是白色。
        static let knob: SwiftUI.Color = DS.adaptive(0xFFFFFF, 0xFFFFFF, lightAlpha: 1, darkAlpha: 1)
        /// 品牌色块上的标志和首字，深浅色都是白色。
        static let onBrand: SwiftUI.Color = DS.adaptive(0xFFFFFF, 0xFFFFFF, lightAlpha: 1, darkAlpha: 1)
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
            Sample(name: "knob", lightHex: "#FFFFFF", darkHex: "#FFFFFF", color: knob),
            Sample(name: "on-brand", lightHex: "#FFFFFF", darkHex: "#FFFFFF", color: onBrand),
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
        /// 开关轨道宽。
        static let switchW: CGFloat = 48
        /// 开关轨道高。
        static let switchH: CGFloat = 30
        /// 开关滑块直径。
        static let switchKnob: CGFloat = 26
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

    enum Icon: String, CaseIterable, Identifiable, Sendable {
        case catFood = "cat-food"
        case catCoffee = "cat-coffee"
        case catTransport = "cat-transport"
        case catGrocery = "cat-grocery"
        case catShopping = "cat-shopping"
        case catHousing = "cat-housing"
        case catFun = "cat-fun"
        case catDaily = "cat-daily"
        case catDigital = "cat-digital"
        case catOther = "cat-other"
        case catAll = "cat-all"
        case acctDebit = "acct-debit"
        case acctWallet = "acct-wallet"
        case acctBalance = "acct-balance"
        case acctCredit = "acct-credit"
        case acctCash = "acct-cash"
        case acctInvest = "acct-invest"
        case saveFirst = "save-first"
        case floor = "floor"
        case subscription = "subscription"
        case cycle = "cycle"
        case tabHome = "tab-home"
        case tabOverview = "tab-overview"
        case transfer = "transfer"
        case reimburse = "reimburse"
        case ai = "ai"
        case memory = "memory"
        case screenshot = "screenshot"
        case voice = "voice"
        case cloud = "cloud"
        case export = "export"
        case chevron = "chevron"
        case chevronDown = "chevron-down"
        case back = "back"
        case close = "close"
        case more = "more"
        case add = "add"
        case time = "time"
        case search = "search"
        case edit = "edit"
        case delete = "delete"
        case recategorize = "recategorize"
        case duplicate = "duplicate"
        case done = "done"
        case backspace = "backspace"
        case settings = "settings"
        case bolt = "bolt"
        case bell = "bell"
        case half = "half"
        case inbox = "inbox"
        case clock = "clock"
        case disk = "disk"
        case lock = "lock"
        case arrowOut = "arrow-out"

        var id: String { rawValue }
        static let grid: CGFloat = 256
        static let outline: CGFloat = 6

        var phosphor: String {
            switch self {
            case .catFood: "bowl-steam"
            case .catCoffee: "coffee"
            case .catTransport: "tram"
            case .catGrocery: "basket"
            case .catShopping: "shopping-bag"
            case .catHousing: "house"
            case .catFun: "ticket"
            case .catDaily: "package"
            case .catDigital: "device-mobile"
            case .catOther: "dots-three"
            case .catAll: "squares-four"
            case .acctDebit: "bank"
            case .acctWallet: "wallet"
            case .acctBalance: "currency-cny"
            case .acctCredit: "credit-card"
            case .acctCash: "money"
            case .acctInvest: "trend-up"
            case .saveFirst: "piggy-bank"
            case .floor: "shield-check"
            case .subscription: "repeat"
            case .cycle: "calendar-blank"
            case .tabHome: "house-simple"
            case .tabOverview: "chart-bar"
            case .transfer: "arrows-left-right"
            case .reimburse: "arrow-u-up-left"
            case .ai: "sparkle"
            case .memory: "brain"
            case .screenshot: "image"
            case .voice: "microphone"
            case .cloud: "cloud"
            case .export: "export"
            case .chevron: "caret-right"
            case .chevronDown: "caret-down"
            case .back: "caret-left"
            case .close: "x"
            case .more: "dots-three"
            case .add: "plus"
            case .time: "clock"
            case .search: "magnifying-glass"
            case .edit: "pencil-simple-line"
            case .delete: "trash"
            case .recategorize: "tag"
            case .duplicate: "copy"
            case .done: "check"
            case .backspace: "backspace"
            case .settings: "gear-six"
            case .bolt: ""
            case .bell: ""
            case .half: ""
            case .inbox: ""
            case .clock: ""
            case .disk: ""
            case .lock: ""
            case .arrowOut: ""
            }
        }

        var pathData: String {
            switch self {
            case .catFood: "M224 112H32a8 8 0 0 0-8 8a104.35 104.35 0 0 0 56 92.28V216a16 16 0 0 0 16 16h64a16 16 0 0 0 16-16v-3.72A104.35 104.35 0 0 0 232 120a8 8 0 0 0-8-8m-59.34 88a8 8 0 0 0-4.66 7.27V216H96v-8.71a8 8 0 0 0-4.66-7.29a88.29 88.29 0 0 1-51-72h175.29a88.29 88.29 0 0 1-50.97 72M81.77 55c5.35-6.66 6.67-11.16 6.12-13.14c-.42-1.49-2.41-2.26-2.43-2.26A8 8 0 0 1 88 24a8.1 8.1 0 0 1 2.38.36c1 .31 9.91 3.33 12.79 12.76c2.46 8.07-.55 17.45-8.94 27.89c-5.35 6.66-6.67 11.16-6.12 13.14c.42 1.49 2.37 2.24 2.39 2.25A8 8 0 0 1 88 96a8.1 8.1 0 0 1-2.38-.36c-1-.31-9.91-3.33-12.79-12.76c-2.46-8.07.55-17.45 8.94-27.88m40 0c5.35-6.66 6.67-11.16 6.12-13.14c-.42-1.49-2.41-2.26-2.43-2.26A8 8 0 0 1 128 24a8.1 8.1 0 0 1 2.38.36c1 .31 9.91 3.33 12.79 12.76c2.46 8.07-.55 17.45-8.94 27.89c-5.35 6.66-6.67 11.16-6.12 13.14c.42 1.49 2.37 2.24 2.39 2.25A8 8 0 0 1 128 96a8.1 8.1 0 0 1-2.38-.36c-1-.31-9.91-3.33-12.79-12.76c-2.46-8.07.55-17.45 8.94-27.88m40 0c5.35-6.66 6.67-11.16 6.12-13.14c-.42-1.49-2.41-2.26-2.43-2.26A8 8 0 0 1 168 24a8.1 8.1 0 0 1 2.38.36c1 .31 9.91 3.33 12.79 12.76c2.46 8.07-.55 17.45-8.94 27.89c-5.35 6.66-6.67 11.16-6.12 13.14c.42 1.49 2.37 2.24 2.39 2.25A8 8 0 0 1 168 96a8.1 8.1 0 0 1-2.38-.36c-1-.31-9.91-3.33-12.79-12.76c-2.46-8.07.55-17.45 8.94-27.88"
            case .catCoffee: "M80 56V24a8 8 0 0 1 16 0v32a8 8 0 0 1-16 0m40 8a8 8 0 0 0 8-8V24a8 8 0 0 0-16 0v32a8 8 0 0 0 8 8m32 0a8 8 0 0 0 8-8V24a8 8 0 0 0-16 0v32a8 8 0 0 0 8 8m96 56v8a40 40 0 0 1-37.51 39.91a96.6 96.6 0 0 1-27 40.09H208a8 8 0 0 1 0 16H32a8 8 0 0 1 0-16h24.54A96.3 96.3 0 0 1 24 136V88a8 8 0 0 1 8-8h176a40 40 0 0 1 40 40m-48-24H40v40a80.27 80.27 0 0 0 45.12 72h69.76A80.27 80.27 0 0 0 200 136Zm32 24a24 24 0 0 0-16-22.62V136a96 96 0 0 1-1.2 15a24 24 0 0 0 17.2-23Z"
            case .catTransport: "M184 48h-48V24h32a8 8 0 0 0 0-16H88a8 8 0 0 0 0 16h32v24H72a32 32 0 0 0-32 32v104a32 32 0 0 0 32 32h8l-14.4 19.2a8 8 0 1 0 12.8 9.6L100 216h56l21.6 28.8a8 8 0 1 0 12.8-9.6L176 216h8a32 32 0 0 0 32-32V80a32 32 0 0 0-32-32M72 64h112a16 16 0 0 1 16 16v40H56V80a16 16 0 0 1 16-16m112 136H72a16 16 0 0 1-16-16v-48h144v48a16 16 0 0 1-16 16m-88-28a12 12 0 1 1-12-12a12 12 0 0 1 12 12m88 0a12 12 0 1 1-12-12a12 12 0 0 1 12 12"
            case .catGrocery: "M136 120v56a8 8 0 0 1-16 0v-56a8 8 0 0 1 16 0m36.84-.8l-5.6 56a8 8 0 0 0 7.16 8.8a7 7 0 0 0 .81 0a8 8 0 0 0 7.95-7.2l5.6-56a8 8 0 0 0-15.92-1.6m-89.68 0a8 8 0 0 0-15.92 1.6l5.6 56a8 8 0 0 0 8 7.2a7 7 0 0 0 .81 0a8 8 0 0 0 7.16-8.76Zm156.77-30.14l-15.07 113.06A16.06 16.06 0 0 1 209 216H47a16.06 16.06 0 0 1-15.86-13.88L16.07 89.06A8 8 0 0 1 24 80h44.37L122 18.73a8 8 0 0 1 12 0L187.63 80H232a8 8 0 0 1 7.93 9.06M89.63 80h76.74L128 36.15Zm133.23 16H33.14L47 200h162Z"
            case .catShopping: "M216 40H40a16 16 0 0 0-16 16v144a16 16 0 0 0 16 16h176a16 16 0 0 0 16-16V56a16 16 0 0 0-16-16m0 160H40V56h176zM176 88a48 48 0 0 1-96 0a8 8 0 0 1 16 0a32 32 0 0 0 64 0a8 8 0 0 1 16 0"
            case .catHousing: "m219.31 108.68l-80-80a16 16 0 0 0-22.62 0l-80 80A15.87 15.87 0 0 0 32 120v96a8 8 0 0 0 8 8h64a8 8 0 0 0 8-8v-56h32v56a8 8 0 0 0 8 8h64a8 8 0 0 0 8-8v-96a15.87 15.87 0 0 0-4.69-11.32M208 208h-48v-56a8 8 0 0 0-8-8h-48a8 8 0 0 0-8 8v56H48v-88l80-80l80 80Z"
            case .catFun: "M232 104a8 8 0 0 0 8-8V64a16 16 0 0 0-16-16H32a16 16 0 0 0-16 16v32a8 8 0 0 0 8 8a24 24 0 0 1 0 48a8 8 0 0 0-8 8v32a16 16 0 0 0 16 16h192a16 16 0 0 0 16-16v-32a8 8 0 0 0-8-8a24 24 0 0 1 0-48M32 167.2a40 40 0 0 0 0-78.4V64h56v128H32Zm192 0V192H104V64h120v24.8a40 40 0 0 0 0 78.4"
            case .catDaily: "m223.68 66.15l-88-48.15a15.88 15.88 0 0 0-15.36 0l-88 48.17a16 16 0 0 0-8.32 14v95.64a16 16 0 0 0 8.32 14l88 48.17a15.88 15.88 0 0 0 15.36 0l88-48.17a16 16 0 0 0 8.32-14V80.18a16 16 0 0 0-8.32-14.03M128 32l80.34 44l-29.77 16.3l-80.35-44Zm0 88L47.66 76l33.9-18.56l80.34 44ZM40 90l80 43.78v85.79l-80-43.75Zm176 85.78l-80 43.79v-85.75l32-17.51V152a8 8 0 0 0 16 0v-44.45L216 90v85.77Z"
            case .catDigital: "M176 16H80a24 24 0 0 0-24 24v176a24 24 0 0 0 24 24h96a24 24 0 0 0 24-24V40a24 24 0 0 0-24-24M72 64h112v128H72Zm8-32h96a8 8 0 0 1 8 8v8H72v-8a8 8 0 0 1 8-8m96 192H80a8 8 0 0 1-8-8v-8h112v8a8 8 0 0 1-8 8"
            case .catOther: "M140 128a12 12 0 1 1-12-12a12 12 0 0 1 12 12m56-12a12 12 0 1 0 12 12a12 12 0 0 0-12-12m-136 0a12 12 0 1 0 12 12a12 12 0 0 0-12-12"
            case .catAll: "M104 40H56a16 16 0 0 0-16 16v48a16 16 0 0 0 16 16h48a16 16 0 0 0 16-16V56a16 16 0 0 0-16-16m0 64H56V56h48zm96-64h-48a16 16 0 0 0-16 16v48a16 16 0 0 0 16 16h48a16 16 0 0 0 16-16V56a16 16 0 0 0-16-16m0 64h-48V56h48zm-96 32H56a16 16 0 0 0-16 16v48a16 16 0 0 0 16 16h48a16 16 0 0 0 16-16v-48a16 16 0 0 0-16-16m0 64H56v-48h48zm96-64h-48a16 16 0 0 0-16 16v48a16 16 0 0 0 16 16h48a16 16 0 0 0 16-16v-48a16 16 0 0 0-16-16m0 64h-48v-48h48z"
            case .acctDebit: "M24 104h24v64H32a8 8 0 0 0 0 16h192a8 8 0 0 0 0-16h-16v-64h24a8 8 0 0 0 4.19-14.81l-104-64a8 8 0 0 0-8.38 0l-104 64A8 8 0 0 0 24 104m40 0h32v64H64Zm80 0v64h-32v-64Zm48 64h-32v-64h32ZM128 41.39L203.74 88H52.26ZM248 208a8 8 0 0 1-8 8H16a8 8 0 0 1 0-16h224a8 8 0 0 1 8 8"
            case .acctWallet: "M216 64H56a8 8 0 0 1 0-16h136a8 8 0 0 0 0-16H56a24 24 0 0 0-24 24v128a24 24 0 0 0 24 24h160a16 16 0 0 0 16-16V80a16 16 0 0 0-16-16m0 128H56a8 8 0 0 1-8-8V78.63A23.8 23.8 0 0 0 56 80h160Zm-48-60a12 12 0 1 1 12 12a12 12 0 0 1-12-12"
            case .acctBalance: "M56 56a8 8 0 0 1 8-8h128a8 8 0 0 1 0 16H64a8 8 0 0 1-8-8m160 104a8 8 0 0 0-8 8v16h-32a16 16 0 0 1-16-16v-48h48a8 8 0 0 0 0-16H48a8 8 0 0 0 0 16h48v8a56.06 56.06 0 0 1-56 56a8 8 0 0 0 0 16a72.08 72.08 0 0 0 72-72v-8h32v48a32 32 0 0 0 32 32h40a8 8 0 0 0 8-8v-24a8 8 0 0 0-8-8"
            case .acctCredit: "M224 48H32a16 16 0 0 0-16 16v128a16 16 0 0 0 16 16h192a16 16 0 0 0 16-16V64a16 16 0 0 0-16-16m0 16v24H32V64Zm0 128H32v-88h192zm-16-24a8 8 0 0 1-8 8h-32a8 8 0 0 1 0-16h32a8 8 0 0 1 8 8m-64 0a8 8 0 0 1-8 8h-16a8 8 0 0 1 0-16h16a8 8 0 0 1 8 8"
            case .acctCash: "M128 88a40 40 0 1 0 40 40a40 40 0 0 0-40-40m0 64a24 24 0 1 1 24-24a24 24 0 0 1-24 24m112-96H16a8 8 0 0 0-8 8v128a8 8 0 0 0 8 8h224a8 8 0 0 0 8-8V64a8 8 0 0 0-8-8m-46.35 128H62.35A56.78 56.78 0 0 0 24 145.65v-35.3A56.78 56.78 0 0 0 62.35 72h131.3A56.78 56.78 0 0 0 232 110.35v35.3A56.78 56.78 0 0 0 193.65 184M232 93.37A40.8 40.8 0 0 1 210.63 72H232ZM45.37 72A40.8 40.8 0 0 1 24 93.37V72ZM24 162.63A40.8 40.8 0 0 1 45.37 184H24ZM210.63 184A40.8 40.8 0 0 1 232 162.63V184Z"
            case .acctInvest: "M240 56v64a8 8 0 0 1-16 0V75.31l-82.34 82.35a8 8 0 0 1-11.32 0L96 123.31l-66.34 66.35a8 8 0 0 1-11.32-11.32l72-72a8 8 0 0 1 11.32 0L136 140.69L212.69 64H168a8 8 0 0 1 0-16h64a8 8 0 0 1 8 8"
            case .saveFirst: "M192 116a12 12 0 1 1-12-12a12 12 0 0 1 12 12m-40-52h-40a8 8 0 0 0 0 16h40a8 8 0 0 0 0-16m96 48v32a24 24 0 0 1-24 24h-2.36l-16.21 45.38A16 16 0 0 1 190.36 224h-12.72a16 16 0 0 1-15.07-10.62l-1.92-5.38h-57.3l-1.92 5.38A16 16 0 0 1 86.36 224H73.64a16 16 0 0 1-15.07-10.62L46 178.22a87.7 87.7 0 0 1-21.44-48.38A16 16 0 0 0 16 144a8 8 0 0 1-16 0a32 32 0 0 1 24.28-31A88.12 88.12 0 0 1 112 32h104a8 8 0 0 1 0 16h-21.39a87.93 87.93 0 0 1 30.17 37c.43 1 .85 2 1.25 3A24 24 0 0 1 248 112m-16 0a8 8 0 0 0-8-8h-3.66a8 8 0 0 1-7.64-5.6A71.9 71.9 0 0 0 144 48h-32a72 72 0 0 0-53.09 120.64a8 8 0 0 1 1.64 2.71L73.64 208h12.72l3.82-10.69a8 8 0 0 1 7.53-5.31h68.58a8 8 0 0 1 7.53 5.31l3.82 10.69h12.72l18.11-50.69A8 8 0 0 1 216 152h8a8 8 0 0 0 8-8Z"
            case .floor: "M208 40H48a16 16 0 0 0-16 16v56c0 52.72 25.52 84.67 46.93 102.19c23.06 18.86 46 25.26 47 25.53a8 8 0 0 0 4.2 0c1-.27 23.91-6.67 47-25.53C198.48 196.67 224 164.72 224 112V56a16 16 0 0 0-16-16m0 72c0 37.07-13.66 67.16-40.6 89.42a129.3 129.3 0 0 1-39.4 22.2a128.3 128.3 0 0 1-38.92-21.81C61.82 179.51 48 149.3 48 112V56h160ZM82.34 141.66a8 8 0 0 1 11.32-11.32L112 148.69l50.34-50.35a8 8 0 0 1 11.32 11.32l-56 56a8 8 0 0 1-11.32 0Z"
            case .subscription: "M24 128a72.08 72.08 0 0 1 72-72h108.69l-10.35-10.34a8 8 0 0 1 11.32-11.32l24 24a8 8 0 0 1 0 11.32l-24 24a8 8 0 0 1-11.32-11.32L204.69 72H96a56.06 56.06 0 0 0-56 56a8 8 0 0 1-16 0m200-8a8 8 0 0 0-8 8a56.06 56.06 0 0 1-56 56H51.31l10.35-10.34a8 8 0 0 0-11.32-11.32l-24 24a8 8 0 0 0 0 11.32l24 24a8 8 0 0 0 11.32-11.32L51.31 200H160a72.08 72.08 0 0 0 72-72a8 8 0 0 0-8-8"
            case .cycle: "M208 32h-24v-8a8 8 0 0 0-16 0v8H88v-8a8 8 0 0 0-16 0v8H48a16 16 0 0 0-16 16v160a16 16 0 0 0 16 16h160a16 16 0 0 0 16-16V48a16 16 0 0 0-16-16M72 48v8a8 8 0 0 0 16 0v-8h80v8a8 8 0 0 0 16 0v-8h24v32H48V48Zm136 160H48V96h160z"
            case .tabHome: "m219.31 108.68l-80-80a16 16 0 0 0-22.62 0l-80 80A15.87 15.87 0 0 0 32 120v96a8 8 0 0 0 8 8h176a8 8 0 0 0 8-8v-96a15.87 15.87 0 0 0-4.69-11.32M208 208H48v-88l80-80l80 80Z"
            case .tabOverview: "M224 200h-8V40a8 8 0 0 0-8-8h-56a8 8 0 0 0-8 8v40H96a8 8 0 0 0-8 8v40H48a8 8 0 0 0-8 8v64h-8a8 8 0 0 0 0 16h192a8 8 0 0 0 0-16M160 48h40v152h-40Zm-56 48h40v104h-40Zm-48 48h32v56H56Z"
            case .transfer: "m213.66 181.66l-32 32a8 8 0 0 1-11.32-11.32L188.69 184H48a8 8 0 0 1 0-16h140.69l-18.35-18.34a8 8 0 0 1 11.32-11.32l32 32a8 8 0 0 1 0 11.32m-139.32-64a8 8 0 0 0 11.32-11.32L67.31 88H208a8 8 0 0 0 0-16H67.31l18.35-18.34a8 8 0 0 0-11.32-11.32l-32 32a8 8 0 0 0 0 11.32Z"
            case .reimburse: "M232 144a64.07 64.07 0 0 1-64 64H80a8 8 0 0 1 0-16h88a48 48 0 0 0 0-96H51.31l34.35 34.34a8 8 0 0 1-11.32 11.32l-48-48a8 8 0 0 1 0-11.32l48-48a8 8 0 0 1 11.32 11.32L51.31 80H168a64.07 64.07 0 0 1 64 64"
            case .ai: "M197.58 129.06L146 110l-19-51.62a15.92 15.92 0 0 0-29.88 0L78 110l-51.62 19a15.92 15.92 0 0 0 0 29.88L78 178l19 51.62a15.92 15.92 0 0 0 29.88 0L146 178l51.62-19a15.92 15.92 0 0 0 0-29.88ZM137 164.22a8 8 0 0 0-4.74 4.74L112 223.85L91.78 169a8 8 0 0 0-4.78-4.78L32.15 144L87 123.78a8 8 0 0 0 4.78-4.78L112 64.15L132.22 119a8 8 0 0 0 4.74 4.74L191.85 144ZM144 40a8 8 0 0 1 8-8h16V16a8 8 0 0 1 16 0v16h16a8 8 0 0 1 0 16h-16v16a8 8 0 0 1-16 0V48h-16a8 8 0 0 1-8-8m104 48a8 8 0 0 1-8 8h-8v8a8 8 0 0 1-16 0v-8h-8a8 8 0 0 1 0-16h8v-8a8 8 0 0 1 16 0v8h8a8 8 0 0 1 8 8"
            case .memory: "M248 124a56.11 56.11 0 0 0-32-50.61V72a48 48 0 0 0-88-26.49A48 48 0 0 0 40 72v1.39a56 56 0 0 0 0 101.2V176a48 48 0 0 0 88 26.49A48 48 0 0 0 216 176v-1.41A56.09 56.09 0 0 0 248 124M88 208a32 32 0 0 1-31.81-28.56A56 56 0 0 0 64 180h8a8 8 0 0 0 0-16h-8a40 40 0 0 1-13.33-77.73A8 8 0 0 0 56 78.73V72a32 32 0 0 1 64 0v68.26A47.8 47.8 0 0 0 88 128a8 8 0 0 0 0 16a32 32 0 0 1 0 64m104-44h-8a8 8 0 0 0 0 16h8a56 56 0 0 0 7.81-.56A32 32 0 1 1 168 144a8 8 0 0 0 0-16a47.8 47.8 0 0 0-32 12.26V72a32 32 0 0 1 64 0v6.73a8 8 0 0 0 5.33 7.54A40 40 0 0 1 192 164m16-52a8 8 0 0 1-8 8h-4a36 36 0 0 1-36-36v-4a8 8 0 0 1 16 0v4a20 20 0 0 0 20 20h4a8 8 0 0 1 8 8m-148 8h-4a8 8 0 0 1 0-16h4a20 20 0 0 0 20-20v-4a8 8 0 0 1 16 0v4a36 36 0 0 1-36 36"
            case .screenshot: "M216 40H40a16 16 0 0 0-16 16v144a16 16 0 0 0 16 16h176a16 16 0 0 0 16-16V56a16 16 0 0 0-16-16m0 16v102.75l-26.07-26.06a16 16 0 0 0-22.63 0l-20 20l-44-44a16 16 0 0 0-22.62 0L40 149.37V56ZM40 172l52-52l80 80H40Zm176 28h-21.37l-36-36l20-20L216 181.38zm-72-100a12 12 0 1 1 12 12a12 12 0 0 1-12-12"
            case .voice: "M128 176a48.05 48.05 0 0 0 48-48V64a48 48 0 0 0-96 0v64a48.05 48.05 0 0 0 48 48M96 64a32 32 0 0 1 64 0v64a32 32 0 0 1-64 0Zm40 143.6V240a8 8 0 0 1-16 0v-32.4A80.11 80.11 0 0 1 48 128a8 8 0 0 1 16 0a64 64 0 0 0 128 0a8 8 0 0 1 16 0a80.11 80.11 0 0 1-72 79.6"
            case .cloud: "M160 40a88.09 88.09 0 0 0-78.71 48.67A64 64 0 1 0 72 216h88a88 88 0 0 0 0-176m0 160H72a48 48 0 0 1 0-96c1.1 0 2.2 0 3.29.11A88 88 0 0 0 72 128a8 8 0 0 0 16 0a72 72 0 1 1 72 72"
            case .export: "M216 112v96a16 16 0 0 1-16 16H56a16 16 0 0 1-16-16v-96a16 16 0 0 1 16-16h24a8 8 0 0 1 0 16H56v96h144v-96h-24a8 8 0 0 1 0-16h24a16 16 0 0 1 16 16M93.66 69.66L120 43.31V136a8 8 0 0 0 16 0V43.31l26.34 26.35a8 8 0 0 0 11.32-11.32l-40-40a8 8 0 0 0-11.32 0l-40 40a8 8 0 0 0 11.32 11.32"
            case .chevron: "m181.66 133.66l-80 80a8 8 0 0 1-11.32-11.32L164.69 128L90.34 53.66a8 8 0 0 1 11.32-11.32l80 80a8 8 0 0 1 0 11.32"
            case .chevronDown: "m213.66 101.66l-80 80a8 8 0 0 1-11.32 0l-80-80a8 8 0 0 1 11.32-11.32L128 164.69l74.34-74.35a8 8 0 0 1 11.32 11.32"
            case .back: "M165.66 202.34a8 8 0 0 1-11.32 11.32l-80-80a8 8 0 0 1 0-11.32l80-80a8 8 0 0 1 11.32 11.32L91.31 128Z"
            case .close: "M205.66 194.34a8 8 0 0 1-11.32 11.32L128 139.31l-66.34 66.35a8 8 0 0 1-11.32-11.32L116.69 128L50.34 61.66a8 8 0 0 1 11.32-11.32L128 116.69l66.34-66.35a8 8 0 0 1 11.32 11.32L139.31 128Z"
            case .more: "M140 128a12 12 0 1 1-12-12a12 12 0 0 1 12 12m56-12a12 12 0 1 0 12 12a12 12 0 0 0-12-12m-136 0a12 12 0 1 0 12 12a12 12 0 0 0-12-12"
            case .add: "M224 128a8 8 0 0 1-8 8h-80v80a8 8 0 0 1-16 0v-80H40a8 8 0 0 1 0-16h80V40a8 8 0 0 1 16 0v80h80a8 8 0 0 1 8 8"
            case .time: "M128 24a104 104 0 1 0 104 104A104.11 104.11 0 0 0 128 24m0 192a88 88 0 1 1 88-88a88.1 88.1 0 0 1-88 88m64-88a8 8 0 0 1-8 8h-56a8 8 0 0 1-8-8V72a8 8 0 0 1 16 0v48h48a8 8 0 0 1 8 8"
            case .search: "m229.66 218.34l-50.07-50.06a88.11 88.11 0 1 0-11.31 11.31l50.06 50.07a8 8 0 0 0 11.32-11.32M40 112a72 72 0 1 1 72 72a72.08 72.08 0 0 1-72-72"
            case .edit: "m227.32 73.37l-44.69-44.68a16 16 0 0 0-22.63 0L36.69 152A15.86 15.86 0 0 0 32 163.31V208a16 16 0 0 0 16 16h168a8 8 0 0 0 0-16H115.32l112-112a16 16 0 0 0 0-22.63M92.69 208H48v-44.69l88-88L180.69 120ZM192 108.69L147.32 64l24-24L216 84.69Z"
            case .delete: "M216 48h-40v-8a24 24 0 0 0-24-24h-48a24 24 0 0 0-24 24v8H40a8 8 0 0 0 0 16h8v144a16 16 0 0 0 16 16h128a16 16 0 0 0 16-16V64h8a8 8 0 0 0 0-16M96 40a8 8 0 0 1 8-8h48a8 8 0 0 1 8 8v8H96Zm96 168H64V64h128Zm-80-104v64a8 8 0 0 1-16 0v-64a8 8 0 0 1 16 0m48 0v64a8 8 0 0 1-16 0v-64a8 8 0 0 1 16 0"
            case .recategorize: "M243.31 136L144 36.69A15.86 15.86 0 0 0 132.69 32H40a8 8 0 0 0-8 8v92.69A15.86 15.86 0 0 0 36.69 144L136 243.31a16 16 0 0 0 22.63 0l84.68-84.68a16 16 0 0 0 0-22.63m-96 96L48 132.69V48h84.69L232 147.31ZM96 84a12 12 0 1 1-12-12a12 12 0 0 1 12 12"
            case .duplicate: "M216 32H88a8 8 0 0 0-8 8v40H40a8 8 0 0 0-8 8v128a8 8 0 0 0 8 8h128a8 8 0 0 0 8-8v-40h40a8 8 0 0 0 8-8V40a8 8 0 0 0-8-8m-56 176H48V96h112Zm48-48h-32V88a8 8 0 0 0-8-8H96V48h112Z"
            case .done: "m229.66 77.66l-128 128a8 8 0 0 1-11.32 0l-56-56a8 8 0 0 1 11.32-11.32L96 188.69L218.34 66.34a8 8 0 0 1 11.32 11.32"
            case .backspace: "M216 40H68.53a16.08 16.08 0 0 0-13.72 7.77L9.14 123.88a8 8 0 0 0 0 8.24l45.67 76.11A16.08 16.08 0 0 0 68.53 216H216a16 16 0 0 0 16-16V56a16 16 0 0 0-16-16M61.67 204.12l6.86-4.12ZM216 200H68.53l-43.2-72l43.2-72H216Zm-109.66-53.66L124.69 128l-18.35-18.34a8 8 0 0 1 11.32-11.32L136 116.69l18.34-18.35a8 8 0 0 1 11.32 11.32L147.31 128l18.35 18.34a8 8 0 0 1-11.32 11.32L136 139.31l-18.34 18.35a8 8 0 0 1-11.32-11.32"
            case .settings: "M128 80a48 48 0 1 0 48 48a48.05 48.05 0 0 0-48-48m0 80a32 32 0 1 1 32-32a32 32 0 0 1-32 32m109.94-52.79a8 8 0 0 0-3.89-5.4l-29.83-17l-.12-33.62a8 8 0 0 0-2.83-6.08a111.9 111.9 0 0 0-36.72-20.67a8 8 0 0 0-6.46.59L128 41.85L97.88 25a8 8 0 0 0-6.47-.6a112.1 112.1 0 0 0-36.68 20.75a8 8 0 0 0-2.83 6.07l-.15 33.65l-29.83 17a8 8 0 0 0-3.89 5.4a106.5 106.5 0 0 0 0 41.56a8 8 0 0 0 3.89 5.4l29.83 17l.12 33.62a8 8 0 0 0 2.83 6.08a111.9 111.9 0 0 0 36.72 20.67a8 8 0 0 0 6.46-.59L128 214.15L158.12 231a7.9 7.9 0 0 0 3.9 1a8.1 8.1 0 0 0 2.57-.42a112.1 112.1 0 0 0 36.68-20.73a8 8 0 0 0 2.83-6.07l.15-33.65l29.83-17a8 8 0 0 0 3.89-5.4a106.5 106.5 0 0 0-.03-41.52m-15 34.91l-28.57 16.25a8 8 0 0 0-3 3c-.58 1-1.19 2.06-1.81 3.06a7.94 7.94 0 0 0-1.22 4.21l-.15 32.25a95.9 95.9 0 0 1-25.37 14.3L134 199.13a8 8 0 0 0-3.91-1h-3.83a8.1 8.1 0 0 0-4.1 1l-28.84 16.1A96 96 0 0 1 67.88 201l-.11-32.2a8 8 0 0 0-1.22-4.22c-.62-1-1.23-2-1.8-3.06a8.1 8.1 0 0 0-3-3.06l-28.6-16.29a90.5 90.5 0 0 1 0-28.26l28.52-16.28a8 8 0 0 0 3-3c.58-1 1.19-2.06 1.81-3.06a7.94 7.94 0 0 0 1.22-4.21l.15-32.25a95.9 95.9 0 0 1 25.37-14.3L122 56.87a8 8 0 0 0 4.1 1h3.64a8.1 8.1 0 0 0 4.1-1l28.84-16.1A96 96 0 0 1 188.12 55l.11 32.2a8 8 0 0 0 1.22 4.22c.62 1 1.23 2 1.8 3.06a8.1 8.1 0 0 0 3 3.06l28.6 16.29a90.5 90.5 0 0 1 .05 28.29Z"
            case .bolt: "M13 3 5 13.5h6L10 21l8-10.5h-6Z"
            case .bell: "M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15Z M10 20.5a2 2 0 0 0 4 0"
            case .half: "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M12 3v18"
            case .inbox: "M12 3v11 M7.5 9.5 12 14l4.5-4.5 M5 14v6h14v-6"
            case .clock: "M4.5 12a7.5 7.5 0 1 0 2.2-5.3 M4 4v4h4 M12 8.5V12l2.5 2"
            case .disk: "M5 6c0-1.7 3.1-3 7-3s7 1.3 7 3-3.1 3-7 3-7-1.3-7-3Z M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6 M5 12c0 1.7 3.1 3 7 3s7-1.3 7-3"
            case .lock: "M6 11h12v10H6Z M8.5 11V8a3.5 3.5 0 0 1 7 0v3 M12 15v2"
            case .arrowOut: "M7 17 17 7 M9 7h8v8"
            }
        }

        /// Canvas line glyphs: stroke only on their own grid. Nil for the filled outline glyphs.
        var line: (grid: CGFloat, stroke: CGFloat)? {
            switch self {
            case .bolt: (24, 1.6)
            case .bell: (24, 1.6)
            case .half: (24, 1.6)
            case .inbox: (24, 1.6)
            case .clock: (24, 1.6)
            case .disk: (24, 1.6)
            case .lock: (24, 1.6)
            case .arrowOut: (24, 1.6)
            default: nil
            }
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
