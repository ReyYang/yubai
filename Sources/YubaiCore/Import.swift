import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CoreFoundation
#if canImport(CryptoKit)
import CryptoKit
#elseif os(Linux)
import Crypto
#endif
import CArchive

public struct Classification: Sendable {
    public var category: String; public var nature: Nature; public var reason: String
}
/// Only explicit bill type fields supply deterministic nature hints. No merchant rules.
public enum Classifier {
    public static func classify(inflow: Bool, hint: String = "") -> Classification {
        let text = hint.lowercased()
        let nature: Nature
        if inflow && ["退款", "退货", "refund"].contains(where: text.contains) { nature = .refund }
        else if ["还信用卡", "信用卡还款", "花呗还款", "白条还款"].contains(where: text.contains) { nature = inflow ? .adjustmentIn : .repayment }
        else if ["理财申购", "理财赎回", "余额宝", "零钱通"].contains(where: text.contains) { nature = inflow ? .investSell : .investBuy }
        else if ["转账", "提现", "充值", "红包", "收款"].contains(where: text.contains) { nature = inflow ? .unknownIn : .unknownOut }
        else { nature = inflow ? .income : .expense }
        return Classification(category: "待整理", nature: nature, reason: "保留账单流向与明确性质，等待整理")
    }
}

public enum ImportStatus: String, Sendable { case ready, duplicate, possibleDuplicate, needsAccount, conflict, invalid, skipped }
public struct ImportRow: Identifiable, Sendable {
    public var id = UUID(); public var line: Int; public var entry: Entry?; public var status: ImportStatus
    public var message: String; public var included: Bool
    public var paymentMethod: String = ""
}
public struct ImportPreview: Sendable {
    public var filename: String; public var source: String; public var rows: [ImportRow]; public var warnings: [String]
    public var columnMapping: ImportColumnMapping? = nil
    public var mappedHeader: Int? = nil
    public var selectedEntries: [Entry] { rows.filter(\.included).compactMap(\.entry) }
    public var readyCount: Int { rows.filter { $0.status == .ready }.count }
    public var duplicateCount: Int { rows.filter { $0.status == .duplicate }.count }
    public var issueCount: Int { rows.filter { [.invalid, .conflict, .possibleDuplicate, .needsAccount].contains($0.status) }.count }
    public var paymentMethods: [String] { Array(Set(rows.map(\.paymentMethod).filter { !$0.isEmpty })).sorted() }

}

public enum CSV {
    public static func decode(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .utf8) { return s.replacingOccurrences(of: "\u{FEFF}", with: "") }
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: encoding)) { return s }
        throw YubaiError.invalid("无法识别文件编码，请导出为 UTF-8 CSV 或 XLSX。")
    }
    public static func parse(_ text: String, delimiter: Character? = nil) throws -> [[String]] {
        // Swift treats CRLF as one grapheme cluster; normalize before iterating Characters.
        let canonical = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let sample = canonical.split(separator: "\n").prefix(30).joined(separator: "\n")
        let separator = delimiter ?? (sample.filter { $0 == "\t" }.count > sample.filter { $0 == "," }.count ? "\t" : ",")
        var rows: [[String]] = []; var row: [String] = []; var cell = ""; var quoted = false; var endedQuote = false
        var cellBytes = 0; var cells = 0; var i = canonical.startIndex
        func append(_ c: Character) throws {
            cellBytes += String(c).utf8.count
            guard cellBytes <= 100_000 else { throw YubaiError.invalid("单个字段过长，请检查账单格式。") }
            cell.append(c)
        }
        func finishCell() throws {
            cells += 1
            guard row.count < 256, cells <= 1_000_000 else { throw YubaiError.invalid("表格超过 256 列或 100 万个单元格，请按时间分段导入。") }
            row.append(cell); cell = ""; cellBytes = 0; endedQuote = false
        }
        while i < canonical.endIndex {
            let c = canonical[i]; let next = canonical.index(after: i)
            if quoted {
                if c == "\"" { if next < canonical.endIndex && canonical[next] == "\"" { try append("\""); i = next } else { quoted = false; endedQuote = true } }
                else { try append(c) }
            } else if c == "\"" && cell.isEmpty && !endedQuote { quoted = true }
            else if c == separator { try finishCell() }
            else if c == "\n" {
                try finishCell(); if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
            } else { try append(c) }
            if rows.count > 100_000 { throw YubaiError.invalid("超过 10 万行，请按时间分段导入。") }
            i = canonical.index(after: i)
        }
        guard !quoted else { throw YubaiError.invalid("CSV 引号没有闭合，文件可能未完整导出。") }
        if !cell.isEmpty || !row.isEmpty || endedQuote { try finishCell(); rows.append(row) }
        return rows
    }

}

