import Foundation

public enum YubaiError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum Money {
    public static let limit: Int64 = 99_999_999_999_99
    public static func parse(_ input: String, allowNegative: Bool = false) throws -> Int64 {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for symbol in ["¥", "￥", "CNY", "RMB", "元", " "] { s = s.replacingOccurrences(of: symbol, with: "") }
        s = s.replacingOccurrences(of: "，", with: ",")
        if s.contains(",") {
            guard s.range(of: #"^[+-]?\d{1,3}(,\d{3})+(\.\d{1,2})?$"#, options: .regularExpression) != nil else { throw YubaiError.invalid("金额的千位分隔格式不正确。") }
            s = s.replacingOccurrences(of: ",", with: "")
        }
        s = s.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "＋", with: "+")
        guard s.range(of: #"^[+-]?\d{1,12}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else {
            throw YubaiError.invalid("请输入有效金额，最多保留两位小数。")
        }
        let cents = NSDecimalNumber(decimal: decimal * 100).int64Value
        guard abs(cents) <= limit, allowNegative || cents >= 0 else { throw YubaiError.invalid("金额超出范围或不能为负数。") }
        return cents
    }
    public static func text(_ cents: Int64, currency: Bool = true) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = currency ? .currency : .decimal; f.currencySymbol = "¥"
        f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: Decimal(cents) / 100)) ?? "0.00"
    }
    public static func input(_ cents: Int64) -> String { NSDecimalNumber(decimal: Decimal(cents) / 100).stringValue }
    /// Ungrouped text with exactly two decimal places for editable amounts.
    public static func editableText(_ cents: Int64) -> String {
        let magnitude = cents.magnitude
        let fraction = magnitude % 100
        return "\(cents < 0 ? "-" : "")\(magnitude / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}

public enum Dates {
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }
    public static func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
    public static func addDays(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: n, to: date)! }
    public static func addMonths(_ n: Int, to date: Date) -> Date { calendar.date(byAdding: .month, value: n, to: date)! }
    public static func text(_ d: Date, time: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = time ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"; return f.string(from: d)
    }
    public static func parse(_ input: String) -> Date? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd", "yyyy年MM月dd日 HH:mm:ss", "yyyyMMdd"] {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format; f.isLenient = false
            if let d = f.date(from: value), f.string(from: d) == value { return d }
        }
        return ISO8601DateFormatter().date(from: value)
    }
    public static func excel(_ serial: Double, date1904: Bool = false) -> Date? {
        guard serial.isFinite, serial >= 1, serial <= 100000 else { return nil }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = utc.date(from: DateComponents(year: date1904 ? 1904 : 1899, month: date1904 ? 1 : 12, day: date1904 ? 1 : 30))!
        let absolute = base.addingTimeInterval((serial * 86400).rounded())
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: absolute)
        return calendar.date(from: parts)
    }
}

public enum AccountKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case cash, bank, credit, investment, receivable
    public var id: String { rawValue }
    public var label: String { switch self { case .cash: "零钱与现金"; case .bank: "银行卡"; case .credit: "信用与借款"; case .investment: "投资"; case .receivable: "借出待收" } }
    public var symbol: String { switch self { case .cash: "wallet.bifold"; case .bank: "building.columns"; case .credit: "creditcard"; case .investment: "chart.line.uptrend.xyaxis"; case .receivable: "arrow.down.left.circle" } }
}
public struct Account: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var kind: AccountKind
    public var anchorBalance: Int64; public var anchorDate: Date
    public var reconciled: Bool; public var archived = false
    public var note = ""; public var creditLimit: Int64 = 0
    public var creditPaymentDay: Int?
    public init(name: String, kind: AccountKind = .bank, balance: Int64 = 0, at: Date = Dates.now, reconciled: Bool = true) {
        self.name = name; self.kind = kind; self.anchorBalance = balance; self.anchorDate = at; self.reconciled = reconciled
    }
    /// Date-only in-app entries recorded after reconciliation still move that day's balance.
    /// Earlier posting days are already included in the anchor; imports use posting time alone.
    public func includes(_ entry: Entry, posting: Date) -> Bool {
        posting > anchorDate || (entry.recordedAt.map { $0 > anchorDate && Dates.day(posting) >= Dates.day(anchorDate) } ?? false)
    }
}

public enum Nature: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense, income, transfer, repayment, borrow, lend, loanReturn, loanRecovery, refund, contribution, investBuy, investSell, adjustmentIn, adjustmentOut, unknownIn, unknownOut
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .expense: "支出"; case .income: "收入"; case .transfer: "自有账户转账"; case .repayment: "信用还款"
        case .borrow: "借入本金"; case .lend: "借出本金"; case .loanReturn: "归还借款"; case .loanRecovery: "收回借款"
        case .refund: "消费退款"; case .contribution: "收到分摊"; case .investBuy: "投资申购"; case .investSell: "投资赎回"
        case .adjustmentIn: "调增余额"; case .adjustmentOut: "调减余额"; case .unknownIn: "没写用途的进账"; case .unknownOut: "没写用途的出账"
        }
    }
    public var categoryIncome: Bool { self != .refund && inflow }
    public var inflow: Bool { [.income, .borrow, .loanRecovery, .refund, .contribution, .investSell, .adjustmentIn, .unknownIn].contains(self) }
    public var paired: Bool { [.transfer, .repayment, .investBuy, .investSell, .borrow, .lend, .loanReturn, .loanRecovery].contains(self) }
    public var uncertain: Bool { self == .unknownIn || self == .unknownOut }
    public var symbol: String {
        switch self { case .income: "arrow.down.left"; case .expense: "arrow.up.right"; case .refund: "arrow.uturn.backward"; case .contribution: "person.2"; default: paired ? "arrow.left.arrow.right" : "circle.dotted" }
    }
}

public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var date: Date; public var amount: Int64
    public var recordedAt: Date? // In-app recording time; imports and old ledgers keep nil.
    public var nature: Nature { didSet { if nature != .income { intoFixedSavings = false }; if nature != .expense { fromReserve = false } } }
    public var intoFixedSavings = false { didSet { if nature != .income { intoFixedSavings = false } } }
    public var fromReserve = false { didSet { if nature != .expense { fromReserve = false } } }
    public var spreadFrom: Date?
    public var isUnitemized: Bool { spreadFrom != nil }
    public var accountID: UUID; public var otherAccountID: UUID?
    public var title: String; public var category: String; public var note: String = ""
    public var purpose: String?
    public var partID: UUID?
    public var subcategory: String?
    public var subcategoryUserEdited = false
    public var displayTitle: String { purpose.flatMap { $0.isEmpty ? nil : $0 } ?? title }
    public var source: String = "手动"; public var externalID: String = ""; public var batchID: UUID?
    public var sourceIdentity: String = ""
    public var quickCapture: QuickCaptureOrigin?
    public var sourceRow: Int?; public var fingerprint: String = ""
    public var userEdited = false; public var deletedAt: Date?
    public var relatedEntryID: UUID?; public var planID: UUID?; public var occurrence: Date?
    public var rentID: UUID?; public var rentPeriod: Date?
    public var attachmentID: UUID?; public var classificationReason: String = "手动选择"
    public var otherDate: Date?; public var mergedIntoID: UUID?; public var personalExpense: Int64?
    public init(date: Date = Dates.now, amount: Int64, nature: Nature = .expense, accountID: UUID, title: String, category: String = Classification.pendingCategory, intoFixedSavings: Bool = false, fromReserve: Bool = false) {
        self.date = date; self.amount = amount; self.nature = nature; self.accountID = accountID; self.title = title; self.category = category
        self.intoFixedSavings = nature == .income && intoFixedSavings
        self.fromReserve = nature == .expense && fromReserve
    }
    private enum CodingKeys: String, CodingKey { case fromReserve, spreadFrom, intoFixedSavings, partID, id, date, amount, recordedAt, nature, accountID, otherAccountID, title, category, note, purpose, subcategory, subcategoryUserEdited, source, externalID, batchID, sourceIdentity, quickCapture, sourceRow, fingerprint, userEdited, deletedAt, relatedEntryID, planID, occurrence, rentID, rentPeriod, attachmentID, classificationReason, otherDate, mergedIntoID, personalExpense }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(Int64.self, forKey: .amount)
        recordedAt = try c.decodeIfPresent(Date.self, forKey: .recordedAt)
        nature = try c.decode(Nature.self, forKey: .nature)
        let intoFixed = try c.decodeIfPresent(Bool.self, forKey: .intoFixedSavings) ?? false
        intoFixedSavings = nature == .income && intoFixed
        let reserve = try c.decodeIfPresent(Bool.self, forKey: .fromReserve) ?? false
        fromReserve = nature == .expense && reserve
        spreadFrom = try c.decodeIfPresent(Date.self, forKey: .spreadFrom)
        accountID = try c.decode(UUID.self, forKey: .accountID)
        otherAccountID = try c.decodeIfPresent(UUID.self, forKey: .otherAccountID)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(String.self, forKey: .category)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        partID = try c.decodeIfPresent(UUID.self, forKey: .partID)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose)
        subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        subcategoryUserEdited = try c.decodeIfPresent(Bool.self, forKey: .subcategoryUserEdited) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "手动"
        externalID = try c.decodeIfPresent(String.self, forKey: .externalID) ?? ""
        batchID = try c.decodeIfPresent(UUID.self, forKey: .batchID)
        sourceIdentity = try c.decodeIfPresent(String.self, forKey: .sourceIdentity) ?? ""
        quickCapture = try c.decodeIfPresent(QuickCaptureOrigin.self, forKey: .quickCapture)
        sourceRow = try c.decodeIfPresent(Int.self, forKey: .sourceRow)
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        userEdited = try c.decodeIfPresent(Bool.self, forKey: .userEdited) ?? false
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        relatedEntryID = try c.decodeIfPresent(UUID.self, forKey: .relatedEntryID)
        planID = try c.decodeIfPresent(UUID.self, forKey: .planID)
        occurrence = try c.decodeIfPresent(Date.self, forKey: .occurrence)
        rentID = try c.decodeIfPresent(UUID.self, forKey: .rentID)
        rentPeriod = try c.decodeIfPresent(Date.self, forKey: .rentPeriod)
        attachmentID = try c.decodeIfPresent(UUID.self, forKey: .attachmentID)
        classificationReason = try c.decodeIfPresent(String.self, forKey: .classificationReason) ?? "手动选择"
        otherDate = try c.decodeIfPresent(Date.self, forKey: .otherDate)
        mergedIntoID = try c.decodeIfPresent(UUID.self, forKey: .mergedIntoID)
        personalExpense = try c.decodeIfPresent(Int64.self, forKey: .personalExpense)
    }
    public func encode(to encoder: Encoder) throws {
        // All omitted values already have explicit defaults in init(from:).
        // Keep provenance, deduplication keys and every non-default prior value intact.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(date, forKey: .date); try c.encode(amount, forKey: .amount)
        try c.encode(nature, forKey: .nature); try c.encode(accountID, forKey: .accountID)
        if intoFixedSavings { try c.encode(true, forKey: .intoFixedSavings) }
        if fromReserve { try c.encode(true, forKey: .fromReserve) }
        try c.encodeIfPresent(spreadFrom, forKey: .spreadFrom)
        try c.encode(title, forKey: .title); try c.encode(category, forKey: .category)
        try c.encodeIfPresent(recordedAt, forKey: .recordedAt); try c.encodeIfPresent(otherAccountID, forKey: .otherAccountID)
        if !note.isEmpty { try c.encode(note, forKey: .note) }
        try c.encodeIfPresent(partID, forKey: .partID)
        try c.encodeIfPresent(purpose, forKey: .purpose); try c.encodeIfPresent(subcategory, forKey: .subcategory)
        if subcategoryUserEdited { try c.encode(true, forKey: .subcategoryUserEdited) }
        if source != "手动" { try c.encode(source, forKey: .source) }
        if !externalID.isEmpty { try c.encode(externalID, forKey: .externalID) }
        try c.encodeIfPresent(batchID, forKey: .batchID)
        if !sourceIdentity.isEmpty { try c.encode(sourceIdentity, forKey: .sourceIdentity) }
        try c.encodeIfPresent(quickCapture, forKey: .quickCapture); try c.encodeIfPresent(sourceRow, forKey: .sourceRow)
        if !fingerprint.isEmpty { try c.encode(fingerprint, forKey: .fingerprint) }
        if userEdited { try c.encode(true, forKey: .userEdited) }
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt); try c.encodeIfPresent(relatedEntryID, forKey: .relatedEntryID)
        try c.encodeIfPresent(planID, forKey: .planID); try c.encodeIfPresent(occurrence, forKey: .occurrence)
        try c.encodeIfPresent(rentID, forKey: .rentID); try c.encodeIfPresent(rentPeriod, forKey: .rentPeriod)
        try c.encodeIfPresent(attachmentID, forKey: .attachmentID)
        if classificationReason != "手动选择" { try c.encode(classificationReason, forKey: .classificationReason) }
        try c.encodeIfPresent(otherDate, forKey: .otherDate); try c.encodeIfPresent(mergedIntoID, forKey: .mergedIntoID)
        try c.encodeIfPresent(personalExpense, forKey: .personalExpense)
    }
    public func delta(for account: UUID) -> Int64 {
        if accountID == account { return nature.inflow ? amount : -amount }
        if nature.paired && otherAccountID == account { return nature.inflow ? -amount : amount }
        return 0
    }
    public func postingDate(for account: UUID) -> Date { otherAccountID == account ? (otherDate ?? date) : date }
}

