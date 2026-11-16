import SwiftUI
import YubaiCore

/// The ledger is the home. Presets only select entries; insights has its own tab.
struct LedgerTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @State private var request: LedgerPreset?
    var body: some View {
        let model = LedgerHomeModel.make(store)
        Group {
            if model.isFirstOpen { FirstOpenView().transition(.opacity) }
            else { EntriesView(request: $request).transition(.opacity) }
        }.animation(reduceMotion ? nil : .easeInOut(duration: YubaiMotion.durationFirstLight), value: model.isFirstOpen)
            .navigationTitle("账本").yubaiNavigation().amountPrivacy(store.preferences.hideAmounts)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: store.ledgerPreset, initial: true) { _, preset in
                guard let preset else { return }
                if preset.mode == .whereTo { store.destination = .insights }
                else { request = preset }
                store.ledgerPreset = nil
            }
    }
}
