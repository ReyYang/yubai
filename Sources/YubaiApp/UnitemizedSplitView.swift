import SwiftUI
import YubaiCore

struct UnitemizedSplitSheet: View {
    @Environment(AppStore.self) private var store
    let entryID: UUID
    var body: some View {
        if let entry = store.entriesByID[entryID], entry.deletedAt == nil, entry.isUnitemized {
            UnitemizedSplitEditor(original: entry)
        }
    }
}

/// 先列出想起来的几笔，确认后一次拆分；账本快照保留给撤销。
private struct UnitemizedSplitEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: Entry
    @State private var parts: [EntryDraft] = []
    @State private var keypad = EntryKeypad()
    @State private var purpose = ""
    @State private var category = CategoryAssignment(category: "")
    @State private var hint: CategoryAssignment?
    @State private var date: Date
    @State private var pickingDate = false
    @State private var pickingCategory = false
    @State private var confirmingDiscard = false
    @FocusState private var purposeFocused: Bool

    init(original: Entry) { self.original = original; _date = State(initialValue: original.date) }
    private var total: Int64 { parts.reduce(0) { $0 + $1.amount } }
    private var remaining: Int64 { original.amount - total }
    private var amount: Int64 { keypad.amount ?? 0 }
    private var canAdd: Bool { keypad.canSave && amount <= remaining && purpose.count <= 4000 }
    private var canSplit: Bool { !parts.isEmpty && amount == 0 || canAdd }
    private var range: ClosedRange<Date> { Dates.day(original.spreadFrom ?? original.date)...original.date }
    private var dirty: Bool { !parts.isEmpty || amount > 0 || !purpose.isEmpty }

    var body: some View {
        EntryForm(title: "拆成几笔", actionTitle: "都记下", enabled: canSplit,
                  actionIdentifier: "splitUnitemizedDone", scrollIdentifier: "splitUnitemizedScroll", cancelIdentifier: "splitUnitemizedCancel", cancel: cancel, save: save) {
            ResultBar(label: "没细记", value: amount2(remaining - (canAdd ? amount : 0), hide: store.preferences.hideAmounts), identifier: "splitUnitemizedRemaining")
            stagedRows
            EditableAmountDisplay(amount: keypad.resultText, keypad: keypad, presented: true, selected: false,
                                  identifier: "splitUnitemizedAmount", open: { purposeFocused = false })
            EntryCategoryGrid(nature: .expense, selection: category, hint: hint?.category,
                              choose: { category = $0 ?? CategoryAssignment(category: ""); purposeFocused = false },
                              more: { purposeFocused = false; pickingCategory = true })
        }.fixedBottomBar() { tray }
            .paperBackground().environment(\.yubaiFormSurface, true)
            .sheet(isPresented: $pickingDate) { dateSheet }
            .sheet(isPresented: $pickingCategory) {
                EntryMoreCategorySheet(income: false, selection: category, suggested: hint?.category,
                                       choose: { category = $0; pickingCategory = false }, dismiss: { pickingCategory = false })
            }
            .task(id: "\(store.ledgerRevision)-\(purpose)") { await refreshHint() }
            .entryDiscardGuard(dirty: dirty, amount: total + amount, confirming: $confirmingDiscard)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.large])
            #endif
    }
    private var tray: some View {
        EntryKeyboardTray(purpose: $purpose, purposeIdentifier: "splitUnitemizedPurpose", focus: $purposeFocused) {
            ChipFlow {
                Button { purposeFocused = false; pickingDate = true } label: {
                    Label(ManualBookkeeping.dayLabel(date), systemImage: "calendar").yubaiFont(YubaiFont.callout)
                        .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.tapMin)
                        .background(YubaiColor.keyFn, in: Capsule())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("splitUnitemizedDate")
                Text(store.accountName(original.accountID)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            }
        } keys: {
            if !purposeFocused {
                AmountKeypad(keypad: $keypad, canSave: canAdd, primaryTitle: "好", primaryIdentifier: "splitUnitemizedAdd", save: addPart, embedded: true)
            }
        }
    }
    @ViewBuilder private var stagedRows: some View {
        if !parts.isEmpty {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        stagedRow(part)
                        if index < parts.count - 1 { EntryFormDivider() }
                    }
                }
            }.accessibilityIdentifier("splitUnitemizedParts")
        }
    }
    private func stagedRow(_ part: EntryDraft) -> some View {
        HStack(spacing: YubaiSpace.space8) {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(part.purpose ?? part.title).yubaiFont(YubaiFont.rowTitle)
                Text(Classification.displayCategory(part.category) + " · " + FixedFlowPresentation.monthDay(part.date))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: part.amount, hide: store.preferences.hideAmounts, sign: .outflow)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { parts.removeAll { $0.id == part.id } } label: {
                Image(systemName: "xmark").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityLabel("删掉" + part.title).accessibilityIdentifier("splitUnitemizedRemove_" + part.id.uuidString)
        }.padding(.vertical, YubaiSpace.space8)
    }
    private var dateSheet: some View {
        ScrollView {
            VStack(spacing: YubaiSpace.space8) {
                ManualSheetHeader(title: "日期", actionTitle: "好", actionIdentifier: "splitUnitemizedDateDone", cancelIdentifier: "splitUnitemizedDateCancel",
                                  cancel: { pickingDate = false }, action: { pickingDate = false })
                EntryCalendarView(selection: $date, today: store.financialNow, bounds: range, identifier: "splitUnitemizedCalendar")
            }.padding(.horizontal, YubaiSpace.insetPage)
        }.yubaiSheetBackground()
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
    }
    private func nextPart() -> EntryDraft? {
        guard canAdd else { return nil }
        let clean = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let main = category.category.isEmpty ? Classification.pendingCategory : category.category
        var part = EntryDraft(date: min(original.date, max(range.lowerBound, date)), amount: amount, amountConfirmed: true,
                              nature: .expense, accountID: original.accountID,
                              title: clean.isEmpty ? Classification.displayCategory(main) : clean,
                              category: main, subcategory: category.subcategory, purpose: clean.isEmpty ? nil : clean)
        part.categoryUserEdited = !Classification.isPending(main)
        return part
    }
    private func addPart() {
        guard let part = nextPart() else { return }
        parts.append(part); keypad.reset(); purpose = ""; category = CategoryAssignment(category: ""); purposeFocused = false
    }
    private func cancel() { if dirty { confirmingDiscard = true } else { dismiss() } }
    private func save() {
        guard canSplit else { return }
        let drafts = parts + (nextPart().map { [$0] } ?? [])
        let entryID = original.id
        if store.update("分开记", entryMotion: false, showToast: false, { ledger in
            try Reconciliation.split(entryID: entryID, into: drafts, in: &ledger, now: Date())
        }) {
            store.toast = "已记下 \(drafts.count) 笔"
            dismiss()
        }
    }
    @MainActor private func refreshHint() async {
        let ledger = store.current; let purpose = purpose; let now = Date()
        let value = await Task.detached { EntryHistory.categoryHint(purpose: purpose, nature: .expense, in: ledger, now: now) }.value
        guard !Task.isCancelled else { return }
        hint = value
    }
}
