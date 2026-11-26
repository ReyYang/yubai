import SwiftUI
import YubaiCore

struct OnboardingAccount: Identifiable, Equatable {
    var id = UUID()
    var type: AccountType
    var name: String
    /// Typed as a positive number; a credit card's is the amount owed.
    var amount: Int64?
    var selected: Bool
}

/// What first open collects before the one save.
@MainActor @Observable final class OnboardingDraft {
    var step = 1
    var day = Payday.defaultDay
    var takeHome: Int64 = 0
    var saving: Int64 = 0
    var floor: Int64?
    var focusSaving = false
    var editing: UUID?
    var accounts: [OnboardingAccount] = [
        .init(type: .debit, name: "储蓄卡", selected: false), .init(type: .alipay, name: "支付宝", selected: false),
        .init(type: .wechat, name: "微信零钱", selected: false), .init(type: .credit, name: "信用卡", selected: false),
        .init(type: .cash, name: "现金", selected: false),
    ]

    func upsert(_ account: OnboardingAccount) {
        if let editing, let index = accounts.firstIndex(where: { $0.id == editing }) {
            accounts[index].type = account.type; accounts[index].name = account.name
            accounts[index].amount = account.amount; accounts[index].selected = true
        } else {
            accounts.append(account)
        }
        editing = nil
    }

    var liquidCash: Int64 {
        accounts.filter { $0.selected && $0.type.kind != .credit && $0.type.kind != .investment }.reduce(0) { $0 + ($1.amount ?? 0) }
    }
}

