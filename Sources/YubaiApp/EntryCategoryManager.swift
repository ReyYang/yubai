import SwiftUI
import YubaiCore

/// Canvas S-Cats / S-CatEdit: 分类管理, pushed from 全部分类 › 编辑. Back returns to the panel; the draft stays.
/// One List per page, so large type grows the rows and a long list scrolls while a row is dragged.
struct EntryCategoryManagerView: View {
    let model: EntrySheetViewModel
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.displayScale) private var displayScale
    @State private var direction: String
    @State private var editing: EditTarget?
    @State private var deleting: YubaiCore.Category?

    struct EditTarget: Equatable {
        let name: String?
        let income: Bool
    }

    init(model: EntrySheetViewModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        _direction = State(initialValue: model.draft.nature.categoryIncome ? Self.income : Self.expense)
    }

    private static let expense = "支出"
    private static let income = "收入"
    private var income: Bool { direction == Self.income }

    var body: some View {
        ZStack {
            list
            if let editing {
                EntryCategoryEditView(model: model, target: editing, back: { self.editing = nil })
                    .transition(reduced ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.smoothAnimation, value: editing)
    }

    private var list: some View {
        let categories = model.ledger.orderedCategories(income: income)
        // 其他支出 / 其他收入 is the catch-all: always last, never dragged.
        let movable = categories.filter { !$0.isCatchAll }
        let fixed = categories.filter(\.isCatchAll)
        let count = categories.count
        return VStack(spacing: .zero) {
            EntryPageHeader(title: "分类", back: close) {
                Button { editing = EditTarget(name: nil, income: income) } label: {
                    DS.Icon.add.view(size: EntrySpec.pageIcon, color: DS.Color.accentInk)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityLabel("新建分类")
            }
            List {
                DSSegmented(options: [Self.expense, Self.income], selection: $direction, width: nil)
                    .padding(.top, DS.Space.s8)
                    .padding(.bottom, DS.Space.s16)
                    .padding(.horizontal, DS.Space.s16)
                    .dsPlainRow()
                ForEach(Array(movable.enumerated()), id: \.element.id) { index, category in
                    categoryRow(category, index: index, count: count)
                        .nativeSwipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { deleting = category } label: {
                                Label { Text("删除") } icon: { DS.Icon.delete.templateImage(size: HomeSpec.swipeIcon, scale: displayScale) }
                            }
                            .tint(DS.Color.warnStrong)
                        }
                        // Dragging has no VoiceOver path of its own: move one place at a time.
                        .accessibilityActions {
                            if index > 0 { Button("上移") { move(movable, index, by: -1) } }
                            if index < movable.count - 1 { Button("下移") { move(movable, index, by: 1) } }
                        }
                }
                .onMove { from, to in
                    var names = movable.map(\.name)
                    names.move(fromOffsets: from, toOffset: to)
                    model.reorderVisibleCategories(names, income: income)
                }
                ForEach(fixed) { category in
                    categoryRow(category, index: count - 1, count: count)
                }
                Color.clear.frame(height: DS.Space.s28).dsPlainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .environment(\.defaultMinListRowHeight, .zero)
            .sensoryFeedback(DSMotion.Haptic.toggle, trigger: model.ledger.preferences.categoryOrder)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Color.bg.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .confirmationDialog(deleting.map { "删除「\($0.name)」？" } ?? "", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { category in
            Button("删除", role: .destructive) { model.deleteCategory(category.name, income: category.income) }
        } message: { category in
            Text("已记的 \(model.entryCount(category: category.name, income: category.income)) 笔改到「\(category.income ? "其他收入" : "其他支出")」")
        }
    }

    private func move(_ movable: [YubaiCore.Category], _ index: Int, by step: Int) {
        var names = movable.map(\.name)
        names.swapAt(index, index + step)
        model.reorderVisibleCategories(names, income: income)
    }

    private func categoryRow(_ category: YubaiCore.Category, index: Int, count: Int) -> some View {
        Button { editing = EditTarget(name: category.name, income: income) } label: {
            HStack(spacing: DS.Space.s12) {
                category.entryIcon.view(size: DS.Size.icon, color: DS.Color.ink2)
                    .frame(width: DS.Size.iconTile, height: DS.Size.iconTile)
                    .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                Text(category.name).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).dsFillWidth()
                if !category.subcategories.isEmpty {
                    Text("\(category.subcategories.count) 个小类").dsText(DS.Font.tSub).monospacedDigit()
                        .foregroundStyle(DS.Color.ink3).fixedSize()
                }
                if !category.isCatchAll {
                    DS.Icon.drag.view(size: EntrySpec.checkIcon, color: DS.Color.chevron)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, DS.Space.s16)
            .padding(.trailing, DS.Space.s12)
            .frame(minHeight: DS.Size.rowCat)
            .overlay(alignment: .bottom) {
                if index < count - 1 {
                    DS.Color.separator.frame(height: DS.Stroke.hairline)
                        .padding(.leading, DS.Space.s12)
                        .padding(.leading, DS.Size.iconTile)
                        .padding(.leading, DS.Space.s16)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EntryTactileButtonStyle())
        .dsCardRow(first: index == 0, last: index == count - 1)
        .accessibilityHint(category.isCatchAll ? "查看这个分类" : "编辑这个分类，按住拖动排序")
    }
}

/// Canvas S-CatEdit: name, subcategories (add, drag, swipe to remove) and 删除分类.
/// The catch-all (其他支出 / 其他收入) opens read-only.
private struct EntryCategoryEditView: View {
    let model: EntrySheetViewModel
    let target: EntryCategoryManagerView.EditTarget
    let back: () -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var name: String
    @State private var current: String?
    @State private var newSub = ""
    @State private var addingSub = false
    @State private var confirmDelete = false
    @State private var deletingSub: String?

    init(model: EntrySheetViewModel, target: EntryCategoryManagerView.EditTarget, back: @escaping () -> Void) {
        self.model = model
        self.target = target
        self.back = back
        _name = State(initialValue: target.name ?? "")
        _current = State(initialValue: target.name)
    }

    private var category: YubaiCore.Category? {
        guard let current else { return nil }
        return model.ledger.categories.first { $0.name == current && $0.income == target.income }
    }
    private var readOnly: Bool { category?.isCatchAll == true }
    private var fallback: String { target.income ? "其他收入" : "其他支出" }

    var body: some View {
        VStack(spacing: .zero) {
            EntryPageHeader(title: current == nil ? "新建分类" : readOnly ? current ?? "" : "编辑分类", back: finish) { EmptyView() }
            List {
                (category?.entryIcon ?? .catOther).view(size: EntrySpec.editIcon, color: DS.Color.accentInk)
                    .frame(width: EntrySpec.editCircle, height: EntrySpec.editCircle)
                    .background(DS.Color.accentSoft, in: Circle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s12)
                    .padding(.bottom, DS.Space.s20)
                    .accessibilityHidden(true)
                    .dsPlainRow()
                if !readOnly {
                    nameRow
                        .dsCardRow(first: true, last: true)
                }
                // The picks are expense icons; income categories keep theirs.
                if let category, !readOnly, !category.income {
                    iconGrid(category)
                        .padding(.vertical, DS.Space.s12)
                        .dsCardRow(first: true, last: true)
                        .padding(.top, DS.Space.s20)
                }
                if let category { subcategories(category) }
                if category != nil && !readOnly {
                    Button { confirmDelete = true } label: {
                        Text("删除分类").dsText(DS.Font.tBody).fontWeight(.semibold).foregroundStyle(DS.Color.warnStrong)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonH)
                            .dsPill()
                    }
                    .buttonStyle(EntryTactileButtonStyle())
                    .padding(.top, DS.Space.s20)
                    .padding(.horizontal, DS.Space.s16)
                    .dsPlainRow()
                }
                Color.clear.frame(height: DS.Space.s28).dsPlainRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, .zero)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Color.bg.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, finish)
        .confirmationDialog("删除「\(current ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: delete)
        } message: {
            Text("已记的 \(model.entryCount(category: current ?? "", income: target.income)) 笔改到「\(fallback)」")
        }
        .confirmationDialog(deletingSub.map { "删除「\($0)」？" } ?? "", isPresented: Binding(
            get: { deletingSub != nil }, set: { if !$0 { deletingSub = nil } }), titleVisibility: .visible, presenting: deletingSub) { sub in
            Button("删除", role: .destructive) { remove(sub) }
        } message: { sub in
            Text("已记的 \(model.entryCount(category: current ?? "", subcategory: sub, income: target.income)) 笔改到「\(current ?? "")」")
        }
    }

    /// Canvas S-CatEdit 图标: six to a row, 44 high, the picked one on accent-soft.
    private func iconGrid(_ category: YubaiCore.Category) -> some View {
        let picked = category.entryIcon
        // Spec-Issues 4: every category's icon is its own — one another category shows cannot be picked.
        let taken = Set(model.ledger.categories.filter { $0.income == category.income && !$0.system && $0.name != category.name }.map(\.entryIcon))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s8), count: EntrySpec.iconColumns),
                         spacing: DS.Space.s8) {
            ForEach(DS.Icon.categoryChoices, id: \.self) { icon in
                let on = icon == picked
                let used = taken.contains(icon) && !on
                Button { pick(icon) } label: {
                    icon.view(size: DS.Size.icon, color: on ? DS.Color.accentInk : DS.Color.ink2)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.tapMin)
                        .background(on ? DS.Color.accentSoft : DS.Color.surface,
                                    in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
                }
                .buttonStyle(EntryTactileButtonStyle(haptic: DSMotion.Haptic.toggle))
                .disabled(used)
                .opacity(used ? SettingsSpec.disabledOpacity : 1)
                .accessibilityLabel(icon.choiceName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, DS.Space.s12)
    }

    private func pick(_ icon: DS.Icon) {
        guard let current else { return }
        let income = target.income
        model.mutateLedger("分类图标") { try CategoryModel.setIcon(icon.rawValue, category: current, income: income, in: &$0) }
    }

    private var nameRow: some View {
        HStack(spacing: .zero) {
            Text("名字").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink3)
                .frame(width: EntrySpec.editLabel, alignment: .leading)
            DSInlineTextField(title: "名字", text: $name, autoFocus: current == nil, onSubmit: commitName)
                .submitLabel(.done)
        }
        .padding(.horizontal, DS.Space.s16)
        .frame(minHeight: EntrySpec.accountRow)
    }

    @ViewBuilder private func subcategories(_ category: YubaiCore.Category) -> some View {
        let subs = category.subcategories
        let rows = subs.count + (readOnly ? 0 : 1)
        if rows > 0 {
            Text("小类").dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink3)
                .padding(.horizontal, DS.Space.s20)
                .padding(.top, DS.Space.s20)
                .padding(.bottom, DS.Space.s8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .dsPlainRow()
            ForEach(Array(subs.enumerated()), id: \.element) { index, sub in
                HStack {
                    Text(sub).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink).dsFillWidth()
                    if !readOnly {
                        DS.Icon.drag.view(size: EntrySpec.checkIcon, color: DS.Color.chevron).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, DS.Space.s16)
                .frame(minHeight: EntrySpec.listRow)
                .overlay(alignment: .bottom) {
                    if index < rows - 1 {
                        DS.Color.separator.frame(height: DS.Stroke.hairline).padding(.leading, DS.Space.s16)
                    }
                }
                .dsCardRow(first: index == 0, last: index == rows - 1)
                .modifier(EntrySubSwipe(enabled: !readOnly, scale: displayScale) { deletingSub = sub })
            }
            .onMove(perform: readOnly ? nil : { from, to in
                var moved = subs
                moved.move(fromOffsets: from, toOffset: to)
                reorder(moved)
            })
            if !readOnly {
                addRow.dsCardRow(first: subs.isEmpty, last: true)
            }
        }
    }

    @ViewBuilder private var addRow: some View {
        if addingSub {
            DSInlineTextField(title: "添加小类", text: $newSub, onSubmit: addSub)
                .submitLabel(.done)
                .padding(.horizontal, DS.Space.s8)
                .frame(minHeight: EntrySpec.listRow)
        } else {
            Button { addingSub = true } label: {
                HStack(spacing: DS.Space.s12) {
                    DS.Icon.add.view(size: EntrySpec.checkIcon, color: DS.Color.accentInk)
                    Text("添加小类").dsText(DS.Font.tLabelStrong).foregroundStyle(DS.Color.accentInk).dsFillWidth()
                }
                .padding(.horizontal, DS.Space.s16)
                .frame(minHeight: EntrySpec.listRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(EntryTactileButtonStyle())
        }
    }

    private func finish() {
        if !readOnly { commitName() }
        back()
    }

    private func commitName() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != current else { return }
        let income = target.income
        if let old = current {
            if model.mutateLedger("编辑分类", { try CategoryModel.rename(old, to: cleaned, income: income, in: &$0) }) {
                if model.draftUses(category: old, income: income) { model.draft.category = cleaned }
                current = cleaned
            }
        } else {
            // Every category gets its own icon (Spec-Issues 4).
            var added = YubaiCore.Category(cleaned, income: income)
            added.icon = DS.Icon.newCategoryIcon(name: cleaned, income: income, in: model.ledger)
            if model.mutateLedger("添加分类", { try CategoryModel.add(added, in: &$0) }) { current = cleaned }
        }
    }

    private func addSub() {
        let cleaned = newSub.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current, !cleaned.isEmpty else { addingSub = false; return }
        let income = target.income
        if model.mutateLedger("添加小类", { try CategoryModel.addSubcategory(cleaned, to: current, income: income, in: &$0) }) {
            newSub = ""
            addingSub = false
        }
    }

    private func remove(_ sub: String) {
        guard let current else { return }
        let income = target.income
        if model.mutateLedger("删除小类", { try CategoryModel.removeSubcategory(sub, from: current, income: income, in: &$0) }),
           model.draftUses(category: current, income: income), model.draft.subcategory == sub {
            model.draft.subcategory = nil
        }
    }

    private func reorder(_ subs: [String]) {
        guard let current else { return }
        let income = target.income
        model.mutateLedger("小类排序") { ledger in
            guard let index = ledger.categories.firstIndex(where: { $0.name == current && $0.income == income }) else { return }
            ledger.categories[index].subcategories = subs
        }
    }

    private func delete() {
        guard let current else { return }
        if model.deleteCategory(current, income: target.income) { back() }
    }
}

/// A subcategory's swipe: 删除 asks first, so a full swipe never removes it.
private struct EntrySubSwipe: ViewModifier {
    let enabled: Bool
    let scale: CGFloat
    let delete: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.nativeSwipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: delete) {
                    Label { Text("删除") } icon: { DS.Icon.delete.templateImage(size: HomeSpec.swipeIcon, scale: scale) }
                }
                .tint(DS.Color.warnStrong)
            }
        } else {
            content
        }
    }
}

