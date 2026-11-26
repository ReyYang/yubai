import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

/// Every settings, account and first-open sheet. One stable root host presents them.
enum SettingsSheet: Hashable, Identifiable {
    case cycle, saving, floor, appearance, export, apiKey(enabling: Bool), weeklyTime
    case subAdd, subIcon
    case addCategory(income: Bool), addSubcategory(category: String, income: Bool)
    case renameSubcategory(category: String, sub: String, income: Bool)
    case addCurrency, rate(BillCurrency)
    case accountAdd(AccountType?, onboarding: Bool)
    case accountName(UUID), accountType(UUID), accountLimit(UUID), accountDay(UUID, statement: Bool)
    case onboardFloor
    var id: Self { self }
}

/// The six account types offered when adding an account.
enum AccountType: String, CaseIterable, Hashable, Identifiable {
    case debit, credit, alipay, wechat, cash, investment
    var id: String { rawValue }
    var title: String {
        switch self {
        case .debit: "储蓄卡"; case .credit: "信用卡"; case .alipay: "支付宝"
        case .wechat: "微信"; case .cash: "现金"; case .investment: "投资"
        }
    }
    var defaultName: String {
        switch self {
        case .wechat: "微信零钱"
        default: title
        }
    }
    var kind: AccountKind {
        switch self {
        case .debit: .bank; case .credit: .credit; case .alipay, .wechat, .cash: .cash; case .investment: .investment
        }
    }
    var icon: DS.Icon {
        switch self {
        case .debit: .acctDebit; case .credit: .acctCredit; case .alipay: .acctBalance
        case .wechat: .acctWallet; case .cash: .acctCash; case .investment: .acctInvest
        }
    }
    var balanceLabel: String {
        switch self {
        case .credit: "欠款"; case .investment: "现值"; default: "余额"
        }
    }
    static func of(_ account: Account) -> AccountType {
        switch account.kind {
        case .bank: .debit
        case .credit: .credit
        case .investment: .investment
        case .cash, .receivable:
            account.name.contains("支付宝") ? .alipay : account.name.contains("微信") ? .wechat : .cash
        }
    }
    static var gridItems: [DSTypeGrid.Item] { allCases.map { DSTypeGrid.Item(id: $0.rawValue, title: $0.title, icon: $0.icon) } }
}

/// The subscription being added, kept while the icon picker is open.
struct SubscriptionDraft: Equatable {
    var name = ""
    var amount: Int64?
    var day = Dates.calendar.component(.day, from: Dates.now)
    var yearly = false
    var slug: String?
}

struct SettingsSheetHost: View {
    let sheet: SettingsSheet
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = SettingsRenderCounts.hit("sheetHost")
        switch sheet {
        case .cycle: CycleDaySheet()
        case .saving: SavingAmountSheet()
        case .floor: FloorAmountSheet(onboarding: false)
        case .onboardFloor: FloorAmountSheet(onboarding: true)
        case .appearance: AppearanceSheet()
        case .export: ExportSheet()
        case .apiKey(let enabling): APIKeySheet(enabling: enabling)
        case .weeklyTime: WeeklyTimeSheet()
        case .subAdd: SubscriptionAddSheet()
        case .subIcon: SubscriptionIconSheet()
        case .addCategory(let income): TextEntrySheet(title: income ? "添加收入分类" : "添加支出分类", placeholder: "名称", initial: "", identifier: "categoryName") { name, ledger in
            try CategoryModel.add(YubaiCore.Category(name, income: income), in: &ledger)
        }
        case let .addSubcategory(category, income): TextEntrySheet(title: "添加小类", placeholder: category, initial: "", identifier: "subcategoryName") { name, ledger in
            try CategoryModel.addSubcategory(name, to: category, income: income, in: &ledger)
        }
        case let .renameSubcategory(category, sub, income): TextEntrySheet(title: "改名", placeholder: sub, initial: sub, identifier: "subcategoryName") { name, ledger in
            try CategoryModel.renameSubcategory(sub, in: category, to: name, income: income, ledger: &ledger)
        }
        case .addCurrency: AddCurrencySheet()
        case .rate(let currency): RateSheet(currency: currency)
        case let .accountAdd(type, onboarding): AccountAddSheet(type: type ?? .debit, onboarding: onboarding)
        case .accountName(let id): TextEntrySheet(title: "名称", placeholder: "名称", initial: store.accounts.first { $0.id == id }?.name ?? "", identifier: "accountName") { name, ledger in
            try Accounts.update(id, .init(name: name), in: &ledger, now: Dates.now)
        }
        case .accountType(let id): AccountTypeSheet(accountID: id)
        case .accountLimit(let id): CreditLimitSheet(accountID: id)
        case let .accountDay(id, statement): AccountDaySheet(accountID: id, statement: statement)
        }
    }
}

// MARK: Frame

/// The batch-1 sheet: grabber, 48 pt left-aligned title, scrim tap or swipe to close.
struct SettingsSheetFrame<Content: View>: View {
    let title: String
    var identifier = "settingsSheet"
    var after: SettingsSheet? = nil
    @ViewBuilder var content: (_ close: @escaping () -> Void) -> Content
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled
    @State private var motion = EntrySheetMotion(settled: SettingsFixture.current != nil)

    private var reduced: Bool { !animationsEnabled || (reduceMotionOverride ?? systemReduceMotion) }

