import SwiftUI
import YubaiCore

enum CategorySettingsRoute: Hashable { case categories }
private struct CategoryDetailRoute: Identifiable, Hashable { let name: String; var id: String { name } }
private struct CategorySmallItem: Identifiable { let name: String; var id: String { name } }

struct CategoriesView: View {
    @Environment(AppStore.self) private var store
    @State private var income = false
    @State private var sorting = false
    @State private var adding = false
    @State private var detail: CategoryDetailRoute?
    private var categories: [YubaiCore.Category] { store.current.orderedCategories(income: income) }
    private var hidden: [YubaiCore.Category] { store.current.orderedCategories(income: income, hidden: true) }
    var body: some View {
        VStack(spacing: YubaiSpace.space12) {
            Picker("收支", selection: $income) { Text("支出").tag(false); Text("收入").tag(true) }
                .pickerStyle(.segmented).padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8)
                .accessibilityIdentifier("categoriesDirection")
            if sorting { ordering }
            else {
                Page(spacing: YubaiSpace.space12, topPadding: YubaiSpace.none) {
                    CardRows(categories) { category in
                        if isOther(category.name) {
                            Text(category.name).yubaiFont(YubaiFont.row).lineLimit(1).fixedSize()
                                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
                        } else {
                            Button { detail = .init(name: category.name) } label: {
                                ViewThatFits(in: .horizontal) {
                                    HStack { categoryName(category.name); Spacer(); smallCount(category); categoryChevron }
                                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                                        categoryName(category.name)
                                        HStack { smallCount(category); Spacer(); categoryChevron }
                                    }
                                }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("manageCategory_" + category.name)
                        }
                    }
                    Button { adding = true } label: {
                        Card(style: .list) {
                            Label("加一个大类", systemImage: "plus").yubaiFont(YubaiFont.row).lineLimit(1).fixedSize()
                                .foregroundStyle(YubaiColor.brandInk).frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
                        }
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("addMainCategory")
                    if !hidden.isEmpty {
                        NavigationLink { HiddenCategoriesView(income: income) } label: {
                            Card(style: .list) {
                                HStack {
                                    Text("藏起来的 · \(hidden.count)").yubaiFont(YubaiFont.callout).lineLimit(1).fixedSize()
                                    Spacer(); categoryChevron
                                }.foregroundStyle(YubaiColor.labelSecondary).frame(minHeight: YubaiSize.tapMin)
                            }
                        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("hiddenCategories")
                    }
                }
            }
        }.paperBackground().foregroundStyle(YubaiColor.label).navigationTitle(sorting ? "排序" : "分类").yubaiNavigation()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(sorting ? "完成" : "排序") { sorting.toggle() }
                        .accessibilityIdentifier("sortCategories")
                }
            }
            .navigationDestination(item: $detail) { route in CategoryDetailView(originalName: route.name) }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    CategoryNameSheet(title: "加一个大类") { name in
                        guard store.update("添加分类", { try CategoryModel.add(Category(name, income: income), in: &$0) }) else { return false }
                        detail = .init(name: name); return true
                    }
                }.environment(store).appErrors().yubaiSheetBackground()
            }
    }
    private var ordering: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space12) {
            List {
                ForEach(Array(categories.filter { !isOther($0.name) }.enumerated()), id: \.element.name) { index, category in
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("\(index + 1)").yubaiFont(YubaiFont.amountSmall)
                            .foregroundStyle(YubaiColor.labelSecondary)
                            .frame(minWidth: YubaiSpace.space16).fixedSize()
                        categoryName(category.name)
                    }.frame(minHeight: YubaiSize.tapMin).listRowBackground(YubaiColor.paperSheet)
                        .accessibilityIdentifier("categoryOrder_" + category.name)
                }.onMove(perform: move)
                ForEach(categories.filter { isOther($0.name) }) { category in
                    categoryName(category.name).frame(minHeight: YubaiSize.tapMin).listRowBackground(YubaiColor.paperSheet)
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .clipShape(RoundedRectangle(cornerRadius: YubaiRadius.card)).padding(.horizontal, YubaiSpace.insetPage)
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #endif
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("记一笔先显示").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                ChipFlow {
                    ForEach(Array(categories.prefix(5))) { category in
                        Text(category.name).yubaiFont(YubaiFont.callout).lineLimit(1).fixedSize()
                            .padding(.horizontal, YubaiSpace.gapGroup).padding(.vertical, YubaiSpace.space8)
                            .background(YubaiColor.card, in: Capsule())
                    }
                }.accessibilityIdentifier("categoryOrderPreview")
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.insetPage)
        }
    }
    private func move(from offsets: IndexSet, to destination: Int) {
        var names = categories.filter { !isOther($0.name) }.map(\.name)
        names.move(fromOffsets: offsets, toOffset: destination)
        if let other = categories.first(where: { isOther($0.name) }) { names.append(other.name) }
        let allowed = Set(store.current.categories.filter { !$0.system }.map(\.name))
        var seen = Set(names)
        let remaining = (store.current.preferences.categoryOrder + store.current.categories.map(\.name))
            .filter { allowed.contains($0) && seen.insert($0).inserted }
        store.update("分类排序", recordUndo: false) { try CategoryModel.setOrder(names + remaining, in: &$0) }
    }
    private func smallCount(_ category: YubaiCore.Category) -> some View {
        Text("\(category.subcategories.count) 个小项").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1).fixedSize()
    }
}