/// 首次打开: payday, 先攒, accounts. One save at the end, then home.
struct OnboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride
    @State private var forward = true

    private var reduced: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let _ = SettingsRenderCounts.hit("onboardBody")
        let draft = store.onboarding
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: .zero) {
                topBar(step: draft.step)
                Text(["哪天发工资？", "每月先攒多少？", "钱都放在哪？"][max(0, min(2, draft.step - 1))])
                    .dsText(SettingsSpec.onboardTitle).foregroundStyle(DS.Color.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, SettingsSpec.titleSide).padding(.top, DS.Space.s20)
                    .contentTransition(.opacity)
                Group {
                    switch draft.step {
                    case 1: OnboardPayday(draft: draft, now: store.financialNow)
                    case 2: OnboardSaving(draft: draft, hidden: store.preferences.hideAmounts)
                    default: OnboardAccounts(draft: draft, hidden: store.preferences.hideAmounts)
                    }
                }
                .id(draft.step)
                .transition(reduced ? .opacity : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                                              removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                Spacer(minLength: .zero)
            }
            VStack(spacing: .zero) {
                DSButton(draft.step == 3 ? "开始用余白" : "下一步", enabled: canContinue(draft)) { next(draft) }
                    .accessibilityIdentifier("onboardNext")
                    .padding(.horizontal, DS.Space.s20)
                    .padding(.bottom, draft.step == 2 ? OverviewSpec.valuationApplyTop : SettingsSpec.buttonBottom)
                if draft.step == 2 {
                    DSKeypad(onKey: { press($0, draft) }, variant: .digits)
                        .frame(height: OverviewSpec.valuationTrayHeight, alignment: .top)
                        .background(DS.Color.tray)
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(DS.Color.bg.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardScene")
    }

    private func topBar(step: Int) -> some View {
        HStack(spacing: DS.Space.s12) {
            Button { back() } label: {
                DSIconView(icon: .back, size: HomeSpec.navIcon, color: DS.Color.ink)
                    .frame(width: DS.Size.tapMin, height: DS.Size.tapMin).contentShape(Rectangle())
            }
            .dsPressStyle().opacity(step == 1 ? .zero : 1).disabled(step == 1)
            .accessibilityHidden(step == 1).accessibilityLabel("上一步").accessibilityIdentifier("onboardBack")
            HStack(spacing: SettingsSpec.progressGap) {
                ForEach(1...3, id: \.self) { index in
                    Capsule(style: .continuous).fill(index <= step ? DS.Color.accent : DS.Color.track).frame(height: SettingsSpec.progressHeight)
                }
            }
            .padding(.trailing, SettingsSpec.progressTrailing)
            .accessibilityElement(children: .ignore).accessibilityLabel("第 \(step) 步，共 3 步")
        }
        .padding(.horizontal, DS.Space.s8).frame(height: DS.Size.tapMin)
    }

    private func canContinue(_ draft: OnboardingDraft) -> Bool {
        switch draft.step {
        case 2: draft.saving <= draft.takeHome || draft.takeHome == 0
        default: true
        }
    }

    private func next(_ draft: OnboardingDraft) {
        guard draft.step == 3 else { move(to: draft.step + 1, draft); return }
        guard store.settingsFixture == nil else { return }
        let accounts = draft.accounts.filter(\.selected).map {
            Accounts.Draft(name: $0.name, kind: $0.type.kind, balance: ($0.type == .credit ? -1 : 1) * ($0.amount ?? 0))
        }
        let day = draft.day, takeHome = draft.takeHome, saving = draft.saving, floor = draft.floor, now = store.financialNow
        _ = store.update("开始用余白", recordUndo: false, entryMotion: false, showToast: false) { ledger in
            try Onboarding.finish(day: day, takeHome: takeHome, saving: saving, floor: floor, accounts: accounts, in: &ledger, now: now)
        }
    }

    private func back() {
        let draft = store.onboarding
        guard draft.step > 1 else { return }
        move(to: draft.step - 1, draft)
    }

    private func move(to step: Int, _ draft: OnboardingDraft) {
        forward = step > draft.step
        withAnimation(reduced ? nil : DSMotion.smoothAnimation) { draft.step = step }
    }

    private func press(_ key: String, _ draft: OnboardingDraft) {
        var keypad = EntryKeypad(amount: draft.focusSaving ? draft.saving : draft.takeHome)
        if (draft.focusSaving ? draft.saving : draft.takeHome) == 0 { keypad.reset() }
        keypad.press(key)
        let value = keypad.amount ?? 0
        if draft.focusSaving { draft.saving = value } else { draft.takeHome = value }
    }
}

private struct OnboardPayday: View {
    let draft: OnboardingDraft
    let now: Date

    var body: some View {
        let cycle = CycleStart.cycle(day: draft.day, weekendShift: false, now: now)
        let total = Double(max(1, days(cycle.start, Dates.addDays(1, to: cycle.end))))
        let elapsed = Double(days(cycle.start, Dates.day(now)))
        let left = days(Dates.day(now), cycle.end)
        VStack(spacing: .zero) {
            DSDayGrid(selection: draft.day, cellHeight: SettingsSpec.onboardDayCell, identifier: "onboardDay_") { draft.day = $0 }
            VStack(spacing: .zero) {
                HStack(alignment: .firstTextBaseline) {
                    Text("第一个周期").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                    Spacer(minLength: DS.Space.s8)
                    Text(SettingsDisplay.range(cycle.start, cycle.end)).dsText(DS.Font.tTitle).monospacedDigit().foregroundStyle(DS.Color.ink)
                }
                GeometryReader { geometry in
                    Capsule(style: .continuous).fill(DS.Color.track)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(DS.Color.accent).frame(width: geometry.size.width * min(1, (elapsed + 1) / total))
                        }
                        .clipShape(Capsule(style: .continuous))
                }.frame(height: SettingsSpec.previewBar).padding(.top, DS.Space.s12)
                HStack {
                    Text(SettingsDisplay.monthDay(cycle.start))
                    Spacer(minLength: DS.Space.s4)
                    Text("今天 · 还剩 \(left) 天")
                    Spacer(minLength: DS.Space.s4)
                    Text(SettingsDisplay.monthDay(cycle.end))
                }.dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3).padding(.top, SettingsSpec.labelsTop)
            }
            .padding(DS.Space.s16)
            .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline) }
            .padding(.top, DS.Space.s28)
            .accessibilityElement(children: .combine).accessibilityIdentifier("onboardFirstCycle")
        }
        .padding(.horizontal, DS.Space.s20).padding(.top, SettingsSpec.titleSide)
    }

    private func days(_ from: Date, _ to: Date) -> Int { Dates.calendar.dateComponents([.day], from: Dates.day(from), to: Dates.day(to)).day ?? 0 }
}

