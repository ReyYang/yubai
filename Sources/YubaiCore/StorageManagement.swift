import Foundation

public struct StorageUsage: Equatable, Sendable {
    public var ledgerBytes: Int64 = 0
    public var attachmentBytes: Int64 = 0
    public var recoveryBytes: Int64 = 0
    public var recoveryCount: Int = 0
    public var oldestRecovery: Date?
    public var totalBytes: Int64 { ledgerBytes + attachmentBytes + recoveryBytes }
    public init() {}
}

/// Classification depends on references, never filename or image format. Undone imports
/// still own their originals; soft-deleted entries still own their screenshots.
public enum StorageAttachments {
    public struct Classification: Sendable {
        public var screenshots: [Attachment]
        public var originals: [Attachment]
        public var oldest: Date? { (screenshots + originals).map(\.createdAt).min() }
    }
    public static func classify(in ledger: Ledger) -> Classification {
        let originals = Set(ledger.imports.compactMap(\.attachmentID))
        let entries = Set(ledger.entries.compactMap(\.attachmentID))
        return Classification(screenshots: ledger.attachments.filter { entries.contains($0.id) && !originals.contains($0.id) },
                              originals: ledger.attachments.filter { originals.contains($0.id) })
    }
    public static func oldScreenshots(in ledger: Ledger, months: Int, now: Date = Dates.now, calendar: Calendar = .current) -> [Attachment] {
        guard [3, 6, 12].contains(months), let cutoff = calendar.date(byAdding: .month, value: -months, to: now) else { return [] }
        return classify(in: ledger).screenshots.filter { $0.createdAt < cutoff }
    }
    @discardableResult public static func removeOldScreenshots(from ledger: inout Ledger, months: Int, now: Date = Dates.now, calendar: Calendar = .current) -> [Attachment] {
        let removed = oldScreenshots(in: ledger, months: months, now: now, calendar: calendar)
        let ids = Set(removed.map(\.id))
        ledger.attachments.removeAll { ids.contains($0.id) }
        for i in ledger.entries.indices where ledger.entries[i].attachmentID.map(ids.contains) == true {
            ledger.entries[i].attachmentID = nil
        }
        // Undoing an import must not reintroduce a dangling screenshot reference.
        for i in ledger.imports.indices where ledger.imports[i].undo != nil {
            for j in ledger.imports[i].undo!.entries.indices where ledger.imports[i].undo!.entries[j].attachmentID.map(ids.contains) == true {
                ledger.imports[i].undo!.entries[j].attachmentID = nil
            }
        }
        return removed
    }
}

public enum StorageSize {
    public static func text(_ bytes: Int64) -> String {
        let unit: (Double, String) = bytes >= 1_000_000_000 ? (1_000_000_000, "GB") : bytes >= 1_000_000 ? (1_000_000, "MB") : (1_000, "KB")
        return String(format: "%.1f %@", locale: Locale(identifier: "en_US_POSIX"), Double(max(0, bytes)) / unit.0, unit.1)
    }
}
