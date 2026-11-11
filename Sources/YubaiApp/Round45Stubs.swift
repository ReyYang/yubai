import SwiftUI
import YubaiCore

// Placeholders for types that will live in files owned by P1–P4. Each one is deleted by the package named
// in its comment when that package defines the real type in its own file.

// STUB: replaced by P1 (the real type is `LetterInboxView` renamed, in NowActionCards.swift).
struct TodoView: View {
    var body: some View { LetterInboxView() }
}

// STUB: replaced by P2 (SpendingPartsView.swift).
struct BudgetView: View {
    var body: some View { SpendingPartsView(backTitle: "现在") }
}

// STUB: replaced by P2 (FixedFlowsView.swift).
struct BillDetailView: View {
    let planID: UUID
    var body: some View { Text("") }
}
// STUB: replaced by P2 (FixedFlowsView.swift).
struct BillPaySheet: View {
    let planID: UUID
    let occurrence: Date
    var body: some View { Text("") }
}
// STUB: replaced by P2 (FixedFlowsView.swift).
struct BillMatchSheet: View {
    let planID: UUID
    let occurrence: Date
    let entryID: UUID
    var body: some View { Text("") }
}
// STUB: replaced by P2 (FixedFlowsView.swift).
struct BillLinkSheet: View {
    let planID: UUID
    let occurrence: Date
    var body: some View { Text("") }
}
// STUB: replaced by P2 (FixedFlowsView.swift).
struct BillAddSheet: View {
    var body: some View { Text("") }
}
// STUB: replaced by P2 (FixedFlowsView.swift). The tick button shared by the 现在 page and the 算式 page.
struct BillCheck: View {
    let planID: UUID
    let occurrence: Date
    var body: some View { Text("") }
}
