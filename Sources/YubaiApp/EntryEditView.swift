import SwiftUI
import YubaiCore

struct EntryEditView: View {
    @Environment(AppStore.self) private var store
    let entryID: UUID
    var body: some View {
        if let entry = store.current.entries.first(where: { $0.id == entryID && $0.deletedAt == nil }) {
            EntryEditForm(entry: entry).id(entryID)
        } else { EmptyState("doc.questionmark", "记录已不存在", "") }
    }
}

private struct EntryEditForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Entry
    @State private var amount: String
    @State private var purpose: String
    @State private var deleting = false
    @State private var remembered = false
    @State private var choseCategory = false
    @State private var balances: [UUID: Int64] = [:]
    init(entry: Entry) {
        _draft = State(initialValue: entry)
        _amount = State(initialValue: Money.input(entry.amount))
        _purpose = State(initialValue: entry.displayTitle)
    }
    private var standardNature: Bool { [.expense, .income, .transfer].contains(draft.nature) }
    private var accounts: [Account] { store.current.accounts.filter { !$0.archived || $0.id == draft.accountID || $0.id == draft.otherAccountID } }
    private var canSave: Bool {
        guard let cents = try? Money.parse(amount), cents > 0 else { return false }
        return draft.nature != .transfer || (draft.otherAccountID != nil && draft.otherAccountID != draft.accountID)
    }
    var body: some View {
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
                    HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                        Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                        TextField("0", text: $amount).numericInput().yubaiFont(YubaiFont.amountDisplay)
                            .accessibilityLabel("金额").accessibilityIdentifier("editEntryAmount")
                    }.frame(minHeight: YubaiSize.rowDouble)
                    EntryCategoryChips(frequent: ManualBookkeeping.categories(in: store.current, nature: draft.nature, frequentOnly: true),
                                       all: ManualBookkeeping.categories(in: store.current, nature: draft.nature), selection: $draft.category, didSelect: { choseCategory = true }, limit: 4)
                    Card(style: .list) {
                        VStack(spacing: YubaiSpace.none) {
                            EntryFormRow(title: "用途") {
                                TextField("午饭、打车…（可不填）", text: $purpose).multilineTextAlignment(.trailing).accessibilityLabel("用途")
                            }
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
                            if draft.source != "Apple Pay" {
                                EntryFormDivider()
                                EntryFormRow(title: "备注") { TextField("可不填", text: $draft.note).multilineTextAlignment(.trailing).accessibilityLabel("备注") }
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
        }.yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear { balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) }) }
            .onChange(of: draft.category) { _, _ in remembered = false }
            .onChange(of: draft.nature) { _, nature in
                draft.otherAccountID = nature == .transfer ? accounts.first { $0.id != draft.accountID }?.id : nil
                draft.category = ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true).first ?? draft.category
            }
            .confirmationDialog("删除这笔？", isPresented: $deleting, titleVisibility: .visible) {
                Button("删除这笔", role: .destructive) {
                    if store.update("删除这笔", { ledger in
                        guard let index = ledger.entries.firstIndex(where: { $0.id == draft.id }) else { return }
                        ledger.entries[index].deletedAt = Date()
                    }) { dismiss() }
                }.accessibilityIdentifier("confirmDeleteEntry")
                Button("取消", role: .cancel) {}
            }
    }
    private var deleteButton: some View {
        Button("删除这笔") { deleting = true }.yubaiFont(YubaiFont.button).foregroundStyle(YubaiColor.amberInk)
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
        guard canSave else { return }
        do {
            var edited = draft
            if edited.hasNoCaptureCategory && choseCategory { edited.classificationReason = "手动选择" }
            edited.amount = try Money.parse(amount)
            let clean = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.purpose = clean.isEmpty ? nil : clean
            if clean.isEmpty { edited.title = edited.category }
            if store.update("改一笔", { try ManualBookkeeping.edit(edited, in: &$0) }) { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}
