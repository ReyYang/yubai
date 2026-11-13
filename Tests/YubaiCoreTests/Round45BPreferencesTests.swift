import XCTest
@testable import YubaiCore

final class Round45BPreferencesTests: XCTestCase {
    let now = Round45BFixture.now
    func d(_ text: String) -> Date { Round45BFixture.d(text) }
    func testAITogglesDefaultToMasterSwitchAndPersistIndependentOptOuts() throws {
        var preferences = Preferences()
        XCTAssertTrue(AIFeature.allCases.allSatisfy { !preferences.isAIEnabled(for: $0) })
        preferences.cloudAIEnabled = true
        XCTAssertTrue(AIFeature.allCases.allSatisfy { preferences.isAIEnabled(for: $0) })
        for feature in AIFeature.allCases {
            var individual = preferences; individual.setAIEnabled(false, for: feature)
            XCTAssertFalse(individual.isAIEnabled(for: feature))
            XCTAssertTrue(AIFeature.allCases.filter { $0 != feature }.allSatisfy { individual.isAIEnabled(for: $0) })
            let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(individual))
            XCTAssertEqual(individual, decoded)
            individual.cloudAIEnabled = false; individual.cloudAIEnabled = true
            XCTAssertFalse(individual.isAIEnabled(for: feature))
            individual.setAIEnabled(true, for: feature); XCTAssertEqual(individual, preferences)
        }
        preferences.setAIEnabled(false, for: .answers)
        XCTAssertNil(CloudBackend.configured(preferences: preferences, feature: .answers, environment: [:]))
    }
    func testNewFalseFlagsAndEmptyCollectionsAreOmitted() throws {
        var ledger = Round45BFixture.ledger()
        ledger.reservePaybacks = []; ledger.repeatPreferences = []
        ledger.preferences.weeklyAutoBackup = false; ledger.preferences.aiAnswersDisabled = false
        var plan = Plan(title: "电费", amount: 1000, dueDate: now); plan.occurrenceDateOverrides = [:]
        ledger.plans = [plan]
        let data = try JSONEncoder().encode(ledger), text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for key in ["reservePaybacks", "repeatPreferences", "occurrenceDateOverrides", "weeklyAutoBackup", "aiAnswersDisabled"] {
            XCTAssertFalse(text.contains("\"" + key + "\""), key)
        }
    }
    func testSchema4ArchiveWithoutNewKeysRetainsOldBehavior() throws {
        let original = Round45Fixture.ledger()
        let bytes = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["reservePaybacks", "repeatPreferences"] { json.removeValue(forKey: key) }
        var preferences = try XCTUnwrap(json["preferences"] as? [String: Any])
        for key in ["weeklyAutoBackup", "aiImportClassificationDisabled", "aiAnswersDisabled", "aiWeeklyReviewDisabled", "aiReceiptRecognitionDisabled"] { preferences.removeValue(forKey: key) }
        json["preferences"] = preferences
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.schema, 4); XCTAssertEqual(decoded, original)
        XCTAssertEqual(Finance.funds(decoded, now: now), Finance.funds(original, now: now))
        XCTAssertEqual(Reserve.overview(decoded, now: now), Reserve.overview(original, now: now))
        XCTAssertEqual(Finance.pace(decoded, now: now), Finance.pace(original, now: now))
    }
    func testWeeklyBackupDueAtSevenDaysAndBookkeepingIsMonotonic() {
        var preferences = Preferences()
        XCTAssertFalse(LedgerBackup.isAutoBackupDue(preferences, now: now))
        preferences.weeklyAutoBackup = true; XCTAssertTrue(LedgerBackup.isAutoBackupDue(preferences, now: now))
        LedgerBackup.recordDone(in: &preferences, now: now)
        XCTAssertFalse(LedgerBackup.isAutoBackupDue(preferences, now: Dates.addDays(7, to: now).addingTimeInterval(-1)))
        XCTAssertTrue(LedgerBackup.isAutoBackupDue(preferences, now: Dates.addDays(7, to: now)))
        LedgerBackup.recordDone(in: &preferences, now: now.addingTimeInterval(-1)); XCTAssertEqual(preferences.lastBackupAt, now)
        preferences.weeklyAutoBackup = nil; XCTAssertFalse(LedgerBackup.isAutoBackupDue(preferences, now: Dates.addDays(20, to: now)))
    }
    func testCSVHasBOMChineseHeaderExactCentsAndEscapedOriginalText() throws {
        var ledger = Round45BFixture.ledger()
        var row = Round45BFixture.entry(ledger, date: "2026-11-20", amount: 100, title: "商店,\"甲\"")
        row.note = "第一行\n第二行"; ledger.entries = [row]
        ledger.entries.append(Round45BFixture.entry(ledger, date: "2026-12-20", amount: 1, nature: .income))
        var deleted = row; deleted.id = UUID(); deleted.deletedAt = now; ledger.entries.append(deleted)
        let csv = LedgerBackup.entriesCSV(ledger)
        XCTAssertTrue(csv.starts(with: [0xef, 0xbb, 0xbf]))
        let table = try CSV.parse(CSV.decode(csv))
        XCTAssertEqual(table.count, 3); XCTAssertEqual(table[0][0], "日期")
        XCTAssertEqual(table[1][1], "1.00"); XCTAssertEqual(table[2][1], "0.01")
        XCTAssertEqual(table[1][3], row.title); XCTAssertEqual(table[1][8], row.note)
        XCTAssertEqual(try CSV.parse(CSV.decode(LedgerBackup.entriesCSV(Round45BFixture.ledger()))).count, 1)
    }
    func testPrincipleHoursThresholdStrictnessSpecificityAndFallback() {
        let principles = ["超过 2,000 等 48 小时", "超过 5,000 元等 7 天", "想克制一点"]
        XCTAssertEqual(Wishlist.cooldown(fromPrinciples: principles).map(\.hours), [168, 48])
        XCTAssertEqual(Wishlist.cooldownHours(amount: 200_001, fromPrinciples: principles), 48)
        XCTAssertEqual(Wishlist.cooldownHours(amount: 200_000, fromPrinciples: principles), 168)
        XCTAssertEqual(Wishlist.cooldownHours(amount: 500_001, fromPrinciples: principles), 168)
        XCTAssertEqual(Wishlist.cooldownHours(amount: 10_000, fromPrinciples: principles), 0)
        XCTAssertEqual(Wishlist.cooldownHours(amount: 20_000, fromPrinciples: []), 72)
        XCTAssertEqual(Wishlist.cooldownHours(amount: -1, fromPrinciples: principles), 0)
        XCTAssertTrue(Wishlist.cooldown(fromPrinciples: ["超过 -1 等 48 小时", "超过 0 等 1 天", "超过 200 等 0 小时", "超过 1 等 999999 天"]).isEmpty)
    }
    func testWishlistAddActuallyUsesHourPrinciple() throws {
        var ledger = Round45BFixture.ledger(); ledger.profile.principles = ["超过 2,000 等 48 小时"]
        let verdict = SubmittedPurchaseVerdict(verdict: .wait, reason: "先等等", need: .want, boundReason: "")
        let wish = try Wishlist.add(fromVerdict: verdict, title: "大衣", amount: 240_000, in: &ledger, now: now)
        XCTAssertEqual(wish.coolUntil, now.addingTimeInterval(48 * 3600))
        XCTAssertTrue(Wishlist.cooldownDue(ledger, now: now.addingTimeInterval(48 * 3600 - 1)).isEmpty)
        XCTAssertEqual(Wishlist.cooldownDue(ledger, now: now.addingTimeInterval(48 * 3600)).count, 1)
    }
    func testPinHideReorderAndUnpinRepeatsPersistAndInvalidateCache() throws {
        var ledger = Round45BFixture.ledger()
        for name in ["午饭", "地铁", "咖啡"] {
            for day in ["2026-11-18", "2026-11-19"] {
                var entry = Round45BFixture.entry(ledger, date: day, title: name); entry.recordedAt = entry.date
                ledger.entries.append(entry)
            }
        }
        let repeats = EntryHistory.repeats(in: ledger, now: now, limit: 10)
        XCTAssertEqual(repeats.count, 3)
        _ = Finance.funds(ledger, now: now)
        try EntryHistory.setPinned(repeats[1], pinned: true, in: &ledger)
        XCTAssertEqual(EntryHistory.repeats(in: ledger, now: now).first?.id, repeats[1].id)
        try EntryHistory.setHidden(repeats[0], hidden: true, in: &ledger)
        XCTAssertFalse(EntryHistory.repeats(in: ledger, now: now).contains { $0.id == repeats[0].id })
        try EntryHistory.reorder([repeats[2], repeats[1]], in: &ledger)
        XCTAssertEqual(EntryHistory.repeats(in: ledger, now: now).map(\.id), [repeats[2].id, repeats[1].id])
        XCTAssertEqual(EntryHistory.repeats(in: ledger, now: d("2027-01-01")).map(\.id), [repeats[2].id, repeats[1].id])
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)), ledger)
        try EntryHistory.setPinned(repeats[2], pinned: false, in: &ledger)
        XCTAssertEqual(EntryHistory.repeats(in: ledger, now: d("2027-01-01")).map(\.id), [repeats[1].id])
        let before = ledger
        XCTAssertThrowsError(try EntryHistory.reorder([repeats[1], repeats[1]], in: &ledger)); XCTAssertEqual(ledger, before)
        XCTAssertTrue(EntryHistory.repeats(in: ledger, now: now, limit: 0).isEmpty)
    }
    func testHiddenRepeatSnapshotSurvivesWindowAndUnhidesAsPinned() throws {
        var ledger = frequentLedger()
        let item = try XCTUnwrap(EntryHistory.repeats(in: ledger, now: now).first)
        try EntryHistory.setHidden(item, hidden: true, in: &ledger)
        XCTAssertNil(ledger.repeatPreferences?.first?.pinned)
        XCTAssertEqual(ledger.repeatPreferences?.first?.snapshot, item)
        XCTAssertTrue(EntryHistory.repeats(in: ledger, now: now).isEmpty)
        let later = Dates.addDays(31, to: now)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded.schema, 4); XCTAssertEqual(decoded, ledger); try decoded.validate()
        ledger = decoded
        let hidden = try XCTUnwrap(EntryHistory.hiddenRepeats(in: ledger, now: later).first)
        XCTAssertEqual(hidden.entry, item); XCTAssertEqual(hidden.purpose, item.purpose); XCTAssertEqual(hidden.amount, item.amount)
        try EntryHistory.setHidden(item, hidden: false, in: &ledger)
        XCTAssertTrue(EntryHistory.hiddenRepeats(in: ledger, now: later).isEmpty)
        XCTAssertEqual(EntryHistory.repeats(in: ledger, now: later), [item])
        XCTAssertEqual(ledger.repeatPreferences?.first?.pinned, item)
        XCTAssertNil(ledger.repeatPreferences?.first?.snapshot)
        try EntryHistory.setPinned(item, pinned: false, in: &ledger)
        XCTAssertTrue(EntryHistory.repeats(in: ledger, now: later).isEmpty); XCTAssertNil(ledger.repeatPreferences)
    }
    func testHiddenListingPrefersSnapshotThenLiveAutomaticRepeat() throws {
        var ledger = frequentLedger()
        let item = try XCTUnwrap(EntryHistory.repeats(in: ledger, now: now).first)
        try EntryHistory.setPinned(item, pinned: true, in: &ledger)
        XCTAssertNil(ledger.repeatPreferences?.first?.snapshot)
        try EntryHistory.setHidden(item, hidden: true, in: &ledger)
        let account = Account(name: "现金", kind: .cash, at: now); ledger.accounts.append(account)
        ledger.entries[1].accountID = account.id
        XCTAssertEqual(EntryHistory.hiddenRepeats(in: ledger, now: now).first?.entry, item)
        ledger.repeatPreferences?[0].snapshot = nil
        var live = item; live.accountID = account.id
        XCTAssertEqual(EntryHistory.hiddenRepeats(in: ledger, now: now).first?.entry, live)
        try EntryHistory.unhide(item.id, in: &ledger, now: now)
        XCTAssertEqual(EntryHistory.repeats(in: ledger, now: now), [live])
        XCTAssertNil(ledger.repeatPreferences)
    }
    func testLegacyHiddenRepeatDecodesAndFallsBackToUTF8NameAndAmount() throws {
        var ledger = frequentLedger(purpose: "午饭:🍜", amount: 1234)
        let item = try XCTUnwrap(EntryHistory.repeats(in: ledger, now: now).first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        json["repeatPreferences"] = [["id": item.id, "hidden": true]]
        ledger = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(ledger.schema, 4); XCTAssertNil(ledger.repeatPreferences?.first?.snapshot); try ledger.validate()
        XCTAssertEqual(EntryHistory.hiddenRepeats(in: ledger, now: now).first?.entry, item)
        let later = Dates.addDays(31, to: now)
        let hidden = try XCTUnwrap(EntryHistory.hiddenRepeats(in: ledger, now: later).first)
        XCTAssertNil(hidden.entry); XCTAssertEqual(hidden.purpose, "午饭:🍜"); XCTAssertEqual(hidden.amount, 1234)
        XCTAssertEqual(Money.text(try XCTUnwrap(hidden.amount), currency: false), "12.34")
        let encoded = try JSONEncoder().encode(ledger)
        XCTAssertFalse(try XCTUnwrap(String(data: encoded, encoding: .utf8)).contains("\"snapshot\""))
        XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: encoded), ledger)
        try EntryHistory.unhide(item.id, in: &ledger, now: later)
        XCTAssertNil(ledger.repeatPreferences); XCTAssertTrue(EntryHistory.repeats(in: ledger, now: later).isEmpty)
    }
    func testLegacyHiddenDisplayRejectsMalformedIDsWithoutInventingEntries() {
        var ledger = Round45BFixture.ledger()
        let ids = ["old-id", "999999999999999999999999:x:1:餐饮", "3:午饭:1000:餐饮", "1:午:1000:餐饮",
                   "6:午饭:0:餐饮", "6:午饭:-1:餐饮", "6:午饭:1.00:餐饮", "6:午饭:1000", "6:午饭:1000:",
                   "6:午饭:\(Money.limit + 1):餐饮"]
        ledger.repeatPreferences = ids.map { RepeatPreference(id: $0, hidden: true) }
        let hidden = EntryHistory.hiddenRepeats(in: ledger, now: now)
        XCTAssertEqual(hidden.map(\.id), ids)
        XCTAssertTrue(hidden.allSatisfy { $0.entry == nil && $0.purpose == nil && $0.amount == nil })
    }
    func testHiddenSnapshotsValidateTheSameContentAsPinnedRows() throws {
        var ledger = frequentLedger()
        let item = try XCTUnwrap(EntryHistory.repeats(in: ledger, now: now).first)
        var wrongID = item; wrongID.id = "wrong"
        var empty = item; empty.purpose = ""
        var long = item; long.purpose = String(repeating: "字", count: 4001)
        var zero = item; zero.amount = 0
        var negative = item; negative.amount = -1
        var excessive = item; excessive.amount = Money.limit + 1
        for invalid in [wrongID, empty, long, zero, negative, excessive] {
            ledger.repeatPreferences = [RepeatPreference(id: item.id, hidden: true, snapshot: invalid)]
            XCTAssertThrowsError(try ledger.validate())
            ledger.repeatPreferences = [RepeatPreference(id: item.id, pinned: invalid)]
            XCTAssertThrowsError(try ledger.validate())
        }
        ledger.repeatPreferences = [RepeatPreference(id: "", hidden: true, snapshot: item)]
        XCTAssertThrowsError(try ledger.validate())
        ledger.repeatPreferences = [RepeatPreference(id: item.id, hidden: true, snapshot: item)]
        XCTAssertNoThrow(try ledger.validate())
    }
    func testOnlyHiddenSnapshotsMayReferenceMissingAccounts() throws {
        var ledger = frequentLedger()
        let item = try XCTUnwrap(EntryHistory.repeats(in: ledger, now: now).first)
        try EntryHistory.setHidden(item, hidden: true, in: &ledger)
        ledger.entries = []; ledger.accounts = []
        XCTAssertNoThrow(try ledger.validate())
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger); XCTAssertNoThrow(try decoded.validate())
        XCTAssertEqual(EntryHistory.hiddenRepeats(in: decoded, now: Dates.addDays(31, to: now)).first?.entry, item)
        ledger.repeatPreferences = [RepeatPreference(id: item.id, snapshot: item)]
        XCTAssertThrowsError(try ledger.validate())
        ledger.repeatPreferences = [RepeatPreference(id: item.id, pinned: item)]
        XCTAssertThrowsError(try ledger.validate())
        ledger.repeatPreferences = [RepeatPreference(id: item.id, pinned: item, hidden: true, snapshot: item)]
        XCTAssertThrowsError(try ledger.validate())
    }
    func testUnhideReplacesDeletedOrArchivedAccountWithActiveDefault() throws {
        for deleted in [false, true] {
            var ledger = frequentLedger()
            let item = try XCTUnwrap(EntryHistory.repeats(in: ledger, now: now).first)
            try EntryHistory.setHidden(item, hidden: true, in: &ledger)
            ledger.entries = []
            if deleted { ledger.accounts = [] } else { ledger.accounts[0].archived = true }
            let account = Account(name: "现金", kind: .cash, at: now); ledger.accounts.append(account)
            XCTAssertNoThrow(try ledger.validate())
            let later = Dates.addDays(31, to: now)
            XCTAssertEqual(EntryHistory.hiddenRepeats(in: ledger, now: later).first?.entry, item)
            try EntryHistory.unhide(item.id, in: &ledger, now: later)
            var restored = item; restored.accountID = account.id
            XCTAssertEqual(EntryHistory.repeats(in: ledger, now: later), [restored])
            XCTAssertEqual(ledger.repeatPreferences?.first?.pinned, restored); XCTAssertNoThrow(try ledger.validate())
        }
    }
    func testUnhideWithoutActiveAccountsKeepsHiddenSnapshotAtomically() throws {
        for deleted in [false, true] {
            var ledger = frequentLedger()
            let item = try XCTUnwrap(EntryHistory.repeats(in: ledger, now: now).first)
            try EntryHistory.setHidden(item, hidden: true, in: &ledger)
            ledger.entries = []
            if deleted { ledger.accounts = [] } else { ledger.accounts[0].archived = true }
            let before = ledger
            XCTAssertThrowsError(try EntryHistory.unhide(item.id, in: &ledger, now: Dates.addDays(31, to: now))) {
                XCTAssertEqual($0 as? YubaiError, .invalid("请先添加账户。"))
            }
            XCTAssertEqual(ledger, before); XCTAssertNoThrow(try ledger.validate())
        }
    }
    private func frequentLedger(purpose: String = "午饭", amount: Int64 = 1000) -> Ledger {
        var ledger = Round45BFixture.ledger()
        for day in ["2026-11-18", "2026-11-19"] {
            var entry = Round45BFixture.entry(ledger, date: day, amount: amount, title: purpose)
            entry.recordedAt = entry.date; entry.subcategory = ledger.categories.first { $0.name == "餐饮" }?.subcategories.first
            ledger.entries.append(entry)
        }
        return ledger
    }
    func testAssistantDescriptionUsesRound45WordsAndMoneyValuesAreUnchanged() throws {
        let description = ReadOnlyTool.getFunds.description
        for word in ["每月存", "存着的钱", "这个周期", "日均"] { XCTAssertTrue(description.contains(word), word) }
        for word in ["要攒", "\u{5b58}\u{7740}\u{4e0d}\u{52a8}", "固定收付"] { XCTAssertFalse(description.contains(word)) }
        let ledger = Round45BFixture.ledger(), funds = Finance.funds(ledger, now: now)
        let result = try ReadOnlyTool.getFunds.run(.object([:]), ToolContext(ledger: ledger, now: now))
        XCTAssertEqual(result["available"], .money(funds.available)); XCTAssertEqual(result["saving_target"], .money(funds.savingTarget))
    }
}
