import Foundation

public enum EntryType: String, CaseIterable, Identifiable, Equatable, Sendable {
    case expense
    case income
    case transfer
    case deposit

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        case .deposit: "存入"
        }
    }
}

public enum EntryException: String, CaseIterable, Equatable, Sendable {
    case reserve
    case reimbursement
    case split

    public var title: String {
        switch self {
        case .reserve: "走机动余钱"
        case .reimbursement: "待报销"
        case .split: "待 AA"
        }
    }

    public var pendingRecovery: PendingRecovery? {
        switch self {
        case .reserve: nil
        case .reimbursement: .reimbursement
        case .split: .split
        }
    }
}

/// Pure, Linux-portable arithmetic expression for the self-drawn entry keypad.
/// Enforces nine integer digits for each operand and the running total, with two decimal places.
public struct EntryAmountExpression: Equatable, Sendable {
    public static let maxIntegerDigits = 9
    public static let maxDecimalDigits = 2
    private static let maximumCents: Int64 = 99_999_999_999

    public private(set) var expression: String

    public init(expression: String = "0") {
        self.expression = expression.isEmpty ? "0" : expression
    }

    public init(cents: Int64, stripZeroDecimals: Bool = false) {
        if cents <= 0 {
            self.expression = "0"
        } else {
            self.expression = Self.editableString(for: cents, stripZeroDecimals: stripZeroDecimals)
        }
    }

    public var isEmpty: Bool {
        expression == "0" || expression.isEmpty
    }

    public var isExpression: Bool {
        expression.dropFirst().contains(where: { $0 == "+" || $0 == "-" })
    }

    public var evaluatedCents: Int64? {
        try? Self.evaluate(expression, allowTrailingOperator: true)
    }

    public var canSave: Bool {
        guard let cents = evaluatedCents else { return false }
        return cents > 0 && cents <= Self.maximumCents
    }

    public var formattedDisplay: String {
        Self.formatDisplay(expression)
    }

    public mutating func reset() {
        expression = "0"
    }

    @discardableResult
    public mutating func resolve() -> Int64? {
        guard let cents = try? Self.evaluate(expression, allowTrailingOperator: false) else { return nil }
        expression = Self.editableString(for: max(0, cents), stripZeroDecimals: false)
        return cents
    }

    public mutating func press(_ rawKey: String) {
        if rawKey == "⌫" {
            expression = expression.count > 1 ? String(expression.dropLast()) : "0"
            return
        }

        let key = rawKey == "−" ? "-" : rawKey
        if key == "+" || key == "-" {
            guard !isEmpty else { return }
            var next = expression
            if next.last == "+" || next.last == "-" {
                next.removeLast()
            }
            guard (try? Self.evaluate(next, allowTrailingOperator: false)) != nil else { return }
            expression = next + key
            return
        }

        let start = expression.lastIndex(where: { $0 == "+" || $0 == "-" }).map { expression.index(after: $0) } ?? expression.startIndex
        var operand = String(expression[start...])

        if key == "." {
            guard !operand.contains(".") else { return }
            operand = (operand.isEmpty ? "0" : operand) + "."
        } else if key == "00" {
            if let dot = operand.firstIndex(of: ".") {
                let decimals = operand.distance(from: dot, to: operand.endIndex) - 1
                if decimals == 0 {
                    operand += "00"
                } else if decimals == 1 {
                    operand += "0"
                } else {
                    return
                }
            } else {
                guard operand != "0", !operand.isEmpty else { return }
                guard operand.count + 2 <= Self.maxIntegerDigits else { return }
                operand += "00"
            }
        } else if key.count == 1, let ch = key.first, "0123456789".contains(ch) {
            if let dot = operand.firstIndex(of: ".") {
                let decimals = operand.distance(from: dot, to: operand.endIndex) - 1
                guard decimals < Self.maxDecimalDigits else { return }
                operand.append(ch)
            } else if operand == "0" {
                operand = String(ch)
            } else {
                guard operand.count < Self.maxIntegerDigits else { return }
                operand.append(ch)
            }
        } else {
            return
        }

        let candidate = String(expression[..<start]) + operand
        guard (try? Self.evaluate(candidate, allowTrailingOperator: false)) != nil else { return }
        expression = candidate
    }

