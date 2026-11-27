import SwiftUI
import YubaiCore

typealias CardDismissAnimation = (@escaping () -> Bool) -> Void

/// Letter cards close only through ×. Their content keeps its existing actions.
struct LetterDismissCard<Content: View>: View {
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let onDismiss: () -> Bool
    var onMute: (() -> Bool)? = nil
    @ViewBuilder let content: (@escaping CardDismissAnimation) -> Content
    var body: some View {
        content { action in withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { _ = action() } }
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { _ = onDismiss() } } label: {
                    DSIconView(icon: .close, size: YubaiFont.callout.size, color: YubaiColor.labelSecondary)
                        .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).padding(YubaiSpace.space4).accessibilityLabel("收起").accessibilityIdentifier("dismissLetterCard")
            }
            .accessibilityAction(named: "收起") { _ = onDismiss() }
            .accessibilityAction(named: "以后别提") { _ = onMute?() }
    }
}

struct LetterDetailView: View {
    @Environment(AppStore.self) private var store
    let cardID: UUID
    var body: some View {
        WeeklyReviewView()
            .onAppear {
                if store.cards.first(where: { $0.id == cardID })?.dismissedAt == nil {
                    store.update("读过周回顾", recordUndo: false) { ledger in
                        if let i = ledger.cards.firstIndex(where: { $0.id == cardID }) { ledger.cards[i].dismissedAt = Dates.now }
                    }
                }
            }
    }
}
