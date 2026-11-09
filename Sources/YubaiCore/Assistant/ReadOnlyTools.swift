import Foundation

public struct ToolContext: Sendable {
    public let ledger: Ledger
    public let now: Date
    public let redactor: Redactor
    /// Captured from an explicit local amount input; never from model arguments.
    public let confirmedEntryAmount: Int64?
    public let parsedEntries: [(text: String, amount: Int64)]
    public let parsedEntryAmounts: [Int64]
    public let entryAccountHint: UUID?
    public let memoryCharacterBudget: Int
    let entriesByID: [UUID: Entry]
    public init(ledger: Ledger, now: Date = Date(), confirmedEntryAmount: Int64? = nil, parsedEntryAmounts: [Int64] = [], parsedEntries: [(text: String, amount: Int64)] = [], entryAccountHint: UUID? = nil, memoryCharacterBudget: Int = Memory.defaultCharacterBudget) {
        self.memoryCharacterBudget = memoryCharacterBudget
        self.entryAccountHint = entryAccountHint
        self.parsedEntries = parsedEntries.filter { $0.amount > 0 && $0.amount <= Money.limit }
        self.parsedEntryAmounts = (parsedEntryAmounts.isEmpty ? parsedEntries.map(\.amount) : parsedEntryAmounts).filter { $0 > 0 && $0 <= Money.limit }
        self.confirmedEntryAmount = confirmedEntryAmount
        self.ledger = ledger; self.now = now; self.redactor = Redactor(ledger: ledger)
        self.entriesByID = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
    }
}

public protocol AssistantTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: JSONValue { get }
    func run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue
}