    public static func evaluate(_ raw: String, allowTrailingOperator: Bool = false) throws -> Int64 {
        var text = raw.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        if allowTrailingOperator, text.count > 1, text.last == "+" || text.last == "-" {
            text.removeLast()
        }
        guard !text.isEmpty else { throw YubaiError.invalid("请输入金额。") }

        var total: Int64 = 0
        var operand = ""
        var sign: Int64 = 1

        func parseOperand(_ input: String) throws -> Int64 {
            guard !input.isEmpty else { throw YubaiError.invalid("请输入金额。") }
            let clean = input.hasSuffix(".") ? String(input.dropLast()) : input
            let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { throw YubaiError.invalid("请输入有效金额。") }
            let intPart = String(parts[0])
            let fracPart = parts.count == 2 ? String(parts[1]) : ""
            guard !intPart.isEmpty, intPart.count <= maxIntegerDigits, fracPart.count <= maxDecimalDigits,
                  intPart.allSatisfy(\.isASCII), intPart.allSatisfy(\.isNumber),
                  fracPart.allSatisfy(\.isASCII), fracPart.allSatisfy(\.isNumber),
                  let whole = Int64(intPart) else {
                throw YubaiError.invalid("请输入有效金额，最多九位整数、两位小数。")
            }
            let paddedFrac = fracPart + String(repeating: "0", count: maxDecimalDigits - fracPart.count)
            let centsPart = Int64(paddedFrac) ?? 0
            return whole * 100 + centsPart
        }

        for (index, char) in text.enumerated() {
            if char == "+" || char == "-" {
                if index == 0 && char == "-" {
                    sign = -1
                    continue
                }
                total += try parseOperand(operand) * sign
                guard (-maximumCents...maximumCents).contains(total) else {
                    throw YubaiError.invalid("金额超出范围。")
                }
                operand = ""
                sign = (char == "+") ? 1 : -1
            } else {
                guard "0123456789.".contains(char) else {
                    throw YubaiError.invalid("请输入有效金额。")
                }
                operand.append(char)
            }
        }
        if !operand.isEmpty {
            total += try parseOperand(operand) * sign
        } else if !allowTrailingOperator {
            throw YubaiError.invalid("请输入完整金额。")
        }
        guard (-maximumCents...maximumCents).contains(total) else {
            throw YubaiError.invalid("金额超出范围。")
        }
        return total
    }

    public static func formatDisplay(_ expression: String) -> String {
        var tokens: [String] = []
        var current = ""
        for (index, char) in expression.enumerated() {
            if (char == "+" || char == "-"), index > 0 {
                if !current.isEmpty {
                    tokens.append(formatOperand(current))
                    current = ""
                }
                tokens.append(char == "-" ? "−" : "+")
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(formatOperand(current))
        }
        return tokens.joined(separator: " ")
    }

    private static func formatOperand(_ raw: String) -> String {
        let negative = raw.hasPrefix("-")
        let body = negative ? String(raw.dropFirst()) : raw
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        let intDigits = String(parts.first ?? "0")
        let grouped = groupThousands(intDigits.isEmpty ? "0" : intDigits)
        let prefix = negative ? "−" : ""
        if parts.count == 2 {
            return prefix + grouped + "." + String(parts[1])
        }
        return prefix + grouped
    }

    private static func groupThousands(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var out = ""
        for (index, ch) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 {
                out.append(",")
            }
            out.append(ch)
        }
        return String(out.reversed())
    }

    public static func editableString(for cents: Int64, stripZeroDecimals: Bool = false) -> String {
        let magnitude = cents.magnitude
        let whole = magnitude / 100
        let frac = magnitude % 100
        let sign = cents < 0 ? "-" : ""
        if stripZeroDecimals && frac == 0 {
            return "\(sign)\(whole)"
        }
        return "\(sign)\(whole).\(frac < 10 ? "0" : "")\(frac)"
    }
}

public struct EntrySaveInput: Equatable, Sendable {
    public var type: EntryType
    public var amountCents: Int64
    public var currency: BillCurrency
    public var exchangeRate: Decimal?
    public var purpose: String
    public var category: String
    public var subcategory: String?
    public var accountID: UUID
    public var destinationAccountID: UUID?
    public var date: Date
    public var repeatMonthly: Bool
    public var exception: EntryException?
    public var incomeNextCycle: Bool
    public var personalExpenseCents: Int64?
    public var recordedNature: Nature?
    public var relatedEntryID: UUID?
    public var keepInFixedSavings: Bool
    public var preserveTime: Bool
    public var recoveryParticipants: [RecoveryParticipant]? = nil

