import SwiftUI
import YubaiCore

// STUB: replaced whole-file by P1.
struct NowView: View {
    var body: some View {
        ScrollView { Text("") }.rootScrollContentMargins().rootTabScroll(.now)
            .rootPageHeader { RootHeader(title: "现在") }
            .navigationTitle("现在").yubaiNavigation()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
}
