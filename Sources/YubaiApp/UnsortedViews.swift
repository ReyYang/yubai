import SwiftUI
import YubaiCore

struct UnsortedUndoNotice: Identifiable {
    let id = UUID()
    let questionID: UUID
    let groupIDs: [String]
    let label: String
    let recovery: UnsortedGroupsUndo
}

struct UnsortedUndoRestoration: Equatable {
    let id = UUID()
    let questionID: UUID
    let groupIDs: [String]
}

/// 一笔笔分：一屏一笔，金额、名字、日期放中间，下面是余白猜的分类和别的选项，底下的钮直接写着「数码，下一笔」。
struct LetterTriageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    let entryIDs: [UUID]
    @State private var queue: [UUID] = []
    @State private var index = 0
    @State private var total = 0
    @State private var choice: CategoryAssignment?
    @State private var suggestion: CategoryAssignment?
    @State private var rememberParty = true
    @State private var showsSource = false
    @State private var showingMore = false
    private var entry: Entry? {
        guard queue.indices.contains(index), let row = store.entriesByID[queue[index]], row.deletedAt == nil else { return nil }
        return row
    }
    private var selection: CategoryAssignment { choice ?? suggestion ?? .init(category: Classification.pendingCategory) }
    private var hasSelection: Bool { !Classification.isPending(selection.category) }
    private func party(_ entry: Entry) -> String { entry.title.components(separatedBy: " · ")[0] }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            ScrollView {
                if let entry {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
                        summaryCard(entry)
                        guessBlock(entry)
                        othersBlock(entry)
                        partyToggle(entry)
                    }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8)
                }
            }
        }.fixedBottomBar() { bottomBar }
            .paperBackground().amountPrivacy(store.preferences.hideAmounts).navigationTitle("整理分类").yubaiNavigation().accessibilityIdentifier("letterTriage")
            .toolbar { ToolbarItem(placement: .primaryAction) {
                Text("\(min(index + 1, total)) / \(total)").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            } }
            .sheet(isPresented: $showingMore) {
                EntryMoreCategorySheet(income: entry.map { $0.nature != .refund && $0.nature.inflow } ?? false, selection: selection,
                                       suggested: suggestion?.category, choose: { picked in
                    choice = picked; showingMore = false
                }, dismiss: { showingMore = false })
            }
            .onAppear {
                guard total == 0 else { return }
                let ids = Set(entryIDs)
                queue = store.sortedEntries.filter { ids.contains($0.id) && $0.deletedAt == nil && Classification.isPending($0) }.map(\.id)
                total = queue.count
                if queue.isEmpty { dismiss() } else { prepare() }
            }
            .onChange(of: entry?.id) { _, _ in prepare() }
    }

    private func summaryCard(_ entry: Entry) -> some View {
        let line = ImportStatementText.balanceDate(entry.date) + " · " + store.accountName(entry.accountID)
        let original = entry.note.isEmpty ? entry.title : entry.note
        return Card {
            VStack(spacing: YubaiSpace.space8) {
                Text(line).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                AmountLabel(cents: entry.amount, hide: store.preferences.hideAmounts, role: .display, sign: entry.nature.inflow ? .inflow : .outflow)
                Text(entry.displayTitle).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.body, weight: .medium).multilineTextAlignment(.center)
                Button { showsSource.toggle() } label: {
                    Text("看原文").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk).yubaiHitTarget()
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("sortSourceToggle")
                    .accessibilityValue(showsSource ? "已展开" : "已收起")
                if showsSource {
                    Text(store.preferences.hideAmounts ? "金额已隐藏" : original).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(YubaiSpace.gapGroup)
                        .background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous))
                        .accessibilityLabel(store.preferences.hideAmounts ? "金额已隐藏" : "原文：" + original)
                }
            }.frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private func guessBlock(_ entry: Entry) -> some View {
        if suggestion != nil {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                sectionLabel("余白猜是")
                ChipFlow {
                    ForEach(guessedNames(entry), id: \.self) { name in
                        CategoryChoiceChip(title: name, selected: selection.category == name) {
                            choice = name == suggestion?.category ? suggestion : .init(category: name)
                        }.accessibilityIdentifier("sortGuess_" + name)
                    }
                }
            }
        }
    }
    private func othersBlock(_ entry: Entry) -> some View {
        let income = entry.nature != .refund && entry.nature.inflow
        let guesses = guessedNames(entry)
        let names = store.current.orderedCategories(income: income).map(\.name).filter { !guesses.contains($0) }
        var shown = Array(names.prefix(5))
        if let picked = choice?.category, !guesses.contains(picked), !shown.contains(picked) { shown.insert(picked, at: 0) }
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionLabel("别的")
            ChipFlow {
                ForEach(shown, id: \.self) { name in
                    CategoryChoiceChip(title: name, selected: selection.category == name) { choice = .init(category: name) }
                        .accessibilityIdentifier("sortCategory_" + name)
                }
                CategoryChoiceChip(title: "更多") { showingMore = true }.accessibilityIdentifier("sortCategoryMore")
            }
        }
    }
    private func guessedNames(_ entry: Entry) -> [String] {
        guard let suggestion else { return [] }
        let available = Set(store.current.orderedCategories(income: entry.nature.categoryIncome).map(\.name))
        return [suggestion.category] + ["娱乐", "购物"].filter { $0 != suggestion.category && available.contains($0) }
    }
    private func sectionLabel(_ title: String) -> some View {
        Text(title).yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary).padding(.horizontal, YubaiSpace.space4)
    }
    private func partyToggle(_ entry: Entry) -> some View {
        Toggle(isOn: $rememberParty) {
            Text("以后「" + party(entry) + "」都这样分").yubaiFont(YubaiFont.row).lineLimit(2)
        }.tint(YubaiColor.toggleOn).padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.rowDouble)
            .background(YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control, style: .continuous))
            .accessibilityIdentifier("sortRememberParty")
    }
    private var bottomBar: some View {
        let title = hasSelection ? Classification.displayCategory(selection.category) + "，下一笔" : "下一笔"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: YubaiSpace.gapGroup) { skipButton.fixedSize(); nextButton(title).frame(maxWidth: .infinity) }
            VStack(spacing: YubaiSpace.space8) { nextButton(title); skipButton }
        }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.space8)
            .background(YubaiColor.canvas).overlay(alignment: .top) { PageFade(edge: .bottom).offset(y: -YubaiSize.iconButton) }
    }
    private var skipButton: some View {
        Button("跳过") { advance() }.buttonStyle(SecondaryButtonStyle(background: YubaiColor.raised))
            .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("skipLetterEntry")
    }
    private func nextButton(_ title: String) -> some View {
        Button(title) { save() }.buttonStyle(PrimaryButtonStyle()).disabled(!hasSelection || entry == nil)
            .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("saveLetterEntry")
    }
    private func prepare() {
        choice = nil; showsSource = false; rememberParty = true
        suggestion = entry.flatMap { CategoryGuesser.guess($0, in: store.current) }
    }
    private func advance() {
        index += 1
        while queue.indices.contains(index) && store.entriesByID[queue[index]].map({ $0.deletedAt != nil || !Classification.isPending($0) }) != false { index += 1 }
        if index >= queue.count { dismiss() } else { prepare() }
    }
    private func save() {
        guard var entry, hasSelection else { return }
        let selected = selection; let remember = rememberParty
        entry.category = selected.category; entry.subcategory = selected.subcategory; entry.subcategoryUserEdited = true
        if entry.nature.uncertain { entry.nature = entry.nature.inflow ? .income : .expense }
        if store.update("分类", showToast: false, { ledger in
            try ManualBookkeeping.edit(entry, in: &ledger)
            try CategoryModel.confirm(selected, entryIDs: [entry.id], includingParty: remember, in: &ledger)
        }) { advance() }
    }
}
