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
public struct SyncedExchangeRates: Codable, Equatable, Sendable {
    /// The publisher's reference date.
    public var date: Date
    /// When the last successful sync finished.
    public var fetchedAt: Date
    /// CNY yuan per one unit, keyed by currency code.
    public var cnyPerUnit: [String: Decimal]
    public init(date: Date, fetchedAt: Date, cnyPerUnit: [String: Decimal]) {
        self.date = date; self.fetchedAt = fetchedAt; self.cnyPerUnit = cnyPerUnit
    }
    public func rate(for currency: BillCurrency) -> Decimal? {
        currency == .cny ? 1 : cnyPerUnit[currency.rawValue]
    }
}

public enum ExchangeRates {
    /// European Central Bank daily reference rates: free, no key, updated on working days.
    public static let sourceURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    /// Sync on foreground when the last success is older than this.
    public static let refreshInterval: TimeInterval = 12 * 3600
    /// Settings shows 「去更新」 after this many days without a success.
    public static let staleDays = 7

    public static func needsSync(_ ledger: Ledger, now: Date) -> Bool {
        guard ledger.preferences.autoRateSync != false else { return false }
        guard let last = ledger.preferences.syncedRates?.fetchedAt else { return true }
        return now.timeIntervalSince(last) >= refreshInterval || last > now
    }

    public static func isStale(_ ledger: Ledger, now: Date) -> Bool {
        guard let last = ledger.preferences.syncedRates?.fetchedAt else { return true }
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

    /// Store a sync result. Entries already recorded keep their frozen rate.
    public static func apply(_ rates: SyncedExchangeRates, to ledger: inout Ledger) throws {
        guard !rates.cnyPerUnit.isEmpty, rates.cnyPerUnit.values.allSatisfy({ $0 > 0 && $0 <= 100_000 }) else {
            throw YubaiError.invalid("汇率数据不完整。")
        }
        var next = ledger, merged = rates
        // A partial response never erases quotes it does not mention.
        for (code, value) in ledger.preferences.syncedRates?.cnyPerUnit ?? [:] where merged.cnyPerUnit[code] == nil {
            merged.cnyPerUnit[code] = value
        }
        next.preferences.syncedRates = merged
        try next.validate(); ledger = next
    }

    /// Rate to use for a new entry: a fixed manual rate set in Settings wins,
    /// otherwise the latest synced rate. Nil means the person must type one.
    public static func rate(for currency: BillCurrency, in ledger: Ledger, now: Date) -> EntryRate? {
        guard currency != .cny else { return nil }
        if let manual = FixedFlows.exchangeRate(for: currency, in: ledger, now: now) {
            return EntryRate(cnyPerUnit: manual.cnyPerUnit, date: manual.updatedAt, manual: true)
        }
        guard let synced = ledger.preferences.syncedRates, let value = synced.rate(for: currency) else { return nil }
        return EntryRate(cnyPerUnit: value, date: synced.date, manual: false)
    }

    /// Converts original cents to CNY cents with the given rate, rounded to fen.
    public static func convert(_ originalCents: Int64, at rate: EntryRate) -> Int64? {
        guard rate.isValid, (0...Money.limit).contains(originalCents) else { return nil }
        var value = Decimal(originalCents) * rate.cnyPerUnit, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded >= 0, rounded <= Decimal(Money.limit) else { return nil }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Display-only conversion from the CNY ledger into the main currency, using
    /// the latest synced (or fixed manual) rate. The ledger itself never changes.
    public static func display(_ cnyCents: Int64, in ledger: Ledger, now: Date) -> (currency: BillCurrency, cents: Int64) {
        let main = ledger.preferences.mainCurrency ?? .cny
        guard main != .cny, let rate = rate(for: main, in: ledger, now: now), rate.cnyPerUnit > 0 else { return (.cny, cnyCents) }
        var value = Decimal(cnyCents) / rate.cnyPerUnit, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard abs(rounded) <= Decimal(Money.limit) else { return (.cny, cnyCents) }
        return (main, NSDecimalNumber(decimal: rounded).int64Value)
    }

    /// Changing the main currency only changes display; recorded entries stay in CNY.
    public static func setMainCurrency(_ currency: BillCurrency, in ledger: inout Ledger, now: Date) throws {
        guard currency == .cny || rate(for: currency, in: ledger, now: now) != nil else { throw YubaiError.invalid("先更新汇率。") }
        ledger.preferences.mainCurrency = currency == .cny ? nil : currency
    }
}
