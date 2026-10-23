import XCTest
@testable import YubaiCore

final class FinanceScaleTests: XCTestCase {
    func testLargeLedgerMatchesReferenceIncludingOldRecurrencesAndPostingDates() throws {
        let now = Dates.parse("2026-10-01 12:00:00")!; var ledger = Ledger()
        ledger.profile.floorAmount = 45678
        ledger.accounts = [Account(name: "Bank", balance: 9_000_000, at: Dates.addDays(-90, to: now)), Account(name: "Cash", kind: .cash, balance: 300_000, at: Dates.addDays(-30, to: now)), Account(name: "Credit", kind: .credit, balance: -700_000, at: Dates.addDays(-60, to: now)), Account(name: "Credit surplus", kind: .credit, balance: 500_000, at: now), Account(name: "Investment", kind: .investment, balance: 800_000, at: Dates.addDays(-45, to: now)), Account(name: "Receivable", kind: .receivable, balance: 200_000, at: Dates.addDays(-20, to: now))]
        ledger.accounts[1].archived = true; ledger.accounts[5].reconciled = false
        ledger.goals = [Goal(title: "Goal", target: 100_000, reserved: 12345)]
        var ended = Plan(title: "Ended", amount: 700, dueDate: Dates.parse("2024-01-31 15:00:00")!, frequency: .monthly); ended.endDate = Dates.parse("2025-02-28 15:00:00")!
        var inactive = Plan(title: "Inactive", amount: 900, dueDate: Dates.parse("1999-01-01")!, frequency: .weekly); inactive.active = false
        ledger.plans = [Plan(title: "Weekly", amount: 3000, dueDate: Dates.parse("1990-01-01 08:30:00")!, frequency: .weekly), Plan(title: "Capped weekly", amount: 5000, dueDate: Dates.parse("1980-01-01")!, frequency: .weekly), Plan(title: "Monthly income", amount: 10000, dueDate: Dates.parse("2015-01-31 18:00:00")!, frequency: .monthly, inflow: true, nature: .income), Plan(title: "Repayment", amount: 80000, dueDate: Dates.addDays(10, to: now), nature: .repayment), ended, inactive]
        let rent = Rent(monthlyTotal: 45000, personalShare: 17000, startDate: Dates.parse("2005-01-15 16:00:00")!, nextDueDate: Dates.parse("2005-01-31 09:00:00")!, monthsPerPayment: 1, receiveDay: 5)
        var endedRent = Rent(monthlyTotal: 60000, personalShare: 30000, startDate: Dates.parse("2024-01-01")!, nextDueDate: Dates.parse("2024-01-31 09:00:00")!, monthsPerPayment: 3, receiveDay: 28); endedRent.endDate = Dates.parse("2025-01-31")!
        ledger.rents = [rent, endedRent]
        let natures = Nature.allCases
        for index in 0..<5000 {
            let nature = natures[index % natures.count]
            var entry = Entry(date: Dates.addDays(index % 400 - 380, to: now), amount: Int64(index % 999 + 1), nature: nature, accountID: ledger.accounts[index % ledger.accounts.count].id, title: "Entry \(index)", category: index % 2 == 0 ? "Food" : "Other")
            if nature.paired {
                entry.accountID = ledger.accounts[0].id
                switch nature {
                case .repayment, .borrow, .loanReturn: entry.otherAccountID = ledger.accounts[2].id
                case .lend, .loanRecovery: entry.otherAccountID = ledger.accounts[5].id
                case .investBuy, .investSell: entry.otherAccountID = ledger.accounts[4].id
                default: entry.otherAccountID = index % 3 == 0 ? nil : ledger.accounts[1].id
                }
                entry.otherDate = Dates.addDays(index % 5 - 2, to: entry.date)
            }
            if index % 113 == 0 {
                let plan = ledger.plans[(index / 113) % ledger.plans.count]
                entry.planID = plan.id; entry.occurrence = plan.frequency.advance(plan.dueDate, by: index % 1800).addingTimeInterval(600)
                entry.nature = plan.nature; entry.accountID = ledger.accounts[0].id; entry.otherAccountID = plan.nature == .repayment ? ledger.accounts[2].id : nil
            } else if index % 127 == 0 {
                entry.rentID = rent.id; entry.rentPeriod = Dates.addMonths(index % 250, to: rent.nextDueDate)
                entry.nature = index % 2 == 0 ? .expense : .contribution; entry.otherAccountID = nil
            }
            if index % 19 == 0 {
                let anchor = ledger.accounts.first { $0.id == entry.accountID }!.anchorDate
                entry.date = Dates.day(anchor); entry.recordedAt = anchor.addingTimeInterval(index % 2 == 0 ? 60 : -60)
            }
            if index % 23 == 0 { entry.deletedAt = now }
            ledger.entries.append(entry)
        }
        let plan = ledger.plans[0]; let occurrence = plan.frequency.advance(plan.dueDate, by: 1900)
        for index in 0..<4 {
            var entry = Entry(date: Dates.addDays(1, to: now), amount: index == 3 ? plan.amount * 2 : 500, accountID: ledger.accounts[0].id, title: "Partial plan payment")
            entry.planID = plan.id; entry.occurrence = occurrence.addingTimeInterval(Double(index) * 60)
            if index == 2 { entry.deletedAt = now }
            ledger.entries.append(entry)
        }
        let month = Dates.parse("2026-09-01")!
        for index in 0..<3 {
            var entry = Entry(date: now, amount: 1000, nature: .contribution, accountID: ledger.accounts[0].id, title: "Rent contribution")
            entry.rentID = rent.id; entry.rentPeriod = Dates.addDays(index * 10, to: month)
            ledger.entries.append(entry)
        }
        try ledger.validate()
        let expected = ReferenceFinance.funds(ledger, now: now); let actual = Finance.funds(ledger, now: now)
        XCTAssertEqual(Finance.occurrences(in: ledger, now: now), expected.occurrences)
        XCTAssertEqual(actual.occurrences, expected.occurrences)
        XCTAssertEqual([actual.cash, actual.debt, actual.investments, actual.receivables, actual.netWorth, actual.committed, actual.goals, actual.emergency, actual.living, actual.uncertainInflow, actual.available, actual.expectedIncome], [expected.cash, expected.debt, expected.investments, expected.receivables, expected.netWorth, expected.committed, expected.goals, expected.emergency, expected.living, expected.uncertainInflow, expected.available, expected.expectedIncome])
        XCTAssertEqual(actual.warnings, expected.warnings)
        XCTAssertEqual(actual.points.map(\.date), expected.points.map(\.date))
        XCTAssertEqual(actual.points.map(\.conservative), expected.points.map(\.conservative))
        XCTAssertEqual(actual.points.map(\.expected), expected.points.map(\.expected))
        XCTAssertEqual(Finance.occurrences(in: ledger, now: now, days: 7), ReferenceFinance.occurrences(in: ledger, now: now, days: 7))
    }
}

