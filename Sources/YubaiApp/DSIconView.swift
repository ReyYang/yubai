import SwiftUI
import YubaiCore

struct DSIconView: View {
    let icon: DS.Icon
    let size: CGFloat
    var color: Color? = nil

    /// Remix filled outlines, plus the stroked line of custom glyphs, parsed once on the 24 grid.
    private static let cachedPaths: [DS.Icon: (fill: Path, stroke: Path?)] = {
        var map: [DS.Icon: (fill: Path, stroke: Path?)] = [:]
        map.reserveCapacity(DS.Icon.allCases.count)
        for glyph in DS.Icon.allCases {
            map[glyph] = (buildPath(from: glyph.pathData), glyph.stroke.map { buildPath(from: $0.pathData) })
        }
        return map
    }()

    static func buildPath(from d: String) -> Path {
        var path = Path()
        guard let commands = try? SVGPathParser.parse(d) else { return path }
        for command in commands {
            switch command {
            case .moveTo(let point):
                path.move(to: CGPoint(x: point.x, y: point.y))
            case .lineTo(let point):
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            case .cubicTo(let c1, let c2, let end):
                path.addCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control1: CGPoint(x: c1.x, y: c1.y),
                    control2: CGPoint(x: c2.x, y: c2.y)
                )
            case .quadTo(let control, let end):
                path.addQuadCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control: CGPoint(x: control.x, y: control.y)
                )
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }

