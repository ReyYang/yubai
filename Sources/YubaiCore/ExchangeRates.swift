import Foundation

/// The rate frozen into one foreign-currency entry.
public struct EntryRate: Codable, Equatable, Sendable {
    /// CNY yuan per one original-currency unit.
    public var cnyPerUnit: Decimal
    /// Reference date of a synced rate, or the day a manual rate was typed.
    public var date: Date
    /// True when the person typed this rate for this entry.
    public var manual: Bool
    public init(cnyPerUnit: Decimal, date: Date, manual: Bool) {
        self.cnyPerUnit = cnyPerUnit; self.date = date; self.manual = manual
    }
    var isValid: Bool {
        !cnyPerUnit.isNaN && cnyPerUnit > 0 && cnyPerUnit <= 100_000 &&
        (-2_208_988_800...7_258_118_400).contains(date.timeIntervalSince1970)
    }
}

/// The latest daily reference rates. Synced once a day, never while recording.
/// Kept on this device only (see `RateSyncState`), never in the ledger or on iCloud.
public struct SyncedExchangeRates: Codable, Equatable, Sendable {
    /// The publisher's latest reference date.
    public var date: Date
    /// When the last successful sync finished.
    public var fetchedAt: Date
    /// CNY yuan per one unit, keyed by currency code.
    public var cnyPerUnit: [String: Decimal]
    /// Each quote's own reference date: a quote kept from an older sync keeps its older date.
    public var quoteDates: [String: Date]
    public init(date: Date, fetchedAt: Date, cnyPerUnit: [String: Decimal], quoteDates: [String: Date]? = nil) {
        self.date = date; self.fetchedAt = fetchedAt; self.cnyPerUnit = cnyPerUnit
        self.quoteDates = quoteDates ?? Dictionary(uniqueKeysWithValues: cnyPerUnit.keys.map { ($0, date) })
    }
    private enum CodingKeys: String, CodingKey { case date, fetchedAt, cnyPerUnit, quoteDates }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        fetchedAt = try c.decode(Date.self, forKey: .fetchedAt)
        cnyPerUnit = try c.decode([String: Decimal].self, forKey: .cnyPerUnit)
        let stored: [String: Date]? = (try? c.decodeIfPresent([String: Date].self, forKey: .quoteDates)) ?? nil
        let fallback = date
        quoteDates = stored ?? Dictionary(uniqueKeysWithValues: cnyPerUnit.keys.map { ($0, fallback) })
    }
    public func rate(for currency: BillCurrency) -> Decimal? {
        currency == .cny ? 1 : cnyPerUnit[currency.rawValue]
    }
    public func quoteDate(for currency: BillCurrency) -> Date? {
        cnyPerUnit[currency.rawValue] == nil ? nil : quoteDates[currency.rawValue] ?? date
    }
}

/// This device's rate sync: the rates, when it last tried and last succeeded, and how many tries
/// in a row failed (for backoff). Lives in local storage, not in the ledger.
public struct RateSyncState: Codable, Equatable, Sendable {
    public var rates: SyncedExchangeRates?
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var failures: Int
    /// Why the last try failed, said in 主币种与汇率 next to 重试.
    public var lastError: String?
    public init(rates: SyncedExchangeRates? = nil, lastAttempt: Date? = nil, lastSuccess: Date? = nil, failures: Int = 0, lastError: String? = nil) {
        self.rates = rates; self.lastAttempt = lastAttempt; self.lastSuccess = lastSuccess; self.failures = failures; self.lastError = lastError
    }

    /// A good response: merged into the rates, which change only when the reference date or a quote did.
    /// False, and nothing changes, when it is older than what is kept (a stale cache answering).
    @discardableResult public mutating func succeeded(_ fresh: SyncedExchangeRates, at now: Date) throws -> Bool {
        let merged = try ExchangeRates.merge(fresh, into: rates)
        if let kept = rates, merged.date < kept.date { return false }
        if merged.date != rates?.date || merged.cnyPerUnit != rates?.cnyPerUnit || merged.quoteDates != rates?.quoteDates {
            rates = merged
        }
        lastAttempt = now; lastSuccess = now; failures = 0; lastError = nil
        return true
    }

    /// Rates an older build kept in the ledger: taken once, when this device has none of its own.
    public mutating func adoptLegacy(_ legacy: SyncedExchangeRates?) {
        guard rates == nil, let legacy, !legacy.cnyPerUnit.isEmpty else { return }
        rates = legacy
        lastSuccess = lastSuccess ?? legacy.fetchedAt
    }

    public mutating func failed(_ reason: String, at now: Date) {
        lastAttempt = now; failures += 1; lastError = reason
    }
}

public enum ExchangeRates {
    /// European Central Bank daily reference rates: free, no key, updated on working days.
    public static let sourceURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    /// Sync on foreground when the last success is older than this.
    public static let refreshInterval: TimeInterval = 12 * 3600
    /// The first retry after a failure; each further failure doubles it, up to `refreshInterval`.
    public static let retryBase: TimeInterval = 15 * 60
    /// Settings shows 「去更新」 after this many days without a success.
    public static let staleDays = 7

