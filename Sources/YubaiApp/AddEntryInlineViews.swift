import SwiftUI
import YubaiCore

enum AddEntryInlinePanel: Equatable {
    case none, accounts(destination: Bool), calendar, categories, newAccount(destination: Bool)
}

struct AddEntryAccountChips: View {
    let accounts: [Account]
    let selection: UUID?
    let choose: (UUID) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YubaiSpace.space8) {
                ForEach(accounts) { account in
                    CategoryChoiceChip(title: account.name, selected: account.id == selection) { choose(account.id) }
                        .accessibilityIdentifier("entryAccountChoice_" + account.id.uuidString)
                }
            }
        }.accessibilityIdentifier("entryInlineAccounts")
    }
}

struct AddEntryCalendar: View {
    @Binding var date: Date
    let done: () -> Void
    var body: some View {
        ScrollView {
            EntryCalendarView(selection: Binding(get: { date }, set: { date = $0; done() }), today: Date(), customHeader: { month in
                AnyView(AddEntryCalendarHeader(month: month, done: done))
            }).padding(.horizontal, YubaiSpace.space12)
        }.frame(height: 350).accessibilityIdentifier("entryInlineCalendar")
    }
}

private struct AddEntryCalendarHeader: View {
    @Binding var month: Date
    let done: () -> Void
    @State private var choosingMonth = false
    private var year: Int { Dates.calendar.component(.year, from: month) }
    private var number: Int { Dates.calendar.component(.month, from: month) }
    var body: some View {
        VStack(spacing: YubaiSpace.space8) {
            HStack {
                Button { choosingMonth.toggle() } label: {
                    HStack(spacing: YubaiSpace.space4) {
                        Text(String(year) + "年" + String(number) + "月").yubaiFont(YubaiFont.rowTitle, weight: .semibold).fixedSize()
                        Image(systemName: "chevron.down").yubaiFont(YubaiFont.meta)
                    }.frame(minHeight: YubaiSize.tapMin)
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entryCalendarMonth")
                Spacer(minLength: YubaiSpace.space8)
                Button { if choosingMonth { choosingMonth = false } else { done() } } label: {
                    Text("好").yubaiFont(YubaiFont.body, weight: .semibold).foregroundStyle(YubaiColor.onBrand)
                        .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).background(YubaiColor.brand, in: Circle())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("entryDateDone")
            }
            if choosingMonth { monthWheels }
        }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    private var monthWheels: some View {
        HStack {
            Picker("年", selection: Binding(get: { year }, set: { setMonth(year: $0, number: number) })) {
                ForEach(1900...2200, id: \.self) { value in Text(String(value) + "年").tag(value) }
            }.accessibilityIdentifier("entryCalendarYearWheel")
            Picker("月", selection: Binding(get: { number }, set: { setMonth(year: year, number: $0) })) {
                ForEach(1...12, id: \.self) { value in Text(String(value) + "月").tag(value) }
            }.accessibilityIdentifier("entryCalendarMonthWheel")
        }.labelsHidden()
            #if os(iOS)
            .pickerStyle(.wheel)
            #else
            .pickerStyle(.menu)
            #endif
    }
    private func setMonth(year: Int, number: Int) {
        month = Dates.calendar.date(from: DateComponents(year: year, month: number, day: 1)) ?? month
    }
}

struct AddEntryIncomeChips: View {
    @Environment(AppStore.self) private var store
    let selection: CategoryAssignment
    let hint: String?
    let choose: (CategoryAssignment?) -> Void
    let more: () -> Void
    private struct Choice: Identifiable {
        var title: String; var assignment: CategoryAssignment
        var id: String { assignment.path }
    }
    private var choices: [Choice] {
        let rows = store.current.orderedCategories(income: true)
        var result: [Choice] = []
        if let salary = rows.first(where: { $0.name == "工资奖金" }) {
            for name in ["工资", "奖金"] where salary.subcategories.contains(name) {
                result.append(.init(title: name, assignment: .init(category: salary.name, subcategory: name)))
            }
        }
        for name in ["报销", "礼金赠与"] where rows.contains(where: { $0.name == name }) {
            result.append(.init(title: name == "礼金赠与" ? "红包" : name, assignment: .init(category: name)))
        }
        for row in rows where result.count < 4 && !result.contains(where: { $0.assignment.category == row.name }) {
            result.append(.init(title: row.name, assignment: .init(category: row.name)))
        }
        if !selection.category.isEmpty, !Classification.isPending(selection.category), !result.contains(where: { $0.assignment == selection }) {
            result.append(.init(title: selection.subcategory ?? selection.category, assignment: selection))
        }
        return result
    }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YubaiSpace.space8) {
                ForEach(choices) { row in
                    CategoryChoiceChip(title: row.title, selected: row.assignment == selection,
                                       outlined: hint == row.assignment.category && row.assignment != selection) { choose(row.assignment) }
                        .accessibilityIdentifier("entryCategory_" + row.title)
                }
                CategoryChoiceChip(title: "更多", action: more).accessibilityIdentifier("entryCategoryMore")
            }
        }.accessibilityIdentifier("entryIncomeCategories")
    }
}

