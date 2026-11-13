import SwiftUI
import YubaiCore

/// Keep the destination attached to the list, even if its source row disappears.
/// A bound route lets the list wait for the detail's pop before dismissing itself.
/// The initial group is display-only during the pop transition; confirmation
/// always resolves the current ledger revision through AppStore.
private struct UnsortedGroupRoute: Hashable, Identifiable {
    let questionID: UUID
    let group: UnsortedPartyGroup
    var id: String { group.id }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.questionID == rhs.questionID && lhs.group.id == rhs.group.id }
    func hash(into hasher: inout Hasher) { hasher.combine(questionID); hasher.combine(group.id) }
}

struct UnsortedGroupsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let questionID: UUID
    @State private var search = ""
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showingApply = false
    // The binding becomes false before the sheet's dismissal has finished.
    @State private var applySheetPresented = false
    @State private var detailRoute: UnsortedGroupRoute?
    @State private var isDismissing = false
    var body: some View {
        let snapshot = store.unsortedGroups(questionID: questionID)
        let visible: [UnsortedPartyGroup] = snapshot?.matching(search) ?? []
        let count = snapshot?.entryCount ?? 0
        let selected = snapshot?.groups.filter { selectedIDs.contains($0.id) } ?? []
        ScrollViewReader { proxy in
            ScrollView {
                // CardRows owns the lazy rows; keep the top anchor eagerly laid out.
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                        Text(count.formatted(.number.locale(Locale(identifier: "en_US"))))
                            .yubaiFont(YubaiFont.amountLarge).accessibilityIdentifier("unsortedEntryCount")
                        Text("笔还没分类").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                    }.id("unsortedGroupsTop")
                    SearchInput(text: $search, placeholder: "搜商户", identifier: "unsortedPartySearch", label: "搜索商户")
                    if !visible.isEmpty {
                        CardRows(visible) { group in groupRow(group, selected: selected) }
                            .id(count)
                    }
                }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8).padding(.bottom, YubaiSpace.gapSection)
                    .frame(maxWidth: YubaiSize.contentMaximum).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("unsortedGroupsScroll")
                .onChange(of: count) { _, _ in
                    // Apply and undo both invalidate lazy measurements and return
                    // to the count/search, including while a sheet is closing.
                    proxy.scrollTo("unsortedGroupsTop", anchor: .top)
                }
        }.paperBackground().foregroundStyle(YubaiColor.label)
            .navigationTitle("按商户整理").yubaiNavigation()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(selecting ? "完成" : "选择") { selecting.toggle(); selectedIDs.removeAll() }
                        .foregroundStyle(YubaiColor.brandInk).accessibilityIdentifier("unsortedSelect")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
                if selecting {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("\(selected.count) 组 · \(selected.reduce(0) { $0 + $1.entries.count }) 笔")
                            .yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.labelMuted)
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("unsortedSelectionCount")
                        Button("记为…") { applySheetPresented = true; showingApply = true }
                            .buttonStyle(PrimaryButtonStyle(disabledBackground: YubaiColor.raised)).fixedSize(horizontal: true, vertical: false)
                            .disabled(selected.isEmpty).accessibilityIdentifier("unsortedApplySelected")
                    }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.gapGroup)
                        .background(YubaiColor.canvas.ignoresSafeArea(edges: .bottom))
                }
            }
            .sheet(isPresented: $showingApply, onDismiss: {
                applySheetPresented = false
                dismissIfEmpty()
            }) {
                UnsortedSelectionSheet(questionID: questionID, groupIDs: selectedIDs) {
                    showingApply = false; selecting = false; selectedIDs.removeAll()
                }.environment(store).presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible).yubaiSheetBackground().appErrors()
            }
            .onChange(of: snapshot?.revision, initial: true) { _, _ in
                selectedIDs.formIntersection(snapshot?.groups.map(\.id) ?? [])
                if selectedIDs.isEmpty { showingApply = false }
                dismissIfEmpty()
            }
            .navigationDestination(item: $detailRoute) { route in
                UnsortedGroupView(questionID: route.questionID, initialGroup: route.group)
            }
            .onChange(of: detailRoute) { _, route in if route == nil { dismissIfEmpty() } }
    }
    private func dismissIfEmpty() {
        // Let the sheet/detail finish its own dismissal first. Undo belongs to
        // RootView and remains available after this page returns to 现在.
        guard (store.unsortedGroups(questionID: questionID)?.entryCount ?? 0) == 0,
              !applySheetPresented, detailRoute == nil, !isDismissing else { return }
        isDismissing = true
        dismiss()
    }
    @ViewBuilder private func groupRow(_ group: UnsortedPartyGroup, selected: [UnsortedPartyGroup]) -> some View {
        if selecting {
            Button {
                if !selectedIDs.insert(group.id).inserted { selectedIDs.remove(group.id) }
            } label: { rowContent(group) }
                .buttonStyle(PressButtonStyle())
                .disabled(selected.first.map { $0.inflow != group.inflow } ?? false)
                .opacity(selected.first.map { $0.inflow != group.inflow } == true ? 0.4 : 1)
                .accessibilityAddTraits(selectedIDs.contains(group.id) ? .isSelected : [])
                .accessibilityValue(selectedIDs.contains(group.id) ? "已选择" : "未选择")
                .accessibilityIdentifier("unsortedGroup_" + group.id)
        } else {
            Button { detailRoute = UnsortedGroupRoute(questionID: questionID, group: group) } label: { rowContent(group) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("unsortedGroup_" + group.id)
        }
    }
    private func rowContent(_ group: UnsortedPartyGroup) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
                if selecting {
                    ZStack {
                        Circle().strokeBorder(YubaiColor.labelSecondary, lineWidth: YubaiSize.lineWidth)
                        if selectedIDs.contains(group.id) {
                            Circle().fill(YubaiColor.brand)
                            Image(systemName: "checkmark").yubaiFont(YubaiFont.caption, weight: .semibold).foregroundStyle(YubaiColor.onBrand)
                        }
                    }.frame(width: YubaiSpace.space24, height: YubaiSpace.space24).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Text(group.party).yubaiFont(YubaiFont.rowTitle).lineLimit(1).truncationMode(.tail)
                    Text("\(group.entries.count) 笔 · \(group.entries.first.map(UnsortedEntryPresentation.summary) ?? "")")
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).lineLimit(1).truncationMode(.tail)
                }.frame(maxWidth: .infinity, alignment: .leading)
                AmountLabel(cents: group.total, hide: store.preferences.hideAmounts, role: .amount,
                            sign: group.inflow ? .inflow : .outflow, currency: false).layoutPriority(1)
                if !selecting { Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            }.contentShape(Rectangle())
    }
}

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

