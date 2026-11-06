import SwiftUI
import YubaiCore

struct ImportQuestionCard: View {
    @Environment(AppStore.self) private var store
    let question: ImportQuestion
    let batchID: UUID
    var cardID: UUID? = nil
    var body: some View {
        let count = store.unsortedEntryCount(for: question)
        let title = question.isFallback ? "\(count.formatted(.number.locale(Locale(identifier: "en_US")))) 笔还没分类" : (store.current.preferences.hideAmounts ? "这几笔是什么用途？" : question.text)
        if !question.isFallback || count > 0 {
            Card(style: .compact, background: YubaiColor.amberTint) {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    Text(title)
                        .yubaiFont(YubaiFont.cardTitle).accessibilityIdentifier(question.isFallback ? "unsortedQuestionTitle" : "nowImportQuestion")
                    if question.isFallback {
                        HStack(spacing: YubaiSpace.space8) {
                            TabNavigationLink(.quickSortUnsorted(question.id)) { UnsortedQuickSortView(questionID: question.id) } label: { Text("一个个分") }
                                .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("quickSortUnsorted")
                            TabNavigationLink(.unsortedGroups(question.id)) { UnsortedGroupsView(questionID: question.id) } label: { Text("按对方分") }
                                .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("groupUnsortedByParty")
                        }
                    } else {
                        let ids = Set(question.entryIDs)
                        if let entry = store.sortedEntries.first(where: { ids.contains($0.id) }) {
                            Text(FixedFlowPresentation.monthDay(entry.date) + " · " + entry.title.components(separatedBy: " · ")[0])
                                .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).lineLimit(1)
                        }
                        ChipFlow {
                            ForEach(question.options.indices, id: \.self) { index in
                                Button(question.options[index].title) { store.answerImportQuestion(question, batchID: batchID, option: index) }
                                    .buttonStyle(NowCardButtonStyle()).disabled(store.current.preferences.hideAmounts)
                                    .accessibilityIdentifier("homeImportAnswer_\(question.id)_\(index)")
                            }
                            if let cardID {
                                Button("都不是") { store.sheet = .cardQuestion(cardID) }.buttonStyle(NowCardButtonStyle())
                                    .accessibilityIdentifier("describeImportQuestion")
                            }
                        }
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier(question.isFallback ? "unsortedQuestionCard" : "importQuestionCard")
        }
    }
}

/// Keep the destination attached to the list, even if its source row disappears.
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
    let questionID: UUID
    @State private var search = ""
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showingApply = false
    var body: some View {
        let snapshot = store.unsortedGroups(questionID: questionID)
        let visible: [UnsortedPartyGroup] = snapshot?.matching(search) ?? []
        let count = snapshot?.entryCount ?? 0
        let selected = snapshot?.groups.filter { selectedIDs.contains($0.id) } ?? []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: YubaiSpace.space8) {
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    Text(count.formatted(.number.locale(Locale(identifier: "en_US"))))
                        .yubaiFont(YubaiFont.amountLarge).accessibilityIdentifier("unsortedEntryCount")
                    Text("笔还没分类").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                }
                TextField("搜对方", text: $search).textFieldStyle(.plain).yubaiFont(YubaiFont.row)
                    .padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.segmentedHeight)
                    .background(YubaiColor.raised, in: Capsule()).accessibilityIdentifier("unsortedPartySearch")
                if !visible.isEmpty {
                    CardRows(visible) { group in groupRow(group, selected: selected) }
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8).padding(.bottom, YubaiSpace.gapSection)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).paperBackground().foregroundStyle(YubaiColor.label)
            .navigationTitle("按对方分").yubaiNavigation()
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
                        Button("记为…") { showingApply = true }
                            .buttonStyle(PrimaryButtonStyle(disabledBackground: YubaiColor.raised)).fixedSize(horizontal: true, vertical: false)
                            .disabled(selected.isEmpty).accessibilityIdentifier("unsortedApplySelected")
                    }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.gapGroup)
                        .background(YubaiColor.canvas.ignoresSafeArea(edges: .bottom))
                }
            }
            .sheet(isPresented: $showingApply) {
                UnsortedSelectionSheet(questionID: questionID, groupIDs: selectedIDs) {
                    showingApply = false; selecting = false; selectedIDs.removeAll()
                }.environment(store).presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible).yubaiSheetBackground().appErrors()
            }
            .onChange(of: snapshot?.revision) { _, _ in
                selectedIDs.formIntersection(snapshot?.groups.map(\.id) ?? [])
                if selectedIDs.isEmpty { showingApply = false }
            }
            .navigationDestination(for: UnsortedGroupRoute.self) { route in
                UnsortedGroupView(questionID: route.questionID, initialGroup: route.group)
            }
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
            NavigationLink(value: UnsortedGroupRoute(questionID: questionID, group: group)) { rowContent(group) }
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("unsortedGroup_" + group.id)
        }
    }
    private func rowContent(_ group: UnsortedPartyGroup) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
                if selecting {
                    ZStack {
                        Circle().strokeBorder(YubaiColor.labelSecondary, lineWidth: 2)
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
                AmountLabel(cents: group.total, hide: store.current.preferences.hideAmounts, role: .amount,
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

struct UnsortedUndoBar: View {
    @Environment(AppStore.self) private var store
    let notice: UnsortedUndoNotice
    var body: some View {
        HStack(spacing: YubaiSpace.space8) {
            Text(notice.label).yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("unsortedUndoMessage")
            Button("撤销") { store.undoUnsorted(notice.id) }
                .yubaiFont(YubaiFont.callout, weight: .semibold).frame(minWidth: YubaiSize.tapMin, minHeight: YubaiSize.tapMin)
                .buttonStyle(PressButtonStyle()).accessibilityIdentifier("quickSortUndo")
        }.foregroundStyle(YubaiColor.canvas)
            .padding(.leading, YubaiSpace.insetPage).padding(.trailing, YubaiSpace.space8)
            .frame(minHeight: YubaiSize.rowSingle).background(YubaiColor.label, in: Capsule())
            .task(id: notice.id) {
                do { try await Task.sleep(for: .seconds(YubaiMotion.toastLifetime)) } catch { return }
                if store.unsortedUndo?.id == notice.id { store.unsortedUndo = nil }
            }
    }
}

/// Shared immediate-apply controls for the quick card and the selection sheet.
private struct UnsortedImmediateChoices: View {
    @Environment(AppStore.self) private var store
    let groups: [UnsortedPartyGroup]
    var suggested: String? = nil
    let identifier: String
    let apply: (UnsortedUse, String?, UUID?) -> Void
    @State private var choosingAccount = false
    var body: some View {
        let inflow = groups.first?.inflow ?? false
        let categories = store.current.selectableCategories.filter { $0.income == inflow }
        let ordered = categories.filter { $0.name == suggested } + categories.filter { $0.name != suggested }
        let choices = UnsortedGroups.uses(for: groups, in: store.current).filter { !$0.needsCategory && $0 != .transfer }
        let canTransfer = UnsortedGroups.uses(for: groups, in: store.current).contains(.transfer)
        VStack(alignment: .leading, spacing: YubaiSpace.space16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: YubaiSpace.space8), count: 3), spacing: YubaiSpace.space8) {
                ForEach(ordered) { category in
                    Button { apply(inflow ? .income : .expense, category.name, nil) } label: {
                        Text(category.name).yubaiFont(YubaiFont.button, weight: category.name == suggested ? .semibold : .regular)
                            .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: YubaiSize.rowSingle)
                            .foregroundStyle(category.name == suggested ? YubaiColor.brandInk : YubaiColor.label)
                            .background(YubaiColor.raised, in: Capsule())
                            .overlay { if category.name == suggested { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 2) } }
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier + "Category_" + category.name)
                }
            }
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(inflow ? "不是收入" : "不是支出").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                ChipFlow {
                    ForEach(choices, id: \.rawValue) { use in
                        SuggestionChip(value: use.title, identifier: identifier + "Nature_" + use.rawValue) { apply(use, nil, nil) }
                    }
                    if canTransfer {
                        SuggestionChip(value: UnsortedUse.transfer.title, selected: choosingAccount, identifier: identifier + "Nature_transfer") {
                            choosingAccount.toggle()
                        }
                    }
                }
                if choosingAccount, canTransfer {
                    ChipFlow {
                        ForEach(UnsortedGroups.otherAccounts(for: groups, in: store.current)) { account in
                            SuggestionChip(value: account.name, identifier: identifier + "Account_" + account.id.uuidString) { apply(.transfer, nil, account.id) }
                        }
                    }
                }
            }
        }.disabled(groups.isEmpty)
    }
}