    var body: some View {
        OverviewSheet(title: title, motion: motion, close: finish) {
            content { motion.close(reduced: reduced, sealed: true, onClose: finish) }
        }
        .accessibilityIdentifier(identifier)
    }

    private func finish() { store.settingsSheet = after }
}

/// Fields above, a primary button 14 above the 280 pt digits tray.
struct KeypadSheetLayout<Fields: View>: View {
    let cta: String
    let enabled: Bool
    var identifier = "settingsSheetDone"
    let onKey: (String) -> Void
    let action: () -> Void
    @ViewBuilder var fields: () -> Fields

    var body: some View {
        VStack(spacing: .zero) {
            fields().padding(.top, DS.Space.s4)
            DSButton(cta, enabled: enabled, action: action).accessibilityIdentifier(identifier)
                .padding(.top, OverviewSpec.valuationApplyTop)
        }.padding(.horizontal, DS.Space.s20).padding(.bottom, OverviewSpec.valuationApplyTop)
        DSKeypad(onKey: onKey, variant: .digits)
            .frame(height: OverviewSpec.valuationTrayHeight, alignment: .top)
            .background(DS.Color.tray)
    }
}

/// The focused amount box: label left, 28 pt number right.
struct SettingsAmountBox<Below: View>: View {
    let label: String
    let value: String
    var focused = true
    @ViewBuilder var below: () -> Below

    var body: some View {
        VStack(spacing: .zero) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2)
                Spacer(minLength: DS.Space.s8)
                Text(value).dsText(SettingsSpec.amount).foregroundStyle(DS.Color.ink)
                    .lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                    .accessibilityIdentifier("settingsAmount")
            }
            below()
        }
        .padding(.horizontal, DS.Space.s16).padding(.vertical, SettingsSpec.amountVertical)
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .strokeBorder(focused ? DS.Color.accent : DS.Color.separator, lineWidth: focused ? DS.Stroke.focus : DS.Stroke.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}

extension SettingsAmountBox where Below == EmptyView {
    init(label: String, value: String, focused: Bool = true) {
        self.init(label: label, value: value, focused: focused) { EmptyView() }
    }
}

/// A row of selectable capsule chips.
struct SettingsChips: View {
    struct Chip: Identifiable {
        let id: String
        let title: String
        let selected: Bool
    }
    let chips: [Chip]
    var outlined = false
    let select: (String) -> Void

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            ForEach(chips) { chip in
                Button { select(chip.id) } label: {
                    Text(chip.title).dsText(chip.selected ? DS.Font.tSubStrong : DS.Font.tSub).monospacedDigit()
                        .foregroundStyle(chip.selected ? DS.Color.accentInk : DS.Color.ink2).lineLimit(1)
                        .padding(.horizontal, DS.Space.s12).frame(minHeight: DS.Size.chipH)
                        .background(chip.selected ? DS.Color.accentSoft : (outlined ? .clear : DS.Color.surface), in: DS.Shape.pill)
                        .overlay {
                            if outlined && !chip.selected { DS.Shape.pill.strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
                        }
                        .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
                }.dsPressStyle().accessibilityAddTraits(chip.selected ? .isSelected : []).accessibilityIdentifier("settingsChip_" + chip.id)
            }
            Spacer(minLength: .zero)
        }
    }
}

// MARK: 周期起始日

struct CycleDaySheet: View {
    @Environment(AppStore.self) private var store
    @State private var day = Payday.defaultDay
    @State private var shift = false
    @State private var loaded = false

    var body: some View {
        SettingsSheetFrame(title: "周期起始日", identifier: "cycleSheet") { close in
            VStack(spacing: .zero) {
                DSDayGrid(selection: day) { day = $0 }.padding(.top, DS.Space.s4)
                CyclePreview(day: day, shift: shift, now: store.financialNow).padding(.top, SettingsSpec.previewTop)
                HStack {
                    Text("遇周末提前一天").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink)
                    Spacer(minLength: DS.Space.s8)
                    DSSwitch(title: "遇周末提前一天", isOn: $shift, showsTitle: false).accessibilityIdentifier("cycleWeekendShift")
                }
                .padding(.horizontal, SettingsSpec.cardInset).frame(minHeight: SettingsSpec.row)
                .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                .padding(.top, DS.Space.s20)
                DSButton("完成") {
                    let day = day, shift = shift, now = store.financialNow
                    if store.update("周期起始日", entryMotion: false, showToast: false, { try CycleStart.set(day: day, weekendShift: shift, in: &$0, now: now) }) { close() }
                }.accessibilityIdentifier("cycleDone").padding(.top, SettingsSpec.groupGap)
            }
            .padding(.horizontal, DS.Space.s20).padding(.bottom, OverviewSpec.periodBottom)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            day = CycleStart.day(in: store.current, now: store.financialNow)
            shift = store.preferences.shiftsWeekendPayday
        }
    }
}

