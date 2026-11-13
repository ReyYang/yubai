import SwiftUI
import YubaiCore

struct BillRateLabel: View {
    @Environment(AppStore.self) private var store
    let currency: BillCurrency
    var body: some View {
        let rate = FixedFlows.exchangeRate(for: currency, in: store.current, now: store.financialNow)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.space8) { labels(rate) }
            VStack(alignment: .leading, spacing: YubaiSpace.space4) { labels(rate) }
        }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    @ViewBuilder private func labels(_ rate: ManualExchangeRate?) -> some View {
        Text(rate?.equation ?? "填写汇率").fixedSize(horizontal: false, vertical: true)
        if let rate {
            Spacer(minLength: YubaiSpace.none)
            Text(Dates.calendar.isDate(rate.updatedAt, inSameDayAs: store.financialNow) ? "今天 " + rate.updatedAt.formatted(.dateTime.hour().minute()) + " 更新" : Dates.text(rate.updatedAt, time: true) + " 更新")
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BillRateEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let currency: BillCurrency
    @State private var value = ""
    private var rate: ManualExchangeRate? {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              value.range(of: #"^\d{1,6}(\.\d{1,6})?$"#, options: .regularExpression) != nil else { return nil }
        let rate = ManualExchangeRate(currency: currency, cnyPerUnit: decimal, updatedAt: store.financialNow)
        return rate.isValid ? rate : nil
    }
    var body: some View {
        EntryForm(title: "汇率", actionTitle: "保存", enabled: rate != nil, scrollIdentifier: "billRateEditor", cancel: { dismiss() }, save: save) {
            Card(style: .list) {
                CardTextFieldRow(title: "1 " + currency.unit + " =", text: $value, identifier: "billRateValue", numeric: true, autofocus: true)
            }
            if rate == nil && !value.isEmpty { InlineFieldError(message: "填写有效汇率。") }
        }.onAppear { value = FixedFlows.exchangeRate(for: currency, in: store.current, now: store.financialNow)?.valueText ?? "" }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.medium, .large])
            #endif
    }
    private func save() {
        guard let rate else { return }
        if store.update("汇率", entryMotion: false, { try FixedFlows.setRate(rate, in: &$0) }) { dismiss() }
    }
}

