import SwiftUI
import YubaiCore

enum FixedFlowPresentation {
    static func monthDay(_ date: Date) -> String { Dates.monthDay(date) }
    static func state(_ state: FixedFlowState, inflow: Bool) -> String {
        switch state { case .paid: inflow ? "已收到" : "已付"; case .due: "已到期"; case .upcoming: "还没到" }
    }
    static func detail(_ row: FixedFlowOccurrence, in ledger: Ledger) -> String {
        var parts = [row.statusText()]
        let entry = ledger.activeEntries.filter { $0.planID == row.planID && row.planID != nil && $0.occurrence.map(Dates.day) == Dates.day(row.date) }
            .max { ($0.recordedAt ?? $0.date) < ($1.recordedAt ?? $1.date) }
        if row.state == .paid {
            if entry?.source == "自动扣款" { parts.append("自动") }
            else if let entry { parts.append(monthDay(entry.recordedAt ?? entry.date) + "记") }
        } else if row.autoPay { parts.append("自动") }
        let account = ledger.plans.first { $0.id == row.planID }?.accountID ?? ledger.rents.first { $0.id == row.rentID }?.accountID
        if let account { parts.append(ledger.accountName(account)) }
        if let installment = row.installment { parts.append("\(installment.index)/\(installment.total) 期") }
        if row.estimated { parts.append("大约") }
        return parts.joined(separator: " · ")
    }
}

/// The calendar menu and detail page share the stop confirmation.