/// This cycle and the next as two halves, with today's marker. Only the bar moves on change.
struct CyclePreview: View {
    let day: Int
    let shift: Bool
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dsAnimationsEnabled) private var animationsEnabled

    var body: some View {
        let _ = SettingsRenderCounts.hit("cyclePreview")
        let current = CycleStart.cycle(day: day, weekendShift: shift, now: now)
        let next = CycleStart.nextCycle(day: day, weekendShift: shift, now: now)
        let total = Double(max(1, days(current.start, Dates.addDays(1, to: next.end))))
        let thisShare = Double(days(current.start, next.start)) / total
        let today = Double(days(current.start, Dates.day(now))) / total
        let animate = animationsEnabled && !(reduceMotionOverride ?? systemReduceMotion)
        VStack(spacing: SettingsSpec.labelGap) {
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - SettingsSpec.previewGap)
                ZStack(alignment: .leading) {
                    HStack(spacing: SettingsSpec.previewGap) {
                        Capsule(style: .continuous).fill(DS.Color.accent).frame(width: width * thisShare)
                        Capsule(style: .continuous).fill(DS.Color.track)
                    }.frame(height: SettingsSpec.previewBar)
                    Capsule(style: .continuous).fill(DS.Color.ink)
                        .frame(width: SettingsSpec.markerWidth, height: SettingsSpec.markerHeight)
                        .offset(x: geometry.size.width * today)
                }.frame(maxHeight: .infinity)
            }.frame(height: SettingsSpec.markerHeight)
            HStack(spacing: .zero) {
                Text("\(Text("本期").fontWeight(.semibold).foregroundStyle(DS.Color.ink)) \(SettingsDisplay.range(current.start, current.end))")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("下期 " + SettingsDisplay.range(next.start, next.end)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3)
            .accessibilityElement(children: .combine).accessibilityIdentifier("cyclePreviewRange")
        }
        .animation(animate ? DSMotion.snappyAnimation : nil, value: day)
        .animation(animate ? DSMotion.snappyAnimation : nil, value: shift)
    }

    private func days(_ from: Date, _ to: Date) -> Int {
        Dates.calendar.dateComponents([.day], from: Dates.day(from), to: Dates.day(to)).day ?? 0
    }
}

// MARK: 先攒 / 底线存款

struct SavingAmountSheet: View {
    @Environment(AppStore.self) private var store
    @State private var keypad = EntryKeypad()
    @State private var replace = true
    @State private var loaded = false

    var body: some View {
        let takeHome = SettingsSummary.takeHome(in: store.current, now: store.financialNow)
        let current = SettingsSummary.savingTarget(in: store.current, now: store.financialNow)
        let amount = keypad.amount ?? 0
        let hidden = store.preferences.hideAmounts
        let values = (SettingsSummary.savingChips(takeHome: takeHome) + [current]).reduce(into: [Int64]()) { if $1 > 0 && !$0.contains($1) { $0.append($1) } }
        SettingsSheetFrame(title: "每月先攒", identifier: "savingSheet") { close in
            KeypadSheetLayout(cta: "完成", enabled: keypad.amount != nil, onKey: press, action: {
                let value = keypad.amount ?? 0
                if store.update("先攒", entryMotion: false, showToast: false, { $0.savingRule = .fixed(value) }) { close() }
            }) {
                SettingsAmountBox(label: "每月先攒", value: text(hidden: hidden)) {
                    if takeHome > 0 {
                        DSSplitBar(share: Double(amount) / Double(takeHome)).padding(.top, SettingsSpec.chipsTop)
                        HStack {
                            Text("先攒 " + OverviewDisplay.share(amount, of: takeHome))
                            Spacer(minLength: DS.Space.s8)
                            Text("留给花 " + OverviewDisplay.money(takeHome - amount, hidden: hidden))
                        }.dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3)
                            .padding(.top, SettingsSpec.labelsTop)
                    }
                }
                SettingsChips(chips: values.map { .init(id: "\($0)", title: OverviewDisplay.money($0, hidden: hidden), selected: $0 == amount) }) { id in
                    keypad = EntryKeypad(amount: Int64(id) ?? 0); replace = true
                }.padding(.top, SettingsSpec.chipsTop)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            keypad = EntryKeypad(amount: store.settingsFixture?.savingInput ?? current)
        }
    }

    private func text(hidden: Bool) -> String {
        hidden ? OverviewDisplay.money(0, hidden: true) : replace ? OverviewDisplay.money(keypad.amount ?? 0, hidden: false) : keypad.groupedText
    }

    private func press(_ key: String) {
        if replace { keypad.reset(); replace = false }
        keypad.press(key)
    }
}

struct FloorAmountSheet: View {
    let onboarding: Bool
    @Environment(AppStore.self) private var store
    @State private var keypad = EntryKeypad()
    @State private var replace = true
    @State private var loaded = false