    var body: some View {
        let scale = size / DS.Icon.grid
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let paths = Self.cachedPaths[icon] ?? (Path(), nil)
        let fillStyle: AnyShapeStyle = color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground)
        Rectangle()
            .fill(fillStyle)
            .frame(width: size, height: size)
            .mask {
                ZStack {
                    paths.fill.applying(transform).fill(Color.black)
                    if let stroke = paths.stroke, let width = icon.stroke?.width {
                        stroke.applying(transform).stroke(Color.black, style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

extension DS.Icon {
    func view(size: CGFloat, color: Color? = nil) -> DSIconView {
        DSIconView(icon: self, size: size, color: color)
    }
}

extension Label where Title == Text, Icon == DSIconView {
    init(_ title: LocalizedStringKey, icon: DS.Icon, size: CGFloat, color: Color? = nil) {
        self.init { Text(title) } icon: { DSIconView(icon: icon, size: size, color: color) }
    }
    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, icon: DS.Icon, size: CGFloat, color: Color? = nil) {
        self.init { Text(title) } icon: { DSIconView(icon: icon, size: size, color: color) }
    }
}

extension DS.Icon {
    /// Ledgers store SF Symbol names for categories; every screen draws them through this table.
    /// Unknown names, including ones from older ledgers, fall back to `.catOther`.
    /// A category's icon: the one picked in 编辑分类, then a known name, then its stored symbol.
    init(category name: String, symbol: String, income: Bool, icon: String? = nil) {
        self = icon.flatMap(DS.Icon.init(rawValue:)) ?? Self.categoryNames[name] ?? DS.Icon(symbol: symbol, income: income)
    }

    /// 编辑分类 · 图标: the 18 picks, in the canvas order (Main.dc.html iconChoices).
    static let categoryChoices: [DS.Icon] = [
        .catLearning, .catFood, .catCoffee, .catTransport, .catShopping, .catHousing, .catHealth, .catBeauty, .catFun,
        .catTravel, .catFamily, .catInsurance, .catFees, .catDigital, .catDaily, .catGrocery, .catOther, .incInvestment,
    ]

    /// What VoiceOver says for each pick in 编辑分类 · 图标.
    var choiceName: String {
        switch self {
        case .catLearning: "书本"; case .catFood: "碗"; case .catCoffee: "咖啡杯"; case .catTransport: "地铁"
        case .catShopping: "购物袋"; case .catHousing: "房子"; case .catHealth: "药箱"; case .catBeauty: "剪刀"
        case .catFun: "游戏"; case .catTravel: "行李箱"; case .catFamily: "礼物"; case .catInsurance: "盾牌"
        case .catFees: "票据"; case .catDigital: "手机"; case .catDaily: "商店"; case .catGrocery: "菜篮"
        case .catOther: "三个点"; case .incInvestment: "走势"
        default: "图标"
        }
    }

    struct CategoryKey: Hashable { let name: String; let income: Bool }

    /// Every category's icon in one ledger, with no two expense categories alike unless the person chose so.
    /// Picks made in 编辑分类 stay as chosen; then each category keeps what its name or symbol means while
    /// no earlier category has it by meaning; the rest take the first free pick, in the order the categories were added,
    /// so an icon does not move when the list is reordered. Income categories show no icon cell and keep
    /// their own; the catch-all keeps its three dots.
    static func categoryIcons(_ categories: [YubaiCore.Category]) -> [CategoryKey: DS.Icon] {
        var result: [CategoryKey: DS.Icon] = [:]
        // A hand pick may repeat a meaning icon (the person saw it there); it never pushes that one off.
        var picked = Set<DS.Icon>(), taken = Set<DS.Icon>()
        for category in categories {
            guard let icon = category.icon.flatMap(DS.Icon.init(rawValue:)) else { continue }
            result[CategoryKey(name: category.name, income: category.income)] = icon
            if !category.income { picked.insert(icon) }
        }
        var waiting: [CategoryKey] = []
        for category in categories {
            let key = CategoryKey(name: category.name, income: category.income)
            guard result[key] == nil else { continue }
            let natural = DS.Icon(category: category.name, symbol: category.symbol, income: category.income)
            if category.income || category.system || category.name == "其他支出" {
                result[key] = natural
            } else if natural != .catOther && !taken.contains(natural) {
                result[key] = natural; taken.insert(natural)
            } else {
                waiting.append(key)
            }
        }
        for key in waiting {
            let free = categoryChoices.first { !taken.contains($0) && !picked.contains($0) && $0 != .catOther && $0 != .incInvestment } ?? .catOther
            result[key] = free
            if free != .catOther { taken.insert(free) }
        }
        return result
    }

    init(symbol: String, income: Bool = false) {
        if symbol == "gift" { self = income ? .incGift : .catFamily; return }
        self = Self.storedSymbols[symbol] ?? .catOther
    }

    private static let categoryNames: [String: DS.Icon] = [
        "吃饭": .catFood, "餐饮": .catFood, "咖啡": .catCoffee, "咖啡茶饮": .catCoffee,
        "交通": .catTransport, "出行": .catTransport, "买菜": .catGrocery, "生鲜买菜": .catGrocery,
        "购物": .catShopping, "居住": .catHousing, "住房": .catHousing, "娱乐": .catFun,
        "日用": .catDaily, "日用百货": .catDaily, "数码": .catDigital, "数码电器": .catDigital,
        // 通讯 is talking to people, not a device: its own bubble, so it never looks like 数码.
        "通讯": .chat,
        "工资": .incSalary, "奖金": .incSalary, "工资奖金": .incSalary, "兼职劳务": .incSideJob,
        "礼金赠与": .incGift, "投资收益": .incInvestment, "二手转卖": .incResale,
        "报销": .reimburse, "退款": .refund,
    ]

    private static let storedSymbols: [String: DS.Icon] = [
        // Default expense categories.
        "fork.knife": .catFood, "bag": .catShopping, "tram": .catTransport, "house": .catHousing,
        "cross.case": .catHealth, "scissors": .catBeauty, "sparkles": .catFun, "suitcase": .catTravel,
        "repeat": .catMembership, "book": .catLearning, "checkmark.shield": .catInsurance,
        "percent": .catFees, "ellipsis": .catOther,
        // Default income categories.
        "briefcase": .incSalary, "hammer": .incSideJob, "chart.line.uptrend.xyaxis": .incInvestment,
        "receipt": .reimburse, "arrow.triangle.2.circlepath": .incResale, "arrow.2.circlepath": .incResale,
        "arrow.left.arrow.right": .transfer,
        // Older ledgers and imports.
        "takeoutbag.and.cup.and.straw": .catFood, "cup.and.saucer": .catCoffee,
        "car": .catTransport, "bus": .catTransport, "basket": .catGrocery, "cart": .catGrocery,
        "shoppingbag": .catShopping, "house.fill": .catHousing, "ticket": .catFun, "gamecontroller": .catFun,
        "shippingbox": .catDaily, "iphone": .catDigital, "desktopcomputer": .catDigital,
        "banknote": .incSalary, "square.grid.2x2": .catOther,
        // Nature fallbacks written by ManualBookkeeping.
        "arrow.down.left": .dirIncome, "arrow.up.right": .dirExpense, "arrow.uturn.backward": .refund,
        "person.2": .split, "circle.dotted": .radioOff,
    ]
}

extension AccountKind {
    var icon: DS.Icon {
        switch self {
        case .bank: .acctDebit
        case .credit: .acctCredit
        case .investment: .acctInvest
        case .cash: .acctCash
        case .receivable: .acctReceivable
        }
    }
}

/// The open ledger's category icons, worked out once whenever its categories change.
enum CategoryIcons {
    nonisolated(unsafe) private(set) static var current: [DS.Icon.CategoryKey: DS.Icon] = [:]
    nonisolated(unsafe) private static var source: [YubaiCore.Category] = []

    @MainActor static func configure(_ categories: [YubaiCore.Category]) {
        guard categories != source else { return }
        source = categories
        current = DS.Icon.categoryIcons(categories)
    }
}
