import SwiftUI
import YubaiCore

enum AccountValuationTarget: Hashable {
    case reconcile(UUID)
    case invest(UUID)

    var accountID: UUID {
        switch self {
        case .reconcile(let id), .invest(let id): id
        }
    }

    var isInvestment: Bool {
        if case .invest = self { return true }
        return false
    }
}

struct AccountValuationSheetOverlay: View {
    let target: AccountValuationTarget
    let account: Account
    @State private var book: Int64
    let close: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled
    @State private var motion: EntrySheetMotion
    @State private var keypad: EntryKeypad
    @State private var negative: Bool
    @State private var replace: Bool
    @State private var saved = false

    init(target: AccountValuationTarget, account: Account, book: Int64, initial: Int64?, close: @escaping () -> Void) {
        self.target = target
        self.account = account
        _book = State(initialValue: book)
        self.close = close
        let amount = initial ?? book
        _motion = State(initialValue: EntrySheetMotion(settled: initial != nil))
        _keypad = State(initialValue: EntryKeypad(amount: abs(amount)))
        _negative = State(initialValue: amount < 0 || (amount == 0 && account.kind == .credit))
        _replace = State(initialValue: initial == nil)
    }

    private var reduced: Bool { !animationsEnabled || (reduceMotionOverride ?? systemReduceMotion) }
    private var amount: Int64 { (keypad.amount ?? 0) * (negative ? -1 : 1) }
    private var difference: Int64 { amount - book }
    private var canSave: Bool { !saved && difference != 0 && keypad.amount != nil }
    private var hidden: Bool { store.preferences.hideAmounts }

    var body: some View {
        let _ = OverviewRenderCounts.hit("valuationSheetBody")
        OverviewSheet(title: target.isInvestment ? "更新" + account.name : "核对余额", motion: motion, close: close) {
            VStack(spacing: .zero) {
                HStack(spacing: DS.Space.s12) {
                    box(target.isInvestment ? "上次" : "余白记的", value: book, input: false)
                    box(target.isInvestment ? "现在" : "银行 App 里", value: amount, input: true)
                        .onTapGesture { replace = true }
                        .accessibilityAction(named: "全选") { replace = true }
                        .accessibilityAction(named: Text("切换正负")) { if !target.isInvestment { negative.toggle() } }
                }.padding(.top, DS.Space.s4)
                differenceRow.padding(.top, DS.Space.s16)
                Button(action: save) {
                    Text(target.isInvestment ? "更新" : "记为余额校准").dsText(DS.Font.tTitle)
                        .foregroundStyle(DS.Color.onAccent)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.buttonH)
                        .dsPill(DS.Color.accent)
                        .opacity(canSave ? 1 : OverviewSpec.disabledOpacity)
                }.dsPressStyle().disabled(!canSave)
                    .accessibilityIdentifier(target.isInvestment ? "overviewInvestApply" : "reconcileApply")
                    .padding(.top, OverviewSpec.valuationApplyTop)
            }.padding(.horizontal, DS.Space.s20).padding(.bottom, DS.Space.s12)

            DSKeypad(onKey: press, variant: .digits)
                .frame(height: OverviewSpec.valuationTrayHeight, alignment: .top)
                .background(DS.Color.tray)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(target.isInvestment ? "investmentValuationSheet" : "reconcileSheet")
        .accessibilityAction(.escape) { if !saved { motion.close(reduced: reduced, onClose: close) } }
    }

    private func box(_ label: String, value: Int64, input: Bool) -> some View {
        VStack(alignment: .leading, spacing: OverviewSpec.headingGap) {
            Text(label).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
            Text(input ? inputText : OverviewDisplay.money(value, hidden: hidden))
                .dsText(DS.Font.tTitle).monospacedDigit()
                .foregroundStyle(input ? DS.Color.ink : DS.Color.ink2)
                .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .accessibilityIdentifier(input ? "overviewValuationAmount" : "overviewBookAmount")
        }
        .padding(.horizontal, DS.Space.s12).padding(.vertical, OverviewSpec.valuationBoxVertical)
        .frame(maxWidth: .infinity, minHeight: OverviewSpec.valuationBoxHeight, alignment: .leading)
        .dsSurface(input ? DS.Color.raised : DS.Color.surface, radius: DS.Radius.s)
        .overlay {
            if input {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .strokeBorder(DS.Color.accent, lineWidth: DS.Stroke.focus)
            }
        }
    }

    private var inputText: String {
        if hidden { return OverviewDisplay.money(amount, hidden: true) }
        if replace { return OverviewDisplay.money(amount, hidden: false) }
        let parts = keypad.displayText.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int64(parts[0]) ?? 0
        let sign = negative ? "−" : ""
        let integer = whole.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))
        return sign + integer + (parts.count > 1 ? "." + parts[1] : "")
    }

    private var differenceRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(target.isInvestment ? "涨跌" : "差额").dsText(DS.Font.tLabel)
            Spacer(minLength: DS.Space.s8)
            Text(HomeDisplay.signed(difference, hidden: hidden))
                .dsText(OverviewSpec.difference).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                .contentTransition(reduced ? .identity : .numericText(value: Double(difference)))
                .animation(reduced ? nil : DSMotion.standardAnimation, value: difference)
                .accessibilityIdentifier("overviewValuationDifference")
        }.foregroundStyle(!target.isInvestment && difference != 0 ? DS.Color.warnInk : DS.Color.ink)
    }

    private func press(_ key: String) {
        guard !saved else { return }
        if replace {
            keypad.reset()
            replace = false
        }
        keypad.press(key)
    }

    private func save() {
        guard canSave else { return }
        let now = store.overviewFixture?.now ?? Dates.now
        let actual = amount
        let target = target
        var adjustment: Entry?
        let ok = store.update(target.isInvestment ? "更新" + account.name : "对余额", entryMotion: false, showToast: false) { ledger in
            switch target {
            case .reconcile(let id):
                adjustment = try Reconciliation.reconcileAccount(&ledger, accountID: id, actualBalance: actual, now: now)
            case .invest(let id):
                try Reconciliation.revalueInvestment(&ledger, accountID: id, newValue: actual, now: now)
            }
        }
        guard ok else { return }
        saved = true
        motion.close(reduced: reduced, sealed: true) {
            close()
            if let adjustment {
                let delta = adjustment.delta(for: target.accountID)
                store.toast = "已记调整 " + HomeDisplay.signed(delta, hidden: store.preferences.hideAmounts)
            }
        }
    }
}