private struct OnboardSaving: View {
    let draft: OnboardingDraft
    let hidden: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        let chips = SettingsSummary.savingChips(takeHome: draft.takeHome)
        let custom = draft.saving > 0 && !chips.contains(draft.saving)
        VStack(spacing: SettingsSpec.balanceTop) {
            Button { draft.focusSaving = false } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("每月到手").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2)
                    Spacer(minLength: DS.Space.s8)
                    Text(OverviewDisplay.money(draft.takeHome, hidden: hidden)).dsText(DS.Font.nSpineLg).foregroundStyle(DS.Color.ink)
                    if !draft.focusSaving { caret }
                }
                .padding(.horizontal, DS.Space.s16).frame(maxWidth: .infinity, minHeight: SettingsSpec.incomeBox)
                .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .strokeBorder(draft.focusSaving ? DS.Color.separator : DS.Color.accent, lineWidth: draft.focusSaving ? DS.Stroke.hairline : SettingsSpec.savingBorder)
                }
                .contentShape(Rectangle())
            }.dsPressStyle().accessibilityIdentifier("onboardTakeHome")
            VStack(spacing: .zero) {
                HStack(alignment: .firstTextBaseline) {
                    Text("每月先攒").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk)
                    Spacer(minLength: DS.Space.s8)
                    Text(OverviewDisplay.money(draft.saving, hidden: hidden)).dsText(DS.Font.nSpineLg).foregroundStyle(DS.Color.ink)
                        .accessibilityIdentifier("onboardSavingAmount")
                    if draft.focusSaving { caret }
                }
                if draft.takeHome > 0 {
                    DSSplitBar(share: Double(draft.saving) / Double(draft.takeHome)).padding(.top, SettingsSpec.chipsTop)
                    HStack {
                        Text("先攒 " + OverviewDisplay.share(draft.saving, of: draft.takeHome))
                        Spacer(minLength: DS.Space.s8)
                        Text("留给花 " + OverviewDisplay.money(draft.takeHome - draft.saving, hidden: hidden))
                    }.dsText(DS.Font.tCaption).monospacedDigit().foregroundStyle(DS.Color.ink3).padding(.top, SettingsSpec.labelsTop)
                }
                SettingsChips(chips: chips.map { .init(id: "\($0)", title: OverviewDisplay.money($0, hidden: hidden), selected: $0 == draft.saving) }
                              + (custom ? [.init(id: "\(draft.saving)", title: OverviewDisplay.money(draft.saving, hidden: hidden), selected: true)] : []),
                              outlined: true) { id in draft.saving = Int64(id) ?? 0; draft.focusSaving = true }
                    .padding(.top, SettingsSpec.chipsTop)
            }
            .padding(.horizontal, DS.Space.s16).padding(.vertical, SettingsSpec.amountVertical)
            .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .strokeBorder(draft.focusSaving ? DS.Color.accent : DS.Color.separator, lineWidth: draft.focusSaving ? SettingsSpec.savingBorder : DS.Stroke.hairline)
            }
            .contentShape(Rectangle())
            .onTapGesture { draft.focusSaving = true }
            Button { store.settingsSheet = .onboardFloor } label: {
                HStack(spacing: DS.Space.s8) {
                    Text("底线存款").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink2)
                    Spacer(minLength: DS.Space.s8)
                    Text(draft.floor.map { OverviewDisplay.money($0, hidden: hidden) } ?? "稍后再设").dsText(DS.Font.tLabel).monospacedDigit().foregroundStyle(DS.Color.ink3)
                    DSIconView(icon: .chevron, size: SettingsSpec.linkIcon, color: DS.Color.ink3)
                }
                .padding(.horizontal, DS.Space.s4).frame(minHeight: SettingsSpec.floorRow)
                .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                .contentShape(Rectangle())
            }.dsPressStyle().accessibilityIdentifier("onboardFloor")
        }
        .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s20)
    }

    private var caret: some View {
        Capsule(style: .continuous).fill(DS.Color.accent).frame(width: SettingsSpec.markerWidth, height: SettingsSpec.caretHeight)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            .accessibilityHidden(true)
    }
}

