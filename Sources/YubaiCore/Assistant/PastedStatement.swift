import Foundation

/// Local attachment for the import review flow. Neither the data nor the preamble
/// belongs in cloud conversation history.
public struct PastedStatement: Equatable, Sendable {
    public let data: Data
    public let filename: String
    public let preamble: String
    public let rowCount: Int
    public internal(set) var summary: PastedStatementSummary?
    public internal(set) var needsColumnMapping = false
    public internal(set) var previewError: String?

    /// Find the longest consecutive CSV/TSV table, including quoted multiline cells.
    /// Requiring a separate textual header and a data row excludes sentence drafts.
    public static func detect(_ text: String) -> PastedStatement? {
        let canonical = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var best: (range: Range<String.Index>, rows: Int, delimiter: Character)?
        for delimiter: Character in ["\t", ","] {
            let records = records(in: canonical, delimiter: delimiter)
            var start = 0
            while start < records.count {
                guard let header = records[start].cells, isHeader(header) else { start += 1; continue }
                var end = start + 1
                while end < records.count, records[end].cells?.count == header.count { end += 1 }
                let count = end - start - 1
                if count > 0, count > (best?.rows ?? 0) {
                    best = (records[start].range.lowerBound..<records[end - 1].range.upperBound, count, delimiter)
                }
                start = end
            }
        }
        guard let best else { return nil }
        return PastedStatement(data: Data(canonical[best.range].utf8),
            filename: best.delimiter == "\t" ? "pasted.tsv" : "pasted.csv",
            preamble: String(canonical[..<best.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), rowCount: best.rows)
    }

    private static func isHeader(_ row: [String]) -> Bool {
        let labels = row.map(BillImporter.clean).filter { !$0.isEmpty }
        return labels.count >= 2 && labels.allSatisfy {
            $0.rangeOfCharacter(from: .letters) != nil &&
                Dates.parse($0) == nil && (try? Money.parse($0, allowNegative: true)) == nil
        }
    }

    private struct Record {
        let range: Range<String.Index>
        let cells: [String]?
    }
    private static func records(in text: String, delimiter: Character) -> [Record] {
        var result: [Record] = []
        var start = text.startIndex, i = start
        var quoted = false, atCellStart = true
        func append(until end: String.Index) {
            let rows = try? CSV.parse(String(text[start..<end]).replacingOccurrences(of: "\u{FEFF}", with: ""), delimiter: delimiter)
            result.append(Record(range: start..<end, cells: rows?.count == 1 ? rows?.first : nil))
        }
        while i < text.endIndex {
            let c = text[i], next = text.index(after: i)
            if quoted {
                if c == "\"" {
                    if next < text.endIndex, text[next] == "\"" { i = text.index(after: next); continue }
                    quoted = false
                }
            } else if c == "\"", atCellStart { quoted = true; atCellStart = false }
            else if c == delimiter { atCellStart = true }
            else if c == "\n" { append(until: i); start = next; atCellStart = true }
            else if c != "\u{FEFF}" { atCellStart = false }
            i = next
        }
        if start < text.endIndex { append(until: text.endIndex) }
        return result
    }

    /// Uses a disposable account only when the ledger has none. Account selection
    /// and validation still happen when the UI opens the normal import preview.
    func locallyPreviewed(ledger: Ledger) -> PastedStatement {
        var result = self
        var snapshot = ledger
        let accountID: UUID
        if let account = ledger.accounts.first(where: { !$0.archived }) { accountID = account.id }
        else {
            let account = Account(name: "待选择导入账户")
            snapshot.accounts.append(account); accountID = account.id
        }
        do {
            let preview = try BillImporter.preview(data: data, filename: filename, accountID: accountID, ledger: snapshot)
            result.summary = PastedStatementSummary(preview)
        } catch ImportColumnError.missing { result.needsColumnMapping = true }
        catch { result.previewError = error.localizedDescription }
        return result
    }

    var replyText: String {
        if let summary {
            let source = summary.source == "BeeCount" ? "蜜蜂记账导出" : summary.source == "文件" ? "账单表格" : "\(summary.source)账单"
            return "这是一份\(source)，\(summary.entryCount) 笔。请先核对，再导入。"
        }
        if needsColumnMapping { return "检测到一份账单表格，\(rowCount) 行数据。需要先识别日期和金额等列，再核对导入。" }
        return "检测到一份账单表格。\(previewError ?? "请在导入页核对。")"
    }
}

public struct PastedStatementSummary: Equatable, Sendable {
    public let source: String
    /// All preview rows, including existing duplicates and rows needing review.
    public let entryCount: Int
    public let startDate: Date?
    public let endDate: Date?
    public let expenseCount: Int
    public let incomeCount: Int
    /// Integer cents; transfers are excluded from both income and expenses.
    public let expenseTotal: Int64
    public let incomeTotal: Int64
    public let issueCount: Int

    init(_ preview: ImportPreview) {
        let entries = preview.rows.compactMap(\.entry)
        let expenses = entries.filter { $0.nature == .expense }
        let income = entries.filter { $0.nature == .income }
        source = preview.source; entryCount = preview.rows.count; issueCount = preview.issueCount
        startDate = entries.map(\.date).min(); endDate = entries.map(\.date).max()
        expenseCount = expenses.count; incomeCount = income.count
        expenseTotal = expenses.reduce(0) { $0 + $1.amount }; incomeTotal = income.reduce(0) { $0 + $1.amount }
    }
}
