import XCTest
@testable import YubaiCore

final class ExchangeRateTests: XCTestCase {
    private let now = Dates.parse("2026-11-27 09:00:00")!
    private let ecb = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
    <Cube><Cube time='2026-11-26'>
    <Cube currency='USD' rate='1.0500'/><Cube currency='JPY' rate='160.00'/><Cube currency='CAD' rate='1.5000'/>
    <Cube currency='CNY' rate='7.6518'/><Cube currency='XXX' rate='2'/>
    </Cube></Cube></gesmes:Envelope>
    """

    private func ledger() -> Ledger {
        var ledger = Ledger()
        ledger.accounts = [Account(name: "银行卡", balance: 1_000_000, at: now.addingTimeInterval(-86_400))]
        return ledger
    }
    private func input(_ cents: Int64, _ currency: BillCurrency, typed: Decimal? = nil, account: UUID) -> EntrySaveInput {
        EntrySaveInput(type: .expense, amountCents: cents, currency: currency, exchangeRate: typed,
                       purpose: "咖啡", category: "餐饮", accountID: account, date: now)
    }

    func testParsesECBIntoCNYPerUnit() throws {
        let rates = try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now)
        XCTAssertEqual(rates.date, Dates.parse("2026-11-26"))
        XCTAssertEqual(rates.rate(for: .eur), Decimal(string: "7.6518"))
        XCTAssertEqual(rates.rate(for: .cad), Decimal(string: "5.1012"))
        XCTAssertEqual(rates.rate(for: .jpy), Decimal(string: "0.047824"))
        XCTAssertNil(rates.rate(for: .hkd)); XCTAssertNil(rates.cnyPerUnit["XXX"])
        XCTAssertThrowsError(try ExchangeRates.parseECB(Data("<Cube currency='USD' rate='1'/>".utf8), fetchedAt: now))
    }

    func testSyncCadenceIsTwelveHoursAndCanBeTurnedOff() throws {
        var l = ledger()
        XCTAssertTrue(ExchangeRates.needsSync(l, now: now))
        try ExchangeRates.apply(try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now), to: &l)
        XCTAssertFalse(ExchangeRates.needsSync(l, now: now.addingTimeInterval(11 * 3600)))
        XCTAssertTrue(ExchangeRates.needsSync(l, now: now.addingTimeInterval(12 * 3600)))
        XCTAssertFalse(ExchangeRates.isStale(l, now: now.addingTimeInterval(6 * 86_400)))
        XCTAssertTrue(ExchangeRates.isStale(l, now: now.addingTimeInterval(7 * 86_400)))
        l.preferences.autoRateSync = false
        XCTAssertFalse(ExchangeRates.needsSync(l, now: now.addingTimeInterval(30 * 86_400)))
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(decoded.preferences.syncedRates, l.preferences.syncedRates)
        XCTAssertEqual(decoded.preferences.autoRateSync, false)
    }

    func testEntryFreezesRateAndLaterSyncNeverChangesIt() throws {
        var l = ledger(); let account = l.accounts[0].id
        XCTAssertNil(EntrySaveMapper.cnyAmount(for: input(425, .cad, account: account), in: l, now: now))
        try ExchangeRates.apply(try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now), to: &l)
        try EntrySaveMapper.makeChange(input(425, .cad, account: account), in: l, now: now).apply(to: &l)
        let saved = try XCTUnwrap(l.entries.last)
        XCTAssertEqual(saved.amount, 2168)
        XCTAssertEqual(saved.exchangeRate, EntryRate(cnyPerUnit: Decimal(string: "5.1012")!, date: Dates.parse("2026-11-26")!, manual: false))
        var later = l.preferences.syncedRates!; later.cnyPerUnit["CAD"] = 6; later.fetchedAt = now.addingTimeInterval(86_400)
        try ExchangeRates.apply(later, to: &l)
        XCTAssertEqual(l.entries.last?.amount, 2168)
        try EntrySaveMapper.edit(saved.id, input: input(425, .cad, account: account), in: &l, now: now.addingTimeInterval(86_400))
        XCTAssertEqual(l.entries.last?.amount, 2168); XCTAssertEqual(l.entries.last?.exchangeRate?.cnyPerUnit, Decimal(string: "5.1012"))
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(decoded.entries.last?.exchangeRate, l.entries.last?.exchangeRate)
    }

    func testTypedRateOverridesOnlyThisEntry() throws {
        var l = ledger(); let account = l.accounts[0].id
        try ExchangeRates.apply(try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now), to: &l)
        try EntrySaveMapper.makeChange(input(425, .cad, typed: 5, account: account), in: l, now: now).apply(to: &l)
        XCTAssertEqual(l.entries.last?.amount, 2125); XCTAssertEqual(l.entries.last?.exchangeRate?.manual, true)
        XCTAssertEqual(ExchangeRates.rate(for: .cad, in: l, now: now)?.cnyPerUnit, Decimal(string: "5.1012"))
    }

    func testMainCurrencyChangesDisplayOnly() throws {
        var l = ledger()
        XCTAssertThrowsError(try ExchangeRates.setMainCurrency(.cad, in: &l, now: now))
        try ExchangeRates.apply(try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now), to: &l)
        try ExchangeRates.setMainCurrency(.cad, in: &l, now: now)
        XCTAssertEqual(ExchangeRates.display(51_012, in: l, now: now).currency, .cad)
        XCTAssertEqual(ExchangeRates.display(51_012, in: l, now: now).cents, 10_000)
        try ExchangeRates.setMainCurrency(.cny, in: &l, now: now)
        XCTAssertNil(l.preferences.mainCurrency)
        XCTAssertEqual(ExchangeRates.display(51_012, in: l, now: now).cents, 51_012)
    }

    func testQuickCaptureCountsEachEntranceOverSevenDays() throws {
        var l = ledger()
        _ = try QuickCapture.applePay(merchant: "瑞幸", amount: "18", card: "招行", date: now, in: &l, now: now)
        _ = try QuickCapture.applePay(merchant: "全家", amount: "9", card: "招行", date: now.addingTimeInterval(-8 * 86_400), in: &l, now: now.addingTimeInterval(-8 * 86_400))
        let draft = EntryDraft(date: now, amount: 3200, amountConfirmed: true, accountID: l.accounts[0].id, title: "午饭", category: "餐饮")
        try QuickCapture.record([draft], in: &l, source: QuickCapture.Entrance.siri.rawValue, now: now)
        XCTAssertEqual(QuickCapture.recentCount(.applePay, in: l, now: now), 1)
        XCTAssertEqual(QuickCapture.recentCount(.siri, in: l, now: now), 1)
    }
}
