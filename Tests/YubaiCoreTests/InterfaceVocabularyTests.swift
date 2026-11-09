import Foundation
import XCTest
@testable import YubaiCore

final class InterfaceVocabularyTests: XCTestCase {
    func testAppStringLiteralsUseCurrentVocabulary() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Sources/YubaiApp")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let banned = ["始终留着", "保守可动用", "还能自在支配", "软线", "柔性提醒", "提案", "待明确", "待整理", "回访", "管家的话", "余白助手", "使用指南"]
        for file in files {
            var scanner = SwiftStringScanner(try String(contentsOf: file, encoding: .utf8))
            for literal in scanner.literals() {
                for word in banned where literal.contains(word) {
                    XCTFail("\(file.lastPathComponent) 的字符串仍含「\(word)」：\(literal)")
                }
            }
        }
    }

    func testScannerSkipsCommentsAndReadsRawMultilineAndInterpolatedStrings() {
        let source = ##"""
        // "保守可动用"
        /* "软线" /* "回访" */ "使用指南" */
        let a = "还能花 // 事实" // "待明确"
        let b = #"每周来信 /* 原文 */"#
        let c = """
        我的消费观
        """
        let d = "明细：\(title ?? "心愿单")"
        let e = "余白\"助手"
        let f = #"明细：\#(value /* "管家的话" */)"#
        """##
        var scanner = SwiftStringScanner(source)
        XCTAssertEqual(scanner.literals(), ["还能花 // 事实", "每周来信 /* 原文 */", "\n我的消费观\n", "心愿单", "明细：", "余白\"助手", "明细："])
    }

    func testPresentationKeepsStoredCategoryAndMemorySourceValues() throws {
        XCTAssertEqual(Classification.pendingCategory, "待整理")
        XCTAssertEqual(Classification.displayCategory(Classification.pendingCategory), "没分类")
        XCTAssertEqual(Classification.displayCategory("餐饮"), "餐饮")
        XCTAssertEqual(MemorySource.followUp.rawValue, "followUp")
        XCTAssertEqual(MemorySource.feedback.rawValue, "feedback")
        XCTAssertEqual(MemorySource.reflection.rawValue, "reflection")
        XCTAssertEqual(MemorySource.feedback.label, "你点过的提醒")
        XCTAssertEqual(MemorySource.reflection.label, "每周来信")
    }
}

/// A lexical scan, so comment markers inside strings remain visible and nested
/// block comments, raw strings and strings inside interpolations are handled.
private struct SwiftStringScanner {
    private let characters: [Character]
    private var index = 0
    private var result: [String] = []
    init(_ source: String) { characters = Array(source) }
    mutating func literals() -> [String] { code(); return result }
    private func matches(_ text: String) -> Bool {
        let token = Array(text)
        return index + token.count <= characters.count && Array(characters[index..<(index + token.count)]) == token
    }
    private mutating func code(interpolation: Bool = false) {
        var parentheses = 0
        while index < characters.count {
            if matches("//") {
                while index < characters.count && characters[index] != "\n" { index += 1 }
            } else if matches("/*") {
                index += 2
                var depth = 1
                while index < characters.count && depth > 0 {
                    if matches("/*") { depth += 1; index += 2 }
                    else if matches("*/") { depth -= 1; index += 2 }
                    else { index += 1 }
                }
            } else if characters[index] == "\"" || characters[index] == "#" {
                let start = index
                while index < characters.count && characters[index] == "#" { index += 1 }
                let hashes = index - start
                if index < characters.count && characters[index] == "\"" { string(hashes: hashes) }
                else { index = start + 1 }
            } else if interpolation && characters[index] == ")" && parentheses == 0 {
                index += 1; return
            } else {
                if characters[index] == "(" { parentheses += 1 }
                if characters[index] == ")" { parentheses -= 1 }
                index += 1
            }
        }
    }
    private mutating func string(hashes: Int) {
        let quotes = matches("\"\"\"") ? "\"\"\"" : "\""
        let suffix = String(repeating: "#", count: hashes)
        let end = quotes + suffix
        let escape = "\\" + suffix
        index += quotes.count
        var text = ""
        while index < characters.count {
            if matches(end) { index += end.count; break }
            if matches(escape + "(") {
                index += escape.count + 1
                code(interpolation: true)
            } else if matches(escape) {
                index += escape.count
                if index < characters.count { text.append(characters[index]); index += 1 }
            } else { text.append(characters[index]); index += 1 }
        }
        result.append(text)
    }
}
