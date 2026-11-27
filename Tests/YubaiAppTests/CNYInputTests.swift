import XCTest
import YubaiCore
@testable import YubaiApp

/// Typed amounts are saved as CNY, so every keypad sheet shows CNY even when the main currency is not.
@MainActor
final class CNYInputTests: XCTestCase {
    private let now = Dates.parse("2026-11-27 09:00:00")!

    override func tearDown() {
        DisplayCurrency.configure(Ledger(), synced: nil, now: now)
        super.tearDown()
    }

    private func usdLedger() throws -> Ledger {
        var ledger = Ledger()
        try FixedFlows.setRate(ManualExchangeRate(currency: .usd, cnyPerUnit: Decimal(string: "7.11")!, updatedAt: now), in: &ledger)
        try ExchangeRates.setMainCurrency(.usd, in: &ledger, synced: nil, now: now)
        return ledger
    }

    func testKeypadSheetsShowCNYWhateverTheMainCurrency() throws {
        DisplayCurrency.configure(try usdLedger(), synced: nil, now: now)
        // Home follows the main currency…
        XCTAssertEqual(HomeDisplay.money(720_000, hidden: false, currency: true), "US$1,012.66")
        // …but the reconcile box starts from the ¥7,200 the ledger holds, so 完成 writes no adjustment.
        XCTAssertEqual(SettingsDisplay.typed(SettingsDisplay.inputMoney(720_000), hidden: false), "¥7,200.00")
        XCTAssertEqual(SettingsDisplay.typed("7,2", hidden: false), "¥7,2")
        XCTAssertEqual(SettingsDisplay.typed("7,2", hidden: true), "¥••••")
        // Chips and helper numbers beside the box stay in CNY too.
        XCTAssertEqual(SettingsDisplay.cny(300_000, hidden: false), "3,000.00")
        XCTAssertEqual(SettingsDisplay.cny(-1_250, hidden: false, symbol: true), "−¥12.50")
        XCTAssertEqual(SettingsDisplay.cnySigned(-618_700, hidden: false), "−¥6,187.00")
        XCTAssertEqual(SettingsDisplay.cnySigned(500, hidden: false), "+¥5.00")
    }
}
