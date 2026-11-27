import Foundation
import XCTest
import YubaiCore

/// 记一笔 guesses a category on every change of 用途. On a 10,000-bill ledger with 200 different
/// purposes one guess must stay well under a frame: p95 ≤ 4 ms in Release.
/// Run: swift test -c release --filter CategoryGuessPerformanceTests
final class CategoryGuessPerformanceTests: XCTestCase {
    func testGuessOnEveryPurposeChangeStaysUnderFourMilliseconds() throws {
        let start = Dates.parse("2025-01-01 09:00:00")!
        var ledger = Ledger()
        let bank = Account(name: "招行", kind: .bank, balance: 10_000_000, at: start)
        ledger.accounts = [bank]
        ledger.categories = Category.defaults
        let words = ["午饭", "咖啡", "打车", "地铁", "超市", "水果", "电影", "健身房", "理发", "买药", "房租", "话费", "宽带", "外卖", "晚饭",
                     "早餐", "奶茶", "加油", "停车", "高铁", "机票", "酒店", "门票", "游戏", "会员", "课程", "红包", "宠物", "衣服", "鞋"]
        let purposes: [String] = (0..<200).map { (index: Int) -> String in
            let word: String = words[index % words.count]
            return word + " " + String(index / words.count) + "号店"
        }
        let names: [String] = ledger.categories.filter { !$0.income }.map(\.name)
        var entries: [Entry] = []
        entries.reserveCapacity(10_000)
        for index in 0..<10_000 {
            let date: Date = start.addingTimeInterval(Double(index) * 3_000)
            let amount: Int64 = Int64(100 + index % 9_000)
            entries.append(Entry(date: date, amount: amount, accountID: bank.id,
                                 title: purposes[index % purposes.count], category: names[index % names.count]))
        }
        ledger.entries = entries
        // Remembered parties, as a used ledger has.
        for (index, purpose) in purposes.enumerated() where index.isMultiple(of: 2) {
            ledger.classificationMemory[purpose] = names[index % names.count]
        }

        let now = start.addingTimeInterval(10_000 * 3_000)
        _ = CategoryGuesser.guess(purposes[0], nature: .expense, date: now, in: ledger)  // warm up
        var samples: [Double] = []
        for _ in 0..<5 {
            for purpose in purposes {
                let begin = DispatchTime.now().uptimeNanoseconds
                _ = CategoryGuesser.guess(purpose, nature: .expense, date: now, in: ledger)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000)
            }
        }
        samples.sort()
        let median = samples[samples.count / 2]
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        print(String(format: "CategoryGuess 10000 bills / 200 purposes / %d guesses: median %.3f ms, p95 %.3f ms", samples.count, median, p95))
        #if !DEBUG
        XCTAssertLessThanOrEqual(p95, 4, "one guess per purpose change must fit well inside a frame")
        #endif
    }
}
