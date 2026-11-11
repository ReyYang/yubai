import Foundation

/// Builds local proposals only. The agent collects them; persistence belongs to AppStore.
public enum ProposalTool: String, CaseIterable, AssistantTool {
    case entryChanges = "propose_entry_changes", plan = "propose_plan"
    case entry = "propose_entry", profile = "propose_profile_change"
    public static var all: [any AssistantTool] { allCases.map { $0 as any AssistantTool } }
    public var name: String { rawValue }
    public var description: String {
        switch self {
        case .entryChanges: return "提议整理现有记录，只能改变分类、性质、用途或关联，不能改金额、主账户、原始日期。用户确认后才应用。"
        case .plan: return "提议新增/结束资金安排或新增房租；金额为人民币元。收入安排可用into_fixed_savings直接放入存着的钱。用户确认后才应用。"
        case .entry: return "提议语音或截图补记，多笔用entries一次提出全部。金额只能取本机从原文解析的候选或用户已核对金额；AI不能确认金额，草稿等待用户确认。收入可用into_fixed_savings直接放入存着的钱，不计入每月存的收入比例。"
        case .profile: return "提议新增/修改/移除愿意多花或想克制的领域、消费原则或存着的钱；不搬动储蓄目标。可用items一次提交整份消费观，用户确认后才应用。"
        }
    }
    private static func string(_ description: String) -> JSONValue { .object(["type": .string("string"), "description": .string(description)]) }
    private static func choice(_ values: [String]) -> JSONValue { .object(["type": .string("string"), "enum": .strings(values)]) }
    private static func object(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object(["type": .string("object"), "properties": .object(properties), "required": .strings(required), "additionalProperties": .bool(false)])
    }
    public var parameters: JSONValue {
        var fields: [String: JSONValue] = ["reason": Self.string("提案依据，简短中文")]
        let id = Self.string("本地UUID，从查询结果取，不猜测")
        let amount = Self.string("人民币元，十进制文本，最多两位小数")
        let date = Self.string("yyyy-MM-dd")
        let intoFixedSavings: JSONValue = .object(["type": .string("boolean"), "description": .string("仅nature=income可用；true表示进账直接放入存着的钱，不计入周期收入及每月存比例；默认false")])
        switch self {
        case .entryChanges:
            fields["items"] = .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(200), "items": Self.object([
                "kind": Self.choice(["set_category", "set_nature", "set_purpose", "pair_transfer", "link_refund", "link_plan", "link_rent", "mark_duplicate"]),
                "entry": id, "other_entry": id, "category": Self.string("分类名"),
                "nature": Self.choice(Nature.allCases.map(\.rawValue)), "other_account": id,
                "text": Self.string("用途"), "plan": id, "rent": id, "date": Self.string("仅 link_plan/link_rent 使用，yyyy-MM-dd；不修改原始日期")
            ], required: ["kind", "entry"])])
        case .plan:
            fields.merge(["operation": Self.choice(["add_plan", "end_plan", "add_rent"]), "id": id,
                "title": Self.string("安排标题"), "amount": amount, "date": date,
                "frequency": Self.choice(Frequency.allCases.map(\.rawValue)), "nature": Self.choice(Nature.allCases.map(\.rawValue)),
                "category": Self.string("分类"), "account": id, "personal_share": amount, "into_fixed_savings": intoFixedSavings,
                "start_date": date, "months_per_payment": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(12)]),
                "receive_day": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(28)])
            ]) { _, new in new }
        case .entry:
            let entryFields: [String: JSONValue] = ["title": Self.string("原始描述，参考parsed_entries"), "amount": amount, "date": date, "account": id,
                "nature": Self.choice(Nature.allCases.map(\.rawValue)), "category": Self.string("分类"), "purpose": Self.string("用途"), "into_fixed_savings": intoFixedSavings]
            fields.merge(entryFields) { _, new in new }
            fields["entries"] = .object(["type": .string("array"), "minItems": .number(1),
                "description": .string("一次提出全部补记；与顶层单笔字段二选一，金额及同额次数必须来自本机候选。"),
                "items": Self.object(entryFields, required: ["title", "amount", "date", "account"])])
        case .profile:
            fields.merge(Self.profileFields) { _, new in new }
            fields["items"] = .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(200),
                "description": .string("整份消费观或多项反馈用一次调用提交；与顶层operation二选一。"),
                "items": Self.object(Self.profileFields, required: ["operation"])])
        }
        var required = ["reason"]
        switch self {
        case .entryChanges: required.append("items")
        case .plan: required.append("operation")
        case .profile: break
        case .entry: break
        }
        return Self.object(fields, required: required)
    }
    private static var profileFields: [String: JSONValue] {
        return ["operation": Self.choice(["upsert_area", "remove_area", "add_principle", "edit_principle", "remove_principle", "set_floor", "clear_floor"]),
                "id": Self.string("本地UUID，从查询结果取"), "stance": Self.choice(["generous", "restrain"]), "title": Self.string("领域名"),
                "categories": .object(["type": .string("array"), "items": Self.string("分类名")]),
                "subcategories": .object(["type": .string("array"), "items": Self.string("主项/小项")]),
                "keywords": .object(["type": .string("array"), "items": Self.string("关键词")]),
                "note": Self.string("领域说明"), "per_week_count": .object(["type": .string("integer"), "minimum": .number(0), "maximum": .number(10000)]),
                "per_month_amount": Self.string("人民币元，最多两位小数"), "text": Self.string("消费原则"), "old_text": Self.string("原消费原则"), "amount": Self.string("人民币元，最多两位小数")
            ]
    }
    private static func profileChange(_ a: Arguments) throws -> ProfileChange {
        let change: ProfileChange
        switch try a.text("operation") {
        case "upsert_area":
            guard let stance = ProfileStance(rawValue: try a.text("stance")) else { throw YubaiError.invalid("请选择愿意多花或想克制。") }
            let count: Int? = a.fields["per_week_count"] == nil ? nil : try a.integer("per_week_count", fallback: 0, range: 0...10000)
            let monthly: Int64? = a.fields["per_month_amount"] == nil ? nil : try a.amount("per_month_amount")
            var area = ProfileArea(title: try a.text("title"), match: AreaMatch(categories: try a.strings("categories"), keywords: try a.strings("keywords"), subcategories: try a.strings("subcategories")),
                                   note: try a.optionalText("note") ?? "", softLimit: count == nil && monthly == nil ? nil : SoftLimit(perWeekCount: count, perMonthAmount: monthly))
            if let id = try a.optionalUUID("id") { area.id = id }
            change = .upsertArea(area, stance: stance)
        case "remove_area": change = .removeArea(try a.uuid("id"))
        case "add_principle": change = .addPrinciple(try a.text("text"))
        case "edit_principle": change = .editPrinciple(old: try a.text("old_text"), new: try a.text("text"))
        case "remove_principle": change = .removePrinciple(try a.text("text"))
        case "set_floor": change = .setFloorAmount(try a.amount("amount"))
        case "clear_floor": change = .setFloorAmount(nil)
        default: throw YubaiError.invalid("未知的画像修改。")
        }
        return change
    }

    public func run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue {
        let change = try propose(args, ctx); return result(change, ctx)
    }
    public func propose(_ args: JSONValue, _ ctx: ToolContext) throws -> ChangeSet {
        let a = try Arguments(args, schema: parameters)
        func category(_ raw: String, nature: Nature) throws -> String {
            if nature == .transfer { return "内部移动" }
            if Classification.isPending(raw) { return Classification.pendingCategory }
            guard let choice = CategoryMapping.match(raw, in: ctx.ledger, income: nature.categoryIncome) else { throw YubaiError.invalid("请选择已有分类。") }
            return choice.category
        }
        let items: [ChangeItem]
        switch self {
        case .entryChanges:
            guard let rows = a.fields["items"]?.arrayValue, !rows.isEmpty, rows.count <= 200,
                  let itemSchema = parameters["properties"]?["items"]?["items"] else { throw YubaiError.invalid("请提供 1 至 200 项整理修改。") }
            items = try rows.map { row in
                let r = try Arguments(row, schema: itemSchema); let id = try r.uuid("entry")
                let kind = try r.text("kind")
                let extra: [String]
                switch kind {
                case "set_category": extra = ["category"]
                case "set_nature": extra = ["nature", "other_account"]
                case "set_purpose": extra = ["text"]
                case "pair_transfer": extra = ["other_entry", "nature"]
                case "link_refund", "mark_duplicate": extra = ["other_entry"]
                case "link_plan": extra = ["plan", "date"]
                case "link_rent": extra = ["rent", "date"]
                default: throw YubaiError.invalid("未知的整理项目。")
                }
                guard Set(r.fields.keys).isSubset(of: Set(["kind", "entry"] + extra)) else { throw YubaiError.invalid("这个整理项目包含不适用的字段。") }
                switch kind {
                case "set_category": return .setCategory(entry: id, category: try r.text("category"))
                case "set_nature": return .setNature(entry: id, nature: try r.nature(), otherAccount: try r.optionalUUID("other_account"))
                case "set_purpose": return .setPurpose(entry: id, text: try r.text("text"))
                case "pair_transfer": return .pairTransfer(a: id, b: try r.uuid("other_entry"), nature: try r.nature(default: .transfer))
                case "link_refund": return .linkRefund(refund: id, original: try r.uuid("other_entry"))
                case "link_plan": return .linkPlan(entry: id, plan: try r.uuid("plan"), occurrence: try r.date("date"))
                case "link_rent": return .linkRent(entry: id, rent: try r.uuid("rent"), period: try r.date("date"))
                case "mark_duplicate": return .markDuplicate(entry: id, of: try r.uuid("other_entry"))
                default: throw YubaiError.invalid("未知的整理项目。")
                }
            }
        case .plan:
            switch try a.text("operation") {
            case "add_plan":
                let nature = try a.nature(default: .expense)
                let frequencyText = try a.optionalText("frequency") ?? "once"
                guard let frequency = Frequency(rawValue: frequencyText) else { throw YubaiError.invalid("安排周期无效。") }
                var plan = Plan(title: try a.text("title"), amount: try a.amount("amount"), dueDate: try a.date("date"),
                                frequency: frequency, inflow: nature.inflow, category: try category(a.optionalText("category") ?? Classification.pendingCategory, nature: nature), nature: nature,
                                intoFixedSavings: try a.intoFixedSavings(nature: nature))
                plan.accountID = try a.optionalUUID("account"); items = [.addPlan(plan)]
            case "end_plan":
                guard a.fields["into_fixed_savings"] == nil else { throw YubaiError.invalid("只有收入安排可以直接放入存着的钱。") }
                items = [.endPlan(try a.uuid("id"), try a.date("date"))]
            case "add_rent":
                guard a.fields["into_fixed_savings"] == nil else { throw YubaiError.invalid("只有收入安排可以直接放入存着的钱。") }
                var rent = Rent(title: try a.text("title"), monthlyTotal: try a.amount("amount"), personalShare: try a.amount("personal_share"),
                                startDate: try a.date("start_date"), nextDueDate: try a.date("date"),
                                monthsPerPayment: try a.integer("months_per_payment", fallback: 3, range: 1...12),
                                receiveDay: try a.integer("receive_day", fallback: 1, range: 1...28))
                rent.accountID = try a.optionalUUID("account"); items = [.addRent(rent)]
            default: throw YubaiError.invalid("未知的安排修改。")
            }
        case .entry:
            let rows: [Arguments]
            if let entries = a.fields["entries"] {
                guard Set(a.fields.keys) == Set(["reason", "entries"]), let values = entries.arrayValue, !values.isEmpty,
                      let schema = parameters["properties"]?["entries"]?["items"] else { throw YubaiError.invalid("entries需要非空补记数组，不能混用单笔参数。") }
                rows = try values.map { try Arguments($0, schema: schema) }
            } else { rows = [a] }
            var available: [Int64: Int] = [:]
            for amount in ctx.parsedEntryAmounts { available[amount, default: 0] += 1 }
            // A confirmed single draft authorizes one occurrence, never unlimited reuse.
            if let amount = ctx.confirmedEntryAmount { available[amount] = max(available[amount, default: 0], 1) }
            var confirmedAvailable = ctx.confirmedEntryAmount != nil
            items = try rows.map { row in
                try Task.checkCancellation()
                let amount = try row.amount("amount")
                guard available[amount, default: 0] > 0 else {
                    throw YubaiError.invalid("金额及同额使用次数必须来自本机解析的原文，请补充或核对金额。")
                }
                available[amount, default: 0] -= 1
                let confirmed = confirmedAvailable && ctx.confirmedEntryAmount == amount
                if confirmed { confirmedAvailable = false }
                let nature = try row.nature(default: .expense)
                return .addEntry(EntryDraft(date: try row.date("date"), amount: amount, amountConfirmed: confirmed,
                    nature: nature, accountID: try row.uuid("account"), title: try row.text("title"),
                    category: try category(row.optionalText("category") ?? Classification.pendingCategory, nature: nature), purpose: try row.optionalText("purpose"),
                    intoFixedSavings: try row.intoFixedSavings(nature: nature)))
            }
        case .profile:
            if let rows = a.fields["items"]?.arrayValue {
                guard a.fields["operation"] == nil, Set(a.fields.keys) == Set(["reason", "items"]),
                      !rows.isEmpty, rows.count <= 200 else { throw YubaiError.invalid("整份消费观需要 1 至 200 项，不能混用单项参数。") }
                items = try rows.map { row in
                    .profile(try Self.profileChange(Arguments(row, schema: Self.object(Self.profileFields, required: ["operation"]))))
                }
            } else {
                guard a.fields["items"] == nil else { throw YubaiError.invalid("items 需要修改数组。") }
                items = [.profile(try Self.profileChange(a))]
            }
        }
        var change = ChangeSet(source: "问余白", reason: try a.text("reason"), items: items); change.createdAt = ctx.now
        var copy = ctx.ledger; _ = try validatedDrafts(change).apply(to: &copy)
        return change
    }
    // Validate all fields on a throwaway copy; the returned draft stays unconfirmed.
    private func validatedDrafts(_ change: ChangeSet) -> ChangeSet {
        var check = change
        check.items = change.items.map { item in
            if case .addEntry(var draft) = item { draft.amountConfirmed = true; return .addEntry(draft) }
            return item
        }
        return check
    }
    func result(_ change: ChangeSet, _ ctx: ToolContext) -> JSONValue {
        var copy = ctx.ledger
        let skipped = (try? validatedDrafts(change).apply(to: &copy)) ?? []
        return ctx.redactor.value(.object(["id": .string(change.id.uuidString), "preview": .strings(change.preview(in: ctx.ledger)),
                                          "skipped": .strings(skipped), "entry_ids": .strings(change.items.flatMap(\.entryIDs).map { $0.uuidString }),
                                          "status": .string("仅提案，等待用户确认，尚未修改账本")]))
    }
}

