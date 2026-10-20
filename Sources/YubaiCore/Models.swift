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
    public init(name: String, kind: AccountKind = .bank, balance: Int64 = 0, at: Date = Date(), reconciled: Bool = true) {
        self.name = name; self.kind = kind; self.anchorBalance = balance; self.anchorDate = at; self.reconciled = reconciled
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
        case .adjustmentIn: "调增余额"; case .adjustmentOut: "调减余额"; case .unknownIn: "待明确流入"; case .unknownOut: "待明确流出"
        }
    }
    public var inflow: Bool { [.income, .borrow, .loanRecovery, .refund, .contribution, .investSell, .adjustmentIn, .unknownIn].contains(self) }
    public var paired: Bool { [.transfer, .repayment, .investBuy, .investSell, .borrow, .lend, .loanReturn, .loanRecovery].contains(self) }
    public var uncertain: Bool { self == .unknownIn || self == .unknownOut }
    public var symbol: String {
        switch self { case .income: "arrow.down.left"; case .expense: "arrow.up.right"; case .refund: "arrow.uturn.backward"; case .contribution: "person.2"; default: paired ? "arrow.left.arrow.right" : "circle.dotted" }
    }
}

public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var date: Date; public var amount: Int64
    public var nature: Nature; public var accountID: UUID; public var otherAccountID: UUID?
    public var title: String; public var category: String; public var note: String = ""
    public var purpose: String?
    public var displayTitle: String { purpose.flatMap { $0.isEmpty ? nil : $0 } ?? title }
    public var source: String = "手动"; public var externalID: String = ""; public var batchID: UUID?
    public var sourceIdentity: String = ""
    public var sourceRow: Int?; public var fingerprint: String = ""
    public var userEdited = false; public var deletedAt: Date?
    public var relatedEntryID: UUID?; public var planID: UUID?; public var occurrence: Date?
    public var rentID: UUID?; public var rentPeriod: Date?
    public var attachmentID: UUID?; public var classificationReason: String = "手动选择"
    public var otherDate: Date?; public var mergedIntoID: UUID?; public var personalExpense: Int64?
    public init(date: Date = Date(), amount: Int64, nature: Nature = .expense, accountID: UUID, title: String, category: String = "其他支出") {
        self.date = date; self.amount = amount; self.nature = nature; self.accountID = accountID; self.title = title; self.category = category
    }
    public func delta(for account: UUID) -> Int64 {
        if accountID == account { return nature.inflow ? amount : -amount }
        if nature.paired && otherAccountID == account { return nature.inflow ? -amount : amount }
        return 0
    }
    public func postingDate(for account: UUID) -> Date { otherAccountID == account ? (otherDate ?? date) : date }
}

