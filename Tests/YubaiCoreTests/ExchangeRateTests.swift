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
    private func input(_ cents: Int64, _ currency: BillCurrency, typed: Decimal? = nil, account: UUID, synced: SyncedExchangeRates? = nil) -> EntrySaveInput {
        var value = EntrySaveInput(type: .expense, amountCents: cents, currency: currency, exchangeRate: typed,
                                   purpose: "咖啡", category: "餐饮", accountID: account, date: now)
        value.syncedRates = synced
        return value
    }

    func testRemovingAFixedRateFallsBackToTheSyncedOneUnlessAPlanNeedsIt() throws {
        var ledger = ledger()
        let synced = try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now)
        try FixedFlows.setRate(ManualExchangeRate(currency: .usd, cnyPerUnit: 7.2, updatedAt: now), in: &ledger)
        XCTAssertEqual(ExchangeRates.rate(for: .usd, in: ledger, synced: synced, now: now)?.manual, true)
        try FixedFlows.removeRate(.usd, in: &ledger)
        XCTAssertEqual(ExchangeRates.rate(for: .usd, in: ledger, synced: synced, now: now)?.manual, false)
        XCTAssertNil(ledger.preferences.billExchangeRates)

        try FixedFlows.setRate(ManualExchangeRate(currency: .usd, cnyPerUnit: 7.2, updatedAt: now), in: &ledger)
        var plan = Plan(title: "iCloud", amount: 999, dueDate: now, frequency: .monthly, inflow: false, category: "会员订阅")
        plan.currency = .usd
        ledger.plans = [plan]
        XCTAssertThrowsError(try FixedFlows.removeRate(.usd, in: &ledger))
    }

    func testYenIsShownWhole() {
        XCTAssertEqual(BillCurrency.jpy.amountText(128_000), "JP¥1,280")
        XCTAssertEqual(BillCurrency.jpy.formatted(208_333), "2,083")
        XCTAssertEqual(BillCurrency.cad.amountText(425), "C$4.25")
    }

    func testParsesECBIntoCNYPerUnit() throws {
        let rates = try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now)
        XCTAssertEqual(rates.date, Dates.parse("2026-11-26"))
        XCTAssertEqual(rates.rate(for: .eur), Decimal(string: "7.6518"))
        XCTAssertEqual(rates.rate(for: .cad), Decimal(string: "5.1012"))
        XCTAssertEqual(rates.rate(for: .jpy), Decimal(string: "0.04782375"))
        XCTAssertNil(rates.rate(for: .hkd)); XCTAssertNil(rates.cnyPerUnit["XXX"])
        XCTAssertThrowsError(try ExchangeRates.parseECB(Data("<Cube currency='USD' rate='1'/>".utf8), fetchedAt: now))
        XCTAssertThrowsError(try ExchangeRates.parseECB(Data("<Cube time='2026-11-26'><Cube currency='CNY' rate='7.6'/>".utf8), fetchedAt: now))
        let garbage = try ExchangeRates.parseECB(Data(ecb.replacingOccurrences(of: "1.5000", with: "1.5garbage").utf8), fetchedAt: now)
        XCTAssertNil(garbage.rate(for: .cad))
    }

    func testSyncCadenceIsTwelveHoursBacksOffAfterFailuresAndCanBeTurnedOff() throws {
        var state = RateSyncState()
        XCTAssertTrue(ExchangeRates.needsSync(autoSync: true, state: state, now: now))
        try state.succeeded(ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now), at: now)
        XCTAssertFalse(ExchangeRates.needsSync(autoSync: true, state: state, now: now.addingTimeInterval(11 * 3600)))
        XCTAssertTrue(ExchangeRates.needsSync(autoSync: true, state: state, now: now.addingTimeInterval(12 * 3600)))
        XCTAssertFalse(ExchangeRates.isStale(state, now: now.addingTimeInterval(6 * 86_400)))
        XCTAssertTrue(ExchangeRates.isStale(state, now: now.addingTimeInterval(7 * 86_400)))
        XCTAssertFalse(ExchangeRates.needsSync(autoSync: false, state: state, now: now.addingTimeInterval(30 * 86_400)))
        // Failures wait 15 min, then 30, …, never longer than 12 hours, instead of retrying on every return.
        let later = now.addingTimeInterval(13 * 3600)
        state.failed("网络连不上", at: later)
        XCTAssertFalse(ExchangeRates.needsSync(autoSync: true, state: state, now: later.addingTimeInterval(14 * 60)))
        XCTAssertTrue(ExchangeRates.needsSync(autoSync: true, state: state, now: later.addingTimeInterval(15 * 60)))
        state.failed("网络连不上", at: later)
        XCTAssertFalse(ExchangeRates.needsSync(autoSync: true, state: state, now: later.addingTimeInterval(29 * 60)))
        for _ in 0..<20 { state.failed("网络连不上", at: later) }
        XCTAssertTrue(ExchangeRates.needsSync(autoSync: true, state: state, now: later.addingTimeInterval(12 * 3600)))
        XCTAssertEqual(state.lastError, "网络连不上")
        let decoded = try JSONDecoder().decode(RateSyncState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }

    func testSyncedRatesNeverGoIntoTheLedger() throws {
        var l = ledger()
        l.preferences.mainCurrency = .usd
        let encoded = String(decoding: try JSONEncoder().encode(l), as: UTF8.self)
        XCTAssertFalse(encoded.contains("syncedRates"))
        XCTAssertTrue(encoded.contains("mainCurrency"))
        // An older build's ledger: its rates are read for this device to adopt, and the next save drops them.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        var preferences = try XCTUnwrap(object["preferences"] as? [String: Any])
        let rates = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SyncedExchangeRates(date: now, fetchedAt: now, cnyPerUnit: ["USD": 7.5])))
        preferences["syncedRates"] = rates; object["preferences"] = preferences
        let old = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.preferences.legacySyncedRates?.rate(for: .usd), 7.5)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(old), as: UTF8.self).contains("syncedRates"))
    }

    func testEntryFreezesRateAndLaterSyncNeverChangesIt() throws {
        var l = ledger(); let account = l.accounts[0].id
        XCTAssertNil(EntrySaveMapper.cnyAmount(for: input(425, .cad, account: account), in: l, now: now))
        let synced = try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now)
        try EntrySaveMapper.makeChange(input(425, .cad, account: account, synced: synced), in: l, now: now).apply(to: &l)
        let saved = try XCTUnwrap(l.entries.last)
        XCTAssertEqual(saved.amount, 2168)
        XCTAssertEqual(saved.exchangeRate, EntryRate(cnyPerUnit: Decimal(string: "5.1012")!, date: Dates.parse("2026-11-26")!, manual: false))
        var later = synced; later.cnyPerUnit["CAD"] = 6; later.fetchedAt = now.addingTimeInterval(86_400)
        XCTAssertEqual(l.entries.last?.amount, 2168)
        try EntrySaveMapper.edit(saved.id, input: input(425, .cad, account: account, synced: later), in: &l, now: now.addingTimeInterval(86_400))
        XCTAssertEqual(l.entries.last?.amount, 2168); XCTAssertEqual(l.entries.last?.exchangeRate?.cnyPerUnit, Decimal(string: "5.1012"))
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(decoded.entries.last?.exchangeRate, l.entries.last?.exchangeRate)
    }

    func testTypedRateOverridesOnlyThisEntry() throws {
        var l = ledger(); let account = l.accounts[0].id
        let synced = try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now)
        try EntrySaveMapper.makeChange(input(425, .cad, typed: 5, account: account, synced: synced), in: l, now: now).apply(to: &l)
        XCTAssertEqual(l.entries.last?.amount, 2125); XCTAssertEqual(l.entries.last?.exchangeRate?.manual, true)
        XCTAssertEqual(ExchangeRates.rate(for: .cad, in: l, synced: synced, now: now)?.cnyPerUnit, Decimal(string: "5.1012"))
    }

    func testMainCurrencyChangesDisplayOnly() throws {
        var l = ledger()
        XCTAssertThrowsError(try ExchangeRates.setMainCurrency(.cad, in: &l, synced: nil, now: now))
        let synced = try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now)
        try ExchangeRates.setMainCurrency(.cad, in: &l, synced: synced, now: now)
        let display = MoneyDisplay(ledger: l, synced: synced, now: now)
        XCTAssertEqual(display.convert(51_012).currency, .cad)
        XCTAssertEqual(display.convert(51_012).minor, 10_000)
        try ExchangeRates.setMainCurrency(.cny, in: &l, synced: synced, now: now)
        XCTAssertNil(l.preferences.mainCurrency)
        XCTAssertEqual(MoneyDisplay(ledger: l, synced: synced, now: now).convert(51_012).minor, 51_012)
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

    func testPartialSyncKeepsQuotesItDoesNotMentionWithTheirOwnDate() throws {
        var state = RateSyncState()
        try state.succeeded(ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now), at: now)
        let partial = ecb.replacingOccurrences(of: "<Cube currency='CAD' rate='1.5000'/>", with: "")
            .replacingOccurrences(of: "2026-11-26", with: "2026-11-27")
        try state.succeeded(ExchangeRates.parseECB(Data(partial.utf8), fetchedAt: now.addingTimeInterval(86_400)), at: now.addingTimeInterval(86_400))
        XCTAssertEqual(state.rates?.rate(for: .cad), Decimal(string: "5.1012"))
        XCTAssertEqual(state.rates?.quoteDate(for: .cad), Dates.parse("2026-11-26"), "the kept quote keeps its old date")
        XCTAssertEqual(state.rates?.quoteDate(for: .usd), Dates.parse("2026-11-27"))
        XCTAssertEqual(ExchangeRates.rate(for: .cad, in: ledger(), synced: state.rates, now: now)?.date, Dates.parse("2026-11-26"))
    }

    func testSameReferenceDateDoesNotRewriteRates() throws {
        var state = RateSyncState()
        try state.succeeded(ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now), at: now)
        let first = state.rates
        try state.succeeded(ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now.addingTimeInterval(3600)), at: now.addingTimeInterval(3600))
        XCTAssertEqual(state.rates, first, "unchanged quotes keep the stored copy")
        XCTAssertEqual(state.lastSuccess, now.addingTimeInterval(3600))
    }

    func testDisplayRoundsOnceAndNeverOverflows() throws {
        let yen = MoneyDisplay(currency: .jpy, cnyPerUnit: Decimal(string: "0.0478")!)
        // ¥0.72 is 15.06 yen: one rounding gives 15; rounding to cents first and then to yen could give 16.
        XCTAssertEqual(yen.text(72), "15")
        // ¥1.41 is 29.498 yen: once, 29; via 29.50 it would be 30.
        XCTAssertEqual(yen.text(141), "29")
        XCTAssertEqual(yen.text(717, symbol: true), "JP¥150")
        XCTAssertEqual(yen.text(-717, symbol: true), "-JP¥150")
        let usd = MoneyDisplay(currency: .usd, cnyPerUnit: 7)
        XCTAssertEqual(usd.text(700, symbol: true), "US$1.00")
        XCTAssertEqual(usd.text(-1_000), "-1.43")
        let tiny = MoneyDisplay(currency: .usd, cnyPerUnit: Decimal(string: "0.0000001")!)
        XCTAssertEqual(tiny.convert(Money.limit).currency, .cny)
        XCTAssertEqual(tiny.text(Money.limit, symbol: true), "¥" + Money.text(Money.limit, currency: false), "CNY numbers keep ¥")
        XCTAssertEqual(MoneyDisplay.cny.text(123_456, symbol: true), "¥1,234.56")
        XCTAssertTrue(tiny.text(Money.limit).hasPrefix("¥"), "a CNY fallback says ¥ even where the main currency shows no symbol")
    }

    func testRetainedQuotesKeepTheirDateAndOlderAnswersAreIgnored() throws {
        let monday = Dates.parse("2026-11-23")!, tuesday = Dates.parse("2026-11-24")!
        var state = RateSyncState()
        try state.succeeded(SyncedExchangeRates(date: monday, fetchedAt: monday, cnyPerUnit: ["USD": 7.1, "CAD": 5.1]), at: monday)
        // Tuesday's answer lacks CAD: CAD stays, with Monday's date.
        try state.succeeded(SyncedExchangeRates(date: tuesday, fetchedAt: tuesday, cnyPerUnit: ["USD": 7.2]), at: tuesday)
        XCTAssertEqual(state.rates?.quoteDate(for: .cad), monday)
        XCTAssertEqual(state.rates?.quoteDate(for: .usd), tuesday)
        // A later answer the same day brings CAD back at the same price: its date moves to Tuesday.
        try state.succeeded(SyncedExchangeRates(date: tuesday, fetchedAt: tuesday, cnyPerUnit: ["USD": 7.2, "CAD": 5.1]), at: tuesday)
        XCTAssertEqual(state.rates?.quoteDate(for: .cad), tuesday)
        // A stale cache answering with Monday changes nothing.
        try state.succeeded(SyncedExchangeRates(date: monday, fetchedAt: tuesday, cnyPerUnit: ["USD": 7.0]), at: tuesday)
        XCTAssertEqual(state.rates?.rate(for: .usd), 7.2)
    }

    func testRatesAnOlderBuildKeptInTheLedgerAreAdoptedOnce() throws {
        let old = #"{"date":"2026-11-26T00:00:00Z","fetchedAt":"2026-11-26T09:00:00Z","cnyPerUnit":{"USD":7.11}}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(SyncedExchangeRates.self, from: Data(old.utf8))
        var state = RateSyncState()
        state.adoptLegacy(legacy)
        XCTAssertEqual(state.rates?.rate(for: .usd), Decimal(string: "7.11"))
        XCTAssertEqual(state.lastSuccess, legacy.fetchedAt)
        var newer = state
        newer.adoptLegacy(SyncedExchangeRates(date: now, fetchedAt: now, cnyPerUnit: ["USD": 9]))
        XCTAssertEqual(newer.rates?.rate(for: .usd), Decimal(string: "7.11"), "the device's own rates win")
    }

    func testEditingALegacyForeignEntryKeepsItsBookedAmount() throws {
        var l = ledger(); let account = l.accounts[0].id
        var legacy = Entry(date: now, amount: 2125, accountID: account, title: "咖啡", category: "餐饮")
        legacy.originalCurrency = .cad; legacy.originalAmount = 425
        l.entries.append(legacy)
        try EntrySaveMapper.edit(legacy.id, input: input(425, .cad, account: account, synced: try ExchangeRates.parseECB(Data(ecb.utf8), fetchedAt: now)), in: &l, now: now)
        XCTAssertEqual(l.entries.last?.amount, 2125); XCTAssertEqual(l.entries.last?.exchangeRate?.cnyPerUnit, 5)
        try EntrySaveMapper.edit(legacy.id, input: input(850, .cad, account: account), in: &l, now: now)
        XCTAssertEqual(l.entries.last?.amount, 4250)
    }

    func testImportMergeKeepsOrReplacesTheFrozenRate() {
        let account = UUID()
        var manual = Entry(date: now, amount: 2168, accountID: account, title: "咖啡", category: "餐饮")
        manual.originalCurrency = .cad; manual.originalAmount = 425
        manual.exchangeRate = EntryRate(cnyPerUnit: Decimal(string: "5.1012")!, date: now, manual: false)
        let same = Entry(date: now, amount: 2168, accountID: account, title: "STARBUCKS", category: "餐饮")
        XCTAssertEqual(BillImporter.mergedImport(same, preserving: manual, accountIsUnknown: false).exchangeRate, manual.exchangeRate)
        let charged = Entry(date: now, amount: 2210, accountID: account, title: "STARBUCKS", category: "餐饮")
        XCTAssertEqual(BillImporter.mergedImport(charged, preserving: manual, accountIsUnknown: false).exchangeRate?.cnyPerUnit, Decimal(2210) / Decimal(425))
    }

    func testShortcutDefaultSourceCountsAsSiri() throws {
        var l = ledger()
        let draft = EntryDraft(date: now, amount: 3200, amountConfirmed: true, accountID: l.accounts[0].id, title: "午饭", category: "餐饮")
        try QuickCapture.record([draft], in: &l, now: now)
        XCTAssertEqual(QuickCapture.recentCount(.siri, in: l, now: now), 1)
    }
}
