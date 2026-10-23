import SwiftUI
import YubaiCore

struct QuickEntryView: View {
    var prefill: QuickEntryPrefill? = nil
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var keypad = EntryKeypad()
    @State private var nature = Nature.expense
    @State private var category = "餐饮"
    @State private var purpose = ""
    @State private var accountID: UUID?
    @State private var otherAccountID: UUID?
    @State private var date = Date()
    @State private var userChoseCategory = false
    @State private var loaded = false
    @State private var balances: [UUID: Int64] = [:]
    @State private var suggestion: Occurrence?
    @State private var selectedMatchID: String?
    @FocusState private var purposeFocused: Bool
    private var accounts: [Account] { store.current.accounts.filter { !$0.archived } }
    private var canSave: Bool { keypad.canSave && accountID != nil && (nature != .transfer || (otherAccountID != nil && otherAccountID != accountID)) }
    var body: some View {
        let available = previewAvailable
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    ManualSheetHeader(title: "记一笔", actionTitle: "导入", actionImage: "photo", primary: false,
                                      cancel: { dismiss() }, action: { store.sheetSource = nil; store.sheet = prefill?.screenshot.map(AppSheet.screenshotReview) ?? .imports })
                    if accounts.isEmpty {
                        EmptyAccountState { store.sheet = .account(nil) }
                        Spacer(minLength: YubaiSpace.none)
                    } else {
                        Segmented(choices: [(Nature.expense, "支出"), (.income, "收入"), (.transfer, "转账")], selection: $nature)
                        amountDisplay
                        EntryCategoryChips(frequent: ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true),
                                           all: ManualBookkeeping.categories(in: store.current, nature: nature), selection: $category,
                                           didSelect: { userChoseCategory = true })
                        form
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text("记下后，还能花").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            Spacer()
                            AmountLabel(cents: available, hide: store.current.preferences.hideAmounts, currency: true, fractionDigits: available % 100 == 0 ? 0 : 2)
                                .accessibilityIdentifier("afterEntryAvailable")
                        }
                        Spacer(minLength: YubaiSpace.gapGroup)
                        if let suggestion { matchChip(suggestion) }
                        EntryKeypadView(keypad: $keypad, canSave: canSave, save: { save(again: false) }, onKey: { purposeFocused = false })
                        Button("记下，再记一笔") { save(again: true) }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
                            .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle()).disabled(!canSave)
                            .accessibilityIdentifier("saveAndAddAnother")
                    }
                }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup).padding(.bottom, YubaiSpace.gapSection)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }.yubaiFont(YubaiFont.body).foregroundStyle(YubaiColor.label)
            #if os(iOS)
            .presentationDetents([.large])
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onAppear {
                guard !loaded else { return }; loaded = true
                accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id
                category = ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true).first ?? category
                if let prefill {
                    if let selected = prefill.category { category = selected; userChoseCategory = true }
                    purpose = prefill.purpose ?? ""
                    if let amount = prefill.amount { keypad.reset(); Money.input(amount).forEach { keypad.press(String($0)) } }
                }
                refreshBalances(); refreshSuggestions()
            }
            .onChange(of: store.current.updatedAt) { _, _ in refreshBalances(); refreshSuggestions() }
            .onChange(of: keypad.amount) { _, _ in refreshSuggestions() }
            .onChange(of: date) { _, _ in refreshSuggestions() }
            .onChange(of: nature) { _, value in
                userChoseCategory = false
                category = ManualBookkeeping.guessCategory(purpose, nature: value, in: store.current) ?? ManualBookkeeping.categories(in: store.current, nature: value, frequentOnly: true).first ?? "其他支出"
                if value == .transfer { otherAccountID = accounts.first { $0.id != accountID }?.id }
                refreshSuggestions()
            }
            .onChange(of: accountID) { _, id in
                if nature == .transfer && id == otherAccountID { otherAccountID = accounts.first { $0.id != id }?.id }
                refreshSuggestions()
            }
            .onChange(of: purpose) { _, value in
                refreshSuggestions()
                guard !userChoseCategory else { return }
                category = ManualBookkeeping.guessCategory(value, nature: nature, in: store.current) ?? ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true).first ?? category
            }
    }
    private func matchChip(_ match: Occurrence) -> some View {
        let selected = selectedMatchID == match.id
        return Button { purposeFocused = false; selectedMatchID = selected ? nil : match.id } label: {
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
    private func refreshSuggestions() {
        let first = FixedFlows.suggestions(amount: keypad.amount ?? 0, nature: nature, purpose: purpose, day: date,
                                           accountID: accountID, in: store.current).first
        if first?.id != suggestion?.id { selectedMatchID = nil }
        suggestion = first
    }
    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text("¥").yubaiFont(YubaiFont.amountAccount).foregroundStyle(YubaiColor.labelSecondary)
            Text(keypad.displayText.replacingOccurrences(of: "-", with: "−")).yubaiFont(YubaiFont.amountDisplay)
                .numberTransition(value: Double(keypad.amount ?? 0) / 100)
                .lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("entryKeypadAmount")
            Rectangle().fill(YubaiColor.brand).frame(width: 2, height: YubaiSize.rowIcon).accessibilityHidden(true)
            Spacer(minLength: YubaiSpace.none)
        }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle()).onTapGesture { purposeFocused = false }
    }
    private var form: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                EntryFormRow(title: "用途") {
                    TextField("", text: $purpose).multilineTextAlignment(.trailing)
                        .focused($purposeFocused).accessibilityIdentifier("entryPurpose").accessibilityLabel("用途")
                }
                RecentPurposeChips(selection: $purpose)
                EntryFormDivider()
                EntryFormRow(title: "账户") { EntryAccountMenu(accounts: accounts, balances: balances, selection: $accountID, showsBalance: true) }
                if nature == .transfer {
                    EntryFormDivider()
                    EntryFormRow(title: "转入") { EntryAccountMenu(accounts: accounts.filter { $0.id != accountID }, balances: balances, selection: $otherAccountID, showsBalance: true) }
                }
                EntryFormDivider()
                EntryFormRow(title: "日期") { EntryDateChip(date: $date) }
            }
        }
    }
    private func draftChange(now: Date) throws -> ChangeSet {
        guard let accountID, let amount = keypad.amount else { throw YubaiError.invalid("请选择账户并填写金额。") }
        return try ManualBookkeeping.change(amount: amount, nature: nature, accountID: accountID, otherAccountID: otherAccountID,
                                             day: date, purpose: purpose, category: category, link: selectedLink, now: now)
    }
    private var previewAvailable: Int64 {
        let now = Date()
        guard canSave, let change = try? draftChange(now: now), let available = try? ManualBookkeeping.available(after: change, in: store.current, now: now) else { return store.funds.available }
        return available
    }
    private func refreshBalances() {
        balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Finance.balance($0, in: store.current)) })
    }
    private func save(again: Bool) {
        guard canSave else { return }
        _ = keypad.resolve(); purposeFocused = false
        do {
            let change = try draftChange(now: Date())
            guard store.apply(change, label: "记一笔") else { return }
            let title = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            let sign: AmountLabel.Sign = nature.inflow ? .inflow : .outflow
            let amount = store.current.preferences.hideAmounts ? "••••" : AmountLabel.text(keypad.amount ?? 0, sign: sign, decimals: 2)
            store.setEntrySaveToast("已记下 · " + (title.isEmpty ? category : title) + " " + amount + " · " + store.current.accountName(accountID))
            if again {
                keypad.reset(); purpose = ""; userChoseCategory = false; selectedMatchID = nil
                category = ManualBookkeeping.categories(in: store.current, nature: nature, frequentOnly: true).first ?? category
            } else { dismiss() }
        } catch { store.error = error.localizedDescription }
    }
}