    var body: some View {
        let chips = SettingsSummary.floorChips(in: store.current, now: store.financialNow)
        let amount = keypad.amount ?? 0
        let hidden = store.preferences.hideAmounts
        let titles = ["3 个月花销", "6 个月花销"]
        SettingsSheetFrame(title: "底线存款", identifier: "floorSheet") { close in
            KeypadSheetLayout(cta: "完成", enabled: keypad.amount != nil, onKey: press, action: {
                let value = keypad.amount ?? 0
                if onboarding { store.onboarding.floor = value; close(); return }
                if store.update("底线存款", entryMotion: false, showToast: false, { try Reserve.setFloor(value, in: &$0, now: store.financialNow) }) { close() }
            }) {
                SettingsAmountBox(label: "底线存款", value: hidden ? OverviewDisplay.money(0, hidden: true) : replace ? OverviewDisplay.money(amount, hidden: false) : keypad.groupedText)
                if !chips.isEmpty {
                    let values = chips
                    SettingsChips(chips: zip(titles, values).map { .init(id: $0.0, title: $0.0, selected: $0.1 == amount && $0.1 > 0) }) { id in
                        if let index = titles.firstIndex(of: id), values.indices.contains(index) { keypad = EntryKeypad(amount: values[index]); replace = true }
                    }.padding(.top, SettingsSpec.chipsTop)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            keypad = EntryKeypad(amount: onboarding ? (store.onboarding.floor ?? 0) : (store.profile.floorAmount ?? 0))
        }
    }

    private func press(_ key: String) {
        if replace { keypad.reset(); replace = false }
        keypad.press(key)
    }
}

// MARK: 外观 / 导出

struct AppearanceSheet: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        SettingsSheetFrame(title: "外观", identifier: "appearanceSheet") { close in
            DSPeriodOptionGroup(options: [.init(id: "system", title: "跟随系统"), .init(id: "light", title: "浅色"), .init(id: "dark", title: "深色")],
                                selection: store.preferences.appearance, rowHeight: SettingsSpec.row, identifierPrefix: "appearance_") { value in
                if store.update("外观", entryMotion: false, showToast: false, { $0.preferences.appearance = value }) { close() }
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
    }
}

struct ExportSheet: View {
    @Environment(AppStore.self) private var store
    @State private var range = ExportRange.current
    @State private var exporting = false

    var body: some View {
        let ledger = store.current, now = store.financialNow
        SettingsSheetFrame(title: "导出账单", identifier: "exportSheet") { close in
            VStack(spacing: .zero) {
                DSPeriodOptionGroup(options: ExportRange.allCases.map { option in
                    let interval = option.interval(in: ledger, now: now)
                    let count = "\(LedgerBackup.exportCount(ledger, in: interval).formatted()) 笔"
                    return .init(id: option.rawValue, title: title(option),
                                 range: interval.map { SettingsDisplay.range($0.lowerBound, $0.upperBound) + " · " + count } ?? count)
                }, selection: range.rawValue, rowHeight: SettingsSpec.row, identifierPrefix: "exportRange_") { range = ExportRange(rawValue: $0) ?? .current }
                DSButton("导出 CSV", enabled: !exporting) { export(close) }
                    .accessibilityIdentifier("exportCSV").padding(.top, DS.Space.s20)
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
    }

    private func title(_ range: ExportRange) -> String {
        switch range {
        case .current: "本期"
        case .previous: "上期"
        case .all: "全部"
        }
    }

    private func export(_ close: @escaping () -> Void) {
        let ledger = store.current, interval = range.interval(in: ledger, now: store.financialNow)
        let name = "余白账目-" + Dates.text(store.financialNow) + ".csv"
        exporting = true
        Task {
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                do { try LedgerBackup.entriesCSV(ledger, in: interval).write(to: url, options: .atomic); return url } catch { return nil }
            }.value
            exporting = false
            guard let url else { store.error = "没能写出文件，存储空间可能不够。"; return }
            SystemShare.present(url)
            close()
        }
    }
}

/// The system share sheet.
@MainActor enum SystemShare {
    static func present(_ url: URL) {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
        #endif
    }
}

// MARK: Text

/// One text field and 完成, for names.
struct TextEntrySheet: View {
    let title: String
    let placeholder: String
    let initial: String
    let identifier: String
    let save: (String, inout Ledger) throws -> Void
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsSheetFrame(title: title, identifier: identifier + "Sheet") { close in
            VStack(spacing: DS.Space.s16) {
                DSInlineTextField(title: placeholder, text: $text, onSubmit: { commit(close) }).accessibilityIdentifier(identifier)
                DSButton("完成", enabled: !clean.isEmpty && clean != initial) { commit(close) }.accessibilityIdentifier(identifier + "Done")
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, DS.Space.s20)
        }
        .onAppear { if !loaded { loaded = true; text = initial } }
    }

    private func commit(_ close: @escaping () -> Void) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != initial else { return }
        if store.update(title, entryMotion: false, showToast: false, { try save(clean, &$0) }) { close() }
    }
}

// MARK: 币种

struct AddCurrencySheet: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let used = Set((store.preferences.billExchangeRates ?? []).map(\.currency))
        let remaining = BillCurrency.allCases.filter { $0 != .cny && !used.contains($0) }
        SettingsSheetFrame(title: "添加币种", identifier: "addCurrencySheet") { _ in
            DSPeriodOptionGroup(options: remaining.map { .init(id: $0.rawValue, title: $0.unit, range: $0.rawValue) },
                                selection: "", rowHeight: SettingsSpec.subRow, identifierPrefix: "addCurrency_") { code in
                if let currency = BillCurrency(rawValue: code) { store.settingsSheet = .rate(currency) }
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
    }
}

/// CNY per one unit, up to four decimals.
struct RateSheet: View {
    let currency: BillCurrency
    @Environment(AppStore.self) private var store
    @State private var text = ""
    @State private var replace = true
    @State private var loaded = false

