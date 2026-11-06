import SwiftUI
import YubaiCore

/// The shared two-step picker. The caller commits additions and assignments in
/// its own transaction, so quick sorting retains one save and one undo.
struct CategoryPicker: View {
    enum Style { case grid, sections }
    @Environment(AppStore.self) private var store
    let income: Bool
    var selected: CategoryAssignment? = nil
    var suggested: String? = nil
    var applyingCount = 0
    var identifier = "categoryPicker"
    var style = Style.grid
    let choose: (CategoryAssignment, CategoryAddition?) -> Bool
    @State private var expanded: String?
    @State private var adding = false

    private var categories: [YubaiCore.Category] {
        let ordered = store.current.orderedCategories(income: income)
        if style == .sections { return ordered }
        return ordered.filter { $0.name == suggested } + ordered.filter { $0.name != suggested }
    }
    var body: some View {
        Group {
            if style == .sections { sections }
            else { grid }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                CategoryAdditionSheet(income: income, parent: expanded, applyingCount: applyingCount) { addition in
                    choose(addition.assignment, addition)
                }
            }.environment(store).appErrors().yubaiSheetBackground()
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .onChange(of: income) { _, _ in expanded = nil }
        .onChange(of: store.current.id) { _, _ in expanded = nil; adding = false }
    }
    private var grid: some View {
        CategoryGridLayout {
            ForEach(categories) { category in
                mainTile(category)
                    .layoutValue(key: CategoryExpandedKey.self, value: expanded == category.name)
            }
            addButton
            if let category = categories.first(where: { $0.name == expanded }) {
                smallItems(category).layoutValue(key: CategoryPanelKey.self, value: true)
            }
        }
    }
    /// Entry forms show both levels together: a main button confirms main-only,
    /// while a small-item button confirms the complete assignment immediately.
    private var sections: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space16) {
            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    CategoryChoiceChip(title: category.name, selected: selected?.category == category.name,
                                       outlined: suggested == category.name && selected?.category != category.name, prominent: true) {
                        _ = choose(.init(category: category.name), nil)
                    }.accessibilityIdentifier(identifier + "Category_" + category.name)
                        .accessibilityHint("只记" + category.name)
                    if !category.subcategories.isEmpty {
                        ChipFlow {
                            ForEach(category.subcategories, id: \.self) { sub in
                                CategoryChoiceChip(title: sub, selected: selected == .init(category: category.name, subcategory: sub)) {
                                    _ = choose(.init(category: category.name, subcategory: sub), nil)
                                }.accessibilityIdentifier(identifier + "Subcategory_" + category.name + "/" + sub)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            addButton
        }
    }
    private var addButton: some View {
        Button { adding = true } label: {
            Label("加一个", systemImage: "plus").yubaiFont(YubaiFont.button)
                .lineLimit(1).fixedSize().padding(.horizontal, YubaiSpace.gapGroup)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle)
                .foregroundStyle(YubaiColor.brandInk)
                .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: 1) }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier + "Add")
    }
    private func mainTile(_ category: YubaiCore.Category) -> some View {
        let active = expanded == category.name || (expanded == nil && selected?.category == category.name)
        return Button {
            if category.subcategories.isEmpty { _ = choose(.init(category: category.name), nil) }
            else { withAnimation(YubaiMotion.quick) { expanded = expanded == category.name ? nil : category.name } }
        } label: {
            Text(category.name).yubaiFont(YubaiFont.button, weight: active || suggested == category.name ? .semibold : .regular)
                .lineLimit(1).fixedSize().padding(.horizontal, YubaiSpace.gapGroup)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle)
                .foregroundStyle(active ? YubaiColor.onBrand : (suggested == category.name ? YubaiColor.brandInk : YubaiColor.label))
                .background(active ? YubaiColor.brand : YubaiColor.raised, in: Capsule())
                .overlay { if !active && suggested == category.name { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 2) } }
        }.buttonStyle(PressButtonStyle()).opacity(expanded != nil && expanded != category.name ? 0.45 : 1)
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityValue(expanded == category.name ? "已展开" : "")
            .accessibilityHint(category.subcategories.isEmpty ? "选择这个分类" : "展开或收起小项")
            .accessibilityIdentifier(identifier + "Category_" + category.name)
    }
    private func smallItems(_ category: YubaiCore.Category) -> some View {
        ChipFlow {
            ForEach(category.subcategories, id: \.self) { sub in
                CategoryChoiceChip(title: sub, selected: selected == .init(category: category.name, subcategory: sub)) {
                    if choose(.init(category: category.name, subcategory: sub), nil) { expanded = nil }
                }.accessibilityIdentifier(identifier + "Subcategory_" + category.name + "/" + sub)
            }
            CategoryChoiceChip(title: "只记" + category.name, outlined: true) {
                if choose(.init(category: category.name), nil) { expanded = nil }
            }.accessibilityIdentifier(identifier + "MainOnly_" + category.name)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.gapGroup)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
    }
}

struct CategoryChoiceChip: View {
    let title: String
    var selected = false
    var outlined = false
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).yubaiFont(prominent ? YubaiFont.button : YubaiFont.callout, weight: prominent ? .semibold : nil)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                .foregroundStyle(selected ? YubaiColor.onBrand : (outlined ? YubaiColor.brandInk : YubaiColor.label))
                .background(selected ? YubaiColor.brand : (outlined ? Color.clear : YubaiColor.raised), in: Capsule())
                .overlay { if outlined { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1) } }
                .frame(minHeight: YubaiSize.tapMin)
        }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Value-based form control; uses the same picker without auto-applying a draft.
