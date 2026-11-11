import SwiftUI
import YubaiCore

private struct ImportResultSnapshot: Sendable {
    var plans: [RecognizedImportPlan] = []
    var unclassifiedIDs: [UUID] = []
    var categoryCount = 0
    var pairCount = 0

    init() {}
    init(batchID: UUID, ledger: Ledger, now: Date) {
        plans = ImportRecognition.plans(batchID: batchID, in: ledger, now: now)
        let entries = ledger.activeEntries.filter { $0.batchID == batchID }
        unclassifiedIDs = entries.filter { Classification.isPending($0) }.map(\.id)
        categoryCount = ledger.imports.first { $0.id == batchID }?.organization?.categoryCount
            ?? entries.filter { !Classification.isPending($0) }.count
        pairCount = ledger.imports.first { $0.id == batchID }?.organization?.pairCount ?? 0
    }
}

struct ImportResultPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let batchID: UUID
    let hasNext: Bool
    let next: () -> Void
    let restart: () -> Void
    @State private var snapshot = ImportResultSnapshot()
    @State private var adding = false
    private var batch: ImportBatch? { store.imports.first { $0.id == batchID && $0.undoneAt == nil } }
    private var organizing: Bool { store.organizingBatchID != nil || store.organizingPendingImports }

    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            if let batch {
                Page(spacing: YubaiSpace.gapSection) {
                    Text("\(batch.importedCount) 笔，都进账本了。").yubaiFont(YubaiFont.lead).accessibilityIdentifier("importResultSummary")
                    if store.organizingBatchID == batchID { ProgressView("正在整理…") }
                    counts
                    if !snapshot.plans.isEmpty { recognizedPlans }
                    if let error = store.organizationErrors[batchID] {
                        InlineNote(text: error, style: .attention)
                        Button("现在整理") { Task { await store.organizeImport(batchID) } }
                            .buttonStyle(SecondaryButtonStyle()).disabled(organizing || !store.preferences.isAIEnabled(for: .importClassification))
                            .accessibilityIdentifier("retryImportOrganization")
                    }
                }
                actions
            } else {
                Page {
                    EmptyState("arrow.uturn.backward", "这一批已撤销", action: "继续导入", onAction: restart)
                    Text("有效记录 \(store.current.activeEntries.count) 笔").accessibilityIdentifier("activeEntryCount")
                }
            }
        }.accessibilityIdentifier("importResultPage")
            .task(id: "\(batchID)-\(store.ledgerRevision)") { await refresh() }
            #if DEBUG && targetEnvironment(simulator)
            .uiTestAccessibilityValue(UITestSupport.secondBatchState(in: store.current))
            #endif
    }

    @ViewBuilder private var counts: some View {
        if snapshot.categoryCount > 0 || snapshot.pairCount > 0 || !snapshot.unclassifiedIDs.isEmpty {
            Card(style: .compact) {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.gapGroup)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
                layout {
                    if snapshot.categoryCount > 0 { count("归了类", snapshot.categoryCount) }
                    if snapshot.pairCount > 0 { count("配成转账", snapshot.pairCount) }
                    if !snapshot.unclassifiedIDs.isEmpty {
                        NavigationLink { LetterTriageView(entryIDs: snapshot.unclassifiedIDs) } label: {
                            count("还没分类", snapshot.unclassifiedIDs.count, amber: true)
                        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("importResultUnclassified")
                    }
                }
            }
        }
    }
    private func count(_ title: String, _ value: Int, amber: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(title).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
            Text("\(value)").yubaiFont(YubaiFont.amount).foregroundStyle(amber ? YubaiColor.amberInk : YubaiColor.label)
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
    private var recognizedPlans: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
            Text("从流水里认出来的").yubaiFont(YubaiFont.caption, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                .padding(.horizontal, YubaiSpace.space4)
            CardRows(snapshot.plans) { candidate in planRow(candidate) }
                .accessibilityIdentifier("importRecognizedPlans")
            NavigationLink {
                Page {
                    ForEach(snapshot.plans) { candidate in
                        Card { planRow(candidate) }
                        CardRows(store.evidenceEntries(Set(candidate.links.map(\.entryID)), activeOnly: true)) { entry in
                            EntryLink(entry: entry, hideAmount: store.preferences.hideAmounts)
                        }
                    }
                }.navigationTitle("从流水里认出来的").yubaiNavigation()
            } label: { Text("一项项看").frame(minHeight: YubaiSize.tapMin) }
                .buttonStyle(SecondaryButtonStyle(compact: true)).accessibilityIdentifier("reviewRecognizedImportPlans")
        }
    }
    private func planRow(_ candidate: RecognizedImportPlan) -> some View {
        let plan = candidate.plan
        let day = plan.monthlyDay ?? Dates.calendar.component(.day, from: plan.dueDate)
        let schedule = plan.frequency == .monthly ? "每月 \(day) 号" : plan.frequency.label
        let detail = schedule + (candidate.kind == .salary ? " · 已到账 \(candidate.links.count) 次" : "")
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space4)) : AnyLayout(HStackLayout(spacing: YubaiSpace.gapGroup))
        return layout {
            VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                Text(plan.title).yubaiFont(YubaiFont.row)
                Text(detail).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            AmountLabel(cents: plan.amount, hide: store.preferences.hideAmounts, sign: plan.inflow ? .inflow : .outflow)
        }.frame(minHeight: YubaiSize.rowDouble).accessibilityElement(children: .combine)
            .accessibilityIdentifier("recognizedImportPlan_" + plan.id.uuidString)
    }
    private var actions: some View {
        VStack(spacing: YubaiSpace.space8) {
            if !snapshot.plans.isEmpty {
                Button("都加上", action: addAll).buttonStyle(PrimaryButtonStyle()).disabled(adding || organizing)
                    .accessibilityIdentifier("addAllRecognizedImportPlans")
            } else if hasNext {
                Button("继续下一份", action: next).buttonStyle(PrimaryButtonStyle()).disabled(organizing)
                    .accessibilityIdentifier("continueNextImport")
            } else {
                Button("回到账本") { store.destination = .ledger; store.sheet = nil }.buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("closeImportResult")
            }
            Button("整批撤销") { store.undoImport(batchID) }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
                .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).buttonStyle(PressButtonStyle()).disabled(organizing || adding)
                .accessibilityIdentifier("undoImportResult")
        }.padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.insetPage)
    }
    private func refresh() async {
        let ledger = store.current, revision = store.ledgerRevision, now = Date()
        let value = await Task.detached(priority: .userInitiated) { ImportResultSnapshot(batchID: batchID, ledger: ledger, now: now) }.value
        guard !Task.isCancelled, store.ledgerRevision == revision else { return }
        snapshot = value
    }
    private func addAll() {
        guard !adding, !organizing else { return }
        adding = true
        let now = Date()
        let saved = store.update("都加上", entryMotion: false, showToast: false) { ledger in
            _ = try ImportRecognition.addAll(batchID: batchID, in: &ledger, now: now)
            Finance.enablePaydayConfirmation(&ledger, now: now)
        }
        if saved { snapshot.plans = [] }
        adding = false
    }
}
