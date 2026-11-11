import SwiftUI
import YubaiCore

// STUB: replaced whole-file by P4.
struct YubaiTabView: View {
    var body: some View {
        ScrollView { Text("") }.rootScrollContentMargins().rootTabScroll(.yubai)
            .rootPageHeader { RootHeader(title: "余白") }
            .navigationTitle("余白").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
}
