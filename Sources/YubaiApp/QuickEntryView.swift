import SwiftUI
import YubaiCore

struct QuickEntryView: View {
    var prefill: QuickEntryPrefill? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keypad = EntryKeypad()
    @State private var nature = Nature.expense
    @State private var category = "餐饮"
    @State private var purpose = ""
    @State private var accountID: UUID?
    @State private var otherAccountID: UUID?
    @State private var showingTransferAccountEditor = false
    @State private var accountIDsBeforeAdding: Set<UUID> = []
    @State private var transferAccountHighlighted = false
    @State private var date = Date()
    @State private var loaded = false
    @State private var balances: [UUID: Int64] = [:]
    @State private var suggestion: Occurrence?
    @State private var selectedMatchID: String?
    @State private var repeatsMonthly = false
    @State private var previewAvailable: Int64 = 0
    @FocusState private var purposeFocused: Bool
    private var accounts: [Account] { store.accounts.filter { !$0.archived } }
    private var transferAccounts: [Account] { accounts.filter { $0.id != accountID } }
    private var canSave: Bool { keypad.canSave && accountID != nil && (nature != .transfer || (otherAccountID != nil && otherAccountID != accountID)) }
    var body: some View {
        let available = previewAvailable
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                ManualSheetHeader(title: "记一笔", actionTitle: "导入", actionImage: "photo", primary: false,
                                  cancel: { dismiss() }, action: { store.sheetSource = nil; store.sheet = prefill?.screenshot.map(AppSheet.screenshotReview) ?? .imports })
                if accounts.isEmpty {
                    EmptyAccountState { store.sheet = .account(nil) }
                } else {
                    Segmented(choices: [(Nature.expense, "支出"), (.income, "收入"), (.transfer, "转账")], selection: $nature)
                    amountDisplay
                    if nature != .transfer {
                        EntryCategoryChips(frequent: ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true),
                                           all: ManualBookkeeping.categories(in: store.current, nature: nature), selection: $category,
                                           didSelect: { purposeFocused = false })
                            .simultaneousGesture(TapGesture().onEnded { purposeFocused = false })
                    }
                    form
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("记下后，还能花").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                        Spacer()
                        AmountLabel(cents: available, hide: store.preferences.hideAmounts, currency: true)
                            .accessibilityIdentifier("afterEntryAvailable")
                    }
                    if let suggestion { matchChip(suggestion) }
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.gapGroup)
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("entryFormScroll")
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
                if !accounts.isEmpty && !purposeFocused {
                    AmountKeypad(keypad: $keypad, canSave: canSave,
                                 primaryTitle: canSave ? "记下 \(keypad.resultText) 元" : "记下", primaryIdentifier: "saveQuickEntry",
                                 save: { save(again: false) }, saveAnother: { save(again: true) })
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: purposeFocused)
            .yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            .environment(\.yubaiFormSurface, true).paperBackground().yubaiSheetBackground()
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showingTransferAccountEditor, onDismiss: selectAddedTransferAccount) {
                NavigationStack { AccountEditor(account: nil) }
                    .environment(store).tint(YubaiColor.brandInk).appErrors()
                    .presentationDragIndicator(.visible).yubaiSheetBackground().frame(minWidth: 340, minHeight: 520)
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id
                category = ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true).first ?? category
                if let prefill {
                    if let selected = prefill.category { category = selected }
                    purpose = prefill.purpose ?? ""
                    if let amount = prefill.amount { keypad.reset(); Money.input(amount).forEach { keypad.press(String($0)) } }
                }
                previewAvailable = store.funds.available
                refreshBalances()
            }
            .onChange(of: store.current.updatedAt) { _, _ in refreshBalances() }
            .task(id: previewInput) { await refreshPreview() }
            .onChange(of: nature) { _, value in
                category = ManualBookkeeping.categories(in: store.current, nature: value, frequentOnly: true).first ?? (value.inflow ? "其他收入" : "其他支出")
                if value == .transfer { otherAccountID = accounts.first { $0.id != accountID }?.id }
            }
            .onChange(of: accountID) { _, id in
                if nature == .transfer && id == otherAccountID { otherAccountID = accounts.first { $0.id != id }?.id }
            }
    }
    private func matchChip(_ match: Occurrence) -> some View {
        let selected = selectedMatchID == match.id
        return Button { purposeFocused = false; selectedMatchID = selected ? nil : match.id; if !selected { repeatsMonthly = false } } label: {
            HStack(spacing: YubaiSpace.space8) {
                if selected { Image(systemName: "checkmark") }
                Text((selected ? "已选 · " + match.title + "这期" : "是" + match.title + "这期吗") + " · " + FixedFlowPresentation.monthDay(match.date))
            }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.amberStrong)
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8).background(YubaiColor.amberTint, in: Capsule())
                .overlay { if selected { Capsule().strokeBorder(YubaiColor.amberDot, lineWidth: 1) } }
                .frame(minHeight: YubaiSize.tapMin)
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("fixedFlowSuggestion")
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityHint(selected ? "再点取消关联" : "关联这期账单")
    }
    private var selectedLink: (planID: UUID, occurrence: Date)? {
        guard let suggestion, suggestion.id == selectedMatchID, let id = suggestion.planID else { return nil }
        return (id, suggestion.date)
    }
    private struct PreviewInput: Equatable {
        var expression: String; var nature: Nature; var purpose: String; var category: String
        var date: Date; var accountID: UUID?; var otherAccountID: UUID?
        var selectedMatchID: String?; var repeatsMonthly: Bool; var ledgerUpdatedAt: Date
    }
    private var previewInput: PreviewInput {
        PreviewInput(expression: keypad.expression, nature: nature, purpose: purpose, category: category, date: date,
                     accountID: accountID, otherAccountID: otherAccountID, selectedMatchID: selectedMatchID,
                     repeatsMonthly: repeatsMonthly, ledgerUpdatedAt: store.current.updatedAt)
    }
    @MainActor private func refreshPreview() async {
        // No ledger work runs in body or the key action. Cancellation coalesces
        // quick input; the expensive unchanged Core calculations run off-main.
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        guard !Task.isCancelled else { return }
        let ledger = store.current; let now = Date(); let fallback = store.funds.available
        let amount = keypad.amount ?? 0; let nature = self.nature; let purpose = self.purpose; let day = date; let account = accountID
        let change = canSave ? (try? draftChange(now: now)) : nil
        let result = await Task.detached(priority: .userInitiated) {
            let match = FixedFlows.suggestions(amount: amount, nature: nature, purpose: purpose, day: day, accountID: account, in: ledger).first
            let available = change.flatMap { try? ManualBookkeeping.available(after: $0, in: ledger, now: now) } ?? fallback
            return (match, available)
        }.value
        guard !Task.isCancelled else { return }
        if result.0?.id != suggestion?.id { selectedMatchID = nil }
        suggestion = result.0; previewAvailable = result.1
    }
    private var amountDisplay: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.none) {
            Text(keypad.expressionText ?? "").yubaiFont(YubaiFont.amount, weight: .regular).foregroundStyle(YubaiColor.labelSecondary)
                .lineLimit(1).minimumScaleFactor(0.5).frame(height: YubaiFont.amount.lineHeight)
                .accessibilityIdentifier("entryKeypadExpression").accessibilityHidden(keypad.expressionText == nil)
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
                Text(keypad.displayText.replacingOccurrences(of: "-", with: "−")).yubaiFont(YubaiFont.amountDisplay)
                    .numberTransition(value: Double(keypad.amount ?? 0) / 100)
                    .lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("entryKeypadAmount")
                Rectangle().fill(YubaiColor.brand).frame(width: 2, height: YubaiSize.rowIcon).accessibilityHidden(true)
                Spacer(minLength: YubaiSpace.none)
            }.frame(minHeight: YubaiSize.rowDouble)
        }.contentShape(Rectangle()).onTapGesture { purposeFocused = false }
    }
    private var form: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                EntryFormRow(title: "用途") {
                    TextField("", text: $purpose, prompt: Text("可不填").foregroundStyle(YubaiColor.labelSecondary)).multilineTextAlignment(.trailing)
                        .focused($purposeFocused).accessibilityIdentifier("entryPurpose").accessibilityLabel("用途")
                        .submitLabel(.done).onSubmit { purposeFocused = false }
                }
                RecentPurposeChips(selection: $purpose)
                EntryFormDivider()
                EntryFormRow(title: nature == .transfer ? "转出" : "账户") {
                    EntryAccountMenu(accounts: accounts, balances: balances, selection: $accountID, showsBalance: true)
                        .accessibilityLabel(nature == .transfer ? "转出" : "账户")
                        .simultaneousGesture(TapGesture().onEnded { purposeFocused = false })
                }
                if nature == .transfer {
                    EntryFormDivider()
                    EntryFormRow(title: "转入") {
                        if transferAccounts.isEmpty {
                            addTransferAccountChip
                        } else {
                            EntryAccountMenu(accounts: transferAccounts, balances: balances, selection: $otherAccountID, showsBalance: true)
                                .accessibilityLabel("转入").accessibilityIdentifier("transferDestinationAccount")
                                .simultaneousGesture(TapGesture().onEnded { purposeFocused = false })
                        }
                    }
                    .background {
                        YubaiColor.brandTint.opacity(transferAccountHighlighted ? 1 : 0)
                            .padding(.horizontal, -YubaiSpace.insetCard)
                    }
                    .task(id: otherAccountID) {
                        guard transferAccountHighlighted, let otherAccountID,
                              YubaiMotion.claim("new-row-transfer-" + otherAccountID.uuidString) else { return }
                        withAnimation(YubaiMotion.wash(reduceMotion: reduceMotion)) { transferAccountHighlighted = false }
                    }
                }
                EntryFormDivider()
                EntryFormRow(title: "日期") {
                    EntryDateChip(date: $date).simultaneousGesture(TapGesture().onEnded { purposeFocused = false })
                }
                if nature != .transfer && selectedLink == nil {
                    EntryFormDivider()
                    EntryFormRow(title: "重复") {
                        EntryRepeatChip(selected: repeatsMonthly, value: repeatsMonthly ? "每月 \(Dates.calendar.component(.day, from: date)) 号" : "不重复") {
                            purposeFocused = false; repeatsMonthly.toggle()
                        }
                    }
                }
            }
        }
    }
    private var addTransferAccountChip: some View {
        Button {
            purposeFocused = false
            accountIDsBeforeAdding = Set(store.accounts.map(\.id))
            showingTransferAccountEditor = true
        } label: {
            HStack(spacing: YubaiSpace.space4) {
                Image(systemName: "plus")
                Text("添加账户")
            }.yubaiFont(YubaiFont.callout, weight: .medium).foregroundStyle(YubaiColor.brandInk)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                .background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("transferAddAccount").accessibilityLabel("添加账户")
    }
    private func selectAddedTransferAccount() {
        defer { accountIDsBeforeAdding.removeAll() }
        guard let added = transferAccounts.first(where: { !accountIDsBeforeAdding.contains($0.id) }) else { return }
        otherAccountID = added.id
        transferAccountHighlighted = true
    }
    private func draftChange(now: Date) throws -> ChangeSet {
        guard let accountID, let amount = keypad.amount else { throw YubaiError.invalid("请选择账户并填写金额。") }
        if repeatsMonthly && nature != .transfer && selectedLink == nil {
            return try FixedFlows.monthlyEntryChange(amount: amount, nature: nature, accountID: accountID, day: date,
                                                      purpose: purpose, category: category, now: now)
        }
        return try ManualBookkeeping.change(amount: amount, nature: nature, accountID: accountID, otherAccountID: otherAccountID,
                                             day: date, purpose: purpose, category: category, link: selectedLink, now: now)
    }
    private func refreshBalances() {
        balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) })
    }
    private func save(again: Bool) {
        guard canSave else { return }
        _ = keypad.resolve(); purposeFocused = false
        // Saving may beat the debounce. Revalidate the user's selected match
        // against the final input before constructing its linked payment.
        let match = FixedFlows.suggestions(amount: keypad.amount ?? 0, nature: nature, purpose: purpose, day: date,
                                           accountID: accountID, in: store.current).first
        if match?.id != suggestion?.id { selectedMatchID = nil }
        suggestion = match
        do {
            let change = try draftChange(now: Date())
            guard store.apply(change, label: "记一笔") else { return }
            let title = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            let sign: AmountLabel.Sign = nature.inflow ? .inflow : .outflow
            let amount = store.preferences.hideAmounts ? "••••" : AmountLabel.text(keypad.amount ?? 0, sign: sign)
            if again {
                // Continuous entry keeps the sheet open, so the root's deferred
                // sheet-dismissal success must be delivered here exactly once.
                store.cancelEntrySaveMotion(); store.entrySaveTrigger &+= 1
            }
            let repeatSuffix = repeatsMonthly && nature != .transfer && selectedLink == nil ? " · 每月 \(Dates.calendar.component(.day, from: date)) 号" : ""
            store.setEntrySaveToast("已记下 · " + (title.isEmpty ? category : title) + " " + amount + " · " + store.accountName(accountID) + repeatSuffix)
            if again {
                keypad.reset(); purpose = ""; selectedMatchID = nil; repeatsMonthly = false
                category = ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true).first ?? category
            } else { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}