struct CategoryPickerField: View {
    @Environment(AppStore.self) private var store
    let income: Bool
    let selection: CategoryAssignment
    var suggested: String? = nil
    var allowsDirectionChange = false
    var identifier = "categoryField"
    let choose: (CategoryAssignment) -> Void
    @State private var showing = false
    @State private var direction = false
    var body: some View {
        Button { direction = income; showing = true } label: {
            ViewThatFits(in: .horizontal) {
                HStack { Text("分类").fixedSize(); Spacer(); value }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { Text("分类").fixedSize(); value }
            }.yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.label)
                .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            .sheet(isPresented: $showing) {
                NavigationStack {
                    Page(topPadding: YubaiSpace.space8) {
                        if allowsDirectionChange {
                            Picker("收支", selection: $direction) { Text("支出").tag(false); Text("收入").tag(true) }.pickerStyle(.segmented)
                        }
                        CategoryPicker(income: direction, selected: selection, suggested: suggested, identifier: identifier) { choice, addition in
                            if let addition, !store.update("添加分类", { try addition.apply(to: &$0) }) { return false }
                            choose(choice); showing = false; return true
                        }
                    }.navigationTitle("分类").yubaiNavigation()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showing = false } } }
                }.environment(store).appErrors().yubaiSheetBackground()
            }
    }
    private var value: some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(Classification.displayCategory(selection.category) + (selection.subcategory.map { " · " + $0 } ?? "")).lineLimit(1).fixedSize()
            Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption).accessibilityHidden(true)
        }.foregroundStyle(YubaiColor.brandInk)
    }
}

struct CategoryAdditionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let income: Bool
    @State var parent: String?
    var applyingCount = 0
    let add: (CategoryAddition) -> Bool
    private let initialParent: String?
    @State private var name = ""
    @State private var allParents = false
    init(income: Bool, parent: String?, applyingCount: Int = 0, add: @escaping (CategoryAddition) -> Bool) {
        self.income = income; _parent = State(initialValue: parent); initialParent = parent
        self.applyingCount = applyingCount; self.add = add
    }
    private var addition: CategoryAddition { .init(name: name, parent: parent, income: income) }
    private var valid: Bool { var ledger = store.current; return (try? addition.apply(to: &ledger)) != nil }
    private var parents: [YubaiCore.Category] {
        let ordered = store.current.orderedCategories(income: income).filter { !["其他支出", "其他收入"].contains($0.name) }
        return ordered.filter { $0.name == initialParent } + ordered.filter { $0.name != initialParent }
    }
    var body: some View {
        Page(spacing: YubaiSpace.space24, topPadding: YubaiSpace.space8) {
            Card(style: .list) {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("名字").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    TextField("", text: $name).yubaiFont(YubaiFont.row).accessibilityLabel("名字").accessibilityIdentifier("categoryAdditionName")
                }.padding(.vertical, YubaiSpace.space8)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("放在").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                ChipFlow {
                    CategoryChoiceChip(title: "新的大类", selected: parent == nil) { parent = nil }
                        .accessibilityIdentifier("categoryAdditionMain")
                    ForEach(allParents ? parents : Array(parents.prefix(3))) { category in
                        CategoryChoiceChip(title: category.name, selected: parent == category.name) { parent = category.name }
                            .accessibilityIdentifier("categoryAdditionParent_" + category.name)
                    }
                    if !allParents && parents.count > 3 {
                        CategoryChoiceChip(title: "更多…", outlined: true) { allParents = true }
                    }
                }
            }
        }.navigationTitle("加一个").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }.accessibilityIdentifier("categoryAdditionCancel")
            } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if add(addition) { dismiss() }
                } label: {
                    Text(applyingCount > 0 ? "加上，这 \(applyingCount) 笔记为\(addition.name)" : "加上")
                        .fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(PrimaryButtonStyle(disabledBackground: YubaiColor.raised)).disabled(!valid)
                    .accessibilityIdentifier("categoryAdditionSave")
                    .padding(YubaiSpace.insetPage).background(YubaiColor.canvas)
            }
    }
}

private struct CategoryExpandedKey: LayoutValueKey { static let defaultValue = false }
private struct CategoryPanelKey: LayoutValueKey { static let defaultValue = false }

/// Three columns at ordinary sizes; wider labels wrap as intact tiles. The small
/// item panel spans the available width directly after the expanded tile's row.
private struct CategoryGridLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 350, subviews: subviews).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).1
        for i in subviews.indices {
            let frame = frames[i]
            subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (CGSize, [CGRect]) {
        let gap = YubaiSpace.space8
        let base = max(0, (width - gap * 2) / 3)
        let panel = subviews.indices.first { subviews[$0][CategoryPanelKey.self] }
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var row: [Int] = []; var rowWidth: CGFloat = 0; var rowHeight: CGFloat = 0; var y: CGFloat = 0
        func flush() {
            guard !row.isEmpty else { return }
            y += rowHeight + gap
            if row.contains(where: { subviews[$0][CategoryExpandedKey.self] }), let panel {
                let size = subviews[panel].sizeThatFits(ProposedViewSize(width: width, height: nil))
                frames[panel] = CGRect(x: 0, y: y, width: width, height: size.height); y += size.height + gap
            }
            row = []; rowWidth = 0; rowHeight = 0
        }
        for i in subviews.indices where i != panel {
            let ideal = subviews[i].sizeThatFits(.unspecified)
            let tileWidth = max(base, ideal.width)
            if !row.isEmpty && (row.count == 3 || rowWidth + gap + tileWidth > width + 0.5) { flush() }
            let x = row.isEmpty ? 0 : rowWidth + gap
            frames[i] = CGRect(x: x, y: y, width: tileWidth, height: ideal.height)
            row.append(i); rowWidth = x + tileWidth; rowHeight = max(rowHeight, ideal.height)
        }
        flush()
        return (CGSize(width: width, height: max(0, y - gap)), frames)
    }
}