public enum BillImporter {
    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{FEFF}", with: "") }
    static func normalized(_ s: String) -> String { clean(s).lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")") }
    static let dateNames = ["交易时间", "交易创建时间", "记账日期", "交易日期", "日期", "时间", "date", "datetime", "入账日期", "记账时间", "发生时间", "发生日期", "账单日期"]
    static let amountNames = ["金额(元)", "金额", "交易金额", "交易金额(元)", "发生额", "amount", "支出金额", "收入金额", "借方发生额", "贷方发生额"]
    static func sourceKey(_ entry: Entry) -> String {
        if !entry.sourceIdentity.isEmpty { return entry.sourceIdentity }
        let source = entry.source == "文件" ? entry.source + ":" + entry.accountID.uuidString : entry.source
        return source + ":" + entry.externalID + (entry.nature == .refund ? ":refund" : "")
    }
    public static func preview(data: Data, filename: String, accountID: UUID, ledger: Ledger, accountMappings: [String: UUID] = [:], requireAccountMapping: Bool = false, mapping: ImportColumnMapping? = nil, mappedHeader: Int = 0) throws -> ImportPreview {
        guard data.count <= 50 * 1024 * 1024 else { throw YubaiError.invalid("单个账单请小于 50 MB。") }
        guard ledger.accounts.contains(where: { $0.id == accountID }), accountMappings.values.allSatisfy({ id in ledger.accounts.contains { $0.id == id } }) else { throw YubaiError.invalid("导入账户不存在，请重新选择。") }
        let workbook = filename.lowercased().hasSuffix(".xlsx") ? try XLSX.readWorkbook(data) : nil
        let table = try workbook?.rows ?? CSV.parse(CSV.decode(data), delimiter: filename.lowercased().hasSuffix(".tsv") ? "\t" : nil)
        let knownHeader = table.firstIndex(where: { row in
            let h = row.map(normalized)
            return h.contains(where: { dateNames.map(normalized).contains($0) }) && h.contains(where: { amountNames.map(normalized).contains($0) })
        })
        guard let headerIndex = mapping == nil ? knownHeader : mappedHeader, table.indices.contains(headerIndex) else { throw ImportColumnError.missing }
        let headers = table[headerIndex].map(normalized)
        func index(_ aliases: [String]) -> Int? { headers.firstIndex { aliases.map(normalized).contains($0) } }
        if let mapping { try mapping.validate(headers: table[headerIndex], samples: Array(table.dropFirst(headerIndex + 1).prefix(5)), date1904: workbook?.date1904) }
        let dateCol = mapping?.date ?? index(dateNames)!, amountCol = mapping?.amount ?? (mapping == nil ? index(amountNames) : nil)
        let debitCol = mapping?.outflow ?? (mapping == nil ? index(["支出金额", "借方发生额"]) : nil), creditCol = mapping?.inflow ?? (mapping == nil ? index(["收入金额", "贷方发生额"]) : nil)
        let namedDirectionCol = mapping == nil ? index(["收/支", "收支", "收支类型", "收入/支出", "direction", "借贷标志", "收支方向"]) : nil
        let directionWords = Set(["收入", "收", "贷", "in", "income", "credit", "支出", "支", "借", "out", "expense", "debit", "转账", "transfer", Nature.transfer.label])
        // Only inspect values when header aliases cannot establish a direction column.
        // Stop at the first incompatible cell; no full-column copies are needed.
        let valueDirectionCol = mapping == nil && namedDirectionCol == nil ? headers.indices.first { col in
            var hasValue = false
            for row in table.dropFirst(headerIndex + 1) where row.indices.contains(col) {
                let value = normalized(row[col])
                if value.isEmpty { continue }
                guard directionWords.contains(value) else { return false }
                hasValue = true
            }
            return hasValue
        } : nil
        let directionCol = mapping?.direction ?? mapping?.type ?? namedDirectionCol ?? valueDirectionCol
            ?? (mapping == nil ? index(["类型", "交易类型", "type"]) : nil)
        let titleCol = mapping?.description ?? (mapping == nil ? index(["商品", "商品说明", "商品名称", "摘要", "用途", "名称", "title", "交易备注"]) : nil)
        let merchantCol = mapping?.counterparty ?? (mapping == nil ? index(["交易对方", "对方户名", "商户名称", "merchant"]) : nil)
        let typeCol = mapping?.type ?? index(["交易类型", "类型", "性质", "type"])
        let statusCol = index(["当前状态", "交易状态", "状态", "status"])
        let idCol = index(["交易单号", "交易号", "流水号", "订单号", "交易订单号", "id"])
        let noteCol = mapping?.note ?? (mapping == nil ? index(["备注", "说明", "附言", "memo", "notes", "note"]) : nil)
        let categoryCol = mapping?.category ?? index(["分类", "一级分类", "类别", "分类名称", "category"])
        let subcategoryCol = mapping?.subcategory ?? index(["二级分类", "子分类", "子类别", "subcategory"])
        let fromAccountCol = index(["转出账户", "转出帐户", "支出账户", "from account"])
        let toAccountCol = index(["转入账户", "转入帐户", "收入账户", "to account"])
        let currencyCol = index(["币种", "货币", "currency"])
        let paymentCol = mapping?.account ?? (mapping == nil ? index(["支付方式", "收/付款方式", "收付款方式", "付款方式", "资金渠道", "账户", "帐户", "账户名称", "收支账户", "account"]) : nil)
        let prefix = table.prefix(headerIndex + 1).flatMap { $0 }.joined()
        let isBeeCount = ["类型", "分类", "二级分类", "转出账户", "转入账户"].allSatisfy { headers.contains(normalized($0)) }
        let source = isBeeCount ? "BeeCount" : prefix.contains("微信") || headers.contains(normalized("商品")) && headers.contains(normalized("交易单号")) ? "微信" : (prefix.contains("支付宝") || headers.contains(normalized("交易创建时间")) ? "支付宝" : "文件")
        var knownIDs: [String: Entry] = [:]; var knownHashes: Set<String> = []
        for entry in ledger.entries {
            if !entry.externalID.isEmpty { knownIDs[sourceKey(entry)] = entry }
            if !entry.fingerprint.isEmpty { knownHashes.insert(entry.fingerprint) }
        }
        var rows: [ImportRow] = []; var occurrences: [String: Int] = [:]
        for (offset, row) in table.dropFirst(headerIndex + 1).enumerated() {
            let line = headerIndex + offset + 2
            func field(_ col: Int?) -> String { guard let col, row.indices.contains(col) else { return "" }; return clean(row[col]) }
            let rawDate = field(dateCol) + (mapping?.time.map { " " + field($0) } ?? "")
            var rawAmount = field(amountCol), inferredDirection = ""
            if debitCol != nil && creditCol != nil {
                let debit = field(debitCol), credit = field(creditCol)
                let debitNonzero = !debit.isEmpty && debit != "-" && (try? Money.parse(debit, allowNegative: true)) != 0
                let creditNonzero = !credit.isEmpty && credit != "-" && (try? Money.parse(credit, allowNegative: true)) != 0
                if debitNonzero && creditNonzero { rows.append(ImportRow(line: line, status: .invalid, message: "同一行收入与支出均有金额，请核对原账单", included: false)); continue }
                rawAmount = debitNonzero ? debit : credit
                inferredDirection = debitNonzero ? "支出" : "收入"
            }
            if rawDate.isEmpty && rawAmount.isEmpty { continue }
            if rawDate.hasPrefix("---") || rawDate.contains("共计") || rawDate.hasPrefix("注：") { continue }
            let status = field(statusCol)
            if ["交易关闭", "已关闭", "已取消", "交易失败", "未支付", "等待付款", "支付中"].contains(where: status.contains) {
                rows.append(ImportRow(line: line, status: .skipped, message: "未完成交易：\(status)", included: false)); continue
            }
            do {
                let currency = field(currencyCol).uppercased()
                guard currency.isEmpty || ["CNY", "RMB", "人民币", "元", "156"].contains(currency) else { throw YubaiError.invalid("当前仅支持人民币，此行币种为 \(currency)，未换汇入账") }
                let date: Date
                if let parsed = Dates.parse(rawDate) { date = parsed }
                else if filename.lowercased().hasSuffix(".xlsx"), let serial = Double(rawDate), (1...100000).contains(serial) {
                    guard let excelDate = Dates.excel(serial, date1904: workbook?.date1904 ?? false) else { throw YubaiError.invalid("Excel 日期无效") }; date = excelDate
                } else { throw YubaiError.invalid("无法识别日期“\(rawDate)”") }
                let signed = try Money.parse(rawAmount, allowNegative: true)
                guard signed != 0 else { throw YubaiError.invalid("金额为零") }
                let direction = inferredDirection.isEmpty ? field(directionCol) : inferredDirection
                let type = field(typeCol)
                let isTransfer = ["转账", "transfer", Nature.transfer.label].contains(direction.lowercased()) || type == Nature.transfer.label || ((fromAccountCol != nil || toAccountCol != nil) && ["转账", "transfer"].contains(type.lowercased()))
                let explicitNature = isTransfer ? Nature.transfer : Nature.allCases.first { $0.label == type }
                let inflow: Bool
                if let explicitNature { inflow = explicitNature.inflow }
                else if ["收入", "收", "贷", "in", "income", "credit"].contains(direction.lowercased()) { inflow = true }
                else if ["支出", "支", "借", "out", "expense", "debit"].contains(direction.lowercased()) { inflow = false }
                else if signed < 0 { inflow = false }
                else if ["不计收支", "/", "中性交易"].contains(direction) {
                    if type.contains("退款") { inflow = true }
                    else if ["提现", "还款", "充值"].contains(where: type.contains) { inflow = false }
                    else { throw YubaiError.invalid("不计收支记录方向不明，需要手动补记") }
                } else { throw YubaiError.invalid("缺少收入/支出方向，请使用模板的收支列") }
                let titleParts = [field(merchantCol), field(titleCol)].filter { !$0.isEmpty && $0 != "/" && $0 != "-" }
                let fallbackTitle = [field(noteCol), field(subcategoryCol), field(categoryCol), type].first { !["", "/", "-"].contains($0) } ?? "账单记录"
                let title = titleParts.isEmpty ? fallbackTitle : Array(NSOrderedSet(array: titleParts)).compactMap { $0 as? String }.joined(separator: " · ")
                let classification = Classifier.classify(inflow: inflow, hint: type)
                let method = ["", "/", "-", "--"].contains(field(paymentCol)) ? "" : field(paymentCol)
                func transferAccount(_ name: String) -> UUID? {
                    guard !name.isEmpty else { return nil }
                    if let id = accountMappings[name] { return id }
                    let matches = ledger.accounts.filter { !$0.archived && clean($0.name) == name }
                    return matches.count == 1 ? matches[0].id : nil
                }
                let fromName = field(fromAccountCol), toName = field(toAccountCol)
                let fromAccount = transferAccount(fromName), toAccount = transferAccount(toName)
                let mappedAccount = isTransfer ? (fromAccount ?? accountID) : (accountMappings[method] ?? accountID)
                let needsMapping = isTransfer ? (fromAccount == nil || toAccount == nil) : (requireAccountMapping && !method.isEmpty && accountMappings[method] == nil)
                if isTransfer, let fromAccount, let toAccount, fromAccount == toAccount { throw YubaiError.invalid("转账的两个账户必须不同，请核对原账单或账户对应。") }
                let rawCategory = field(subcategoryCol).isEmpty ? field(categoryCol) : field(subcategoryCol)
                var entry = Entry(date: date, amount: abs(signed), nature: explicitNature ?? classification.nature, accountID: mappedAccount, title: title, category: ledger.resolveCategory(rawCategory.isEmpty ? classification.category : rawCategory))
                if isTransfer { entry.otherAccountID = toAccount }
                entry.note = [field(noteCol), status.isEmpty ? "" : "原账单状态：" + status, method.isEmpty ? "" : "收付款方式：" + method].filter { !$0.isEmpty }.joined(separator: "\n"); entry.source = source; entry.sourceRow = line; entry.externalID = field(idCol).replacingOccurrences(of: "\t", with: "")
                if isTransfer {
                    entry.note += "\n转出账户：" + fromName + "；转入账户：" + toName
                }
                entry.classificationReason = classification.reason
                let baseIdentity = [source, String(date.timeIntervalSince1970), Money.input(entry.amount), inflow ? "+" : "-", title, mappedAccount.uuidString].joined(separator: "|") + (isTransfer ? "|to:" + (toAccount?.uuidString ?? toName) : "")
                let ordinal = occurrences[baseIdentity, default: 0]; occurrences[baseIdentity] = ordinal + 1
                // Distinct stable IDs are distinct events. Without IDs, retain duplicate-looking rows within a file by occurrence count.
                let identity = baseIdentity + "|" + (entry.externalID.isEmpty ? "occurrence:\(ordinal)" : entry.externalID)
                entry.fingerprint = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                var rowStatus: ImportStatus = .ready; var message = classification.reason
                let key = sourceKey(entry); entry.sourceIdentity = entry.externalID.isEmpty ? "" : key
                if !entry.externalID.isEmpty, let old = knownIDs[key] {
                    if old.amount != entry.amount && !old.userEdited { rowStatus = .conflict; message = "相同交易单号出现不同金额，未覆盖原记录" }
                    else { rowStatus = .duplicate; message = old.deletedAt != nil ? "已删除的记录，保留你的删除决定" : (old.userEdited ? "已存在，保留你的修改" : "交易单号已存在") }
                } else if needsMapping { rowStatus = .needsAccount; message = isTransfer ? "请对应转出账户“\(fromName)”和转入账户“\(toName)”" : "请选择“\(method)”对应的实际账户" }
                else if knownHashes.contains(entry.fingerprint) { rowStatus = .duplicate; message = "同来源、时间、金额和用途已存在" }
                else if ledger.activeEntries.contains(where: { $0.source != source && $0.amount == entry.amount && $0.nature.inflow == entry.nature.inflow && abs($0.date.timeIntervalSince(date)) < 60 && $0.accountID == mappedAccount }) {
                    rowStatus = .possibleDuplicate; message = "另一来源有同时间同金额记录，核对后可选中导入"
                }
                if rowStatus == .ready && status.contains("退款") && entry.nature != .refund { message += "；含退款状态，退款明细需另行导入或补记" }
                rows.append(ImportRow(line: line, entry: entry, status: rowStatus, message: message, included: rowStatus == .ready, paymentMethod: isTransfer ? (fromAccount == nil ? fromName : (toAccount == nil ? toName : "")) : method))
                if rowStatus == .ready {
                    knownHashes.insert(entry.fingerprint)
                    if !entry.externalID.isEmpty { knownIDs[key] = entry }
                }
            } catch { rows.append(ImportRow(line: line, status: .invalid, message: error.localizedDescription, included: false)) }
        }
        guard !rows.isEmpty else { throw YubaiError.invalid("表头已识别，但没有发现可导入的交易行。") }
        var warnings = ["按实际收付款账户入账。未填写收付款方式的行归入所选默认账户。"]
        if rows.contains(where: { $0.status == .needsAccount }) { warnings.append("账单包含不同收付款方式，请在上方逐组选择对应账户；未对应的行暂不入账。") }
        if rows.contains(where: { $0.status == .invalid }) { warnings.append("有行无法识别，详情已保留；这些行不会悄悄计入账本。") }
        return ImportPreview(filename: filename, source: source, rows: rows, warnings: warnings, columnMapping: mapping, mappedHeader: mapping == nil ? nil : headerIndex)
    }
    public static func commit(_ preview: ImportPreview, data: Data, to ledger: inout Ledger) throws -> ImportBatch {
        var candidate = ledger
        let batch = try commitValidated(preview, data: data, to: &candidate)
        ledger = candidate
        return batch
    }
    private static func commitValidated(_ preview: ImportPreview, data: Data, to ledger: inout Ledger) throws -> ImportBatch {
        guard preview.rows.filter(\.included).allSatisfy({ [.ready, .possibleDuplicate].contains($0.status) }) else { throw YubaiError.invalid("仍有不可入账的行被选中，请重新预览并核对账户。") }
        guard !preview.selectedEntries.isEmpty else { throw YubaiError.invalid("还没有选中可导入的记录。") }
        var batch = ImportBatch(filename: preview.filename, importedCount: preview.selectedEntries.count, duplicateCount: preview.duplicateCount, skippedCount: preview.rows.filter { !$0.included && $0.status != .duplicate }.count)
        batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
        let attachment = Attachment(name: preview.filename, data: data); batch.attachmentID = attachment.id
        var existing = Set(ledger.entries.map(\.id))
        let existingSourceIDs = Set(ledger.entries.filter { !$0.externalID.isEmpty }.map(sourceKey))
        let existingHashes = Set(ledger.entries.map(\.fingerprint).filter { !$0.isEmpty })
        for var entry in preview.selectedEntries {
            guard !existing.contains(entry.id) else { throw YubaiError.invalid("这一批记录已保存，请重新读取文件。") }
            guard entry.externalID.isEmpty || !existingSourceIDs.contains(sourceKey(entry)), entry.fingerprint.isEmpty || !existingHashes.contains(entry.fingerprint) else { throw YubaiError.invalid("账本在预览后发生变化，已有重复记录。请重新预览，再确认导入。") }
            existing.insert(entry.id); entry.batchID = batch.id; entry.attachmentID = attachment.id; ledger.entries.append(entry)
        }
        ledger.attachments.append(attachment); ledger.imports.append(batch); try ledger.validate(); return batch
    }
    public static func undo(batchID: UUID, in ledger: inout Ledger, now: Date = Date()) {
        guard let batch = ledger.imports.first(where: { $0.id == batchID }) else { return }
        if let undo = batch.undo {
            ledger.entries.removeAll { $0.batchID == batchID }
            for original in undo.entries {
                if let i = ledger.entries.firstIndex(where: { $0.id == original.id }) { ledger.entries[i] = original }
            }
            ledger.plans.removeAll { undo.planIDs.contains($0.id) }
            ledger.cards.removeAll { undo.cardIDs.contains($0.id) }
            for id in undo.memoryIDs ?? [] { Memory.reject(lineMemoryID: id, in: &ledger, now: now) }
            ledger.attachments.removeAll { $0.id == batch.attachmentID }
            ledger.imports.removeAll { $0.id == batchID }
            ledger.updatedAt = undo.updatedAt
        } else {
            // Legacy batches lack the originals needed for a complete restoration.
            for i in ledger.entries.indices where ledger.entries[i].batchID == batchID && ledger.entries[i].deletedAt == nil { ledger.entries[i].deletedAt = now }
            if let i = ledger.imports.firstIndex(where: { $0.id == batchID }) { ledger.imports[i].undoneAt = now }
        }
    }
}