/// Shared immediate-apply controls for the quick card and the selection sheet.
private struct UnsortedImmediateChoices: View {
    @Environment(AppStore.self) private var store
    let groups: [UnsortedPartyGroup]
    var suggested: String? = nil
    let identifier: String
    let apply: (UnsortedUse, CategoryAssignment?, UUID?, CategoryAddition?) -> Bool
    @State private var choosingAccount = false
    var body: some View {
        let inflow = groups.first?.inflow ?? false
        let choices = UnsortedGroups.uses(for: groups, in: store.current).filter { !$0.needsCategory && $0 != .transfer }
        let canTransfer = UnsortedGroups.uses(for: groups, in: store.current).contains(.transfer)
        VStack(alignment: .leading, spacing: YubaiSpace.space16) {
            CategoryPicker(income: inflow, suggested: suggested,
                           applyingCount: groups.reduce(0) { $0 + $1.entries.count }, identifier: identifier) { choice, addition in
                apply(inflow ? .income : .expense, choice, nil, addition)
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(inflow ? "不是收入" : "不是支出").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                ChipFlow {
                    ForEach(choices, id: \.rawValue) { use in
                        CategoryChoiceChip(title: use.title) { _ = apply(use, nil, nil, nil) }
                            .accessibilityIdentifier(identifier + "Nature_" + use.rawValue)
                    }
                    if canTransfer {
                        CategoryChoiceChip(title: UnsortedUse.transfer.title, selected: choosingAccount) {
                            choosingAccount.toggle()
                        }.accessibilityIdentifier(identifier + "Nature_transfer")
                    }
                }
                if choosingAccount, canTransfer {
                    ChipFlow {
                        ForEach(UnsortedGroups.otherAccounts(for: groups, in: store.current)) { account in
                            CategoryChoiceChip(title: account.name) { _ = apply(.transfer, nil, account.id, nil) }
                                .accessibilityIdentifier(identifier + "Account_" + account.id.uuidString)
                        }
                    }
                }
            }
        }.disabled(groups.isEmpty)
    }
}

