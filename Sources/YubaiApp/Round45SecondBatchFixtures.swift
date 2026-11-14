#if DEBUG && targetEnvironment(simulator)
import Foundation
import YubaiCore

extension UITestSupport {
    static let secondBatchScripts: Set<String> = ["v45-import-plans", "v45-import-merge", "v45-receipt", "v45-principles", "v45-backup", "v45-ai", "v45-repeats"]
    static let secondBatchManualID = UUID(uuidString: "45000000-0000-0000-0000-000000000005")!

    static var secondBatchReceipt: ReceiptCandidate? {
        guard script == "v45-receipt" else { return nil }
        let text = ["合成超市", Dates.text(Dates.now), "牛奶、鸡蛋、蔬菜 -96.50 支出", "洗衣液 -59.90 支出", "坚果 -30.00 支出", "合计 186.40"].joined(separator: "\n")
        return ReceiptCandidate(text: text, amounts: ["96.50", "59.90", "30.00"], title: "合成超市", date: Dates.now)
    }
    static var secondBatchBackupFolder: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard script == "v45-backup", let index = arguments.firstIndex(of: "--test-ledger"), arguments.indices.contains(index + 1) else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YubaiUITests/" + arguments[index + 1] + "/自动备份", isDirectory: true)
    }
    static var secondBatchBackupFileCount: Int {
        guard let folder = secondBatchBackupFolder else { return 0 }
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "yubaibackup" }.count
    }
    @MainActor static func secondBatchState(in ledger: Ledger) -> String {
        let manual = ledger.entries.first { $0.id == secondBatchManualID }
        return "requests=\(UITestRequestLog.shared.count);entries=\(ledger.activeEntries.count);plans=\(ledger.plans.count);batches=\(ledger.imports.count);manualSource=\(manual?.source ?? "");manualTitle=\(manual?.displayTitle ?? "");manualCategory=\(manual?.category ?? "")"
    }
    @MainActor static func prepareSecondBatch(_ repository: LedgerRepository, script: String, now: Date) throws {
        var ledger = Ledger()
        if let appearance = galleryAppearance { ledger.preferences.appearance = appearance }
        ledger.preferences.onboardingComplete = true
        ledger.preferences.cloudAIEnabled = ["v45-receipt", "v45-principles", "v45-ai"].contains(script)
        ledger.cycleAnchor = .calendarMonth
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.lastSubcategoryBatchDay = Dates.text(now)
        ledger.mutedTopics = ["letter"]
        let account = Account(name: "合成银行卡", balance: 1_000_000, at: Dates.addDays(-1000, to: now))
        ledger.accounts = [account]
        switch script {
        case "v45-import-plans":
            let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
            var rows = ["时间,收支,金额,名称,分类,交易单号"]
            for index in 1...3 {
                let start = Dates.addMonths(-index, to: month)
                rows.append(Dates.text(Dates.addDays(14, to: start)) + " 12:00:00,收入,8000.00,合成工资,工资奖金,salary-\(index)")
                rows.append(Dates.text(Dates.addDays(15, to: start)) + " 12:00:00,支出,3500.00,合成房租,居住,rent-\(index)")
            }
            let data = Data(rows.joined(separator: "\n").utf8)
            let preview = try BillImporter.preview(data: data, filename: "合成流水.csv", accountID: account.id, ledger: ledger)
            let batch = try BillImporter.commit(preview, data: data, to: &ledger, now: now)
            if let index = ledger.imports.firstIndex(where: { $0.id == batch.id }) { ledger.imports[index].needsOrganization = false }
        case "v45-import-merge":
            var manual = Entry(date: Dates.day(now), amount: 1800, accountID: account.id, title: "合成手记咖啡", category: "餐饮")
            manual.id = secondBatchManualID; manual.purpose = "合成手记咖啡"; manual.note = "合成原备注"; manual.recordedAt = now; manual.userEdited = true
            ledger.entries = [manual]
        case "v45-repeats", "v45-ai":
            for (index, row) in [("地铁", Int64(800), "交通"), ("午饭", Int64(2800), "餐饮"), ("咖啡", Int64(3200), "餐饮")].enumerated() {
                for offset in 1...2 {
                    let date = now.addingTimeInterval(-Double(offset * 3600 + index * 60))
                    var entry = Entry(date: date, amount: row.1, accountID: account.id, title: row.0, category: row.2)
                    entry.recordedAt = date; entry.purpose = row.0; ledger.entries.append(entry)
                }
            }
        case "v45-backup":
            ledger.preferences.weeklyAutoBackup = true
            ledger.preferences.lastBackupAt = Dates.addDays(-8, to: now)
            if let folder = secondBatchBackupFolder {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try WeeklyBackupAccess.shared.remember(folder, for: ledger.id)
            }
        default: break
        }
        try ledger.validate()
        try repository.save(ledger, reason: "合成测试夹具")
    }

    static func secondBatchReceiptReply(_ request: ChatRequest, script: String) throws -> ChatMessage? {
        guard script == "v45-receipt", request.purpose == "拍小票、认截图" else { return nil }
        let rows: [JSONValue] = [("牛奶、鸡蛋、蔬菜", "96.50"), ("洗衣液", "59.90"), ("坚果", "30.00")].map {
            .object(["title": .string($0.0), "amount": .string($0.1), "date": .string(Dates.text(Dates.now)), "income": .bool(false)])
        }
        return ChatMessage(role: .assistant, content: try JSONValue.object(["shop": .string("合成超市"), "rows": .array(rows)]).jsonText())
    }
}
#endif
