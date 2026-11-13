import SwiftUI
import YubaiCore

/// 账本根页：账目 / 去向两个视图，页头固定，其他页带筛选跳进来时读 `store.ledgerPreset` 后清空。
struct LedgerTabView: View {
    @Environment(AppStore.self) private var store
    @State private var mode = LedgerMode.detail
    @State private var request: LedgerPreset?

    var body: some View {
        content
            .rootPageHeader { RootHeader(title: "账本") }
            .navigationTitle("账本").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .onChange(of: store.ledgerPreset, initial: true) { _, preset in
                guard let preset else { return }
                request = preset; mode = preset.mode; store.ledgerPreset = nil
            }
    }
    @ViewBuilder private var content: some View {
        switch mode {
        case .detail: EntriesView(mode: $mode, request: $request)
        case .whereTo: WhereView(mode: $mode, request: $request)
        }
    }
}