public enum Frequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case once, weekly, monthly, quarterly, yearly, halfYearly, fortnightly
    public var id: String { rawValue }
    public var label: String { switch self { case .once: "一次"; case .weekly: "每周"; case .monthly: "每月"; case .quarterly: "每季"; case .yearly: "每年"; case .halfYearly: "每半年"; case .fortnightly: "每两周" } }
    public func advance(_ original: Date, by count: Int) -> Date {
        switch self { case .once: return original; case .weekly: return Dates.addDays(7 * count, to: original); case .monthly: return Dates.addMonths(count, to: original); case .quarterly: return Dates.addMonths(3 * count, to: original); case .yearly: return Dates.addMonths(12 * count, to: original); case .halfYearly: return Dates.addMonths(6 * count, to: original); case .fortnightly: return Dates.addDays(14 * count, to: original) }
    }
}
public struct Plan: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var amount: Int64; public var dueDate: Date
    public var frequency: Frequency
    /// Amount is in this currency; entries and all finance totals remain CNY.
    public var currency: BillCurrency = .cny
    public var yearlyReserveSince: Date?
    public var inflow: Bool { didSet { if !inflow { intoFixedSavings = false } } }
    public var accountID: UUID?
    public var category: String
    public var nature: Nature { didSet { if nature != .income { intoFixedSavings = false } } }
    public var intoFixedSavings = false { didSet { if nature != .income || !inflow { intoFixedSavings = false } } }
    public var active = true
    public var endDate: Date?; public var stoppedAt: Date?; public var note = ""
    public var autoPay = false; public var autoPaySince: Date?
    public var installments: Int?; public var estimated = false
    // Preserve a detected payday when the first due date is clamped to a short month.
    public var monthlyDay: Int?
    public var skippedOccurrences: [Date] = []
    /// Linked periods retained when the recurring schedule is replaced. These
    /// count toward installments, and are merged by day with the new schedule.
    public var previousOccurrences: [Date] = []
    /// Completion before an edit is independent of later price/estimate changes.
    /// A period still needs a live linked payment to remain paid.
    public var settledOccurrences: [Date] = []
    public var estimatedAmountSince: Date?
    /// Original scheduled day → replacement day. Nil preserves the recurring schedule.
    public var occurrenceDateOverrides: [Date: Date]?
    public init(title: String, amount: Int64, dueDate: Date, frequency: Frequency = .once, inflow: Bool = false, category: String = Classification.pendingCategory, nature: Nature = .expense, intoFixedSavings: Bool = false) {
        self.title = title; self.amount = amount; self.dueDate = dueDate; self.frequency = frequency; self.inflow = inflow; self.category = category; self.nature = nature
        self.intoFixedSavings = nature == .income && inflow && intoFixedSavings
        if frequency == .yearly { yearlyReserveSince = Dates.day(Dates.now) }
    }
    private enum CodingKeys: String, CodingKey { case currency, yearlyReserveSince, occurrenceDateOverrides, intoFixedSavings, id, title, amount, dueDate, frequency, inflow, accountID, category, nature, active, endDate, stoppedAt, note, autoPay, autoPaySince, installments, estimated, skippedOccurrences, monthlyDay, previousOccurrences, settledOccurrences, estimatedAmountSince }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        amount = try c.decode(Int64.self, forKey: .amount); dueDate = try c.decode(Date.self, forKey: .dueDate)
        frequency = try c.decodeIfPresent(Frequency.self, forKey: .frequency) ?? .once; inflow = try c.decode(Bool.self, forKey: .inflow)
        currency = try c.decodeIfPresent(BillCurrency.self, forKey: .currency) ?? .cny
        yearlyReserveSince = try c.decodeIfPresent(Date.self, forKey: .yearlyReserveSince) ?? (frequency == .yearly ? Dates.day(Dates.now) : nil)
        accountID = try c.decodeIfPresent(UUID.self, forKey: .accountID)
        category = try c.decode(String.self, forKey: .category); nature = try c.decode(Nature.self, forKey: .nature)
        let intoFixed = try c.decodeIfPresent(Bool.self, forKey: .intoFixedSavings) ?? false
        intoFixedSavings = nature == .income && inflow && intoFixed
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true; endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        stoppedAt = try c.decodeIfPresent(Date.self, forKey: .stoppedAt)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        autoPay = try c.decodeIfPresent(Bool.self, forKey: .autoPay) ?? false
        autoPaySince = try c.decodeIfPresent(Date.self, forKey: .autoPaySince)
        installments = try c.decodeIfPresent(Int.self, forKey: .installments)
        monthlyDay = try c.decodeIfPresent(Int.self, forKey: .monthlyDay)
        estimated = try c.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        skippedOccurrences = try c.decodeIfPresent([Date].self, forKey: .skippedOccurrences) ?? []
        previousOccurrences = try c.decodeIfPresent([Date].self, forKey: .previousOccurrences) ?? []
        settledOccurrences = try c.decodeIfPresent([Date].self, forKey: .settledOccurrences) ?? []
        estimatedAmountSince = try c.decodeIfPresent(Date.self, forKey: .estimatedAmountSince)
        occurrenceDateOverrides = try c.decodeIfPresent([Date: Date].self, forKey: .occurrenceDateOverrides)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(amount, forKey: .amount)
        try c.encode(dueDate, forKey: .dueDate); try c.encode(frequency, forKey: .frequency); try c.encode(inflow, forKey: .inflow)
        if currency != .cny { try c.encode(currency, forKey: .currency) }
        try c.encodeIfPresent(yearlyReserveSince, forKey: .yearlyReserveSince)
        try c.encodeIfPresent(accountID, forKey: .accountID); try c.encode(category, forKey: .category); try c.encode(nature, forKey: .nature)
        try c.encode(intoFixedSavings, forKey: .intoFixedSavings); try c.encode(active, forKey: .active)
        try c.encodeIfPresent(endDate, forKey: .endDate); try c.encodeIfPresent(stoppedAt, forKey: .stoppedAt); try c.encode(note, forKey: .note)
        try c.encode(autoPay, forKey: .autoPay); try c.encodeIfPresent(autoPaySince, forKey: .autoPaySince)
        try c.encodeIfPresent(installments, forKey: .installments); try c.encode(estimated, forKey: .estimated)
        try c.encodeIfPresent(monthlyDay, forKey: .monthlyDay); try c.encode(skippedOccurrences, forKey: .skippedOccurrences)
        try c.encode(previousOccurrences, forKey: .previousOccurrences); try c.encode(settledOccurrences, forKey: .settledOccurrences)
        try c.encodeIfPresent(estimatedAmountSince, forKey: .estimatedAmountSince)
        if let occurrenceDateOverrides, !occurrenceDateOverrides.isEmpty { try c.encode(occurrenceDateOverrides, forKey: .occurrenceDateOverrides) }
    }
    func schedule(through end: Date) -> [(index: Int, date: Date)] {
        guard let overrides = occurrenceDateOverrides, !overrides.isEmpty else { return baseSchedule(through: end) }
        let through = max(end, overrides.keys.max() ?? end)
        return baseSchedule(through: through).compactMap { item in
            let date = overrides[Dates.day(item.date)] ?? item.date
            return date <= end ? (item.index, date) : nil
        }.sorted { $0.date == $1.date ? $0.index < $1.index : $0.date < $1.date }
    }
    func baseSchedule(through end: Date) -> [(index: Int, date: Date)] {
        let previous = Set(previousOccurrences.map(Dates.day))
        var dates = previousOccurrences
        let limit = min(2400, max(0, installments ?? 2400))
        var added = previous.count
        for index in 0..<2400 {
            if added >= limit { break }
            let date = scheduledDate(at: index)
            if date > end || endDate.map({ date > $0 }) == true { break }
            if !previous.contains(Dates.day(date)) { dates.append(date); added += 1 }
            if frequency == .once { break }
        }
        return dates.sorted().enumerated().compactMap { index, date in date <= end ? (index, date) : nil }
    }
    func scheduledDate(at index: Int) -> Date {
        let date = frequency.advance(dueDate, by: index)
        guard frequency == .monthly, let monthlyDay else { return date }
        let calendar = Dates.calendar
        let month = calendar.dateInterval(of: .month, for: date)!.start
        let last = calendar.range(of: .day, in: .month, for: date)!.count
        return Dates.addDays(min(max(1, monthlyDay), last) - 1, to: month)
    }
    func isSkipped(on date: Date) -> Bool { skippedOccurrences.contains { Dates.day($0) == Dates.day(date) } }
    /// The earliest scheduled, non-waived day after a boundary, without expanding
    /// an unlimited arrangement to the end of the supported date range.
    func nextScheduledDate(after boundary: Date) -> Date? {
        if let overrides = occurrenceDateOverrides, !overrides.isEmpty {
            return schedule(through: Date(timeIntervalSince1970: 7_258_118_400)).first { $0.date > boundary && !isSkipped(on: $0.date) }?.date
        }
        let previous = Set(previousOccurrences.map(Dates.day))
        let historical = previousOccurrences.filter { $0 > boundary && !isSkipped(on: $0) }.min()
        let limit = min(2400, max(0, installments ?? 2400))
        var count = previous.count
        for index in 0..<2400 {
            if count >= limit { break }
            let date = scheduledDate(at: index)
            if endDate.map({ date > $0 }) == true { break }
            if !previous.contains(Dates.day(date)) {
                count += 1
                if date > boundary && !isSkipped(on: date) { return min(date, historical ?? date) }
            }
            if frequency == .once { break }
        }
        return historical
    }
    func occurrenceIndex(on date: Date) -> Int? {
        if !previousOccurrences.isEmpty || !(occurrenceDateOverrides?.isEmpty ?? true) {
            return schedule(through: Dates.addDays(1, to: Dates.day(date)).addingTimeInterval(-0.001)).first { Dates.day($0.date) == Dates.day(date) }?.index
        }
        let day = Dates.day(date); let start = Dates.day(dueDate)
        guard day >= start, endDate.map({ day <= Dates.day($0) }) ?? true else { return nil }
        let count: Int
        switch frequency {
        case .once: count = 0
        case .weekly, .fortnightly: count = (Dates.calendar.dateComponents([.day], from: start, to: day).day ?? -1) / (frequency == .weekly ? 7 : 14)
        case .monthly, .quarterly, .halfYearly, .yearly:
            let c = Dates.calendar
            let months = c.dateComponents([.month], from: c.dateInterval(of: .month, for: start)!.start, to: c.dateInterval(of: .month, for: day)!.start).month ?? -1
            count = months / (frequency == .monthly ? 1 : (frequency == .quarterly ? 3 : (frequency == .halfYearly ? 6 : 12)))
        }
        guard count >= 0, installments.map({ count < $0 }) ?? true,
              Dates.day(scheduledDate(at: count)) == day else { return nil }
        return count
    }
}
public struct Goal: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var target: Int64; public var reserved: Int64
    public var dueDate: Date?; public var note = ""
    public init(title: String, target: Int64, reserved: Int64 = 0, dueDate: Date? = nil) { self.title = title; self.target = target; self.reserved = reserved; self.dueDate = dueDate }
}
public struct Rent: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var monthlyTotal: Int64; public var personalShare: Int64
    public var startDate: Date; public var nextDueDate: Date; public var monthsPerPayment: Int
    public var receiveDay: Int; public var accountID: UUID?; public var active = true; public var note = ""
    public var endDate: Date?; public var stoppedAt: Date?
    public init(title: String = "合租房租", monthlyTotal: Int64, personalShare: Int64, startDate: Date, nextDueDate: Date, monthsPerPayment: Int = 3, receiveDay: Int = 1) {
        self.title = title; self.monthlyTotal = monthlyTotal; self.personalShare = personalShare; self.startDate = startDate; self.nextDueDate = nextDueDate; self.monthsPerPayment = monthsPerPayment; self.receiveDay = receiveDay
    }
}
public struct Category: Codable, Identifiable, Equatable, Sendable {
    public var name: String; public var symbol: String; public var income: Bool
    public var subcategories: [String]
    public var keywords: [String]
    public var subcategoryKeywords: [String: [String]]
    public var system: Bool
    public var hidden: Bool
    public var id: String { CategoryNamespace.key(name, income: income) }
    public var isCatchAll: Bool { name == (income ? "其他收入" : "其他支出") }
    public init(_ name: String, _ symbol: String = "square.grid.2x2", income: Bool = false,
                subcategories: [String] = [], keywords: [String] = [], subcategoryKeywords: [String: [String]] = [:],
                system: Bool = false, hidden: Bool = false) {
        self.name = name; self.symbol = symbol; self.income = income; self.subcategories = subcategories
        self.keywords = keywords; self.subcategoryKeywords = subcategoryKeywords; self.system = system; self.hidden = hidden
    }
    private enum CodingKeys: String, CodingKey { case name, symbol, income, subcategories, keywords, subcategoryKeywords, system, hidden }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name); symbol = try c.decode(String.self, forKey: .symbol)
        income = try c.decode(Bool.self, forKey: .income)
        subcategories = try c.decodeIfPresent([String].self, forKey: .subcategories) ?? []
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        subcategoryKeywords = try c.decodeIfPresent([String: [String]].self, forKey: .subcategoryKeywords) ?? [:]
        system = try c.decodeIfPresent(Bool.self, forKey: .system) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
    /// Goods belong to shopping; services/experiences to their domain. Tickets
    /// belong to transport; recurring monthly/yearly services to subscriptions.
    public static let defaults: [Category] = [
        .init("餐饮", "fork.knife", subcategories: ["早餐", "午餐", "晚餐", "外卖", "咖啡饮品", "零食水果", "聚餐", "买菜做饭"],
              keywords: ["吃饭", "饭", "食堂", "餐厅", "烧烤", "小吃", "面馆", "麻辣烫", "饭店", "餐饮", "烧麦", "火锅", "快餐"], subcategoryKeywords: [
                "早餐": ["早餐", "早饭"], "午餐": ["午餐", "午饭"], "晚餐": ["晚餐", "晚饭"],
                "外卖": ["外卖", "饿了么", "美团外卖"], "咖啡饮品": ["咖啡", "奶茶", "饮品", "coffee", "cafe", "茶饮"], "零食水果": ["零食", "水果"], "聚餐": ["聚餐"],
                "买菜做饭": ["买菜", "做饭", "买蔬菜", "菜市场", "生鲜", "叮咚"]]),
        .init("购物", "bag", subcategories: ["日用百货", "服饰鞋包", "数码电器", "家居家电", "美妆个护", "运动户外", "书和文具", "烟酒", "快递"],
              keywords: ["购物", "淘宝", "京东"], subcategoryKeywords: [
                "日用百货": ["日用", "纸巾", "洗衣", "洗衣液", "超市", "罗森", "便利店", "商店", "百货"], "服饰鞋包": ["买衣", "衣服", "买鞋", "鞋包"],
                "数码电器": ["手机", "电脑", "数码", "电器"], "家居家电": ["家居", "家电", "家具"], "美妆个护": ["洗发", "美妆", "个护", "护肤"],
                "运动户外": ["登山杖", "登山鞋", "帐篷", "运动装备", "户外装备"], "书和文具": ["书籍", "买书", "文具", "办公用品"],
                "烟酒": ["烟", "香烟", "酒", "白酒", "啤酒"], "快递": ["快递", "寄快递", "寄东西", "寄包裹", "顺丰", "邮费", "运费", "寄件"]]),
        .init("交通", "tram", subcategories: ["公共交通", "打车", "加油停车", "共享单车", "火车飞机", "养车"], subcategoryKeywords: [
                "公共交通": ["地铁", "公交"], "打车": ["滴滴", "打车", "出租车"], "加油停车": ["加油", "停车", "高速", "加油站", "停车场", "ETC"],
                "共享单车": ["共享单车"], "火车飞机": ["火车", "机票", "高铁", "车票", "飞机票"],
                "养车": ["保养", "洗车", "修车", "汽车保养", "换机油", "换轮胎", "违章", "交通罚款", "违章罚款", "交警罚款", "年检", "4S"]]),
        .init("居住", "house", subcategories: ["房租", "水电燃气", "物业", "网费话费", "维修", "家政保洁"], subcategoryKeywords: [
                "房租": ["房租"], "水电燃气": ["水费", "电费", "燃气"], "物业": ["物业"], "网费话费": ["网费", "话费"], "维修": ["维修"], "家政保洁": ["家政", "保洁", "钟点工", "清洁", "请阿姨", "打扫卫生"]]),
        .init("医疗健康", "cross.case", subcategories: ["看病", "药品", "体检"], subcategoryKeywords: ["看病": ["看病", "挂号", "医院", "诊所"], "药品": ["药品", "买药", "药店", "药房"], "体检": ["体检"]]),
        .init("美容个护", "scissors", subcategories: ["理发", "美容美甲", "洗浴按摩"], subcategoryKeywords: [
                "理发": ["理发", "美发", "造型", "发型", "剪发", "剪头发", "剪头", "洗头", "洗剪吹", "理发店", "发廊", "烫发", "染发"], "美容美甲": ["美甲", "美容", "美睫", "做指甲", "做美甲"],
                "洗浴按摩": ["洗浴", "按摩", "足疗", "SPA", "汗蒸"]]),
        .init("娱乐", "sparkles", subcategories: ["电影演出", "游戏", "运动健身", "兴趣爱好"], keywords: ["娱乐"], subcategoryKeywords: [
                "电影演出": ["电影", "演唱会", "演出"], "游戏": ["游戏"], "运动健身": ["健身", "健身房", "球场"], "兴趣爱好": ["兴趣", "爱好"]]),
        .init("旅行", "suitcase", subcategories: ["住宿", "门票游玩", "跟团包价"], subcategoryKeywords: ["住宿": ["住宿", "酒店", "民宿"], "门票游玩": ["门票", "游玩"], "跟团包价": ["跟团", "包价"]]),
        .init("会员订阅", "repeat", subcategories: ["影音会员", "软件云服务", "其他会员"], keywords: ["会员", "订阅", "按月自动扣", "按年自动扣", "每月自动扣费", "每年自动扣费", "月费", "年费"], subcategoryKeywords: [
                "影音会员": ["影音会员", "视频会员", "音乐会员", "电影会员"], "软件云服务": ["软件工具", "软件订阅", "软件会员", "云服务", "icloud"], "其他会员": ["其他会员", "健身房会员", "健身会员", "月卡", "年卡"]]),
        .init("学习成长", "book", subcategories: ["课程", "考试证书"], subcategoryKeywords: ["课程": ["课程", "培训"], "考试证书": ["考试", "证书"]]),
        .init("人情家庭", "gift", subcategories: ["红包礼物", "给家人", "孩子", "宠物", "孝敬长辈", "捐赠"], subcategoryKeywords: ["红包礼物": ["红包", "礼物"], "给家人": ["给家人"], "孩子": ["孩子"], "宠物": ["宠物"],
                "孝敬长辈": ["孝敬", "长辈", "孝敬父母", "给爸妈", "给父母", "给妈妈", "给爸爸"], "捐赠": ["捐款", "捐赠", "捐钱", "公益"]]),
        .init("保险税费", "checkmark.shield", subcategories: ["保险", "税费"], subcategoryKeywords: [
                "保险": ["保险", "交保险", "买保险", "交保费", "续保", "保费", "人寿", "车险", "医疗险"], "税费": ["个税", "税费", "缴税", "交税", "补税", "纳税", "印花税", "契税"]]),
        .init("利息手续费", "percent", subcategories: ["手续费", "利息"], subcategoryKeywords: ["手续费": ["手续费"], "利息": ["利息"]]),
        .init("其他支出", "ellipsis"),
        .init("工资奖金", "briefcase", income: true, subcategories: ["工资", "奖金", "补贴", "公积金"], subcategoryKeywords: ["工资": ["工资", "薪水", "薪资"], "奖金": ["奖金", "年终奖"], "补贴": ["补贴"], "公积金": ["公积金提取", "住房公积金", "提公积金", "取公积金"]]),
        .init("兼职劳务", "hammer", income: true, keywords: ["兼职", "稿费", "劳务"]),
        .init("礼金赠与", "gift", income: true, keywords: ["礼金", "赠与", "红包"]),
        .init("投资收益", "chart.line.uptrend.xyaxis", income: true, subcategories: ["利息", "基金股票"], subcategoryKeywords: ["利息": ["利息"], "基金股票": ["基金", "股票"]]),
        .init("报销", "receipt", income: true, keywords: ["报销", "差旅报销"]),
        .init("二手转卖", "arrow.triangle.2.circlepath", income: true, keywords: ["闲鱼", "转转", "二手", "回收", "卖闲置", "卖二手"]),
        .init("其他收入", "ellipsis", income: true),
        .init("内部移动", "arrow.left.arrow.right", system: true)
    ]
}
public struct Attachment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var createdAt = Dates.now
    private var bytes: Data
    public var data: Data {
        get { bytes }
        set { bytes = newValue; byteCount = newValue.count; checksum = nil; stagedChecksum = LedgerCodec.checksum(newValue); payloadURL = nil; payloadRepository = nil }
    }
    public private(set) var byteCount: Int
    var checksum: String?
    private var stagedChecksum: String?
    var payloadURL: URL?
    var payloadRepository: LedgerRepository?
    var payloadChecksum: String { checksum ?? stagedChecksum ?? LedgerCodec.checksum(bytes) }
    public init(name: String, data: Data) { self.name = name; bytes = data; byteCount = data.count; stagedChecksum = LedgerCodec.checksum(data) }
    mutating func unload(at url: URL, repository: LedgerRepository) {
        checksum = payloadChecksum; bytes = Data(); payloadURL = url; payloadRepository = repository
    }
    private enum CodingKeys: String, CodingKey { case id, name, createdAt, data, byteCount, checksum }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        let embedded = try c.decodeIfPresent(Data.self, forKey: .data)
        bytes = embedded ?? Data()
        byteCount = try c.decodeIfPresent(Int.self, forKey: .byteCount) ?? bytes.count
        checksum = try c.decodeIfPresent(String.self, forKey: .checksum)
        guard byteCount >= 0, byteCount <= LedgerCodec.capacity else { throw YubaiError.invalid("附件大小无效。") }
        if let embedded {
            stagedChecksum = LedgerCodec.checksum(embedded)
            guard byteCount == embedded.count, checksum.map({ $0 == stagedChecksum }) ?? true else { throw YubaiError.invalid("附件内容不完整。") }
            checksum = nil
        } else {
            guard c.contains(.byteCount), let checksum, checksum.count == 64,
                  checksum.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw YubaiError.invalid("附件缺少大小或校验信息。") }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(createdAt, forKey: .createdAt)
        try c.encode(byteCount, forKey: .byteCount)
        if encoder.userInfo[.ledgerMetadataOnly] as? Bool == true {
            try c.encode(payloadChecksum, forKey: .checksum)
        } else { try c.encode(data, forKey: .data) }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.createdAt == rhs.createdAt && lhs.byteCount == rhs.byteCount && lhs.payloadChecksum == rhs.payloadChecksum
    }
}
public struct ImportBatch: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var filename: String; public var importedAt = Dates.now
    public var importedCount: Int; public var duplicateCount: Int; public var skippedCount: Int
    public var attachmentID: UUID?; public var undoneAt: Date?
    public var needsOrganization: Bool?
    /// Successful request coverage, including rows intentionally left uncertain.
    /// Missing in older ledgers; classification alone is not a completion marker.
    public var organizedEntryIDs: Set<UUID>?
    public var organization: ImportOrganization?
    public var undo: ImportUndo?
    public init(filename: String, importedCount: Int, duplicateCount: Int, skippedCount: Int) { self.filename = filename; self.importedCount = importedCount; self.duplicateCount = duplicateCount; self.skippedCount = skippedCount }
}
public struct Preferences: Codable, Equatable, Sendable {
    // Legacy funds preferences: retained for archive compatibility, ignored by Finance.
    public var horizonDays = 90; public var emergencyReserve: Int64 = 0
    public var dailyLiving: Int64 = 0; public var hideAmounts = false; public var lockEnabled = false
    public var appearance = "system"; public var purchaseValues = "为长期有用和真正喜欢的事物花钱"
    public var colorTheme = "jade-vivid"
    /// Optional DeepSeek assistance; default off. Requires `DEEPSEEK_API_KEY` for now.
    public var cloudAIEnabled = false
    public var weeklyLetterPush = false
    public var butlerNotices: ButlerNoticePreferences?
    public var billExchangeRates: [ManualExchangeRate]?
    public var lastBillCurrency: BillCurrency?
    /// Nil, including an old ledger, means enabled.
    public var yearlyBillsSetAside: Bool?
    public var quickCapture = QuickCapturePreferences()
    public var categoryOrder: [String] = Category.defaults.filter { !$0.system }.map(\.name)
    public var onboardingComplete = false
    public var profileColdStartDone = false
    public var lastBackupAt: Date?
    public var weeklyAutoBackup: Bool?
    // Disabled flags let nil and false retain the old opt-in master-switch behavior.
    public var aiImportClassificationDisabled: Bool?
    public var aiAnswersDisabled: Bool?
    public var aiWeeklyReviewDisabled: Bool?
    public var aiReceiptRecognitionDisabled: Bool?
    public var butlerSuggestionsEnabled: Bool?
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case butlerNotices, billExchangeRates, lastBillCurrency, yearlyBillsSetAside, butlerSuggestionsEnabled
        case weeklyAutoBackup, aiImportClassificationDisabled, aiAnswersDisabled, aiWeeklyReviewDisabled, aiReceiptRecognitionDisabled
        case horizonDays, emergencyReserve, dailyLiving, hideAmounts, lockEnabled
        case appearance, purchaseValues, colorTheme, cloudAIEnabled, onboardingComplete, profileColdStartDone, weeklyLetterPush, quickCapture, lastBackupAt, categoryOrder
    }
    // Decode the former master switch without including it in newly encoded ledgers.
    private enum LegacyCodingKeys: String, CodingKey {
        case localAIEnabled
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        horizonDays = try values.decode(Int.self, forKey: .horizonDays)
        emergencyReserve = try values.decode(Int64.self, forKey: .emergencyReserve)
        dailyLiving = try values.decode(Int64.self, forKey: .dailyLiving)
        hideAmounts = try values.decode(Bool.self, forKey: .hideAmounts)
        lockEnabled = try values.decode(Bool.self, forKey: .lockEnabled)
        appearance = try values.decode(String.self, forKey: .appearance)
        purchaseValues = try values.decode(String.self, forKey: .purchaseValues)
        colorTheme = try values.decodeIfPresent(String.self, forKey: .colorTheme) ?? "jade-vivid"
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let wasEnabled = try legacy.decodeIfPresent(Bool.self, forKey: .localAIEnabled) ?? true
        cloudAIEnabled = (try values.decodeIfPresent(Bool.self, forKey: .cloudAIEnabled) ?? false) && wasEnabled
        weeklyLetterPush = try values.decodeIfPresent(Bool.self, forKey: .weeklyLetterPush) ?? false
        butlerNotices = try values.decodeIfPresent(ButlerNoticePreferences.self, forKey: .butlerNotices)
        billExchangeRates = try values.decodeIfPresent([ManualExchangeRate].self, forKey: .billExchangeRates)
        lastBillCurrency = try values.decodeIfPresent(BillCurrency.self, forKey: .lastBillCurrency)
        yearlyBillsSetAside = try values.decodeIfPresent(Bool.self, forKey: .yearlyBillsSetAside)
        categoryOrder = try values.decodeIfPresent([String].self, forKey: .categoryOrder) ?? categoryOrder
        quickCapture = try values.decodeIfPresent(QuickCapturePreferences.self, forKey: .quickCapture) ?? QuickCapturePreferences()
        onboardingComplete = try values.decode(Bool.self, forKey: .onboardingComplete)
        profileColdStartDone = try values.decodeIfPresent(Bool.self, forKey: .profileColdStartDone) ?? false
        lastBackupAt = try values.decodeIfPresent(Date.self, forKey: .lastBackupAt)
        weeklyAutoBackup = try values.decodeIfPresent(Bool.self, forKey: .weeklyAutoBackup)
        aiImportClassificationDisabled = try values.decodeIfPresent(Bool.self, forKey: .aiImportClassificationDisabled)
        aiAnswersDisabled = try values.decodeIfPresent(Bool.self, forKey: .aiAnswersDisabled)
        aiWeeklyReviewDisabled = try values.decodeIfPresent(Bool.self, forKey: .aiWeeklyReviewDisabled)
        aiReceiptRecognitionDisabled = try values.decodeIfPresent(Bool.self, forKey: .aiReceiptRecognitionDisabled)
        butlerSuggestionsEnabled = try values.decodeIfPresent(Bool.self, forKey: .butlerSuggestionsEnabled)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(horizonDays, forKey: .horizonDays); try c.encode(emergencyReserve, forKey: .emergencyReserve)
        try c.encode(dailyLiving, forKey: .dailyLiving); try c.encode(hideAmounts, forKey: .hideAmounts)
        try c.encode(lockEnabled, forKey: .lockEnabled); try c.encode(appearance, forKey: .appearance)
        try c.encode(purchaseValues, forKey: .purchaseValues); try c.encode(colorTheme, forKey: .colorTheme)
        try c.encode(cloudAIEnabled, forKey: .cloudAIEnabled); try c.encode(weeklyLetterPush, forKey: .weeklyLetterPush)
        try c.encodeIfPresent(butlerNotices, forKey: .butlerNotices)
        try c.encodeIfPresent(billExchangeRates, forKey: .billExchangeRates)
        try c.encodeIfPresent(lastBillCurrency, forKey: .lastBillCurrency)
        try c.encodeIfPresent(yearlyBillsSetAside, forKey: .yearlyBillsSetAside)
        try c.encode(quickCapture, forKey: .quickCapture); try c.encode(categoryOrder, forKey: .categoryOrder)
        try c.encode(onboardingComplete, forKey: .onboardingComplete); try c.encode(profileColdStartDone, forKey: .profileColdStartDone)
        try c.encodeIfPresent(lastBackupAt, forKey: .lastBackupAt)
        if weeklyAutoBackup == true { try c.encode(true, forKey: .weeklyAutoBackup) }
        if aiImportClassificationDisabled == true { try c.encode(true, forKey: .aiImportClassificationDisabled) }
        if aiAnswersDisabled == true { try c.encode(true, forKey: .aiAnswersDisabled) }
        if aiWeeklyReviewDisabled == true { try c.encode(true, forKey: .aiWeeklyReviewDisabled) }
        if aiReceiptRecognitionDisabled == true { try c.encode(true, forKey: .aiReceiptRecognitionDisabled) }
        try c.encodeIfPresent(butlerSuggestionsEnabled, forKey: .butlerSuggestionsEnabled)
    }
}
public struct AdviceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var createdAt = Dates.now; public var title: String; public var amount: Int64
    public var result: String; public var note: String
    public init(title: String, amount: Int64, result: String, note: String) { self.title = title; self.amount = amount; self.result = result; self.note = note }
}
public struct AreaMatch: Codable, Equatable, Sendable {
    public var categories: [String]; public var keywords: [String]; public var subcategories: [String]
    public init(categories: [String] = [], keywords: [String] = [], subcategories: [String] = []) {
        self.categories = categories; self.keywords = keywords; self.subcategories = subcategories
    }
    private enum CodingKeys: String, CodingKey { case categories, keywords, subcategories }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        subcategories = try c.decodeIfPresent([String].self, forKey: .subcategories) ?? []
    }
}
public struct SoftLimit: Codable, Equatable, Sendable {
    public var perWeekCount: Int?; public var perMonthAmount: Int64?
    public init(perWeekCount: Int? = nil, perMonthAmount: Int64? = nil) { self.perWeekCount = perWeekCount; self.perMonthAmount = perMonthAmount }
}
public struct ProfileArea: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var match: AreaMatch
    public var note: String; public var softLimit: SoftLimit?; public var confirmedAt: Date?
    public init(title: String, match: AreaMatch = AreaMatch(), note: String = "", softLimit: SoftLimit? = nil, confirmedAt: Date? = nil) {
        self.title = title; self.match = match; self.note = note; self.softLimit = softLimit; self.confirmedAt = confirmedAt
    }
    private enum CodingKeys: String, CodingKey { case id, title, match, note, softLimit, confirmedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        match = try c.decode(AreaMatch.self, forKey: .match); note = try c.decode(String.self, forKey: .note)
        softLimit = try c.decodeIfPresent(SoftLimit.self, forKey: .softLimit)
        confirmedAt = try c.decodeIfPresent(Date.self, forKey: .confirmedAt)
    }
}
public struct SpendingProfile: Codable, Equatable, Sendable {
    public var generous: [ProfileArea] = []; public var restrain: [ProfileArea] = []
    public var principles: [String] = []; public var floorAmount: Int64?; public var updatedAt = Dates.now
    public var principleDates: [String: Date] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case generous, restrain, principles, floorAmount, updatedAt, principleDates }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generous = try c.decode([ProfileArea].self, forKey: .generous); restrain = try c.decode([ProfileArea].self, forKey: .restrain)
        principles = try c.decode([String].self, forKey: .principles); floorAmount = try c.decodeIfPresent(Int64.self, forKey: .floorAmount)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        principleDates = try c.decodeIfPresent([String: Date].self, forKey: .principleDates) ?? [:]
    }
    public mutating func stamp(changedFrom old: SpendingProfile, at date: Date) {
        func stamped(_ areas: [ProfileArea], previous: [ProfileArea]) -> [ProfileArea] {
            areas.map { area in
                var next = area
                let prior = previous.first { $0.id == area.id }
                next.confirmedAt = prior?.confirmedAt
                if let prior {
                    if next != prior { next.confirmedAt = date }
                } else { next.confirmedAt = date }
                return next
            }
        }
        generous = stamped(generous, previous: old.generous); restrain = stamped(restrain, previous: old.restrain)
        principleDates = principleDates.filter { principles.contains($0.key) }
        for text in principles {
            if !old.principles.contains(text) { principleDates[text] = date }
            else { principleDates[text] = old.principleDates[text] }
        }
        if self != old { updatedAt = date }
    }
}
public enum MemoryKind: String, Codable, CaseIterable, Hashable, Sendable { case plan, value, life }
public enum MemorySource: String, Codable, CaseIterable, Sendable {
    case chat, followUp, importAnswer, feedback, reflection, user
    public var label: String {
        switch self {
        case .chat: "聊天时"
        case .followUp: "买了一个月 · 用得怎么样？"
        case .importAnswer: "导入时问过"
        case .feedback: "你点过的提醒"
        case .reflection: "每周来信"
        case .user: "你写的"
        }
    }
}
public struct MemoryNote: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID; public var text: String; public var kind: MemoryKind; public var source: MemorySource
    public var createdAt: Date; public var updatedAt: Date; public var previousText: String?
    public var lastUsedAt: Date?; public var evidence: [UUID]
    public init(id: UUID = UUID(), text: String, kind: MemoryKind, source: MemorySource,
                createdAt: Date = Dates.now, updatedAt: Date? = nil, previousText: String? = nil,
                lastUsedAt: Date? = nil, evidence: [UUID] = []) {
        self.id = id; self.text = text; self.kind = kind; self.source = source
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt; self.previousText = previousText
        self.lastUsedAt = lastUsedAt; self.evidence = evidence
    }
}
public enum CategoryMemory {
    public static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"[\p{N}\p{P}]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func directions(_ path: String, in ledger: Ledger) -> [Bool] {
        let choice = CategoryAssignment(path: path)
        let direct = [false, true].filter { income in
            let value = ledger.categoryAssignment(category: choice.category, subcategory: choice.subcategory, income: income)
            return ledger.categories.contains { $0.name == value.category && $0.income == income }
        }
        if !direct.isEmpty { return direct }
        let legacy = CategoryMigration.canonical(choice.category)
        return [false, true].filter { income in ledger.categories.contains { $0.name == legacy.category && $0.income == income } }
    }
    public static func value(_ key: String, income: Bool, in ledger: Ledger) -> String? {
        ledger.classificationMemory[CategoryNamespace.key(key, income: income)] ?? ledger.classificationMemory[key]
    }
    public static func store(_ path: String, key: String, income: Bool, in ledger: inout Ledger) {
        let category = CategoryAssignment(path: path).category
        let scoped = CategoryNamespace.key(key, income: income)
        if let old = ledger.classificationMemory[key] {
            let directions = Set(self.directions(old, in: ledger))
            if directions == [!income] {
                ledger.classificationMemory.removeValue(forKey: key)
                ledger.classificationMemory[CategoryNamespace.key(key, income: !income)] = old
                ledger.classificationMemory[scoped] = path; return
            }
        }
        if ledger.classificationMemory[scoped] != nil || ledger.classificationMemory[CategoryNamespace.key(key, income: !income)] != nil || ledger.categories.contains(where: { $0.name == category && $0.income != income }) {
            ledger.classificationMemory[scoped] = path
        } else { ledger.classificationMemory[key] = path }
    }
    public static func remember(_ entry: Entry, includingParty: Bool = false, in ledger: inout Ledger) {
        let choice = ledger.normalizedCategory(for: entry)
        guard !Classification.isPending(choice.category), ledger.categories.contains(where: { $0.name == choice.category && $0.income == entry.nature.categoryIncome && !$0.system }) else { return }
        for key in SubcategoryClassifier.keys(entry) { store(choice.path, key: key, income: entry.nature.categoryIncome, in: &ledger) }
        if includingParty {
            let key = self.key(UnsortedGroups.party(for: entry))
            if !key.isEmpty { store(choice.path, key: key, income: entry.nature.categoryIncome, in: &ledger) }
        }
    }
}
public enum CardKind: String, Codable, CaseIterable, Sendable {
    case answerQuestion, restrain, shortfall, unknownInflow, staleBalance, recurring, duplicate, offCharacter, followUp, cooldownDue, weeklyLetter
}
public enum CardAction: Codable, Equatable, Sendable {
    case openEvidence, confirmChangeSet(UUID), reconcileAccount(UUID), answerQuestion, openWish(UUID)
}
public enum CardFeedback: String, Codable, Sendable { case worth, regret }
public struct ButlerCard: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var kind: CardKind; public var title: String; public var body: String
    public var evidence: [UUID]; public var action: CardAction?; public var dedupeKey: String
    public var createdAt = Dates.now; public var dismissedAt: Date?; public var feedback: CardFeedback?
    public var importQuestion: ImportQuestion?
    public var facts: [CardFact]?
    public var areaID: UUID?
    public var priority: Int?
    public var letter: LetterFacts?
    public var feedbackAt: Date?
    public var feedbackProposalID: UUID?
    public var meta: String?
    public init(kind: CardKind, title: String, body: String, evidence: [UUID] = [], action: CardAction? = nil, dedupeKey: String) {
        self.kind = kind; self.title = title; self.body = body; self.evidence = evidence; self.action = action; self.dedupeKey = dedupeKey
    }
}
public enum WishStatus: String, Codable, CaseIterable, Sendable { case thinking, bought, dropped }
public struct WishItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var amount: Int64; public var purpose: String
    public var createdAt = Dates.now; public var status: WishStatus = .thinking; public var judgment: String
    public var boughtEntryID: UUID?; public var followUpAt: Date?; public var followUpAnswer: String?
    public var followUpAnsweredAt: Date?
    public var coolUntil: Date?
    public var droppedAt: Date?
    public var source: String?
    public var category: String?
    public var subcategory: String?
    public init(title: String, amount: Int64, purpose: String = "", judgment: String = "") {
        self.title = title; self.amount = amount; self.purpose = purpose; self.judgment = judgment
    }
    init(_ advice: AdviceRecord) {
        self.init(title: advice.title, amount: advice.amount, purpose: advice.note, judgment: advice.result)
        id = advice.id; createdAt = advice.createdAt
    }
}
public enum CycleAnchor: String, Codable, Sendable { case payday, calendarMonth }

