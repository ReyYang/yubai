import Foundation

public struct QuickCapturePreferences: Codable, Equatable, Sendable {
    public var cardAccounts: [String: UUID] = [:]
    // Decode-only legacy payload, consumed and cleared by Ledger.init(from:).
    var merchantCategories: [String: String] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case cardAccounts, merchantCategories }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardAccounts = try c.decodeIfPresent([String: UUID].self, forKey: .cardAccounts) ?? [:]
        merchantCategories = try c.decodeIfPresent([String: String].self, forKey: .merchantCategories) ?? [:]
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cardAccounts, forKey: .cardAccounts)
    }
}
public struct QuickCaptureOrigin: Codable, Equatable, Sendable {
    public var merchant: String?; public var card: String?; public var transactionDate: Date?; public var withoutOpeningApp: Bool
    public init(merchant: String? = nil, card: String? = nil, transactionDate: Date? = nil, withoutOpeningApp: Bool) {
        self.merchant = merchant; self.card = card; self.transactionDate = transactionDate; self.withoutOpeningApp = withoutOpeningApp
    }
}
public enum QuickCaptureResult: Equatable, Sendable {
    case needsFollowUp
    case drafts([EntryDraft])
}
public struct QuickCaptureSnapshot: Codable, Equatable, Sendable {
    public struct Frequent: Codable, Equatable, Sendable {
        public var purpose: String; public var amount: Int64; public var category: String
    }
    public var generatedAt: Date; public var available: Int64; public var todayCount: Int; public var todayTotal: Int64
    public var frequent: [Frequent]
    public init(ledger: Ledger, now: Date = Date()) {
        generatedAt = now; available = QuickCapture.available(in: ledger, now: now)
        let entries = ledger.activeEntries.filter { $0.date <= now }
        let today = entries.filter { Dates.calendar.isDate($0.date, inSameDayAs: now) }
        todayCount = today.count
        todayTotal = today.reduce(0) { $0 + ($1.nature.inflow ? -$1.amount : $1.amount) }
        // 同一用途、金额和分类算一项；频次相同时优先最近记过的。
        let groups = Dictionary(grouping: entries.filter { $0.nature == .expense }) {
            FrequentKey(purpose: $0.displayTitle, amount: $0.amount, category: $0.category)
        }
        frequent = groups.keys.sorted {
            let a = groups[$0]!, b = groups[$1]!
            if a.count != b.count { return a.count > b.count }
            let ad = a.map(\.date).max()!, bd = b.map(\.date).max()!
            if ad != bd { return ad > bd }
            return $0.purpose + $0.category + String($0.amount) < $1.purpose + $1.category + String($1.amount)
        }.prefix(3).map { Frequent(purpose: $0.purpose, amount: $0.amount, category: $0.category) }
    }
    private struct FrequentKey: Hashable { var purpose: String; var amount: Int64; var category: String }
}