private struct UnsortedSelectionSheet: View {
    @Environment(AppStore.self) private var store
    let questionID: UUID
    let groupIDs: Set<String>
    let applied: () -> Void
    var body: some View {
        let snapshot = store.unsortedGroups(questionID: questionID)
        let groups = snapshot?.groups.filter { groupIDs.contains($0.id) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.space16) {
                Text("\(groups.reduce(0) { $0 + $1.entries.count }) 笔记为").yubaiFont(YubaiFont.heroLabel)
                UnsortedImmediateChoices(groups: groups, suggested: groups.count == 1 ? groups.first.flatMap { UnsortedGroups.suggestedCategory(for: $0, in: store.current) } : nil, identifier: "unsortedSelected") { use, choice, account, addition in
                    if store.applyUnsortedGroups(questionID: questionID, groupIDs: groupIDs, use: use, category: choice?.category,
                                                 otherAccount: account, subcategory: choice?.subcategory, addition: addition) { applied(); return true }
                    return false
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.space24)
        }.paperBackground().foregroundStyle(YubaiColor.label).manualSheetHeader("分类", showsAction: false)
    }
}

struct UnsortedGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let questionID: UUID
    let groupID: String
    @State private var use: UnsortedUse?
    @State private var category: String?
    @State private var subcategory: String?
    @State private var otherAccount: UUID?
    @State private var purpose = ""
    // An empty exclusion set means all rows are selected, without rebuilding a
    // large ID set on every chip tap or render.
    @State private var excludedEntryIDs: Set<UUID> = []
    @State private var lastGroup: UnsortedPartyGroup
    @State private var isDismissing = false
    init(questionID: UUID, initialGroup: UnsortedPartyGroup) {
        self.questionID = questionID; groupID = initialGroup.id
        _lastGroup = State(initialValue: initialGroup)
    }
    var body: some View {
        let snapshot = store.unsortedGroups(questionID: questionID)
        let liveGroup = snapshot?.groupsByID[groupID]
        let group = liveGroup ?? lastGroup
        ScrollViewReader { proxy in
            Page(spacing: YubaiSpace.space16, topPadding: YubaiSpace.space8) {
                heading(group).id("unsortedGroupTop")
                categoryChoices(group)
                natureChoices(group)
                if use == .transfer { accountChoices(group) }
                purposeField
                entries(group).id(group.entries.count)
            }.accessibilityIdentifier("unsortedGroupScroll")
                .onChange(of: liveGroup?.entries.count) { _, _ in
                    proxy.scrollTo("unsortedGroupTop", anchor: .top)
                }
        }.navigationTitle(lastGroup.party).yubaiNavigation()
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
                applyButton(group, available: liveGroup != nil)
                    .padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.gapGroup)
                    .background(YubaiColor.canvas.ignoresSafeArea(edges: .bottom))
            }
            .allowsHitTesting(liveGroup != nil && !isDismissing)
            .onChange(of: snapshot?.revision, initial: true) { _, _ in
                if let liveGroup {
                    lastGroup = liveGroup
                    // Background checkpoints must preserve the user's exclusions.
                    // A successful partial apply resets them explicitly below.
                    if !excludedEntryIDs.isEmpty { excludedEntryIDs.formIntersection(liveGroup.entries.lazy.map(\.id)) }
                }
                else { dismissOnce() }
            }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func natureChoices(_ group: UnsortedPartyGroup) -> some View {
        let choices = UnsortedGroups.uses(for: group, in: store.current).filter { !$0.needsCategory }
        // Keep the transfer choice last, as in the approved expense layout.
        let ordered = group.inflow ? choices : choices.filter { $0 != .transfer } + choices.filter { $0 == .transfer }
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle(group.inflow ? "不是收入" : "不是支出")
            ChipFlow {
                ForEach(ordered, id: \.rawValue) { choice in
                    CategoryChoiceChip(title: choice.title, selected: use == choice) {
                        use = choice; category = nil; subcategory = nil; otherAccount = nil
                    }.accessibilityIdentifier("unsortedNature_" + choice.rawValue)
                }
            }
        }
    }
    private func categoryChoices(_ group: UnsortedPartyGroup) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("分类")
            CategoryPicker(income: group.inflow,
                           selected: category.map { .init(category: $0, subcategory: subcategory) },
                           suggested: UnsortedGroups.suggestedCategory(for: group, in: store.current),
                           applyingCount: group.entries.count - excludedEntryIDs.count, identifier: "unsorted") { choice, addition in
                if let addition {
                    if excludedEntryIDs.count < group.entries.count { return apply(group, choice: choice, addition: addition) }
                    guard store.update("添加分类", { try addition.apply(to: &$0) }) else { return false }
                }
                use = group.inflow ? .income : .expense; category = choice.category
                subcategory = choice.subcategory; otherAccount = nil; return true
            }.id(use?.rawValue)
        }
    }
    private func accountChoices(_ group: UnsortedPartyGroup) -> some View {
        let accounts: [Account] = UnsortedGroups.otherAccounts(for: group, in: store.current)
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("转到哪个账户")
            ChipFlow {
                ForEach(accounts) { account in
                    CategoryChoiceChip(title: account.name, selected: otherAccount == account.id) { otherAccount = account.id }
                        .accessibilityIdentifier("unsortedAccount_" + account.id.uuidString)
                }
            }
        }
    }
    private var purposeField: some View {
        Card(style: .list) { CardTextFieldRow(title: "用途", text: $purpose, identifier: "unsortedPurpose") }
    }
    private func applyButton(_ group: UnsortedPartyGroup, available: Bool) -> some View {
        let count = group.entries.count - excludedEntryIDs.count
        let result = category.map { $0 + (subcategory.map { " · " + $0 } ?? "") } ?? use?.title
        let title = count > 0 ? result.map { "\(count.formatted(.number.locale(Locale(identifier: "en_US")))) 笔记为 \($0)" } : nil
        return Button(title ?? "选一个分类") {
            guard let use else { return }
            let selected = Set(group.entries.lazy.filter { !excludedEntryIDs.contains($0.id) }.map(\.id))
            if store.applyUnsortedGroup(questionID: questionID, groupID: groupID, use: use, category: category,
                                        otherAccount: otherAccount, entryIDs: selected, purpose: purpose, subcategory: subcategory) {
                if let remaining = store.unsortedGroups(questionID: questionID)?.groupsByID[groupID] {
                    lastGroup = remaining; excludedEntryIDs.removeAll()
                } else { dismissOnce() }
            }
        }.buttonStyle(PrimaryButtonStyle(disabledBackground: YubaiColor.raised))
            .accessibilityIdentifier("applyUnsortedGroup").disabled(!available || isDismissing || !canApply(group))
    }
    private func apply(_ group: UnsortedPartyGroup, choice: CategoryAssignment, addition: CategoryAddition) -> Bool {
        let selected = Set(group.entries.lazy.filter { !excludedEntryIDs.contains($0.id) }.map(\.id))
        guard store.applyUnsortedGroup(questionID: questionID, groupID: groupID, use: group.inflow ? .income : .expense,
                                       category: choice.category, otherAccount: nil, entryIDs: selected, purpose: purpose,
                                       subcategory: choice.subcategory, addition: addition) else { return false }
        if let remaining = store.unsortedGroups(questionID: questionID)?.groupsByID[groupID] {
            lastGroup = remaining; excludedEntryIDs.removeAll()
        } else { dismissOnce() }
        return true
    }
    private func entries(_ group: UnsortedPartyGroup) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("这几笔")
            CardRows(group.entries, hasLeadingIcon: true) { entry in
                UnsortedEntryRow(entry: entry, inflow: group.inflow, selected: !excludedEntryIDs.contains(entry.id)) {
                    if !excludedEntryIDs.insert(entry.id).inserted { excludedEntryIDs.remove(entry.id) }
                }
            }
        }
    }
    private func heading(_ group: UnsortedPartyGroup) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space2) {
            Text(group.party).yubaiFont(YubaiFont.quote)
            HStack(spacing: YubaiSpace.space4) {
                Text("\(group.entries.count.formatted(.number.locale(Locale(identifier: "en_US")))) 笔 ·").yubaiFont(YubaiFont.callout)
                AmountLabel(cents: group.total, hide: store.preferences.hideAmounts, role: .small,
                            sign: group.inflow ? .inflow : .outflow, currency: false)
            }.foregroundStyle(YubaiColor.labelMuted)
        }
    }
    private func canApply(_ group: UnsortedPartyGroup) -> Bool {
        excludedEntryIDs.count < group.entries.count && purpose.count <= 4000 &&
        UnsortedGroups.canApply(to: group, use: use, category: category, otherAccount: otherAccount, in: store.current)
    }
    private func dismissOnce() {
        guard !isDismissing else { return }
        isDismissing = true
        dismiss()
    }
}