private struct ZIP {
    struct Item { var name: String; var method: UInt16; var compressed: Int; var size: Int; var offset: Int; var crc: UInt32 }
    let data: Data; let items: [Item]
    init(_ data: Data) throws {
        guard data.count > 22, data.count <= 50 * 1024 * 1024 else { throw YubaiError.invalid("XLSX 文件为空或过大。") }
        func u16(_ i: Int) -> UInt16 { UInt16(data[i]) | UInt16(data[i+1]) << 8 }
        func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i+2)) << 16 }
        guard let end = stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1).first(where: { u32($0) == 0x06054b50 }) else { throw YubaiError.invalid("XLSX 压缩目录损坏。") }
        let count = Int(u16(end + 10)); var cursor = Int(u32(end + 16)); var found: [Item] = []; var total = 0
        guard count <= 5000 else { throw YubaiError.invalid("XLSX 包含过多内容，请只导出账单工作表。") }
        for _ in 0..<count {
            guard cursor >= 0, cursor + 46 <= data.count, u32(cursor) == 0x02014b50 else { throw YubaiError.invalid("XLSX 目录不完整。") }
            let flags = u16(cursor + 8); let nameLength = Int(u16(cursor + 28)), extra = Int(u16(cursor + 30)), comment = Int(u16(cursor + 32))
            guard flags & 1 == 0 else { throw YubaiError.invalid("请先用账单密码解密文件，再导入未加密 XLSX。") }
            guard cursor + 46 + nameLength + extra + comment <= data.count else { throw YubaiError.invalid("XLSX 文件已截断。") }
            let size = Int(u32(cursor + 24)); total += size
            guard size <= 30 * 1024 * 1024, total <= 100 * 1024 * 1024 else { throw YubaiError.invalid("XLSX 解压内容过大。") }
            let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8) ?? ""
            found.append(Item(name: name, method: u16(cursor + 10), compressed: Int(u32(cursor + 20)), size: size, offset: Int(u32(cursor + 42)), crc: u32(cursor + 16)))
            cursor += 46 + nameLength + extra + comment
        }
        self.data = data; self.items = found
    }
    func read(_ name: String) throws -> Data? {
        guard let item = items.first(where: { $0.name == name }) else { return nil }
        let o = item.offset
        guard o >= 0, o + 30 <= data.count else { throw YubaiError.invalid("XLSX 内容偏移无效。") }
        func u16(_ i: Int) -> Int { Int(data[i]) | Int(data[i+1]) << 8 }
        guard data.subdata(in: o..<o+4) == Data([0x50, 0x4b, 0x03, 0x04]), u16(o+8) == Int(item.method), o + 30 + u16(o+26) <= data.count,
              String(data: data.subdata(in: o+30..<o+30+u16(o+26)), encoding: .utf8) == item.name else { throw YubaiError.invalid("XLSX 本地文件头与目录不一致，文件可能损坏。") }
        let start = o + 30 + u16(o+26) + u16(o+28)
        guard start >= 0, item.compressed >= 0, start + item.compressed <= data.count else { throw YubaiError.invalid("XLSX 数据不完整。") }
        let source = data.subdata(in: start..<start + item.compressed)
        var output: Data
        if item.method == 0 { output = source }
        else if item.method == 8 {
            output = Data(count: max(1, item.size))
            let result = output.withUnsafeMutableBytes { destination in source.withUnsafeBytes { input in yubai_inflate(input.bindMemory(to: UInt8.self).baseAddress, source.count, destination.bindMemory(to: UInt8.self).baseAddress, item.size) } }
            guard result == 0 else { throw YubaiError.invalid("XLSX 解压失败。") }
            output = output.prefix(item.size)
        } else { throw YubaiError.invalid("XLSX 使用了不支持的压缩方式。") }
        let crc = output.withUnsafeBytes { yubai_crc32($0.bindMemory(to: UInt8.self).baseAddress, output.count) }
        guard output.count == item.size, crc == item.crc else { throw YubaiError.invalid("XLSX 校验失败，文件可能损坏。") }
        return output
    }
}