/// Replaces the composer in its existing presentation, including management and additions.
struct AddEntryCategories: View {
    @Environment(AppStore.self) private var store
    let income: Bool
    let selection: CategoryAssignment
    let suggested: String?
    let cancel: () -> Void
    let choose: (CategoryAssignment?) -> Void
    @State private var adding = false
    @State private var parent: String?
    @State private var managing = false
    private var rows: [YubaiCore.Category] { store.current.orderedCategories(income: income) }
    var body: some View {
        Group {
            if adding {
                CategoryAdditionSheet(income: income, parent: parent, cancel: { adding = false }) { addition in
                    guard store.update("添加分类", entryMotion: false, showToast: false, { try addition.apply(to: &$0) }) else { return false }
                    choose(addition.assignment); return true
                }
            } else if managing { manager }
            else { picker }
        }.accessibilityIdentifier("entryCategoryPicker")
    }
    private var picker: some View {
        VStack(spacing: 0) {
            ManualSheetHeader(title: "选分类", actionTitle: "管理", primary: false, cancelTitle: "返回",
                              actionIdentifier: "entryMoreManage", cancelIdentifier: "entryMoreCancel",
                              cancel: cancel, action: { managing = true }).padding(.horizontal, YubaiSpace.insetPage)
            Page(topPadding: YubaiSpace.space8) {
                CategoryPicker(income: income, selected: selection.category.isEmpty ? nil : selection, suggested: suggested,
                               identifier: "entryMore", style: .entry, addInline: { target in parent = target; adding = true }) { assignment, _ in
                    choose(assignment); return true
                }
            }
        }
    }
    private var manager: some View {
        VStack(spacing: 0) {
            ManualSheetHeader(title: "分类", actionTitle: "新分类", primary: false, cancelTitle: "返回",
                              actionIdentifier: "addMainCategory", cancelIdentifier: "entryCategoryManageBack",
                              cancel: { managing = false }, action: { parent = nil; adding = true })
                .padding(.horizontal, YubaiSpace.insetPage)
            List {
                ForEach(rows) { row in
                    HStack {
                        Text(row.name).yubaiFont(YubaiFont.row).lineLimit(1)
                        Spacer(minLength: YubaiSpace.space8)
                        if !row.isCatchAll {
                            Button("不显示") { hide(row, true) }.yubaiFont(YubaiFont.callout).frame(minHeight: 44)
                                .accessibilityIdentifier("entryHideCategory_" + row.name)
                        }
                    }.listRowBackground(YubaiColor.paperSheet)
                }.onMove(perform: move)
                let hidden = store.current.orderedCategories(income: income, hidden: true)
                if !hidden.isEmpty {
                    Section("已隐藏") {
                        ForEach(hidden) { row in
                            HStack {
                                Text(row.name).lineLimit(1); Spacer()
                                Button("放回去") { hide(row, false) }.frame(minHeight: 44)
                                    .accessibilityIdentifier("entryUnhideCategory_" + row.name)
                            }.listRowBackground(YubaiColor.paperSheet)
                        }
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #endif
                .accessibilityIdentifier("entryInlineCategoryManager")
        }
    }
    private func hide(_ row: YubaiCore.Category, _ hidden: Bool) {
        store.update("分类", entryMotion: false, showToast: false) { try CategoryModel.setHidden(hidden, category: row.name, income: income, in: &$0) }
    }
    private func move(_ offsets: IndexSet, to target: Int) {
        var names = rows.map(\.name); names.move(fromOffsets: offsets, toOffset: target)
        store.update("分类", entryMotion: false, showToast: false) { try CategoryModel.setOrder(names, income: income, in: &$0) }
    }
}

struct AddEntryAccountForm: View {
    @Environment(AppStore.self) private var store
    let cancel: () -> Void
    let added: (Account) -> Void
    @State private var name = ""
    @State private var kind = AccountKind.bank
    @State private var keypad = EntryKeypad()
    @FocusState private var nameFocused: Bool
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (keypad.amount ?? -1) >= 0 }
    var body: some View {
        EntryForm(title: "添加账户", actionTitle: "加上", enabled: valid, actionIdentifier: "saveManualSheet", cancel: cancel, save: save) {
            Card(style: .list) { FormTextRow(title: "名称", text: $name, identifier: "accountName", focus: $nameFocused) }
            SegmentedWide(choices: [(AccountKind.bank, "银行卡"), (.cash, "现金"), (.credit, "信用卡")], selection: $kind)
            EditableAmountDisplay(amount: keypad.resultText, keypad: keypad, presented: true, selected: false,
                                  identifier: "accountBalance", open: { nameFocused = false }, hide: store.preferences.hideAmounts)
        }.safeAreaInset(edge: .bottom) {
            if !nameFocused { AmountKeypad(keypad: $keypad, canSave: valid, primaryTitle: "加上", primaryIdentifier: "saveEntryAccount", save: save) }
        }
    }
    private func save() {
        guard valid, let amount = keypad.amount else { return }
        let account = Account(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind,
                              balance: kind == .credit ? -amount : amount, at: Date())
        if store.update("添加账户", entryMotion: false, showToast: false, { $0.accounts.append(account) }) { added(account) }
    }
}
