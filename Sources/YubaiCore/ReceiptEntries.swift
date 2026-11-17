import Foundation

public enum ReceiptEntryMode: String, Equatable, Sendable { case separate, merged }
extension ReceiptTextParser {
    /// Pass only checked lines. Empty selection returns no drafts.
    public static func entryDrafts(from lines: [Draft], shopName: String, mode: ReceiptEntryMode, in ledger: Ledger, accountID: UUID) throws -> [EntryDraft] {
        guard ledger.accounts.contains(where: { $0.id == accountID }), lines.allSatisfy({ (1...Money.limit).contains($0.amount) && (-2_208_988_800...7_258_118_400).contains($0.date.timeIntervalSince1970) }) else {
            throw YubaiError.invalid("请核对金额和日期。")
        }
        guard let first = lines.first else { return [] }
        if mode == .separate { return lines.map { $0.entryDraft(in: ledger, accountID: accountID) } }
        let shop = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shop.isEmpty, shop.count <= 4000,
              lines.allSatisfy({ $0.nature == first.nature && Dates.day($0.date) == Dates.day(first.date) }) else {
            throw YubaiError.invalid("请核对金额和日期。")
        }
        var total: Int64 = 0
        for line in lines {
            guard total <= Money.limit - line.amount else { throw YubaiError.invalid("金额超出范围。") }
            total += line.amount
        }
        let choice = CategoryGuesser.guess(shop, nature: first.nature, date: first.date, in: ledger)
        return [EntryDraft(date: first.date, amount: total, amountConfirmed: true, nature: first.nature, accountID: accountID,
                           title: shop, category: choice?.category ?? Classification.pendingCategory, subcategory: choice?.subcategory, purpose: shop)]
    }
}