    private var value: Decimal? { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        SettingsSheetFrame(title: currency.unit, identifier: "rateSheet") { close in
            KeypadSheetLayout(cta: "完成", enabled: value != nil, onKey: press, action: {
                guard let value else { return }
                let rate = ManualExchangeRate(currency: currency, cnyPerUnit: value, updatedAt: store.financialNow)
                if store.update("汇率", entryMotion: false, showToast: false, { try FixedFlows.setRate(rate, in: &$0) }) { close() }
            }) {
                SettingsAmountBox(label: "1 " + currency.rawValue + " =", value: text.isEmpty ? "0" : text)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            text = FixedFlows.exchangeRate(for: currency, in: store.current, now: store.financialNow)?.valueText ?? ""
        }
    }

    private func press(_ key: String) {
        if replace { text = ""; replace = false }
        switch key {
        case "⌫": text = String(text.dropLast())
        case ".": if !text.contains(".") { text = (text.isEmpty ? "0" : text) + "." }
        default:
            let decimals = text.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
            guard text.count < 12, !(text.contains(".") && decimals >= 4) else { return }
            text = text == "0" ? key : text + key
        }
    }
}

// MARK: 订阅

struct SubscriptionAddSheet: View {
    @Environment(AppStore.self) private var store
    @State private var keypad = EntryKeypad()
    @State private var replace = false
    @State private var pickingDay = false
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var store = store
        let draft = store.subscriptionDraft
        let hidden = store.preferences.hideAmounts
        let canSave = !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && (keypad.amount ?? 0) > 0
        SettingsSheetFrame(title: "添加订阅", identifier: "subscriptionAddSheet") { close in
            VStack(spacing: .zero) {
                VStack(spacing: .zero) {
                    HStack(spacing: SettingsSpec.nameFieldInset) {
                        Button { keep(); store.settingsSheet = .subIcon } label: {
                            DSBrandTile(name: draft.name.isEmpty ? "?" : draft.name, slug: draft.slug)
                        }.dsPressStyle().accessibilityLabel("订阅图标").accessibilityIdentifier("subscriptionIcon")
                        DSInlineTextField(title: "名称", text: $store.subscriptionDraft.name, autoFocus: false, embedded: true)
                            .focused($nameFocused)
                            .accessibilityIdentifier("subscriptionName")
                    }
                    .padding(.horizontal, SettingsSpec.nameFieldInset).frame(minHeight: SettingsSpec.row)
                    .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
                    SettingsAmountBox(label: draft.yearly ? "每年" : "每月", value: hidden ? OverviewDisplay.money(0, hidden: true) : replace ? OverviewDisplay.money(keypad.amount ?? 0, hidden: false) : keypad.groupedText)
                        .padding(.top, SettingsSpec.balanceTop)
                        .onTapGesture { nameFocused = false }
                    SettingsChips(chips: [.init(id: "day", title: "每月 \(draft.day) 日", selected: !draft.yearly),
                                          .init(id: "yearly", title: "每年", selected: draft.yearly)]) { id in
                        if id == "day" {
                            if store.subscriptionDraft.yearly { store.subscriptionDraft.yearly = false } else { pickingDay.toggle() }
                        } else { store.subscriptionDraft.yearly = true; pickingDay = false }
                    }.padding(.top, SettingsSpec.chipsTop)
                    if pickingDay {
                        DSDayGrid(selection: draft.day, identifier: "subscriptionDay_") { day in
                            store.subscriptionDraft.day = min(day, Dates.calendar.range(of: .day, in: .month, for: store.financialNow)?.count ?? day)
                            pickingDay = false
                        }.padding(.top, DS.Space.s8)
                    }
                }.padding(.top, DS.Space.s4)
                DSButton("添加", enabled: canSave) { save(close) }.accessibilityIdentifier("subscriptionSave")
                    .padding(.top, OverviewSpec.valuationApplyTop)
            }.padding(.horizontal, DS.Space.s20).padding(.bottom, OverviewSpec.valuationApplyTop)
            if !nameFocused {
                DSKeypad(onKey: press, variant: .digits)
                    .frame(height: OverviewSpec.valuationTrayHeight, alignment: .top)
                    .background(DS.Color.tray)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let amount = draft.amount { keypad = EntryKeypad(amount: amount); replace = true }
        }
    }

    private func keep() { store.subscriptionDraft.amount = keypad.amount }

    private func press(_ key: String) {
        if replace { keypad.reset(); replace = false }
        keypad.press(key)
        store.subscriptionDraft.amount = keypad.amount
    }

    private func save(_ close: @escaping () -> Void) {
        let draft = store.subscriptionDraft, now = store.financialNow
        guard let amount = keypad.amount, amount > 0 else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = Dates.day(now)
        var due = Payday.nominalDate(day: draft.day, inMonthOf: today)
        if due < today { due = Payday.nominalDate(day: draft.day, inMonthOf: Dates.addMonths(1, to: today)) }
        let categories = FixedFlows.categories(inflow: false, in: store.current)
        var plan = Plan(title: name, amount: amount, dueDate: due, frequency: draft.yearly ? .yearly : .monthly,
                        category: categories.first { $0 == "会员订阅" } ?? categories.first ?? Classification.pendingCategory)
        plan.monthlyDay = draft.yearly ? nil : draft.day
        plan.iconSlug = draft.slug
        plan.accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id
        if store.update("添加订阅", entryMotion: false, { try ChangeSet(source: "用户操作", reason: "添加订阅", items: [.addPlan(plan)]).apply(to: &$0) }) {
            store.subscriptionDraft = SubscriptionDraft()
            close()
        }
    }
}

struct SubscriptionIconSheet: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var selected: String?
    @State private var loaded = false

