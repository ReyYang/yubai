import SwiftUI
import YubaiCore
#if os(iOS)
import UIKit
#endif

/// 「全部」格和「更多」芯片共用的选分类页：常用在上，全部在下，点一颗就选中并回去。
struct EntryMoreCategorySheet: View {
    @Environment(AppStore.self) private var store
    let income: Bool
    let selection: CategoryAssignment
    var suggestionOnly = false
    var suggested: String? = nil
    let choose: (CategoryAssignment) -> Void
    let dismiss: () -> Void
    @State private var managing = false
    private var selected: CategoryAssignment? {
        suggestionOnly || selection.category.isEmpty || Classification.isPending(selection.category) ? nil : selection
    }
    var body: some View {
        NavigationStack {
            Page(topPadding: YubaiSpace.space8) {
                CategoryPicker(income: income, selected: selected, suggested: suggested,
                               identifier: "entryMore", style: .entry) { choice, addition in
                    if let addition, !store.update("添加分类", { try addition.apply(to: &$0) }) { return false }
                    choose(choice); return true
                }
            }.accessibilityIdentifier("entryCategoryPicker").manualSheetNavigation()
                .safeAreaInset(edge: .top) {
                    ManualSheetHeader(title: "选分类", actionTitle: "管理", primary: false, cancelTitle: "返回",
                                      actionIdentifier: "entryMoreManage", cancelIdentifier: "entryMoreCancel",
                                      cancel: dismiss, action: { managing = true }).padding(.horizontal, YubaiSpace.space20)
                }
        }.environment(store).appErrors().presentationDragIndicator(.visible).yubaiSheetBackground()
            .sheet(isPresented: $managing) {
                NavigationStack { CategoriesView().manualSheetHeader("分类", cancelTitle: "关闭", showsAction: false) }
                    .environment(store).appErrors().yubaiSheetBackground()
            }
    }
}

private struct EntryDiscardGuard: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let dirty: Bool
    let amount: Int64
    @Binding var confirming: Bool
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(dirty)
            .accessibilityAction(.escape) {
                if dirty { confirming = true } else { dismiss() }
            }
            #if os(iOS)
            .background { DismissAttempt(dirty: dirty) { confirming = true }.frame(width: YubaiSpace.none, height: YubaiSpace.none) }
            #elseif os(macOS)
            .onExitCommand { if dirty { confirming = true } else { dismiss() } }
            #endif
            .sheet(isPresented: $confirming) {
                ConfirmationSheet(title: amount == 0 ? "放弃修改？" : "已经填了 \(Money.text(amount, currency: false)) 元") {
                    Button("放弃这笔") { confirming = false; dismiss() }.buttonStyle(DestructiveButtonStyle())
                }
            }
    }
}

#if os(iOS)
private struct DismissAttempt: UIViewControllerRepresentable {
    var dirty: Bool
    var attempt: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.dirty = dirty; controller.attempt = attempt
        DispatchQueue.main.async { controller.install() }
    }
    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var dirty = false
        var attempt: () -> Void = {}
        weak var previousDelegate: UIAdaptivePresentationControllerDelegate?
        weak var attachedPresentation: UIPresentationController?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false; view.accessibilityElementsHidden = true }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        func install() {
            var host: UIViewController? = self
            while let current = host {
                if let presentation = current.presentationController, current.presentingViewController != nil {
                    if presentation.delegate !== self {
                        previousDelegate = presentation.delegate; presentation.delegate = self
                    }
                    attachedPresentation = presentation; break
                }
                host = current.parent
            }
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !dirty && (previousDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            previousDelegate?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            previousDelegate?.presentationControllerDidDismiss?(presentationController)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if dirty { attempt() } else { previousDelegate?.presentationControllerDidAttemptToDismiss?(presentationController) }
        }
    }
}
#endif

extension View {
    func entryDiscardGuard(dirty: Bool, amount: Int64, confirming: Binding<Bool>) -> some View {
        modifier(EntryDiscardGuard(dirty: dirty, amount: amount, confirming: confirming))
    }
    func manualSheetNavigation() -> some View {
        self.paperBackground().environment(\.yubaiFormSurface, true)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
    }
}

private struct RootTabScroll: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    let tab: Destination
    #if os(iOS)
    @State private var position = ScrollPosition(edge: .top)
    #endif
    func body(content: Content) -> some View {
        #if os(iOS)
        content.scrollPosition($position).onChange(of: store.rootScrollRequest[tab]) { _, _ in
            withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { position.scrollTo(edge: .top) }
        }
        #else
        content
        #endif
    }
}
extension View {
    @ViewBuilder func rootTabScroll(_ tab: Destination?) -> some View {
        if let tab { modifier(RootTabScroll(tab: tab)) }
        else { self }
    }
}

// MARK: - Round 45 entry components