public enum Frequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case once, weekly, monthly, quarterly, yearly
    public var id: String { rawValue }
    public var label: String { switch self { case .once: "一次"; case .weekly: "每周"; case .monthly: "每月"; case .quarterly: "每季"; case .yearly: "每年" } }
    public func advance(_ original: Date, by count: Int) -> Date {
        switch self { case .once: return original; case .weekly: return Dates.addDays(7 * count, to: original); case .monthly: return Dates.addMonths(count, to: original); case .quarterly: return Dates.addMonths(3 * count, to: original); case .yearly: return Dates.addMonths(12 * count, to: original) }
    }
}
public struct Plan: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var amount: Int64; public var dueDate: Date
    public var frequency: Frequency; public var inflow: Bool; public var accountID: UUID?
    public var category: String; public var nature: Nature; public var active = true
    public var endDate: Date?; public var note = ""
    public init(title: String, amount: Int64, dueDate: Date, frequency: Frequency = .once, inflow: Bool = false, category: String = "其他支出", nature: Nature = .expense) {
        self.title = title; self.amount = amount; self.dueDate = dueDate; self.frequency = frequency; self.inflow = inflow; self.category = category; self.nature = nature
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
    public var endDate: Date?
    public init(title: String = "合租房租", monthlyTotal: Int64, personalShare: Int64, startDate: Date, nextDueDate: Date, monthsPerPayment: Int = 3, receiveDay: Int = 1) {
        self.title = title; self.monthlyTotal = monthlyTotal; self.personalShare = personalShare; self.startDate = startDate; self.nextDueDate = nextDueDate; self.monthsPerPayment = monthsPerPayment; self.receiveDay = receiveDay
    }
}
public struct Category: Codable, Identifiable, Equatable, Sendable {
    public var name: String; public var symbol: String; public var income: Bool
    public var id: String { name }
    public init(_ name: String, _ symbol: String = "square.grid.2x2", income: Bool = false) { self.name = name; self.symbol = symbol; self.income = income }
    public static let defaults: [Category] = [
        .init("餐饮", "fork.knife"), .init("居住", "house"), .init("交通", "tram"), .init("日用购物", "bag"),
        .init("医疗健康", "cross.case"), .init("学习工作", "book"), .init("娱乐旅行", "sparkles"), .init("人情家庭", "gift"),
        .init("利息手续费", "percent"), .init("其他支出", "ellipsis"), .init("工资奖金", "briefcase", income: true),
        .init("兼职劳务", "hammer", income: true), .init("礼金赠与", "gift", income: true), .init("投资收益", "chart.line.uptrend.xyaxis", income: true), .init("其他收入", "ellipsis", income: true)
    ]
}
public struct Attachment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var createdAt = Date()
    public var data: Data { didSet { byteCount = data.count; checksum = nil } }
    public private(set) var byteCount: Int
    var checksum: String?
    public init(name: String, data: Data) { self.name = name; self.data = data; byteCount = data.count }
    private enum CodingKeys: String, CodingKey { case id, name, createdAt, data, byteCount, checksum }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        let embedded = try c.decodeIfPresent(Data.self, forKey: .data)
        data = embedded ?? Data()
        byteCount = try c.decodeIfPresent(Int.self, forKey: .byteCount) ?? data.count
        checksum = try c.decodeIfPresent(String.self, forKey: .checksum)
        guard byteCount >= 0, byteCount <= LedgerCodec.capacity else { throw YubaiError.invalid("附件大小无效。") }
        if let embedded {
            guard byteCount == embedded.count, checksum.map({ $0 == LedgerCodec.checksum(embedded) }) ?? true else { throw YubaiError.invalid("附件内容不完整。") }
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
            try c.encode(checksum ?? LedgerCodec.checksum(data), forKey: .checksum)
        } else { try c.encode(data, forKey: .data) }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.createdAt == rhs.createdAt && lhs.data == rhs.data && lhs.byteCount == rhs.byteCount
    }
}
public struct ImportBatch: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var filename: String; public var importedAt = Date()
    public var importedCount: Int; public var duplicateCount: Int; public var skippedCount: Int
    public var attachmentID: UUID?; public var undoneAt: Date?
    public var needsOrganization: Bool?
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
    public var onboardingComplete = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case horizonDays, emergencyReserve, dailyLiving, hideAmounts, lockEnabled
        case appearance, purchaseValues, colorTheme, cloudAIEnabled, onboardingComplete, weeklyLetterPush
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
        onboardingComplete = try values.decode(Bool.self, forKey: .onboardingComplete)
    }
}
public struct AdviceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var createdAt = Date(); public var title: String; public var amount: Int64
    public var result: String; public var note: String
    public init(title: String, amount: Int64, result: String, note: String) { self.title = title; self.amount = amount; self.result = result; self.note = note }
}
public struct AreaMatch: Codable, Equatable, Sendable {
    public var categories: [String]; public var keywords: [String]
    public init(categories: [String] = [], keywords: [String] = []) { self.categories = categories; self.keywords = keywords }
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
    public var principles: [String] = []; public var floorAmount: Int64?; public var updatedAt = Date()
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
public enum CategoryMemory {
    public static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"[\p{N}\p{P}]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func remember(_ entry: Entry, in ledger: inout Ledger) {
        let normalized = key(entry.title)
        if !normalized.isEmpty { ledger.categoryMemory[normalized] = entry.category }
    }
}
public enum CardKind: String, Codable, CaseIterable, Sendable {
    case answerQuestion, restrain, shortfall, unknownInflow, staleBalance, recurring, duplicate, offCharacter, followUp, weeklyLetter
}
public enum CardAction: Codable, Equatable, Sendable {
    case openEvidence, confirmChangeSet(UUID), reconcileAccount(UUID), answerQuestion, openWish(UUID)
}
public enum CardFeedback: String, Codable, Sendable { case worth, regret }
public struct ButlerCard: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var kind: CardKind; public var title: String; public var body: String
    public var evidence: [UUID]; public var action: CardAction?; public var dedupeKey: String
    public var createdAt = Date(); public var dismissedAt: Date?; public var feedback: CardFeedback?
    public var importQuestion: ImportQuestion?
    public var facts: [CardFact]?
    public var areaID: UUID?
    public var priority: Int?
    public var letter: LetterFacts?
    public var feedbackAt: Date?
    public var feedbackProposalID: UUID?
    public init(kind: CardKind, title: String, body: String, evidence: [UUID] = [], action: CardAction? = nil, dedupeKey: String) {
        self.kind = kind; self.title = title; self.body = body; self.evidence = evidence; self.action = action; self.dedupeKey = dedupeKey
    }
}
public enum WishStatus: String, Codable, CaseIterable, Sendable { case thinking, bought, dropped }
public struct WishItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID(); public var title: String; public var amount: Int64; public var purpose: String
    public var createdAt = Date(); public var status: WishStatus = .thinking; public var judgment: String
    public var boughtEntryID: UUID?; public var followUpAt: Date?; public var followUpAnswer: String?
    public var followUpAnsweredAt: Date?
    public init(title: String, amount: Int64, purpose: String = "", judgment: String = "") {
        self.title = title; self.amount = amount; self.purpose = purpose; self.judgment = judgment
    }
    init(_ advice: AdviceRecord) {
        self.init(title: advice.title, amount: advice.amount, purpose: advice.note, judgment: advice.result)
        id = advice.id; createdAt = advice.createdAt
    }
}
public struct Ledger: Codable, Equatable, Sendable {
    public var schema = 2; public var id = UUID(); public var updatedAt = Date()
    public var isSample = false
    public var accounts: [Account] = []; public var entries: [Entry] = []; public var plans: [Plan] = []
    public var goals: [Goal] = []; public var rents: [Rent] = []
    public var categories = Category.defaults; public var imports: [ImportBatch] = []; public var attachments: [Attachment] = []
    public var categoryAliases: [String: String] = [:]
    public var categoryMemory: [String: String] = [:]
    public var preferences = Preferences()
    public var profile = SpendingProfile(); public var cards: [ButlerCard] = []
    public var pendingChanges: [ChangeSet] = []; public var wishlist: [WishItem] = []; public var mutedTopics: [String] = []
    // Only retained for restoring a legacy backup into a repository; never encoded.
    var preMigrationData: Data?
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
        case schema, id, updatedAt, isSample, accounts, entries, plans, goals, rents, categories, imports, attachments, categoryAliases, categoryMemory, preferences, profile, cards, pendingChanges, wishlist, mutedTopics
    }
    private enum LegacyKeys: String, CodingKey { case advice }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        guard schema == 1 || schema == 2 else { throw YubaiError.invalid("这个账本来自更新版本，请先更新余白。") }
        let legacy = schema == 1
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
        categoryMemory = try c.decodeIfPresent([String: String].self, forKey: .categoryMemory) ?? [:]
        preferences = try c.decode(Preferences.self, forKey: .preferences)
        profile.updatedAt = updatedAt
        profile = try c.decodeIfPresent(SpendingProfile.self, forKey: .profile) ?? profile
        // Preserve legacy reserves from both schema 1 and older schema 2 ledgers.
        if profile.floorAmount == nil && preferences.emergencyReserve > 0 {
            profile.floorAmount = preferences.emergencyReserve
        }
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
        schema = 2
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(2, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(isSample, forKey: .isSample)
        try c.encode(accounts, forKey: .accounts)
        try c.encode(entries, forKey: .entries)
        try c.encode(plans, forKey: .plans)
        try c.encode(goals, forKey: .goals)
        try c.encode(rents, forKey: .rents)
        try c.encode(categories, forKey: .categories)
        try c.encode(imports, forKey: .imports)
        try c.encode(attachments, forKey: .attachments)
        try c.encode(categoryAliases, forKey: .categoryAliases)
        try c.encode(categoryMemory, forKey: .categoryMemory)
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
        lhs.goals == rhs.goals &&
        lhs.rents == rhs.rents &&
        lhs.categories == rhs.categories &&
        lhs.imports == rhs.imports &&
        lhs.attachments == rhs.attachments &&
        lhs.categoryAliases == rhs.categoryAliases &&
        lhs.categoryMemory == rhs.categoryMemory &&
        lhs.preferences == rhs.preferences &&
        lhs.profile == rhs.profile &&
        lhs.cards == rhs.cards &&
        lhs.pendingChanges == rhs.pendingChanges &&
        lhs.wishlist == rhs.wishlist &&
        lhs.mutedTopics == rhs.mutedTopics
    }
    public var activeEntries: [Entry] { entries.filter { $0.deletedAt == nil } }
    public func accountName(_ id: UUID?) -> String { accounts.first { $0.id == id }?.name ?? "未指定账户" }
    public func resolveCategory(_ category: String) -> String { categoryAliases[category] ?? category }
    public func validate() throws {
        guard schema == 1 || schema == 2 else { throw YubaiError.invalid("这个账本来自更新版本，请先更新余白。") }
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
              Set(mutedTopics).count == mutedTopics.count else { throw YubaiError.invalid("画像、卡片或提案包含重复标识。") }
        let ids = Set(accounts.map(\.id)); let categoryNames = categories.map(\.name)
        func dateValid(_ value: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(value.timeIntervalSince1970) }
        guard categoryMemory.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 4000 && CategoryMemory.key($0.key) == $0.key &&
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.value.count <= 200 }) else { throw YubaiError.invalid("分类对照表无效。") }
        guard Set(categoryNames).count == categoryNames.count else { throw YubaiError.invalid("分类名称不能重复。") }
        for a in accounts { guard !a.name.trimmingCharacters(in: .whitespaces).isEmpty, a.anchorBalance >= -Money.limit, a.anchorBalance <= Money.limit, (0...Money.limit).contains(a.creditLimit), dateValid(a.anchorDate) else { throw YubaiError.invalid("账户信息无效。") } }
        for e in entries {
            guard ids.contains(e.accountID), e.amount > 0, e.amount <= Money.limit, !e.title.isEmpty,
                  dateValid(e.date), e.otherDate.map(dateValid) ?? true,
                  e.occurrence.map(dateValid) ?? true, e.rentPeriod.map(dateValid) ?? true,
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
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let refunds = Dictionary(grouping: activeEntries.filter { $0.nature == .refund && $0.relatedEntryID != nil }, by: { $0.relatedEntryID! })
        for (id, rows) in refunds {
            guard let original = entriesByID[id], original.deletedAt == nil, original.nature == .expense,
                  rows.reduce(Int64(0), { $0 + $1.amount }) <= original.amount else { throw YubaiError.invalid("关联退款超过原支出，或原支出已被移除。请先核对退款关联。") }
        }
        try validateProfileAndCards()
        for change in pendingChanges { try change.validateStructure() }
        for p in plans { guard p.amount > 0, p.amount <= Money.limit, !p.title.isEmpty, dateValid(p.dueDate), p.endDate.map({ dateValid($0) && $0 >= p.dueDate }) ?? true else { throw YubaiError.invalid("资金安排信息无效。") } }
        guard plans.reduce(Int64(0), { $0 + $1.amount }) <= Money.limit else { throw YubaiError.invalid("所有安排总额超出安全计算范围。") }
        for g in goals { guard g.target > 0, g.target <= Money.limit, g.reserved >= 0, g.reserved <= g.target, !g.title.isEmpty else { throw YubaiError.invalid("目标金额或预留金额无效。") } }
        for r in rents { guard r.monthlyTotal > 0, r.monthlyTotal <= Money.limit / 12, r.personalShare >= 0, r.personalShare <= r.monthlyTotal, (1...12).contains(r.monthsPerPayment), (1...28).contains(r.receiveDay), dateValid(r.startDate), dateValid(r.nextDueDate), r.endDate.map({ dateValid($0) && $0 >= r.startDate }) ?? true else { throw YubaiError.invalid("房租金额、分摊或周期无效。") } }
        guard (7...366).contains(preferences.horizonDays), preferences.emergencyReserve >= 0, preferences.emergencyReserve <= Money.limit,
              preferences.dailyLiving >= 0, preferences.dailyLiving <= Money.limit / 366 else { throw YubaiError.invalid("资金偏好数值无效。") }
    }
}

