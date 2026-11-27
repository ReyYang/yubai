import Foundation

/// Words and numbers on 问余白 cards. Everything here is computed from the ledger;
/// the model only supplies the one reason line and the follow-up question.
public struct AskChange: Equatable, Sendable, Identifiable {
    public let label: String
    public let from: Int64
    public let to: Int64
    /// Set when every recorded entry is dated after today: 还能花 counts it on that
    /// day, so today's line would read the same number on both sides.
    public var deferredTo: Date? = nil
    public init(label: String, from: Int64, to: Int64, deferredTo: Date? = nil) {
        self.label = label; self.from = from; self.to = to; self.deferredTo = deferredTo
    }
    public var id: String { label }
    /// Entries dated after `now` that change nothing today.
    static func deferredDate(_ drafts: [EntryDraft], before: Int64, after: Int64, now: Date) -> Date? {
        guard !drafts.isEmpty, before == after, drafts.allSatisfy({ $0.date > now }) else { return nil }
        return drafts.map(\.date).min()
    }
    /// A budget pushed below zero reads 「超 X」.
    public var overrun: Bool { to < 0 }
    public var better: Bool { to > from }
}

public struct AskFact: Equatable, Sendable, Identifiable {
    public let key: String
    public let value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
    public var id: String { key + "|" + value }
}

public enum AskVerdictWord {
    private static let outingCategories: Set<String> = ["吃饭", "餐饮", "娱乐", "旅行", "出行"]
    private static let outingWords = ["去", "吃", "玩", "聚", "旅"]

    /// skip 先别买 · wait 建议延后 · buy 可以买, or 可以去 for an outing.
    public static func word(_ verdict: PurchaseVerdict, title: String, category: String?) -> String {
        switch verdict {
        case .skip: return "先别买"
        case .wait: return "建议延后"
        case .buy:
            let outing = category.map(outingCategories.contains) == true || outingWords.contains { title.contains($0) }
            return outing ? "可以去" : "可以买"
        }
    }
}

public struct AskPurchaseCard: Equatable, Sendable {
    public let verdict: PurchaseVerdict
    public let word: String
    /// The change line under the verdict.
    public let headline: AskChange
    /// 账上还有 N 项变化: every other line the purchase moves.
    public let changes: [AskChange]
    /// 值不值 · N 条: habit, the user's own words and earlier answers.
    public let worth: [AskFact]
    /// 「<date> 提醒我」 for 建议延后: the day the next cycle starts.
    public let remindOn: Date?

    public static func make(ledger: Ledger, title: String, amount: Int64, category: String?, subcategory: String? = nil,
                            verdict: PurchaseVerdict, daysLeft: Int, now: Date) -> AskPurchaseCard {
        let lines = changes(ledger: ledger, amount: amount, category: category, daysLeft: daysLeft, now: now)
        let part = lines.part
        let headline = verdict == .skip || part == nil ? lines.available : part!
        let all = [part, lines.available, lines.daily].compactMap { $0 }.filter { $0 != headline }
        let breakdown = Finance.spendableBreakdown(ledger, now: now)
        return AskPurchaseCard(verdict: verdict, word: AskVerdictWord.word(verdict, title: title, category: category),
                               headline: headline, changes: all,
                               worth: worth(ledger: ledger, title: title, category: category, subcategory: subcategory, now: now),
                               remindOn: verdict == .wait ? Dates.addDays(1, to: Dates.day(breakdown.cycleEnd)) : nil)
    }

    /// The budget line (when a budget covers the category), 还能花 and 每天.
    public static func changes(ledger: Ledger, amount: Int64, category: String?, daysLeft: Int, now: Date)
        -> (part: AskChange?, available: AskChange, daily: AskChange) {
        let available = Finance.funds(ledger, now: now).available
        let after = available - amount
        let days = Int64(max(1, daysLeft))
        let part = category.flatMap { name in
            HomeBudgets(in: ledger, now: now).ordered.first { $0.categories.contains(ledger.resolveCategory(name, income: false)) || $0.name == name }
        }.map { budget in AskChange(label: budget.name + "还剩", from: budget.amount - budget.spent, to: budget.amount - budget.spent - amount) }
        func perDay(_ value: Int64) -> Int64 { Int64((Double(value) / Double(days)).rounded()) }
        return (part, AskChange(label: "还能花", from: available, to: after),
                AskChange(label: "每天", from: perDay(available), to: perDay(after)))
    }