private struct CategoryDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let originalName: String
    @State private var name = ""
    @State private var savedName = ""
    @FocusState private var nameFocused: Bool
    @State private var smallItem: CategorySmallItem?
    @State private var adding = false
    @State private var merging = false
    private var categoryName: String { store.current.categoryAssignment(category: originalName).category }
    private var category: YubaiCore.Category? { store.current.categories.first { $0.name == categoryName } }
    var body: some View {
        Page(spacing: YubaiSpace.space24, topPadding: YubaiSpace.space8) {
            if let category {
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            Text("名字").fixedSize()
                            TextField("", text: $name).multilineTextAlignment(.trailing).focused($nameFocused)
                                .accessibilityLabel("名字").accessibilityIdentifier("categoryName").onSubmit(rename)
                        }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.buttonHeight)
                        categorySeparator
                        recordedCount(categoryName, ledger: store.current)
                    }
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("小项").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    ChipFlow {
                        ForEach(category.subcategories, id: \.self) { sub in
                            CategoryChoiceChip(title: sub) { nameFocused = false; rename(); smallItem = .init(name: sub) }
                                .accessibilityIdentifier("editSubcategory_" + sub)
                        }
                        CategoryChoiceChip(title: "加小项", outlined: true) { nameFocused = false; rename(); adding = true }
                            .accessibilityIdentifier("addSubcategory")
                    }
                }
                Card(style: .list) {
                    VStack(spacing: YubaiSpace.none) {
                        Button { nameFocused = false; rename(); merging = true } label: {
                            HStack { Text("合并到…").lineLimit(1).fixedSize(); Spacer(); categoryChevron }
                                .yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.rowSingle).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("mergeCategory")
                        categorySeparator
                        Toggle(isOn: Binding(get: { category.hidden }, set: { hidden in
                            store.update("修改分类") { try CategoryModel.setHidden(hidden, category: categoryName, in: &$0) }
                        })) { Text("记账时藏起来").lineLimit(1).fixedSize() }
                            .yubaiFont(YubaiFont.row).tint(YubaiColor.toggleOn).frame(minHeight: YubaiSize.rowSingle)
                            .accessibilityIdentifier("hideCategory")
                    }
                }
            }
        }.navigationTitle(categoryName).yubaiNavigation()
            .onAppear { name = categoryName; savedName = categoryName }
            .onChange(of: nameFocused) { _, focused in if !focused { rename() } }
            .onDisappear { rename() }
            .sheet(item: $smallItem) { item in
                NavigationStack { CategorySubcategoryEditor(category: categoryName, original: item.name) }
                    .environment(store).appErrors().yubaiSheetBackground().presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $adding) {
                NavigationStack {
                    CategoryNameSheet(title: "加小项") { name in
                        store.update("添加小项") { try CategoryModel.addSubcategory(name, to: categoryName, in: &$0) }
                    }
                }.environment(store).appErrors().yubaiSheetBackground()
            }
            .sheet(isPresented: $merging) {
                NavigationStack { CategoryMergeView(source: categoryName) { dismiss() } }
                    .environment(store).appErrors().yubaiSheetBackground()
            }
    }
    private func rename() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard category != nil, categoryName == savedName, clean != categoryName else { return }
        if store.update("修改分类", { try CategoryModel.rename(categoryName, to: clean, in: &$0) }) { name = clean; savedName = clean }
        else { name = categoryName }
    }
}