    var body: some View {
        let name = store.subscriptionDraft.name
        let slugs = DSBrandCatalog.search(query)
        SettingsSheetFrame(title: "订阅图标", identifier: "subscriptionIconSheet", after: .subAdd) { close in
            VStack(spacing: .zero) {
                HStack(spacing: DS.Space.s8) {
                    DSIconView(icon: .search, size: DS.Font.tTitle.size, color: DS.Color.ink3)
                    DSInlineTextField(title: "搜索", text: $query, autoFocus: false, embedded: true).accessibilityIdentifier("subscriptionIconSearch")
                }
                .padding(.horizontal, DS.Space.s12).frame(minHeight: DS.Size.tapMin)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: DSLayout.categoryRow), spacing: SettingsSpec.cardInset) {
                    tile(nil, name: name)
                    ForEach(slugs, id: \.self) { slug in tile(slug, name: name) }
                }.padding(.top, SettingsSpec.previewTop)
                DSButton("完成") {
                    store.subscriptionDraft.slug = selected
                    close()
                }.accessibilityIdentifier("subscriptionIconDone").padding(.top, DS.Space.s28)
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
        .onAppear { if !loaded { loaded = true; selected = store.subscriptionDraft.slug ?? store.settingsFixture?.iconSelection } }
    }

    private func tile(_ slug: String?, name: String) -> some View {
        let on = selected == slug
        return Button { selected = slug } label: {
            Group {
                if let slug { DSBrandTile(name: slug, slug: slug, size: SettingsSpec.pickTile) }
                else {
                    Text(DSBrandCatalog.monogram(name.isEmpty ? "A" : name)).dsText(SettingsSpec.pickMonogram).foregroundStyle(DS.Color.ink2)
                        .frame(width: SettingsSpec.pickTile, height: SettingsSpec.pickTile)
                        .background(DS.Color.surface, in: .rect(cornerRadius: SettingsSpec.pickTile * SettingsSpec.tileRadius, style: .continuous))
                }
            }
            .overlay {
                let radius = SettingsSpec.pickTile * SettingsSpec.tileRadius
                if on {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).inset(by: -DS.Size.segmentedInset)
                        .stroke(DS.Color.accent, lineWidth: SettingsSpec.markGap)
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline)
                }
            }
        }
        .dsPressStyle()
        .accessibilityLabel(slug.flatMap { s in BrandIcons.catalog.first { $0.slug == s }?.name } ?? "首字")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("subscriptionIcon_" + (slug ?? "monogram"))
    }
}

// MARK: AI

struct APIKeySheet: View {
    let enabling: Bool
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var key = ""
    @State private var saving = false
    @State private var loaded = false

    private var valid: Bool {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.hasPrefix("sk-") && clean.count > SettingsSpec.keyPrefix + SettingsSpec.keySuffix
    }

    var body: some View {
        SettingsSheetFrame(title: "DeepSeek 密钥", identifier: "apiKeySheet") { close in
            VStack(spacing: .zero) {
                ZStack(alignment: .leading) {
                    Text(masked).dsText(SettingsSpec.key).foregroundStyle(key.isEmpty ? DS.Color.ink3 : DS.Color.ink).lineLimit(1)
                        .accessibilityHidden(true)
                    DSInlineTextField(title: "DeepSeek 密钥", text: $key, autoFocus: false, secure: true, embedded: true)
                        .opacity(SettingsSpec.hiddenFieldOpacity)
                        .accessibilityIdentifier("apiKeyField")
                }
                .padding(.horizontal, SettingsSpec.cardInset).frame(minHeight: SettingsSpec.row)
                .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).strokeBorder(DS.Color.accent, lineWidth: DS.Stroke.focus) }
                GeometryReader { geometry in
                    let paste = max(0, geometry.size.width - DS.Space.s12) * SettingsSpec.pasteShare
                    HStack(spacing: DS.Space.s12) {
                        DSButton("粘贴", kind: .secondary) { pasteKey() }.frame(width: paste).accessibilityIdentifier("apiKeyPaste")
                        DSButton("保存", enabled: valid && !saving) { save(close) }.accessibilityIdentifier("apiKeySave")
                    }
                }.frame(height: DS.Size.buttonH).padding(.top, SettingsSpec.keyButtonsTop)
                Button {
                    if let url = URL(string: "https://platform.deepseek.com/api_keys") { openURL(url) }
                } label: {
                    HStack(spacing: DS.Space.s4) {
                        Text("去 DeepSeek 申请").dsText(DS.Font.tLabelStrong)
                        DSIconView(icon: .arrowOut, size: SettingsSpec.linkIcon, color: DS.Color.accentInk)
                    }.foregroundStyle(DS.Color.accentInk).frame(maxWidth: .infinity, minHeight: DS.Size.tapMin).contentShape(Rectangle())
                }.dsPressStyle().accessibilityIdentifier("apiKeyApply").padding(.top, DS.Space.s8)
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
        .onAppear { if !loaded { loaded = true; key = store.settingsFixture?.apiKey ?? "" } }
    }

    /// `sk-` and the last four; the rest are bullets. The key itself is never shown or logged.
    private var masked: String {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > SettingsSpec.keyPrefix + SettingsSpec.keySuffix else { return clean.isEmpty ? "sk-" : String(repeating: "•", count: clean.count) }
        return String(clean.prefix(SettingsSpec.keyPrefix)) + String(repeating: "•", count: SettingsSpec.keyBullets) + String(clean.suffix(SettingsSpec.keySuffix))
    }