    static func worth(ledger: Ledger, title: String, category: String?, subcategory: String?, now: Date) -> [AskFact] {
        var sample = Entry(date: now, amount: 1, accountID: UUID(), title: title, category: category ?? Classification.pendingCategory)
        sample.subcategory = subcategory
        var rows: [AskFact] = []
        let start = Dates.addDays(-89, to: Dates.day(now))
        let resolved = category.map { ledger.resolveCategory($0, income: false) }
        let similar = ledger.activeEntries.filter { entry in
            entry.nature == .expense && entry.date >= start && entry.date <= now
                && (resolved.map { ledger.normalizedCategory(for: entry).category == $0 } ?? entry.displayTitle.contains(title))
        }
        if let resolved { rows.append(AskFact(key: "90 天", value: "\(Classification.displayCategory(resolved)) \(similar.count) 笔")) }
        for area in ledger.profile.restrain + ledger.profile.generous where ButlerCards.matches(area, entry: sample, ledger: ledger) && !area.note.isEmpty {
            rows.append(AskFact(key: area.title, value: "「" + area.note + "」"))
        }
        for principle in ledger.profile.principles { rows.append(AskFact(key: "原则", value: "「" + principle + "」")) }
        for wish in ledger.wishlist where wish.followUpAnswer != nil && Wishlist.similarTitles(title, wish.title) {
            rows.append(AskFact(key: wish.title, value: wish.followUpAnswer?.components(separatedBy: "：").first ?? ""))
        }
        return rows
    }
}

/// 审批卡: what an AI-proposed change will do, computed from the change set.
public struct AskApproval: Equatable, Sendable {
    public let title: String
    public let action: String
    public let change: AskChange
    public let facts: [AskFact]
    /// The entry 修改 opens: the original bill for an offset, otherwise the first touched entry.
    public let editEntryID: UUID?

    public static func make(_ proposed: ChangeSet, ledger: Ledger, now: Date) -> AskApproval {
        let change = proposed.confirmingAmounts()
        let before = Finance.funds(ledger, now: now).available
        let after = (try? ManualBookkeeping.available(after: change, in: ledger, now: now)) ?? before
        let added = change.items.compactMap { item -> EntryDraft? in if case .addEntry(let draft) = item { return draft }; return nil }
        let line = AskChange(label: "还能花", from: before, to: after,
                             deferredTo: added.count == change.items.count ? AskChange.deferredDate(added, before: before, after: after, now: now) : nil)
        let entries = Dictionary(ledger.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A refund draft linked to an existing expense: 报销 or 退款 到账.
        for case .linkRefund(let refundID, let originalID) in change.items {
            guard let original = entries[originalID],
                  let draft = change.items.lazy.compactMap({ item -> EntryDraft? in
                      if case .addEntry(let draft) = item, draft.id == refundID { return draft }; return nil }).first else { continue }
            let category = ledger.normalizedCategory(for: original).category
            let budgets = HomeBudgets(in: ledger, now: now).ordered
            var preview = ledger
            let spentAfter: Int64? = (try? change.apply(to: &preview)).flatMap { _ in
                HomeBudgets(in: preview, now: now).ordered.first { $0.categories.contains(category) }?.spent
            }
            var facts = [AskFact(key: "原账单", value: original.displayTitle + " · " + monthDay(original.date) + " · -" + Money.text(original.amount, currency: false)),
                         AskFact(key: "到账", value: ledger.accountName(draft.accountID) + " +" + Money.text(draft.amount, currency: false))]
            if let budget = budgets.first(where: { $0.categories.contains(category) }), let spentAfter {
                facts.append(AskFact(key: budget.name, value: Money.text(budget.spent, currency: false) + " → " + Money.text(spentAfter, currency: false)))
            }
            let day = ManualBookkeeping.dayLabel(original.date, now: now)
            return AskApproval(title: "把到账的 \(Money.text(draft.amount, currency: false)) 冲抵\(day)的\(original.displayTitle)",
                               action: "确认冲抵", change: line, facts: facts, editEntryID: original.id)
        }
        let touched = change.items.flatMap(\.entryIDs).compactMap { entries[$0] }
        return AskApproval(title: change.reason, action: "确认", change: line,
                           facts: touched.prefix(3).map { AskFact(key: monthDay($0.date), value: $0.displayTitle + " " + Money.text($0.amount, currency: false)) },
                           editEntryID: touched.first?.id)
    }

    static func monthDay(_ date: Date) -> String {
        let parts = Dates.calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
    }
}

extension ChangeSet {
    /// What 确认 applies: the user has now seen every proposed amount.
    public func confirmingAmounts() -> ChangeSet {
        var value = self
        value.items = items.map { item in
            guard case .addEntry(var draft) = item else { return item }
            draft.amountConfirmed = true
            return .addEntry(draft)
        }
        return value
    }
}

/// 截图批量记账: duplicates start unchecked; the total follows the checked rows.
public enum AskBatch {
    /// Same rule as the import merge: same amount and direction within a day, any account.
    public static func isLikelyDuplicate(_ draft: EntryDraft, in ledger: Ledger) -> Bool {
        ledger.activeEntries.contains { entry in
            entry.amount == draft.amount && entry.nature.inflow == draft.nature.inflow && !entry.nature.paired
                && abs(Dates.calendar.dateComponents([.day], from: Dates.day(entry.date), to: Dates.day(draft.date)).day ?? Int.max) <= 1
        }
    }

    public static func initiallyChecked(_ drafts: [EntryDraft], in ledger: Ledger) -> Set<UUID> {
        Set(drafts.filter { !isLikelyDuplicate($0, in: ledger) }.map(\.id))
    }