private extension Ledger {
    func validateProfileAndCards() throws {
        func text(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && s.count <= 4000 }
        func date(_ d: Date) -> Bool { (-2_208_988_800...7_258_118_400).contains(d.timeIntervalSince1970) }
        let areas = profile.generous + profile.restrain
        guard areas.count <= 200, Set(areas.map(\.id)).count == areas.count,
              profile.principles.count <= 200, profile.principles.allSatisfy(text),
              Set(profile.principles).count == profile.principles.count,
              profile.principleDates.allSatisfy({ profile.principles.contains($0.key) && date($0.value) }),
              profile.floorAmount.map({ (0...Money.limit).contains($0) }) ?? true,
              date(profile.updatedAt), mutedTopics.allSatisfy(text) else { throw YubaiError.invalid("消费画像或静音主题无效。") }
        for a in areas {
            guard text(a.title), a.note.count <= 4000, a.match.categories.count <= 200, a.match.keywords.count <= 200,
                  a.confirmedAt.map(date) ?? true,
                  a.match.categories.allSatisfy(text), a.match.keywords.allSatisfy(text),
                  (a.softLimit?.perWeekCount).map({ (0...10_000).contains($0) }) ?? true,
                  (a.softLimit?.perMonthAmount).map({ (0...Money.limit).contains($0) }) ?? true else { throw YubaiError.invalid("消费领域或柔性提醒数值无效。") }
        }
        for c in cards {
            // Evidence and action targets can have been deleted or dismissed since creation.
            guard text(c.title), c.body.count <= 16_000, text(c.dedupeKey), c.evidence.count <= 1000,
                  Set(c.evidence).count == c.evidence.count, date(c.createdAt), c.dismissedAt.map(date) ?? true,
                  c.feedbackAt.map(date) ?? true,
                  c.facts.map({ $0.count <= 1000 && $0.allSatisfy { text($0.label) && $0.value.count <= 4000 } }) ?? true else { throw YubaiError.invalid("管家卡片无效。") }
            if let letter = c.letter {
                guard date(letter.weekEnding), letter.series.count == 7, letter.series.allSatisfy({ date($0.date) }),
                      Set(letter.series.map(\.date)).count == 7, letter.evidence.count <= 1000 else { throw YubaiError.invalid("每周来信依据无效。") }
            }
        }
        for w in wishlist {
            guard text(w.title), (0...Money.limit).contains(w.amount), w.purpose.count <= 4000,
                  w.judgment.count <= 16_000, date(w.createdAt), w.followUpAt.map(date) ?? true,
                  w.followUpAnsweredAt.map(date) ?? true,
                  (w.followUpAnswer?.count ?? 0) <= 4000 else { throw YubaiError.invalid("心愿记录无效。") }
        }
    }
}
