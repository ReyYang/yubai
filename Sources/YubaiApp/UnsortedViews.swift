import SwiftUI
import YubaiCore

struct ImportQuestionCard: View {
    @Environment(AppStore.self) private var store
    let question: ImportQuestion
    let batchID: UUID
    var cardID: UUID? = nil
    var body: some View {
        let rows = UnsortedGroups.entries(for: question, in: store.current)
        let title = question.isFallback ? "\(rows.count.formatted(.number.locale(Locale(identifier: "en_US")))) 笔还没分类" : (store.current.preferences.hideAmounts ? "这几笔是什么用途？" : question.text)
        if !question.isFallback || !rows.isEmpty {
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

struct UnsortedGroupsView: View {
    @Environment(AppStore.self) private var store
    let questionID: UUID
    @State private var search = ""
    private var question: ImportQuestion? {
        store.current.imports.filter { $0.undoneAt == nil }.flatMap { $0.organization?.questions ?? [] }.first { $0.id == questionID }
    }
    var body: some View {
        let groups: [UnsortedPartyGroup] = question.map { UnsortedGroups.groups(for: $0, in: store.current) } ?? []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible: [UnsortedPartyGroup] = query.isEmpty ? groups : groups.filter { $0.party.localizedCaseInsensitiveContains(query) }
        let count: Int = groups.reduce(0) { $0 + $1.entries.count }
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
    }
    private func groupRow(_ group: UnsortedPartyGroup) -> some View {
        NavigationLink { UnsortedGroupView(questionID: questionID, groupID: group.id) } label: {
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
    private var question: ImportQuestion? {
        store.current.imports.filter { $0.undoneAt == nil }.flatMap { $0.organization?.questions ?? [] }.first { $0.id == questionID }
    }
    var body: some View {
        Page(spacing: YubaiSpace.space16, topPadding: YubaiSpace.space8) {
            if let question, let group = UnsortedGroups.groups(for: question, in: store.current).first(where: { $0.id == groupID }) {
                heading(group)
                useChoices(group)
                if use?.needsCategory == true { categoryChoices(group) }
                if use == .transfer { accountChoices(group) }
                ViewThatFits(in: .horizontal) {
                    applyButton(group, question: question).fixedSize(horizontal: true, vertical: false)
                    applyButton(group, question: question)
                }
                recentEntries(group)
            }
        }.navigationTitle("一组").yubaiNavigation()
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
    }
    private func useChoices(_ group: UnsortedPartyGroup) -> some View {
        let choices: [UnsortedUse] = UnsortedGroups.uses(for: group, in: store.current)
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("这些钱是")
            ChipFlow {
                ForEach(choices, id: \.rawValue) { choice in
                    SuggestionChip(value: choice.title, selected: use == choice, identifier: "unsortedUse_" + choice.rawValue) {
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
                    SuggestionChip(value: choice.name, selected: category == choice.name, identifier: "unsortedCategory_" + choice.name) { category = choice.name }
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
    private func applyButton(_ group: UnsortedPartyGroup, question: ImportQuestion) -> some View {
        Button("这 \(group.entries.count.formatted(.number.locale(Locale(identifier: "en_US")))) 笔都这样记") {
            if let use, store.applyUnsortedGroup(questionID: questionID, groupID: groupID, use: use, category: category, otherAccount: otherAccount) { dismiss() }
        }.buttonStyle(PrimaryButtonStyle(compact: true, disabledBackground: YubaiColor.raised))
            .accessibilityIdentifier("applyUnsortedGroup").disabled(!canApply(question))
    }
    private func recentEntries(_ group: UnsortedPartyGroup) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            sectionTitle("最近几笔")
            CardRows(Array(group.entries.prefix(4)), rowHeight: YubaiSize.tapMin) { entry in
                HStack {
                    Text(FixedFlowPresentation.monthDay(entry.date)).yubaiFont(YubaiFont.callout)
                    Spacer(minLength: YubaiSpace.space8)
                    AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts, role: .small,
                                sign: group.inflow ? .inflow : .outflow, currency: false)
                }
            }.accessibilityIdentifier("unsortedRecentEntries")
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
    private func canApply(_ question: ImportQuestion) -> Bool {
        guard let use else { return false }
        return UnsortedGroups.changeSet(groupID: groupID, question: question, use: use, category: category, otherAccount: otherAccount, in: store.current) != nil
    }
}