/// All results are explicit field allowlists; no Entry / Ledger encoding goes to the cloud.
public enum ReadOnlyTool: String, CaseIterable, AssistantTool {
    case getFunds = "get_funds", forecast, queryEntries = "query_entries", summarize
    case compareToHabit = "compare_to_habit", getProfile = "get_profile"
    public static var all: [any AssistantTool] { allCases.map { $0 as any AssistantTool } }
    public var name: String { rawValue }
    public var description: String {
        switch self {
        case .getFunds: return "本机计算的还能花看到当前周期末：有固定工资时到下次发工资前一天，否则到自然月末。存着不动是固定存款，不算进还能花；要攒是这个月先留出的钱。日常开销不扣，未来收入不提前计入。"
        case .forecast: return "从今天预测指定日期的保守/预计余额及此前已知付款；可比较一笔金额。最远365天，预计收入不算保守资金。"
        case .queryEntries: return "筛选记录，返回本地证据ID及脱敏摘要，每页最多50条。offset从0开始，用next_offset继续查询。日期边界均包含当天，金额过滤用原始金额。"
        case .summarize: return "按日/周(周一开始)/月/分类汇总匹配记录；默认全部，不受查询默认条数限制。消费退款抵扣，房租只计个人承担。"
        case .compareToHabit: return "近90个自然日同类实际消费的均值、中位数、每周频次和最近记录；有数据时附last_year去年同期90天均值和次数，以及匹配的想克制领域柔性线soft_limits。不含未来记录或退款，可比较金额位置。"
        case .getProfile: return "当前结构化消费观：愿意多花、想克制及柔性提醒、原则（text和confirmed_at对象数组）、确认日期、存着不动和攒钱安排。附生活背景memories（可能过时，省略时用recall检索）和最近10条已回答心愿回访recent_followups。你常花的是近90天本机统计，不是用户要求。每次消费判断重新读取。附提案所需的本地账户/安排标识；补记前读取本机已确认金额。"
        }
    }
    private static func field(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }
    private static let amountSchema: JSONValue = .object([
        "anyOf": .array([.object(["type": .string("string")]), .object(["type": .string("number")])]),
        "description": .string("人民币元，最多两位小数，不是分。优先传字符串。")])
    private static var filters: [String: JSONValue] {
        ["start_date": field("string", "起始日 yyyy-MM-dd（包含）"),
         "end_date": field("string", "结束日 yyyy-MM-dd（包含）"),
         "category": field("string", "分类全名，退款跟随原支出分类"),
         "subcategory": field("string", "小项名，配合category；退款跟随原支出小项"),
         "nature": .object(["type": .string("string"), "enum": .strings(["spending", "income", "transfer"])]),
         "keyword": field("string", "标题或备注子串"), "min_amount": amountSchema, "max_amount": amountSchema,
         "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(50)])]
    }
    public var parameters: JSONValue {
        var fields: [String: JSONValue] = [:]
        switch self {
        case .getFunds, .getProfile: break
        case .forecast:
            fields = ["date": Self.field("string", "yyyy-MM-dd，与days二选一"),
                      "days": .object(["type": .string("integer"), "minimum": .number(0), "maximum": .number(365)]),
                      "amount": Self.amountSchema]
        case .queryEntries:
            fields = Self.filters
            fields["offset"] = .object(["type": .string("integer"), "minimum": .number(0)])
        case .summarize:
            fields = Self.filters
            fields["group_by"] = .object(["type": .string("string"), "enum": .strings(["day", "week", "month", "category", "subcategory"])])
        case .compareToHabit:
            fields = ["subcategory": Self.field("string", "有小项时优先按小项比较"), "category": Self.field("string", "分类，与keyword至少提供一项；两项同时给出取交集"),
                      "keyword": Self.field("string", "标题或备注子串"), "amount": Self.amountSchema]
        }
        return .object(["type": .string("object"), "properties": .object(fields), "additionalProperties": .bool(false)])
    }

    public func run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue {
        let allowedFields = Set(parameters["properties"]?.objectValue?.keys.map { $0 } ?? [])
        guard let fields = args.objectValue, Set(fields.keys).isSubset(of: allowedFields) else {
            throw YubaiError.invalid("参数必须是对象，且只能包含工具声明的字段。")
        }
        let result: JSONValue
        switch self {
        case .getFunds:
            let f = Finance.funds(ctx.ledger, now: ctx.now)
            var fields: [String: JSONValue] = ["available": .money(f.available), "cash": .money(f.cash), "debt": .money(f.debt),
                "committed": .money(f.committed), "goals": .money(f.goals), "fixed_savings": .money(ctx.ledger.fixedSavings ?? 0),
                "cycle_start": .string(Dates.text(f.cycleStart)), "cycle_end": .string(Dates.text(f.cycleEnd)), "cycle_is_payday": .bool(f.cycleIsPayday),
                "liquid_start": .money(f.liquidStart), "cycle_income": .money(f.cycleIncome), "saving_target": .money(f.savingTarget),
                "cycle_spent": .money(f.cycleSpent), "due_rest": .money(f.dueRest), "daily_allowance": .money(f.dailyAllowance), "saving_shortfall": .money(f.savingShortfall),
                "living": .money(f.living), "uncertain": .money(f.uncertainInflow), "expected_income": .money(f.expectedIncome),
                "horizon_days": .number(Double(f.horizonDays)), "warnings": .strings(f.warnings)]
            switch ctx.ledger.savingRule {
            case .fixed(let amount): fields["saving_rule"] = .object(["type": .string("fixed"), "amount": .money(amount)])
            case .share(let percent): fields["saving_rule"] = .object(["type": .string("share"), "percent": .number(Double(percent))])
            case nil: fields["saving_rule"] = .null
            }
            if let payday = f.payday { fields["payday"] = .string(Dates.text(payday)) }
            if let title = f.paydayTitle { fields["payday_title"] = .string(title) }
            result = .object(fields)
        case .forecast: result = try forecast(fields, ctx)
        case .queryEntries:
            let filter = try Filter(fields)
            let all = filter.entries(ctx)
            let offset = try fields["offset"].map { try Self.integer($0, range: 0...Int.max) } ?? 0
            let rows = Array(all.dropFirst(min(offset, all.count)).prefix(filter.limit ?? 20))
            var page: [String: JSONValue] = ["entries": .array(rows.map { summary($0, ctx) }),
                "entry_ids": .strings(rows.map { $0.id.uuidString }), "matched_count": .number(Double(all.count)),
                "truncated": .bool(offset + rows.count < all.count)]
            if offset + rows.count < all.count { page["next_offset"] = .number(Double(offset + rows.count)) }
            result = .object(page)
        case .summarize: result = try summarizeWithChart(fields, ctx).result
        case .compareToHabit: result = try habit(fields, ctx)
        case .getProfile: result = profile(ctx)
        }
        return ctx.redactor.value(result)
    }

    private func profile(_ ctx: ToolContext) -> JSONValue {
        func area(_ a: ProfileArea) -> JSONValue {
            var row: [String: JSONValue] = ["id": .string(a.id.uuidString), "title": .string(a.title),
                "match": .object(["categories": .strings(a.match.categories), "subcategories": .strings(a.match.subcategories), "keywords": .strings(a.match.keywords)]),
                "categories": .strings(a.match.categories), "subcategories": .strings(a.match.subcategories), "keywords": .strings(a.match.keywords), "note": .string(a.note),
                "confirmed_at": a.confirmedAt.map { .string(Dates.text($0)) } ?? .null,
                "days_since_confirmed": a.confirmedAt.map { .number(Double(Dates.calendar.dateComponents([.day], from: Dates.day($0), to: Dates.day(ctx.now)).day ?? 0)) } ?? .null,
                "soft_line": .string(a.softLimit?.text ?? "")]
            if let count = a.softLimit?.perWeekCount { row["per_week_count"] = .number(Double(count)) }
            if let amount = a.softLimit?.perMonthAmount { row["per_month_amount"] = .money(amount) }
            row["soft_limit"] = a.softLimit.map { limit in
                .object(["per_week_count": limit.perWeekCount.map { .number(Double($0)) } ?? .null,
                    "per_month_amount": limit.perMonthAmount.map { .money($0) } ?? .null, "text": .string(limit.text)])
            } ?? .null
            return .object(row)
        }
        let followups = ctx.ledger.wishlist.filter { $0.followUpAnswer != nil }.sorted {
            let a = $0.followUpAnsweredAt ?? $0.followUpAt ?? $0.createdAt
            let b = $1.followUpAnsweredAt ?? $1.followUpAt ?? $1.createdAt
            return a == b ? $0.id.uuidString < $1.id.uuidString : a > b
        }
        let recent: [JSONValue] = followups.prefix(10).map { wish in
            .object(["title": .string(wish.title), "amount": .money(wish.amount),
                "judgment": .string(String(wish.judgment.prefix(200))), "answer": wish.followUpAnswer.map { .string($0) } ?? .null,
                "bought_date": wish.boughtEntryID.flatMap { ctx.entriesByID[$0] }.map { .string(Dates.text($0.date)) } ?? .null])
        }
        var fields: [String: JSONValue] = [
            "generous": .array(ctx.ledger.profile.generous.map(area)), "restrain": .array(ctx.ledger.profile.restrain.map(area)),
            "principles": .array(ctx.ledger.profile.principles.map { text in .object(["text": .string(text),
                "confirmed_at": ctx.ledger.profile.principleDates[text].map { .string(Dates.text($0)) } ?? .null]) }),
            "recent_followups": .array(recent),
            "memories": Memory.context(ledger: ctx.ledger, now: ctx.now, characterBudget: ctx.memoryCharacterBudget),
            "categories": .strings(ctx.ledger.selectableCategories.filter { !$0.income }.map(\.name)),
            "fixed_savings": ctx.ledger.fixedSavings.map { .money($0) } ?? .null,
            "habits": .object(["label": .string("你常花的"), "meaning": .string("这是从账本里看到的，不是你的要求；分类与商户可能重叠，不可相加。"),
                "window_days": .number(90), "lines": .array(ProfileHabits.summary(ctx.ledger, now: ctx.now).map {
                    .object(["kind": .string($0.kind.rawValue), "title": .string($0.title), "total": .money($0.total),
                        "count": .number(Double($0.count)), "count_per_week": .number($0.countPerWeek), "average": .money($0.average)]) })]),
            "accounts": .array(ctx.ledger.accounts.enumerated().map { index, a in .object(["id": .string(a.id.uuidString), "title": .string("账户\(index + 1)"), "kind": .string(a.kind.rawValue)]) }),
            "plans": .array(ctx.ledger.plans.map { .object(["id": .string($0.id.uuidString), "title": .string($0.title), "amount": .money($0.amount), "date": .string(Dates.text($0.dueDate))]) }),
            "rents": .array(ctx.ledger.rents.map { .object(["id": .string($0.id.uuidString), "title": .string($0.title)]) }),
            "goals": .array(ctx.ledger.goals.map { .object(["id": .string($0.id.uuidString), "title": .string($0.title),
                "target": .money($0.target), "saved": .money($0.reserved), "reserved": .money($0.reserved),
                "date": $0.dueDate.map { .string(Dates.text($0)) } ?? .null]) })]
        if let account = ctx.entryAccountHint { fields["entry_account_hint"] = .string(account.uuidString) }
        fields["category_policy"] = .string("自动归类仅待整理（没分类）可改主项；其他支出、其他收入是主动选择，不可改动。")
        fields["category_table"] = .array(ctx.ledger.selectableCategories.map { .object(["category": .string($0.name), "income": .bool($0.income), "subcategories": .strings($0.subcategories)]) })
        fields["parsed_entries"] = .array(ctx.parsedEntries.map { .object(["text": .string($0.text), "amount": .money($0.amount)]) })
        fields["parsed_entry_amounts"] = .array(ctx.parsedEntryAmounts.map { .money($0) })
        if let amount = ctx.confirmedEntryAmount { fields["confirmed_entry_amount"] = .money(amount) }
        return .object(fields)
    }

    private func forecast(_ fields: [String: JSONValue], _ ctx: ToolContext) throws -> JSONValue {
        guard (fields["date"] != nil) != (fields["days"] != nil) else { throw YubaiError.invalid("请提供date或days其中一项。") }
        let days: Int
        if let value = fields["date"] {
            let date = try Self.date(value)
            days = Dates.calendar.dateComponents([.day], from: Dates.day(ctx.now), to: date).day ?? -1
        } else { days = try Self.integer(fields["days"], range: 0...365) }
        guard (0...365).contains(days) else { throw YubaiError.invalid("只能预测今天至365天内的日期。") }
        // Finance's occurrence horizon ends at midnight. Calculate one extra day so
        // payments later on the requested calendar day reach that day's forecast point.
        let target = Dates.addDays(days, to: Dates.day(ctx.now))
        let funds = Finance.funds(ctx.ledger, now: ctx.now, days: days + 1)
        guard let point = funds.points.first(where: { $0.date == target }) else { throw YubaiError.invalid("没有可用的预测。") }
        let payments = funds.occurrences.filter { !$0.inflow && Dates.day($0.date) <= point.date }
        var result: [String: JSONValue] = ["date": .string(Dates.text(point.date)),
            "conservative": .money(point.conservative), "expected": .money(point.expected), "warnings": .strings(funds.warnings),
            "known_payments": .array(payments.map { .object(["title": .string($0.title), "date": .string(Dates.text($0.date)),
                "amount": .money($0.amount), "overdue": .bool($0.overdue)]) })]
        if let value = fields["amount"] {
            let amount = try Self.amount(value)
            let after = point.conservative - amount
            result["amount"] = .money(amount); result["enough"] = .bool(after >= 0)
            result["after_purchase"] = .money(after); result["short_by"] = .money(max(0, -after))
        }
        return .object(result)
    }

    func summarizeWithChart(_ fields: [String: JSONValue], _ ctx: ToolContext) throws -> (result: JSONValue, chart: AnswerChart) {
        let allowed = Set(Self.summarize.parameters["properties"]?.objectValue?.keys.map { $0 } ?? [])
        guard Set(fields.keys).isSubset(of: allowed) else { throw YubaiError.invalid("汇总参数包含未声明的字段。") }
        let filter = try Filter(fields)
        let group = try Self.optionalString(fields["group_by"]) ?? "category"
        guard ["day", "week", "month", "category", "subcategory"].contains(group) else { throw YubaiError.invalid("group_by必须是day/week/month/category/subcategory。") }
        let all = filter.entries(ctx)
        let rows = filter.limit.map { Array(all.prefix($0)) } ?? all
        let byID = ctx.entriesByID
        let grouped = Dictionary(grouping: rows) { entry -> String in
            switch group {
            case "day": return Dates.text(entry.date)
            case "month": return String(Dates.text(entry.date).prefix(7))
            case "week":
                var calendar = Dates.calendar; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
                return Dates.text(calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start ?? Dates.day(entry.date))
            case "subcategory":
                let choice = ctx.ledger.normalizedCategory(for: entry, entriesByID: byID)
                return CategoryNamespace.key(choice.category + "/" + (choice.subcategory ?? "没分类"), income: entry.nature.categoryIncome)
            default: return CategoryNamespace.key(ctx.ledger.normalizedCategory(for: entry, entriesByID: byID).category, income: entry.nature.categoryIncome)
            }
        }
        func totals(_ entries: [Entry]) -> [String: JSONValue] {
            ["count": .number(Double(entries.count)),
             "spending": .money(entries.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ctx.ledger) }),
             "income": .money(entries.filter { $0.nature == .income }.reduce(Int64(0)) { $0 + $1.amount }),
             "transfer_volume": .money(entries.filter { $0.nature.paired }.reduce(Int64(0)) { $0 + $1.amount })]
        }
        var result = totals(rows)
        result["group_by"] = .string(group)
        result["groups"] = .array(grouped.keys.sorted().map { key in
            let groupRows = grouped[key] ?? []
            var values = totals(groupRows); values["group"] = .string(CategoryNamespace.split(key).name)
            if group == "category" || group == "subcategory" {
                values["category_income"] = .bool(CategoryNamespace.split(key).income ?? false)
                let small = Dictionary(grouping: groupRows) { entry -> String in
                    return ctx.ledger.normalizedCategory(for: entry, entriesByID: byID).subcategory ?? "没分类"
                }
                values["subcategories"] = .array(small.keys.sorted().map { name in
                    var row = totals(small[name] ?? []); row["subcategory"] = name == "没分类" ? .null : .string(name); return .object(row)
                })
                if group == "subcategory" { values["subcategory"] = groupRows.first.flatMap { entry in ctx.ledger.normalizedCategory(for: entry, entriesByID: byID).subcategory }.map(JSONValue.string) ?? .null }
            }
            return .object(values)
        })
        result["matched_count"] = .number(Double(all.count)); result["truncated"] = .bool(rows.count < all.count)
        // Keep payloads bounded; totals cover every row, evidence is a representative recent sample.
        result["entry_ids"] = .strings(rows.prefix(50).map { $0.id.uuidString })
        result["evidence_truncated"] = .bool(rows.count > 50)
        let points = grouped.keys.sorted().map { key in
            AnswerChart.Point(label: ctx.redactor.text(CategoryNamespace.split(key).name), cents: (grouped[key] ?? []).reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ctx.ledger) })
        }
        return (ctx.redactor.value(.object(result)), AnswerChart(kind: ["category", "subcategory"].contains(group) ? .bar : .line, title: "消费汇总（元）", points: points))
    }

    private func habit(_ fields: [String: JSONValue], _ ctx: ToolContext) throws -> JSONValue {
        let category = try Self.optionalString(fields["category"])
        let keyword = try Self.optionalString(fields["keyword"])
        let subcategory = try Self.optionalString(fields["subcategory"])
        guard category != nil || keyword != nil || subcategory != nil else { throw YubaiError.invalid("请提供category或keyword。") }
        var filters = fields; filters.removeValue(forKey: "amount"); filters["nature"] = .string("spending")
        if subcategory != nil { filters.removeValue(forKey: "keyword") }
        let start = Dates.addDays(-89, to: Dates.day(ctx.now))
        let matching = try Filter(filters).entries(ctx).filter { $0.nature == .expense }
        let rows = matching.filter { $0.date >= start && $0.date <= ctx.now }
        let amounts = rows.map { Finance.spendingAmount($0, ledger: ctx.ledger) }.sorted()
        var result: [String: JSONValue] = ["window_days": .number(90), "count": .number(Double(rows.count)),
            "count_per_week": .number(Double(rows.count) * 7 / 90),
            "recent": .array(rows.prefix(5).map { summary($0, ctx) }), "entry_ids": .strings(rows.prefix(5).map { $0.id.uuidString })]
        if let end = Dates.calendar.date(byAdding: .year, value: -1, to: ctx.now) {
            let priorStart = Dates.addDays(-89, to: Dates.day(end))
            let prior = matching.filter { $0.date >= priorStart && $0.date <= end }
            if !prior.isEmpty {
                result["last_year"] = .object(["window_days": .number(90), "count": .number(Double(prior.count)),
                    "average": .money(prior.reduce(Int64(0)) { $0 + Finance.spendingAmount($1, ledger: ctx.ledger) } / Int64(prior.count))])
            }
        }
        var sample = Entry(date: ctx.now, amount: 1, accountID: UUID(), title: keyword ?? "", category: category ?? "")
        sample.subcategory = subcategory
        let areas = ctx.ledger.profile.restrain.filter { ButlerCards.matches($0, entry: sample, ledger: ctx.ledger) }
        if !areas.isEmpty {
            result["soft_limits"] = .array(areas.map { area in .object(["id": .string(area.id.uuidString), "title": .string(area.title),
                "per_week_count": area.softLimit?.perWeekCount.map { .number(Double($0)) } ?? .null,
                "per_month_amount": area.softLimit?.perMonthAmount.map { .money($0) } ?? .null]) })
        }
        if amounts.isEmpty {
            result["average"] = .null; result["median"] = .null
            if let value = fields["amount"] { result["amount"] = .money(try Self.amount(value)); result["percentile"] = .null }
        } else {
            let total = amounts.reduce(Int64(0), +)
            let middle = amounts.count / 2
            let median = amounts.count % 2 == 0 ? amounts[middle - 1] + (amounts[middle] - amounts[middle - 1]) / 2 : amounts[middle]
            result["average"] = .money(total / Int64(amounts.count)); result["median"] = .money(median)
            result["rounding"] = .string("均值和中位数不足一分的部分舍去。")
            if let value = fields["amount"] {
                let amount = try Self.amount(value)
                result["amount"] = .money(amount)
                result["percentile"] = .number(Double(amounts.filter { $0 <= amount }.count) / Double(amounts.count) * 100)
                result["percentile_meaning"] = .string("历史同类消费中，金额小于或等于本次金额的百分比。")
            }
        }
        return .object(result)
    }

    private func summary(_ entry: Entry, _ ctx: ToolContext) -> JSONValue {
        .object(["id": .string(entry.id.uuidString), "date": .string(Dates.text(entry.date)),
            "amount": .money(entry.amount), "spending_amount": .money(Finance.spendingAmount(entry, ledger: ctx.ledger)),
            "direction": .string(entry.nature.paired ? "transfer" : (entry.nature.inflow ? "income" : "spending")),
            "nature": .string(entry.nature.rawValue), "title": .string(entry.displayTitle), "category": .string(ctx.ledger.normalizedCategory(for: entry, entriesByID: ctx.entriesByID).category),
            "subcategory": ctx.ledger.normalizedCategory(for: entry, entriesByID: ctx.entriesByID).subcategory.map(JSONValue.string) ?? .null,
            "account": .string(entry.accountID.uuidString),
            "account_kind": .string(ctx.ledger.accounts.first { $0.id == entry.accountID }?.kind.rawValue ?? "unknown")])
    }

    private struct Filter {
        var start: Date?; var end: Date?; var category: String?; var subcategory: String?; var nature: String?; var keyword: String?
        var minimum: Int64?; var maximum: Int64?; var limit: Int?
        init(_ fields: [String: JSONValue]) throws {
            start = try fields["start_date"].map { try ReadOnlyTool.date($0) }
            end = try fields["end_date"].map { Dates.addDays(1, to: try ReadOnlyTool.date($0)) }
            category = try ReadOnlyTool.optionalString(fields["category"])
            subcategory = try ReadOnlyTool.optionalString(fields["subcategory"])
            nature = try ReadOnlyTool.optionalString(fields["nature"])
            keyword = try ReadOnlyTool.optionalString(fields["keyword"])
            minimum = try fields["min_amount"].map { try ReadOnlyTool.amount($0) }
            maximum = try fields["max_amount"].map { try ReadOnlyTool.amount($0) }
            limit = try fields["limit"].map { try ReadOnlyTool.integer($0, range: 1...50) }
            if let start, let end, start >= end { throw YubaiError.invalid("日期范围颠倒。") }
            if let minimum, let maximum, minimum > maximum { throw YubaiError.invalid("金额范围颠倒。") }
            if let nature, !["spending", "income", "transfer"].contains(nature) { throw YubaiError.invalid("nature必须是spending/income/transfer。") }
        }
        func entries(_ ctx: ToolContext) -> [Entry] {
            let byID = ctx.entriesByID
            return ctx.ledger.activeEntries.filter { e in
                if let start, e.date < start { return false }
                if let end, e.date >= end { return false }
                if let category, ctx.ledger.normalizedCategory(for: e, entriesByID: byID).category != ctx.ledger.resolveCategory(category, income: e.nature.categoryIncome) { return false }
                if let subcategory {
                    if ctx.ledger.normalizedCategory(for: e, entriesByID: byID).subcategory != subcategory { return false }
                }
                if let keyword {
                    let text = e.title + " " + (e.purpose ?? "") + " " + e.note
                    if !text.localizedCaseInsensitiveContains(keyword) && !ctx.redactor.text(text).localizedCaseInsensitiveContains(keyword) { return false }
                }
                if let minimum, e.amount < minimum { return false }
                if let maximum, e.amount > maximum { return false }
                switch nature {
                case "spending": return e.nature == .expense || e.nature == .refund
                case "income": return e.nature == .income
                case "transfer": return e.nature.paired
                default: return true
                }
            }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        }
    }
    private static func optionalString(_ value: JSONValue?) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw YubaiError.invalid("文本参数不能为空。") }
        return text
    }
    private static func date(_ value: JSONValue) throws -> Date {
        guard let text = value.stringValue, text.count == 10, let date = Dates.parse(text), Dates.text(date) == text else {
            throw YubaiError.invalid("日期请用yyyy-MM-dd格式。")
        }
        return Dates.day(date)
    }
    private static func amount(_ value: JSONValue) throws -> Int64 {
        if let text = value.stringValue { return try Money.parse(text) }
        if case .number(let n) = value, n.isFinite { return try Money.parse(NSDecimalNumber(value: n).stringValue) }
        throw YubaiError.invalid("金额请用人民币元，最多两位小数。")
    }
    private static func integer(_ value: JSONValue?, range: ClosedRange<Int>) throws -> Int {
        guard let value, case .number(let n) = value, let integer = Int(exactly: n), range.contains(integer) else { throw YubaiError.invalid("整数参数超出范围。") }
        return integer
    }
}
