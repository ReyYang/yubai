import Foundation
import YubaiCore

/// UI-only policy. Import.swift assigns these four source names and sourceRow;
/// committed imports also carry batchID. Capture/assistant/automatic entries
/// keep their purpose but do not expose legacy manual notes as a second field.
enum EntryNotePresentation {
    static func isImported(_ entry: Entry) -> Bool {
        entry.sourceRow != nil || entry.batchID != nil || ["文件", "微信", "支付宝", "BeeCount"].contains(entry.source)
    }
    static func importedNote(_ entry: Entry) -> String { isImported(entry) ? entry.note : "" }
    static func manualPurposes(_ entries: [Entry]) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: entries.filter { !$0.note.isEmpty && !isImported($0) }.map { ($0.id, $0.displayTitle) })
    }
}
