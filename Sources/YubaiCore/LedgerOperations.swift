import Foundation

public enum LedgerOperations {
    /// Keep stored refund categories aligned with their original expenses.
    public static func syncLinkedRefundCategories(in ledger: inout Ledger, expenseIDs: Set<UUID>? = nil) {
        let expenses = Dictionary(uniqueKeysWithValues: ledger.entries.filter { $0.nature == .expense }.map { ($0.id, $0) })
        for i in ledger.entries.indices where ledger.entries[i].nature == .refund {
            guard let id = ledger.entries[i].relatedEntryID, expenseIDs?.contains(id) ?? true, let original = expenses[id] else { continue }
            ledger.entries[i].category = original.category; ledger.entries[i].subcategory = original.subcategory
        }
    }
    public static func bulkEdit(_ ids: Set<UUID>, category: String?, nature: Nature?, in ledger: inout Ledger) throws {
        guard category != nil || nature != nil else { throw YubaiError.invalid("请选择要修改的分类或性质。") }
        var candidate = ledger
        for i in candidate.entries.indices where ids.contains(candidate.entries[i].id) {
            let e = candidate.entries[i]
            guard e.deletedAt == nil else { throw YubaiError.invalid("请先恢复记录，再批量整理。") }
            if let nature, nature != e.nature {
                guard !nature.paired, !e.nature.paired, e.otherAccountID == nil, e.planID == nil, e.rentID == nil, e.relatedEntryID == nil else { throw YubaiError.invalid("选中记录含已关联的资金移动、退款或安排，请在详情中逐笔核对性质。分类仍可批量修改。") }
                guard nature.inflow == e.nature.inflow else { throw YubaiError.invalid("批量整理不能改变资金流向。请分别选择流入或流出记录。") }
                candidate.entries[i].nature = nature
                candidate.entries[i].personalExpense = nil
            }
            if let category, category != candidate.entries[i].category {
                candidate.entries[i].category = category; candidate.entries[i].subcategory = nil; candidate.entries[i].subcategoryUserEdited = false
                SubcategoryClassifier.classify(&candidate.entries[i], ledger: ledger)
            }
            candidate.entries[i].userEdited = true; candidate.entries[i].classificationReason = "用户批量纠正"
        }
        syncLinkedRefundCategories(in: &candidate)
        if category != nil {
            for entry in candidate.activeEntries where ids.contains(entry.id) { CategoryMemory.remember(entry, in: &candidate) }
        }
        try candidate.validate(); ledger = candidate
    }
    @discardableResult public static func mergeTransfer(_ first: UUID, _ second: UUID, nature: Nature = .transfer, in ledger: inout Ledger, now: Date = Date()) throws -> UUID {
        guard first != second, let a = ledger.entries.first(where: { $0.id == first && $0.deletedAt == nil }),
              let b = ledger.entries.first(where: { $0.id == second && $0.deletedAt == nil }),
              a.amount == b.amount, a.nature.inflow != b.nature.inflow, a.accountID != b.accountID,
              a.otherAccountID == nil, b.otherAccountID == nil, a.rentID == nil, b.rentID == nil,
              a.planID == nil, b.planID == nil, nature.paired else { throw YubaiError.invalid("只能关联两个不同账户、金额相同、方向相反且尚未关联安排的记录。") }
        let incoming = a.nature.inflow ? a : b; let outgoing = a.nature.inflow ? b : a
        var primary = nature.inflow ? incoming : outgoing
        let evidence = nature.inflow ? outgoing : incoming
        primary.nature = nature; primary.otherAccountID = evidence.accountID; primary.otherDate = evidence.date
        primary.category = "内部移动"; primary.userEdited = true; primary.classificationReason = "用户关联两侧记录，保留原始来源"
        let primaryIndex = ledger.entries.firstIndex { $0.id == primary.id }!
        let evidenceIndex = ledger.entries.firstIndex { $0.id == evidence.id }!
        ledger.entries[primaryIndex] = primary; ledger.entries[evidenceIndex].deletedAt = now; ledger.entries[evidenceIndex].mergedIntoID = primary.id
        try ledger.validate(); return primary.id
    }
    public static func recordPersonalShare(_ entry: inout Entry, ledger: Ledger) {
        if entry.nature == .refund, let original = ledger.entries.first(where: { $0.id == entry.relatedEntryID }), let personal = original.personalExpense {
            entry.personalExpense = NSDecimalNumber(decimal: Decimal(entry.amount) * Decimal(personal) / Decimal(original.amount)).int64Value; return
        }
        guard entry.nature == .expense, let id = entry.rentID, let rent = ledger.rents.first(where: { $0.id == id }) else { entry.personalExpense = nil; return }
        entry.personalExpense = NSDecimalNumber(decimal: Decimal(entry.amount) * Decimal(rent.personalShare) / Decimal(rent.monthlyTotal)).int64Value
    }
}
