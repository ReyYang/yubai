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

private struct EntryEditForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Entry
    @State private var amount: String
    @State private var purpose: String
    @State private var remembered = false
    @State private var choseCategory = false
    @State private var balances: [UUID: Int64] = [:]
    @State private var keypad = EntryKeypad()
    @State private var amountKeypadPresented = false
    @State private var amountSelected = false
    @State private var repeatsMonthly = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var purposeFocused: Bool
    init(entry: Entry) {
        _draft = State(initialValue: entry)
        _amount = State(initialValue: Money.input(entry.amount))
        _purpose = State(initialValue: entry.displayTitle)
    }
    private var standardNature: Bool { [.expense, .income, .transfer].contains(draft.nature) }
    private var accounts: [Account] { store.accounts.filter { !$0.archived || $0.id == draft.accountID || $0.id == draft.otherAccountID } }
    private var canSave: Bool {
        guard let cents = amountKeypadPresented ? keypad.amount : (try? Money.parse(amount)), cents > 0 else { return false }
        return draft.nature != .transfer || (draft.otherAccountID != nil && draft.otherAccountID != draft.accountID)
    }
    var body: some View {
        ScrollViewReader { scroll in
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        ManualSheetHeader(title: "改一笔", showsAction: draft.source != "Apple Pay", enabled: canSave, cancel: { dismiss() }, action: save)
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
                        if draft.nature != .transfer {
                            EntryCategoryChips(frequent: ManualBookkeeping.categories(in: store.current, nature: draft.nature, frequentOnly: true),
                                               income: draft.nature != .refund && draft.nature.inflow,
                                               selection: .init(category: draft.category, subcategory: draft.subcategory),
                                               suggest: { ManualBookkeeping.guessCategory(purpose, nature: draft.nature, in: store.current) }) { choice in
                                draft.category = choice.category; draft.subcategory = choice.subcategory
                                draft.subcategoryUserEdited = true; choseCategory = true; remembered = false; purposeFocused = false
                            }
                        }
                        Card(style: .list) {
                            VStack(spacing: YubaiSpace.none) {
                                EntryFormRow(title: "用途") {
                                    TextField("", text: $purpose).multilineTextAlignment(.trailing).focused($purposeFocused).accessibilityLabel("用途")
                                }
                                RecentPurposeChips(selection: $purpose)
                                EntryFormDivider()
                                EntryFormRow(title: "账户") {
                                    EntryAccountMenu(accounts: accounts, balances: balances,
                                                     selection: Binding(get: { draft.accountID }, set: { if let id = $0 { draft.accountID = id } }))
                                }
                                if draft.nature == .transfer {
                                    EntryFormDivider()
                                    EntryFormRow(title: "转入") {
                                        EntryAccountMenu(accounts: accounts.filter { $0.id != draft.accountID }, balances: balances, selection: $draft.otherAccountID)
                                    }
                                }
                                EntryFormDivider()
                                EntryFormRow(title: "时间") { HStack(spacing: YubaiSpace.space8) { EntryDateChip(date: $draft.date); EntryDateChip(date: $draft.date, time: true) } }
                                if draft.nature != .transfer {
                                    EntryFormDivider()
                                    EntryFormRow(title: "重复") {
                                        EntryRepeatChip(selected: draft.planID != nil || repeatsMonthly, value: repeatValue, opensPlan: draft.planID != nil) {
                                            finishAmount(); purposeFocused = false
                                            if let id = draft.planID { store.sheetSource = nil; store.sheet = .editPlan(id) }
                                            else { repeatsMonthly.toggle() }
                                        }
                                    }
                                }
                            }
                        }
                        if draft.source != "Apple Pay" {
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
                        if draft.source == "Apple Pay" {
                            HStack(spacing: YubaiSpace.space8) {
                                deleteButton.frame(maxWidth: .infinity)
                                Button("好了", action: save).buttonStyle(PrimaryButtonStyle()).disabled(!canSave).frame(maxWidth: .infinity)
                            }
                        } else { deleteButton }

                    }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup).padding(.bottom, YubaiSpace.gapSection)
                        .frame(minHeight: geometry.size.height, alignment: .top).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                    .finishAmountOnOutsideTap(presented: amountKeypadPresented, finish: finishAmount)
            }
            .task(id: amountKeypadPresented) {
                guard amountKeypadPresented else { return }
                do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
                withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { scroll.scrollTo("editAmount", anchor: .top) }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            if amountKeypadPresented {
                AmountKeypad(keypad: $keypad, amountSelected: $amountSelected, canSave: keypad.canSave,
                             primaryTitle: "好", primaryIdentifier: "amountKeypadDone", save: finishAmount)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }.animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: amountKeypadPresented)
            .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            .environment(\.yubaiFormSurface, true).paperBackground()
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear { balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) }) }
            .onChange(of: purposeFocused) { _, focused in if focused { finishAmount() } }
            .onChange(of: draft.category) { _, _ in remembered = false }
            .onChange(of: draft.nature) { _, nature in
                draft.otherAccountID = nature == .transfer ? accounts.first { $0.id != draft.accountID }?.id : nil
                draft.category = ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true).first ?? draft.category
                draft.subcategory = nil; draft.subcategoryUserEdited = true; choseCategory = nature != .transfer
            }

    }
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
        Button("删除这笔") {
            if store.update("删除这笔", { ledger in
                guard let index = ledger.entries.firstIndex(where: { $0.id == draft.id }) else { return }
                ledger.entries[index].deletedAt = Date()
            }) { dismiss() }
        }.yubaiFont(YubaiFont.button).foregroundStyle(YubaiColor.amberInk)
            .frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight).background(YubaiColor.card, in: Capsule())
            .buttonStyle(PressButtonStyle()).accessibilityIdentifier("deleteEntry")
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
            if clean.isEmpty { edited.title = edited.category }
            if store.update("改一笔", { ledger in
                // Note is retained source evidence, no longer an editable field.
                // Read the saved value here so an older form cannot overwrite it.
                var updated = edited
                if let original = ledger.entries.first(where: { $0.id == updated.id }) { updated.note = original.note }
                if repeatsMonthly && updated.planID == nil && updated.nature != .transfer {
                    try FixedFlows.repeatMonthly(updated, in: &ledger)
                } else { try ManualBookkeeping.edit(updated, in: &ledger) }
                if choseCategory {
                    try CategoryModel.confirm(.init(category: updated.category, subcategory: updated.subcategory), entryIDs: [updated.id], in: &ledger)
                }
            }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}