// Deliberately retain the scan-based calculation as an independent correctness oracle.
private enum ReferenceFinance {
    static func balance(_ account: Account, in ledger: Ledger, at: Date = Date()) -> Int64 {
        account.anchorBalance + ledger.entries.lazy.filter { $0.deletedAt == nil && account.includes($0, posting: $0.postingDate(for: account.id)) && $0.postingDate(for: account.id) <= at }.reduce(Int64(0)) { $0 + $1.delta(for: account.id) }
    }
    static func occurrences(in ledger: Ledger, now: Date = Date(), days: Int? = nil) -> [Occurrence] {
        let start = Dates.day(now); let end = Dates.addDays(days ?? 90, to: start)
        let entries = ledger.activeEntries
        var result: [Occurrence] = []
        for p in ledger.plans where p.active {
            // Always derive from the original day (Jan 31 → Feb 28 → Mar 31), never chained dates.
            for index in 0..<2400 {
                let date = p.frequency.advance(p.dueDate, by: index)
                if date > end || (p.endDate != nil && date > p.endDate!) { break }
                let paid = entries.filter { $0.planID == p.id && $0.occurrence.map(Dates.day) == Dates.day(date) }.reduce(Int64(0)) { $0 + $1.amount }
                if paid < p.amount {
                    result.append(Occurrence(id: "\(p.id)-\(date.timeIntervalSince1970)", title: p.title, date: date, amount: p.amount - paid, inflow: p.inflow, planID: p.id, overdue: Dates.day(date) < start))
                }
                if p.frequency == .once { break }
            }
        }
        for r in ledger.rents where r.active {
            for index in 0..<240 {
                let due = Dates.addMonths(index * r.monthsPerPayment, to: r.nextDueDate)
                if due > end || (r.endDate != nil && Dates.day(due) > Dates.day(r.endDate!)) { break }
                let paid = entries.filter { $0.rentID == r.id && $0.nature == .expense && $0.rentPeriod.map(Dates.day) == Dates.day(due) }.reduce(Int64(0)) { $0 + $1.amount }
                let dueAmount = r.monthlyTotal * Int64(r.monthsPerPayment)
                if paid < dueAmount { result.append(Occurrence(id: "rent-\(r.id)-\(due.timeIntervalSince1970)", title: r.title, date: due, amount: dueAmount - paid, inflow: false, rentID: r.id, overdue: Dates.day(due) < start)) }
            }
            let firstMonth = Dates.calendar.date(from: Dates.calendar.dateComponents([.year, .month], from: r.startDate))!
            for index in 0..<1200 {
                let month = Dates.addMonths(index, to: firstMonth)
                let receiveDate = max(Dates.addDays(r.receiveDay - 1, to: month), r.startDate)
                if receiveDate > end || (r.endDate != nil && Dates.day(receiveDate) > Dates.day(r.endDate!)) { break }
                let paid = entries.filter { $0.rentID == r.id && $0.nature == .contribution && $0.rentPeriod.map { Dates.calendar.isDate($0, equalTo: month, toGranularity: .month) } == true }.reduce(Int64(0)) { $0 + $1.amount }
                let amount = r.monthlyTotal - r.personalShare - paid
                if amount > 0 { result.append(Occurrence(id: "share-\(r.id)-\(month.timeIntervalSince1970)", title: r.title + " · 应收分摊", date: receiveDate, amount: amount, inflow: true, rentID: r.id, overdue: Dates.day(receiveDate) < start, rentMonth: month)) }
            }
        }
        return result.sorted { $0.date < $1.date }
    }
    static func funds(_ ledger: Ledger, now: Date = Date()) -> Funds {
        let accounts = ledger.accounts // Archived accounts still own money and obligations.
        let cash = accounts.filter { $0.kind == .cash || $0.kind == .bank }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let creditNet = accounts.filter { $0.kind == .credit }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let debt = accounts.filter { $0.kind == .credit }.reduce(Int64(0)) { $0 + max(0, -balance($1, in: ledger, at: now)) }
        let investment = accounts.filter { $0.kind == .investment }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let receivables = accounts.filter { $0.kind == .receivable }.reduce(Int64(0)) { $0 + balance($1, in: ledger, at: now) }
        let occurrences = occurrences(in: ledger, now: now)
        // Credit principal is reserved once as debt. A credit-repayment plan only changes its payment date.
        let commitments = occurrences.filter { !$0.inflow && !($0.planID.flatMap { id in ledger.plans.first { $0.id == id } }.map { $0.nature == .repayment } ?? false) }
        let today = Dates.day(now); let end = Dates.addDays(91, to: today)
        let payday = ledger.plans.filter { $0.active && $0.inflow && $0.nature == .income && $0.frequency != .once }.flatMap { plan in
            (0..<2400).map { plan.frequency.advance(plan.dueDate, by: $0) }.filter { Dates.day($0) > today && $0 < end && (plan.endDate == nil || $0 <= plan.endDate!) }
        }.min().map(Dates.day)
        let horizonDays = payday.map { Dates.calendar.dateComponents([.day], from: today, to: $0).day! } ?? 90
        let committed = commitments.filter { payday == nil || Dates.day($0.date) <= payday! }.reduce(Int64(0)) { $0 + $1.amount }
        let goals = ledger.goals.reduce(Int64(0)) { $0 + $1.reserved }
        let daily = Finance.estimatedDailyLiving(ledger, now: now)
        let living = daily * Int64(horizonDays)
        // An unresolved inflow after the most recent reconciliation is withheld until its nature is known.
        let uncertain = ledger.activeEntries.filter { e in
            e.nature == .unknownIn && e.date <= now && accounts.contains { $0.id == e.accountID && $0.includes(e, posting: e.date) && ($0.kind == .cash || $0.kind == .bank) }
        }.reduce(Int64(0)) { $0 + $1.amount }
        let available = cash - debt - committed - goals - (ledger.profile.floorAmount ?? 0) - living - uncertain
        let expectedIncome = occurrences.filter(\.inflow).reduce(Int64(0)) { $0 + $1.amount }
        var warnings: [String] = []
        if accounts.isEmpty { warnings.append("还没有账户") }
        if accounts.contains(where: { !$0.reconciled }) { warnings.append("有账户还没对过账。") }
        if accounts.contains(where: { now.timeIntervalSince($0.anchorDate) > 14 * 86400 }) { warnings.append("部分账户上次对账已超过 14 天，请补齐账单。") }
        if ledger.activeEntries.contains(where: { $0.nature.uncertain }) { warnings.append("有账目没写用途，请补上。") }
        if occurrences.contains(where: \.overdue) { warnings.append("有固定收付已到期，请确认是否已付。") }
        if ledger.activeEntries.contains(where: { $0.nature.paired && $0.otherAccountID == nil }) { warnings.append("有转账没选另一账户，请补上。") }
        let baseline = cash - debt - goals - (ledger.profile.floorAmount ?? 0) - uncertain
        var points: [ForecastPoint] = []
        for offset in 0...90 {
            let date = Dates.addDays(offset, to: Dates.day(now))
            let out = commitments.filter { Dates.day($0.date) <= date }.reduce(Int64(0)) { $0 + $1.amount }
            let incoming = occurrences.filter { $0.inflow && Dates.day($0.date) <= date }.reduce(Int64(0)) { $0 + $1.amount }
            let conservative = baseline - out - Int64(offset) * daily
            points.append(ForecastPoint(date: date, conservative: conservative, expected: conservative + incoming))
        }
        return Funds(cash: cash, debt: debt, investments: investment, receivables: receivables, netWorth: cash + creditNet + investment + receivables,
                     livingEstimated: true, committed: committed, goals: goals, emergency: (ledger.profile.floorAmount ?? 0), living: living,
                     uncertainInflow: uncertain, available: available, expectedIncome: expectedIncome,
                     occurrences: occurrences, points: points, warnings: warnings)
    }
}