private struct Arguments {
    let fields: [String: JSONValue]
    init(_ value: JSONValue, schema: JSONValue) throws {
        let keys = Set(schema["properties"]?.objectValue?.keys.map { $0 } ?? [])
        guard let fields = value.objectValue, Set(fields.keys).isSubset(of: keys) else { throw YubaiError.invalid("修改参数只能包含声明的字段。") }
        self.fields = fields
    }
    func text(_ key: String) throws -> String {
        guard let s = fields[key]?.stringValue, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.count <= 4000 else { throw YubaiError.invalid("修改缺少有效的 \(key)。") }
        return s
    }
    func optionalText(_ key: String) throws -> String? { fields[key] == nil ? nil : try text(key) }
    func uuid(_ key: String) throws -> UUID {
        guard let id = UUID(uuidString: try text(key)) else { throw YubaiError.invalid("\(key) 不是有效标识。") }; return id
    }
    func optionalUUID(_ key: String) throws -> UUID? { fields[key] == nil ? nil : try uuid(key) }
    func date(_ key: String) throws -> Date {
        let text = try self.text(key)
        guard text.count == 10, let date = Dates.parse(text), Dates.text(date) == text else { throw YubaiError.invalid("\(key) 需要 yyyy-MM-dd 日期。") }; return date
    }
    func amount(_ key: String) throws -> Int64 { try Money.parse(text(key)) }
    func nature(default fallback: Nature? = nil) throws -> Nature {
        if fields["nature"] == nil, let fallback { return fallback }
        guard let nature = Nature(rawValue: try text("nature")) else { throw YubaiError.invalid("资金性质无效。") }; return nature
    }
    func intoFixedSavings(nature: Nature) throws -> Bool {
        guard let value = fields["into_fixed_savings"] else { return false }
        guard nature == .income, case .bool(let flag) = value else { throw YubaiError.invalid("只有收入可以直接放入存着的钱，into_fixed_savings需要布尔值。") }
        return flag
    }
    func strings(_ key: String) throws -> [String] {
        guard let value = fields[key] else { return [] }
        guard let array = value.arrayValue, array.count <= 200 else { throw YubaiError.invalid("\(key) 需要文本数组。") }
        return try array.map { guard let s = $0.stringValue, !s.isEmpty, s.count <= 4000 else { throw YubaiError.invalid("\(key) 含无效文本。") }; return s }
    }
    func integer(_ key: String, fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value = fields[key] else { return fallback }
        guard case .number(let n) = value, n.isFinite, n.rounded() == n, n >= Double(range.lowerBound), n <= Double(range.upperBound) else { throw YubaiError.invalid("\(key) 超出范围。") }
        return Int(n)
    }
}
