import SwiftUI
import YubaiCore

/// 账本里点一笔：钱数、名字、分类账户日期，下面是几个去处和原文。
struct EntryDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var sourceFields: [UnsortedEntryField] = []
    @State private var splitting = false
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection) {
            if let entry = store.entriesByID[entryID] {
                header(entry)
                if entry.deletedAt == nil {
                    actions(entry)
                    sourceBlock(entry)
                    Button("删掉这一笔", action: delete).buttonStyle(DestructiveButtonStyle()).accessibilityIdentifier("deleteEntryDetail")
                } else {
                    Text("已删掉").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        .accessibilityLabel("这笔记录已删掉，不计入汇总")
                    Button("恢复") {
                        store.update("恢复记录") { ledger in
                            if let i = ledger.entries.firstIndex(where: { $0.id == entryID }) { ledger.entries[i].deletedAt = nil }
                        }
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("restoreEntry")
                    sourceBlock(entry)
                }
            } else { EmptyState("doc.questionmark", "记录已不存在", action: "返回", onAction: { dismiss() }) }
        }.amountPrivacy(hide).navigationTitle("这一笔").yubaiNavigation().accessibilityIdentifier("entryDetailPage")
            .sheet(isPresented: $splitting, onDismiss: {
                if store.entriesByID[entryID]?.deletedAt != nil { dismiss() }
            }) {
                UnitemizedSplitSheet(entryID: entryID).environment(store).appErrors().yubaiSheetBackground()
            }
    }

    private func header(_ entry: Entry) -> some View {
        let choice = store.current.normalizedCategory(for: entry)
        let category = Classification.displayCategory(choice.category) + (choice.subcategory.map { " · " + $0 } ?? "")
        let line = [category, store.accountName(entry.accountID), FixedFlowPresentation.monthDay(entry.date)].joined(separator: " · ")
        return VStack(spacing: YubaiSpace.space8) {
            AmountLabel(cents: entry.amount, hide: hide, role: .display, sign: entry.nature.inflow ? .inflow : .outflow)
            Text(entry.displayTitle).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.cardTitle).multilineTextAlignment(.center).accessibilityIdentifier("entryDetailTitle")
            Text(line).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.top, YubaiSpace.gapSection)
    }
    private func actions(_ entry: Entry) -> some View {
        let repeatable = entry.planID == nil && entry.rentID == nil && entry.nature != .transfer && !entry.isUnitemized
        return Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                row("改这一笔", value: nil, identifier: "entryDetailEdit") { store.sheetSource = nil; store.sheet = .editEntry(entry.id) }
                if entry.isUnitemized && entry.nature == .expense {
                    EntryFormDivider()
                    row("拆成几笔", value: nil, identifier: "entryDetailSplit") { splitting = true }
                }
                if repeatable {
                    EntryFormDivider()
                    row("每月都有？设成固定账单", value: nil, identifier: "entryDetailRepeat") { makeFixed(entry) }
                }
                EntryFormDivider()
                row("该不该买", value: "问余白", identifier: "entryDetailAsk") {
                    let question = "\(entry.displayTitle)，\(Money.text(entry.amount))，该不该买？"
                    store.sheetSource = nil; store.sheet = .ask(question)
                }
            }
        }
    }
    private func row(_ title: String, value: String?, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: YubaiSpace.gapGroup) {
                Text(title).yubaiFont(YubaiFont.body).dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: YubaiSpace.space8)
                if let value { Text(value).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
                Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true)
            }.frame(minHeight: YubaiSize.rowDouble).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier(identifier)
    }
    /// 导入的账留着银行原文；手记的没有原文，就不出这一块。
    @ViewBuilder private func sourceBlock(_ entry: Entry) -> some View {
        if EntryNotePresentation.isImported(entry) {
            let fields = !hide && !sourceFields.isEmpty ? sourceFields
                : UnsortedEntryPresentation.fallbackFields(entry, account: store.accountName(entry.accountID), hideAmounts: hide)
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text("银行原文").yubaiFont(YubaiFont.caption, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    .padding(.horizontal, YubaiSpace.space4)
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    if hide { Text("金额已隐藏") }
                    else {
                        ForEach(fields.indices, id: \.self) { index in
                            if !fields[index].value.isEmpty {
                                Text(fields[index].key + "  " + fields[index].value).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Text(entry.source + (entry.batchID == nil ? "" : " · 导入")).foregroundStyle(YubaiColor.labelSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).textSelection(.enabled)
                    .padding(YubaiSpace.gapGroup)
                    .background(YubaiColor.card, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                    .accessibilityElement(children: .contain).accessibilityIdentifier("entryDetailSource")
            }.task(id: hide) { await loadSource(entry) }
        }
    }
    @MainActor private func loadSource(_ entry: Entry) async {
        guard !hide, sourceFields.isEmpty, let row = entry.sourceRow else { return }
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
    private func makeFixed(_ entry: Entry) {
        store.update("设成固定账单") { ledger in try FixedFlows.repeatMonthly(entry, in: &ledger) }
    }
    private func delete() {
        if store.update("删掉", { ledger in
            if let i = ledger.entries.firstIndex(where: { $0.id == entryID }) { ledger.entries[i].deletedAt = Date() }
        }) { dismiss() }
    }
}

/// UI-only policy. Import.swift assigns these four source names and sourceRow;
/// committed imports also carry batchID. Capture/assistant/automatic entries
/// keep their purpose but do not expose legacy manual notes as a second field.
enum EntryNotePresentation {
    static func isImported(_ entry: Entry) -> Bool {
        entry.sourceRow != nil || entry.batchID != nil || ["文件", "微信", "支付宝", "BeeCount"].contains(entry.source)
    }
    static func importedNote(_ entry: Entry) -> String { isImported(entry) ? entry.note : "" }
    static func manualPurposes(_ entries: [Entry]) -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: entries.filter { !$0.note.isEmpty && !isImported($0) }.map { ($0.id, $0.displayTitle) })
    }
}
