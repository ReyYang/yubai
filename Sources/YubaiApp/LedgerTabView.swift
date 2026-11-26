import SwiftUI
import YubaiCore

/// The ledger is the home. Presets only select entries; insights has its own tab.
struct LedgerTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @State private var request: LedgerPreset?
    @State private var mountedRevision: UInt64

    init(navigationRevision: UInt64) {
        _mountedRevision = State(initialValue: navigationRevision)
    }
    var body: some View {
        let isFirstOpen = store.homeHero.isFirstOpen
        Group {
            if isFirstOpen {
                VStack(spacing: .zero) {
                    HomeTopBar { store.tabRouteRequest = .settings }
                    FirstOpenView()
                }.transition(.opacity)
            }
            else { HomeView(request: request).transition(.opacity) }
        }.animation(DSMotion.reduceMotionAnimation, value: isFirstOpen)
            .navigationTitle("账本").yubaiNavigation().amountPrivacy(store.preferences.hideAmounts)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: store.ledgerPreset, initial: true) { _, preset in
                applyPreset(preset)
            }
    }
    private func applyPreset(_ preset: LedgerPreset?) {
        // resetRootNavigation replaces the root, but its outgoing ledger can
        // still observe the new preset. It must not consume a request intended
        // for the replacement. State retains this consumer's mounted revision
        // even if SwiftUI updates its initializer before removing it.
        guard mountedRevision == store.navigationRevision,
              let preset, store.ledgerPreset == preset else { return }
        if preset.mode == .whereTo { store.destination = .insights }
        else { request = preset }
        store.ledgerPreset = nil
    }
}