    public init(
        type: EntryType,
        amountCents: Int64,
        currency: BillCurrency = .cny,
        exchangeRate: Decimal? = nil,
        purpose: String = "",
        category: String = Classification.pendingCategory,
        subcategory: String? = nil,
        accountID: UUID,
        destinationAccountID: UUID? = nil,
        date: Date,
        repeatMonthly: Bool = false,
        exception: EntryException? = nil,
        incomeNextCycle: Bool = false,
        personalExpenseCents: Int64? = nil,
        recordedNature: Nature? = nil,
        relatedEntryID: UUID? = nil,
        keepInFixedSavings: Bool = false,
        preserveTime: Bool = false
    ) {
        self.type = type
        self.amountCents = amountCents
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.purpose = purpose
        self.category = category
        self.subcategory = subcategory
        self.accountID = accountID
        self.destinationAccountID = destinationAccountID
        self.date = date
        self.repeatMonthly = repeatMonthly
        self.exception = exception
        self.incomeNextCycle = incomeNextCycle
        self.personalExpenseCents = personalExpenseCents
        self.recordedNature = recordedNature
        self.relatedEntryID = relatedEntryID
        self.keepInFixedSavings = keepInFixedSavings
        self.preserveTime = preserveTime
    }
}

public enum EntryEffect: Equatable, Sendable {
    case reserve(Int64), monthly(Int64), split(Int64), reimbursement(Int64)

    public var text: String {
        switch self {
        case .reserve(let amount): "机动余钱还剩 " + Money.text(amount, currency: false)
        case .monthly(let amount): "下期起每月先留 " + Money.text(amount, currency: false)
        case .split(let amount): "待收回 " + Money.text(amount, currency: false)
        case .reimbursement(let amount): "待收回 " + Money.text(amount, currency: false)
        }
    }

    public func displayText(hidesAmount: Bool) -> String {
        hidesAmount ? "••••" : text
    }

    public var warning: Bool {
        switch self {
        case .split, .reimbursement: true
        case .reserve, .monthly: false
        }
    }
}

public enum EntrySaveMapper {
    public static func cnyAmount(for input: EntrySaveInput, in ledger: Ledger, now: Date) -> Int64? {
        guard input.amountCents > 0 else { return nil }
        guard input.currency != .cny else { return input.amountCents }
        if let rateValue = input.exchangeRate {
            let quote = ManualExchangeRate(currency: input.currency, cnyPerUnit: rateValue, updatedAt: now)
            return quote.convert(input.amountCents)
        }
        return FixedFlows.exchangeRate(for: input.currency, in: ledger, now: now)?.convert(input.amountCents)
    }

    public static func effect(for input: EntrySaveInput, in ledger: Ledger, now: Date) -> EntryEffect? {
        guard input.recordedNature == nil, input.exception != nil || input.repeatMonthly,
              let amount = cnyAmount(for: input, in: ledger, now: now), amount > 0 else { return nil }
        if input.type == .expense, let exception = input.exception {
            switch exception {
            case .reserve:
                var updated = ledger
                guard let change = try? makeChange(input, in: ledger, now: now),
                      (try? change.apply(to: &updated)) != nil else { return nil }
                return .reserve(updated.fixedSavingsTotal(now: now))
            case .split: return .split(amount - min(amount, max(0, input.personalExpenseCents ?? 0)))
            case .reimbursement: return .reimbursement(amount)
            }
        }
        guard input.exception == nil, input.repeatMonthly,
              input.type == .expense || input.type == .deposit else { return nil }
        if input.type == .deposit {
            guard ledger.accounts.contains(where: { $0.id == input.destinationAccountID && $0.kind == .investment }) else { return nil }
        }
        return .monthly(amount)
    }

    /// 算作存入 · 本期已存: every bill home tags 存入 (into savings, or an investment buy) in this cycle,
    /// counted as a positive amount, plus the draft when its date falls in this cycle.
    public static func depositedThisCycle(in ledger: Ledger, now: Date, adding draftAmount: Int64, on draftDate: Date) -> Int64 {
        let cycle = Finance.cycle(in: ledger, now: now)
        func inCycle(_ date: Date) -> Bool { Dates.day(date) >= Dates.day(cycle.start) && Dates.day(date) <= Dates.day(cycle.end) }
        let saved = ledger.activeEntries.reduce(Int64(0)) { total, entry in
            guard entry.intoFixedSavings || entry.nature == .investBuy, entry.date <= now, inCycle(entry.date) else { return total }
            return total + abs(entry.amount)
        }
        return saved + (inCycle(draftDate) ? max(0, draftAmount) : 0)
    }

    public static func selectableAccounts(in ledger: Ledger, keeping selectedID: UUID? = nil) -> [Account] {
        ledger.accounts.filter { !$0.archived || $0.id == selectedID }
    }

