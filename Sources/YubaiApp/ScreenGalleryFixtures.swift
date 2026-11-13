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
        seedBatch3Questions(for: ledgerID)
    }
    /// Exercise the real get_profile -> propose_entry -> user confirmation flow offline.
    /// Accounts and amounts come from the real tool response, never invented aliases.
    static func galleryReply(_ request: ChatRequest, script: String) throws -> ChatMessage? {
        if let reply = try batch3Reply(request, script: script) { return reply }
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
        // Several large adjacent-day bills exercise actual payments and upcoming rows.
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

#if DEBUG && targetEnvironment(simulator)
extension UITestSupport {
    static let v46Scripts: Set<String> = Set(["v46-sort", "v46-home", "v46-quiet", "v46-bill", "v46-gap", "v46-over", "v46-payday", "v46-leftover", "v46-empty", "v46-hard", "v46-big", "v46-busy", "v46-deck", "v46-saved", "v46-spend"]).union(batch3Scripts)
    static func v46Ledger(_ script: String, now: Date) throws -> Ledger {
        if batch3Scripts.contains(script) { return try batch3Ledger(script, now: now) }
        let today = Dates.day(now)
        if script == "v46-empty" {
            var empty = Ledger(); empty.id = galleryID(4600)
            empty.preferences.appearance = galleryAppearance ?? "light"
            empty.preferences.profileColdStartDone = true
            return empty
        }
        if script == "v46-sort" {
            var value = organizationLedger(now: now)
            value.preferences.cloudAIEnabled = false
            value.preferences.profileColdStartDone = true
            value.cards = []
            value.entries.removeAll { $0.batchID == nil || $0.nature == .unknownIn }
            for index in value.accounts.indices { value.accounts[index].anchorDate = now }
            try value.validate(); return value
        }
        let base: String
        switch script {
        case "v46-bill", "v46-deck": base = "v45-bill"
        case "v46-gap": base = "v45-gap"
        case "v46-over": base = "v45-over"
        case "v46-payday": base = "v45-payday"
        case "v46-leftover": base = "v45-newcycle"
        default: base = "v45-home"
        }
        var ledger = try v45Ledger(base, now: now)
        ledger.id = galleryID(4600); ledger.preferences.profileColdStartDone = true
        ledger.preferences.appearance = galleryAppearance ?? "light"
        ledger.accounts[0].name = "招行储蓄卡"
        ledger.accounts[0].id = galleryID(4610)
        // Remap references after assigning a stable bank ID.
        let bank = ledger.accounts[0].id
        for index in ledger.entries.indices { ledger.entries[index].accountID = bank }
        var planIDs: [UUID: UUID] = [:]
        for index in ledger.plans.indices {
            planIDs[ledger.plans[index].id] = galleryID(4620 + index)
            ledger.plans[index].accountID = bank; ledger.plans[index].id = galleryID(4620 + index)
        }
        for index in ledger.entries.indices { if let id = ledger.entries[index].planID { ledger.entries[index].planID = planIDs[id] } }
        let archived = Account(name: galleryLongTitle, kind: .bank, balance: 123_456_789, at: today)
        var archivedAccount = archived; archivedAccount.id = galleryID(4619); archivedAccount.archived = true
        ledger.accounts.append(archivedAccount)
        ledger.categories.append(YubaiCore.Category(galleryLongTitle, "shippingbox"))
        if ["v46-home", "v46-hard"].contains(script) {
            var renewal = Plan(title: script == "v46-hard" ? "中国移动手机话费及家庭宽带融合套餐自动续费" : "视频会员",
                               amount: script == "v46-hard" ? 128_800 : 2500, dueDate: Dates.addDays(1, to: today), frequency: .monthly, category: "订阅")
            renewal.id = galleryID(4630); renewal.accountID = bank; ledger.plans.append(renewal)
            ledger.memories.append(MemoryNote(text: renewal.title + (script == "v46-hard" ? "上个月没用过" : "上个月没打开过"), kind: .life, source: .user, createdAt: now))
            ledger.accounts[0].anchorBalance += renewal.amount
            for index in 0..<2 {
                var wish = WishItem(title: index == 0 ? "降噪耳机" : galleryLongTitle, amount: index == 0 ? 189900 : 123456789)
                wish.id = galleryID(4640 + index); wish.createdAt = now.addingTimeInterval(-48 * 3600); wish.coolUntil = now.addingTimeInterval(-1)
                ledger.wishlist.append(wish)
            }
        }
        if script == "v46-home" {
            for (index, item) in [("地铁", Int64(800), "交通"), ("午饭", 2800, "餐饮"), ("咖啡", 3200, "餐饮")].enumerated() {
                for offset in 1...(index == 0 ? 3 : 2) {
                    let date = Dates.addDays(-offset, to: today).addingTimeInterval(Double(12 - index) * 3600)
                    var entry = Entry(date: date, amount: item.1, accountID: bank, title: item.0, category: item.2)
                    entry.recordedAt = date; entry.purpose = item.0; entry.userEdited = true
                    ledger.entries.append(entry)
                }
            }
        }
        if script == "v46-quiet" || script == "v46-big" { ledger.wishlist = [] }
        if script == "v46-bill", let index = ledger.plans.firstIndex(where: { $0.title == "话费和宽带" }) {
            let previous = Dates.addMonths(-1, to: today)
            ledger.plans[index].dueDate = previous
            var paid = Entry(date: previous, amount: ledger.plans[index].amount, accountID: bank, title: "话费和宽带", category: ledger.plans[index].category)
            paid.id = galleryID(4680); paid.planID = ledger.plans[index].id; paid.occurrence = previous
            ledger.entries.append(paid)
        }
        if ["v46-big", "v46-over", "v46-busy"].contains(script) { ledger.plans.removeAll { !$0.inflow } }
        if script == "v46-over" {
            ledger.entries.removeAll { $0.date >= Dates.addDays(-2, to: today) && $0.nature == .expense }
            // A recent balance check suppresses a gap reminder in this fixture.
            for index in ledger.accounts.indices {
                let balance = Finance.balance(ledger.accounts[index], in: ledger, at: now)
                ledger.accounts[index].anchorDate = now; ledger.accounts[index].anchorBalance = balance
            }
        }
        if script == "v46-hard" { ledger.entries.removeAll { $0.date >= Dates.addDays(-1, to: today) } }
        if script == "v46-hard", let index = ledger.plans.firstIndex(where: { $0.title == "话费和宽带" }) {
            ledger.plans[index].title = galleryLongTitle; ledger.plans[index].amount = 1_216_000
        }
        if script == "v46-gap" {
            let latest = Dates.addDays(-3, to: today).addingTimeInterval(12 * 3600)
            ledger.entries.append(Entry(date: latest, amount: 1, accountID: bank, title: "上次记账", category: "餐饮"))
            ledger.accounts[0].anchorBalance += 1
            ledger.accounts[1].name = "微信零钱"
            ledger.accounts[1].anchorBalance = 186000
            ledger.accounts.append(Account(name: "支付宝", kind: .cash, balance: 110000, at: Dates.addDays(-12, to: today)))
        }
        if script == "v46-busy" || script == "v46-deck" {
            var batch = ImportBatch(filename: "11月账单.csv", importedCount: script == "v46-busy" ? 214 : 4, duplicateCount: 0, skippedCount: 0)
            batch.id = galleryID(4650); batch.importedAt = today; batch.needsOrganization = true
            ledger.imports = [batch]
            for index in 0..<batch.importedCount {
                let amount: Int64 = script == "v46-busy" ? 1 : [2500, 2800, 3200, 61800][index]
                let date = script == "v46-busy" ? Dates.addMonths(-1, to: today) : Dates.addDays(-index % 3, to: today)
                var row = Entry(date: date, amount: amount, accountID: bank,
                                title: index == 0 ? galleryLongTitle : "商户 \(index)", category: Classification.pendingCategory)
                row.id = galleryID(4700 + index); row.batchID = batch.id; row.source = "文件"
                ledger.entries.append(row); ledger.accounts[0].anchorBalance += amount
            }
            if script == "v46-deck" {
                var second = Plan(title: galleryLongTitle, amount: 123456789, dueDate: today, category: "居住")
                second.id = galleryID(4660); second.accountID = bank; ledger.plans.append(second)
            }
        }
        if script == "v46-saved" {
            var wish = WishItem(title: "降噪耳机", amount: 189900)
            wish.id = galleryID(4649); wish.createdAt = now.addingTimeInterval(-49 * 3600); wish.status = .dropped; wish.droppedAt = now.addingTimeInterval(-3600)
            ledger.wishlist = [wish]
            var stopped = Plan(title: "视频会员", amount: 2500, dueDate: Dates.addMonths(-1, to: Dates.addDays(-2, to: today)), frequency: .monthly, category: "订阅")
            stopped.id = galleryID(4670); stopped.accountID = bank
            ledger.stoppedSubscriptions = [StoppedSubscription(plan: stopped, stoppedAt: Dates.addMonths(-1, to: Dates.addDays(-3, to: today)))]
            ledger.butlerSavings = [ButlerSaving(id: "recovered:46", item: "视频会员", amount: 2500, cadence: .once,
                                                date: Dates.addMonths(-2, to: today), undoable: false)]
            ButlerSavings.synchronize(&ledger, now: now)
        }
        if script == "v46-spend", let salaryIndex = ledger.plans.firstIndex(where: { $0.inflow }) {
            let salaryDate = Dates.addMonths(-1, to: ledger.plans[salaryIndex].dueDate)
            ledger.plans[salaryIndex].dueDate = salaryDate
            ledger.accounts[0].anchorDate = salaryDate.addingTimeInterval(-1); ledger.accounts[0].anchorBalance = 0
            ledger.fixedSavings = 0
            var salary = Entry(date: salaryDate.addingTimeInterval(9 * 3600), amount: 801000, nature: .income, accountID: bank, title: "工资", category: "工资奖金")
            salary.id = galleryID(4681); salary.planID = ledger.plans[salaryIndex].id; salary.occurrence = salaryDate
            ledger.entries = [salary]
            for index in 0..<32 {
                let day = Dates.addDays(-1 - index % 8, to: today)
                ledger.entries.append(Entry(date: day, amount: 2500, accountID: bank, title: index == 0 ? galleryLongTitle : "日常", category: "餐饮"))
            }
            ledger.entries.append(Entry(date: today, amount: 2800, accountID: bank, title: "午饭", category: "餐饮"))
            ledger.entries.append(Entry(date: today, amount: 800, accountID: bank, title: "地铁", category: "交通"))
            if let rent = ledger.plans.firstIndex(where: { $0.title == "房租" }) { ledger.plans[rent].amount = 300000 }
            for (index, item) in [("水费", Int64(12000)), ("网费", 15000)].enumerated() {
                var bill = Plan(title: item.0, amount: item.1, dueDate: Dates.addDays(3 + index, to: today), category: "居住")
                bill.id = galleryID(4682 + index); bill.accountID = bank; ledger.plans.append(bill)
            }
        }
        if script == "v46-over", let pace = Finance.pace(ledger, now: now), let index = ledger.entries.firstIndex(where: { $0.nature == .expense && $0.date >= pace.start }) {
            ledger.entries[index].amount += Int64(pace.daysTotal) * 8000 + 32000 - pace.spent
        }
        // Pin the hero while retaining real formulas and stress rows. No mocked
        // view values: reconcile, overspend and undo still run their real mutators.
        let target: Int64
        switch script {
        case "v46-over": target = -32000
        case "v46-payday", "v46-leftover": target = 21200
        case "v46-gap": target = 170400
        case "v46-bill": target = 118900
        case "v46-hard": target = 12856400
        default: target = 156400
        }
        ledger.accounts[0].anchorBalance += target - Finance.funds(ledger, now: now).available
        ledger.updatedAt = now
        try ledger.validate(); return ledger
    }
}
#endif
