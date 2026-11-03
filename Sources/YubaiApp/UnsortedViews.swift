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
                        TabNavigationLink(.unsortedGroups(question.id)) { UnsortedGroupsView(questionID: question.id) } label: { Text("按对方分") }
                            .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("groupUnsortedByParty")
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
private struct UnsortedGroupRoute: Hashable {
    let questionID: UUID
    let group: UnsortedPartyGroup
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.questionID == rhs.questionID && lhs.group.id == rhs.group.id }
    func hash(into hasher: inout Hasher) { hasher.combine(questionID); hasher.combine(group.id) }
}

struct UnsortedGroupsView: View {
    @Environment(AppStore.self) private var store
    let questionID: UUID
    @State private var search = ""
    var body: some View {
        let snapshot = store.unsortedGroups(questionID: questionID)
        let visible: [UnsortedPartyGroup] = snapshot?.matching(search) ?? []
        let count = snapshot?.entryCount ?? 0
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
                    CardRows(visible) { group in groupRow(group) }
                }
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.space8).padding(.bottom, YubaiSpace.gapSection)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).paperBackground().foregroundStyle(YubaiColor.label)
            .navigationTitle("按对方分").yubaiNavigation()
            .navigationDestination(for: UnsortedGroupRoute.self) { route in
                UnsortedGroupView(questionID: route.questionID, initialGroup: route.group)
            }
    }
    private func groupRow(_ group: UnsortedPartyGroup) -> some View {
        NavigationLink(value: UnsortedGroupRoute(questionID: questionID, group: group)) {
            HStack(spacing: YubaiSpace.gapGroup) {
                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                    Text(group.party).yubaiFont(YubaiFont.rowTitle).lineLimit(1).truncationMode(.tail)
                    Text("\(group.entries.count) 笔").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                AmountLabel(cents: group.total, hide: store.current.preferences.hideAmounts, role: .amount,
                            sign: group.inflow ? .inflow : .outflow, currency: false).layoutPriority(1)
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("unsortedGroup_" + group.id)
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
                    .padding(YubaiSpace.space8).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
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