private struct UnsortedSelectionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let questionID: UUID
    let groupIDs: Set<String>
    let applied: () -> Void
    var body: some View {
        let snapshot = store.unsortedGroups(questionID: questionID)
        let groups = snapshot?.groups.filter { groupIDs.contains($0.id) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.space16) {
                Text("\(groups.reduce(0) { $0 + $1.entries.count }) 笔记为").yubaiFont(YubaiFont.heroLabel)
                UnsortedImmediateChoices(groups: groups, identifier: "unsortedSelected") { use, category, account in
                    if store.applyUnsortedGroups(questionID: questionID, groupIDs: groupIDs, use: use, category: category, otherAccount: account) { applied() }
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.vertical, YubaiSpace.space24)
        }.paperBackground().foregroundStyle(YubaiColor.label)
            .onChange(of: snapshot?.revision) { _, _ in if groups.isEmpty { dismiss() } }
    }
}

struct UnsortedQuickSortView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let questionID: UUID
    @State private var session = UnsortedQuickSession()
    @State private var detailRoute: UnsortedGroupRoute?
    @State private var isDismissing = false
    var body: some View {
        let snapshot = store.unsortedGroups(questionID: questionID)
        let groups = snapshot?.groups ?? []
        let group = session.queue.compactMap { snapshot?.groupsByID[$0] }.first ?? groups.first
        VStack(spacing: YubaiSpace.space16) {
            GeometryReader { proxy in
                Capsule().fill(YubaiColor.neutralSoft)
                    .overlay(alignment: .leading) {
                        Capsule().fill(YubaiColor.brand).frame(width: proxy.size.width * CGFloat(session.done) / CGFloat(max(1, session.total)))
                    }
            }.frame(height: YubaiSpace.space4).padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space4)
                .accessibilityLabel("分类进度").accessibilityValue("已分 \(session.done) 组，共 \(session.total) 组")
            ScrollView {
                if let group {
                    VStack(alignment: .leading, spacing: YubaiSpace.space16) {
                        quickCard(group)
                        UnsortedImmediateChoices(groups: [group], suggested: UnsortedGroups.suggestedCategory(for: group, in: store.current), identifier: "quickSort") { use, category, account in
                            if store.applyUnsortedGroup(questionID: questionID, groupID: group.id, use: use,
                                                        category: category, otherAccount: account, quickSort: true) {
                                session.record(group.id)
                                session.reconcile(store.unsortedGroups(questionID: questionID)?.groups ?? [])
                            }
                        }
                    }.id(group.id)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(x: YubaiSpace.space24).combined(with: .opacity), removal: .offset(x: -YubaiSpace.space24).combined(with: .opacity)))
                        .padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.space16)
                }
            }.animation(YubaiMotion.quick, value: group?.id)
        }.frame(maxWidth: 1080).frame(maxWidth: .infinity).paperBackground().foregroundStyle(YubaiColor.label)
            .navigationTitle("一个个分").yubaiNavigation()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Text("\(session.done)/\(session.total)").yubaiFont(YubaiFont.caption).monospacedDigit()
                        .foregroundStyle(YubaiColor.labelSecondary).accessibilityIdentifier("quickSortProgress")
                        .accessibilityValue("还没分类 \(snapshot?.entryCount ?? 0) 笔")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: YubaiSpace.none) {
                VStack(spacing: YubaiSpace.space8) {
                    if store.unsortedUndo != nil { Color.clear.frame(height: YubaiSize.rowSingle).accessibilityHidden(true) }
                    Button("跳过") { if let group { session.skip(group.id) } }
                        .yubaiFont(YubaiFont.button).foregroundStyle(YubaiColor.labelSecondary)
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).buttonStyle(.plain)
                        .disabled(group == nil).accessibilityIdentifier("quickSortSkip")
                }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.space4)
            }
            .navigationDestination(item: $detailRoute) { route in
                UnsortedGroupView(questionID: route.questionID, initialGroup: route.group)
            }
            .onChange(of: snapshot?.revision, initial: true) { _, _ in
                session.reconcile(groups)
                dismissIfEmpty(groups)
            }
            .onChange(of: detailRoute) { _, route in if route == nil { dismissIfEmpty(groups) } }
            .onChange(of: store.unsortedUndoRestoration) { _, restoration in
                guard let restoration, restoration.questionID == questionID else { return }
                for id in restoration.groupIDs.reversed() { session.restore(id) }
                session.reconcile(groups)
            }
    }
    private func dismissIfEmpty(_ groups: [UnsortedPartyGroup]) {
        guard groups.isEmpty, detailRoute == nil, !isDismissing else { return }
        isDismissing = true; dismiss()
    }
    private func quickCard(_ group: UnsortedPartyGroup) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.none) {
            Text(group.party).yubaiFont(YubaiFont.quote).accessibilityIdentifier("quickSortParty")
            HStack(spacing: YubaiSpace.space4) {
                Text("\(group.entries.count) 笔 ·").yubaiFont(YubaiFont.callout)
                AmountLabel(cents: group.total, hide: store.current.preferences.hideAmounts, role: .small,
                            sign: group.inflow ? .inflow : .outflow, currency: false)
            }.foregroundStyle(YubaiColor.labelMuted).padding(.top, YubaiSpace.space2)
                .accessibilityIdentifier("quickSortGroupCount")
            Rectangle().fill(YubaiColor.neutralSoft).frame(height: 1).padding(.top, YubaiSpace.space8)
            ForEach(Array(group.entries.prefix(2))) { entry in
                HStack(spacing: YubaiSpace.space8) {
                    Text(FixedFlowPresentation.monthDay(entry.date)).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
                    Text(UnsortedEntryPresentation.summary(entry)).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts, role: .small,
                                sign: group.inflow ? .inflow : .outflow, currency: false).fixedSize()
                }.yubaiFont(YubaiFont.caption).padding(.vertical, YubaiSpace.space8)
                Rectangle().fill(YubaiColor.neutralSoft).frame(height: 1)
            }
            Button { detailRoute = UnsortedGroupRoute(questionID: questionID, group: group) } label: {
                HStack(spacing: YubaiSpace.space4) {
                    Text("这 \(group.entries.count) 笔")
                    Image(systemName: "chevron.right")
                }.yubaiFont(YubaiFont.callout, weight: .medium).foregroundStyle(YubaiColor.brandInk)
                    .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("quickSortGroupDetails")
        }.padding(.horizontal, YubaiSpace.insetCard).padding(.top, YubaiSpace.insetCard).padding(.bottom, YubaiSpace.space8)
            .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.card))
    }
}