private struct OnboardAccounts: View {
    let draft: OnboardingDraft
    let hidden: Bool
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: .zero) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SettingsSpec.accountGap), count: SettingsSpec.onboardColumns),
                      spacing: SettingsSpec.accountGap) {
                ForEach(draft.accounts) { account in tile(account) }
                Button {
                    draft.editing = nil
                    store.settingsSheet = .accountAdd(.debit, onboarding: true)
                } label: {
                    VStack(alignment: .leading, spacing: .zero) {
                        DSIconView(icon: .add, size: SettingsSpec.typeIcon, color: DS.Color.accentInk)
                        Spacer(minLength: .zero)
                        Text("其他账户").dsText(SettingsSpec.tileName).foregroundStyle(DS.Color.accentInk)
                    }
                    .padding(.horizontal, SettingsSpec.cardInset).padding(.vertical, DS.Space.s12)
                    .frame(maxWidth: .infinity, minHeight: SettingsSpec.accountTile, alignment: .leading)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                            .strokeBorder(DS.Color.separator, style: StrokeStyle(lineWidth: DS.Stroke.focus, dash: SettingsSpec.dash))
                    }
                    .contentShape(Rectangle())
                }.dsPressStyle().accessibilityIdentifier("onboardOtherAccount")
            }
            HStack(alignment: .firstTextBaseline) {
                Text("流动现金").dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3)
                Spacer(minLength: DS.Space.s8)
                Text(OverviewDisplay.money(draft.liquidCash, hidden: hidden, currency: true)).dsText(OverviewSpec.saved).foregroundStyle(DS.Color.accentInk)
                    .contentTransition(.numericText(value: Double(draft.liquidCash)))
                    .accessibilityIdentifier("onboardLiquidCash")
            }
            .padding(.horizontal, DS.Space.s4).padding(.top, SettingsSpec.amountVertical)
            .overlay(alignment: .top) { DS.Color.ink.frame(height: DS.Stroke.hairline) }
            .padding(.top, DS.Space.s20)
        }
        .padding(.horizontal, DS.Space.s20).padding(.top, DS.Space.s20)
    }

    private func tile(_ account: OnboardingAccount) -> some View {
        Button {
            if !account.selected, let index = draft.accounts.firstIndex(where: { $0.id == account.id }) {
                draft.accounts[index].selected = true
            } else if account.amount == nil {
                draft.editing = account.id
                store.settingsSheet = .accountAdd(account.type, onboarding: true)
            } else if let index = draft.accounts.firstIndex(where: { $0.id == account.id }) {
                draft.accounts[index].selected = false
            }
        } label: {
            VStack(alignment: .leading, spacing: .zero) {
                DSIconView(icon: account.type.icon, size: SettingsSpec.typeIcon, color: account.selected ? DS.Color.accentInk : DS.Color.ink3)
                Spacer(minLength: .zero)
                Text(account.name).dsText(SettingsSpec.tileName).foregroundStyle(account.selected ? DS.Color.ink : DS.Color.ink2).lineLimit(1)
                if let amount = account.amount {
                    Text((account.type == .credit ? "欠 " : "") + OverviewDisplay.money(amount, hidden: hidden))
                        .dsText(DS.Font.tSubStrong).monospacedDigit().foregroundStyle(DS.Color.ink).padding(.top, OverviewSpec.headingGap)
                }
            }
            .padding(.horizontal, SettingsSpec.cardInset).padding(.vertical, DS.Space.s12)
            .frame(maxWidth: .infinity, minHeight: SettingsSpec.accountTile, alignment: .leading)
            .background(account.selected ? DS.Color.raised : .clear, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .strokeBorder(account.selected ? DS.Color.accent : DS.Color.separator, lineWidth: account.selected ? DS.Stroke.focus : DS.Stroke.hairline)
            }
            .overlay(alignment: .topTrailing) {
                if account.selected {
                    DSIconView(icon: .done, size: SettingsSpec.badgeIcon, color: DS.Color.onAccent)
                        .frame(width: SettingsSpec.badge, height: SettingsSpec.badge)
                        .background(DS.Color.accent, in: Circle())
                        .padding(DS.Space.s12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .dsPressStyle()
        .accessibilityAddTraits(account.selected ? .isSelected : [])
        .accessibilityIdentifier("onboardAccount_" + account.name)
    }
}
