import SwiftUI
import YubaiCore

/// One home deletion that can still come back: its own ID, what it deleted and when its bar goes.
/// 撤销 restores exactly these entries, whatever else changed since.
struct BillUndoNotice: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let entryIDs: Set<UUID>
    let deletedAt: Date
    /// Wall-clock end of the 4-second bar; coming back from background keeps it.
    let deadline: Date
}

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

extension Entry {
    /// 改分类 only for a bill that has its own category: not a 转账, not a refund tied to another bill.
    /// The floating card, the long-press menu and VoiceOver all ask this.
    var canRecategorize: Bool { !nature.paired && relatedEntryID == nil }
}

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
        let at = financialNow
        var deleted: Set<UUID> = []
        guard update("删除", recordUndo: false, { deleted = try EntryRecovery.delete(entry.id, from: &$0, now: at) }) else { return false }
        clearUndo(); unsortedUndo = nil; toast = nil
        billUndo = BillUndoNotice(label: label, entryIDs: deleted, deletedAt: at, deadline: Date().addingTimeInterval(HomeSpec.undoBarSeconds))
        return true
    }

    /// 撤销 on one deletion's bar: brings back only that deletion, and only while it is the bar on screen.
    func undoBillDeletion(_ id: UUID) {
        guard let notice = billUndo, notice.id == id else { return }
        billUndo = nil
        // Already back (e.g. from 最近删除): the bar just goes, no error.
        if update("撤销", recordUndo: false, reportError: false, entryMotion: false, {
            try EntryRecovery.undoDelete(notice.entryIDs, deletedAt: notice.deletedAt, in: &$0)
        }) {
            undoTrigger &+= 1
            toast = "已撤销"
        }
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
    /// The menu as laid out: rows grow with large type, so its place is measured, not counted.
    @State private var measuredMenu: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let card = CGRect(x: DS.Space.s16, y: request.frame.midY - origin.y - HomeSpec.menuCardHeight / 2,
                              width: geo.size.width - DS.Space.s16 * 2, height: HomeSpec.menuCardHeight)
            let menuHeight = measuredMenu ?? DS.Size.rowSub * (entry.canRecategorize ? 4 : 3)
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
                    // Placed only once measured, so large type never shows it on the wrong side first.
                    .opacity(shown && measuredMenu != nil ? 1 : 0)
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
            if entry.canRecategorize {
                item("改分类", icon: .recategorize) { store.perform(.recategorize, on: entry) }
            }
            item("删除", icon: .delete, tint: DS.Color.warnStrong, separator: false) { store.deleteBill(entry) }
        }
        .frame(width: DS.Size.menuW)
        .fixedSize(horizontal: false, vertical: true)
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
        .dsShadow(DS.Shadow.float)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredMenu = $0 }
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
            .frame(minHeight: DS.Size.rowSub)
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
    var onPress: (Bool) -> Void = { _ in }

    func makeBody(configuration: Configuration) -> some View {
        DSPressStyle().makeBody(configuration: configuration)
            .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
            .task(id: configuration.isPressed) {
                guard configuration.isPressed else { return }
                do { try await Task.sleep(for: .seconds(HomeSpec.longPress)) } catch { return }
                onHold()
            }
    }
}

/// A bill row's tap and long press. Whether this press already opened the menu lives here,
/// per row, so a long press never re-renders the page.
struct HomeBillButton<Label: View>: View {
    let onTap: () -> Void
    let onHold: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var held = false
    @State private var release: Task<Void, Never>?

    var body: some View {
        Button {
            // The release of a long press already opened the menu; it is not a tap.
            if held { held = false } else { onTap() }
        } label: { label() }
        .buttonStyle(BillRowPressStyle(onHold: {
            held = true
            onHold()
        }, onPress: { pressed in
            release?.cancel()
            if pressed { held = false; return }
            // A press that slid off or became a scroll never fires the tap: forget the hold.
            release = Task { @MainActor in
                try? await Task.sleep(for: .seconds(HomeSpec.holdRelease))
                if !Task.isCancelled { held = false }
            }
        }))
    }
}

/// Row frames for the long-press menu, written without invalidating the list.
final class BillRowFrames {
    var frames: [UUID: CGRect] = [:]
}

extension DS.Icon {
    @MainActor private static var templates: [String: Image] = [:]

    /// Swipe actions only draw `Image`; render the shared path once per icon, size and scale as a template.
    @MainActor func templateImage(size: CGFloat, scale: CGFloat) -> Image {
        let key = "\(rawValue)@\(size)x\(scale)"
        if let cached = Self.templates[key] { return cached }
        let renderer = ImageRenderer(content: DSIconView(icon: self, size: size, color: .black))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return Image(size: CGSize(width: size, height: size)) { _ in } }
        let image = Image(decorative: cgImage, scale: scale).renderingMode(.template)
        Self.templates[key] = image
        return image
    }
}
