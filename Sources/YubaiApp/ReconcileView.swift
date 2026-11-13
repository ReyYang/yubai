import SwiftUI
import YubaiCore

/// 对一下余额：每个账户写着账上是多少，旁边填现在实际有多少；差的记成一笔「没细记」。
struct ReconcileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var rows: [Reconciliation.Row] = []
    @State private var inputs: [UUID: String] = [:]
    @State private var loaded = false

    private var actual: [UUID: Int64] {
        var values: [UUID: Int64] = [:]
        for row in rows { values[row.id] = (try? Money.parse(inputs[row.id] ?? "", allowNegative: true)) ?? row.book }
        return values
    }
    private var hasInvalidInput: Bool {
        rows.contains { row in
            let text = (inputs[row.id] ?? "").trimmingCharacters(in: .whitespaces)
            return text.isEmpty || (try? Money.parse(text, allowNegative: true)) == nil
        }
    }
    /// 正数 = 少了，负数 = 多了。
    private var missing: Int64 { Reconciliation.preview(store.current, actual: actual, now: store.financialNow).missing }
    private var range: (from: Date, through: Date) {
        let today = Dates.day(Date())
        return (store.recordGap?.from ?? today, today)
    }
    private var rangeText: String {
        let (from, through) = range
        let first = FixedFlowPresentation.monthDay(from), last = FixedFlowPresentation.monthDay(through)
        return from == through ? first : first + " – " + last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(rows) { row in
                            accountRow(row)
                            if row.id != rows.last?.id { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
                        }
                    }
                }
                if missing != 0 { resultBar }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup)
        }.scrollDismissesKeyboard(.interactively).paperBackground()
            .safeAreaInset(edge: .top, spacing: YubaiSpace.none) {
                ManualSheetHeader(title: "对一下余额", showsAction: false, cancel: { dismiss() }, action: {})
                    .padding(.horizontal, YubaiSpace.insetPage)
            }
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) { actions }
            .accessibilityIdentifier("reconcileSheet")
            .onAppear(perform: load)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.large])
            #endif
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        rows = Reconciliation.rows(in: store.current, now: Date())
        inputs = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, Money.editableText($0.book)) })
    }

    private func accountRow(_ row: Reconciliation.Row) -> some View {
        let hide = store.preferences.hideAmounts
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(row.name).yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                Text("账上 " + amount2(row.book, hide: hide)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: YubaiSpace.space8) }
            field(row)
        }.padding(.vertical, YubaiSpace.space8).frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
    }

    private func field(_ row: Reconciliation.Row) -> some View {
        let binding = Binding(get: { inputs[row.id] ?? "" }, set: { inputs[row.id] = $0 })
        return BalanceAmountField(text: binding, label: row.name + "实际余额", identifier: "reconcileField_" + row.name)
    }

    private var resultBar: some View {
        let value = abs(missing)
        let text = missing > 0 ? "少了" : "多了"
        return ResultBar(label: rangeText + " " + text, value: amount2(value, hide: store.preferences.hideAmounts),
                         amber: missing > 0, identifier: "reconcileResult")
    }

    private var actions: some View {
        let title: String
        if missing > 0 { title = "记成一笔 " + amount2(-missing, hide: store.preferences.hideAmounts) }
        else if missing < 0 { title = "记成一笔 " + (store.preferences.hideAmounts ? "••••" : AmountLabel.text(-missing, sign: .inflow)) }
        else { title = "好" }
        return VStack(spacing: YubaiSpace.space8) {
            Button(title, action: apply).buttonStyle(PrimaryButtonStyle()).disabled(hasInvalidInput)
                .accessibilityIdentifier("reconcileApply")
            Button("一笔笔补上", action: addByHand).buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("reconcileByHand")
        }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.space8)
    }

    private func apply() {
        guard !hasInvalidInput else { return }
        let values = actual
        let difference = missing
        let ok = store.update("对余额", entryMotion: false, showToast: false) { ledger in
            let added = try Reconciliation.apply(&ledger, actual: values, now: Date())
            for index in ledger.cards.indices {
                if case .reconcileAccount(let id) = ledger.cards[index].action, values[id] != nil { ledger.cards[index].dismissedAt = Date() }
            }
            _ = added
        }
        if ok {
            store.toast = "已补 · 没细记 " + amount2(-difference, hide: store.preferences.hideAmounts)
            dismiss()
        }
    }

    /// 不一次补平：回到记一笔，一笔笔补。
    private func addByHand() {
        store.present(.addEntry, from: "add")
    }
}