public struct Ledger: Codable, Equatable, Sendable {
    // Every stored domain field invalidates the cache, including nested array/
    // struct edits. Keep this observer when adding fields; copies then stay isolated.
    var calculations = LedgerCalculations()
    public var schema = 4 { didSet { calculations = LedgerCalculations() } }
    public var id = UUID() { didSet { calculations = LedgerCalculations() } }
    public var updatedAt = Date() { didSet { calculations = LedgerCalculations() } }
    public var isSample = false { didSet { calculations = LedgerCalculations() } }
    public var accounts: [Account] = [] { didSet { calculations = LedgerCalculations() } }
    public var entries: [Entry] = [] { didSet { calculations = LedgerCalculations() } }
    public var plans: [Plan] = [] { didSet { calculations = LedgerCalculations() } }
    public var spendingParts: [SpendingPart] = [] { didSet { calculations = LedgerCalculations() } }
    public var partsMode: PartsMode = .amount { didSet { calculations = LedgerCalculations() } }
    public var partLeftover: PartLeftover = .mergeIntoFixedSavings { didSet { calculations = LedgerCalculations() } }
    public var partCarry: [UUID: Int64] = [:] { didSet { calculations = LedgerCalculations() } }
    public var partCarryCycleStart: Date? { didSet { calculations = LedgerCalculations() } }
    /// nil preserves the automatic schedule used by existing ledgers.
    public var cycleAnchor: CycleAnchor? { didSet { calculations = LedgerCalculations() } }
    public var paydayConfirmSince: Date? { didSet { calculations = LedgerCalculations() } }
    public var salarySetupDeferral: SalarySetupDeferral? { didSet { calculations = LedgerCalculations() } }
    public var cycleCovers: [CycleCover] = [] { didSet { calculations = LedgerCalculations() } }
    public var reserveAdjustments: [ReserveAdjustment] = [] { didSet { calculations = LedgerCalculations() } }
    public var savingsTransfers: [SavingsTransfer] = [] { didSet { calculations = LedgerCalculations() } }
    public var savingsTopupDecisions: [SavingsTopupDecision] = [] { didSet { calculations = LedgerCalculations() } }
    public var reservePaybacks: [ReservePayback]? { didSet { calculations = LedgerCalculations() } }
    public var repeatPreferences: [RepeatPreference]? { didSet { calculations = LedgerCalculations() } }
    /// User-set base plus closed-cycle merges. Read fixedSavingsTotal(now:) for
    /// the total including earmarked income; recording income never changes this base.
    public var fixedSavings: Int64? { didSet { calculations = LedgerCalculations() } }
    public var savingRule: SavingRule? {
        didSet {
            switch savingRule {
            case .fixed(let amount): lastFixedSavingTarget = amount
            case .share(let percent): lastSavingSharePercent = percent
            case nil: break
            }
            calculations = LedgerCalculations()
        }
    }
    public var lastFixedSavingTarget: Int64? { didSet { calculations = LedgerCalculations() } }
    public var lastSavingSharePercent: Int? { didSet { calculations = LedgerCalculations() } }
    public var savingHistory: [CycleSaving] = [] { didSet { calculations = LedgerCalculations() } }
    public var goals: [Goal] = [] { didSet { calculations = LedgerCalculations() } }
    public var rents: [Rent] = [] { didSet { calculations = LedgerCalculations() } }
    public var categories = Category.defaults { didSet { calculations = LedgerCalculations() } }
    public var imports: [ImportBatch] = [] { didSet { calculations = LedgerCalculations() } }
    public var attachments: [Attachment] = [] { didSet { calculations = LedgerCalculations() } }
    public var categoryAliases: [String: String] = [:] { didSet { calculations = LedgerCalculations() } }
    /// Independent of the file schema; older readers safely ignore this field.
    public var defaultCategoriesVersion: Int? = CategoryMigration.currentDefaultsVersion { didSet { calculations = LedgerCalculations() } }
    public var manualNotesMerged = true { didSet { calculations = LedgerCalculations() } }
    public var classificationMemory: [String: String] = [:] { didSet { calculations = LedgerCalculations() } }
    // Source-compatible projections backed by the same store, never encoded.
    public var categoryMemory: [String: String] {
        get { classificationMemory.mapValues { CategoryAssignment(path: $0).category } }
        set {
            var merged = newValue
            for (key, old) in classificationMemory where CategoryAssignment(path: old).category == newValue[key] { merged[key] = old }
            classificationMemory = merged
        }
    }
    public var subcategoryMemory: [String: String] {
        get { classificationMemory.filter { CategoryAssignment(path: $0.value).subcategory != nil } }
        set {
            for (key, value) in classificationMemory where CategoryAssignment(path: value).subcategory != nil && newValue[key] == nil {
                classificationMemory[key] = CategoryAssignment(path: value).category
            }
            classificationMemory.merge(newValue) { _, new in new }
        }
    }
    public var lastSubcategoryBatchDay: String? { didSet { calculations = LedgerCalculations() } }
    public var subscriptionChecks: [String: String] = [:] { didSet { calculations = LedgerCalculations() } }
    public var stoppedSubscriptions: [StoppedSubscription] = [] { didSet { calculations = LedgerCalculations() } }
    public var butlerSavings: [ButlerSaving] = [] { didSet { calculations = LedgerCalculations() } }
    public var butlerAnswers: [String: Date] = [:] { didSet { calculations = LedgerCalculations() } }
    public var dismissedSalaryKeys: Set<String> = [] { didSet { calculations = LedgerCalculations() } }
    public var memories: [MemoryNote] = [] { didSet { calculations = LedgerCalculations() } }
    public var lastReflectionWeek: String? { didSet { calculations = LedgerCalculations() } }
    public var butlerAI: ButlerAIState? { didSet { calculations = LedgerCalculations() } }
    public var preferences = Preferences() { didSet { calculations = LedgerCalculations() } }
    public var profile = SpendingProfile() { didSet { calculations = LedgerCalculations() } }
    public var cards: [ButlerCard] = [] { didSet { calculations = LedgerCalculations() } }
    public var pendingChanges: [ChangeSet] = [] { didSet { calculations = LedgerCalculations() } }
    public var wishlist: [WishItem] = [] { didSet { calculations = LedgerCalculations() } }
    public var mutedTopics: [String] = [] { didSet { calculations = LedgerCalculations() } }
    // Only retained for restoring a legacy backup into a repository; never encoded.
    var preMigrationData: Data? { didSet { calculations = LedgerCalculations() } }
    // Compatibility for the old purchase screen until its replacement. Writes persist as wishes.
    public var advice: [AdviceRecord] {
        get { wishlist.map { wish in
            var record = AdviceRecord(title: wish.title, amount: wish.amount, result: wish.judgment, note: wish.purpose)
            record.id = wish.id; record.createdAt = wish.createdAt; return record
        } }
        set { wishlist = newValue.map { record in
            var wish = wishlist.first { $0.id == record.id } ?? WishItem(record)
            wish.title = record.title; wish.amount = record.amount; wish.judgment = record.result; wish.purpose = record.note
            return wish
        } }
    }
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case butlerSavings, butlerAnswers, salarySetupDeferral, butlerAI
        case savingsTransfers, savingsTopupDecisions, reservePaybacks, repeatPreferences, paydayConfirmSince, cycleCovers, reserveAdjustments, cycleAnchor, lastFixedSavingTarget, lastSavingSharePercent, spendingParts, partsMode, partLeftover, partCarry, partCarryCycleStart, fixedSavings, savingRule, savingHistory, schema, id, updatedAt, isSample, accounts, entries, plans, goals, rents, categories, imports, attachments, categoryAliases, defaultCategoriesVersion, manualNotesMerged, categoryMemory, subcategoryMemory, classificationMemory, lastSubcategoryBatchDay, subscriptionChecks, stoppedSubscriptions, dismissedSalaryKeys, memories, lastReflectionWeek, preferences, profile, cards, pendingChanges, wishlist, mutedTopics
    }
    private enum LegacyKeys: String, CodingKey { case advice }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        guard (1...4).contains(schema) else { throw YubaiError.invalid("这个账本来自更新版本，请先更新余白。") }
        let legacy = schema == 1
        let needsCategoryMigration = schema < 4
        id = try c.decode(UUID.self, forKey: .id)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isSample = try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? isSample
        accounts = try c.decode([Account].self, forKey: .accounts)
        entries = try c.decode([Entry].self, forKey: .entries)
        plans = try c.decode([Plan].self, forKey: .plans)
        goals = try c.decode([Goal].self, forKey: .goals)
        rents = try c.decode([Rent].self, forKey: .rents)
        // Legacy `rules` JSON is intentionally ignored and omitted on the next save.
        categories = try c.decode([Category].self, forKey: .categories)
        imports = try c.decode([ImportBatch].self, forKey: .imports)
        attachments = try c.decode([Attachment].self, forKey: .attachments)
        categoryAliases = try c.decodeIfPresent([String: String].self, forKey: .categoryAliases) ?? categoryAliases
        defaultCategoriesVersion = try c.decodeIfPresent(Int.self, forKey: .defaultCategoriesVersion)
        let oldMain = try c.decodeIfPresent([String: String].self, forKey: .categoryMemory) ?? [:]
        let oldSmall = try c.decodeIfPresent([String: String].self, forKey: .subcategoryMemory) ?? [:]
        classificationMemory = try c.decodeIfPresent([String: String].self, forKey: .classificationMemory) ?? [:]
        lastSubcategoryBatchDay = try c.decodeIfPresent(String.self, forKey: .lastSubcategoryBatchDay)
        subscriptionChecks = try c.decodeIfPresent([String: String].self, forKey: .subscriptionChecks) ?? [:]
        stoppedSubscriptions = try c.decodeIfPresent([StoppedSubscription].self, forKey: .stoppedSubscriptions) ?? []
        dismissedSalaryKeys = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedSalaryKeys) ?? []
        memories = try c.decodeIfPresent([MemoryNote].self, forKey: .memories) ?? []
        lastReflectionWeek = try c.decodeIfPresent(String.self, forKey: .lastReflectionWeek)
        butlerAI = try c.decodeIfPresent(ButlerAIState.self, forKey: .butlerAI)
        preferences = try c.decode(Preferences.self, forKey: .preferences)
        profile.updatedAt = updatedAt
        profile = try c.decodeIfPresent(SpendingProfile.self, forKey: .profile) ?? profile
        // Preserve legacy reserves from both schema 1 and older schema 2 ledgers.
        if profile.floorAmount == nil && preferences.emergencyReserve > 0 {
            profile.floorAmount = preferences.emergencyReserve
        }
        spendingParts = try c.decodeIfPresent([SpendingPart].self, forKey: .spendingParts) ?? []
        partsMode = try c.decodeIfPresent(PartsMode.self, forKey: .partsMode) ?? .amount
        partLeftover = try c.decodeIfPresent(PartLeftover.self, forKey: .partLeftover) ?? .mergeIntoFixedSavings
        partCarry = try c.decodeIfPresent([UUID: Int64].self, forKey: .partCarry) ?? [:]
        partCarryCycleStart = try c.decodeIfPresent(Date.self, forKey: .partCarryCycleStart)
        cycleAnchor = try c.decodeIfPresent(CycleAnchor.self, forKey: .cycleAnchor)
        paydayConfirmSince = try c.decodeIfPresent(Date.self, forKey: .paydayConfirmSince)
        salarySetupDeferral = try c.decodeIfPresent(SalarySetupDeferral.self, forKey: .salarySetupDeferral)
        cycleCovers = try c.decodeIfPresent([CycleCover].self, forKey: .cycleCovers) ?? []
        reserveAdjustments = try c.decodeIfPresent([ReserveAdjustment].self, forKey: .reserveAdjustments) ?? []
        savingsTransfers = try c.decodeIfPresent([SavingsTransfer].self, forKey: .savingsTransfers) ?? []
        savingsTopupDecisions = try c.decodeIfPresent([SavingsTopupDecision].self, forKey: .savingsTopupDecisions) ?? []
        reservePaybacks = try c.decodeIfPresent([ReservePayback].self, forKey: .reservePaybacks)
        repeatPreferences = try c.decodeIfPresent([RepeatPreference].self, forKey: .repeatPreferences)
        fixedSavings = try c.decodeIfPresent(Int64.self, forKey: .fixedSavings) ?? profile.floorAmount
        savingRule = try c.decodeIfPresent(SavingRule.self, forKey: .savingRule)
        lastFixedSavingTarget = try c.decodeIfPresent(Int64.self, forKey: .lastFixedSavingTarget)
        lastSavingSharePercent = try c.decodeIfPresent(Int.self, forKey: .lastSavingSharePercent)
        // Property observers do not run during decoding. Seed memory from the active rule in old backups too.
        switch savingRule {
        case .fixed(let amount): lastFixedSavingTarget = amount
        case .share(let percent): lastSavingSharePercent = percent
        case nil: break
        }
        savingHistory = try c.decodeIfPresent([CycleSaving].self, forKey: .savingHistory) ?? []
        butlerSavings = try c.decodeIfPresent([ButlerSaving].self, forKey: .butlerSavings) ?? []
        butlerAnswers = try c.decodeIfPresent([String: Date].self, forKey: .butlerAnswers) ?? [:]
        cards = try c.decodeIfPresent([ButlerCard].self, forKey: .cards) ?? cards
        pendingChanges = try c.decodeIfPresent([ChangeSet].self, forKey: .pendingChanges) ?? pendingChanges
        wishlist = try c.decodeIfPresent([WishItem].self, forKey: .wishlist) ?? wishlist
        mutedTopics = try c.decodeIfPresent([String].self, forKey: .mutedTopics) ?? mutedTopics
        let old = try decoder.container(keyedBy: LegacyKeys.self)
        let records = try old.decodeIfPresent([AdviceRecord].self, forKey: .advice) ?? []
        guard Set(records.map(\.id)).count == records.count else { throw YubaiError.invalid("旧购买记录包含重复标识。") }
        for record in records where !wishlist.contains(where: { $0.id == record.id }) { wishlist.append(WishItem(record)) }
        if legacy, preferences.purchaseValues != "为长期有用和真正喜欢的事物花钱",
           !profile.principles.contains(preferences.purchaseValues) {
            profile.principles.insert(preferences.purchaseValues, at: 0)
        }
        // Deterministic legacy precedence: main < merchant < subcategory < new store.
        var importedMemory: [String: String] = [:]
        for (index, source) in [oldMain, preferences.quickCapture.merchantCategories, oldSmall, classificationMemory].enumerated() {
            for key in source.keys.sorted() {
                let scoped: (name: String, income: Bool?) = index == 3 ? CategoryNamespace.split(key) : (key, nil)
                let plain = CategoryMemory.key(scoped.name)
                let normalized = scoped.income.map { CategoryNamespace.key(plain, income: $0) } ?? plain
                if !normalized.isEmpty { importedMemory[normalized] = source[key] }
            }
        }
        classificationMemory = importedMemory
        preferences.quickCapture.merchantCategories = [:]
        if needsCategoryMigration { CategoryMigration.apply(to: &self) }
        CategoryMigration.addMissingDefaults(to: &self)
        CategoryMigration.upgradeKeywords(to: &self)
        manualNotesMerged = try c.decodeIfPresent(Bool.self, forKey: .manualNotesMerged) ?? false
        ManualNoteMigration.apply(to: &self)
        schema = 4
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(4, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(isSample, forKey: .isSample)
        try c.encode(accounts, forKey: .accounts)
        try c.encode(entries, forKey: .entries)
        try c.encode(plans, forKey: .plans)
        try c.encode(spendingParts, forKey: .spendingParts)
        try c.encode(partsMode, forKey: .partsMode)
        try c.encode(partLeftover, forKey: .partLeftover)
        try c.encode(partCarry, forKey: .partCarry)
        try c.encodeIfPresent(partCarryCycleStart, forKey: .partCarryCycleStart)
        try c.encodeIfPresent(cycleAnchor, forKey: .cycleAnchor)
        try c.encodeIfPresent(paydayConfirmSince, forKey: .paydayConfirmSince)
        try c.encodeIfPresent(salarySetupDeferral, forKey: .salarySetupDeferral)
        if !cycleCovers.isEmpty { try c.encode(cycleCovers, forKey: .cycleCovers) }
        if !reserveAdjustments.isEmpty { try c.encode(reserveAdjustments, forKey: .reserveAdjustments) }
        if !savingsTransfers.isEmpty { try c.encode(savingsTransfers, forKey: .savingsTransfers) }
        if !savingsTopupDecisions.isEmpty { try c.encode(savingsTopupDecisions, forKey: .savingsTopupDecisions) }
        if let reservePaybacks, !reservePaybacks.isEmpty { try c.encode(reservePaybacks, forKey: .reservePaybacks) }
        if let repeatPreferences, !repeatPreferences.isEmpty { try c.encode(repeatPreferences, forKey: .repeatPreferences) }
        try c.encodeIfPresent(fixedSavings, forKey: .fixedSavings)
        try c.encodeIfPresent(savingRule, forKey: .savingRule)
        try c.encodeIfPresent(lastFixedSavingTarget, forKey: .lastFixedSavingTarget)
        try c.encodeIfPresent(lastSavingSharePercent, forKey: .lastSavingSharePercent)
        try c.encode(savingHistory, forKey: .savingHistory)
        try c.encode(goals, forKey: .goals)
        try c.encode(rents, forKey: .rents)
        try c.encode(categories, forKey: .categories)
        try c.encode(imports, forKey: .imports)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(categoryAliases, forKey: .categoryAliases)
        try c.encodeIfPresent(defaultCategoriesVersion, forKey: .defaultCategoriesVersion)
        try c.encode(manualNotesMerged, forKey: .manualNotesMerged)
        try c.encode(classificationMemory, forKey: .classificationMemory)
        try c.encodeIfPresent(lastSubcategoryBatchDay, forKey: .lastSubcategoryBatchDay)
        try c.encode(subscriptionChecks, forKey: .subscriptionChecks)
        try c.encode(stoppedSubscriptions, forKey: .stoppedSubscriptions)
        if !butlerSavings.isEmpty { try c.encode(butlerSavings, forKey: .butlerSavings) }
        if !butlerAnswers.isEmpty { try c.encode(butlerAnswers, forKey: .butlerAnswers) }
        try c.encode(dismissedSalaryKeys.sorted(), forKey: .dismissedSalaryKeys)
        try c.encode(memories, forKey: .memories)
        try c.encodeIfPresent(lastReflectionWeek, forKey: .lastReflectionWeek)
        try c.encodeIfPresent(butlerAI, forKey: .butlerAI)
        try c.encode(preferences, forKey: .preferences)
        try c.encode(profile, forKey: .profile)
        try c.encode(cards, forKey: .cards)
        try c.encode(pendingChanges, forKey: .pendingChanges)
        try c.encode(wishlist, forKey: .wishlist)
        try c.encode(mutedTopics, forKey: .mutedTopics)
    }
    public static func == (lhs: Ledger, rhs: Ledger) -> Bool {
        lhs.schema == rhs.schema &&
        lhs.id == rhs.id &&
        lhs.updatedAt == rhs.updatedAt &&
        lhs.isSample == rhs.isSample &&
        lhs.accounts == rhs.accounts &&
        lhs.entries == rhs.entries &&
        lhs.plans == rhs.plans &&
        lhs.spendingParts == rhs.spendingParts &&
        lhs.partsMode == rhs.partsMode &&
        lhs.partLeftover == rhs.partLeftover &&
        lhs.partCarry == rhs.partCarry &&
        lhs.partCarryCycleStart == rhs.partCarryCycleStart &&
        lhs.cycleAnchor == rhs.cycleAnchor &&
        lhs.paydayConfirmSince == rhs.paydayConfirmSince &&
        lhs.salarySetupDeferral == rhs.salarySetupDeferral &&
        lhs.cycleCovers == rhs.cycleCovers &&
        lhs.reserveAdjustments == rhs.reserveAdjustments &&
        lhs.savingsTransfers == rhs.savingsTransfers &&
        lhs.savingsTopupDecisions == rhs.savingsTopupDecisions &&
        lhs.reservePaybacks == rhs.reservePaybacks &&
        lhs.repeatPreferences == rhs.repeatPreferences &&
        lhs.fixedSavings == rhs.fixedSavings &&
        lhs.savingRule == rhs.savingRule &&
        lhs.lastFixedSavingTarget == rhs.lastFixedSavingTarget &&
        lhs.lastSavingSharePercent == rhs.lastSavingSharePercent &&
        lhs.savingHistory == rhs.savingHistory &&
        lhs.goals == rhs.goals &&
        lhs.rents == rhs.rents &&
        lhs.categories == rhs.categories &&
        lhs.imports == rhs.imports &&
        lhs.attachments == rhs.attachments &&
        lhs.categoryAliases == rhs.categoryAliases &&
        lhs.defaultCategoriesVersion == rhs.defaultCategoriesVersion &&
        lhs.manualNotesMerged == rhs.manualNotesMerged &&
        lhs.classificationMemory == rhs.classificationMemory &&
        lhs.lastSubcategoryBatchDay == rhs.lastSubcategoryBatchDay &&
        lhs.subscriptionChecks == rhs.subscriptionChecks &&
        lhs.stoppedSubscriptions == rhs.stoppedSubscriptions &&
        lhs.butlerSavings == rhs.butlerSavings &&
        lhs.butlerAnswers == rhs.butlerAnswers &&
        lhs.dismissedSalaryKeys == rhs.dismissedSalaryKeys &&
        lhs.memories == rhs.memories &&
        lhs.lastReflectionWeek == rhs.lastReflectionWeek &&
        lhs.butlerAI == rhs.butlerAI &&
        lhs.preferences == rhs.preferences &&
        lhs.profile == rhs.profile &&
        lhs.cards == rhs.cards &&
        lhs.pendingChanges == rhs.pendingChanges &&
        lhs.wishlist == rhs.wishlist &&
        lhs.mutedTopics == rhs.mutedTopics
    }
    public var activeEntries: [Entry] { entries.filter { $0.deletedAt == nil } }
    public func accountName(_ id: UUID?) -> String { accounts.first { $0.id == id }?.name ?? "未指定账户" }
    public func resolveCategory(_ category: String, income: Bool) -> String {
        let value = CategoryAssignment(path: category)
        return categoryAssignment(category: value.category, subcategory: value.subcategory, income: income).category
    }
    public func validate() throws {
        if calculations.isValidated { return }
        guard (1...4).contains(schema) else { throw YubaiError.invalid("这个账本来自更新版本，请先更新余白。") }
        guard accounts.count <= 1000, entries.count <= 200_000, plans.count <= 1000, rents.count <= 100,
              goals.count <= 1000, attachments.count <= 5000, cards.count <= 5000,
              pendingChanges.count <= 100, wishlist.count <= 5000, mutedTopics.count <= 5000 else { throw YubaiError.invalid("账本超出安全容量，请分卷备份。") }
        guard Set(accounts.map(\.id)).count == accounts.count, Set(entries.map(\.id)).count == entries.count,
              Set(plans.map(\.id)).count == plans.count, Set(rents.map(\.id)).count == rents.count,
              Set(goals.map(\.id)).count == goals.count,
              Set(imports.map(\.id)).count == imports.count,
              Set(attachments.map(\.id)).count == attachments.count else { throw YubaiError.invalid("账本包含重复标识，无法安全读取。") }
        guard Set(cards.map(\.id)).count == cards.count, Set(wishlist.map(\.id)).count == wishlist.count,
              Set(pendingChanges.map(\.id)).count == pendingChanges.count,
              Set(mutedTopics).count == mutedTopics.count else { throw YubaiError.invalid("画像、卡片或修改包含重复标识。") }
        try FixedFlows.validateCurrencies(in: self)
        let ids = Set(accounts.map(\.id)); let categoryNames = categories.map(\.id)
        func dateValid(_ value: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(value.timeIntervalSince1970) }
        guard butlerSavings.count <= 10_000, butlerAnswers.count <= 20_000,
              Set(butlerSavings.map(\.id)).count == butlerSavings.count,
              butlerSavings.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && !$0.item.isEmpty && $0.item.count <= 4000 &&
                  (1...Money.limit).contains($0.amount) && dateValid($0.date) && ($0.undoneAt.map(dateValid) ?? true) && ($0.endedAt.map(dateValid) ?? true) }),
              butlerAnswers.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 2000 && dateValid($0.value) })
        else { throw YubaiError.invalid("省下的钱或管家记录无效。") }
        for record in butlerSavings {
            guard record.endedAt.map({ $0 >= record.date }) ?? true,
                  record.undoneAt.map({ $0 >= record.date }) ?? true,
                  record.waitedHours.map({ $0 >= 0 }) ?? true else { throw YubaiError.invalid("省下的钱或管家记录无效。") }
            if let plan = record.plan {
                guard (plan.currency != .cny || plan.amount == record.amount), !plan.title.isEmpty, plan.nature == .expense, !plan.inflow,
                      plan.frequency != .once, record.cadence == .from(plan.frequency), dateValid(plan.dueDate),
                      plan.endDate.map(dateValid) ?? true, plan.installments.map({ $0 > 0 }) ?? true
                else { throw YubaiError.invalid("省下的钱或管家记录无效。") }
            }
        }
        let partCategories = spendingParts.flatMap(\.categories)
        guard spendingParts.count <= 1000, Set(spendingParts.map(\.id)).count == spendingParts.count,
              !spendingParts.contains(where: { $0.id == SpendingPart.unassignedID }),
              Set(partCategories).count == partCategories.count,
              spendingParts.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 100 &&
                  ($0.amount.map { (0...Money.limit).contains($0) } ?? true) && ($0.share.map { (1...10).contains($0) } ?? true) }),
              spendingParts.compactMap(\.share).reduce(0, +) <= 10,
              partCarry.values.allSatisfy({ (0...Money.limit).contains($0) }), partCarryCycleStart.map(dateValid) ?? true
        else { throw YubaiError.invalid("分项的金额、成数或分类无效。") }
        guard fixedSavings.map({ (0...Money.limit).contains($0) }) ?? true,
              savingRule?.isValid ?? true,
              lastFixedSavingTarget.map({ SavingRule.fixed($0).isValid }) ?? true,
              lastSavingSharePercent.map({ SavingRule.share($0).isValid }) ?? true,
              savingHistory.count <= 5000,
              Set(savingHistory.map(\.cycleStart)).count == savingHistory.count,
              savingHistory.allSatisfy({ dateValid($0.cycleStart) && dateValid($0.cycleEnd) && $0.cycleStart <= $0.cycleEnd &&
                  (0...Money.limit).contains($0.income) && (0...Money.limit).contains($0.target) && (0...$0.target).contains($0.saved) &&
                  (0...Money.limit).contains($0.leftover) && ($0.unspent.map { (0...Money.limit).contains($0) } ?? true) })
        else { throw YubaiError.invalid("攒钱的金额或周期无效。") }
        guard paydayConfirmSince.map(dateValid) ?? true,
              salarySetupDeferral.map({ dateValid($0.deferredAt) && $0.postedIncomeIDs.count <= 1_000_000 }) ?? true,
              Set(cycleCovers.map(\.id)).count == cycleCovers.count,
              cycleCovers.allSatisfy({ dateValid($0.cycleStart) && dateValid($0.date) && (1...Money.limit).contains($0.amount) }),
              Set(reserveAdjustments.map(\.id)).count == reserveAdjustments.count,
              reserveAdjustments.allSatisfy({ dateValid($0.date) && (-Money.limit...Money.limit).contains($0.delta) })
        else { throw YubaiError.invalid("攒钱的金额或周期无效。") }
        try Reserve.validatePaybacks(in: self)
        try Reserve.validateFlexibleSavings(in: self)
        try EntryHistory.validateRepeatPreferences(in: self)
        guard preferences.lastBackupAt.map(dateValid) ?? true else { throw YubaiError.invalid("上次备份时间无效。") }
        guard Set(memories.map(\.id)).count == memories.count else { throw YubaiError.invalid("记忆包含重复标识。") }
        for note in memories { try Memory.validate(note) }
        if let week = lastReflectionWeek {
            guard MemoryReflection.validWeek(week) else { throw YubaiError.invalid("每周来信的周次无效。") }
        }
        guard classificationMemory.allSatisfy({ !CategoryNamespace.split($0.key).name.isEmpty && CategoryNamespace.split($0.key).name.count <= 4000 && CategoryMemory.key(CategoryNamespace.split($0.key).name) == CategoryNamespace.split($0.key).name &&
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.value.count <= 401 && $0.value.split(separator: "/", omittingEmptySubsequences: false).count <= 2 }) else { throw YubaiError.invalid("分类对照表无效。") }
        if let day = lastSubcategoryBatchDay {
            guard Dates.parse(day).map({ Dates.text($0) == day }) ?? false else { throw YubaiError.invalid("小项归类日期无效。") }
        }
        guard subcategoryMemory.allSatisfy({ !CategoryNamespace.split($0.key).name.isEmpty && CategoryNamespace.split($0.key).name.count <= 4000 && CategoryMemory.key(CategoryNamespace.split($0.key).name) == CategoryNamespace.split($0.key).name && $0.value.split(separator: "/", omittingEmptySubsequences: false).count == 2 }),
              subscriptionChecks.allSatisfy({ item in !item.key.isEmpty && item.key.count <= 200 && item.value.count == 7 && Dates.parse(item.value + "-01").map { String(Dates.text($0).prefix(7)) == item.value } == true }) else { throw YubaiError.invalid("小项或固定收付对照表无效。") }
        guard stoppedSubscriptions.count <= 5000, Set(stoppedSubscriptions.map(\.id)).count == stoppedSubscriptions.count else { throw YubaiError.invalid("停掉的固定收付记录无效。") }
        for stopped in stoppedSubscriptions {
            let p = stopped.plan
            guard p.amount > 0, p.amount <= Money.limit, !p.title.isEmpty, dateValid(p.dueDate), p.endDate.map(dateValid) ?? true,
                  p.installments.map({ $0 > 0 }) ?? true, dateValid(stopped.stoppedAt), stopped.resumedAt.map({ dateValid($0) && $0 >= stopped.stoppedAt }) ?? true else { throw YubaiError.invalid("停掉的固定收付日期或金额无效。") }
        }
        for category in categories {
            guard !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, category.name.count <= 200, !category.name.contains("/"),
                  !category.subcategories.contains("其他"),
                  Set(category.subcategories).count == category.subcategories.count,
                  category.subcategories.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 200 && !$0.contains("/") }) else { throw YubaiError.invalid("主项和小项只支持两级。") }
        }
        guard Set(categoryNames).count == categoryNames.count else { throw YubaiError.invalid("分类名称不能重复。") }
        for a in accounts { guard !a.name.trimmingCharacters(in: .whitespaces).isEmpty, a.anchorBalance >= -Money.limit, a.anchorBalance <= Money.limit, (0...Money.limit).contains(a.creditLimit), a.creditPaymentDay.map({ (1...31).contains($0) }) ?? true, dateValid(a.anchorDate) else { throw YubaiError.invalid("账户信息无效。") } }
        for e in entries {
            guard ids.contains(e.accountID), e.amount > 0, e.amount <= Money.limit, !e.title.isEmpty,
                  dateValid(e.date), e.recordedAt.map(dateValid) ?? true, e.otherDate.map(dateValid) ?? true,
                  e.occurrence.map(dateValid) ?? true, e.rentPeriod.map(dateValid) ?? true,
                  e.spreadFrom.map({ dateValid($0) && Dates.day($0) <= Dates.day(e.date) }) ?? true,
                  e.subcategory.map({ !$0.isEmpty && $0.count <= 200 && !$0.contains("/") }) ?? true,
                  (e.purpose?.count ?? 0) <= 4000 else { throw YubaiError.invalid("交易金额、日期或账户无效。") }
            if let other = e.otherAccountID { guard ids.contains(other), other != e.accountID, e.nature.paired else { throw YubaiError.invalid("转账的两个账户必须不同且存在。") } }
            if e.nature.paired, let other = e.otherAccountID, let kind = accounts.first(where: { $0.id == other })?.kind, e.nature != .transfer {
                let required: AccountKind = [.borrow, .loanReturn, .repayment].contains(e.nature) ? .credit : ([.lend, .loanRecovery].contains(e.nature) ? .receivable : .investment)
                guard kind == required, accounts.contains(where: { $0.id == e.accountID && ($0.kind == .cash || $0.kind == .bank) }) else { throw YubaiError.invalid("\(e.nature.label)需要把收付款账户关联到“\(required.label)”账户，请核对两边账户类型。") }
            }
            if e.mergedIntoID != nil && e.deletedAt == nil { throw YubaiError.invalid("已合并的转账证据不能单独恢复，否则会重复记账。请撤销合并或恢复合并前版本。") }
            if let personal = e.personalExpense { guard personal >= 0, personal <= e.amount else { throw YubaiError.invalid("个人承担金额不能超过本笔付款。") } }
            if e.deletedAt == nil, let pID = e.planID {
                guard let p = plans.first(where: { $0.id == pID }), e.occurrence != nil, e.nature == p.nature else { throw YubaiError.invalid("这笔记录已关联资金安排，性质需要与安排一致；请先解除关联再修改。") }
            }
            if e.deletedAt == nil, let rID = e.rentID {
                guard rents.contains(where: { $0.id == rID }), e.rentPeriod != nil, e.nature == .expense || e.nature == .contribution else { throw YubaiError.invalid("房租记录需要保留支出或收到分摊的性质；请先解除关联再修改。") }
            }
        }
        // Include future postings too, so advancing time cannot invalidate a stored total.
        guard fixedSavingsTotal(now: .distantFuture) <= Money.limit else { throw YubaiError.invalid("存下的钱的总额超出范围。") }
        let refunds = Dictionary(grouping: entries.lazy.filter { $0.deletedAt == nil && $0.nature == .refund && $0.relatedEntryID != nil }, by: { $0.relatedEntryID! })
        if !refunds.isEmpty {
            let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            for (id, rows) in refunds {
                guard let original = entriesByID[id], original.deletedAt == nil, original.nature == .expense,
                      rows.reduce(Int64(0), { $0 + $1.amount }) <= original.amount else { throw YubaiError.invalid("关联退款超过原支出，或原支出已被移除。请先核对退款关联。") }
            }
        }
        try validateProfileAndCards()
        for change in pendingChanges { try change.validateStructure() }
        for p in plans {
            try FixedFlows.validateDateOverrides(p)
            var schedule = p; schedule.endDate = nil
            guard p.amount > 0, p.amount <= Money.limit, !p.title.isEmpty, dateValid(p.dueDate), p.endDate.map({ dateValid($0) && ($0 >= p.dueDate || p.stoppedAt != nil || !p.active) }) ?? true,
                              p.stoppedAt.map(dateValid) ?? true, p.autoPaySince.map(dateValid) ?? true, p.installments.map({ $0 > 0 }) ?? true,
                              p.estimatedAmountSince.map(dateValid) ?? true,
                              p.previousOccurrences.count <= 2400, p.settledOccurrences.count <= 2400,
                              p.previousOccurrences.allSatisfy(dateValid), p.settledOccurrences.allSatisfy(dateValid),
                              Set(p.previousOccurrences.map(Dates.day)).count == p.previousOccurrences.count,
                              Set(p.settledOccurrences.map(Dates.day)).count == p.settledOccurrences.count,
                              p.installments.map({ $0 >= p.previousOccurrences.count }) ?? true,
                              p.monthlyDay.map({ (1...31).contains($0) && p.frequency == .monthly }) ?? true,
                              p.skippedOccurrences.allSatisfy(dateValid),
                              Set(p.skippedOccurrences.map(Dates.day)).count == p.skippedOccurrences.count,
                              p.skippedOccurrences.allSatisfy({ dateValid($0) && schedule.occurrenceIndex(on: $0) != nil }) else { throw YubaiError.invalid("资金安排信息无效。") }
        }
        guard plans.reduce(Int64(0), { $0 + $1.amount }) <= Money.limit else { throw YubaiError.invalid("所有安排总额超出安全计算范围。") }
        for g in goals { guard g.target > 0, g.target <= Money.limit, g.reserved >= 0, g.reserved <= g.target, !g.title.isEmpty else { throw YubaiError.invalid("想存金额或已存金额无效。") } }
        for r in rents { guard r.monthlyTotal > 0, r.monthlyTotal <= Money.limit / 12, r.personalShare >= 0, r.personalShare <= r.monthlyTotal, (1...12).contains(r.monthsPerPayment), (1...28).contains(r.receiveDay), dateValid(r.startDate), dateValid(r.nextDueDate), r.endDate.map({ dateValid($0) && $0 >= r.startDate }) ?? true, r.stoppedAt.map(dateValid) ?? true else { throw YubaiError.invalid("房租金额、分摊或周期无效。") } }
        guard (7...366).contains(preferences.horizonDays), preferences.emergencyReserve >= 0, preferences.emergencyReserve <= Money.limit,
              preferences.dailyLiving >= 0, preferences.dailyLiving <= Money.limit / 366 else { throw YubaiError.invalid("资金偏好数值无效。") }
        calculations.markValidated()
    }
}