    /// Due when 每天自动更新 is on, the last success is 12 hours old, and any failure backoff has passed.
    public static func needsSync(autoSync: Bool, state: RateSyncState, now: Date) -> Bool {
        guard autoSync else { return false }
        if let success = state.lastSuccess, success <= now, now.timeIntervalSince(success) < refreshInterval { return false }
        if state.failures > 0, let attempt = state.lastAttempt, attempt <= now {
            let wait = min(refreshInterval, retryBase * pow(2, Double(min(state.failures, 12) - 1)))
            return now.timeIntervalSince(attempt) >= wait
        }
        return true
    }

    public static func isStale(_ state: RateSyncState, now: Date) -> Bool {
        guard let last = state.lastSuccess else { return true }
        return now.timeIntervalSince(last) >= Double(staleDays) * 86_400
    }
    /// Parses the ECB daily XML (EUR base) into CNY per unit for the supported currencies.
    public static func parseECB(_ data: Data, fetchedAt: Date) throws -> SyncedExchangeRates {
        guard let text = String(data: data, encoding: .utf8) else { throw YubaiError.invalid("汇率数据无法读取。") }
        func attribute(_ name: String, in tag: Substring) -> String? {
            guard let range = tag.range(of: name + "='") ?? tag.range(of: name + "=\"") else { return nil }
            let rest = tag[range.upperBound...]
            guard let end = rest.firstIndex(where: { $0 == "'" || $0 == "\"" }) else { return nil }
            return String(rest[..<end])
        }
        var perEUR: [String: Decimal] = [:]
        var reference: Date?
        for piece in text.split(separator: "<").dropFirst() where piece.hasPrefix("Cube ") {
            let tag = piece.prefix { $0 != ">" }
            if let time = attribute("time", in: tag) { reference = Dates.parse(time) }
            if let code = attribute("currency", in: tag), let raw = attribute("rate", in: tag),
               !raw.isEmpty, raw.allSatisfy({ "0123456789.".contains($0) }), raw.filter({ $0 == "." }).count <= 1,
               let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), value > 0 {
                perEUR[code] = value
            }
        }
        guard let reference, let cnyPerEUR = perEUR["CNY"], perEUR["USD"] != nil else { throw YubaiError.invalid("汇率数据不完整。") }
        perEUR["EUR"] = 1
        var result: [String: Decimal] = [:]
        for currency in BillCurrency.allCases where currency != .cny {
            guard let value = perEUR[currency.rawValue] else { continue }
            var quotient = cnyPerEUR / value, rounded = Decimal()
            NSDecimalRound(&rounded, &quotient, 10, .plain)
            if rounded > 0 { result[currency.rawValue] = rounded }
        }
        return SyncedExchangeRates(date: reference, fetchedAt: fetchedAt, cnyPerUnit: result)
    }

    /// A sync result merged with the last one. A partial response never erases quotes it does not
    /// mention, and those keep their own older reference date.
    public static func merge(_ fresh: SyncedExchangeRates, into old: SyncedExchangeRates?) throws -> SyncedExchangeRates {
        guard !fresh.cnyPerUnit.isEmpty, fresh.cnyPerUnit.values.allSatisfy({ $0 > 0 && $0 <= 100_000 }) else {
            throw YubaiError.invalid("汇率数据不完整。")
        }
        var merged = fresh
        for (code, value) in old?.cnyPerUnit ?? [:] where merged.cnyPerUnit[code] == nil {
            merged.cnyPerUnit[code] = value
            merged.quoteDates[code] = old?.quoteDates[code] ?? old?.date
        }
        return merged
    }

    /// Rate to use for a new entry: a fixed manual rate set in Settings wins,
    /// otherwise the latest synced rate (with its own reference date). Nil means the person must type one.
    public static func rate(for currency: BillCurrency, in ledger: Ledger, synced: SyncedExchangeRates?, now: Date) -> EntryRate? {
        guard currency != .cny else { return nil }
        if let manual = FixedFlows.exchangeRate(for: currency, in: ledger, now: now) {
            return EntryRate(cnyPerUnit: manual.cnyPerUnit, date: manual.updatedAt, manual: true)
        }
        guard let synced, let value = synced.rate(for: currency), let date = synced.quoteDate(for: currency) else { return nil }
        return EntryRate(cnyPerUnit: value, date: date, manual: false)
    }

    /// Converts original cents to CNY cents with the given rate, rounded to fen.
    public static func convert(_ originalCents: Int64, at rate: EntryRate) -> Int64? {
        guard rate.isValid, (0...Money.limit).contains(originalCents) else { return nil }
        var value = Decimal(originalCents) * rate.cnyPerUnit, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded >= 0, rounded <= Decimal(Money.limit) else { return nil }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Changing the main currency only changes display; recorded entries stay in CNY.
    public static func setMainCurrency(_ currency: BillCurrency, in ledger: inout Ledger, synced: SyncedExchangeRates?, now: Date) throws {
        guard currency == .cny || rate(for: currency, in: ledger, synced: synced, now: now) != nil else { throw YubaiError.invalid("先更新汇率。") }
        ledger.preferences.mainCurrency = currency == .cny ? nil : currency
    }
}