public enum QuickCapture {
    public static func parse(_ text: String, in ledger: Ledger, now: Date = Date()) throws -> QuickCaptureResult {
        let amounts = EntryAmountParser.entries(in: text)
        guard !amounts.isEmpty else { return .needsFollowUp }
        guard let account = ManualBookkeeping.defaultAccount(in: ledger) else { throw YubaiError.invalid("请先添加账户。") }
        return .drafts(amounts.map { item in
            var purpose = item.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            // 金额解析仍只使用 EntryAmountParser；这里仅清理连接词。
            while let first = purpose.first, "和与及".contains(first) { purpose.removeFirst(); purpose = purpose.trimmingCharacters(in: .whitespaces) }
            let choice = CategoryGuesser.guess(purpose, nature: .expense, date: now, in: ledger)
            let category = choice?.category ?? Classification.pendingCategory
            return EntryDraft(date: now, amount: item.amount, amountConfirmed: true, accountID: account.id,
                              title: purpose.isEmpty ? Classification.displayCategory(category) : purpose, category: category, subcategory: choice?.subcategory, purpose: purpose.isEmpty ? nil : purpose)
        })
    }
    public static func available(in ledger: Ledger, now: Date = Date()) -> Int64 { Finance.funds(ledger, now: now).available }
    @discardableResult public static func record(_ drafts: [EntryDraft], in ledger: inout Ledger, source: String = "快捷指令", withoutOpeningApp: Bool = true, now: Date = Date()) throws -> [UUID] {
        guard !drafts.isEmpty else { return [] }
        var next = ledger
        var change = ChangeSet(source: source, reason: "记一笔", items: drafts.map(ChangeItem.addEntry)); change.createdAt = now
        try change.apply(to: &next)
        let ids = Set(drafts.map(\.id))
        for i in next.entries.indices where ids.contains(next.entries[i].id) {
            next.entries[i].quickCapture = QuickCaptureOrigin(withoutOpeningApp: withoutOpeningApp)
            if Classification.isPending(next.entries[i]) { next.entries[i].classificationReason = "没分类" }
        }
        try next.validate(); ledger = next; return drafts.map(\.id)
    }
    public static func applePayAmount(_ text: String) throws -> Int64 {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "CN¥", with: "¥", options: .caseInsensitive)
        guard clean.range(of: #"^[¥￥]?\s*\d+(?:,\d{3})*(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let amount = try? Money.parse(clean), amount > 0 else { throw YubaiError.invalid("请核对付款金额。") }
        return amount
    }
    @discardableResult public static func applePay(merchant: String, amount: String, card: String, date: Date,
                                                  in ledger: inout Ledger, now: Date = Date()) throws -> (entry: Entry, inserted: Bool) {
        let cents = try applePayAmount(amount)
        let merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines), card = card.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty, !card.isEmpty else { throw YubaiError.invalid("请填写商户和卡名。") }
        // 不按两分钟时间桶分组，跨桶重触发也能识别。软删除仍保留去重凭据。
        let identity = "apple-pay:" + LedgerCodec.checksum(try JSONEncoder().encode([cardKey(card), cardKey(merchant), String(cents)]))
        if let duplicate = ledger.entries.first(where: { $0.source == "Apple Pay" && $0.sourceIdentity == identity && abs(($0.quickCapture?.transactionDate ?? $0.date).timeIntervalSince(date)) <= 120 }) { return (duplicate, false) }
        let mapped = ledger.preferences.quickCapture.cardAccounts.first { cardKey($0.key) == cardKey(card) }?.value
        let account = mapped.flatMap { id in ledger.accounts.first { $0.id == id && !$0.archived } } ?? ManualBookkeeping.defaultAccount(in: ledger)
        guard let account else { throw YubaiError.invalid("请先添加账户。") }
        let rule = ledger.classificationMemory[key(merchant)]
        let choice = CategoryGuesser.guess(merchant, nature: .expense, date: date, in: ledger)
        let category = choice?.category
        var entry = Entry(date: date, amount: cents, accountID: account.id, title: merchant, category: category ?? Classification.pendingCategory)
        entry.subcategory = choice?.subcategory
        entry.purpose = merchant; entry.recordedAt = now; entry.source = "Apple Pay"; entry.sourceIdentity = identity
        entry.externalID = identity + ":" + String(date.timeIntervalSince1970)
        entry.classificationReason = category == nil ? "没分类" : (rule == nil ? "本机分类" : "商户分类")
        entry.quickCapture = QuickCaptureOrigin(merchant: merchant, card: card, transactionDate: date, withoutOpeningApp: true)
        var next = ledger; next.entries.append(entry); try next.validate(); ledger = next; return (entry, true)
    }
    public static func undo(entryID: UUID, in ledger: inout Ledger, now: Date = Date()) {
        guard let index = ledger.entries.firstIndex(where: { $0.id == entryID && $0.deletedAt == nil }) else { return }
        ledger.entries[index].deletedAt = now
    }
    public static func remember(merchant: String, category: String, in ledger: inout Ledger) throws {
        let merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines), category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty, !category.isEmpty else { throw YubaiError.invalid("请填写商户和分类。") }
        let normalized = key(merchant)
        let choice = CategoryMapping.match(category, in: ledger) ?? ledger.categoryAssignment(category: category)
        guard !normalized.isEmpty, ledger.selectableCategories.contains(where: { $0.name == choice.category }) else { throw YubaiError.invalid("请选择已有分类。") }
        ledger.classificationMemory[normalized] = choice.path
    }
    public static func key(_ text: String) -> String { CategoryMemory.key(text) }
    public static func cardKey(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
extension Entry { public var hasNoCaptureCategory: Bool { Classification.isPending(self) } }

/// Vision 只提供文字行；金额、用途与日期的启发式在这里共用，导入与截图记保持一致。
public enum ReceiptTextParser {
    public struct Draft: Equatable, Sendable {
        public var date: Date; public var amount: Int64; public var title: String; public var nature: Nature
        public var dateNeedsReview: Bool; public var directionNeedsReview: Bool
        public func entryDraft(in ledger: Ledger, accountID: UUID) -> EntryDraft {
            let choice = CategoryGuesser.guess(title, nature: nature, date: date, in: ledger)
            return EntryDraft(date: date, amount: amount, amountConfirmed: true, nature: nature, accountID: accountID,
                       title: title, category: choice?.category ?? Classification.pendingCategory, subcategory: choice?.subcategory, purpose: title)
        }
    }
    public static func drafts(lines: [String], now: Date = Date()) -> [Draft] {
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let payment = lines.contains { ["支付成功", "付款成功", "交易成功"].contains($0) }
        let ignored = ["余额", "合计", "总计", "优惠", "原价", "手续费", "单号", "订单", "卡号", "实付前"]
        let meta = ["支付", "付款", "微信", "支付宝", "交易", "账单", "金额", "详情", "服务", "时间", "收款方", "商户", "收入", "支出", "今天", "昨天"]
        func title(_ text: String) -> String? {
            var clean = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            for prefix in ["收款方", "商户名称", "商户", "用途", "付款给"] where clean.hasPrefix(prefix) {
                clean = String(clean.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            for suffix in ["收入", "支出"] where clean.hasSuffix(suffix) { clean = String(clean.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces) }
            guard clean.count >= 2, clean.count < 60, clean.rangeOfCharacter(from: .decimalDigits) == nil,
                  !meta.contains(where: { clean == $0 || clean == $0 + "成功" || clean == $0 + "金额" || clean == $0 + "方式" }), !ignored.contains(where: clean.contains),
                  !["返回", "完成", "收支", "全部", "支付方式", "付款方式"].contains(clean) else { return nil }
            return clean
        }
        let regex = try! NSRegularExpression(pattern: #"(?:[¥￥]\s*[−\-+]?\d[\d,]*(?:\.\d{1,2})?|[−\-+]\s*\d[\d,]*(?:\.\d{1,2})?|(?<![\d.:])\d[\d,]*\.\d{2})(?![\d.:])"#)
        let datePattern = #"\d{4}[-/]\d{1,2}[-/]\d{1,2}(?: \d{1,2}:\d{2}(?::\d{2})?)?"#
        let dates = try! NSRegularExpression(pattern: datePattern)
        func inlineDate(_ line: String) -> Date? {
            guard let match = dates.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), let range = Range(match.range, in: line) else { return nil }
            return Dates.parse(String(line[range]))
        }
        var result: [Draft] = []; var currentDate = lines.compactMap { Dates.parse($0) ?? inlineDate($0) }.first
        for (index, original) in lines.enumerated() {
            if let date = Dates.parse(original) { currentDate = date; continue }
            if let date = inlineDate(original) { currentDate = date }
            if ignored.contains(where: original.contains) { continue }
            var line = original.replacingOccurrences(of: datePattern, with: " ", options: .regularExpression)
            // 时间、日期和长标识都不能变成金额。
            for pattern in [#"\d{1,2}:\d{2}(?::\d{2})?"#, #"\d{8,}"#, #"\d{1,2}月\d{1,2}日?"#] {
                line = line.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let range = Range(match.range, in: line) else { continue }
                let raw = String(line[range]).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "+", with: "")
                guard let amount = try? Money.parse(raw, allowNegative: true), amount != 0 else { continue }
                let remaining = line.replacingCharacters(in: range, with: "")
                let adjacent = [index - 1, index + 1, index - 2, index + 2].filter { lines.indices.contains($0) }.compactMap { title(lines[$0]) }.first
                let purpose = title(remaining) ?? adjacent ?? "截图补记"
                let income = line.contains("收入") || line.contains("收款") || line.contains("+")
                let expense = payment || line.contains("支出") || line.contains("付款") || line.contains("支付") || line.contains("-") || line.contains("−")
                result.append(Draft(date: currentDate ?? now, amount: abs(amount), title: purpose, nature: income ? .income : .expense,
                                    dateNeedsReview: currentDate == nil, directionNeedsReview: !income && !expense))
                if payment { return result }
            }
        }
        return result
    }
    public static func table(lines: [String], now: Date = Date()) throws -> Data {
        let drafts = drafts(lines: lines, now: now)
        guard !drafts.isEmpty else { throw YubaiError.invalid("没认出金额") }
        var rows = ["日期,金额,收支,用途,备注"]
        for draft in drafts {
            let purpose = draft.title.replacingOccurrences(of: "\"", with: "\"\"")
            let note = (draft.dateNeedsReview ? "日期待核对 " : "") + (draft.directionNeedsReview ? "收支待核对" : "")
            rows.append("\(Dates.text(draft.date, time: true)),\(Money.input(draft.amount)),\(draft.nature.inflow ? "收入" : "支出"),\"\(purpose)\",\(note)")
        }
        return Data(rows.joined(separator: "\n").utf8)
    }
}