extension View {
    /// A List row that draws nothing of its own: spacing, headers, the segmented control.
    func dsPlainRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// A row of a raised, radius-m group 16 in from each edge; the group's ends round.
    func dsCardRow(first: Bool, last: Bool) -> some View {
        let radius = DS.Radius.m
        return listRowInsets(EdgeInsets(top: .zero, leading: DS.Space.s16, bottom: .zero, trailing: DS.Space.s16))
            .listRowSeparator(.hidden)
            .listRowBackground(
                UnevenRoundedRectangle(topLeadingRadius: first ? radius : .zero, bottomLeadingRadius: last ? radius : .zero,
                                       bottomTrailingRadius: last ? radius : .zero, topTrailingRadius: first ? radius : .zero,
                                       style: .continuous)
                    .fill(DS.Color.raised)
                    .padding(.horizontal, DS.Space.s16)
            )
    }
}

/// Main.dc.html 推进来的页面: back, a centered title, one trailing control.
struct EntryPageHeader<Trailing: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text(title).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: back) {
                    DS.Icon.back.view(size: EntrySpec.pageIcon, color: DS.Color.ink)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityLabel("返回")
                Spacer()
                trailing()
            }
        }
        .frame(height: DS.Size.tapMin)
        .padding(.horizontal, DS.Space.s8)
    }
}

extension DS.Icon {
    /// The icon a new category starts with: what its name already means, if no other category shows it;
    /// else the first pick no other expense category shows. Income categories keep their own icons.
    static func newCategoryIcon(name: String, income: Bool, in ledger: Ledger) -> String? {
        let taken = Set(ledger.categories.filter { $0.income == income && !$0.system }.map(\.entryIcon))
        let natural = DS.Icon(category: name, symbol: YubaiCore.Category(name).symbol, income: income)
        if natural != .catOther && !taken.contains(natural) { return nil }
        guard !income else { return nil }
        return categoryChoices.first { !taken.contains($0) && $0 != .catOther }?.rawValue
    }

}
