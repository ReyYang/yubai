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
    @State private var previewAvailable: Int64?
    @State private var projectedFixedSavings: Int64?
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
                    EntryForm(title: formTitle, actionTitle: primaryTitle, showsAction: !amountKeypadPresented, enabled: canSave,
                                  actionIdentifier: onSave == nil ? "saveManualSheet" : "saveDraftEdit", cancel: cancel, save: save) {
                        if draft.source == "Apple Pay" {
                            Pill(text: "来自 Apple Pay · " + (draft.quickCapture?.card ?? "") + " · " + (draft.quickCapture?.transactionDate ?? draft.date).formatted(.dateTime.hour().minute()), variant: .neutral, height: YubaiSize.smallBadge, showsDot: false)
                        }
                        if standardNature && draft.source != "Apple Pay" {
                            Segmented(choices: [(Nature.expense, "支出"), (.income, "收入"), (.transfer, "转账")], selection: $draft.nature,
                                          identifier: { "entryNature_" + $0.rawValue })
                        } else if !standardNature {
                            Text(draft.nature.entryLabel).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin)
                        }
                        EditableAmountDisplay(amount: amount, keypad: keypad, presented: amountKeypadPresented,
                                              selected: amountSelected, identifier: "editEntryAmount", open: openAmount)
                            .id("editAmount")
                        InlineFieldError(message: currentAmount <= 0 ? "金额须大于 0.00 元" : nil)
                        if draft.nature != .transfer { resultBar }
                        if draft.nature != .transfer {
                            EntryCategoryChips(frequent: ManualBookkeeping.categories(in: store.current, nature: draft.nature, frequentOnly: true),
                                               income: draft.nature != .refund && draft.nature.inflow,
                                               selection: .init(category: draft.category, subcategory: draft.subcategory), suggestionOnly: categoryIsSuggestion, allowsDirectionChange: standardNature && draft.planID == nil && draft.source != "Apple Pay",
                                               directionChanged: { income in
                                                   if income != draft.nature.categoryIncome { skipNatureReset = true; draft.nature = income ? .income : .expense }
                                               }, suggest: { categoryIsSuggestion ? draft.category : nil }) { choice in
                                draft.category = choice.category; draft.subcategory = choice.subcategory
                                draft.subcategoryUserEdited = true; choseCategory = true; categoryIsSuggestion = false; remembered = false; purposeFocused = false
                            }
                        }
                        if onSave == nil && draft.source != "Apple Pay" {
                            provenanceRow
                            askRow
                        }
                        EntryFormFields(purpose: $purpose, purposeError: purpose.count > 4000 ? "用途最多 4,000 字" : nil, nature: draft.nature, accounts: accounts, balances: balances,
                                        accountID: Binding(get: { draft.accountID }, set: { if let id = $0 { draft.accountID = id } }),
                                        otherAccountID: $draft.otherAccountID, date: $draft.date, showsTime: true, showsRecent: false,
                                        focus: $purposeFocused, recall: { entry in
                            draft.category = entry.category; draft.subcategory = entry.subcategory; draft.subcategoryUserEdited = true; choseCategory = true; categoryIsSuggestion = false
                            if accounts.contains(where: { $0.id == entry.accountID }) { draft.accountID = entry.accountID }
                            purposeFocused = false
                        }) {}
                        if let merchant = draft.quickCapture?.merchant {
                            HStack(spacing: YubaiSpace.gapGroup) {
                                Text("以后「\(merchant)」都记到 \(Classification.displayCategory(draft.category))").yubaiFont(YubaiFont.caption)
                                Text("·").foregroundStyle(YubaiColor.labelSecondary)
                                Button(remembered ? "已记好" : "好") {
                                    remembered = store.update("记下商户分类") { try QuickCapture.remember(merchant: merchant, category: draft.category, income: draft.nature.categoryIncome, in: &$0) }
                                }.disabled(remembered).foregroundStyle(YubaiColor.brandInk)
                            }
                        }
                    }.finishAmountOnOutsideTap(presented: amountKeypadPresented, finish: finishAmount)
            .task(id: amountKeypadPresented) {
                guard amountKeypadPresented else { return }
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { scroll.scrollTo("editAmount", anchor: .top) }
            }
        }.safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
            EntryKeyboardTray(purpose: $purpose, focus: $purposeFocused) {
                ChipFlow {
                    EntryDateChip(date: $draft.date, inTray: true, allowsFuture: true, identifier: "editEntryDate")
                    EntryAccountMenu(accounts: accounts, balances: balances, selection: Binding(get: { draft.accountID }, set: { if let value = $0 { draft.accountID = value } }), inTray: true)
                    if draft.nature == .income { EntryFixedSavingsChip(selected: $draft.intoFixedSavings, action: { finishAmount(); purposeFocused = false }) }
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
            .task(id: previewInput) { await refreshPreview() }
            .onChange(of: purposeFocused) { _, focused in if focused { finishAmount() } else { openAmount() } }
            .onChange(of: draft.category) { _, _ in remembered = false; draft.partID = nil }
            .onChange(of: draft.nature) { _, nature in
                if nature != .income { draft.intoFixedSavings = false }
                if skipNatureReset { skipNatureReset = false; return }
                draft.otherAccountID = nature == .transfer ? accounts.first { $0.id != draft.accountID }?.id : nil
                let suggestion = EntryHistory.suggestion(purpose: purpose, nature: nature, in: store.current)
                draft.category = suggestion?.category ?? Classification.pendingCategory
                draft.subcategory = suggestion?.subcategory; draft.subcategoryUserEdited = true
                categoryIsSuggestion = suggestion != nil; choseCategory = false
            }

    }
    @ViewBuilder private var resultBar: some View {
        let hide = store.preferences.hideAmounts
        if let totals = fixedSavingsTotals {
            ResultBar(label: "存着不动", value: ResultBar.change(totals.current, totals.new, hide: hide), identifier: "entrySavingHint")
        } else {
            let value = previewAvailable ?? store.funds.available
            ResultBar(label: "改完还能花", value: amount2(value, hide: hide), amber: value < 0, identifier: "entrySavingHint")
        }
    }
    /// 记录信息一行，「删掉」在右边，看得见，离确认远。
    private var provenanceRow: some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(provenance).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            Spacer(minLength: YubaiSpace.space8)
            Button(action: deleteEntry) {
                Text("删掉").yubaiFont(YubaiFont.callout, weight: .medium).foregroundStyle(YubaiColor.amberInk)
                    .padding(.horizontal, YubaiSpace.space8).yubaiHitTarget(alignment: .trailing)
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("deleteEntry")
        }.frame(minHeight: YubaiSize.tapMin)
    }
    private var askRow: some View {
        Button {
            let question = "\(draft.displayTitle)，\(Money.text(draft.amount))，该不该买？"
            store.sheetSource = nil; store.sheet = .ask(question)
        } label: {
            Card(style: .list) {
                HStack(spacing: YubaiSpace.space8) {
                    AssistantMark(size: YubaiFont.navTitle.size, color: YubaiColor.brandInk)
                    Text("该不该买").yubaiFont(YubaiFont.row)
                    Spacer()
                    Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
                }.frame(minHeight: YubaiSize.rowSingle)
            }
        }.buttonStyle(PressButtonStyle())
    }
    private var fixedSavingsTotals: (current: Int64, new: Int64)? {
        guard draft.nature == .income, draft.intoFixedSavings, let projectedFixedSavings else { return nil }
        return (store.funds.fixedSavingsTotal, projectedFixedSavings)
    }
    private struct PreviewInput: Equatable {
        var revision: UInt64
        var entry: Entry
        var amount: Int64
        var purpose: String
        var moment: Date
    }
    private var previewInput: PreviewInput {
        PreviewInput(revision: store.ledgerRevision, entry: draft, amount: currentAmount, purpose: purpose, moment: store.financialNow)
    }
    @MainActor private func refreshPreview() async {
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        let ledger = store.current; let now = Date()
        var entry = draft; entry.amount = currentAmount
        if Dates.day(entry.date) > Dates.day(now) { entry.date = Dates.day(entry.date) }
        let edited = entry
        let value = await Task.detached(priority: .userInitiated) {
            let available = try? ManualBookkeeping.available(after: edited, in: ledger, now: now)
            var projected = ledger
            let saved = (try? ManualBookkeeping.edit(edited, in: &projected, now: now)) != nil
            let fixed: Int64? = saved ? Finance.funds(projected, now: now).fixedSavingsTotal : nil
            return (available, fixed)
        }.value
        guard !Task.isCancelled else { return }
        previewAvailable = value.0; projectedFixedSavings = value.1
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
    private func deleteEntry() {
        if store.update("删掉", { ledger in
            guard let index = ledger.entries.firstIndex(where: { $0.id == draft.id }) else { return }
            ledger.entries[index].deletedAt = Date()
        }) { dismiss() }
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
            let now = Date()
            if Dates.day(edited.date) > Dates.day(now) { edited.date = Dates.day(edited.date) }
            if categoryIsSuggestion && !choseCategory { edited.category = Classification.pendingCategory; edited.subcategory = nil }
            if edited.hasNoCaptureCategory && choseCategory { edited.classificationReason = "手动选择" }
            edited.amount = try Money.parse(amount)
            let clean = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.purpose = clean.isEmpty ? nil : clean
            if clean.isEmpty { edited.title = Classification.displayCategory(edited.category) }
            if let onSave { onSave(edited); dismiss(); return }
            let justPosted = original.date > now && edited.date <= now
            if store.update("改一笔", { ledger in
                // Note is retained source evidence, no longer an editable field.
                // Read the saved value here so an older form cannot overwrite it.
                var updated = edited
                if let original = ledger.entries.first(where: { $0.id == updated.id }) { updated.note = original.note }
                if repeatsMonthly && updated.planID == nil && updated.nature != .transfer {
                    try FixedFlows.repeatMonthly(updated, in: &ledger)
                } else { try ManualBookkeeping.edit(updated, in: &ledger, now: now) }
                if choseCategory && !Classification.isPending(updated.category) {
                    try CategoryModel.confirm(.init(category: updated.category, subcategory: updated.subcategory), entryIDs: [updated.id], in: &ledger)
                }
                if justPosted { FixedFlows.autoLink(&ledger, addedEntryIDs: [updated.id], now: now) }
            }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}
