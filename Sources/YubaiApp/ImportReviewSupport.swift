import Foundation
import SwiftUI
import YubaiCore

struct WelcomeStatement: Sendable {
    let accountID: UUID
    let data: Data
    var preview: ImportPreview
}

/// Shared with the import queue, including its three local reading stages.
struct ImportReadingProgress: View {
    let value: Double
    var body: some View {
        ProgressView(value: value, total: 3).tint(YubaiColor.brand)
            .frame(width: YubaiSize.buttonHeight).accessibilityLabel("读取进度")
    }
}

/// Shared wording for file review and pasted-table cards.
enum ImportStatementText {
    static func source(_ source: String) -> String {
        source == "BeeCount" ? "蜜蜂记账" : source == "文件" ? "账单表格" : source
    }
    static func range(_ dates: [Date]) -> String { range(start: dates.min(), end: dates.max()) }
    static func range(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "日期待核对" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.calendar = Dates.calendar
        formatter.timeZone = Dates.calendar.timeZone
        let sameYear = Dates.calendar.component(.year, from: start) == Dates.calendar.component(.year, from: end)
        formatter.dateFormat = sameYear ? "M月d日" : "yyyy年M月d日"
        let first = formatter.string(from: start), last = formatter.string(from: end)
        if first == last { return first }
        if sameYear && Dates.calendar.component(.month, from: start) == Dates.calendar.component(.month, from: end) { formatter.dateFormat = "d日" }
        return first + "–" + formatter.string(from: end)
    }
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = Dates.calendar.timeZone; formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    static func balanceDate(_ date: Date) -> String {
        range([date]) + " " + time(date)
    }
}
