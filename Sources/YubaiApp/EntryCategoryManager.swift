import SwiftUI
import YubaiCore

/// Canvas S-Cats / S-CatEdit: 分类管理, pushed from 全部分类 › 编辑. Back returns to the panel; the draft stays.
struct EntryCategoryManagerView: View {
    let model: EntrySheetViewModel
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var direction: String
    @State private var editing: EditTarget?

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
        let categories = model.ledger.orderedCategories(income: income).filter { !$0.system }
        return VStack(spacing: .zero) {
            EntryPageHeader(title: "分类", back: close) {
                Button { editing = EditTarget(name: nil, income: income) } label: {
                    DS.Icon.add.view(size: EntrySpec.pageIcon, color: DS.Color.accentInk)
                        .frame(width: DS.Size.tapMin, height: DS.Size.tapMin)
                }
                .buttonStyle(EntryTactileButtonStyle())
                .accessibilityLabel("新建分类")
            }
            ScrollView {
                VStack(spacing: .zero) {
                    DSSegmented(options: [Self.expense, Self.income], selection: $direction, width: nil)
                        .padding(.top, DS.Space.s8)
                    List {
                        ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                            Button { editing = EditTarget(name: category.name, income: income) } label: {
                                row(category, last: index == categories.count - 1)
                            }
                            .buttonStyle(EntryTactileButtonStyle())
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(DS.Color.raised)
                            .accessibilityHint("编辑这个分类，按住拖动排序")
                        }
                        .onMove { from, to in
                            var names = categories.map(\.name)
                            names.move(fromOffsets: from, toOffset: to)
                            let income = income
                            model.mutateLedger("分类排序") { try CategoryModel.setOrder(names, income: income, in: &$0) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.defaultMinListRowHeight, .zero)
                    .frame(height: DS.Size.rowCat * CGFloat(categories.count))
                    .background(DS.Color.raised)
                    .clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
                    .padding(.top, DS.Space.s16)
                    .sensoryFeedback(DSMotion.Haptic.toggle, trigger: model.ledger.preferences.categoryOrder)
                }
                .padding(.horizontal, DS.Space.s16)
                .padding(.bottom, DS.Space.s28)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Color.bg.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }

    private func row(_ category: YubaiCore.Category, last: Bool) -> some View {
        HStack(spacing: DS.Space.s12) {
            category.entryIcon.view(size: DS.Size.icon, color: DS.Color.ink2)
                .frame(width: DS.Size.iconTile, height: DS.Size.iconTile)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.s, style: .continuous))
            Text(category.name).dsText(DS.Font.tTitle).foregroundStyle(DS.Color.ink).lineLimit(1).dsFillWidth()
            if !category.subcategories.isEmpty {
                Text("\(category.subcategories.count) 个小类").dsText(DS.Font.tSub).monospacedDigit()
                    .foregroundStyle(DS.Color.ink3).fixedSize()
            }
            DS.Icon.drag.view(size: EntrySpec.checkIcon, color: DS.Color.chevron)
                .accessibilityHidden(true)
        }
        .padding(.leading, DS.Space.s16)
        .padding(.trailing, DS.Space.s12)
        .frame(minHeight: DS.Size.rowCat)
        .overlay(alignment: .bottom) {
            if !last {
                DS.Color.separator.frame(height: DS.Stroke.hairline)
                    .padding(.leading, DS.Space.s16 + DS.Size.iconTile + DS.Space.s12)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Canvas S-CatEdit: name, subcategories (add, drag, swipe to remove) and 删除分类.
private struct EntryCategoryEditView: View {
    let model: EntrySheetViewModel
    let target: EntryCategoryManagerView.EditTarget
    let back: () -> Void
    @State private var name: String
    @State private var current: String?
    @State private var newSub = ""
    @State private var addingSub = false
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field { case name, sub }

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
    private var fallback: String { target.income ? "其他收入" : "其他支出" }

    var body: some View {
        VStack(spacing: .zero) {
            EntryPageHeader(title: current == nil ? "新建分类" : "编辑分类", back: finish) { EmptyView() }
            ScrollView {
                VStack(spacing: DS.Space.s20) {
                    (category?.entryIcon ?? .catOther).view(size: EntrySpec.editIcon, color: DS.Color.accentInk)
                        .frame(width: EntrySpec.editCircle, height: EntrySpec.editCircle)
                        .background(DS.Color.accentSoft, in: Circle())
                        .padding(.top, DS.Space.s4)
                        .accessibilityHidden(true)
                    nameRow
                    if let category { subcategories(category) }
                    if category != nil {
                        Button { confirmDelete = true } label: {
                            Text("删除分类").dsText(DS.Font.tBody).fontWeight(.semibold).foregroundStyle(DS.Color.warnStrong)
                                .frame(maxWidth: .infinity, minHeight: DS.Size.buttonH)
                                .dsPill()
                        }
                        .buttonStyle(EntryTactileButtonStyle())
                    }
                }
                .padding(.horizontal, DS.Space.s16)
                .padding(.top, DS.Space.s8)
                .padding(.bottom, DS.Space.s28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Color.bg.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, finish)
        .onAppear { if current == nil { focus = .name } }
        .confirmationDialog("删除「\(current ?? "")」？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: delete)
        } message: {
            Text("已记的 \(entryCount) 笔改到「\(fallback)」")
        }
    }

    private var nameRow: some View {
        HStack(spacing: .zero) {
            Text("名字").dsText(DS.Font.tLabel).foregroundStyle(DS.Color.ink3)
                .frame(width: EntrySpec.editLabel, alignment: .leading)
            TextField("", text: $name)
                .textFieldStyle(.plain).dsText(DS.Font.tBody).fontWeight(.semibold).foregroundStyle(DS.Color.ink)
                .tint(DS.Color.accent)
                .focused($focus, equals: .name)
                .submitLabel(.done)
                .onSubmit(commitName)
                .accessibilityLabel("名字")
        }
        .padding(.horizontal, DS.Space.s16)
        .frame(minHeight: EntrySpec.accountRow)
        .background(DS.Color.raised, in: .rect(cornerRadius: DS.Radius.m, style: .continuous))
    }

    private func subcategories(_ category: YubaiCore.Category) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Text("小类").dsText(DS.Font.tSubStrong).foregroundStyle(DS.Color.ink3)
                .padding(.horizontal, DS.Space.s4)
                .accessibilityAddTraits(.isHeader)
            List {
                ForEach(category.subcategories, id: \.self) { sub in
                    HStack {
                        Text(sub).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink).dsFillWidth()
                        DS.Icon.drag.view(size: EntrySpec.checkIcon, color: DS.Color.chevron).accessibilityHidden(true)
                    }
                    .padding(.horizontal, DS.Space.s16)
                    .frame(minHeight: EntrySpec.listRow)
                    .overlay(alignment: .bottom) {
                        DS.Color.separator.frame(height: DS.Stroke.hairline).padding(.leading, DS.Space.s16)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.Color.raised)
                    .nativeSwipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { remove(sub) } label: { Text("删除") }
                            .tint(DS.Color.warnStrong)
                    }
                }
                .onMove { from, to in
                    var subs = category.subcategories
                    subs.move(fromOffsets: from, toOffset: to)
                    reorder(subs)
                }
                addRow
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.Color.raised)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.defaultMinListRowHeight, .zero)
            .frame(height: EntrySpec.listRow * CGFloat(category.subcategories.count + 1))
            .clipShape(.rect(cornerRadius: DS.Radius.m, style: .continuous))
        }
    }

    @ViewBuilder private var addRow: some View {
        if addingSub {
            TextField("", text: $newSub, prompt: Text("添加小类").foregroundStyle(DS.Color.ink3))
                .textFieldStyle(.plain).dsText(DS.Font.tBody).foregroundStyle(DS.Color.ink)
                .tint(DS.Color.accent)
                .focused($focus, equals: .sub)
                .submitLabel(.done)
                .onSubmit(addSub)
                .padding(.horizontal, DS.Space.s16)
                .frame(minHeight: EntrySpec.listRow)
                .onAppear { focus = .sub }
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

    private var entryCount: Int {
        guard let current else { return 0 }
        return model.ledger.activeEntries.filter {
            $0.nature.categoryIncome == target.income && model.ledger.normalizedCategory(for: $0).category == current
        }.count
    }

    private func finish() {
        commitName()
        back()
    }

    private func commitName() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != current else { return }
        let income = target.income
        if let old = current {
            if model.mutateLedger("编辑分类", { try CategoryModel.rename(old, to: cleaned, income: income, in: &$0) }) {
                if model.draft.category == old { model.draft.category = cleaned }
                current = cleaned
            }
        } else if model.mutateLedger("添加分类", { try CategoryModel.add(YubaiCore.Category(cleaned, income: income), in: &$0) }) {
            current = cleaned
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
           model.draft.category == current, model.draft.subcategory == sub {
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
        let income = target.income
        let fallback = fallback
        if model.mutateLedger("删除分类", { try CategoryModel.merge(current, into: fallback, income: income, in: &$0) }) {
            if model.draft.category == current {
                model.draft.category = nil
                model.draft.subcategory = nil
            }
            back()
        }
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