struct UnsortedGroupView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let questionID: UUID
    let groupID: String
    @State private var use: UnsortedUse?
    @State private var category: String?
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
        Page(spacing: YubaiSpace.space16, topPadding: YubaiSpace.space8) {
            heading(group)
            categoryChoices(group)
            natureChoices(group)
            if use == .transfer { accountChoices(group) }
            purposeField
            entries(group)
        }.accessibilityIdentifier("unsortedGroupScroll").navigationTitle("一组").yubaiNavigation()
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
                    SuggestionChip(value: choice.title, selected: use == choice, identifier: "unsortedNature_" + choice.rawValue) {
                        use = choice; category = nil; otherAccount = nil
                    }
                }
            }
        }
    }
    private func categoryChoices(_ group: UnsortedPartyGroup) -> some View {
        let choices: [YubaiCore.Category] = store.current.selectableCategories.filter { $0.income == group.inflow }
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("分类")
            ChipFlow {
                ForEach(choices) { choice in
                    SuggestionChip(value: choice.name, selected: category == choice.name, identifier: "unsortedCategory_" + choice.name) {
                        use = group.inflow ? .income : .expense; category = choice.name; otherAccount = nil
                    }
                }
            }
        }
    }
    private func accountChoices(_ group: UnsortedPartyGroup) -> some View {
        let accounts: [Account] = UnsortedGroups.otherAccounts(for: group, in: store.current)
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("转到哪个账户")
            ChipFlow {
                ForEach(accounts) { account in
                    SuggestionChip(value: account.name, selected: otherAccount == account.id, identifier: "unsortedAccount_" + account.id.uuidString) { otherAccount = account.id }
                }
            }
        }
    }
    private var purposeField: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("用途")
            TextField("可不填", text: $purpose).textFieldStyle(.plain).yubaiFont(YubaiFont.row)
                .lineLimit(1).padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.segmentedHeight)
                .background(YubaiColor.raised, in: Capsule())
                .accessibilityLabel("用途").accessibilityIdentifier("unsortedPurpose")
        }
    }
    private func applyButton(_ group: UnsortedPartyGroup, available: Bool) -> some View {
        let count = group.entries.count - excludedEntryIDs.count
        let result = category ?? use?.title
        let title = count > 0 ? result.map { "\(count.formatted(.number.locale(Locale(identifier: "en_US")))) 笔记为 \($0)" } : nil
        return Button(title ?? "选一个分类") {
            guard let use else { return }
            let selected = Set(group.entries.lazy.filter { !excludedEntryIDs.contains($0.id) }.map(\.id))
            if store.applyUnsortedGroup(questionID: questionID, groupID: groupID, use: use, category: category,
                                        otherAccount: otherAccount, entryIDs: selected, purpose: purpose) {
                if let remaining = store.unsortedGroups(questionID: questionID)?.groupsByID[groupID] {
                    lastGroup = remaining; excludedEntryIDs.removeAll()
                } else { dismissOnce() }
            }
        }.buttonStyle(PrimaryButtonStyle(disabledBackground: YubaiColor.raised))
            .accessibilityIdentifier("applyUnsortedGroup").disabled(!available || isDismissing || !canApply(group))
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
                AmountLabel(cents: group.total, hide: store.current.preferences.hideAmounts, role: .small,
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
        let hideAmounts = store.current.preferences.hideAmounts
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
                    : UnsortedEntryPresentation.fallbackFields(entry, account: store.current.accountName(entry.accountID), hideAmounts: hideAmounts)
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
                let batch = store.current.imports.first { $0.id == entry.batchID }
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
