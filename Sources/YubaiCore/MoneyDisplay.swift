import Foundation

/// The one way an amount stored in CNY is shown: in the main currency (display only, Spec-Currency),
/// converted once and rounded once to that currency's precision. If the converted number would not fit,
/// it falls back to CNY with its own ¥, so a CNY number never wears a foreign symbol.
public struct MoneyDisplay: Codable, Equatable, Sendable {
    public let currency: BillCurrency
    /// CNY yuan per one unit of `currency` (1 for CNY).
    public let cnyPerUnit: Decimal

    public static let cny = MoneyDisplay(currency: .cny, cnyPerUnit: 1)

    public init(currency: BillCurrency, cnyPerUnit: Decimal) {
        let usable = currency != .cny && cnyPerUnit > 0 && !cnyPerUnit.isNaN
        self.currency = usable ? currency : .cny
        self.cnyPerUnit = usable ? cnyPerUnit : 1
    }

    /// The ledger's main currency at the latest synced rate; a fixed rate only when nothing synced.
    public init(ledger: Ledger, synced: SyncedExchangeRates?, now: Date) {
        let main = ledger.preferences.mainCurrency ?? .cny
        let rate = main == .cny ? nil
            : synced?.rate(for: main) ?? FixedFlows.exchangeRate(for: main, in: ledger, now: now)?.cnyPerUnit
        self.init(currency: rate == nil ? .cny : main, cnyPerUnit: rate ?? 1)
    }

    /// The amount in the display currency, in its minor units, and which currency that is.
    public func convert(_ cnyCents: Int64) -> (currency: BillCurrency, minor: Int64) {
        guard currency != .cny else { return (.cny, cnyCents) }
        let digits = currency.fractionDigits
        var value = Decimal(cnyCents) / cnyPerUnit
        if digits == 0 { value /= 100 }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let limit = Decimal(Money.limit)
        guard abs(rounded) <= limit else { return (.cny, cnyCents) }
        return (currency, NSDecimalNumber(decimal: rounded).int64Value)
    }

    /// 「1,234.56」, or with `symbol` 「US$1,234.56」 / 「-¥12.00」.
    public func text(_ cnyCents: Int64, symbol: Bool = false) -> String {
        let (shown, minor) = convert(cnyCents)
        let number = Self.number(abs(minor), digits: shown.fractionDigits)
        // Too large to convert falls back to CNY: then ¥ always shows, so the number is never misread.
        return (minor < 0 ? "-" : "") + (symbol || shown != currency ? shown.symbol : "") + number
    }

    /// The symbol that `text(_:symbol:)` would use for this amount.
    public func symbol(for cnyCents: Int64) -> String { convert(cnyCents).currency.symbol }

    // Formatters are made once; formatting is thread-safe.
    nonisolated(unsafe) private static let twoDigits: NumberFormatter = make(2)
    nonisolated(unsafe) private static let noDigits: NumberFormatter = make(0)
    private static func make(_ digits: Int) -> NumberFormatter {
        let f = NumberFormatter(); f.locale = Locale(identifier: "zh_CN"); f.numberStyle = .decimal
        f.minimumFractionDigits = digits; f.maximumFractionDigits = digits; f.roundingMode = .halfUp
        return f
    }

    /// `minor` in the currency's minor units (cents, or whole yen).
    static func number(_ minor: Int64, digits: Int) -> String {
        if digits == 0 { return noDigits.string(from: NSNumber(value: minor)) ?? "\(minor)" }
        return twoDigits.string(from: NSDecimalNumber(decimal: Decimal(minor) / 100)) ?? "0.00"
    }
}
