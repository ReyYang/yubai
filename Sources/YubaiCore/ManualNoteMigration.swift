import Foundation

/// A load migration, not a rule for newly edited notes. Import metadata and bank
/// text stay intact, including imported rows whose source label was later edited.
enum ManualNoteMigration {
    static func apply(to ledger: inout Ledger) {
        guard !ledger.manualNotesMerged else { return }
        func merged(_ old: Entry) -> Entry {
            guard ["手动", "问余白"].contains(old.source), old.batchID == nil,
                  old.sourceRow == nil, old.externalID.isEmpty, old.sourceIdentity.isEmpty,
                  old.fingerprint.isEmpty, !old.note.isEmpty else { return old }
            var entry = old
            let purpose = old.purpose ?? ""
            entry.purpose = String((purpose.isEmpty ? old.note : purpose + " · " + old.note).prefix(4000))
            entry.note = ""
            return entry
        }
        ledger.entries = ledger.entries.map(merged)
        // Retained import undo snapshots may also contain manually made rows.
        for i in ledger.imports.indices where ledger.imports[i].undo != nil {
            ledger.imports[i].undo!.entries = ledger.imports[i].undo!.entries.map(merged)
        }
        ledger.manualNotesMerged = true
    }
}
