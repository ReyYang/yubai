import Foundation

public enum AIFeature: String, Codable, Equatable, Sendable, CaseIterable {
    case importClassification, answers, weeklyReview, receiptRecognition, butlerSuggestions
}
extension Preferences {
    public func isAIEnabled(for feature: AIFeature) -> Bool {
        guard cloudAIEnabled else { return false }
        switch feature {
        case .importClassification: return aiImportClassificationDisabled != true
        case .answers: return aiAnswersDisabled != true
        case .weeklyReview: return aiWeeklyReviewDisabled != true
        case .receiptRecognition: return aiReceiptRecognitionDisabled != true
        case .butlerSuggestions: return butlerSuggestionsEnabled == true
        }
    }
    public mutating func setAIEnabled(_ enabled: Bool, for feature: AIFeature) {
        let disabled: Bool? = enabled ? nil : true
        switch feature {
        case .importClassification: aiImportClassificationDisabled = disabled
        case .answers: aiAnswersDisabled = disabled
        case .weeklyReview: aiWeeklyReviewDisabled = disabled
        case .receiptRecognition: aiReceiptRecognitionDisabled = disabled
        case .butlerSuggestions: butlerSuggestionsEnabled = enabled
        }
    }
}

extension CloudBackend {
    public static func configured(preferences: Preferences, feature: AIFeature, keyStore: APIKeyStore = .shared,
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  redactor: Redactor = .shared) -> CloudBackend? {
        configured(enabled: preferences.isAIEnabled(for: feature), keyStore: keyStore, environment: environment, redactor: redactor)
    }
}

public enum LedgerBackup {
    /// Active entries, including scheduled future entries; CRLF and RFC 4180 quoting.
    public static func entriesCSV(_ ledger: Ledger) -> Data {
        func cell(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let accounts = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0.name) })
        var rows = [["日期", "金额", "性质", "用途", "分类", "小项", "账户", "转入账户", "备注", "来源"]]
        for entry in ledger.entries.filter({ $0.deletedAt == nil }).sorted(by: { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) {
            let cents = entry.amount.magnitude
            let fraction = cents % 100
            let amount = "\(cents / 100).\(fraction < 10 ? "0" : "")\(fraction)"
            rows.append([Dates.text(entry.date, time: true), amount, entry.nature.label, entry.displayTitle,
                         Classification.displayCategory(ledger.normalizedCategory(for: entry).category), entry.subcategory ?? "",
                         accounts[entry.accountID] ?? "", entry.otherAccountID.flatMap { accounts[$0] } ?? "", entry.note, entry.source])
        }
        return Data(("\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }
    public static func isAutoBackupDue(_ preferences: Preferences, now: Date) -> Bool {
        guard preferences.weeklyAutoBackup == true else { return false }
        guard let last = preferences.lastBackupAt else { return true }
        return now >= Dates.addDays(7, to: last)
    }
    /// Call only after the App successfully wrote its backup file.
    public static func recordDone(in preferences: inout Preferences, now: Date) {
        preferences.lastBackupAt = max(preferences.lastBackupAt ?? now, now)
    }
}