    /// 还能花 before and after recording the checked drafts.
    public static func total(_ drafts: [EntryDraft], checked: Set<UUID>, source: String = "问余白", in ledger: Ledger, now: Date) -> AskChange {
        let before = Finance.funds(ledger, now: now).available
        let chosen = drafts.filter { checked.contains($0.id) }
        guard !chosen.isEmpty else { return AskChange(label: "记下后还能花", from: before, to: before) }
        let items = chosen.map { draft -> ChangeItem in var value = draft; value.amountConfirmed = true; return .addEntry(value) }
        let after = (try? ManualBookkeeping.available(after: ChangeSet(source: source, reason: "记一笔", items: items), in: ledger, now: now)) ?? before
        return AskChange(label: "记下后还能花", from: before, to: after, deferredTo: AskChange.deferredDate(chosen, before: before, after: after, now: now))
    }
}

/// What code can answer without a model (the 「AI 未连接」 state).
public enum AskLocal {
    public enum Answer: Equatable, Sendable {
        case budget(HomeBudget)
        case purchase(title: String, amount: Int64, category: String?, lines: [AskChange])
        case summary([String])
    }

    public static func answer(_ question: String, in ledger: Ledger, daysLeft: Int, now: Date) -> Answer {
        if question.contains("买"), let amount = purchasePrice(in: question) {
            let title = purchaseTitle(question)
            let category = CategoryGuesser.guess(title, nature: .expense, date: now, in: ledger)?.category
            let lines = AskPurchaseCard.changes(ledger: ledger, amount: amount, category: category, daysLeft: daysLeft, now: now)
            let rows = [lines.part.map { AskChange(label: "买后" + $0.label.replacingOccurrences(of: "还剩", with: ""), from: $0.from, to: $0.to) },
                        AskChange(label: "买后还能花", from: lines.available.from, to: lines.available.to)].compactMap { $0 }
            return .purchase(title: title, amount: amount, category: category, lines: rows)
        }
        if let budget = HomeBudgets(in: ledger, now: now).ordered.first(where: { question.contains($0.name) }) { return .budget(budget) }
        let breakdown = Finance.spendableBreakdown(ledger, now: now)
        let flow = Finance.cashFlow(ledger, during: DateInterval(start: breakdown.cycleStart, end: now.addingTimeInterval(0.001)))
        var facts = [breakdown.headlineTitle + " " + Money.text(breakdown.headlineAmount), "本期支出 " + Money.text(flow.spending)]
        if let top = flow.spendingByCategory.first, top.amount > 0 {
            facts.append("花得最多 · " + Classification.displayCategory(top.category) + " " + Money.text(top.amount))
        }
        return .summary(facts)
    }

    private static let number = #"\d+(?:[,，]\d{3})*(?:\.\d{1,2})?"#
    private static let priceUnit = #"[万千](?:元|块)?|元|块"#
    private static let explicitPrice = #"(?<![\d.,，−-])(?:[¥￥]\s*\#(number)(?:\s*(?:\#(priceUnit)))?|\#(number)\s*(?:\#(priceUnit)))(?![\d.])"#

    /// One price in an affordability question; nil when it names none or several.
    public static func purchasePrice(in text: String) -> Int64? {
        let query = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        if query.range(of: #"(?<![A-Za-z0-9])[−-]\s*[¥￥]?\s*\d"#, options: .regularExpression) != nil { return nil }
        if let range = query.range(of: explicitPrice, options: .regularExpression) {
            guard query[range.upperBound...].range(of: explicitPrice, options: .regularExpression) == nil else { return nil }
            let price = String(query[range])
            let scale: Int64 = price.contains("万") ? 10_000 : (price.contains("千") ? 1_000 : 1)
            let raw = price.filter { !"万千块元".contains($0) && !$0.isWhitespace }
            guard let cents = try? Money.parse(raw), cents > 0, cents <= Money.limit / scale else { return nil }
            return cents * scale
        }
        let singlePriceQuery = query.replacingOccurrences(of: "[各每]", with: " ", options: .regularExpression)
        let candidates = EntryAmountParser.candidates(in: singlePriceQuery)
        return candidates.count == 1 ? candidates.first : nil
    }

    public static func purchaseTitle(_ text: String) -> String {
        let query = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let price = query.range(of: explicitPrice, options: .regularExpression) == nil ? number : explicitPrice
        return query.replacingOccurrences(of: price, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "该不该买|可以买|买得起|能买吗|能买|想买个|想买|要买|买|多少钱|的", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// The running pill's task line.
    public static func runningLabel(_ question: String, in ledger: Ledger, now: Date) -> String {
        if let budget = HomeBudgets(in: ledger, now: now).ordered.first(where: { question.contains($0.name) }) { return "核对\(budget.name)预算…" }
        if question.contains("买"), purchasePrice(in: question) != nil {
            let title = purchaseTitle(question)
            if let category = CategoryGuesser.guess(title, nature: .expense, date: now, in: ledger)?.category,
               let budget = HomeBudgets(in: ledger, now: now).ordered.first(where: { $0.categories.contains(category) }) {
                return "核对\(budget.name)预算…"
            }
            return "核对还能花…"
        }
        if question.contains("记") || question.contains("截图") { return "整理账单…" }
        return "查账…"
    }
}
