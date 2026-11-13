import Foundation

public enum BillCurrency: String, CaseIterable, Codable, Identifiable, Sendable {
    case cny = "CNY", usd = "USD", hkd = "HKD", eur = "EUR", gbp = "GBP", jpy = "JPY", sgd = "SGD", aud = "AUD", cad = "CAD"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .cny: "¥"; case .usd: "US$"; case .hkd: "HK$"; case .eur: "€"; case .gbp: "£"
        case .jpy: "JP¥"; case .sgd: "S$"; case .aud: "A$"; case .cad: "C$"
        }
    }
    public var unit: String {
        switch self {
        case .cny: "人民币"; case .usd: "美元"; case .hkd: "港元"; case .eur: "欧元"; case .gbp: "英镑"
        case .jpy: "日元"; case .sgd: "新加坡元"; case .aud: "澳元"; case .cad: "加拿大元"
        }
    }
    public func amountText(_ cents: Int64, hidden: Bool = false) -> String {
        hidden ? "••••" : symbol + Money.text(cents, currency: false)
    }
}

public struct ManualExchangeRate: Codable, Equatable, Sendable {
    public var currency: BillCurrency
    /// CNY yuan per one original-currency unit; decimal arithmetic, rounded to fen.
    public var cnyPerUnit: Decimal
    public var updatedAt: Date
    public init(currency: BillCurrency, cnyPerUnit: Decimal, updatedAt: Date) {
        self.currency = currency; self.cnyPerUnit = cnyPerUnit; self.updatedAt = updatedAt
    }
    public var isValid: Bool {
        !cnyPerUnit.isNaN && cnyPerUnit > 0 && cnyPerUnit <= 100_000 && currency != .cny &&
        (-2_208_988_800...7_258_118_400).contains(updatedAt.timeIntervalSince1970)
    }
    public var valueText: String { NSDecimalNumber(decimal: cnyPerUnit).stringValue }
    public var equation: String { "1 " + currency.unit + " = " + valueText + " 元" }
    public func convert(_ originalCents: Int64) -> Int64? {
        guard isValid, (0...Money.limit).contains(originalCents) else { return nil }
        var value = Decimal(originalCents) * cnyPerUnit, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded >= 0, rounded <= Decimal(Money.limit) else { return nil }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}

/// A future source can implement this synchronous quote contract. Only manual
/// quotes ship; no timers, network transport or automatic rates are involved.
public protocol BillExchangeRateSource: Sendable {
    func rate(for currency: BillCurrency, asOf date: Date) -> ManualExchangeRate?
}
public struct ManualBillExchangeRates: BillExchangeRateSource {
    public var rates: [ManualExchangeRate]
    public init(_ rates: [ManualExchangeRate]) { self.rates = rates }
    public func rate(for currency: BillCurrency, asOf date: Date) -> ManualExchangeRate? {
        rates.filter { $0.currency == currency && $0.isValid && $0.updatedAt <= date }.max { $0.updatedAt < $1.updatedAt }
    }
}

extension FixedFlows {
    static func validateCurrencies(in ledger: Ledger) throws {
        let rates = ledger.preferences.billExchangeRates ?? []
        guard rates.count <= BillCurrency.allCases.count,
              Set(rates.map(\.currency)).count == rates.count, rates.allSatisfy(\.isValid),
              ledger.plans.allSatisfy({ plan in
                  guard plan.currency != .cny else { return true }
                  return rates.first { $0.currency == plan.currency }?.convert(plan.amount).map { $0 > 0 } == true
              }) else { throw YubaiError.invalid("填写有效汇率。") }
    }
    public static func setRate(_ rate: ManualExchangeRate, in ledger: inout Ledger) throws {
        guard rate.isValid else { throw YubaiError.invalid("填写有效汇率。") }
        var next = ledger
        var rates = next.preferences.billExchangeRates ?? []
        rates.removeAll { $0.currency == rate.currency }; rates.append(rate)
        next.preferences.billExchangeRates = rates
        next.preferences.lastBillCurrency = rate.currency
        try next.validate(); ledger = next
    }
    public static func exchangeRate(for currency: BillCurrency, in ledger: Ledger, now: Date) -> ManualExchangeRate? {
        ManualBillExchangeRates(ledger.preferences.billExchangeRates ?? []).rate(for: currency, asOf: now)
    }
    public static func lastActual(planID: UUID, in ledger: Ledger, now: Date) -> Int64? {
        guard let plan = ledger.plans.first(where: { $0.id == planID }),
              let entry = FixedFlowPayments(in: ledger, now: now).actual[planID],
              plan.estimatedAmountSince.map({ (entry.recordedAt ?? entry.date) > $0 }) ?? true else { return nil }
        return entry.amount
    }
}
