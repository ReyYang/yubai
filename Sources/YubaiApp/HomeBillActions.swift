import SwiftUI
import YubaiCore

/// What the long-press menu lifts: the row's look and where it sits on screen.
struct BillMenuRequest: Equatable {
    let entryID: UUID
    let frame: CGRect
    let icon: DS.Icon
    let name: String
    let amount: String
    let detail: String?
    let detailAmount: String?
    let amountColor: Color
}

enum BillMenuAction { case edit, duplicate, recategorize }

extension AppStore {
    func perform(_ action: BillMenuAction, on entry: Entry) {
        switch action {
        case .edit: openBillEditor(entry)
        case .duplicate: openEntrySheet(QuickEntryPrefill(copying: entry, date: financialNow))
        case .recategorize: openBillEditor(entry, categoryOnly: true)
        }
    }

    /// One path for every bill deletion on home: swipe, long-press menu and the floating card.
    /// The shared undo toast names what went, so 撤销 says what it brings back.
    @discardableResult func deleteBill(_ entry: Entry) -> Bool {
        let label = "已删除 " + entry.displayTitle + " " + HomeDisplay.billAmount(entry, hidden: preferences.hideAmounts)
        guard update("删除", { try EntryRecovery.delete(entry.id, from: &$0, now: financialNow) }) else { return false }
        toast = label
        return true
    }
}

/// The long-press menu, above every page and the tab bar.
struct BillActionOverlays: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content
            .overlay {
                if !store.locked, let request = store.billMenu,
                   let entry = store.current.activeEntries.first(where: { $0.id == request.entryID }) {
                    HomeBillMenuOverlay(request: request, entry: entry, close: { store.billMenu = nil })
                        .id(request.entryID)
                }
            }
    }
}

/// Canvas Main.dc.html 长按菜单: the row lifts onto the scrim, the menu hangs under it.
struct HomeBillMenuOverlay: View {
    let request: BillMenuRequest
    let entry: Entry
    let close: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let card = CGRect(x: DS.Space.s16, y: request.frame.midY - origin.y - HomeSpec.menuCardHeight / 2,
                              width: geo.size.width - DS.Space.s16 * 2, height: HomeSpec.menuCardHeight)
            let menuHeight = DS.Size.rowSub * 4
            let below = card.maxY + HomeSpec.menuGap + menuHeight <= geo.size.height
            let menuY = below ? card.maxY + HomeSpec.menuGap : card.minY - HomeSpec.menuGap - menuHeight
            ZStack(alignment: .topLeading) {
                DS.Color.scrim.opacity(shown ? 1 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)
                lifted
                    .frame(width: card.width, height: card.height)
                    .scaleEffect(shown && !reduced ? HomeSpec.menuLift : 1)
                    .offset(x: card.minX, y: card.minY)
                menu
                    .scaleEffect(shown || reduced ? 1 : HomeSpec.menuScale,
                                 anchor: below ? .topLeading : .bottomLeading)
                    .opacity(shown ? 1 : 0)
                    .offset(x: card.minX, y: menuY)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismiss() }
        .sensoryFeedback(.impact(weight: .light), trigger: shown) { _, new in new }
        .onAppear { withAnimation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.snappyAnimation) { shown = true } }
    }

    private var lifted: some View {
        DSListRow(icon: request.icon, name: request.name, amount: request.amount, detail: request.detail,
                  separator: false, detailAmount: request.detailAmount, amountColor: request.amountColor)
            .padding(.horizontal, DS.Space.s16)
            .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
            .dsShadow(DS.Shadow.float)
            .accessibilityHidden(true)
    }

    private var menu: some View {
        VStack(spacing: .zero) {
            item("编辑", icon: .edit) { store.perform(.edit, on: entry) }
            item("再记一笔", icon: .duplicate) { store.perform(.duplicate, on: entry) }
            item("改分类", icon: .recategorize) { store.perform(.recategorize, on: entry) }
            item("删除", icon: .delete, tint: DS.Color.warnStrong, separator: false) { store.deleteBill(entry) }
        }
        .frame(width: DS.Size.menuW)
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .dsShadow(DS.Shadow.float)
    }

    private func item(_ title: String, icon: DS.Icon, tint: Color = DS.Color.ink, separator: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button {
            close()
            action()
        } label: {
            HStack(spacing: DS.Space.s12) {
                Text(title).dsText(DS.Font.tLabel).foregroundStyle(tint).dsFillWidth()
                icon.view(size: DS.Size.brandTile, color: tint)
            }
            .padding(.horizontal, DS.Space.s16)
            .frame(height: DS.Size.rowSub)
            .overlay(alignment: .bottom) {
                if separator {
                    DS.Color.separator.frame(height: DS.Stroke.hairline).padding(.leading, DS.Space.s16)
                }
            }
            .contentShape(Rectangle())
        }.dsPressStyle().accessibilityIdentifier("billMenu_" + title)
    }

    private func dismiss() {
        withAnimation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.snappyAnimation,
                      completionCriteria: .logicallyComplete) { shown = false } completion: { close() }
    }
}

/// The bill row's press: 0.97 while down, and holding 0.45 s opens the menu.
/// A press, not an extra gesture, so the List's swipe and scroll still own the drag.
struct BillRowPressStyle: ButtonStyle {
    let onHold: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        DSPressStyle().makeBody(configuration: configuration)
            .task(id: configuration.isPressed) {
                guard configuration.isPressed else { return }
                do { try await Task.sleep(for: .seconds(HomeSpec.longPress)) } catch { return }
                onHold()
            }
    }
}

/// Row frames for the long-press menu, written without invalidating the list.
final class BillRowFrames {
    var frames: [UUID: CGRect] = [:]
}

#if os(iOS)
extension DS.Icon {
    /// Swipe actions only draw `Image`; render the shared path once as a template.
    @MainActor func templateImage(size: CGFloat) -> Image {
        let renderer = ImageRenderer(content: DSIconView(icon: self, size: size, color: .black))
        renderer.scale = UITraitCollection.current.displayScale
        guard let image = renderer.uiImage else { return Image(uiImage: UIImage()) }
        return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
    }
}
#endif