struct FixedFlowEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var planID: UUID? = nil
    @State private var title = ""
    @State private var amount = ""
    @State private var currency = BillCurrency.cny
    @State private var frequency = Frequency.monthly
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var category = "其他支出"
    @State private var inflow = false
    @State private var autoPay = false
    @State private var estimated = false
    @State private var intoFixedSavings = false
    @State private var installments: Int?
    @State private var rates: [BillCurrency: String] = [:]
    @State private var editingRate = false
    @State private var pickingDate = false
    @State private var initialized = false
    @State private var initialSignature = ""
    @State private var confirmingDiscard = false
    private var accounts: [Account] { store.accounts.filter { !$0.archived || $0.id == accountID } }
    private var saved: Plan? { store.plans.first { $0.id == planID } }
    private var lastCurrency: BillCurrency { store.preferences.lastBillCurrency.flatMap { $0 == .cny ? nil : $0 } ?? .usd }
    private var cents: Int64? { try? Money.parse(amount) }
    private var rateText: Binding<String> {
        Binding(get: { rates[currency] ?? "" }, set: { rates[currency] = $0 })
    }
    private func quote(_ currency: BillCurrency) -> ManualExchangeRate? {
        guard let text = rates[currency], text.range(of: #"^\d{1,6}(\.\d{1,6})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let old = FixedFlows.exchangeRate(for: currency, in: store.current, now: store.financialNow)
        let value = ManualExchangeRate(currency: currency, cnyPerUnit: decimal, updatedAt: old?.cnyPerUnit == decimal ? old!.updatedAt : store.financialNow)
        return value.isValid ? value : nil
    }
    private var converted: Int64? {
        guard let cents else { return nil }
        return currency == .cny ? cents : quote(currency)?.convert(cents)
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (cents ?? 0) > 0 && (converted ?? 0) > 0 &&
            (!autoPay || accountID != nil) && (planID == nil || signature != initialSignature)
    }
    private var signature: String {
        [title, amount, currency.rawValue, frequency.rawValue, Dates.text(date), accountID?.uuidString ?? "", category,
         String(inflow), String(autoPay), String(estimated), String(intoFixedSavings), installments.map(String.init) ?? "", rates.sorted { $0.key.rawValue < $1.key.rawValue }.map { $0.key.rawValue + $0.value }.joined()].joined(separator: "|")
    }
    var body: some View {
        EntryForm(title: planID == nil ? "加一个账单" : "改账单", actionTitle: planID == nil ? "加上" : "保存", enabled: canSave,
                  scrollIdentifier: "fixedFlowEditor", cancel: cancel, save: save) {
            amountCard
            scheduleCard
            moreCard
        }.amountPrivacy(store.preferences.hideAmounts)
            .entryDiscardGuard(dirty: initialized && signature != initialSignature, amount: cents ?? 0, confirming: $confirmingDiscard)
            .onAppear(perform: load)
            .onChange(of: currency) { _, value in editingRate = value != .cny && quote(value) == nil }
            .onChange(of: inflow) { _, value in
                if planID == nil { category = value ? "其他收入" : "其他支出" }
                if !value { intoFixedSavings = false }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            .presentationDetents([.large])
            #endif
    }
    private var amountCard: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                CardTextFieldRow(title: "名字", text: $title, identifier: "fixedFlowTitle",
                                 leading: AnyView(BillBrandIcon(title: title, category: category, inflow: inflow)), autofocus: true)
                EntryFormDivider()
                MoneyInputRow(title: "金额", text: $amount, identifier: "fixedFlowAmount", currencySymbol: currency.symbol,
                              trailing: AnyView(currencyChips))
                if currency != .cny { foreignRows }
            }
        }
    }
    private var currencyChips: some View {
        ChipFlow {
            currencyChip(.cny)
            currencyChip(currency != .cny ? currency : lastCurrency)
            Menu {
                ForEach(BillCurrency.allCases.filter { $0 != .cny }) { item in
                    Button(item.symbol + " · " + item.unit) { currency = item }
                }
            } label: { Text("其他").fixedSize().padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin).background(YubaiColor.card, in: Capsule()) }
                .accessibilityIdentifier("billCurrencyOther")
        }
    }
    private func currencyChip(_ value: BillCurrency) -> some View {
        Button { currency = value } label: {
            Text(value.symbol).yubaiFont(YubaiFont.callout).fixedSize().padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin)
                .foregroundStyle(currency == value ? YubaiColor.canvas : YubaiColor.label)
                .background(currency == value ? YubaiColor.label : YubaiColor.card, in: Capsule())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("billCurrency_" + value.rawValue)
            .accessibilityAddTraits(currency == value ? .isSelected : [])
    }
    @ViewBuilder private var foreignRows: some View {
        EntryFormDivider()
        if let value = converted {
            EntryFormRow(title: "约") { Text(amount2(value, hide: store.preferences.hideAmounts) + " 元").yubaiFont(YubaiFont.amount).fixedSize() }
        }
        Button { editingRate.toggle() } label: {
            HStack {
                Text(quote(currency)?.equation ?? "填写汇率").fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: YubaiSpace.space4)
                if let rate = quote(currency) { Text(Dates.calendar.isDate(rate.updatedAt, inSameDayAs: store.financialNow) ? "今天" : FixedFlowPresentation.monthDay(rate.updatedAt)).fixedSize() }
            }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("billEditRate")
        if editingRate {
            CardTextFieldRow(title: "1 " + currency.unit + " =", text: rateText, identifier: "billRateValue", numeric: true)
            if !(rates[currency] ?? "").isEmpty && quote(currency) == nil { InlineFieldError(message: "填写有效汇率。") }
        }
    }
    private var scheduleCard: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                EntryFormRow(title: "多久一次") { cycles }.accessibilityIdentifier("fixedFlowSchedule")
                EntryFormDivider()
                EntryFormRow(title: "哪一天") {
                    Button { pickingDate.toggle() } label: {
                        Text(frequency == .monthly ? "\(Dates.calendar.component(.day, from: date)) 号" : FixedFlowPresentation.monthDay(date))
                            .yubaiFont(YubaiFont.row).fixedSize().frame(minHeight: YubaiSize.tapMin)
                    }.buttonStyle(PressButtonStyle()).accessibilityLabel(frequency == .yearly ? "几月几号" : "哪一天")
                        .accessibilityIdentifier("fixedFlowDate")
                }
                if pickingDate { EntryCalendarView(selection: $date, today: store.financialNow, identifier: "fixedFlowCalendar") }
                EntryFormDivider()
                EntryFormRow(title: inflow ? "收到哪里" : "从哪付") {
                    Menu {
                        Button("未指定") { accountID = nil; autoPay = false }
                        ForEach(accounts) { account in Button(account.name) { accountID = account.id } }
                    } label: { Text(store.accountName(accountID)).yubaiFont(YubaiFont.row).lineLimit(1) }
                        .accessibilityIdentifier("fixedFlowAccount")
                }
            }
        }
    }
    private var cycles: some View {
        ChipFlow {
            cycleChip(.monthly)
            cycleChip(.yearly)
            Menu {
                ForEach(Frequency.allCases.filter { $0 != .monthly && $0 != .yearly }) { value in Button(value.label) { frequency = value } }
            } label: {
                Text(frequency == .monthly || frequency == .yearly ? "其他" : frequency.label).fixedSize().padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin)
                    .background(YubaiColor.card, in: Capsule())
            }.accessibilityIdentifier("billCycleOther")
        }
    }
    private func cycleChip(_ value: Frequency) -> some View {
        Button { frequency = value } label: {
            Text(value.label).yubaiFont(YubaiFont.callout).fixedSize().padding(.horizontal, YubaiSpace.space12).frame(minHeight: YubaiSize.tapMin)
                .foregroundStyle(frequency == value ? YubaiColor.canvas : YubaiColor.label)
                .background(frequency == value ? YubaiColor.label : YubaiColor.card, in: Capsule())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("billCycle_" + value.rawValue)
            .accessibilityAddTraits(frequency == value ? .isSelected : [])
    }
    private var moreCard: some View {
        Card(style: .list) {
            DisclosureGroup("更多") {
                VStack(spacing: YubaiSpace.none) {
                    if planID == nil { Toggle("要收", isOn: $inflow).frame(minHeight: YubaiSize.buttonHeight) }
                    EntryFormRow(title: "分类") {
                        Picker("分类", selection: $category) {
                            ForEach(FixedFlows.categories(inflow: inflow, in: store.current), id: \.self) { Text(Classification.displayCategory($0)).tag($0) }
                        }.labelsHidden().accessibilityIdentifier("fixedFlowCategory")
                    }
                    Toggle("金额会变", isOn: Binding(get: { estimated }, set: { value in estimated = value; if value { autoPay = false } })).frame(minHeight: YubaiSize.buttonHeight).accessibilityIdentifier("fixedFlowEstimated")
                    Toggle("到日子自动记一笔", isOn: $autoPay).frame(minHeight: YubaiSize.buttonHeight).disabled(accountID == nil || estimated).accessibilityIdentifier("fixedFlowAutoPay")
                    if inflow { Toggle("到账放进存着不动", isOn: $intoFixedSavings).frame(minHeight: YubaiSize.buttonHeight).accessibilityIdentifier("fixedFlowIntoFixedSavings") }
                    Stepper(value: Binding(get: { installments ?? 0 }, set: { installments = $0 == 0 ? nil : $0 }), in: 0...2400) {
                        Text(installments.map { "共 \($0) 期" } ?? "一直")
                    }.frame(minHeight: YubaiSize.buttonHeight).accessibilityIdentifier("fixedFlowInstallments")
                }
            }.yubaiFont(YubaiFont.row).tint(YubaiColor.toggleOn).padding(.vertical, YubaiSpace.space8)
        }
    }
    private func load() {
        guard !initialized else { return }
        for rate in store.preferences.billExchangeRates ?? [] { rates[rate.currency] = rate.valueText }
        if let saved, let edit = FixedFlows.edit(planID: saved.id, in: store.current, now: store.financialNow) {
            title = edit.title; amount = Money.editableText(edit.amount); currency = saved.currency
            frequency = edit.frequency; date = edit.date; accountID = edit.accountID; category = edit.category
            inflow = edit.inflow; autoPay = edit.autoPay; estimated = edit.estimated
            intoFixedSavings = edit.intoFixedSavings; installments = edit.installments
        } else { date = store.financialNow; accountID = ManualBookkeeping.defaultAccount(in: store.current)?.id }
        initialSignature = signature; initialized = true
    }
    private func cancel() { if signature != initialSignature { confirmingDiscard = true } else { dismiss() } }
    private func save() {
        guard canSave, let amount = cents else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines), now = store.financialNow
        let newQuote = currency == .cny ? nil : self.quote(currency)
        if store.update(planID == nil ? "加上账单" : "改账单", entryMotion: false, { ledger in
            if let newQuote { try FixedFlows.setRate(newQuote, in: &ledger) }
            if let planID {
                do {
                    let change = try FixedFlows.update(planID: planID, title: name, amount: amount, frequency: frequency, date: date,
                                                  accountID: accountID, category: category, installments: installments, autoPay: autoPay, estimated: estimated,
                                                  in: ledger, now: now, intoFixedSavings: intoFixedSavings, currency: currency)
                    try change.apply(to: &ledger)
                } catch FixedFlowEditError.noChanges { }
            } else {
                var plan = Plan(title: name, amount: amount, dueDate: Dates.day(date), frequency: frequency, inflow: inflow,
                                category: category, nature: inflow ? .income : .expense, intoFixedSavings: intoFixedSavings)
                plan.currency = currency; plan.accountID = accountID; plan.installments = installments
                plan.estimated = estimated; plan.autoPay = autoPay; plan.autoPaySince = autoPay ? Dates.day(now) : nil
                plan.yearlyReserveSince = frequency == .yearly ? Dates.day(now) : nil
                let change = ChangeSet(source: "用户操作", reason: "加上账单", items: [.addPlan(plan)])
                try change.apply(to: &ledger)
            }
        }) { dismiss() }
    }
}