    private func pasteKey() {
        #if os(iOS)
        if let text = UIPasteboard.general.string { key = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        #endif
    }

    private func save(_ close: @escaping () -> Void) {
        guard valid, !saving else { return }
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        Task {
            defer { saving = false }
            if store.settingsFixture == nil {
                do { try await Task.detached(priority: .userInitiated) { try APIKeyStore.shared.save(value) }.value }
                catch { store.error = error.localizedDescription; return }
                IntelligenceRuntime.cloud.refresh(); await IntelligenceRuntime.cloud.waitForRefresh()
            }
            key = ""
            if enabling { store.update("云端 AI", entryMotion: false, showToast: false) { $0.preferences.cloudAIEnabled = true } }
            close()
        }
    }
}

struct WeeklyTimeSheet: View {
    @Environment(AppStore.self) private var store
    @State private var time = WeeklyReviewTime.standard
    @State private var loaded = false
    private static let days = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        SettingsSheetFrame(title: "每周回顾", identifier: "weeklyTimeSheet") { close in
            VStack(spacing: .zero) {
                HStack(spacing: DS.Space.s4) {
                    ForEach(Array(Self.days.enumerated()), id: \.offset) { index, name in
                        let on = time.weekday == index + 1
                        Button { time.weekday = index + 1 } label: {
                            Text(name).dsText(on ? DS.Font.tSubStrong : DS.Font.tSub)
                                .foregroundStyle(on ? DS.Color.accentInk : DS.Color.ink2)
                                .frame(maxWidth: .infinity, minHeight: DS.Size.chipH)
                                .background(on ? DS.Color.accentSoft : DS.Color.surface, in: DS.Shape.pill)
                                .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
                        }.dsPressStyle().accessibilityLabel("周" + name).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                HStack(spacing: DS.Space.s12) {
                    stepper(value: $time.hour, range: 0...23, label: "时")
                    Text(":").dsText(SettingsSpec.amount).foregroundStyle(DS.Color.ink3)
                    stepper(value: $time.minute, range: 0...59, step: 5, label: "分")
                }.padding(.top, DS.Space.s20)
                DSButton("完成") {
                    let value = time
                    if store.update("每周回顾", entryMotion: false, showToast: false, { $0.preferences.weeklyReviewTime = value == .standard ? nil : value }) { close() }
                }.accessibilityIdentifier("weeklyTimeDone").padding(.top, SettingsSpec.groupGap)
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
        .onAppear { if !loaded { loaded = true; time = store.preferences.reviewTime } }
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1, label: String) -> some View {
        HStack(spacing: DS.Space.s8) {
            arrow(.back, label: "减少" + label) { value.wrappedValue = value.wrappedValue - step < range.lowerBound ? range.upperBound - range.upperBound % step : value.wrappedValue - step }
            Text(String(format: "%02d", value.wrappedValue)).dsText(SettingsSpec.amount).foregroundStyle(DS.Color.ink)
                .contentTransition(.numericText(value: Double(value.wrappedValue)))
            arrow(.chevron, label: "增加" + label) { value.wrappedValue = value.wrappedValue + step > range.upperBound ? range.lowerBound : value.wrappedValue + step }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value.wrappedValue) " + label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            case .decrement: value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            @unknown default: break
            }
        }
    }

    private func arrow(_ icon: DS.Icon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSIconView(icon: icon, size: SettingsSpec.calendarArrow, color: DS.Color.ink3)
                .frame(width: DS.Size.tapMin, height: DS.Size.tapMin).contentShape(Rectangle())
        }.dsPressStyle().accessibilityLabel(label)
    }
}

// MARK: Accounts

struct AccountAddSheet: View {
    let onboarding: Bool
    @Environment(AppStore.self) private var store
    @State private var type: AccountType
    @State private var name: String
    @State private var keypad = EntryKeypad()
    @State private var replace = false
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    init(type: AccountType, onboarding: Bool) {
        self.onboarding = onboarding
        _type = State(initialValue: type)
        _name = State(initialValue: type.defaultName)
    }

    var body: some View {
        let hidden = store.preferences.hideAmounts
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsSheetFrame(title: "添加账户", identifier: "accountAddSheet") { close in
            VStack(spacing: .zero) {
                VStack(spacing: .zero) {
                    DSTypeGrid(items: AccountType.gridItems, selection: type.rawValue) { id in
                        guard let next = AccountType(rawValue: id) else { return }
                        if name.isEmpty || AccountType.allCases.contains(where: { $0.defaultName == name }) { name = next.defaultName }
                        type = next
                    }
                    DSInlineTextField(title: "名称", text: $name, autoFocus: false, embedded: true)
                        .focused($nameFocused)
                        .accessibilityIdentifier("accountName")
                        .padding(.horizontal, SettingsSpec.cardInset).frame(minHeight: SettingsSpec.nameField)
                        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                                .strokeBorder(nameFocused ? DS.Color.accent : DS.Color.separator, lineWidth: nameFocused ? DS.Stroke.focus : DS.Stroke.hairline)
                        }
                        .padding(.top, SettingsSpec.chipsTop)
                    VStack(alignment: .leading, spacing: OverviewSpec.headingGap) {
                        Text(type.balanceLabel).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3)
                        Text(hidden ? OverviewDisplay.money(0, hidden: true) : replace ? OverviewDisplay.money(keypad.amount ?? 0, hidden: false) : keypad.groupedText)
                            .dsText(DS.Font.nSpineLg).foregroundStyle(DS.Color.ink).lineLimit(1).minimumScaleFactor(HomeSpec.numberMinimumScale)
                            .accessibilityIdentifier("accountBalance")
                    }
                    .padding(.horizontal, SettingsSpec.cardInset).padding(.vertical, SettingsSpec.balanceTop)
                    .frame(maxWidth: .infinity, minHeight: SettingsSpec.balanceBox, alignment: .leading)
                    .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .strokeBorder(nameFocused ? DS.Color.separator : DS.Color.accent, lineWidth: nameFocused ? DS.Stroke.hairline : DS.Stroke.focus)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { nameFocused = false }
                    .padding(.top, SettingsSpec.balanceTop)
                }.padding(.top, DS.Space.s4)
                DSButton("添加", enabled: !clean.isEmpty) { save(close) }.accessibilityIdentifier("saveAccount")
                    .padding(.top, OverviewSpec.valuationApplyTop)
            }.padding(.horizontal, DS.Space.s20).padding(.bottom, OverviewSpec.valuationApplyTop)
            if !nameFocused {
                DSKeypad(onKey: press, variant: .digits)
                    .frame(height: OverviewSpec.valuationTrayHeight, alignment: .top)
                    .background(DS.Color.tray)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if onboarding, let draft = store.onboarding.accounts.first(where: { $0.type == type }) {
                name = draft.name; keypad = EntryKeypad(amount: draft.amount ?? 0); replace = true
            }
            if let fixture = store.settingsFixture?.accountAdd { name = fixture.name; keypad = EntryKeypad(amount: fixture.amount); replace = true }
        }
    }