public enum XLSX {
    public static func read(_ data: Data) throws -> [[String]] {
        try readWorkbook(data).rows
    }
    static func readWorkbook(_ data: Data) throws -> (rows: [[String]], date1904: Bool) {
        let zip = try ZIP(data); var strings: [String] = []
        var date1904 = false
        if let workbook = try zip.read("xl/workbook.xml") { let metadata = SpreadsheetXML(mode: .metadata, strings: []); try metadata.parse(workbook); date1904 = metadata.date1904 }
        if let shared = try zip.read("xl/sharedStrings.xml") {
            let delegate = SpreadsheetXML(mode: .strings, strings: []); try delegate.parse(shared); strings = delegate.shared
        }
        let sheets = zip.items.map(\.name).filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted()
        guard !sheets.isEmpty else { throw YubaiError.invalid("未发现 XLSX 工作表。") }
        var output: [[String]] = []; var totalCells = 0
        for sheet in sheets {
            if let bytes = try zip.read(sheet) {
                let parser = SpreadsheetXML(mode: .sheet, strings: strings); try parser.parse(bytes)
                totalCells += parser.rows.reduce(0) { $0 + $1.count }
                guard totalCells <= 1_000_000, output.count + parser.rows.count <= 100_000 else { throw YubaiError.invalid("工作簿过大，请按时间分段导入。") }
                output += parser.rows
            }
        }
        return (output, date1904)
    }
}
private final class SpreadsheetXML: NSObject, XMLParserDelegate {
    enum Mode { case strings, sheet, metadata }
    let mode: Mode; let strings: [String]; var shared: [String] = []; var rows: [[String]] = []
    var date1904 = false; var cells = 0; var bufferBytes = 0; var valueBytes = 0
    var row: [String] = []; var value = ""; var buffer = ""; var type = ""; var column = 0; var capturing = false
    init(mode: Mode, strings: [String]) { self.mode = mode; self.strings = strings }
    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data); parser.delegate = self; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw YubaiError.invalid("XLSX 表格不完整或过大。请限制在 256 列、10 万行以内。") }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "workbookPr" { date1904 = ["1", "true"].contains(attributeDict["date1904"] ?? "") }
        if elementName == "row" { row = [] }
        if elementName == "si" { value = ""; valueBytes = 0 }
        if elementName == "c" {
            value = ""; valueBytes = 0; type = attributeDict["t"] ?? ""
            let letters = (attributeDict["r"] ?? "A1").prefix { $0.isLetter }
            guard !letters.isEmpty, letters.count <= 3, letters.utf8.allSatisfy({ (65...90).contains($0) }) else { parser.abortParsing(); return }
            column = letters.uppercased().utf8.reduce(0) { $0 * 26 + Int($1) - 64 } - 1
            if column < 0 || column >= 256 { parser.abortParsing(); return }
        }
        if elementName == "v" || elementName == "t" { capturing = true; buffer = ""; bufferBytes = 0 }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if capturing { bufferBytes += string.utf8.count; guard bufferBytes <= 100_000 else { parser.abortParsing(); return }; buffer += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" { capturing = false; valueBytes += bufferBytes; guard valueBytes <= 100_000 else { parser.abortParsing(); return }; value += buffer; buffer = "" }
        if elementName == "si" { shared.append(value); if shared.count > 1_000_000 { parser.abortParsing(); return } }
        if elementName == "c" {
            while row.count <= column { row.append("") }
            if type == "s", let index = Int(value), strings.indices.contains(index) { row[column] = strings[index] }
            else { row[column] = value }
        }
        if elementName == "row" { cells += row.count; rows.append(row); if rows.count > 100_000 || cells > 1_000_000 { parser.abortParsing() } }
    }
}
