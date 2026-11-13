import Foundation

public enum ProfileStance: String, Codable, Sendable { case generous, restrain }
public enum ProfileChange: Codable, Equatable, Sendable {
    /// The same ID edits/moves an existing area; a new ID adds one.
    case upsertArea(ProfileArea, stance: ProfileStance), removeArea(UUID)
    case addPrinciple(String), editPrinciple(old: String, new: String), removePrinciple(String)
    case setFloorAmount(Int64?)
}
public struct EntryDraft: Codable, Equatable, Sendable {
    public var id = UUID(); public var date: Date; public var amount: Int64; public var amountConfirmed: Bool
    public var nature: Nature { didSet { if nature != .income { intoFixedSavings = false }; if nature != .expense { fromReserve = false } } }
    public var intoFixedSavings = false { didSet { if nature != .income { intoFixedSavings = false } } }
    public var fromReserve = false { didSet { if nature != .expense { fromReserve = false } } }
    public var accountID: UUID; public var title: String; public var category: String
    public var partID: UUID?
    public var purpose: String?
    public var subcategory: String?
    /// Set by review editors only when a user changes the proposed category.
    public var categoryUserEdited: Bool?
    public var otherAccountID: UUID?
    public var planID: UUID?; public var occurrence: Date?
    public init(date: Date, amount: Int64, amountConfirmed: Bool = false, nature: Nature = .expense,
                accountID: UUID, title: String, category: String = Classification.pendingCategory, subcategory: String? = nil, purpose: String? = nil, planID: UUID? = nil, occurrence: Date? = nil, intoFixedSavings: Bool = false, fromReserve: Bool = false) {
        self.date = date; self.amount = amount; self.amountConfirmed = amountConfirmed; self.nature = nature
        self.accountID = accountID; self.title = title; self.category = category; self.subcategory = subcategory; self.purpose = purpose
        self.planID = planID; self.occurrence = occurrence
        self.intoFixedSavings = nature == .income && intoFixedSavings
        self.fromReserve = nature == .expense && fromReserve
    }
    private enum CodingKeys: String, CodingKey {
        case id, date, amount, amountConfirmed, nature, fromReserve, intoFixedSavings, accountID, title, category, partID, purpose, subcategory, categoryUserEdited, otherAccountID, planID, occurrence
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(Int64.self, forKey: .amount); amountConfirmed = try c.decode(Bool.self, forKey: .amountConfirmed)
        nature = try c.decode(Nature.self, forKey: .nature)
        let intoFixed = try c.decodeIfPresent(Bool.self, forKey: .intoFixedSavings) ?? false
        intoFixedSavings = nature == .income && intoFixed
        let reserve = try c.decodeIfPresent(Bool.self, forKey: .fromReserve) ?? false
        fromReserve = nature == .expense && reserve
        accountID = try c.decode(UUID.self, forKey: .accountID); title = try c.decode(String.self, forKey: .title)
        category = try c.decode(String.self, forKey: .category); partID = try c.decodeIfPresent(UUID.self, forKey: .partID)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose); subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        categoryUserEdited = try c.decodeIfPresent(Bool.self, forKey: .categoryUserEdited)
        otherAccountID = try c.decodeIfPresent(UUID.self, forKey: .otherAccountID)
        planID = try c.decodeIfPresent(UUID.self, forKey: .planID); occurrence = try c.decodeIfPresent(Date.self, forKey: .occurrence)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(date, forKey: .date)
        try c.encode(amount, forKey: .amount); try c.encode(amountConfirmed, forKey: .amountConfirmed)
        try c.encode(nature, forKey: .nature)
        if intoFixedSavings { try c.encode(true, forKey: .intoFixedSavings) }
        if fromReserve { try c.encode(true, forKey: .fromReserve) }
        try c.encode(accountID, forKey: .accountID); try c.encode(title, forKey: .title); try c.encode(category, forKey: .category)
        try c.encodeIfPresent(partID, forKey: .partID); try c.encodeIfPresent(purpose, forKey: .purpose)
        try c.encodeIfPresent(subcategory, forKey: .subcategory); try c.encodeIfPresent(categoryUserEdited, forKey: .categoryUserEdited)
        try c.encodeIfPresent(otherAccountID, forKey: .otherAccountID); try c.encodeIfPresent(planID, forKey: .planID)
        try c.encodeIfPresent(occurrence, forKey: .occurrence)
    }

}
public enum ChangeItem: Codable, Equatable, Sendable {
    case setCategory(entry: UUID, category: String)
    case setNature(entry: UUID, nature: Nature, otherAccount: UUID?)
    case setPurpose(entry: UUID, text: String)
    case pairTransfer(a: UUID, b: UUID, nature: Nature)
    case linkRefund(refund: UUID, original: UUID)
    case linkPlan(entry: UUID, plan: UUID, occurrence: Date)
    case linkRent(entry: UUID, rent: UUID, period: Date)
    case markDuplicate(entry: UUID, of: UUID)
    case addPlan(Plan), updatePlan(Plan), endPlan(UUID, Date), resumePlan(UUID), addRent(Rent), addEntry(EntryDraft)
    case skipOccurrence(UUID, Date)
    case profile(ProfileChange)

