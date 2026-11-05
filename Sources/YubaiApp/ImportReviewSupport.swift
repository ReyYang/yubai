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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Double
    private var fraction: Double { value.isFinite ? min(1, max(0, value / 3)) : 0 }
    var body: some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(fraction, format: .percent.precision(.fractionLength(0))).yubaiFont(YubaiFont.meta)
                .foregroundStyle(YubaiColor.labelSecondary).monospacedDigit().lineLimit(1)
            GeometryReader { geometry in
                Capsule().fill(YubaiColor.raised)
                    .overlay(alignment: .leading) {
                        Capsule().fill(YubaiColor.brand).frame(width: geometry.size.width * CGFloat(fraction))
                    }
            }.frame(width: 64, height: 6).animation(YubaiMotion.progress(reduceMotion: reduceMotion), value: fraction)
        }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .ignore).accessibilityLabel("读取进度")
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
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
