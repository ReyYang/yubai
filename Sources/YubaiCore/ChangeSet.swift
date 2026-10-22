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
    public var nature: Nature; public var accountID: UUID; public var title: String; public var category: String
    public var purpose: String?
    public var otherAccountID: UUID?
    public var planID: UUID?; public var occurrence: Date?
    public init(date: Date, amount: Int64, amountConfirmed: Bool = false, nature: Nature = .expense,
                accountID: UUID, title: String, category: String = "其他支出", purpose: String? = nil, planID: UUID? = nil, occurrence: Date? = nil) {
        self.date = date; self.amount = amount; self.amountConfirmed = amountConfirmed; self.nature = nature
        self.accountID = accountID; self.title = title; self.category = category; self.purpose = purpose
        self.planID = planID; self.occurrence = occurrence
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
    case addPlan(Plan), endPlan(UUID, Date), resumePlan(UUID), addRent(Rent), addEntry(EntryDraft)
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
    }
    public func preview(in ledger: Ledger, showPreviousValues: Bool = false) -> [String] {
        func entry(_ id: UUID) -> String {
            guard let e = ledger.entries.first(where: { $0.id == id }) else { return "已移除的记录" }
            let parts = Dates.calendar.dateComponents([.month, .day], from: e.date)
            return "\(parts.month ?? 1)月\(parts.day ?? 1)日 \(e.displayTitle) \(e.nature.inflow ? "+" : "−")\(Money.text(e.amount, currency: false))"
        }
        var lines = items.map { item in
            switch item {
            case .setCategory(let id, let category):
                if showPreviousValues, let original = ledger.entries.first(where: { $0.id == id }) {
                    return entry(id) + " · " + original.category + " → " + category
                }
                return "把 \(entry(id)) 归为 \(category)"
            case .setNature(let id, let nature, let other):
                if showPreviousValues, let original = ledger.entries.first(where: { $0.id == id }) {
                    return entry(id) + " · " + original.nature.label + " → " + nature.label + (other.map { "，关联" + ledger.accountName($0) } ?? "")
                }
                return "把 \(entry(id)) 标为 \(nature.label)" + (other.map { "，关联\(ledger.accountName($0))" } ?? "")
            case .setPurpose(let id, let text):
                if showPreviousValues, let original = ledger.entries.first(where: { $0.id == id }) {
                    return entry(id) + " · 「" + (original.purpose ?? original.title) + "」 → 「" + text + "」"
                }
                return "把 \(entry(id)) 的用途记为「\(text)」"
            case .pairTransfer(let a, let b, let nature): return "把 \(entry(a)) 与 \(entry(b)) 配对为\(nature.label)"
            case .linkRefund(let refund, let original): return "把 \(entry(refund)) 关联为 \(entry(original)) 的退款"
            case .linkPlan(let id, let plan, let date): return "把 \(entry(id)) 关联为 \(Dates.text(date)) \(ledger.plans.first { $0.id == plan }?.title ?? "资金安排")"
            case .linkRent(let id, let rent, let date): return "把 \(entry(id)) 关联为 \(Dates.calendar.component(.month, from: date)) 月\(ledger.rents.first { $0.id == rent }?.title ?? "房租")\(ledger.entries.first { $0.id == id }?.nature.inflow == true ? "分摊" : "付款")"
            case .markDuplicate(let id, let original): return "把 \(entry(id)) 作为 \(entry(original)) 的重复记录标为已删除"
            case .addPlan(let p): return "新增\(p.frequency.label)\(p.nature.label)安排「\(p.title)」\(Money.text(p.amount))，从 \(Dates.text(p.dueDate)) 开始" + (p.accountID.map { "，使用\(ledger.accountName($0))" } ?? "")
            case .endPlan(let id, let date): return "将「\(ledger.plans.first { $0.id == id }?.title ?? ledger.rents.first { $0.id == id }?.title ?? "资金安排")」在 \(Dates.text(date)) 之后的安排结束，已到期付款保留"
            case .resumePlan(let id): return "恢复「\(ledger.plans.first { $0.id == id }?.title ?? ledger.rents.first { $0.id == id }?.title ?? "资金安排")」"
            case .addRent(let r): return "新增「\(r.title)」，月租 \(Money.text(r.monthlyTotal))，个人承担 \(Money.text(r.personalShare))，每 \(r.monthsPerPayment) 月支付，从 \(Dates.text(r.startDate)) 起，首付 \(Dates.text(r.nextDueDate))，每月 \(r.receiveDay) 日收分摊" + (r.accountID.map { "，使用\(ledger.accountName($0))" } ?? "")
            case .addEntry(let d):
                let link = d.planID.flatMap { id in d.occurrence.map { "，关联为 \(Dates.text($0)) \(ledger.plans.first { $0.id == id }?.title ?? d.title)" } } ?? ""
                return "新增 \(Dates.text(d.date)) \(d.purpose ?? d.title) \(Money.text(d.amount))（\(d.nature.label)，\(ledger.accountName(d.accountID))，\(d.amountConfirmed ? "金额已确认" : "金额待确认")）" + link
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
                case .setFloorAmount(let amount): return amount.map { "将始终留着设为 \(Money.text($0))" } ?? "清除始终留着的金额"
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
        var next = ledger; var skipped: [String] = []
        var changedExpenseCategories: [UUID: String] = [:]
        func validDate(_ d: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(d.timeIntervalSince1970) }
        let lines = preview(in: ledger)
        let stamp = source + "：" + reason
        func active(_ id: UUID) -> Int? { next.entries.firstIndex { $0.id == id && $0.deletedAt == nil } }
        func touch(_ index: Int) { next.entries[index].classificationReason = stamp; next.entries[index].userEdited = true }
        func skip(_ index: Int) { skipped.append("已跳过：" + lines[index] + "（记录已移除、已关联或已处理）") }
        for (position, item) in items.enumerated() {
            switch item {
            case .setCategory(let id, let category):
                guard let i = active(id) else { skip(position); continue }
                guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, category.count <= 200 else { throw YubaiError.invalid("分类不能为空或过长。") }
                guard next.entries[i].nature != .refund || next.entries[i].relatedEntryID == nil else { skip(position); continue }
                if source != "导入整理" {
                    var confirmed = next.entries[i]; confirmed.category = category
                    CategoryMemory.remember(confirmed, in: &next)
                }
                if next.entries[i].category == category { skip(position); continue }
                next.entries[i].category = category; touch(i)
                if next.entries[i].nature == .expense { changedExpenseCategories[id] = category }
            case .setNature(let id, let nature, let other):
                guard let i = active(id) else { skip(position); continue }
                let e = next.entries[i]
                if e.nature == nature && e.otherAccountID == other { skip(position); continue }
                guard e.planID == nil, e.rentID == nil, e.relatedEntryID == nil, e.otherAccountID == nil,
                      !next.activeEntries.contains(where: { $0.relatedEntryID == id || $0.mergedIntoID == id }) else { skip(position); continue }
                guard nature.inflow == e.nature.inflow else { throw YubaiError.invalid("整理性质不能改变原始资金流向。") }
                next.entries[i].nature = nature; next.entries[i].otherAccountID = other
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
                      !next.activeEntries.contains(where: { $0.relatedEntryID == a || $0.relatedEntryID == b }) else { skip(position); continue }
                _ = try LedgerOperations.mergeTransfer(a, b, nature: nature, in: &next, now: createdAt)
                touch(ai); touch(bi)
            case .linkRefund(let refund, let original):
                guard let i = active(refund), let j = active(original) else { skip(position); continue }
                guard next.entries[i].relatedEntryID == nil, next.entries[i].planID == nil,
                      next.entries[i].rentID == nil, next.entries[i].otherAccountID == nil else { skip(position); continue }
                guard refund != original, next.entries[i].nature.inflow, next.entries[j].nature == .expense else { throw YubaiError.invalid("退款需要关联不同的原始支出，且不能改变资金流向。") }
                next.entries[i].nature = .refund; next.entries[i].relatedEntryID = original
                next.entries[i].category = next.entries[j].category
                var refundEntry = next.entries[i]; LedgerOperations.recordPersonalShare(&refundEntry, ledger: next)
                next.entries[i] = refundEntry; touch(i); touch(j)
            case .linkPlan(let id, let plan, let occurrence):
                guard validDate(occurrence) else { throw YubaiError.invalid("安排发生日无效。") }
                guard let i = active(id), let p = next.plans.first(where: { $0.id == plan }) else { skip(position); continue }
                guard next.entries[i].planID == nil, next.entries[i].rentID == nil, next.entries[i].relatedEntryID == nil else { skip(position); continue }
                guard next.entries[i].nature == p.nature, p.accountID == nil || p.accountID == next.entries[i].accountID else { throw YubaiError.invalid("记录性质或账户与资金安排不符。") }
                guard p.occurrenceIndex(on: occurrence) != nil else { throw YubaiError.invalid("关联日期不是这个资金安排的有效发生日。") }
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
                      !next.activeEntries.contains(where: { $0.relatedEntryID == id }) else { skip(position); continue }
                next.entries[i].deletedAt = createdAt; touch(i)
                next.entries[i].classificationReason += "；重复于 \(original.uuidString)"
            case .addPlan(let p):
                guard !next.plans.contains(where: { $0.id == p.id }) else { skip(position); continue }
                guard p.accountID == nil || next.accounts.contains(where: { $0.id == p.accountID }) else { throw YubaiError.invalid("资金安排的账户不存在。") }
                guard validDate(p.dueDate) else { throw YubaiError.invalid("资金安排的日期无效。") }
                next.plans.append(p)
            case .endPlan(let id, let date):
                guard validDate(date) else { throw YubaiError.invalid("结束日期无效。") }
                // A not-yet-started arrangement can be cancelled without inventing
                // an end date before its original start. Keep all stored records.
                if let i = next.plans.firstIndex(where: { $0.id == id }) {
                    guard next.plans[i].active, next.plans[i].endDate == nil else { skip(position); continue }
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
                guard draft.amountConfirmed else { throw YubaiError.invalid("请先由用户确认补记金额。") }
                var e = Entry(date: draft.date, amount: draft.amount, nature: draft.nature, accountID: draft.accountID, title: draft.title, category: draft.category)
                e.id = draft.id; e.recordedAt = createdAt; e.purpose = draft.purpose; e.otherAccountID = draft.otherAccountID
                if let id = draft.planID, let occurrence = draft.occurrence {
                    guard validDate(occurrence), let plan = next.plans.first(where: { $0.id == id }), plan.occurrenceIndex(on: occurrence) != nil else { throw YubaiError.invalid("关联日期不是这个资金安排的有效发生日。") }
                    guard e.nature == plan.nature, plan.accountID == nil || plan.accountID == e.accountID else { throw YubaiError.invalid("记录性质或账户与资金安排不符。") }
                    e.planID = id; e.occurrence = Dates.day(occurrence)
                } else if draft.planID != nil || draft.occurrence != nil { throw YubaiError.invalid("请同时指定固定收付和发生日。") }
                e.source = source; e.classificationReason = stamp; e.userEdited = true
                next.entries.append(e)
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
                case .setFloorAmount(let amount): next.profile.floorAmount = amount
                }
                next.profile.stamp(changedFrom: ledger.profile, at: createdAt)
                next.profile.updatedAt = createdAt
            }
        }
        for i in next.entries.indices where next.entries[i].nature == .refund {
            if let original = next.entries[i].relatedEntryID, let category = changedExpenseCategories[original],
               next.entries[i].category != category { next.entries[i].category = category; touch(i) }
        }
        let originals = Dictionary(uniqueKeysWithValues: ledger.entries.map { ($0.id, $0) })
        for i in next.entries.indices {
            if let old = originals[next.entries[i].id], old != next.entries[i] {
                guard old.amount == next.entries[i].amount, old.accountID == next.entries[i].accountID, old.date == next.entries[i].date else { throw YubaiError.invalid("不能修改已有记录的金额、账户或日期。") }
                // Includes refund categories updated as a consequence of an original's category change.
                if !next.entries[i].classificationReason.hasPrefix(stamp) { touch(i) }
            }
        }
        try next.validate(); ledger = next; return skipped
    }
    private static func month(_ date: Date) -> Date { Dates.calendar.dateInterval(of: .month, for: date)?.start ?? Dates.day(date) }
}