    public var entryIDs: [UUID] {
        switch self {
        case .setCategory(let id, _), .setNature(let id, _, _), .setPurpose(let id, _),
             .linkPlan(let id, _, _), .linkRent(let id, _, _): return [id]
        case .pairTransfer(let a, let b, _), .linkRefund(let a, let b), .markDuplicate(let a, let b): return [a, b]
        default: return []
        }
    }
}
public struct ChangeSet: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var createdAt = Date(); public var source: String; public var reason: String
    public var items: [ChangeItem]
    public init(source: String, reason: String, items: [ChangeItem]) { self.source = source; self.reason = reason; self.items = items }
    public var isProfileOnly: Bool {
        !items.isEmpty && items.allSatisfy { if case .profile = $0 { return true }; return false }
    }

    public func validateStructure() throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source.count <= 200,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 4000,
              !items.isEmpty,
              (-2_208_988_800...7_258_118_400).contains(createdAt.timeIntervalSince1970) else { throw YubaiError.invalid("修改的来源、明细、时间或项目数量无效。") }
        for case .updatePlan(let plan) in items { try FixedFlows.validateUpdateFields(plan) }
    }
    public func preview(in ledger: Ledger, showPreviousValues: Bool = false) -> [String] {
        let entries = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        func entry(_ id: UUID) -> String {
            guard let e = entries[id] else { return "已移除的记录" }
            let parts = Dates.calendar.dateComponents([.month, .day], from: e.date)
            return "\(parts.month ?? 1)月\(parts.day ?? 1)日 \(e.displayTitle) \(e.nature.inflow ? "+" : "−")\(Money.text(e.amount, currency: false))"
        }
        var lines = items.map { item in
            switch item {
            case .setCategory(let id, let category):
                if showPreviousValues, let original = entries[id] {
                    return entry(id) + " · " + original.category + " → " + category
                }
                return "把 \(entry(id)) 归为 \(category)"
            case .setNature(let id, let nature, let other):
                if showPreviousValues, let original = entries[id] {
                    return entry(id) + " · " + original.nature.label + " → " + nature.label + (other.map { "，关联" + ledger.accountName($0) } ?? "")
                }
                return "把 \(entry(id)) 标为 \(nature.label)" + (other.map { "，关联\(ledger.accountName($0))" } ?? "")
            case .setPurpose(let id, let text):
                if showPreviousValues, let original = entries[id] {
                    return entry(id) + " · 「" + (original.purpose ?? original.title) + "」 → 「" + text + "」"
                }
                return "把 \(entry(id)) 的用途记为「\(text)」"
            case .pairTransfer(let a, let b, let nature): return "把 \(entry(a)) 与 \(entry(b)) 配对为\(nature.label)"
            case .linkRefund(let refund, let original): return "把 \(entry(refund)) 关联为 \(entry(original)) 的退款"
            case .linkPlan(let id, let plan, let date): return "把 \(entry(id)) 关联为 \(Dates.text(date)) \(ledger.plans.first { $0.id == plan }?.title ?? "资金安排")"
            case .linkRent(let id, let rent, let date): return "把 \(entry(id)) 关联为 \(Dates.calendar.component(.month, from: date)) 月\(ledger.rents.first { $0.id == rent }?.title ?? "房租")\(entries[id]?.nature.inflow == true ? "分摊" : "付款")"
            case .markDuplicate(let id, let original): return "把 \(entry(id)) 作为 \(entry(original)) 的重复记录标为已删除"
            case .addPlan(let p): return "新增\(p.frequency.label)\(p.nature.label)安排「\(p.title)」\(Money.text(p.amount))，从 \(Dates.text(p.dueDate)) 开始" + (p.accountID.map { "，使用\(ledger.accountName($0))" } ?? "") + (p.intoFixedSavings ? "，存着不动" : "")
            case .updatePlan(let p): return FixedFlows.describeUpdate(p, in: ledger)
            case .endPlan(let id, let date): return "将「\(ledger.plans.first { $0.id == id }?.title ?? ledger.rents.first { $0.id == id }?.title ?? "资金安排")」在 \(Dates.text(date)) 之后的安排结束，已到期付款保留"
            case .resumePlan(let id): return "恢复「\(ledger.plans.first { $0.id == id }?.title ?? ledger.rents.first { $0.id == id }?.title ?? "资金安排")」"
            case .skipOccurrence(let id, let date): return "跳过「\(ledger.plans.first { $0.id == id }?.title ?? "资金安排")」\(Dates.text(date))这期"
            case .addRent(let r): return "新增「\(r.title)」，月租 \(Money.text(r.monthlyTotal))，个人承担 \(Money.text(r.personalShare))，每 \(r.monthsPerPayment) 月支付，从 \(Dates.text(r.startDate)) 起，首付 \(Dates.text(r.nextDueDate))，每月 \(r.receiveDay) 日收分摊" + (r.accountID.map { "，使用\(ledger.accountName($0))" } ?? "")
            case .addEntry(let d):
                let link = d.planID.flatMap { id in d.occurrence.map { "，关联为 \(Dates.text($0)) \(ledger.plans.first { $0.id == id }?.title ?? d.title)" } } ?? ""
                return "新增 \(Dates.text(d.date)) \(d.purpose ?? d.title) \(Money.text(d.amount))（\(d.nature.label)，\(ledger.accountName(d.accountID))，\(d.amountConfirmed ? "金额已确认" : "金额待确认")）" + link + (d.intoFixedSavings ? "，存着不动" : "")
            case .profile(let change):
                switch change {
                case .upsertArea(let area, let stance):
                    var line = "将「\(area.title)」记为\(stance == .generous ? "愿意多花" : "想克制")的领域"
                    if !area.match.categories.isEmpty { line += "，分类：" + area.match.categories.joined(separator: "、") }
                    if !area.match.keywords.isEmpty { line += "，关键词：" + area.match.keywords.joined(separator: "、") }
                    if !area.note.isEmpty { line += "，说明：" + area.note }
                    if let count = area.softLimit?.perWeekCount { line += "，每周最多 \(count) 次" }
                    if let amount = area.softLimit?.perMonthAmount { line += "，每月最多 \(Money.text(amount))" }
                    return line
                case .removeArea(let id): return "移除消费领域「\((ledger.profile.generous + ledger.profile.restrain).first { $0.id == id }?.title ?? "已移除")」"
                case .addPrinciple(let text): return "新增消费原则「\(text)」"
                case .editPrinciple(let old, let new): return "将消费原则「\(old)」改为「\(new)」"
                case .removePrinciple(let text): return "移除消费原则「\(text)」"
                case .setFloorAmount(let amount):
                    let total = max(amount ?? 0, ledger.fixedSavingsFromIncome(now: createdAt))
                    return amount == nil && total == 0 ? "存着不动 0.00" : "存着不动 \(Money.text(total))"
                }
            }
        }
        let drafts = items.compactMap { item -> EntryDraft? in if case .addEntry(let draft) = item { return draft }; return nil }
        if drafts.count > 1 {
            var total: Int64 = 0
            for draft in drafts {
                let sum = total.addingReportingOverflow(draft.amount)
                guard !sum.overflow else { lines.append("合计金额超出可显示范围"); return lines }
                total = sum.partialValue
            }
            lines.append("合计 \(drafts.count) 笔，\(Money.text(total))")
        }
        return lines
    }

    /// Reports stale items. All validation happens on a copy, so throws never partially mutate the ledger.
    @discardableResult public func apply(to ledger: inout Ledger) throws -> [String] {
        try validateStructure(); try ledger.validate()
        // A single append cannot reclassify existing entries. Avoid building
        // whole-ledger indexes and comparing every original against its copy.
        if items.count == 1, case .addEntry(let draft) = items[0], !ledger.entries.contains(where: { $0.id == draft.id }) {
            var next = ledger
            let entry = try addedEntry(draft, in: ledger)
            next.entries.append(entry)
            if source == "手动" || draft.categoryUserEdited == true { CategoryMemory.remember(entry, in: &next) }
            try next.validate(); ledger = next; return []
        }
        var next = ledger; var skipped: [String] = []
        var changedExpenseCategories: [UUID: String] = [:]
        var incomingTransfers: Set<UUID> = []
        func validDate(_ d: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(d.timeIntervalSince1970) }
        var lines: [String]?
        var entryIndex: [UUID: Int] = items.count > 1 ? Dictionary(uniqueKeysWithValues: next.entries.enumerated().map { ($0.element.id, $0.offset) }) : [:]
        let needsReferences = items.contains { item in
            switch item { case .setNature, .pairTransfer, .markDuplicate: return true; default: return false }
        }
        var referenced = needsReferences ? Set(next.entries.lazy.filter { $0.deletedAt == nil }.compactMap(\.relatedEntryID)) : []
        let merged = needsReferences ? Set(next.entries.lazy.filter { $0.deletedAt == nil }.compactMap(\.mergedIntoID)) : []
        let stamp = source + "：" + reason
        func active(_ id: UUID) -> Int? {
            guard let i = entryIndex[id] ?? next.entries.firstIndex(where: { $0.id == id }), next.entries[i].deletedAt == nil else { return nil }
            entryIndex[id] = i; return i
        }
        func touch(_ index: Int) { next.entries[index].classificationReason = stamp; next.entries[index].userEdited = true }
        func skip(_ index: Int) {
            if lines == nil { lines = preview(in: ledger) }
            skipped.append("已跳过：" + lines![index] + "（记录已移除、已关联或已处理）")
        }
        for (position, item) in items.enumerated() {
            switch item {
            case .setCategory(let id, let rawCategory):
                guard let i = active(id) else { skip(position); continue }
                guard !rawCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rawCategory.count <= 200 else { throw YubaiError.invalid("分类不能为空或过长。") }
                let assignment = CategoryMapping.match(rawCategory, in: next, income: next.entries[i].nature.categoryIncome) ?? next.categoryAssignment(category: rawCategory, income: next.entries[i].nature.categoryIncome)
                let category = assignment.category
                guard Classification.isPending(category) || next.categories.contains(where: { $0.name == category && $0.income == next.entries[i].nature.categoryIncome && !$0.system }) else { throw YubaiError.invalid("请选择已有分类。") }
                if source == "导入整理", !Classification.isPending(next.entries[i]), next.resolveCategory(next.entries[i].category, income: next.entries[i].nature.categoryIncome) != category { skip(position); continue }
                guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, category.count <= 200 else { throw YubaiError.invalid("分类不能为空或过长。") }
                guard next.entries[i].nature != .refund || next.entries[i].relatedEntryID == nil else { skip(position); continue }
                if next.entries[i].category == category {
                    // Legacy pending rows can already carry “其他支出”. An explicit
                    // confirmation must clear their pending classification marker.
                    if Classification.isPending(next.entries[i]) { touch(i) }
                    else { skip(position) }
                    if source != "导入整理" { CategoryMemory.remember(next.entries[i], includingParty: ["按商户整理", "按对方分"].contains(source), in: &next) }
                    continue
                }
                next.entries[i].category = category; next.entries[i].subcategory = assignment.subcategory; next.entries[i].subcategoryUserEdited = false
                SubcategoryClassifier.classify(&next.entries[i], ledger: ledger)
                touch(i)
                if source != "导入整理" { CategoryMemory.remember(next.entries[i], includingParty: ["按商户整理", "按对方分"].contains(source), in: &next) }
                if next.entries[i].nature == .expense { changedExpenseCategories[id] = category }
            case .setNature(let id, let nature, let other):
                guard let i = active(id) else { skip(position); continue }
                let e = next.entries[i]
                if e.nature == nature && e.otherAccountID == other { skip(position); continue }
                guard e.planID == nil, e.rentID == nil, e.relatedEntryID == nil, e.otherAccountID == nil,
                      !referenced.contains(id), !merged.contains(id) else { skip(position); continue }
                guard nature.inflow == e.nature.inflow || (nature == .transfer && other != nil) else { throw YubaiError.invalid("整理性质不能改变原始资金流向。") }
                next.entries[i].nature = nature; next.entries[i].otherAccountID = other
                // Transfer is stored from its outgoing account. An imported
                // incoming leg keeps its original account's positive delta.
                if nature == .transfer, e.nature.inflow, let other {
                    next.entries[i].accountID = other; next.entries[i].otherAccountID = e.accountID
                    next.entries[i].otherDate = e.date
                    incomingTransfers.insert(id)
                }
                next.entries[i].personalExpense = nil; touch(i)
            case .setPurpose(let id, let text):
                guard let i = active(id) else { skip(position); continue }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4000 else { throw YubaiError.invalid("用途不能为空或超过 4000 字。") }
                if next.entries[i].purpose == text { skip(position); continue }
                next.entries[i].purpose = text; touch(i)
            case .pairTransfer(let a, let b, let nature):
                guard let ai = active(a), let bi = active(b) else { skip(position); continue }
                guard next.entries[ai].otherAccountID == nil, next.entries[bi].otherAccountID == nil,
                      next.entries[ai].planID == nil, next.entries[bi].planID == nil,
                      next.entries[ai].rentID == nil, next.entries[bi].rentID == nil,
                      next.entries[ai].relatedEntryID == nil, next.entries[bi].relatedEntryID == nil,
                      !referenced.contains(a), !referenced.contains(b) else { skip(position); continue }
                _ = try LedgerOperations.mergeTransfer(a, b, nature: nature, in: &next, now: createdAt)
                touch(ai); touch(bi)
            case .linkRefund(let refund, let original):
                guard let i = active(refund), let j = active(original) else { skip(position); continue }
                guard next.entries[i].relatedEntryID == nil, next.entries[i].planID == nil,
                      next.entries[i].rentID == nil, next.entries[i].otherAccountID == nil else { skip(position); continue }
                guard refund != original, next.entries[i].nature.inflow, next.entries[j].nature == .expense else { throw YubaiError.invalid("退款需要关联不同的原始支出，且不能改变资金流向。") }
                next.entries[i].nature = .refund; next.entries[i].relatedEntryID = original
                referenced.insert(original)
                next.entries[i].category = next.entries[j].category; next.entries[i].subcategory = next.entries[j].subcategory
                var refundEntry = next.entries[i]; LedgerOperations.recordPersonalShare(&refundEntry, ledger: next)
                next.entries[i] = refundEntry; touch(i); touch(j)
            case .linkPlan(let id, let plan, let occurrence):
                guard validDate(occurrence) else { throw YubaiError.invalid("安排发生日无效。") }
                guard let i = active(id), let p = next.plans.first(where: { $0.id == plan }) else { skip(position); continue }
                guard next.entries[i].planID == nil, next.entries[i].rentID == nil, next.entries[i].relatedEntryID == nil else { skip(position); continue }
                guard next.entries[i].nature == p.nature, p.accountID == nil || p.accountID == next.entries[i].accountID else { throw YubaiError.invalid("记录性质或账户与资金安排不符。") }
                guard p.occurrenceIndex(on: occurrence) != nil, !p.isSkipped(on: occurrence) else { throw YubaiError.invalid("关联日期不是这个资金安排的有效发生日。") }
                next.entries[i].planID = plan; next.entries[i].occurrence = Dates.day(occurrence); touch(i)
            case .linkRent(let id, let rent, let period):
                guard validDate(period) else { throw YubaiError.invalid("房租月份无效。") }
                guard let i = active(id), let r = next.rents.first(where: { $0.id == rent }) else { skip(position); continue }
                guard next.entries[i].rentID == nil, next.entries[i].planID == nil, next.entries[i].relatedEntryID == nil else { skip(position); continue }
                guard next.entries[i].nature == .expense || next.entries[i].nature == .contribution,
                      r.accountID == nil || r.accountID == next.entries[i].accountID,
                      Self.month(period) >= Self.month(r.startDate),
                      r.endDate.map({ Self.month(period) <= Self.month($0) }) ?? true else { throw YubaiError.invalid("房租关联的性质、账户或月份无效。") }
                next.entries[i].rentID = rent; next.entries[i].rentPeriod = Self.month(period)
                var e = next.entries[i]; LedgerOperations.recordPersonalShare(&e, ledger: next); next.entries[i] = e; touch(i)
            case .markDuplicate(let id, let original):
                guard let i = active(id), let j = active(original) else { skip(position); continue }
                guard id != original, next.entries[i].amount == next.entries[j].amount,
                      next.entries[i].nature.inflow == next.entries[j].nature.inflow else { throw YubaiError.invalid("重复记录必须是不同的、金额与方向相同的记录。") }
                guard next.entries[i].otherAccountID == nil, next.entries[i].planID == nil,
                      next.entries[i].rentID == nil, next.entries[i].relatedEntryID == nil,
                      !referenced.contains(id) else { skip(position); continue }
                next.entries[i].deletedAt = createdAt; touch(i)
                next.entries[i].classificationReason += "；重复于 \(original.uuidString)"
            case .addPlan(let p):
                guard !next.plans.contains(where: { $0.id == p.id }) else { skip(position); continue }
                guard p.accountID == nil || next.accounts.contains(where: { $0.id == p.accountID }) else { throw YubaiError.invalid("资金安排的账户不存在。") }
                guard validDate(p.dueDate) else { throw YubaiError.invalid("资金安排的日期无效。") }
                next.plans.append(p)
            case .updatePlan(let p):
                guard let i = next.plans.firstIndex(where: { $0.id == p.id }) else { throw YubaiError.invalid("找不到要修改的安排。") }
                try FixedFlows.validateUpdate(p, replacing: next.plans[i], in: next)
                next.plans[i] = p
            case .skipOccurrence(let id, let date):
                guard validDate(date), let i = next.plans.firstIndex(where: { $0.id == id }),
                      next.plans[i].occurrenceIndex(on: date) != nil else { throw YubaiError.invalid("找不到这期固定收付。") }
                let day = Dates.day(date); let plan = next.plans[i]
                guard !plan.isSkipped(on: day), FixedFlowPayments(in: next).remaining(for: plan, on: day) > 0 else { skip(position); continue }
                next.plans[i].skippedOccurrences.append(day)
            case .endPlan(let id, let date):
                guard validDate(date) else { throw YubaiError.invalid("结束日期无效。") }
                // A not-yet-started arrangement can be cancelled without inventing
                // an end date before its original start. Keep all stored records.
                if let i = next.plans.firstIndex(where: { $0.id == id }) {
                    guard next.plans[i].active, next.plans[i].stoppedAt == nil, next.plans[i].endDate.map({ date < $0 }) ?? true else { skip(position); continue }
                    var snapshot = next.plans[i]
                    snapshot.amount = FixedFlowPayments(in: next).amount(for: snapshot)
                    if !snapshot.inflow && snapshot.nature == .expense && snapshot.frequency != .once {
                        next.stoppedSubscriptions.append(StoppedSubscription(plan: snapshot, stoppedAt: date))
                    }
                    next.plans[i].stoppedAt = date
                    if date < next.plans[i].dueDate { next.plans[i].active = false }
                    else { next.plans[i].endDate = date }
                } else if let i = next.rents.firstIndex(where: { $0.id == id }) {
                    guard next.rents[i].active, next.rents[i].endDate == nil else { skip(position); continue }
                    next.rents[i].stoppedAt = date
                    if date < next.rents[i].startDate { next.rents[i].active = false }
                    else { next.rents[i].endDate = date }
                } else { skip(position); continue }
            case .resumePlan(let id):
                if let i = next.plans.firstIndex(where: { $0.id == id }) {
                    let plan = next.plans[i]
                    guard (plan.stoppedAt ?? plan.endDate).map({ $0 <= createdAt }) ?? !plan.active else { skip(position); continue }
                    for j in next.stoppedSubscriptions.indices where next.stoppedSubscriptions[j].plan.id == id && next.stoppedSubscriptions[j].resumedAt == nil { next.stoppedSubscriptions[j].resumedAt = createdAt }
                    next.plans[i].active = true; next.plans[i].endDate = nil; next.plans[i].stoppedAt = nil
                } else if let i = next.rents.firstIndex(where: { $0.id == id }) {
                    let rent = next.rents[i]
                    guard (rent.stoppedAt ?? rent.endDate).map({ $0 <= createdAt }) ?? !rent.active else { skip(position); continue }
                    next.rents[i].active = true; next.rents[i].endDate = nil; next.rents[i].stoppedAt = nil
                } else { skip(position); continue }
            case .addRent(let r):
                guard !next.rents.contains(where: { $0.id == r.id }) else { skip(position); continue }
                guard r.accountID == nil || next.accounts.contains(where: { $0.id == r.accountID }) else { throw YubaiError.invalid("房租安排的账户不存在。") }
                guard validDate(r.startDate), validDate(r.nextDueDate), r.monthlyTotal > 0 else { throw YubaiError.invalid("房租的日期或金额无效。") }
                next.rents.append(r)
            case .addEntry(let draft):
                guard !next.entries.contains(where: { $0.id == draft.id }) else { skip(position); continue }
                let e = try addedEntry(draft, in: next)
                entryIndex[e.id] = next.entries.count
                next.entries.append(e)
                if source == "手动" || draft.categoryUserEdited == true { CategoryMemory.remember(e, in: &next) }
            case .profile(let change):
                switch change {
                case .upsertArea(let area, let stance):
                    next.profile.generous.removeAll { $0.id == area.id }; next.profile.restrain.removeAll { $0.id == area.id }
                    if stance == .generous { next.profile.generous.append(area) } else { next.profile.restrain.append(area) }
                case .removeArea(let id):
                    guard (next.profile.generous + next.profile.restrain).contains(where: { $0.id == id }) else { skip(position); continue }
                    next.profile.generous.removeAll { $0.id == id }; next.profile.restrain.removeAll { $0.id == id }
                case .addPrinciple(let text):
                    guard !next.profile.principles.contains(text) else { skip(position); continue }; next.profile.principles.append(text)
                case .editPrinciple(let old, let new):
                    guard let i = next.profile.principles.firstIndex(of: old) else { skip(position); continue }; next.profile.principles[i] = new
                case .removePrinciple(let text):
                    guard next.profile.principles.contains(text) else { skip(position); continue }; next.profile.principles.removeAll { $0 == text }
                case .setFloorAmount(let amount):
                    guard amount.map({ (0...Money.limit).contains($0) }) ?? true else { throw YubaiError.invalid("存着不动的金额无效。") }
                    next.setFixedSavingsTotal(amount ?? 0, now: createdAt); next.profile.floorAmount = amount
                }
                next.profile.stamp(changedFrom: ledger.profile, at: createdAt)
                next.profile.updatedAt = createdAt
            }
        }
        for i in next.entries.indices where next.entries[i].nature == .refund {
            if let original = next.entries[i].relatedEntryID, let category = changedExpenseCategories[original],
               let index = entryIndex[original],
               next.entries[i].category != category || next.entries[i].subcategory != next.entries[index].subcategory {
                next.entries[i].category = category; next.entries[i].subcategory = next.entries[index].subcategory; touch(i)
            }
        }
        // Operations preserve existing entry order and only append new rows.
        // Compare by position, avoiding another full Entry dictionary.
        for i in ledger.entries.indices {
            let old = ledger.entries[i]
            if old != next.entries[i] {
                let entry = next.entries[i]
                // A canonical incoming transfer changes the storage orientation,
                // never its original account's amount, direction or posting day.
                let sameIncomingLeg = incomingTransfers.contains(old.id) && old.nature.inflow && old.otherAccountID == nil &&
                    entry.nature == .transfer && entry.otherAccountID == old.accountID &&
                    entry.delta(for: old.accountID) == old.delta(for: old.accountID) && entry.postingDate(for: old.accountID) == old.date
                guard old.amount == entry.amount, old.date == entry.date, old.accountID == entry.accountID || sameIncomingLeg else { throw YubaiError.invalid("不能修改已有记录的金额、账户或日期。") }
                // Includes refund categories updated as a consequence of an original's category change.
                if !next.entries[i].classificationReason.hasPrefix(stamp) { touch(i) }
            }
        }
        try next.validate(); ledger = next; return skipped
    }
    /// Shared by the apply path and the incremental keypad preview.
    func addedEntry(_ draft: EntryDraft, in next: Ledger) throws -> Entry {
        func validDate(_ d: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(d.timeIntervalSince1970) }
        let stamp = source + "：" + reason
                guard draft.amountConfirmed else { throw YubaiError.invalid("请先由用户确认补记金额。") }
                var e = Entry(date: draft.date, amount: draft.amount, nature: draft.nature, accountID: draft.accountID, title: draft.title, category: draft.category)
                e.intoFixedSavings = draft.intoFixedSavings
                e.fromReserve = draft.fromReserve
                if e.fromReserve, e.amount > next.fixedSavingsTotal(now: createdAt) { throw YubaiError.invalid("存着的钱不够。") }
                e.partID = draft.partID; e.id = draft.id; e.subcategoryUserEdited = draft.categoryUserEdited == true; e.subcategory = draft.subcategory; e.recordedAt = createdAt; e.purpose = draft.purpose; e.otherAccountID = draft.otherAccountID
                if let id = draft.planID, let occurrence = draft.occurrence {
                    guard validDate(occurrence), let plan = next.plans.first(where: { $0.id == id }), plan.occurrenceIndex(on: occurrence) != nil,
                          !plan.isSkipped(on: occurrence) else { throw YubaiError.invalid("关联日期不是这个资金安排的有效发生日。") }
                    guard e.nature == plan.nature, plan.accountID == nil || plan.accountID == e.accountID else { throw YubaiError.invalid("记录性质或账户与资金安排不符。") }
                    e.planID = id; e.occurrence = Dates.day(occurrence)
                } else if draft.planID != nil || draft.occurrence != nil { throw YubaiError.invalid("请同时指定固定收付和发生日。") }
                e.source = source; e.classificationReason = stamp; e.userEdited = true
                SubcategoryClassifier.classify(&e, ledger: next)
        return e
    }
    private static func month(_ date: Date) -> Date { Dates.calendar.dateInterval(of: .month, for: date)?.start ?? Dates.day(date) }
}