private struct EntryKeypadView: View {
    @Binding var keypad: EntryKeypad
    let canSave: Bool
    let save: () -> Void
    let onKey: () -> Void
    private let rows = [["1", "2", "3", "⌫"], ["4", "5", "6", "+"], ["7", "8", "9", "−"]]
    var body: some View {
        Grid(horizontalSpacing: YubaiSpace.space8, verticalSpacing: YubaiSpace.space8) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow { ForEach(rows[row], id: \.self) { key in keyButton(key) } }
            }
            GridRow {
                keyButton("."); keyButton("0")
                Button(action: save) {
                    Text("记下 \(keypad.resultText) 元").yubaiFont(YubaiFont.button)
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight)
                        .foregroundStyle(canSave ? YubaiColor.onBrand : YubaiColor.labelSecondary)
                        .background(canSave ? YubaiColor.brand : YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                }.gridCellColumns(2).disabled(!canSave).accessibilityIdentifier("saveQuickEntry")
            }
        }.buttonStyle(PressButtonStyle()).accessibilityElement(children: .contain).accessibilityLabel("数字键盘")
    }
    private func keyButton(_ key: String) -> some View {
        let operation = ["⌫", "+", "−"].contains(key)
        return Button { onKey(); keypad.press(key) } label: {
            Group {
                if key == "⌫" { Image(systemName: "delete.left") }
                else { Text(key) }
            }.yubaiFont(YubaiFont.amountDonut, weight: .regular)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.buttonHeight)
                .background(operation ? YubaiColor.card : YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
        }.accessibilityLabel(key == "⌫" ? "删除一位" : key == "+" ? "加" : key == "−" ? "减" : key == "." ? "小数点" : key)
            .accessibilityIdentifier("keypad_" + key)
    }
}