private extension Ledger {
    func validateProfileAndCards() throws {
        func text(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.count <= 4000 }
        // A merged off-character key can contain every entry ID in the ledger.
        func cardKey(_ s: String) -> Bool { text(s) || (s.hasPrefix("off:") && s.count <= 4 + 37 * 200_000) }
        func date(_ d: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(d.timeIntervalSince1970) }
        let areas = profile.generous + profile.restrain
        guard areas.count <= 200, Set(areas.map(\.id)).count == areas.count,
              profile.principles.count <= 200, profile.principles.allSatisfy(text),
              Set(profile.principles).count == profile.principles.count,
              profile.principleDates.allSatisfy({ profile.principles.contains($0.key) && date($0.value) }),
              profile.floorAmount.map({ (0...Money.limit).contains($0) }) ?? true,
              date(profile.updatedAt), mutedTopics.allSatisfy(cardKey) else { throw YubaiError.invalid("消费画像或静音主题无效。") }
        for a in areas {
            guard text(a.title), a.note.count <= 4000, a.match.categories.count <= 200, a.match.keywords.count <= 200,
                  a.confirmedAt.map(date) ?? true,
                  a.match.categories.allSatisfy(text), a.match.keywords.allSatisfy(text), a.match.subcategories.allSatisfy(text),
                  (a.softLimit?.perWeekCount).map({ (0...10_000).contains($0) }) ?? true,
                  (a.softLimit?.perMonthAmount).map({ (0...Money.limit).contains($0) }) ?? true else { throw YubaiError.invalid("消费领域、次数或金额无效。") }
        }
        for c in cards {
            // Evidence and action targets can have been deleted or dismissed since creation.
            guard text(c.title), c.body.count <= 16_000, cardKey(c.dedupeKey), c.evidence.count <= (c.kind == .offCharacter ? 200_000 : 1000),
                  Set(c.evidence).count == c.evidence.count, date(c.createdAt), c.dismissedAt.map(date) ?? true,
                  c.feedbackAt.map(date) ?? true, c.meta.map({ $0.count <= 16_000 }) ?? true,
                  c.facts.map({ $0.count <= 1000 && $0.allSatisfy { text($0.label) && $0.value.count <= 4000 } }) ?? true else { throw YubaiError.invalid("管家卡片无效。") }
            if let letter = c.letter {
                guard date(letter.weekEnding), letter.series.count == 7, letter.series.allSatisfy({ date($0.date) }),
                      Set(letter.series.map(\.date)).count == 7, letter.evidence.count <= 1000 else { throw YubaiError.invalid("每周来信明细无效。") }
                guard letter.learned?.allSatisfy({ Memory.validText($0.text, limit: 40) }) ?? true,
                      letter.review.map({ date($0.confirmedAt) && text($0.text) && $0.usage.allSatisfy { date($0.weekStart) && $0.count >= 0 && $0.amount >= 0 } }) ?? true else { throw YubaiError.invalid("每周来信中的记忆或消费观问题无效。") }
            }
        }
        for w in wishlist {
            guard text(w.title), (0...Money.limit).contains(w.amount), w.purpose.count <= 4000,
                  w.judgment.count <= 16_000, date(w.createdAt), w.followUpAt.map(date) ?? true,
                  w.followUpAnsweredAt.map(date) ?? true, w.coolUntil.map(date) ?? true, w.droppedAt.map(date) ?? true,
                  (w.followUpAnswer?.count ?? 0) <= 4000 else { throw YubaiError.invalid("心愿记录无效。") }
        }
    }
}