private struct UnsortedEntryRow: View {
    @Environment(AppStore.self) private var store
    let entry: Entry
    let inflow: Bool
    let selected: Bool
    let toggle: () -> Void
    @State private var expanded = false
    @State private var sourceFields: [UnsortedEntryField] = []

    var body: some View {
        let hideAmounts = store.preferences.hideAmounts
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            HStack(alignment: .top, spacing: YubaiSpace.space8) {
                Button(action: toggle) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .yubaiFont(YubaiFont.quote).foregroundStyle(selected ? YubaiColor.brand : YubaiColor.labelSecondary)
                        .frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).contentShape(Rectangle())
                }.buttonStyle(PressButtonStyle()).accessibilityLabel("选择这笔记录")
                    .accessibilityValue(selected ? "已选择" : "未选择")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("unsortedEntryToggle_" + entry.id.uuidString)
                Button { expanded.toggle() } label: {
                    VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                            Text(FixedFlowPresentation.monthDay(entry.date) + " " + ImportStatementText.time(entry.date))
                                .yubaiFont(YubaiFont.callout)
                            Spacer(minLength: YubaiSpace.none)
                            AmountLabel(cents: entry.amount, hide: hideAmounts, role: .small,
                                        sign: inflow ? .inflow : .outflow, currency: false).layoutPriority(1)
                        }
                        Text(UnsortedEntryPresentation.summary(entry)).yubaiFont(YubaiFont.caption)
                            .foregroundStyle(YubaiColor.labelSecondary).lineLimit(1).truncationMode(.tail)
                    }.frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityElement(children: .combine)
                    .accessibilityHint(expanded ? "收起原文" : "展开原文")
                    .accessibilityValue(expanded ? "已展开" : "已收起")
                    .accessibilityIdentifier("unsortedEntry_" + entry.id.uuidString)
            }
            if expanded {
                let fields = !hideAmounts && !sourceFields.isEmpty ? sourceFields
                    : UnsortedEntryPresentation.fallbackFields(entry, account: store.accountName(entry.accountID), hideAmounts: hideAmounts)
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    ForEach(fields.indices, id: \.self) { index in
                        Text(fields[index].key + "  " + fields[index].value).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelMuted)
                    .padding(YubaiSpace.space8).background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                    .padding(.leading, YubaiSize.tapMin + YubaiSpace.space8)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("unsortedEntrySource_" + entry.id.uuidString)
            }
        }.padding(.vertical, YubaiSpace.space8).opacity(selected ? 1 : 0.55)
            .task(id: expanded && !hideAmounts) {
                guard expanded, !hideAmounts, sourceFields.isEmpty, let row = entry.sourceRow else { return }
                let batch = store.imports.first { $0.id == entry.batchID }
                guard let attachmentID = entry.attachmentID ?? batch?.attachmentID,
                      let attachment = store.current.attachments.first(where: { $0.id == attachmentID }) else { return }
                let repository = store.localRepository
                let fields = await Task.detached(priority: .userInitiated) {
                    guard let data = try? repository.attachmentData(attachmentID) else { return [UnsortedEntryField]() }
                    return (try? UnsortedEntryPresentation.sourceFields(data: data, filename: attachment.name, sourceRow: row)) ?? []
                }.value
                guard !Task.isCancelled else { return }
                sourceFields = fields
            }
    }
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
        }.safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) { bottomBar }
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
                        .background(YubaiColor.paperInset, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
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
            .background(YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
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
