import SwiftUI
import YubaiCore

// STUB: replaced whole-file by P4.
struct SavingTabView: View {
    var body: some View {
        ScrollView { Text("") }.rootScrollContentMargins().rootTabScroll(.saving)
            .rootPageHeader { RootHeader(title: "存钱") }
            .navigationTitle("存钱").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
}
