import SwiftUI
import YubaiCore

struct LedgerHomeHeader: View {
    @Environment(AppStore.self) private var store
    let model: LedgerHomeModel
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.none) {
            if model.showsFormula {
                TabNavigationLink(.formula) { FormulaView() } label: { hero(disclosure: true) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("fundsFormula")
                    .accessibilityHint("点开看怎么算")
            } else { hero(disclosure: false) }
            if let fill = model.waterFill {
                WaterBar(fill: fill, tick: model.waterTick, fast: model.waterFast, hide: hide)
                    .padding(.top, YubaiSpace.space12)
            }
            if let total = model.savedTotal {
                TabNavigationLink(.saving) { SavingTabView() } label: { SavedPill(total: total, hide: hide) }
                    .buttonStyle(PressButtonStyle()).accessibilityIdentifier("openSaving")
                    .padding(.top, YubaiSpace.space6)
            }
            LedgerButlerLayer()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func hero(disclosure: Bool) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            AdaptiveValueRow(spreadsValue: false) {
                Text(model.headlineLabel).yubaiFont(YubaiFont.heroLabel)
                    .accessibilityIdentifier("ledgerHeroLabel")
            } value: {
                if let fact = model.gapBillText ?? (model.periodLine.isEmpty ? nil : model.periodLine) {
                    Text(HomeButler.privacyText(fact, hidden: hide)).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        .accessibilityIdentifier(model.gapBillText == nil ? "ledgerPeriod" : "ledgerGapBill")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space6) {
                AmountLabel(cents: model.headlineAmount, hide: hide, role: .hero, currency: true,
                            ink: model.headlineIsAmber ? YubaiColor.amberStrong : YubaiColor.label)
                    .accessibilityIdentifier("availableFunds")
                if disclosure { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary) }
            }
            if let status = model.statusLine {
                Text(HomeButler.privacyText(status, hidden: hide)).yubaiFont(YubaiFont.callout)
                    .foregroundStyle(YubaiColor.amberInk).accessibilityIdentifier("ledgerStatus")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

/// The Core queue supplies exactly one card; an empty slot has no spacing.
private struct LedgerButlerLayer: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if store.salaryPromptDue {
            QuestionCard(eyebrow: "", title: "每月几号发工资，发多少",
                         yesTitle: "填发薪日和工资", noTitle: "以后再说",
                         yesIdentifier: "setupFirstSalary", noIdentifier: "deferFirstSalary",
                         yes: { store.sheetSource = nil; store.sheet = .paydaySetup }, no: {
                _ = store.update("以后再说", recordUndo: false, entryMotion: false, showToast: false) {
                    FirstUse.deferSalarySetup(&$0, now: store.financialNow)
                }
            }).accessibilityIdentifier("firstSalaryCard").padding(.top, YubaiSpace.space16)
        } else if let receipt = store.homeReceipt {
            ButlerReceiptRow(receipt: receipt).padding(.top, YubaiSpace.space16)
                .task(id: receipt.id) {
                    #if DEBUG && targetEnvironment(simulator)
                    if UITestSupport.keepsUndoReceipt { return }
                    #endif
                    do { try await Task.sleep(for: .seconds(6)) } catch { return }
                    if store.homeReceipt?.id == receipt.id { store.homeReceipt = nil }
                }
        } else if (store.organizingPendingImports || store.organizingBatchID != nil) && (store.inboxItems.first?.id.hasPrefix("imports:") ?? true) {
            ImportBusyRow(pending: store.pendingOrganization).padding(.top, YubaiSpace.space16)
        } else if let first = store.inboxItems.first {
            HomeTaskCard(item: first).padding(.top, YubaiSpace.space16)
        }
    }
}
