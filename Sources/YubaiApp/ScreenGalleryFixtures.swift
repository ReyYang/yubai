#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let galleryScripts: Set<String> = ["gallery", "gallery-empty", "gallery-locked"]
    static var galleryAppearance: String? {
        guard let value = ProcessInfo.processInfo.environment["YUBAI_GALLERY_APPEARANCE"], ["light", "dark"].contains(value) else { return nil }
        return value
    }
    // Stable IDs and day-relative dates: identical input day produces identical pixels/data.
    // Amounts in the domain are cents. Zero belongs to balances/targets, never invalid zero entries.
    static let galleryLongTitle = "为了搬家以后和家人朋友一起长期使用而认真挑选并且反复比较尺寸颜色材质保修与运输安排的生活用品"
    static let galleryLatinTitle = "SupercalifragilisticexpialidociousPneumonoultramicroscopicsilicovolcanoconiosis"
    static func galleryID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "47000000-0000-0000-0000-%012d", value))!
    }
    static func resetGalleryDeviceState(for ledgerID: UUID) {
        // Stable fixture IDs must not inherit a previous gallery's questions or snoozes.
        // Called only for a new UUID-isolated --test-ledger; touch this fixture's keys only.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "yubai.recentQuestions." + ledgerID.uuidString)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("yubai.snooze." + ledgerID.uuidString + ".") {
            defaults.removeObject(forKey: key)
        }
    }
    /// Exercise the real get_profile -> propose_entry -> user confirmation flow offline.
    /// Accounts and amounts come from the real tool response, never invented aliases.
    static func galleryReply(_ request: ChatRequest, script: String) throws -> ChatMessage? {
        guard script == "gallery", let lastUser = request.messages.lastIndex(where: { $0.role == .user }),
              request.messages[lastUser].content?.contains("合成午饭 28 元") == true else { return nil }
        let turn = request.messages.suffix(from: lastUser)
        if turn.contains(where: { $0.role == .tool && $0.toolCallID == "gallery-entries" }) {
            return ChatMessage(role: .assistant, content: "两笔待确认")
        }
        guard let profile = turn.last(where: { $0.role == .tool && $0.toolCallID == "gallery-profile" }) else {
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "gallery-profile", name: "get_profile")])
        }
        let facts = try JSONValue.parse(profile.content ?? "")
        guard let account = facts["entry_account_hint"]?.stringValue ?? facts["accounts"]?.arrayValue?.first?["id"]?.stringValue,
              let parsed = facts["parsed_entries"]?.arrayValue, parsed.count == 2 else {
            throw YubaiError.invalid("合成补记缺少账户或两笔本机金额。")
        }
        let rows: [JSONValue] = try parsed.map { row in
            guard let amount = row["amount"]?["text"]?.stringValue, let title = row["text"]?.stringValue else {
                throw YubaiError.invalid("合成补记缺少本机金额。")
            }
            return .object(["title": .string(title), "amount": .string(amount), "date": .string(Dates.text(Date())),
                            "account": .string(account), "nature": .string("expense"), "category": .string("餐饮")])
        }
        let args = try JSONValue.object(["reason": .string("合成补记"), "entries": .array(rows)]).jsonText()
        return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "gallery-entries", name: "propose_entry", arguments: args)])
    }
    static func galleryLedger(_ script: String, now: Date) throws -> Ledger {
        let today = Dates.day(now)
        let month = Dates.calendar.dateInterval(of: .month, for: today)!.start
        func day(_ offset: Int) -> Date { Dates.addDays(offset, to: today) }
        var ledger = Ledger()
        ledger.id = galleryID(1); ledger.updatedAt = today
        ledger.preferences.onboardingComplete = true
        ledger.preferences.profileColdStartDone = true
        // An explicit gallery-only preference avoids changing the simulator's global appearance.
        ledger.preferences.appearance = galleryAppearance ?? "light"
        ledger.lastReflectionWeek = ButlerCards.isoWeek(today)
        ledger.lastSubcategoryBatchDay = Dates.text(today)
        ledger.cycleAnchor = .calendarMonth
        if script == "gallery-empty" { try ledger.validate(); return ledger }
        ledger.preferences.lockEnabled = script == "gallery-locked"
        ledger.preferences.cloudAIEnabled = false // No background organization can alter the stress rows.
        let names = ["合成工资卡", galleryLongTitle, galleryLatinTitle, "零钱", "信用卡", "投资账户", "借出待收", "已归档的旧银行卡", "空账户"]
        let kinds: [AccountKind] = [.bank, .bank, .bank, .cash, .credit, .investment, .receivable, .bank, .cash]
        let balances: [Int64] = [600_000_000, 1, 123_456_789, 0, -123_456_789, 1_000_000, 1, 0, 0]
        for index in names.indices {
            var account = Account(name: names[index], kind: kinds[index], balance: balances[index], at: Dates.addMonths(-4, to: month))
            account.id = galleryID(10 + index); account.archived = index == 7
            account.creditLimit = index == 4 ? 200_000_000 : 0
            ledger.accounts.append(account)
        }
        let bank = ledger.accounts[0].id
        for index in 0..<18 {
            let name = index == 0 ? galleryLongTitle : index == 1 ? galleryLatinTitle : String(format: "合成自建分类%02d", index)
            ledger.categories.append(Category(name, subcategories: ["小项", "小项" + galleryLongTitle, galleryLatinTitle], hidden: index == 17))
        }
        // 72 ordinary rows over three real calendar cycles, plus special cases below.
        let categoryNames = ["餐饮", "交通", "购物", "居住", ledger.categories[ledger.categories.count - 18].name]
        for cycle in 0..<3 {
            let start = Dates.addMonths(-cycle, to: month)
            let lastDay = cycle == 0 ? Dates.calendar.component(.day, from: today) : 28
            for row in 0..<24 {
                let index = cycle * 24 + row
                let date = Dates.addDays(row % max(1, lastDay), to: start)
                let title = row % 3 == 0 ? galleryLongTitle : row % 3 == 1 ? galleryLatinTitle : "合成日常\(index)"
                var entry = Entry(date: date, amount: row == 0 ? 1 : row == 1 ? 123_456_789 : Int64(100 + row * 317),
                                  accountID: bank, title: title, category: categoryNames[row % categoryNames.count])
                entry.id = galleryID(100 + index); entry.recordedAt = date; entry.userEdited = true
                if entry.category == categoryNames[4] { entry.subcategory = "小项" + galleryLongTitle }
                ledger.entries.append(entry)
            }
        }
        var gap = Entry(date: today, amount: 41_200, accountID: bank, title: "没细记", category: Classification.pendingCategory)
        gap.id = galleryID(200); gap.spreadFrom = day(-6); gap.source = "对余额"
        ledger.entries.append(gap)
        var future = Entry(date: day(2), amount: 1, accountID: bank, title: "合成未来账目" + galleryLongTitle, category: "购物")
        future.id = galleryID(201); ledger.entries.append(future)
        var purchase = Entry(date: day(-2), amount: 120_000, accountID: bank, title: galleryLongTitle, category: "购物", fromReserve: true)
        purchase.id = galleryID(202); ledger.entries.append(purchase)
        var anotherPurchase = Entry(date: day(-1), amount: 360_000, accountID: bank, title: galleryLatinTitle, category: "购物", fromReserve: true)
        anotherPurchase.id = galleryID(203); ledger.entries.append(anotherPurchase)
        var deleted = Entry(date: day(-1), amount: 1, accountID: bank, title: "合成已删账目", category: "餐饮")
        deleted.id = galleryID(204); deleted.deletedAt = today; ledger.entries.append(deleted)
        var refund = Entry(date: today, amount: 1, nature: .refund, accountID: bank, title: "合成退款", category: "购物")
        refund.id = galleryID(205); refund.relatedEntryID = purchase.id; ledger.entries.append(refund)
        ledger.fixedSavings = 10_000_000; ledger.savingRule = .fixed(200_000)
        // Use the real mutator, which validates the withdrawal and combined saving target.
        try Reserve.answerPayback(.purchase(purchase.id), cycles: 3, in: &ledger, now: today)
        if ledger.reservePaybacks?.isEmpty == false { ledger.reservePaybacks?[0].id = galleryID(206) }
        for cycle in 1...2 {
            let start = Dates.addMonths(-cycle, to: month)
            ledger.savingHistory.append(CycleSaving(cycleStart: start, cycleEnd: Dates.addDays(-1, to: Dates.addMonths(1, to: start)),
                                                    income: 801_000, target: 200_000, saved: cycle == 1 ? 0 : 200_000,
                                                    unspent: 0, leftoverChoice: .keep))
        }
        // Several large adjacent-day events in both the actual and forecast cash curve.
        for index in 0..<14 {
            let due = day(index - 4)
            var plan = Plan(title: index % 2 == 0 ? galleryLongTitle + "\(index)" : galleryLatinTitle + "\(index)",
                            amount: index < 4 ? Int64(1_200_000 + index * 100_000) : Int64(1 + index * 999),
                            dueDate: due, frequency: .monthly, category: "居住")
            plan.id = galleryID(300 + index); plan.accountID = bank; plan.estimated = index % 3 == 0
            ledger.plans.append(plan)
            if index < 3 {
                var paid = Entry(date: max(month, day(index - 3)), amount: plan.amount, accountID: bank, title: plan.title, category: plan.category)
                paid.id = galleryID(320 + index); paid.planID = plan.id; paid.occurrence = due
                ledger.entries.append(paid)
            }
        }
        ledger.spendingParts = [SpendingPart(id: galleryID(350), name: "合成超支分项" + galleryLongTitle, amount: 1, categories: ["购物"]),
                                SpendingPart(id: galleryID(351), name: galleryLatinTitle, amount: 0, categories: ["交通"])]
        for (index, reserved) in [Int64(0), 1, 100_000].enumerated() {
            var goal = Goal(title: index == 1 ? galleryLatinTitle : galleryLongTitle, target: 100_000, reserved: reserved, dueDate: day(index - 1))
            goal.id = galleryID(360 + index); ledger.goals.append(goal)
        }
        for index in 0..<8 {
            var wish = WishItem(title: index % 2 == 0 ? galleryLongTitle : galleryLatinTitle, amount: index == 0 ? 1 : 123_456_789,
                                purpose: galleryLongTitle, judgment: "合成判断：" + galleryLongTitle)
            wish.id = galleryID(400 + index); wish.createdAt = day(-40 - index)
            switch index {
            case 0: wish.coolUntil = day(2)
            case 1: wish.coolUntil = day(-1)
            case 2: break // thinking, without cooling
            case 3: wish.status = .dropped; wish.droppedAt = day(-1)
            default:
                wish.status = .bought; wish.boughtEntryID = ledger.entries[index].id; wish.followUpAt = index == 4 ? day(-1) : day(5)
                if index >= 6 { wish.followUpAnswer = index == 6 ? "值得" : "有点后悔"; wish.followUpAnsweredAt = today }
            }
            ledger.wishlist.append(wish)
        }
        ledger.profile.generous = [ProfileArea(title: galleryLongTitle, match: AreaMatch(categories: ["购物"]), note: galleryLongTitle, confirmedAt: today)]
        ledger.profile.generous[0].id = galleryID(450)
        ledger.profile.restrain = [ProfileArea(title: galleryLatinTitle, match: AreaMatch(categories: ["餐饮"]), note: galleryLongTitle,
                                             softLimit: SoftLimit(perWeekCount: 1, perMonthAmount: 1), confirmedAt: today)]
        ledger.profile.restrain[0].id = galleryID(451)
        ledger.profile.principles = ["超过 2,000 等 48 小时", galleryLongTitle]; ledger.profile.updatedAt = today
        for (index, kind) in [MemoryKind.plan, .value, .life].enumerated() {
            ledger.memories.append(MemoryNote(id: galleryID(460 + index), text: index == 1 ? galleryLatinTitle : galleryLongTitle,
                                              kind: kind, source: .user, createdAt: day(-index - 1)))
        }
        var batch = ImportBatch(filename: "合成导入" + galleryLongTitle + ".csv", importedCount: 8, duplicateCount: 2, skippedCount: 1)
        batch.id = galleryID(500); batch.importedAt = today; batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: today)
        ledger.imports = [batch]
        // Real recognition reads three monthly rents from this batch. They deliberately have no plan yet.
        for cycle in 1...3 {
            let start = Dates.addMonths(-cycle, to: month)
            var rent = Entry(date: Dates.addDays(15, to: start), amount: 350_000, accountID: bank, title: "合成导入房租" + galleryLongTitle, category: "居住")
            rent.id = galleryID(510 + cycle); rent.batchID = batch.id; rent.source = "文件"; ledger.entries.append(rent)
            var salary = Entry(date: Dates.addDays(14, to: start), amount: 801_000, nature: .income, accountID: bank, title: "合成公司", category: "工资奖金")
            salary.id = galleryID(520 + cycle); salary.batchID = batch.id; salary.source = "文件"; ledger.entries.append(salary)
        }
        for index in 0..<2 {
            var row = Entry(date: day(-index), amount: index == 0 ? 1 : 123_456_789, nature: index == 0 ? .unknownIn : .unknownOut,
                            accountID: bank, title: "合成未分类" + galleryLongTitle)
            row.id = galleryID(530 + index); row.batchID = batch.id; row.source = "文件"; ledger.entries.append(row)
        }
        for index in 0..<3 {
            for offset in 1...2 {
                var row = Entry(date: day(-offset), amount: Int64(800 + index * 100), accountID: bank,
                                title: index == 0 ? galleryLongTitle : index == 1 ? "合成咖啡" : galleryLatinTitle, category: "餐饮")
                row.id = galleryID(550 + index * 2 + offset); row.purpose = row.title; row.recordedAt = row.date; row.userEdited = true
                ledger.entries.append(row)
            }
        }
        let repeats = EntryHistory.repeats(in: ledger, now: today, limit: 100)
        if let pinned = repeats.first(where: { $0.purpose == galleryLongTitle && $0.amount == 800 }) { try EntryHistory.setPinned(pinned, pinned: true, in: &ledger) }
        if let hidden = repeats.first(where: { $0.purpose == galleryLatinTitle && $0.amount == 1000 }) { try EntryHistory.setHidden(hidden, hidden: true, in: &ledger) }
        if let candidate = WeeklyLetter.candidate(ledger, now: today) {
            var letter = candidate.card(now: today); letter.id = galleryID(600); ledger.cards.append(letter)
        }
        var proposedPlan = Plan(title: "合成待确认的固定账单" + galleryLongTitle, amount: 123_456_789, dueDate: day(1), frequency: .monthly, category: "居住")
        proposedPlan.id = galleryID(650); proposedPlan.accountID = bank
        var change = ChangeSet(source: "合成", reason: proposedPlan.title, items: [.addPlan(proposedPlan)])
        change.id = galleryID(651); change.createdAt = today; ledger.pendingChanges = [change]
        var proposal = ButlerCard(kind: .recurring, title: proposedPlan.title, body: "每月 " + Money.text(proposedPlan.amount),
                                  evidence: [galleryID(100), galleryID(101)], action: .confirmChangeSet(change.id), dedupeKey: "gallery:proposal")
        proposal.id = galleryID(652); proposal.createdAt = today; proposal.priority = 0; ledger.cards.append(proposal)
        // Precompute local cards so the app's delayed refresh does not rearrange the first shots.
        let known = Set(ledger.cards.map(\.dedupeKey))
        let candidates = ButlerCards.detect(ledger, now: today).filter { !known.contains($0.dedupeKey) }.sorted { $0.dedupeKey < $1.dedupeKey }
        for (index, candidate) in candidates.enumerated() {
            var card = candidate.card(now: today); card.id = galleryID(700 + index); ledger.cards.append(card)
        }
        ledger.updatedAt = today
        try ledger.validate()
        return ledger
    }
}
#endif