    public static func edit(_ id: UUID, input: EntrySaveInput, in ledger: inout Ledger, now: Date) throws {
        guard let original = ledger.entries.first(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw YubaiError.invalid("找不到账单。")
        }
        var input = input
        input.preserveTime = true
        input.repeatMonthly = false
        let change = try makeChange(input, in: ledger, now: now)
        guard case .addEntry(let draft)? = change.items.first else { throw YubaiError.invalid("无法编辑这笔账单。") }
        var edited = original
        edited.nature = draft.nature
        edited.amount = draft.amount
        edited.date = draft.date
        edited.accountID = draft.accountID
        edited.otherAccountID = draft.otherAccountID
        edited.intoFixedSavings = draft.intoFixedSavings
        edited.fromReserve = draft.fromReserve
        edited.pendingRecovery = draft.pendingRecovery
        edited.personalExpense = draft.personalExpense ?? (draft.nature == original.nature ? original.personalExpense : nil)
        if edited.pendingRecovery != .split {
            edited.recoveryParticipants = nil
        } else if edited.amount != original.amount || edited.personalExpense != original.personalExpense || original.pendingRecovery != .split {
            let people = original.recoveryParticipants ?? draft.recoveryParticipants ?? []
            edited.recoveryParticipants = try EntryRecovery.redistribute(
                people, originalID: id, pending: EntryRecovery.pendingAmount(for: edited), in: ledger)
        }
        edited.countsFromCycleStart = draft.countsFromCycleStart
        edited.originalCurrency = draft.originalCurrency
        edited.originalAmount = draft.originalAmount
        edited.category = draft.category
        edited.subcategory = draft.subcategory
        edited.subcategoryUserEdited = true
        if !input.purpose.isEmpty && input.purpose != original.displayTitle { edited.purpose = input.purpose }
        if edited.nature != original.nature {
            edited.relatedEntryID = nil
            edited.planID = nil
            edited.occurrence = nil
            edited.rentID = nil
            edited.rentPeriod = nil
        }
        try ManualBookkeeping.edit(edited, in: &ledger, now: now)
    }

