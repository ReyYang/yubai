import SwiftUI
import YubaiCore

/// 对一下余额：差额记成调整，预览当前周期的实际资金底线。
struct ReconcileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
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
    private var preview: Reconciliation.Result { Reconciliation.preview(store.current, actual: actual, now: store.financialNow) }
    private var missing: Int64 { preview.missing }
    private var range: (from: Date, through: Date) {
        let today = Dates.day(Dates.now)
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
                            if row.id != rows.last?.id { Rectangle().fill(YubaiColor.separator).frame(height: YubaiSize.separator).accessibilityHidden(true) }
                        }
                    }
                }
                if missing != 0 { resultBar }
                if preview.changesSpendable {
                    ResultBar(label: "还能花变成", value: amount2(preview.spendableAfter.available, hide: store.preferences.hideAmounts),
                              amber: true, identifier: "reconcileSpendableAfter")
                }
                actions.padding(.top, YubaiSpace.gapGroup)
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup)
                .padding(.bottom, YubaiSpace.pageBottomSafe)
        }.scrollDismissesKeyboard(.interactively).paperBackground()
            .safeAreaInset(edge: .top, spacing: YubaiSpace.none) {
                ManualSheetHeader(title: "对一下余额", showsAction: false, cancel: { dismiss() }, action: {})
                    .padding(.horizontal, YubaiSpace.insetPage)
            }
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
        rows = Reconciliation.rows(in: store.current, now: Dates.now)
        inputs = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, Money.editableText($0.book)) })
    }

    private func accountRow(_ row: Reconciliation.Row) -> some View {
        let hide = store.preferences.hideAmounts
        let binding = Binding(get: { inputs[row.id] ?? "" }, set: { inputs[row.id] = $0 })
        return MoneyInputRow(title: row.name + "实际余额", text: binding, identifier: "reconcileField_" + row.name, allowNegative: true, leadingLabel: AnyView(
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(row.name).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle).lineLimit(1)
                Text("账上 " + amount2(row.book, hide: hide)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
        )).padding(.vertical, YubaiSpace.space8)
    }

    private var resultBar: some View {
        let value = abs(missing)
        let text = missing > 0 ? "少了" : "多了"
        return ResultBar(label: rangeText + " " + text, value: amount2(value, hide: store.preferences.hideAmounts),
                         amber: missing > 0, identifier: "reconcileResult")
    }

    private var actions: some View {
        let title: String
        if missing > 0 { title = "记成调整 " + amount2(-missing, hide: store.preferences.hideAmounts) }
        else if missing < 0 { title = "记成调整 " + (store.preferences.hideAmounts ? "••••" : AmountLabel.text(-missing, sign: .inflow)) }
        else { title = "余额一致" }
        return VStack(spacing: YubaiSpace.space8) {
            Button(title, action: apply).buttonStyle(PrimaryButtonStyle()).disabled(hasInvalidInput)
                .accessibilityIdentifier("reconcileApply")
            Button("一笔笔补上", action: addByHand).buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("reconcileByHand")
        }
    }

    private func apply() {
        guard !hasInvalidInput else { return }
        let values = actual
        let difference = missing
        let ok = store.update("对余额", entryMotion: false, showToast: false) { ledger in
            let added = try Reconciliation.apply(&ledger, actual: values, now: Dates.now)
            for index in ledger.cards.indices {
                if case .reconcileAccount(let id) = ledger.cards[index].action, values[id] != nil { ledger.cards[index].dismissedAt = Dates.now }
            }
            _ = added
        }
        if ok {
            store.toast = difference == 0 ? "余额已对好" : "已记调整 " + amount2(-difference, hide: store.preferences.hideAmounts)
            dismiss()
        }
    }

    /// 不一次补平：回到记一笔，一笔笔补。
    private func addByHand() {
        store.present(.addEntry, from: "add")
    }
}
