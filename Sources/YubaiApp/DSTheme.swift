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
        /// 最重的琥珀字：只给「先别买」。
        static let warnStrong: SwiftUI.Color = DS.adaptive(0x5E3F17, 0xF3DDB3, lightAlpha: 1, darkAlpha: 1)
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
            Sample(name: "warn-strong", lightHex: "#5E3F17", darkHex: "#F3DDB3", color: warnStrong),
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
        case heart = "heart"
        case mail = "mail"
        case compass = "compass"
        case chat = "chat"
        case catHealth = "cat-health"
        case catBeauty = "cat-beauty"
        case catTravel = "cat-travel"
        case catMembership = "cat-membership"
        case catLearning = "cat-learning"
        case catFamily = "cat-family"
        case catInsurance = "cat-insurance"
        case catFees = "cat-fees"
        case incSalary = "inc-salary"
        case incSideJob = "inc-side-job"
        case incGift = "inc-gift"
        case incInvestment = "inc-investment"
        case incResale = "inc-resale"
        case acctReceivable = "acct-receivable"
        case dirIncome = "dir-income"
        case dirExpense = "dir-expense"
        case refund = "refund"
        case split = "split"
        case radioOff = "radio-off"
        case arrowRight = "arrow-right"
        case chevronUp = "chevron-up"
        case clear = "clear"
        case radioOn = "radio-on"
        case checkboxOn = "checkbox-on"
        case checkboxOff = "checkbox-off"
        case reminderDate = "reminder-date"
        case addCircle = "add-circle"
        case scanCapture = "scan-capture"
        case warning = "warning"
        case send = "send"
        case undo = "undo"
        case drag = "drag"

        var id: String { rawValue }
        static let grid: CGFloat = 24

        /// Remix Icon name, or the custom 余白 glyph name.
        var source: String {
            switch self {
            case .catFood: "bowl-line"
            case .catCoffee: "cup-line"
            case .catTransport: "subway-line"
            case .catGrocery: "shopping-basket-2-line"
            case .catShopping: "shopping-bag-3-line"
            case .catHousing: "home-4-line"
            case .catFun: "ticket-2-line"
            case .catDaily: "store-2-line"
            case .catDigital: "smartphone-line"
            case .catOther: "more-line"
            case .catAll: "apps-2-line"
            case .acctDebit: "bank-line"
            case .acctWallet: "wallet-3-line"
            case .acctBalance: "currency-line"
            case .acctCredit: "bank-card-line"
            case .acctCash: "cash-line"
            case .acctInvest: "stock-line"
            case .saveFirst: "hand-coin-line"
            case .floor: "safe-line"
            case .subscription: "repeat-2-line"
            case .cycle: "calendar-line"
            case .tabHome: "home-5-line"
            case .tabOverview: "bar-chart-box-line"
            case .transfer: "arrow-left-right-line"
            case .reimburse: "receipt-line"
            case .ai: "sparkling-line"
            case .memory: "brain-line"
            case .screenshot: "image-line"
            case .voice: "mic-line"
            case .cloud: "cloud-line"
            case .export: "share-box-line"
            case .chevron: "arrow-right-s-line"
            case .chevronDown: "arrow-down-s-line"
            case .back: "arrow-left-s-line"
            case .close: "close-line"
            case .more: "more-line"
            case .add: "add-line"
            case .time: "time-line"
            case .search: "search-line"
            case .edit: "edit-2-line"
            case .delete: "delete-bin-line"
            case .recategorize: "price-tag-3-line"
            case .duplicate: "file-copy-line"
            case .done: "check-line"
            case .backspace: "delete-back-2-line"
            case .settings: "settings-3-line"
            case .bolt: "quill-pen-line"
            case .bell: "notification-3-line"
            case .half: "palette-line"
            case .inbox: "download-2-line"
            case .clock: "history-line"
            case .disk: "database-2-line"
            case .lock: "custom:face-scan"
            case .arrowOut: "upload-2-line"
            case .heart: "heart-3-line"
            case .mail: "mail-line"
            case .compass: "scales-3-line"
            case .chat: "custom:ask-brand"
            case .catHealth: "first-aid-kit-line"
            case .catBeauty: "scissors-line"
            case .catTravel: "suitcase-line"
            case .catMembership: "vip-crown-2-line"
            case .catLearning: "book-open-line"
            case .catFamily: "gift-line"
            case .catInsurance: "umbrella-line"
            case .catFees: "coins-line"
            case .incSalary: "briefcase-line"
            case .incSideJob: "hammer-line"
            case .incGift: "red-packet-line"
            case .incInvestment: "line-chart-line"
            case .incResale: "recycle-line"
            case .acctReceivable: "user-received-2-line"
            case .dirIncome: "arrow-left-down-line"
            case .dirExpense: "arrow-right-up-line"
            case .refund: "refund-2-line"
            case .split: "group-line"
            case .radioOff: "checkbox-blank-circle-line"
            case .arrowRight: "arrow-right-line"
            case .chevronUp: "arrow-up-s-line"
            case .clear: "close-circle-fill"
            case .radioOn: "checkbox-circle-fill"
            case .checkboxOn: "checkbox-fill"
            case .checkboxOff: "checkbox-blank-line"
            case .reminderDate: "calendar-schedule-line"
            case .addCircle: "add-circle-line"
            case .scanCapture: "screenshot-2-line"
            case .warning: "error-warning-line"
            case .send: "send-plane-line"
            case .undo: "arrow-go-back-line"
            case .drag: "draggable"
            }
        }

        /// Filled outline on the 24 grid (nonzero).
        var pathData: String {
            switch self {
            case .catFood: "M8 1.5C8 0.947715 7.55228 0.5 7 0.5C6.44772 0.5 6 0.947715 6 1.5V2.5C6 2.50686 6.00042 2.51285 6.00081 2.51843C6.00385 2.56193 6.00516 2.58063 5.79289 2.79289L5.77277 2.81298C5.50599 3.07912 5 3.58391 5 4.5V5.5C5 6.05228 5.44772 6.5 6 6.5C6.55228 6.5 7 6.05228 7 5.5V4.5C7 4.49314 6.99958 4.48715 6.99919 4.48157C6.99615 4.43807 6.99484 4.41937 7.20711 4.20711L7.22723 4.18702C7.49401 3.92088 8 3.41609 8 2.5V1.5ZM19 1.5C19 0.947715 18.5523 0.5 18 0.5C17.4477 0.5 17 0.947715 17 1.5V2.5C17 2.50686 17.0004 2.51285 17.0008 2.51843C17.0038 2.56193 17.0052 2.58063 16.7929 2.79289L16.7728 2.81298C16.506 3.07912 16 3.58391 16 4.5V5.5C16 6.05228 16.4477 6.5 17 6.5C17.5523 6.5 18 6.05228 18 5.5V4.5C18 4.49314 17.9996 4.48715 17.9992 4.48157C17.9962 4.43807 17.9948 4.41937 18.2071 4.20711L18.2272 4.18702C18.494 3.92088 19 3.41609 19 2.5V1.5ZM12.5 0.5C13.0523 0.5 13.5 0.947715 13.5 1.5V2.5C13.5 3.41609 12.994 3.92088 12.7272 4.18702L12.7071 4.20711C12.4948 4.41937 12.4962 4.43807 12.4992 4.48157C12.4996 4.48715 12.5 4.49314 12.5 4.5V5.5C12.5 6.05228 12.0523 6.5 11.5 6.5C10.9477 6.5 10.5 6.05228 10.5 5.5V4.5C10.5 3.58391 11.006 3.07912 11.2728 2.81298L11.2929 2.79289C11.5052 2.58063 11.5038 2.56193 11.5008 2.51843C11.5004 2.51285 11.5 2.50686 11.5 2.5V1.5C11.5 0.947715 11.9477 0.5 12.5 0.5ZM4 10H20C20 14.4183 16.4183 18 12 18C7.58172 18 4 14.4183 4 10ZM3 8C2.44772 8 2 8.44771 2 9V10C2 14.1006 4.46819 17.6248 8 19.1679V20C8 20.5523 8.44772 21 9 21H15C15.5523 21 16 20.5523 16 20V19.1679C19.5318 17.6248 22 14.1006 22 10V9C22 8.44772 21.5523 8 21 8H3Z"
            case .catCoffee: "M16 13V5H6V13C6 14.1046 6.89543 15 8 15H14C15.1046 15 16 14.1046 16 13ZM5 3H20C21.1046 3 22 3.89543 22 5V8C22 9.10457 21.1046 10 20 10H18V13C18 15.2091 16.2091 17 14 17H8C5.79086 17 4 15.2091 4 13V4C4 3.44772 4.44772 3 5 3ZM18 5V8H20V5H18ZM2 19H20V21H2V19Z"
            case .catTransport: "M17.2 20L19 21.5V22H5V21.5L6.8 20H5C3.89543 20 3 19.1046 3 18V7C3 4.79086 4.79086 3 7 3H17C19.2091 3 21 4.79086 21 7V18C21 19.1046 20.1046 20 19 20H17.2ZM13 5V11H19V7C19 5.89543 18.1046 5 17 5H13ZM11 5H7C5.89543 5 5 5.89543 5 7V11H11V5ZM19 13H5V18H19V13ZM7.5 17C6.67157 17 6 16.3284 6 15.5C6 14.6716 6.67157 14 7.5 14C8.32843 14 9 14.6716 9 15.5C9 16.3284 8.32843 17 7.5 17ZM16.5 17C15.6716 17 15 16.3284 15 15.5C15 14.6716 15.6716 14 16.5 14C17.3284 14 18 14.6716 18 15.5C18 16.3284 17.3284 17 16.5 17Z"
            case .catGrocery: "M15.3709 3.44L18.5819 9.002L22.0049 9.00218V11.0022L20.8379 11.002L20.0813 20.0852C20.0381 20.6035 19.6048 21.0022 19.0847 21.0022H4.92502C4.40493 21.0022 3.97166 20.6035 3.92847 20.0852L3.17088 11.002L2.00488 11.0022V9.00218L5.42688 9.002L8.63886 3.44L10.3709 4.44L7.73688 9.002H16.2719L13.6389 4.44L15.3709 3.44ZM18.8309 11.002L5.17788 11.0022L5.84488 19.0022H18.1639L18.8309 11.002ZM13.0049 13.0022V17.0022H11.0049V13.0022H13.0049ZM9.00488 13.0022V17.0022H7.00488V13.0022H9.00488ZM17.0049 13.0022V17.0022H15.0049V13.0022H17.0049Z"
            case .catShopping: "M6.50488 2H17.5049C17.8196 2 18.116 2.14819 18.3049 2.4L21.0049 6V21C21.0049 21.5523 20.5572 22 20.0049 22H4.00488C3.4526 22 3.00488 21.5523 3.00488 21V6L5.70488 2.4C5.89374 2.14819 6.19013 2 6.50488 2ZM19.0049 8H5.00488V20H19.0049V8ZM18.5049 6L17.0049 4H7.00488L5.50488 6H18.5049ZM9.00488 10V12C9.00488 13.6569 10.348 15 12.0049 15C13.6617 15 15.0049 13.6569 15.0049 12V10H17.0049V12C17.0049 14.7614 14.7663 17 12.0049 17C9.24346 17 7.00488 14.7614 7.00488 12V10H9.00488Z"
            case .catHousing: "M19 21H5C4.44772 21 4 20.5523 4 20V11L1 11L11.3273 1.6115C11.7087 1.26475 12.2913 1.26475 12.6727 1.6115L23 11L20 11V20C20 20.5523 19.5523 21 19 21ZM13 19H18V9.15745L12 3.7029L6 9.15745V19H11V13H13V19Z"
            case .catFun: "M21.0049 2.99979C21.5572 2.99979 22.0049 3.4475 22.0049 3.99979V9.49979C20.6242 9.49979 19.5049 10.6191 19.5049 11.9998C19.5049 13.3805 20.6242 14.4998 22.0049 14.4998V19.9998C22.0049 20.5521 21.5572 20.9998 21.0049 20.9998H3.00488C2.4526 20.9998 2.00488 20.5521 2.00488 19.9998V14.4998C3.38559 14.4998 4.50488 13.3805 4.50488 11.9998C4.50488 10.6191 3.38559 9.49979 2.00488 9.49979V3.99979C2.00488 3.4475 2.4526 2.99979 3.00488 2.99979H21.0049ZM20.0049 4.99979H4.00488V7.96779L4.16077 8.04886C5.49935 8.78084 6.42516 10.1733 6.49998 11.788L6.50488 11.9998C6.50488 13.704 5.55755 15.1869 4.16077 15.9507L4.00488 16.0308V18.9998H20.0049V16.0308L19.849 15.9507C18.5104 15.2187 17.5846 13.8263 17.5098 12.2116L17.5049 11.9998C17.5049 10.2956 18.4522 8.81266 19.849 8.04886L20.0049 7.96779V4.99979ZM16.0049 8.99979V14.9998H8.00488V8.99979H16.0049Z"
            case .catDaily: "M21 13.2422V20H22V22H2V20H3V13.2422C1.79401 12.435 1 11.0602 1 9.5C1 8.67286 1.22443 7.87621 1.63322 7.19746L4.3453 2.5C4.52393 2.1906 4.85406 2 5.21132 2H18.7887C19.1459 2 19.4761 2.1906 19.6547 2.5L22.3575 7.18172C22.7756 7.87621 23 8.67286 23 9.5C23 11.0602 22.206 12.435 21 13.2422ZM19 13.9725C18.8358 13.9907 18.669 14 18.5 14C17.2409 14 16.0789 13.478 15.25 12.6132C14.4211 13.478 13.2591 14 12 14C10.7409 14 9.5789 13.478 8.75 12.6132C7.9211 13.478 6.75911 14 5.5 14C5.331 14 5.16417 13.9907 5 13.9725V20H19V13.9725ZM5.78865 4L3.35598 8.21321C3.12409 8.59843 3 9.0389 3 9.5C3 10.8807 4.11929 12 5.5 12C6.53096 12 7.44467 11.3703 7.82179 10.4295C8.1574 9.59223 9.3426 9.59223 9.67821 10.4295C10.0553 11.3703 10.969 12 12 12C13.031 12 13.9447 11.3703 14.3218 10.4295C14.6574 9.59223 15.8426 9.59223 16.1782 10.4295C16.5553 11.3703 17.469 12 18.5 12C19.8807 12 21 10.8807 21 9.5C21 9.0389 20.8759 8.59843 20.6347 8.19746L18.2113 4H5.78865Z"
            case .catDigital: "M7 4V20H17V4H7ZM6 2H18C18.5523 2 19 2.44772 19 3V21C19 21.5523 18.5523 22 18 22H6C5.44772 22 5 21.5523 5 21V3C5 2.44772 5.44772 2 6 2ZM12 17C12.5523 17 13 17.4477 13 18C13 18.5523 12.5523 19 12 19C11.4477 19 11 18.5523 11 18C11 17.4477 11.4477 17 12 17Z"
            case .catOther: "M4.5 10.5C3.675 10.5 3 11.175 3 12C3 12.825 3.675 13.5 4.5 13.5C5.325 13.5 6 12.825 6 12C6 11.175 5.325 10.5 4.5 10.5ZM19.5 10.5C18.675 10.5 18 11.175 18 12C18 12.825 18.675 13.5 19.5 13.5C20.325 13.5 21 12.825 21 12C21 11.175 20.325 10.5 19.5 10.5ZM12 10.5C11.175 10.5 10.5 11.175 10.5 12C10.5 12.825 11.175 13.5 12 13.5C12.825 13.5 13.5 12.825 13.5 12C13.5 11.175 12.825 10.5 12 10.5Z"
            case .catAll: "M7 11.5C4.51472 11.5 2.5 9.48528 2.5 7C2.5 4.51472 4.51472 2.5 7 2.5C9.48528 2.5 11.5 4.51472 11.5 7C11.5 9.48528 9.48528 11.5 7 11.5ZM7 21.5C4.51472 21.5 2.5 19.4853 2.5 17C2.5 14.5147 4.51472 12.5 7 12.5C9.48528 12.5 11.5 14.5147 11.5 17C11.5 19.4853 9.48528 21.5 7 21.5ZM17 11.5C14.5147 11.5 12.5 9.48528 12.5 7C12.5 4.51472 14.5147 2.5 17 2.5C19.4853 2.5 21.5 4.51472 21.5 7C21.5 9.48528 19.4853 11.5 17 11.5ZM17 21.5C14.5147 21.5 12.5 19.4853 12.5 17C12.5 14.5147 14.5147 12.5 17 12.5C19.4853 12.5 21.5 14.5147 21.5 17C21.5 19.4853 19.4853 21.5 17 21.5ZM7 9.5C8.38071 9.5 9.5 8.38071 9.5 7C9.5 5.61929 8.38071 4.5 7 4.5C5.61929 4.5 4.5 5.61929 4.5 7C4.5 8.38071 5.61929 9.5 7 9.5ZM7 19.5C8.38071 19.5 9.5 18.3807 9.5 17C9.5 15.6193 8.38071 14.5 7 14.5C5.61929 14.5 4.5 15.6193 4.5 17C4.5 18.3807 5.61929 19.5 7 19.5ZM17 9.5C18.3807 9.5 19.5 8.38071 19.5 7C19.5 5.61929 18.3807 4.5 17 4.5C15.6193 4.5 14.5 5.61929 14.5 7C14.5 8.38071 15.6193 9.5 17 9.5ZM17 19.5C18.3807 19.5 19.5 18.3807 19.5 17C19.5 15.6193 18.3807 14.5 17 14.5C15.6193 14.5 14.5 15.6193 14.5 17C14.5 18.3807 15.6193 19.5 17 19.5Z"
            case .acctDebit: "M2 20H22V22H2V20ZM4 12H6V19H4V12ZM9 12H11V19H9V12ZM13 12H15V19H13V12ZM18 12H20V19H18V12ZM2 7L12 2L22 7V11H2V7ZM4 8.23607V9H20V8.23607L12 4.23607L4 8.23607ZM12 8C11.4477 8 11 7.55228 11 7C11 6.44772 11.4477 6 12 6C12.5523 6 13 6.44772 13 7C13 7.55228 12.5523 8 12 8Z"
            case .acctWallet: "M22.0049 6.99979H23.0049V16.9998H22.0049V19.9998C22.0049 20.5521 21.5572 20.9998 21.0049 20.9998H3.00488C2.4526 20.9998 2.00488 20.5521 2.00488 19.9998V3.99979C2.00488 3.4475 2.4526 2.99979 3.00488 2.99979H21.0049C21.5572 2.99979 22.0049 3.4475 22.0049 3.99979V6.99979ZM20.0049 16.9998H14.0049C11.2435 16.9998 9.00488 14.7612 9.00488 11.9998C9.00488 9.23836 11.2435 6.99979 14.0049 6.99979H20.0049V4.99979H4.00488V18.9998H20.0049V16.9998ZM21.0049 14.9998V8.99979H14.0049C12.348 8.99979 11.0049 10.3429 11.0049 11.9998C11.0049 13.6566 12.348 14.9998 14.0049 14.9998H21.0049ZM14.0049 10.9998H17.0049V12.9998H14.0049V10.9998Z"
            case .acctBalance: "M17.0047 16.0028H19.0047V4.00281H9.00468V6.00281H17.0047V16.0028ZM17.0047 18.0028V21.0019C17.0047 21.5547 16.5547 22.0028 15.9978 22.0028H4.01154C3.45548 22.0028 3.00488 21.5582 3.00488 21.0019L3.00748 7.00368C3.00759 6.45091 3.45752 6.00281 4.0143 6.00281H7.00468V3.00281C7.00468 2.45052 7.4524 2.00281 8.00468 2.00281H20.0047C20.557 2.00281 21.0047 2.45052 21.0047 3.00281V17.0028C21.0047 17.5551 20.557 18.0028 20.0047 18.0028H17.0047ZM5.0073 8.00281L5.00507 20.0028H15.0047V8.00281H5.0073ZM7.00468 16.0028H11.5047C11.7808 16.0028 12.0047 15.7789 12.0047 15.5028C12.0047 15.2267 11.7808 15.0028 11.5047 15.0028H8.50468C7.12397 15.0028 6.00468 13.8835 6.00468 12.5028C6.00468 11.1221 7.12397 10.0028 8.50468 10.0028H9.00468V9.00281H11.0047V10.0028H13.0047V12.0028H8.50468C8.22854 12.0028 8.00468 12.2267 8.00468 12.5028C8.00468 12.7789 8.22854 13.0028 8.50468 13.0028H11.5047C12.8854 13.0028 14.0047 14.1221 14.0047 15.5028C14.0047 16.8835 12.8854 18.0028 11.5047 18.0028H11.0047V19.0028H9.00468V18.0028H7.00468V16.0028Z"
            case .acctCredit: "M3.00488 2.99979H21.0049C21.5572 2.99979 22.0049 3.4475 22.0049 3.99979V19.9998C22.0049 20.5521 21.5572 20.9998 21.0049 20.9998H3.00488C2.4526 20.9998 2.00488 20.5521 2.00488 19.9998V3.99979C2.00488 3.4475 2.4526 2.99979 3.00488 2.99979ZM20.0049 10.9998H4.00488V18.9998H20.0049V10.9998ZM20.0049 8.99979V4.99979H4.00488V8.99979H20.0049ZM14.0049 14.9998H18.0049V16.9998H14.0049V14.9998Z"
            case .acctCash: "M12.0004 16C14.2095 16 16.0004 14.2091 16.0004 12 16.0004 9.79086 14.2095 8 12.0004 8 9.79123 8 8.00037 9.79086 8.00037 12 8.00037 14.2091 9.79123 16 12.0004 16ZM21.0049 4.00293H3.00488C2.4526 4.00293 2.00488 4.45064 2.00488 5.00293V19.0029C2.00488 19.5552 2.4526 20.0029 3.00488 20.0029H21.0049C21.5572 20.0029 22.0049 19.5552 22.0049 19.0029V5.00293C22.0049 4.45064 21.5572 4.00293 21.0049 4.00293ZM4.00488 15.6463V8.35371C5.13065 8.017 6.01836 7.12892 6.35455 6.00293H17.6462C17.9833 7.13193 18.8748 8.02175 20.0049 8.3564V15.6436C18.8729 15.9788 17.9802 16.8711 17.6444 18.0029H6.3563C6.02144 16.8742 5.13261 15.9836 4.00488 15.6463Z"
            case .acctInvest: "M8.00488 5.00281H11.0049V14.0028H8.00488V17.0028H6.00488V14.0028H3.00488V5.00281H6.00488V2.00281H8.00488V5.00281ZM5.00488 7.00281V12.0028H9.00488V7.00281H5.00488ZM18.0049 10.0028H21.0049V19.0028H18.0049V22.0028H16.0049V19.0028H13.0049V10.0028H16.0049V7.00281H18.0049V10.0028ZM15.0049 12.0028V17.0028H19.0049V12.0028H15.0049Z"
            case .saveFirst: "M5.00488 9.00281C5.55717 9.00281 6.00488 9.45052 6.00488 10.0028C7.63965 10.0028 9.14352 10.5632 10.3349 11.5023L12.5049 11.5028C13.8375 11.5028 15.0348 12.0821 15.8588 13.0025L19.0049 13.0028C20.9972 13.0028 22.7173 14.1681 23.521 15.8542C21.1562 18.9748 17.3268 21.0028 13.0049 21.0028C10.2142 21.0028 7.85466 20.3996 5.944 19.3449C5.80557 19.7284 5.43727 20.0028 5.00488 20.0028H2.00488C1.4526 20.0028 1.00488 19.5551 1.00488 19.0028V10.0028C1.00488 9.45052 1.4526 9.00281 2.00488 9.00281H5.00488ZM6.00589 12.0028L6.00488 17.0248L6.05024 17.0573C7.84406 18.3177 10.183 19.0028 13.0049 19.0028C16.0089 19.0028 18.8035 17.8472 20.84 15.8734L20.9729 15.7398L20.8537 15.6394C20.3897 15.2764 19.8205 15.0512 19.2099 15.0097L19.0049 15.0028L16.8934 15.0028C16.9664 15.3244 17.0049 15.6591 17.0049 16.0028V17.0028H8.00488V15.0028L14.7949 15.0018L14.7605 14.9233C14.38 14.1297 13.593 13.5681 12.6693 13.5081L12.5049 13.5028L9.57547 13.5027C8.66823 12.5773 7.40412 12.0031 6.00589 12.0028ZM4.00488 11.0028H3.00488V18.0028H4.00488V11.0028ZM18.0049 5.00281C19.6617 5.00281 21.0049 6.34595 21.0049 8.00281C21.0049 9.65966 19.6617 11.0028 18.0049 11.0028C16.348 11.0028 15.0049 9.65966 15.0049 8.00281C15.0049 6.34595 16.348 5.00281 18.0049 5.00281ZM18.0049 7.00281C17.4526 7.00281 17.0049 7.45052 17.0049 8.00281C17.0049 8.55509 17.4526 9.00281 18.0049 9.00281C18.5572 9.00281 19.0049 8.55509 19.0049 8.00281C19.0049 7.45052 18.5572 7.00281 18.0049 7.00281ZM11.0049 2.00281C12.6617 2.00281 14.0049 3.34595 14.0049 5.00281C14.0049 6.65966 12.6617 8.00281 11.0049 8.00281C9.34803 8.00281 8.00488 6.65966 8.00488 5.00281C8.00488 3.34595 9.34803 2.00281 11.0049 2.00281ZM11.0049 4.00281C10.4526 4.00281 10.0049 4.45052 10.0049 5.00281C10.0049 5.55509 10.4526 6.00281 11.0049 6.00281C11.5572 6.00281 12.0049 5.55509 12.0049 5.00281C12.0049 4.45052 11.5572 4.00281 11.0049 4.00281Z"
            case .floor: "M18.0049 19.9998H6.00488V21.9998H4.00488V19.9998H3.00488C2.4526 19.9998 2.00488 19.5521 2.00488 18.9998V3.99979C2.00488 3.4475 2.4526 2.99979 3.00488 2.99979H21.0049C21.5572 2.99979 22.0049 3.4475 22.0049 3.99979V18.9998C22.0049 19.5521 21.5572 19.9998 21.0049 19.9998H20.0049V21.9998H18.0049V19.9998ZM4.00488 17.9998H20.0049V4.99979H4.00488V17.9998ZM13.0049 13.8738V16.9998H11.0049V13.8738C9.27966 13.4297 8.00488 11.8636 8.00488 9.99979C8.00488 7.79065 9.79574 5.99979 12.0049 5.99979C14.214 5.99979 16.0049 7.79065 16.0049 9.99979C16.0049 11.8636 14.7301 13.4297 13.0049 13.8738ZM12.0049 11.9998C13.1095 11.9998 14.0049 11.1044 14.0049 9.99979C14.0049 8.89522 13.1095 7.99979 12.0049 7.99979C10.9003 7.99979 10.0049 8.89522 10.0049 9.99979C10.0049 11.1044 10.9003 11.9998 12.0049 11.9998Z"
            case .subscription: "M8 20V21.9324C8 22.2086 7.77614 22.4324 7.5 22.4324C7.38303 22.4324 7.26977 22.3914 7.17991 22.3165L3.06093 18.8841C2.84879 18.7073 2.82013 18.392 2.99691 18.1799C3.09191 18.0659 3.23264 18 3.38103 18L18 18C19.1046 18 20 17.1045 20 16V7.99997H22V16C22 18.2091 20.2091 20 18 20H8ZM16 3.99997V2.0675C16 1.79136 16.2239 1.5675 16.5 1.5675C16.617 1.5675 16.7302 1.60851 16.8201 1.68339L20.9391 5.11587C21.1512 5.29266 21.1799 5.60794 21.0031 5.82008C20.9081 5.93407 20.7674 5.99998 20.619 5.99998L6 5.99997C4.89543 5.99997 4 6.8954 4 7.99997V16H2V7.99997C2 5.79083 3.79086 3.99997 6 3.99997H16Z"
            case .cycle: "M9 1V3H15V1H17V3H21C21.5523 3 22 3.44772 22 4V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V4C2 3.44772 2.44772 3 3 3H7V1H9ZM20 11H4V19H20V11ZM7 5H4V9H20V5H17V7H15V5H9V7H7V5Z"
            case .tabHome: "M13 19H19V9.97815L12 4.53371L5 9.97815V19H11V13H13V19ZM21 20C21 20.5523 20.5523 21 20 21H4C3.44772 21 3 20.5523 3 20V9.48907C3 9.18048 3.14247 8.88917 3.38606 8.69972L11.3861 2.47749C11.7472 2.19663 12.2528 2.19663 12.6139 2.47749L20.6139 8.69972C20.8575 8.88917 21 9.18048 21 9.48907V20Z"
            case .tabOverview: "M3 3H21C21.5523 3 22 3.44772 22 4V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V4C2 3.44772 2.44772 3 3 3ZM4 5V19H20V5H4ZM7 13H9V17H7V13ZM11 7H13V17H11V7ZM15 10H17V17H15V10Z"
            case .transfer: "M16.0503 12.0498L21 16.9996L16.0503 21.9493L14.636 20.5351L17.172 17.9988L4 17.9996V15.9996L17.172 15.9988L14.636 13.464L16.0503 12.0498ZM7.94975 2.0498L9.36396 3.46402L6.828 5.9988L20 5.99955V7.99955L6.828 7.9988L9.36396 10.5351L7.94975 11.9493L3 6.99955L7.94975 2.0498Z"
            case .reimburse: "M9 4L6 2L3 4V19C3 20.6569 4.34315 22 6 22H20C21.6569 22 23 20.6569 23 19V16H21V4L18 2L15 4L12 2L9 4ZM19 16H7V19C7 19.5523 6.55228 20 6 20C5.44772 20 5 19.5523 5 19V5.07037L6 4.4037L9 6.4037L12 4.4037L15 6.4037L18 4.4037L19 5.07037V16ZM20 20H8.82929C8.93985 19.6872 9 19.3506 9 19V18H21V19C21 19.5523 20.5523 20 20 20Z"
            case .ai: "M14 4.4375C15.3462 4.4375 16.4375 3.34619 16.4375 2H17.5625C17.5625 3.34619 18.6538 4.4375 20 4.4375V5.5625C18.6538 5.5625 17.5625 6.65381 17.5625 8H16.4375C16.4375 6.65381 15.3462 5.5625 14 5.5625V4.4375ZM1 11C4.31371 11 7 8.31371 7 5H9C9 8.31371 11.6863 11 15 11V13C11.6863 13 9 15.6863 9 19H7C7 15.6863 4.31371 13 1 13V11ZM4.87601 12C6.18717 12.7276 7.27243 13.8128 8 15.124 8.72757 13.8128 9.81283 12.7276 11.124 12 9.81283 11.2724 8.72757 10.1872 8 8.87601 7.27243 10.1872 6.18717 11.2724 4.87601 12ZM17.25 14C17.25 15.7949 15.7949 17.25 14 17.25V18.75C15.7949 18.75 17.25 20.2051 17.25 22H18.75C18.75 20.2051 20.2051 18.75 22 18.75V17.25C20.2051 17.25 18.75 15.7949 18.75 14H17.25Z"
            case .memory: "M9 4C10.1046 4 11 4.89543 11 6V12.8271C10.1058 12.1373 8.96602 11.7305 7.6644 11.5136L7.3356 13.4864C8.71622 13.7165 9.59743 14.1528 10.1402 14.7408C10.67 15.3147 11 16.167 11 17.5C11 18.8807 9.88071 20 8.5 20C7.11929 20 6 18.8807 6 17.5V17.1493C6.43007 17.2926 6.87634 17.4099 7.3356 17.4864L7.6644 15.5136C6.92149 15.3898 6.1752 15.1144 5.42909 14.7599C4.58157 14.3573 4 13.499 4 12.5C4 11.6653 4.20761 11.0085 4.55874 10.5257C4.90441 10.0504 5.4419 9.6703 6.24254 9.47014L7 9.28078V6C7 4.89543 7.89543 4 9 4ZM12 3.35418C11.2671 2.52376 10.1947 2 9 2C6.79086 2 5 3.79086 5 6V7.77422C4.14895 8.11644 3.45143 8.64785 2.94126 9.34933C2.29239 10.2415 2 11.3347 2 12.5C2 14.0652 2.79565 15.4367 4 16.2422V17.5C4 19.9853 6.01472 22 8.5 22C9.91363 22 11.175 21.3482 12 20.3287C12.825 21.3482 14.0864 22 15.5 22C17.9853 22 20 19.9853 20 17.5V16.2422C21.2044 15.4367 22 14.0652 22 12.5C22 11.3347 21.7076 10.2415 21.0587 9.34933C20.5486 8.64785 19.8511 8.11644 19 7.77422V6C19 3.79086 17.2091 2 15 2C13.8053 2 12.7329 2.52376 12 3.35418ZM18 17.1493V17.5C18 18.8807 16.8807 20 15.5 20C14.1193 20 13 18.8807 13 17.5C13 16.167 13.33 15.3147 13.8598 14.7408C14.4026 14.1528 15.2838 13.7165 16.6644 13.4864L16.3356 11.5136C15.034 11.7305 13.8942 12.1373 13 12.8271V6C13 4.89543 13.8954 4 15 4C16.1046 4 17 4.89543 17 6V9.28078L17.7575 9.47014C18.5581 9.6703 19.0956 10.0504 19.4413 10.5257C19.7924 11.0085 20 11.6653 20 12.5C20 13.499 19.4184 14.3573 18.5709 14.7599C17.8248 15.1144 17.0785 15.3898 16.3356 15.5136L16.6644 17.4864C17.1237 17.4099 17.5699 17.2926 18 17.1493Z"
            case .screenshot: "M2.9918 21C2.44405 21 2 20.5551 2 20.0066V3.9934C2 3.44476 2.45531 3 2.9918 3H21.0082C21.556 3 22 3.44495 22 3.9934V20.0066C22 20.5552 21.5447 21 21.0082 21H2.9918ZM20 15V5H4V19L14 9L20 15ZM20 17.8284L14 11.8284L6.82843 19H20V17.8284ZM8 11C6.89543 11 6 10.1046 6 9C6 7.89543 6.89543 7 8 7C9.10457 7 10 7.89543 10 9C10 10.1046 9.10457 11 8 11Z"
            case .voice: "M11.9998 3C10.3429 3 8.99976 4.34315 8.99976 6V10C8.99976 11.6569 10.3429 13 11.9998 13C13.6566 13 14.9998 11.6569 14.9998 10V6C14.9998 4.34315 13.6566 3 11.9998 3ZM11.9998 1C14.7612 1 16.9998 3.23858 16.9998 6V10C16.9998 12.7614 14.7612 15 11.9998 15C9.23833 15 6.99976 12.7614 6.99976 10V6C6.99976 3.23858 9.23833 1 11.9998 1ZM3.05469 11H5.07065C5.55588 14.3923 8.47329 17 11.9998 17C15.5262 17 18.4436 14.3923 18.9289 11H20.9448C20.4837 15.1716 17.1714 18.4839 12.9998 18.9451V23H10.9998V18.9451C6.82814 18.4839 3.51584 15.1716 3.05469 11Z"
            case .cloud: "M12 2C15.866 2 19 5.13401 19 9C19 9.11351 18.9973 9.22639 18.992 9.33857C21.3265 10.16 23 12.3846 23 15C23 18.3137 20.3137 21 17 21H7C3.68629 21 1 18.3137 1 15C1 12.3846 2.67346 10.16 5.00804 9.33857C5.0027 9.22639 5 9.11351 5 9C5 5.13401 8.13401 2 12 2ZM12 4C9.23858 4 7 6.23858 7 9C7 9.08147 7.00193 9.16263 7.00578 9.24344L7.07662 10.7309L5.67183 11.2252C4.0844 11.7837 3 13.2889 3 15C3 17.2091 4.79086 19 7 19H17C19.2091 19 21 17.2091 21 15C21 12.79 19.21 11 17 11C15.233 11 13.7337 12.1457 13.2042 13.7347L11.3064 13.1021C12.1005 10.7185 14.35 9 17 9C17 6.23858 14.7614 4 12 4Z"
            case .export: "M10 3V5H5V19H19V14H21V20C21 20.5523 20.5523 21 20 21H4C3.44772 21 3 20.5523 3 20V4C3 3.44772 3.44772 3 4 3H10ZM17.5858 5H13V3H21V11H19V6.41421L12 13.4142L10.5858 12L17.5858 5Z"
            case .chevron: "M13.1717 12.0007L8.22192 7.05093L9.63614 5.63672L16.0001 12.0007L9.63614 18.3646L8.22192 16.9504L13.1717 12.0007Z"
            case .chevronDown: "M11.9999 13.1714L16.9497 8.22168L18.3639 9.63589L11.9999 15.9999L5.63599 9.63589L7.0502 8.22168L11.9999 13.1714Z"
            case .back: "M10.8284 12.0007L15.7782 16.9504L14.364 18.3646L8 12.0007L14.364 5.63672L15.7782 7.05093L10.8284 12.0007Z"
            case .close: "M11.9997 10.5865L16.9495 5.63672L18.3637 7.05093L13.4139 12.0007L18.3637 16.9504L16.9495 18.3646L11.9997 13.4149L7.04996 18.3646L5.63574 16.9504L10.5855 12.0007L5.63574 7.05093L7.04996 5.63672L11.9997 10.5865Z"
            case .more: "M4.5 10.5C3.675 10.5 3 11.175 3 12C3 12.825 3.675 13.5 4.5 13.5C5.325 13.5 6 12.825 6 12C6 11.175 5.325 10.5 4.5 10.5ZM19.5 10.5C18.675 10.5 18 11.175 18 12C18 12.825 18.675 13.5 19.5 13.5C20.325 13.5 21 12.825 21 12C21 11.175 20.325 10.5 19.5 10.5ZM12 10.5C11.175 10.5 10.5 11.175 10.5 12C10.5 12.825 11.175 13.5 12 13.5C12.825 13.5 13.5 12.825 13.5 12C13.5 11.175 12.825 10.5 12 10.5Z"
            case .add: "M11 11V5H13V11H19V13H13V19H11V13H5V11H11Z"
            case .time: "M12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12C22 17.5228 17.5228 22 12 22ZM12 20C16.4183 20 20 16.4183 20 12C20 7.58172 16.4183 4 12 4C7.58172 4 4 7.58172 4 12C4 16.4183 7.58172 20 12 20ZM13 12H17V14H11V7H13V12Z"
            case .search: "M18.031 16.6168L22.3137 20.8995L20.8995 22.3137L16.6168 18.031C15.0769 19.263 13.124 20 11 20C6.032 20 2 15.968 2 11C2 6.032 6.032 2 11 2C15.968 2 20 6.032 20 11C20 13.124 19.263 15.0769 18.031 16.6168ZM16.0247 15.8748C17.2475 14.6146 18 12.8956 18 11C18 7.1325 14.8675 4 11 4C7.1325 4 4 7.1325 4 11C4 14.8675 7.1325 18 11 18C12.8956 18 14.6146 17.2475 15.8748 16.0247L16.0247 15.8748Z"
            case .edit: "M5 18.89H6.41421L15.7279 9.57627L14.3137 8.16206L5 17.4758V18.89ZM21 20.89H3V16.6473L16.435 3.21231C16.8256 2.82179 17.4587 2.82179 17.8492 3.21231L20.6777 6.04074C21.0682 6.43126 21.0682 7.06443 20.6777 7.45495L9.24264 18.89H21V20.89ZM15.7279 6.74785L17.1421 8.16206L18.5563 6.74785L17.1421 5.33363L15.7279 6.74785Z"
            case .delete: "M17 6H22V8H20V21C20 21.5523 19.5523 22 19 22H5C4.44772 22 4 21.5523 4 21V8H2V6H7V3C7 2.44772 7.44772 2 8 2H16C16.5523 2 17 2.44772 17 3V6ZM18 8H6V20H18V8ZM9 11H11V17H9V11ZM13 11H15V17H13V11ZM9 4V6H15V4H9Z"
            case .recategorize: "M10.9042 2.10025L20.8037 3.51446L22.2179 13.414L13.0255 22.6063C12.635 22.9969 12.0019 22.9969 11.6113 22.6063L1.71184 12.7069C1.32131 12.3163 1.32131 11.6832 1.71184 11.2926L10.9042 2.10025ZM11.6113 4.22157L3.83316 11.9997L12.3184 20.485L20.0966 12.7069L19.036 5.28223L11.6113 4.22157ZM13.7327 10.5855C12.9516 9.80448 12.9516 8.53815 13.7327 7.7571C14.5137 6.97606 15.78 6.97606 16.5611 7.7571C17.3421 8.53815 17.3421 9.80448 16.5611 10.5855C15.78 11.3666 14.5137 11.3666 13.7327 10.5855Z"
            case .duplicate: "M6.9998 6V3C6.9998 2.44772 7.44752 2 7.9998 2H19.9998C20.5521 2 20.9998 2.44772 20.9998 3V17C20.9998 17.5523 20.5521 18 19.9998 18H16.9998V20.9991C16.9998 21.5519 16.5499 22 15.993 22H4.00666C3.45059 22 3 21.5554 3 20.9991L3.0026 7.00087C3.0027 6.44811 3.45264 6 4.00942 6H6.9998ZM5.00242 8L5.00019 20H14.9998V8H5.00242ZM8.9998 6H16.9998V16H18.9998V4H8.9998V6Z"
            case .done: "M9.9997 15.1709L19.1921 5.97852L20.6063 7.39273L9.9997 17.9993L3.63574 11.6354L5.04996 10.2212L9.9997 15.1709Z"
            case .backspace: "M6.53451 3H20.9993C21.5516 3 21.9993 3.44772 21.9993 4V20C21.9993 20.5523 21.5516 21 20.9993 21H6.53451C6.20015 21 5.88792 20.8329 5.70246 20.5547L0.369122 12.5547C0.145189 12.2188 0.145189 11.7812 0.369122 11.4453L5.70246 3.4453C5.88792 3.1671 6.20015 3 6.53451 3ZM7.06969 5L2.40302 12L7.06969 19H19.9993V5H7.06969ZM12.9993 10.5858L15.8277 7.75736L17.242 9.17157L14.4135 12L17.242 14.8284L15.8277 16.2426L12.9993 13.4142L10.1709 16.2426L8.75668 14.8284L11.5851 12L8.75668 9.17157L10.1709 7.75736L12.9993 10.5858Z"
            case .settings: "M3.33946 17.0002C2.90721 16.2515 2.58277 15.4702 2.36133 14.6741C3.3338 14.1779 3.99972 13.1668 3.99972 12.0002C3.99972 10.8345 3.3348 9.824 2.36353 9.32741C2.81025 7.71651 3.65857 6.21627 4.86474 4.99001C5.7807 5.58416 6.98935 5.65534 7.99972 5.072C9.01009 4.48866 9.55277 3.40635 9.4962 2.31604C11.1613 1.8846 12.8847 1.90004 14.5031 2.31862C14.4475 3.40806 14.9901 4.48912 15.9997 5.072C17.0101 5.65532 18.2187 5.58416 19.1346 4.99007C19.7133 5.57986 20.2277 6.25151 20.66 7.00021C21.0922 7.7489 21.4167 8.53025 21.6381 9.32628C20.6656 9.82247 19.9997 10.8336 19.9997 12.0002C19.9997 13.166 20.6646 14.1764 21.6359 14.673C21.1892 16.2839 20.3409 17.7841 19.1347 19.0104C18.2187 18.4163 17.0101 18.3451 15.9997 18.9284C14.9893 19.5117 14.4467 20.5941 14.5032 21.6844C12.8382 22.1158 11.1148 22.1004 9.49633 21.6818C9.55191 20.5923 9.00929 19.5113 7.99972 18.9284C6.98938 18.3451 5.78079 18.4162 4.86484 19.0103C4.28617 18.4205 3.77172 17.7489 3.33946 17.0002ZM8.99972 17.1964C10.0911 17.8265 10.8749 18.8227 11.2503 19.9659C11.7486 20.0133 12.2502 20.014 12.7486 19.9675C13.1238 18.8237 13.9078 17.8268 14.9997 17.1964C16.0916 16.5659 17.347 16.3855 18.5252 16.6324C18.8146 16.224 19.0648 15.7892 19.2729 15.334C18.4706 14.4373 17.9997 13.2604 17.9997 12.0002C17.9997 10.74 18.4706 9.5632 19.2729 8.6665C19.1688 8.4405 19.0538 8.21822 18.9279 8.00021C18.802 7.78219 18.667 7.57148 18.5233 7.36842C17.3457 7.61476 16.0911 7.43414 14.9997 6.80405C13.9083 6.17395 13.1246 5.17768 12.7491 4.03455C12.2509 3.98714 11.7492 3.98646 11.2509 4.03292C10.8756 5.17671 10.0916 6.17364 8.99972 6.80405C7.9078 7.43447 6.65245 7.61494 5.47428 7.36803C5.18485 7.77641 4.93463 8.21117 4.72656 8.66637C5.52881 9.56311 5.99972 10.74 5.99972 12.0002C5.99972 13.2604 5.52883 14.4372 4.72656 15.3339C4.83067 15.5599 4.94564 15.7822 5.07152 16.0002C5.19739 16.2182 5.3324 16.4289 5.47612 16.632C6.65377 16.3857 7.90838 16.5663 8.99972 17.1964ZM11.9997 15.0002C10.3429 15.0002 8.99972 13.6571 8.99972 12.0002C8.99972 10.3434 10.3429 9.00021 11.9997 9.00021C13.6566 9.00021 14.9997 10.3434 14.9997 12.0002C14.9997 13.6571 13.6566 15.0002 11.9997 15.0002ZM11.9997 13.0002C12.552 13.0002 12.9997 12.5525 12.9997 12.0002C12.9997 11.4479 12.552 11.0002 11.9997 11.0002C11.4474 11.0002 10.9997 11.4479 10.9997 12.0002C10.9997 12.5525 11.4474 13.0002 11.9997 13.0002Z"
            case .bolt: "M6.93912 14.0328C6.7072 14.6563 6.51032 15.2331 6.33421 15.8155C7.29345 15.1189 8.43544 14.6767 9.75193 14.5121C12.2652 14.198 14.4976 12.5385 15.6279 10.4537L14.1721 8.99888L15.5848 7.58417C15.9185 7.25004 16.2521 6.91614 16.5858 6.58248C17.0151 6.15312 17.5 5.35849 18.0129 4.2149C12.4197 5.08182 8.99484 8.50647 6.93912 14.0328ZM17 8.99739L18 9.99669C17 12.9967 14 15.9967 10 16.4967C7.33146 16.8303 5.66421 18.6636 4.99824 21.9967H3C4 15.9967 6 1.99669 21 1.99669C20.0009 4.99402 19.0018 6.99313 18.0027 7.99402C17.6662 8.33049 17.3331 8.66382 17 8.99739Z"
            case .bell: "M20 17H22V19H2V17H4V10C4 5.58172 7.58172 2 12 2C16.4183 2 20 5.58172 20 10V17ZM18 17V10C18 6.68629 15.3137 4 12 4C8.68629 4 6 6.68629 6 10V17H18ZM9 21H15V23H9V21Z"
            case .half: "M12 2C17.5222 2 22 5.97778 22 10.8889C22 13.9556 19.5111 16.4444 16.4444 16.4444H14.4778C13.5556 16.4444 12.8111 17.1889 12.8111 18.1111C12.8111 18.5333 12.9778 18.9222 13.2333 19.2111C13.5 19.5111 13.6667 19.9 13.6667 20.3333C13.6667 21.2556 12.9 22 12 22C6.47778 22 2 17.5222 2 12C2 6.47778 6.47778 2 12 2ZM10.8111 18.1111C10.8111 16.0843 12.451 14.4444 14.4778 14.4444H16.4444C18.4065 14.4444 20 12.851 20 10.8889C20 7.1392 16.4677 4 12 4C7.58235 4 4 7.58235 4 12C4 16.19 7.2226 19.6285 11.324 19.9718C10.9948 19.4168 10.8111 18.7761 10.8111 18.1111ZM7.5 12C6.67157 12 6 11.3284 6 10.5C6 9.67157 6.67157 9 7.5 9C8.32843 9 9 9.67157 9 10.5C9 11.3284 8.32843 12 7.5 12ZM16.5 12C15.6716 12 15 11.3284 15 10.5C15 9.67157 15.6716 9 16.5 9C17.3284 9 18 9.67157 18 10.5C18 11.3284 17.3284 12 16.5 12ZM12 9C11.1716 9 10.5 8.32843 10.5 7.5C10.5 6.67157 11.1716 6 12 6C12.8284 6 13.5 6.67157 13.5 7.5C13.5 8.32843 12.8284 9 12 9Z"
            case .inbox: "M13 10H18L12 16L6 10H11V3H13V10ZM4 19H20V12H22V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V12H4V19Z"
            case .clock: "M12 2C17.5228 2 22 6.47715 22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12H4C4 16.4183 7.58172 20 12 20C16.4183 20 20 16.4183 20 12C20 7.58172 16.4183 4 12 4C9.25022 4 6.82447 5.38734 5.38451 7.50024L8 7.5V9.5H2V3.5H4L3.99989 5.99918C5.82434 3.57075 8.72873 2 12 2ZM13 7L12.9998 11.585L16.2426 14.8284L14.8284 16.2426L10.9998 12.413L11 7H13Z"
            case .disk: "M5 12.5C5 12.8134 5.46101 13.3584 6.53047 13.8931C7.91405 14.5849 9.87677 15 12 15C14.1232 15 16.0859 14.5849 17.4695 13.8931C18.539 13.3584 19 12.8134 19 12.5V10.3287C17.35 11.3482 14.8273 12 12 12C9.17273 12 6.64996 11.3482 5 10.3287V12.5ZM19 15.3287C17.35 16.3482 14.8273 17 12 17C9.17273 17 6.64996 16.3482 5 15.3287V17.5C5 17.8134 5.46101 18.3584 6.53047 18.8931C7.91405 19.5849 9.87677 20 12 20C14.1232 20 16.0859 19.5849 17.4695 18.8931C18.539 18.3584 19 17.8134 19 17.5V15.3287ZM3 17.5V7.5C3 5.01472 7.02944 3 12 3C16.9706 3 21 5.01472 21 7.5V17.5C21 19.9853 16.9706 22 12 22C7.02944 22 3 19.9853 3 17.5ZM12 10C14.1232 10 16.0859 9.58492 17.4695 8.89313C18.539 8.3584 19 7.81342 19 7.5C19 7.18658 18.539 6.6416 17.4695 6.10687C16.0859 5.41508 14.1232 5 12 5C9.87677 5 7.91405 5.41508 6.53047 6.10687C5.46101 6.6416 5 7.18658 5 7.5C5 7.81342 5.46101 8.3584 6.53047 8.89313C7.91405 9.58492 9.87677 10 12 10Z"
            case .lock: "M3 8V5a2 2 0 0 1 2-2h3v2H5v3Z M21 8V5a2 2 0 0 0-2-2h-3v2h3v3Z M3 16v3a2 2 0 0 0 2 2h3v-2H5v-3Z M21 16v3a2 2 0 0 1-2 2h-3v-2h3v-3Z M7.7 8.8a.9.9 0 0 1 1.8 0v1.6a.9.9 0 0 1-1.8 0Z M14.5 8.8a.9.9 0 0 1 1.8 0v1.6a.9.9 0 0 1-1.8 0Z M11.2 8.8a.8.8 0 0 1 1.6 0v3a1.4 1.4 0 0 1-1.4 1.4H11a.8.8 0 0 1 0-1.6h.2Z M8.3 14.6a.9.9 0 0 1 1.3 0A3.4 3.4 0 0 0 12 15.6a3.4 3.4 0 0 0 2.4-1a.9.9 0 0 1 1.3 1.3A5.2 5.2 0 0 1 12 17.4a5.2 5.2 0 0 1-3.7-1.5a.9.9 0 0 1 0-1.3Z"
            case .arrowOut: "M4 19H20V12H22V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V12H4V19ZM13 9V16H11V9H6L12 3L18 9H13Z"
            case .heart: "M16.5 3C19.5376 3 22 5.5 22 9C22 16 14.5 20 12 21.5C9.5 20 2 16 2 9C2 5.5 4.5 3 7.5 3C9.35997 3 11 4 12 5C13 4 14.64 3 16.5 3ZM12.9339 18.6038C13.8155 18.0485 14.61 17.4955 15.3549 16.9029C18.3337 14.533 20 11.9435 20 9C20 6.64076 18.463 5 16.5 5C15.4241 5 14.2593 5.56911 13.4142 6.41421L12 7.82843L10.5858 6.41421C9.74068 5.56911 8.5759 5 7.5 5C5.55906 5 4 6.6565 4 9C4 11.9435 5.66627 14.533 8.64514 16.9029C9.39 17.4955 10.1845 18.0485 11.0661 18.6038C11.3646 18.7919 11.6611 18.9729 12 19.1752C12.3389 18.9729 12.6354 18.7919 12.9339 18.6038Z"
            case .mail: "M3 3H21C21.5523 3 22 3.44772 22 4V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V4C2 3.44772 2.44772 3 3 3ZM20 7.23792L12.0718 14.338L4 7.21594V19H20V7.23792ZM4.51146 5L12.0619 11.662L19.501 5H4.51146Z"
            case .compass: "M12.9985 2L12.9979 3.278L17.9985 4.94591L21.631 3.73509L22.2634 5.63246L19.2319 6.643L22.3272 15.1549C21.2353 16.2921 19.6996 17 17.9985 17C16.2975 17 14.7618 16.2921 13.6699 15.1549L16.7639 6.643L12.9979 5.387V19H16.9985V21H6.99854V19H10.9979V5.387L7.23192 6.643L10.3272 15.1549C9.23528 16.2921 7.69957 17 5.99854 17C4.2975 17 2.76179 16.2921 1.66992 15.1549L4.76392 6.643L1.73363 5.63246L2.36608 3.73509L5.99854 4.94591L10.9979 3.278L10.9985 2H12.9985ZM17.9985 9.10267L16.04 14.4892C16.628 14.8201 17.2979 15 17.9985 15C18.6992 15 19.3691 14.8201 19.957 14.4892L17.9985 9.10267ZM5.99854 9.10267L4.04004 14.4892C4.62795 14.8201 5.29792 15 5.99854 15C6.69916 15 7.36912 14.8201 7.95703 14.4892L5.99854 9.10267Z"
            case .chat: "M15 3H15.8A5.2 5.2 0 0 1 21 8.2V12.8A5.2 5.2 0 0 1 15.8 18H15V9.9H18.1V5.9H15Z M14.4 6.4H16.6A1 1 0 0 1 17.6 7.4V8.4A1 1 0 0 1 16.6 9.4H14.4A1 1 0 0 1 13.4 8.4V7.4A1 1 0 0 1 14.4 6.4Z"
            case .catHealth: "M16 1C16.5523 1 17 1.44772 17 2V5H21C21.5523 5 22 5.44772 22 6V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V6C2 5.44772 2.44772 5 3 5H7V2C7 1.44772 7.44772 1 8 1H16ZM20 7H4V19H20V7ZM13 9V12H16V14H12.999L13 17H11L10.999 14H8V12H11V9H13ZM15 3H9V5H15V3Z"
            case .catBeauty: "M9.44618 8.02867L12 10.5825L18.7279 3.85457C19.509 3.07352 20.7753 3.07352 21.5563 3.85457L9.44618 15.9647C9.79807 16.5603 10 17.2549 10 17.9967C10 20.2058 8.20914 21.9967 6 21.9967C3.79086 21.9967 2 20.2058 2 17.9967C2 15.7876 3.79086 13.9967 6 13.9967C6.74181 13.9967 7.43645 14.1986 8.03197 14.5505L10.5858 11.9967L8.03197 9.44289C7.43645 9.79478 6.74181 9.9967 6 9.9967C3.79086 9.9967 2 8.20584 2 5.9967C2 3.78756 3.79086 1.9967 6 1.9967C8.20914 1.9967 10 3.78756 10 5.9967C10 6.73851 9.79807 7.43316 9.44618 8.02867ZM14.8255 13.408L21.5563 20.1388C20.7753 20.9199 19.509 20.9199 18.7279 20.1388L13.4113 14.8222L14.8255 13.408ZM7.41421 16.5825C7.05228 16.2206 6.55228 15.9967 6 15.9967C4.89543 15.9967 4 16.8921 4 17.9967C4 19.1013 4.89543 19.9967 6 19.9967C7.10457 19.9967 8 19.1013 8 17.9967C8 17.4444 7.77614 16.9444 7.41421 16.5825ZM7.41421 7.41092C7.77614 7.04899 8 6.54899 8 5.9967C8 4.89213 7.10457 3.9967 6 3.9967C4.89543 3.9967 4 4.89213 4 5.9967C4 7.10127 4.89543 7.9967 6 7.9967C6.55228 7.9967 7.05228 7.77285 7.41421 7.41092Z"
            case .catTravel: "M15 3C15.5523 3 16 3.44772 16 4V6H21C21.5523 6 22 6.44772 22 7V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V7C2 6.44772 2.44772 6 3 6H8V4C8 3.44772 8.44772 3 9 3H15ZM16 8H8V19H16V8ZM4 8V19H6V8H4ZM14 5H10V6H14V5ZM18 8V19H20V8H18Z"
            case .catMembership: "M3.49709 8.06464L4.78355 18.9996H19.2266L20.513 8.06464L16.5032 10.7379L12.0051 4.44051L7.50694 10.7379L3.49709 8.06464ZM2.80577 5.20006L7.00505 7.99958L11.1913 2.13881C11.5123 1.6894 12.1369 1.58531 12.5863 1.90631C12.6761 1.97045 12.7546 2.04901 12.8188 2.13881L17.0051 7.99958L21.2043 5.20006C21.6639 4.89371 22.2847 5.01788 22.5911 5.47741C22.7228 5.67503 22.7799 5.91308 22.7522 6.14895L21.109 20.1164C21.0497 20.62 20.6229 20.9996 20.1158 20.9996H3.8943C3.38722 20.9996 2.9604 20.62 2.90115 20.1164L1.25792 6.14895C1.19339 5.60045 1.58573 5.10349 2.13423 5.03896C2.37011 5.01121 2.60816 5.06832 2.80577 5.20006ZM12.0051 14.9996C10.9005 14.9996 10.0051 14.1042 10.0051 12.9996C10.0051 11.895 10.9005 10.9996 12.0051 10.9996C13.1096 10.9996 14.0051 11.895 14.0051 12.9996C14.0051 14.1042 13.1096 14.9996 12.0051 14.9996Z"
            case .catLearning: "M13 21V23H11V21H3C2.44772 21 2 20.5523 2 20V4C2 3.44772 2.44772 3 3 3H9C10.1947 3 11.2671 3.52375 12 4.35418C12.7329 3.52375 13.8053 3 15 3H21C21.5523 3 22 3.44772 22 4V20C22 20.5523 21.5523 21 21 21H13ZM20 19V5H15C13.8954 5 13 5.89543 13 7V19H20ZM11 19V7C11 5.89543 10.1046 5 9 5H4V19H11Z"
            case .catFamily: "M15.0049 2.00281C17.214 2.00281 19.0049 3.79367 19.0049 6.00281C19.0049 6.73184 18.8098 7.41532 18.4691 8.00392L23.0049 8.00281V10.0028H21.0049V20.0028C21.0049 20.5551 20.5572 21.0028 20.0049 21.0028H4.00488C3.4526 21.0028 3.00488 20.5551 3.00488 20.0028V10.0028H1.00488V8.00281L5.54065 8.00392C5.19992 7.41532 5.00488 6.73184 5.00488 6.00281C5.00488 3.79367 6.79574 2.00281 9.00488 2.00281C10.2001 2.00281 11.2729 2.52702 12.0058 3.35807C12.7369 2.52702 13.8097 2.00281 15.0049 2.00281ZM11.0049 10.0028H5.00488V19.0028H11.0049V10.0028ZM19.0049 10.0028H13.0049V19.0028H19.0049V10.0028ZM9.00488 4.00281C7.90031 4.00281 7.00488 4.89824 7.00488 6.00281C7.00488 7.05717 7.82076 7.92097 8.85562 7.99732L9.00488 8.00281H11.0049V6.00281C11.0049 5.00116 10.2686 4.1715 9.30766 4.02558L9.15415 4.00829L9.00488 4.00281ZM15.0049 4.00281C13.9505 4.00281 13.0867 4.81869 13.0104 5.85355L13.0049 6.00281V8.00281H15.0049C16.0592 8.00281 16.923 7.18693 16.9994 6.15207L17.0049 6.00281C17.0049 4.89824 16.1095 4.00281 15.0049 4.00281Z"
            case .catInsurance: "M12.998 2.04938C18.0514 2.5511 21.998 6.81465 21.998 12V13H12.998V19C12.998 20.1046 13.8935 21 14.998 21C16.1026 21 16.998 20.1046 16.998 19V18H18.998V19C18.998 21.2091 17.2072 23 14.998 23C12.7889 23 10.998 21.2091 10.998 19V13H1.99805V12C1.99805 6.81465 5.94472 2.5511 10.998 2.04938V2C10.998 1.44772 11.4458 1 11.998 1C12.5503 1 12.998 1.44772 12.998 2V2.04938ZM19.9362 11C19.4441 7.05369 16.0777 4 11.998 4C7.91843 4 4.55204 7.05369 4.05994 11H19.9362Z"
            case .catFees: "M14.0049 2.00281C18.4232 2.00281 22.0049 5.58453 22.0049 10.0028C22.0049 13.2474 20.0733 16.0409 17.2973 17.296C16.0422 20.0718 13.249 22.0028 10.0049 22.0028C5.5866 22.0028 2.00488 18.4211 2.00488 14.0028C2.00488 10.7587 3.9359 7.96554 6.71122 6.71012C7.96681 3.93438 10.7603 2.00281 14.0049 2.00281ZM10.0049 8.00281C6.69117 8.00281 4.00488 10.6891 4.00488 14.0028C4.00488 17.3165 6.69117 20.0028 10.0049 20.0028C13.3186 20.0028 16.0049 17.3165 16.0049 14.0028C16.0049 10.6891 13.3186 8.00281 10.0049 8.00281ZM11.0049 9.00281V10.0028H13.0049V12.0028H9.00488C8.72874 12.0028 8.50488 12.2267 8.50488 12.5028C8.50488 12.7483 8.68176 12.9524 8.91501 12.9948L9.00488 13.0028H11.0049C12.3856 13.0028 13.5049 14.1221 13.5049 15.5028C13.5049 16.8835 12.3856 18.0028 11.0049 18.0028V19.0028H9.00488V18.0028H7.00488V16.0028H11.0049C11.281 16.0028 11.5049 15.7789 11.5049 15.5028C11.5049 15.2573 11.328 15.0532 11.0948 15.0109L11.0049 15.0028H9.00488C7.62417 15.0028 6.50488 13.8835 6.50488 12.5028C6.50488 11.1221 7.62417 10.0028 9.00488 10.0028V9.00281H11.0049ZM14.0049 4.00281C12.2214 4.00281 10.6196 4.78097 9.52064 6.01629C9.68133 6.00764 9.84254 6.00281 10.0049 6.00281C14.4232 6.00281 18.0049 9.58453 18.0049 14.0028C18.0049 14.1655 18 14.327 17.9905 14.4873C19.2265 13.3885 20.0049 11.7866 20.0049 10.0028C20.0049 6.6891 17.3186 4.00281 14.0049 4.00281Z"
            case .incSalary: "M7 5V2C7 1.44772 7.44772 1 8 1H16C16.5523 1 17 1.44772 17 2V5H21C21.5523 5 22 5.44772 22 6V20C22 20.5523 21.5523 21 21 21H3C2.44772 21 2 20.5523 2 20V6C2 5.44772 2.44772 5 3 5H7ZM4 16V19H20V16H4ZM4 14H20V7H4V14ZM9 3V5H15V3H9ZM11 11H13V13H11V11Z"
            case .incSideJob: "M20 2C20.5523 2 21 2.44772 21 3V8C21 8.55228 20.5523 9 20 9H15V22C15 22.5523 14.5523 23 14 23H10C9.44772 23 9 22.5523 9 22V9H3.5C2.94772 9 2.5 8.55228 2.5 8V5.61803C2.5 5.23926 2.714 4.893 3.05279 4.72361L8.5 2H20ZM15 4H8.97214L4.5 6.23607V7H11V21H13V7H15V4ZM19 4H17V7H19V4Z"
            case .incGift: "M14.178 9.76602C16.0334 9.35487 17.695 8.4283 19.0049 7.14424V4.00281H5.00488V7.14424C6.31472 8.4283 7.97632 9.35487 9.83175 9.76602C10.2621 9.01149 11.0741 8.50281 12.0049 8.50281C12.9357 8.50281 13.7477 9.01149 14.178 9.76602ZM14.3861 11.7666C14.0633 12.7737 13.1192 13.5028 12.0049 13.5028C10.8905 13.5028 9.94648 12.7737 9.6237 11.7666C7.92722 11.425 6.36024 10.7257 5.00488 9.75071V20.0028H19.0049V9.75071C17.6495 10.7257 16.0825 11.425 14.3861 11.7666ZM4.00488 2.00281H20.0049C20.5572 2.00281 21.0049 2.45052 21.0049 3.00281V21.0028C21.0049 21.5551 20.5572 22.0028 20.0049 22.0028H4.00488C3.4526 22.0028 3.00488 21.5551 3.00488 21.0028V3.00281C3.00488 2.45052 3.4526 2.00281 4.00488 2.00281Z"
            case .incInvestment: "M5 3V19H21V21H3V3H5ZM20.2929 6.29289L21.7071 7.70711L16 13.4142L13 10.415L8.70711 14.7071L7.29289 13.2929L13 7.58579L16 10.585L20.2929 6.29289Z"
            case .incResale: "M19.5605 12.0975L21.092 14.7501C22.0585 16.4241 21.4849 18.5647 19.8109 19.5312C19.2788 19.8384 18.6753 20.0001 18.0609 20.0001L15.9985 19.9995L15.9987 22.5001L10.9987 19.0001L15.9987 15.5001L15.9985 17.9995L18.0609 18.0001C18.3242 18.0001 18.5829 17.9308 18.8109 17.7991C19.5283 17.3849 19.7742 16.4675 19.3599 15.7501L17.8285 13.0975L19.5605 12.0975ZM7.30257 9.13407L7.83366 15.2142L5.66848 13.9635L4.63751 15.7501C4.50586 15.9781 4.43655 16.2368 4.43655 16.5001C4.43655 17.3285 5.10812 18.0001 5.93655 18.0001L8.99948 18.0002V20.0001H5.93655C4.00355 20.0001 2.43655 18.4331 2.43655 16.5001C2.43655 15.8857 2.59827 15.2822 2.90546 14.7501L3.93648 12.9635L1.77148 11.7142L7.30257 9.13407ZM13.7487 2.96901C14.2808 3.2762 14.7226 3.71803 15.0298 4.2501L16.0605 6.03551L18.226 4.78599L17.6949 10.8661L12.1638 8.28599L14.3285 7.03551L13.2978 5.2501C13.1661 5.02207 12.9768 4.83271 12.7487 4.70106C12.0313 4.28684 11.1139 4.53266 10.6997 5.2501L9.16818 7.90261L7.43615 6.90266L8.96764 4.2501C9.93414 2.57607 12.0747 2.00251 13.7487 2.96901Z"
            case .acctReceivable: "M14 14.252V16.3414C13.3744 16.1203 12.7013 16 12 16C8.68629 16 6 18.6863 6 22H4C4 17.5817 7.58172 14 12 14C12.6906 14 13.3608 14.0875 14 14.252ZM12 13C8.685 13 6 10.315 6 7C6 3.685 8.685 1 12 1C15.315 1 18 3.685 18 7C18 10.315 15.315 13 12 13ZM12 11C14.21 11 16 9.21 16 7C16 4.79 14.21 3 12 3C9.79 3 8 4.79 8 7C8 9.21 9.79 11 12 11ZM20 17H23V19H20V22.5L15 18L20 13.5V17Z"
            case .dirIncome: "M9 13.589L17.6066 4.98242L19.0208 6.39664L10.4142 15.0032H18V17.0032H7V6.00324H9V13.589Z"
            case .dirExpense: "M16.0037 9.41421L7.39712 18.0208L5.98291 16.6066L14.5895 8H7.00373V6H18.0037V17H16.0037V9.41421Z"
            case .refund: "M5.67591 4.25667C9.60392 1.03828 15.4094 1.26236 19.076 4.92893C22.9812 8.83418 22.9812 15.1658 19.076 19.0711C15.1707 22.9763 8.83906 22.9763 4.93382 19.0711C2.40932 16.5466 1.51676 13.0081 2.25611 9.76666L2.33275 9.45394L4.26718 9.96315C3.56967 12.623 4.26329 15.5721 6.34803 17.6569C9.47222 20.781 14.5375 20.781 17.6617 17.6569C20.7859 14.5327 20.7859 9.46734 17.6617 6.34315C14.8441 3.5255 10.4475 3.24903 7.32006 5.51375L7.09886 5.67983L8.1158 6.6967L3.5196 7.75736L4.58026 3.16117L5.67591 4.25667ZM13.0049 6V8H15.5049V10H10.0049C9.72874 10 9.50488 10.2239 9.50488 10.5C9.50488 10.7455 9.68176 10.9496 9.91501 10.9919L10.0049 11H14.0049C15.3856 11 16.5049 12.1193 16.5049 13.5C16.5049 14.8807 15.3856 16 14.0049 16H13.0049V18H11.0049V16H8.50488V14H14.0049C14.281 14 14.5049 13.7761 14.5049 13.5C14.5049 13.2545 14.328 13.0504 14.0948 13.0081L14.0049 13H10.0049C8.62417 13 7.50488 11.8807 7.50488 10.5C7.50488 9.11929 8.62417 8 10.0049 8H11.0049V6H13.0049Z"
            case .split: "M2 22C2 17.5817 5.58172 14 10 14C14.4183 14 18 17.5817 18 22H16C16 18.6863 13.3137 16 10 16C6.68629 16 4 18.6863 4 22H2ZM10 13C6.685 13 4 10.315 4 7C4 3.685 6.685 1 10 1C13.315 1 16 3.685 16 7C16 10.315 13.315 13 10 13ZM10 11C12.21 11 14 9.21 14 7C14 4.79 12.21 3 10 3C7.79 3 6 4.79 6 7C6 9.21 7.79 11 10 11ZM18.2837 14.7028C21.0644 15.9561 23 18.752 23 22H21C21 19.564 19.5483 17.4671 17.4628 16.5271L18.2837 14.7028ZM17.5962 3.41321C19.5944 4.23703 21 6.20361 21 8.5C21 11.3702 18.8042 13.7252 16 13.9776V11.9646C17.6967 11.7222 19 10.264 19 8.5C19 7.11935 18.2016 5.92603 17.041 5.35635L17.5962 3.41321Z"
            case .radioOff: "M12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12C22 17.5228 17.5228 22 12 22ZM12 20C16.4183 20 20 16.4183 20 12C20 7.58172 16.4183 4 12 4C7.58172 4 4 7.58172 4 12C4 16.4183 7.58172 20 12 20Z"
            case .arrowRight: "M16.1716 10.9999L10.8076 5.63589L12.2218 4.22168L20 11.9999L12.2218 19.778L10.8076 18.3638L16.1716 12.9999H4V10.9999H16.1716Z"
            case .chevronUp: "M11.9999 10.8284L7.0502 15.7782L5.63599 14.364L11.9999 8L18.3639 14.364L16.9497 15.7782L11.9999 10.8284Z"
            case .clear: "M12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12C22 17.5228 17.5228 22 12 22ZM12 10.5858L9.17157 7.75736L7.75736 9.17157L10.5858 12L7.75736 14.8284L9.17157 16.2426L12 13.4142L14.8284 16.2426L16.2426 14.8284L13.4142 12L16.2426 9.17157L14.8284 7.75736L12 10.5858Z"
            case .radioOn: "M12 22C17.5228 22 22 17.5228 22 12C22 6.47715 17.5228 2 12 2C6.47715 2 2 6.47715 2 12C2 17.5228 6.47715 22 12 22ZM17.4571 9.45711L11 15.9142L6.79289 11.7071L8.20711 10.2929L11 13.0858L16.0429 8.04289L17.4571 9.45711Z"
            case .checkboxOn: "M4 3H20C20.5523 3 21 3.44772 21 4V20C21 20.5523 20.5523 21 20 21H4C3.44772 21 3 20.5523 3 20V4C3 3.44772 3.44772 3 4 3ZM11.0026 16L18.0737 8.92893L16.6595 7.51472L11.0026 13.1716L8.17421 10.3431L6.75999 11.7574L11.0026 16Z"
            case .checkboxOff: "M4 3H20C20.5523 3 21 3.44772 21 4V20C21 20.5523 20.5523 21 20 21H4C3.44772 21 3 20.5523 3 20V4C3 3.44772 3.44772 3 4 3ZM5 5V19H19V5H5Z"
            case .reminderDate: "M7 3V1H9V3H15V1H17V3H21C21.5523 3 22 3.44772 22 4V9H20V5H17V7H15V5H9V7H7V5H4V19H10V21H3C2.44772 21 2 20.5523 2 20V4C2 3.44772 2.44772 3 3 3H7ZM17 12C14.7909 12 13 13.7909 13 16C13 18.2091 14.7909 20 17 20C19.2091 20 21 18.2091 21 16C21 13.7909 19.2091 12 17 12ZM11 16C11 12.6863 13.6863 10 17 10C20.3137 10 23 12.6863 23 16C23 19.3137 20.3137 22 17 22C13.6863 22 11 19.3137 11 16ZM16 13V16.4142L18.2929 18.7071L19.7071 17.2929L18 15.5858V13H16Z"
            case .addCircle: "M11 11V7H13V11H17V13H13V17H11V13H7V11H11ZM12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12C22 17.5228 17.5228 22 12 22ZM12 20C16.4183 20 20 16.4183 20 12C20 7.58172 16.4183 4 12 4C7.58172 4 4 7.58172 4 12C4 16.4183 7.58172 20 12 20Z"
            case .scanCapture: "M3 3H5V5H3V3ZM7 3H9V5H7V3ZM11 3H13V5H11V3ZM15 3H17V5H15V3ZM19 3H21V5H19V3ZM19 7H21V9H19V7ZM3 19H5V21H3V19ZM3 15H5V17H3V15ZM3 11H5V13H3V11ZM3 7H5V9H3V7ZM10.6667 11L11.7031 9.4453C11.8886 9.1671 12.2008 9 12.5352 9H15.4648C15.7992 9 16.1114 9.1671 16.2969 9.4453L17.3333 11H20C20.5523 11 21 11.4477 21 12V20C21 20.5523 20.5523 21 20 21H8C7.44772 21 7 20.5523 7 20V12C7 11.4477 7.44772 11 8 11H10.6667ZM9 19H19V13H16.263L14.9296 11H13.0704L11.737 13H9V19ZM14 18C12.8954 18 12 17.1046 12 16C12 14.8954 12.8954 14 14 14C15.1046 14 16 14.8954 16 16C16 17.1046 15.1046 18 14 18Z"
            case .warning: "M12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12C22 17.5228 17.5228 22 12 22ZM12 20C16.4183 20 20 16.4183 20 12C20 7.58172 16.4183 4 12 4C7.58172 4 4 7.58172 4 12C4 16.4183 7.58172 20 12 20ZM11 15H13V17H11V15ZM11 7H13V13H11V7Z"
            case .send: "M21.7267 2.95694L16.2734 22.0432C16.1225 22.5716 15.7979 22.5956 15.5563 22.1126L11 13L1.9229 9.36919C1.41322 9.16532 1.41953 8.86022 1.95695 8.68108L21.0432 2.31901C21.5716 2.14285 21.8747 2.43866 21.7267 2.95694ZM19.0353 5.09647L6.81221 9.17085L12.4488 11.4255L15.4895 17.5068L19.0353 5.09647Z"
            case .undo: "M5.82843 6.99955L8.36396 9.53509L6.94975 10.9493L2 5.99955L6.94975 1.0498L8.36396 2.46402L5.82843 4.99955H13C17.4183 4.99955 21 8.58127 21 12.9996C21 17.4178 17.4183 20.9996 13 20.9996H4V18.9996H13C16.3137 18.9996 19 16.3133 19 12.9996C19 9.68584 16.3137 6.99955 13 6.99955H5.82843Z"
            case .drag: "M8.5 7C9.32843 7 10 6.32843 10 5.5C10 4.67157 9.32843 4 8.5 4C7.67157 4 7 4.67157 7 5.5C7 6.32843 7.67157 7 8.5 7ZM8.5 13.5C9.32843 13.5 10 12.8284 10 12C10 11.1716 9.32843 10.5 8.5 10.5C7.67157 10.5 7 11.1716 7 12C7 12.8284 7.67157 13.5 8.5 13.5ZM10 18.5C10 19.3284 9.32843 20 8.5 20C7.67157 20 7 19.3284 7 18.5C7 17.6716 7.67157 17 8.5 17C9.32843 17 10 17.6716 10 18.5ZM15.5 7C16.3284 7 17 6.32843 17 5.5C17 4.67157 16.3284 4 15.5 4C14.6716 4 14 4.67157 14 5.5C14 6.32843 14.6716 7 15.5 7ZM17 12C17 12.8284 16.3284 13.5 15.5 13.5C14.6716 13.5 14 12.8284 14 12C14 11.1716 14.6716 10.5 15.5 10.5C16.3284 10.5 17 11.1716 17 12ZM15.5 20C16.3284 20 17 19.3284 17 18.5C17 17.6716 16.3284 17 15.5 17C14.6716 17 14 17.6716 14 18.5C14 19.3284 14.6716 20 15.5 20Z"
            }
        }

        /// Extra stroked line for custom glyphs, width on the 24 grid. Nil for Remix glyphs.
        var stroke: (pathData: String, width: CGFloat)? {
            switch self {
            case .chat: ("M8.2 3H15.8A5.2 5.2 0 0 1 21 8.2V12.8A5.2 5.2 0 0 1 15.8 18H10.5L6 21.5V18A5.2 5.2 0 0 1 3 13.2V8.2A5.2 5.2 0 0 1 8.2 3Z", 2)
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
