import Foundation
import YubaiCore

/// Spec-Currency 什么时候同步: on the way back to the foreground, when the last success is older than
/// 12 hours and 每天自动更新 is on, fetch the ECB daily reference rates once. Recording never waits for it;
/// a failure is silent and the settings row shows the age of the last good sync (X-sync-fail).
extension AppStore {
    /// Fixtures and UI tests never reach the network.
    private var mayFetchRates: Bool {
        guard !isDesignFixture else { return false }
        if ProcessInfo.processInfo.arguments.contains("--test-ledger") { return false }
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { return false }
        #endif
        return true
    }

    func syncExchangeRatesIfNeeded(force: Bool = false) async {
        guard mayFetchRates, !rateSyncRunning, !locked, loadFailure == nil else { return }
        guard force || ExchangeRates.needsSync(current, now: Date()) else { return }
        rateSyncRunning = true
        defer { rateSyncRunning = false }
        do {
            var request = URLRequest(url: ExchangeRates.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("Yubai", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let rates = try ExchangeRates.parseECB(data, fetchedAt: Date())
            _ = update("汇率同步", preservingUpdatedAt: true, recordUndo: false, reportError: false,
                       entryMotion: false, showToast: false) { try ExchangeRates.apply(rates, to: &$0) }
        } catch {
            // Silent by design: the last rates stay in use.
        }
    }
}

/// 主币种 only changes display. Every amount that goes through `HomeDisplay.money` is shown in the
/// main currency at the latest rate; the ledger stays in CNY.
/// Written on the main actor when the ledger's preferences change; read by the display funnels.
enum DisplayCurrency {
    nonisolated(unsafe) private(set) static var main: BillCurrency = .cny
    nonisolated(unsafe) private(set) static var cnyPerUnit: Decimal = 1

    @MainActor static func configure(_ ledger: Ledger, now: Date) {
        let currency = ledger.preferences.mainCurrency ?? .cny
        guard currency != .cny, let rate = ExchangeRates.rate(for: currency, in: ledger, now: now), rate.cnyPerUnit > 0 else {
            main = .cny; cnyPerUnit = 1; return
        }
        main = currency; cnyPerUnit = rate.cnyPerUnit
    }

    static var symbol: String { main.symbol }

    static func convert(_ cnyCents: Int64) -> Int64 {
        guard main != .cny else { return cnyCents }
        var value = Decimal(cnyCents) / cnyPerUnit, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard abs(rounded) <= Decimal(Money.limit) else { return cnyCents }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