    private func press(_ key: String) {
        if replace { keypad.reset(); replace = false }
        keypad.press(key)
    }

    private func save(_ close: @escaping () -> Void) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines), amount = keypad.amount ?? 0
        guard !clean.isEmpty else { return }
        if onboarding {
            store.onboarding.upsert(OnboardingAccount(type: type, name: clean, amount: amount, selected: true))
            close(); return
        }
        let draft = Accounts.Draft(name: clean, kind: type.kind, balance: type == .credit ? -amount : amount)
        if store.update("添加账户", entryMotion: false, { try Accounts.add(draft, in: &$0, now: store.financialNow) }) { close() }
    }
}

struct AccountTypeSheet: View {
    let accountID: UUID
    @Environment(AppStore.self) private var store
    @State private var type: AccountType = .debit
    @State private var loaded = false

    var body: some View {
        SettingsSheetFrame(title: "类型", identifier: "accountTypeSheet") { close in
            VStack(spacing: .zero) {
                DSTypeGrid(items: AccountType.gridItems, selection: type.rawValue) { type = AccountType(rawValue: $0) ?? type }
                DSButton("完成") {
                    let kind = type.kind
                    if store.update("账户类型", entryMotion: false, showToast: false, { try Accounts.update(accountID, .init(kind: kind), in: &$0, now: store.financialNow) }) { close() }
                }.accessibilityIdentifier("accountTypeDone").padding(.top, DS.Space.s20)
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
        .onAppear { if !loaded, let account = store.accounts.first(where: { $0.id == accountID }) { loaded = true; type = .of(account) } }
    }
}

struct CreditLimitSheet: View {
    let accountID: UUID
    @Environment(AppStore.self) private var store
    @State private var keypad = EntryKeypad()
    @State private var replace = true
    @State private var loaded = false

    var body: some View {
        let hidden = store.preferences.hideAmounts
        SettingsSheetFrame(title: "额度", identifier: "creditLimitSheet") { close in
            KeypadSheetLayout(cta: "完成", enabled: keypad.amount != nil, onKey: press, action: {
                let value = keypad.amount ?? 0
                if store.update("额度", entryMotion: false, showToast: false, { try Accounts.update(accountID, .init(creditLimit: value), in: &$0, now: store.financialNow) }) { close() }
            }) {
                SettingsAmountBox(label: "额度", value: hidden ? OverviewDisplay.money(0, hidden: true) : replace ? OverviewDisplay.money(keypad.amount ?? 0, hidden: false) : keypad.groupedText)
            }
        }
        .onAppear { if !loaded { loaded = true; keypad = EntryKeypad(amount: store.accounts.first { $0.id == accountID }?.creditLimit ?? 0) } }
    }

    private func press(_ key: String) {
        if replace { keypad.reset(); replace = false }
        keypad.press(key)
    }
}

struct AccountDaySheet: View {
    let accountID: UUID
    let statement: Bool
    @Environment(AppStore.self) private var store
    @State private var day: Int?
    @State private var loaded = false

    var body: some View {
        SettingsSheetFrame(title: statement ? "账单日" : "还款日", identifier: "accountDaySheet") { close in
            VStack(spacing: .zero) {
                DSDayGrid(selection: day, identifier: "accountDay_") { day = $0 }
                DSButton("完成", enabled: day != nil) {
                    let value = day
                    let change = statement ? Accounts.Change(statementDay: .some(value)) : Accounts.Change(paymentDay: .some(value))
                    if store.update(statement ? "账单日" : "还款日", entryMotion: false, showToast: false, { try Accounts.update(accountID, change, in: &$0, now: store.financialNow) }) { close() }
                }.accessibilityIdentifier("accountDayDone").padding(.top, SettingsSpec.groupGap)
            }
            .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s4).padding(.bottom, OverviewSpec.periodBottom)
        }
        .onAppear {
            guard !loaded, let account = store.accounts.first(where: { $0.id == accountID }) else { return }
            loaded = true
            day = statement ? account.creditStatementDay : account.creditPaymentDay
        }
    }
}