private struct CategoryNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: (String) -> Bool
    @State private var name = ""
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            Card(style: .list) {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text("名字").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    TextField("", text: $name).yubaiFont(YubaiFont.row).accessibilityLabel("名字").accessibilityIdentifier("newCategoryName")
                }.padding(.vertical, YubaiSpace.space8)
            }
        }.navigationTitle(title).yubaiNavigation().toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("加上") { if save(name.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveNewCategory")
            }
        }
    }
}

private struct CategorySubcategoryEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let category: String
    let original: String
    @State private var name = ""
    var body: some View {
        Page(spacing: YubaiSpace.space16, topPadding: YubaiSpace.space8) {
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    HStack {
                        Text("名字").fixedSize()
                        TextField("", text: $name).multilineTextAlignment(.trailing).accessibilityLabel("名字").accessibilityIdentifier("subcategoryName")
                    }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.buttonHeight)
                    categorySeparator
                    recordedCount(category, subcategory: original, ledger: store.current)
                }
            }
            Button("删掉这个小项") {
                if store.update("删除小项", { try CategoryModel.removeSubcategory(original, from: category, in: &$0) }) { dismiss() }
            }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.card)).foregroundStyle(YubaiColor.amberInk)
                .accessibilityIdentifier("deleteSubcategory")
        }.navigationTitle("小项").yubaiNavigation().onAppear { name = original }.toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("好") {
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if clean == original || store.update("修改小项", { try CategoryModel.renameSubcategory(original, in: category, to: clean, ledger: &$0) }) { dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveSubcategory")
            }
        }
    }
}

private struct CategoryMergeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let source: String
    let merged: () -> Void
    @State private var target: String?
    private var income: Bool { store.current.categories.first { $0.name == source }?.income ?? false }
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            CardRows(store.current.orderedCategories(income: income).filter { $0.name != source }) { category in
                Button { target = category.name } label: {
                    HStack {
                        categoryName(category.name); Spacer()
                        if target == category.name { Image(systemName: "checkmark").foregroundStyle(YubaiColor.brandInk) }
                    }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(target == category.name ? .isSelected : [])
                    .accessibilityIdentifier("mergeInto_" + category.name)
            }
        }.navigationTitle(source + "合并到").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let target else { return }
                    if store.update("合并分类", { try CategoryModel.merge(source, into: target, in: &$0) }) { dismiss(); merged() }
                } label: {
                    Text("\(categoryEntryCount(source, ledger: store.current)) 笔改成\(target ?? "")").fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(PrimaryButtonStyle(disabledBackground: YubaiColor.raised)).disabled(target == nil)
                    .accessibilityIdentifier("confirmCategoryMerge").padding(YubaiSpace.insetPage).background(YubaiColor.canvas)
            }
    }
}

private struct HiddenCategoriesView: View {
    @Environment(AppStore.self) private var store
    let income: Bool
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            CardRows(store.current.orderedCategories(income: income, hidden: true)) { category in
                HStack {
                    categoryName(category.name); Spacer()
                    Button("显示") { store.update("修改分类") { try CategoryModel.setHidden(false, category: category.name, in: &$0) } }
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).fixedSize()
                        .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("unhideCategory_" + category.name)
                }
            }
        }.navigationTitle("藏起来的").yubaiNavigation()
    }
}

private func isOther(_ name: String) -> Bool { ["其他支出", "其他收入"].contains(name) }
private func categoryName(_ name: String) -> some View { Text(name).yubaiFont(YubaiFont.row).lineLimit(1).fixedSize() }
private var categoryChevron: some View { Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true) }
private var categorySeparator: some View { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
private func categoryEntryCount(_ category: String, subcategory: String? = nil, ledger: Ledger) -> Int {
    ledger.activeEntries.filter {
        let choice = ledger.categoryAssignment(category: $0.category, subcategory: $0.subcategory)
        return choice.category == category && (subcategory == nil || choice.subcategory == subcategory)
    }.count
}
private func recordedCount(_ category: String, subcategory: String? = nil, ledger: Ledger) -> some View {
    HStack {
        Text("记过").fixedSize(); Spacer()
        Text("\(categoryEntryCount(category, subcategory: subcategory, ledger: ledger)) 笔").foregroundStyle(YubaiColor.labelSecondary).fixedSize()
    }.yubaiFont(YubaiFont.row).frame(minHeight: YubaiSize.rowSingle)
}
