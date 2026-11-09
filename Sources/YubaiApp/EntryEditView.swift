import SwiftUI
import YubaiCore

struct EntryEditView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    var body: some View {
        if let entry = store.entriesByID[entryID], entry.deletedAt == nil {
            EntryEditForm(entry: entry).id(entryID)
        } else { EmptyState("doc.questionmark", "记录已不存在", action: "返回", onAction: { dismiss() }) }
    }
}

struct EntryEditForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: Entry
    var formTitle: String
    var primaryTitle: String
    var onSave: ((Entry) -> Void)?
    @State private var confirmingDiscard = false
    @State private var draft: Entry
    @State private var amount: String
    @State private var purpose: String
    @State private var remembered = false
    @State private var choseCategory = false
    @State private var categoryIsSuggestion = false
    @State private var skipNatureReset = false
    @State private var balances: [UUID: Int64] = [:]
    @State private var keypad = EntryKeypad()
    @State private var amountKeypadPresented = false
    @State private var amountSelected = false
    @State private var repeatsMonthly = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var purposeFocused: Bool
    init(entry: Entry, title: String = "改一笔", primaryTitle: String = "好", onSave: ((Entry) -> Void)? = nil) {
        original = entry; formTitle = title; self.primaryTitle = primaryTitle; self.onSave = onSave
        _draft = State(initialValue: entry)
        _amount = State(initialValue: Money.input(entry.amount))
        _purpose = State(initialValue: entry.displayTitle)
    }
    private var standardNature: Bool { [.expense, .income, .transfer].contains(draft.nature) }
    private var accounts: [Account] { store.accounts.filter { !$0.archived || $0.id == draft.accountID || $0.id == draft.otherAccountID } }
    private var canSave: Bool {
        guard let cents = amountKeypadPresented ? keypad.amount : (try? Money.parse(amount)), cents > 0 else { return false }
        return purpose.count <= 4000 && (draft.nature != .transfer || (draft.otherAccountID != nil && draft.otherAccountID != draft.accountID))
    }
    var body: some View {
        ScrollViewReader { scroll in
                    EntryForm(title: formTitle, actionTitle: primaryTitle, enabled: canSave,
                                  actionIdentifier: onSave == nil ? "saveManualSheet" : "saveDraftEdit", cancel: cancel, save: save) {
                        if draft.source == "Apple Pay" {
                            Pill(text: "来自 Apple Pay · " + (draft.quickCapture?.card ?? "") + " · " + (draft.quickCapture?.transactionDate ?? draft.date).formatted(.dateTime.hour().minute()), variant: .neutral, height: 26, showsDot: false)
                        }
                        if standardNature && draft.source != "Apple Pay" {
                            Segmented(choices: [(Nature.expense, "支出"), (.income, "收入"), (.transfer, "转账")], selection: $draft.nature)
                        } else if !standardNature {
                            Text(draft.nature.entryLabel).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin)
                        }
                        EditableAmountDisplay(amount: amount, keypad: keypad, presented: amountKeypadPresented,
                                              selected: amountSelected, identifier: "editEntryAmount", open: openAmount)
                            .id("editAmount")
                        InlineFieldError(message: currentAmount <= 0 ? "金额须大于 0.00 元" : nil)
                        if draft.nature != .transfer { EntrySavingHintBar(hint: savingHint, afterOverride: previewAfter) }
                        if draft.nature != .transfer {
                            EntryCategoryChips(frequent: ManualBookkeeping.categories(in: store.current, nature: draft.nature, frequentOnly: true),
                                               income: draft.nature != .refund && draft.nature.inflow,
                                               selection: .init(category: draft.category, subcategory: draft.subcategory), suggestionOnly: categoryIsSuggestion, allowsDirectionChange: standardNature && draft.planID == nil && draft.source != "Apple Pay",
                                               suggest: { categoryIsSuggestion ? draft.category : nil }) { choice in
                                if standardNature, let value = store.current.categories.first(where: { $0.name == choice.category }), value.income != draft.nature.inflow {
                                    skipNatureReset = true; draft.nature = value.income ? .income : .expense
                                }
                                draft.category = choice.category; draft.subcategory = choice.subcategory
                                draft.subcategoryUserEdited = true; choseCategory = true; categoryIsSuggestion = false; remembered = false; purposeFocused = false
                            }
                        }
                        EntryFormFields(purpose: $purpose, purposeError: purpose.count > 4000 ? "用途最多 4,000 字" : nil, nature: draft.nature, accounts: accounts, balances: balances,
                                        accountID: Binding(get: { draft.accountID }, set: { if let id = $0 { draft.accountID = id } }),
                                        otherAccountID: $draft.otherAccountID, date: $draft.date, showsTime: true,
                                        focus: $purposeFocused, recall: { entry in
                            draft.category = entry.category; draft.subcategory = entry.subcategory; draft.subcategoryUserEdited = true; choseCategory = true; categoryIsSuggestion = false
                            if accounts.contains(where: { $0.id == entry.accountID }) { draft.accountID = entry.accountID }
                            purposeFocused = false
                        }) {}
                        if onSave == nil && draft.source != "Apple Pay" {
                            Text(provenance).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            Button {
                                let question = "\(draft.displayTitle)，\(Money.text(draft.amount))，该不该买？"
                                store.sheetSource = nil; store.sheet = .ask(question)
                            } label: {
                                Card(style: .list) {
                                    HStack(spacing: YubaiSpace.space8) {
                                        AssistantMark(size: 16, color: YubaiColor.brandInk)
                                        Text("该不该买 ›").yubaiFont(YubaiFont.row)
                                        Spacer()
                                    }.frame(minHeight: YubaiSize.rowSingle)
                                }
                            }.buttonStyle(PressButtonStyle())
                        }
                        if let merchant = draft.quickCapture?.merchant {
                            HStack(spacing: YubaiSpace.gapGroup) {
                                Text("以后「\(merchant)」都记到 \(Classification.displayCategory(draft.category))").yubaiFont(YubaiFont.caption)
                                Text("·").foregroundStyle(YubaiColor.labelSecondary)
                                Button(remembered ? "已记好" : "好") {
                                    remembered = store.update("记下商户分类") { try QuickCapture.remember(merchant: merchant, category: draft.category, in: &$0) }
                                }.disabled(remembered).foregroundStyle(YubaiColor.brandInk)
                            }
                        }
                        Spacer(minLength: YubaiSpace.gapSection)
                        if onSave == nil { deleteButton }

                    }.finishAmountOnOutsideTap(presented: amountKeypadPresented, finish: finishAmount)
            .task(id: amountKeypadPresented) {
                guard amountKeypadPresented else { return }
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { scroll.scrollTo("editAmount", anchor: .top) }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            EntryKeyboardTray(purpose: $purpose, focus: $purposeFocused) {
                HStack(spacing: 8) {
                    EntryDateChip(date: $draft.date, inTray: true)
                    EntryAccountMenu(accounts: accounts, balances: balances, selection: Binding(get: { draft.accountID }, set: { if let value = $0 { draft.accountID = value } }), inTray: true)
                    Spacer(minLength: 0)
                    if draft.nature != .transfer {
                        EntryRepeatChip(selected: draft.planID != nil || repeatsMonthly, value: repeatValue, opensPlan: draft.planID != nil, inTray: true) {
                            finishAmount(); purposeFocused = false
                            if let id = draft.planID { store.sheetSource = nil; store.sheet = .editPlan(id) }
                            else { repeatsMonthly.toggle() }
                        }
                    }
                }
            } keys: {
                if amountKeypadPresented {
                    AmountKeypad(keypad: $keypad, amountSelected: $amountSelected, canSave: canSave,
                                 primaryTitle: primaryTitle, primaryIdentifier: "saveEditedEntry", save: save, embedded: true)
                }
            }
        }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: amountKeypadPresented)
            .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            .environment(\.yubaiFormSurface, true).paperBackground()
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .entryDiscardGuard(dirty: dirty, amount: currentAmount, confirming: $confirmingDiscard)
            .onAppear { balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) }); openAmount() }
            .onChange(of: purposeFocused) { _, focused in if focused { finishAmount() } else { openAmount() } }
            .onChange(of: draft.category) { _, _ in remembered = false }
            .onChange(of: draft.nature) { _, nature in
                if skipNatureReset { skipNatureReset = false; return }
                draft.otherAccountID = nature == .transfer ? accounts.first { $0.id != draft.accountID }?.id : nil
                let suggestion = EntryHistory.suggestion(purpose: purpose, nature: nature, in: store.current)
                draft.category = suggestion?.category ?? Classification.pendingCategory
                draft.subcategory = suggestion?.subcategory; draft.subcategoryUserEdited = true
                categoryIsSuggestion = suggestion != nil; choseCategory = nature != .transfer
            }

    }
    private var savingHint: EntryHint {
        var ledger = store.current
        ledger.entries.removeAll { $0.id == original.id }
        return EntryHint.make(ledger: ledger, amount: currentAmount, category: draft.category, isFixedBill: draft.planID != nil || draft.rentID != nil || repeatsMonthly,
                              nature: draft.nature, subcategory: draft.subcategory)
    }
    private var previewAfter: Int64? {
        guard store.entriesByID[original.id] != nil else { return nil }
        var entry = draft; entry.amount = currentAmount
        return try? ManualBookkeeping.available(after: entry, in: store.current)
    }
    private var currentAmount: Int64 { amountKeypadPresented ? keypad.amount ?? 0 : (try? Money.parse(amount)) ?? 0 }
    private var dirty: Bool { draft != original || currentAmount != original.amount || purpose != original.displayTitle || repeatsMonthly }
    private func cancel() { if dirty { confirmingDiscard = true } else { dismiss() } }
    private var repeatValue: String {
        if let id = draft.planID, let plan = store.plans.first(where: { $0.id == id }) {
            return plan.frequency == .monthly ? "每月 \(plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)) 号" : plan.frequency.label
        }
        return repeatsMonthly || draft.planID != nil ? "每月 \(Dates.calendar.component(.day, from: draft.date)) 号" : "不重复"
    }
    private func openAmount() {
        guard !amountKeypadPresented else { return }
        purposeFocused = false
        keypad = EntryKeypad(amount: (try? Money.parse(amount)) ?? 0)
        amountSelected = true; amountKeypadPresented = true
    }
    private func finishAmount() {
        guard amountKeypadPresented else { return }
        if let cents = keypad.resolve() { amount = Money.input(cents) }
        amountSelected = false; amountKeypadPresented = false
    }
    private var deleteButton: some View {
        Button("删掉") {
            if store.update("删掉", { ledger in
                guard let index = ledger.entries.firstIndex(where: { $0.id == draft.id }) else { return }
                ledger.entries[index].deletedAt = Date()
            }) { dismiss() }
        }.buttonStyle(DestructiveButtonStyle()).accessibilityIdentifier("deleteEntry")
    }
    private var provenance: String {
        let source = draft.source == "手动" ? "手动记的" : draft.source
        guard let recorded = draft.recordedAt else { return source }
        let c = Dates.calendar; let p = c.dateComponents([.month, .day, .hour, .minute], from: recorded)
        return source + String(format: " · %d月%d日 %02d:%02d", p.month ?? 1, p.day ?? 1, p.hour ?? 0, p.minute ?? 0)
    }
    private func save() {
        finishAmount()
        guard canSave else { return }
        do {
            var edited = draft
            if edited.hasNoCaptureCategory && choseCategory { edited.classificationReason = "手动选择" }
            edited.amount = try Money.parse(amount)
            let clean = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.purpose = clean.isEmpty ? nil : clean
            if clean.isEmpty { edited.title = Classification.displayCategory(edited.category) }
            if let onSave { onSave(edited); dismiss(); return }
            if store.update("改一笔", { ledger in
                // Note is retained source evidence, no longer an editable field.
                // Read the saved value here so an older form cannot overwrite it.
                var updated = edited
                if let original = ledger.entries.first(where: { $0.id == updated.id }) { updated.note = original.note }
                if repeatsMonthly && updated.planID == nil && updated.nature != .transfer {
                    try FixedFlows.repeatMonthly(updated, in: &ledger)
                } else { try ManualBookkeeping.edit(updated, in: &ledger) }
                if choseCategory && !Classification.isPending(updated.category) {
                    try CategoryModel.confirm(.init(category: updated.category, subcategory: updated.subcategory), entryIDs: [updated.id], in: &ledger)
                }
            }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}