    public static func makeChange(_ input: EntrySaveInput, in ledger: Ledger, now: Date = Dates.now) throws -> ChangeSet {
        guard let source = ledger.accounts.first(where: { $0.id == input.accountID }) else {
            throw YubaiError.invalid("先选择一个账户。")
        }
        guard let cnyCents = cnyAmount(for: input, in: ledger, now: now), cnyCents > 0 else {
            throw YubaiError.invalid("请核对金额或汇率。")
        }

        let originalCurrency: BillCurrency? = input.currency == .cny ? nil : input.currency
        let originalAmount: Int64? = input.currency == .cny ? nil : input.amountCents
        let effectiveRepeat = input.repeatMonthly && input.exception == nil

        func patchDraft(_ change: inout ChangeSet, transform: (inout EntryDraft) -> Void) {
            change.items = change.items.map { item in
                guard case .addEntry(var draft) = item else { return item }
                if input.preserveTime { draft.date = input.date }
                transform(&draft)
                return .addEntry(draft)
            }
        }

        if let nature = input.recordedNature {
            let category = nature.paired ? "内部移动" : input.category
            var change = try ManualBookkeeping.change(
                amount: cnyCents, nature: nature, accountID: source.id, otherAccountID: input.destinationAccountID,
                day: input.date, purpose: input.purpose, category: category, now: now
            )
            patchDraft(&change) { draft in
                draft.subcategory = nature.paired ? nil : input.subcategory
                draft.originalCurrency = originalCurrency
                draft.originalAmount = originalAmount
            }
            if nature == .refund, let original = input.relatedEntryID,
               case .addEntry(let draft)? = change.items.first {
                guard ledger.entries.contains(where: { $0.id == original && $0.deletedAt == nil && $0.nature == .expense }) else {
                    throw YubaiError.invalid("找不到原始支出。")
                }
                change.items.append(.linkRefund(refund: draft.id, original: original))
            }
            return change
        }

        switch input.type {
        case .expense:
            let resolvedCategory = Classification.isPending(input.category) ? Classification.pendingCategory : input.category
            let sub = input.subcategory
            let fromReserve = input.exception == .reserve
            let pendingRecovery = input.exception?.pendingRecovery
            let myShare: Int64? = pendingRecovery == .split
                ? input.personalExpenseCents.map { min(cnyCents, max(0, $0)) }
                : nil

            var change: ChangeSet
            if effectiveRepeat {
                change = try FixedFlows.monthlyEntryChange(
                    amount: cnyCents,
                    nature: .expense,
                    accountID: source.id,
                    day: input.date,
                    purpose: input.purpose,
                    category: resolvedCategory,
                    now: now,
                    intoFixedSavings: false
                )
            } else {
                change = try ManualBookkeeping.change(
                    amount: cnyCents,
                    nature: .expense,
                    accountID: source.id,
                    day: input.date,
                    purpose: input.purpose,
                    category: resolvedCategory,
                    now: now,
                    intoFixedSavings: false,
                    fromReserve: fromReserve
                )
            }
            patchDraft(&change) { draft in
                draft.subcategory = sub
                draft.categoryUserEdited = true
                draft.pendingRecovery = pendingRecovery
                draft.personalExpense = myShare
                if let myShare, myShare < cnyCents {
                    draft.recoveryParticipants = input.recoveryParticipants
                        ?? [RecoveryParticipant(name: "TA", amount: cnyCents - myShare)]
                }
                draft.originalCurrency = originalCurrency
                draft.originalAmount = originalAmount
            }
            return change

        case .income:
            let resolvedCategory = Classification.isPending(input.category) ? Classification.pendingCategory : input.category
            let sub = input.subcategory
            let countsFromCycleStart: Date?
            if input.incomeNextCycle {
                let info = Finance.cycleInfo(in: ledger, now: input.date)
                countsFromCycleStart = Dates.day(Dates.addDays(1, to: info.end))
            } else {
                countsFromCycleStart = nil
            }

            var change: ChangeSet
            if effectiveRepeat {
                change = try FixedFlows.monthlyEntryChange(
                    amount: cnyCents,
                    nature: .income,
                    accountID: source.id,
                    day: input.date,
                    purpose: input.purpose,
                    category: resolvedCategory,
                    now: now,
                    intoFixedSavings: input.keepInFixedSavings
                )
            } else {
                change = try ManualBookkeeping.change(
                    amount: cnyCents,
                    nature: .income,
                    accountID: source.id,
                    day: input.date,
                    purpose: input.purpose,
                    category: resolvedCategory,
                    now: now,
                    intoFixedSavings: input.keepInFixedSavings,
                    fromReserve: false
                )
            }
            patchDraft(&change) { draft in
                draft.subcategory = sub
                draft.categoryUserEdited = true
                draft.countsFromCycleStart = countsFromCycleStart
                draft.originalCurrency = originalCurrency
                draft.originalAmount = originalAmount
            }
            return change

        case .transfer:
            guard let destID = input.destinationAccountID,
                  let destination = ledger.accounts.first(where: { $0.id == destID }),
                  destination.id != source.id else {
                throw YubaiError.invalid("转账的两个账户必须不同。")
            }
            let isCashOrBank = source.kind == .cash || source.kind == .bank
            let nature: Nature = (isCashOrBank && destination.kind == .credit) ? .repayment : .transfer
            var change = try ManualBookkeeping.change(
                amount: cnyCents,
                nature: nature,
                accountID: source.id,
                otherAccountID: destination.id,
                day: input.date,
                purpose: input.purpose,
                category: "内部移动",
                now: now
            )
            patchDraft(&change) { draft in
                draft.originalCurrency = originalCurrency
                draft.originalAmount = originalAmount
            }
            return change

        case .deposit:
            guard let destID = input.destinationAccountID,
                  let destination = ledger.accounts.first(where: { $0.id == destID }),
                  destination.id != source.id else {
                throw YubaiError.invalid("存入的两个账户必须不同。")
            }
            guard source.kind == .cash || source.kind == .bank,
                  [.investment, .bank, .cash].contains(destination.kind) else {
                throw YubaiError.invalid("请选择可存入的账户。")
            }
            let isInvestBuy = destination.kind == .investment
            let nature: Nature = isInvestBuy ? .investBuy : .transfer
            let intoFixedSavings = !isInvestBuy

            var change: ChangeSet
            if effectiveRepeat && nature != .transfer {
                change = try FixedFlows.monthlyEntryChange(
                    amount: cnyCents,
                    nature: nature,
                    accountID: source.id,
                    otherAccountID: destination.id,
                    day: input.date,
                    purpose: input.purpose,
                    category: "内部移动",
                    now: now,
                    intoFixedSavings: intoFixedSavings
                )
            } else {
                change = try ManualBookkeeping.change(
                    amount: cnyCents,
                    nature: nature,
                    accountID: source.id,
                    otherAccountID: destination.id,
                    day: input.date,
                    purpose: input.purpose,
                    category: "内部移动",
                    now: now,
                    intoFixedSavings: intoFixedSavings
                )
            }
            patchDraft(&change) { draft in
                draft.originalCurrency = originalCurrency
                draft.originalAmount = originalAmount
            }
            return change
        }
    }
}
