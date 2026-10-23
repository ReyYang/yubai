import SwiftUI
import YubaiCore

/// Evidence opens the original record, including its source and existing associations.
struct EntryDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    var body: some View {
        Page {
            if let entry = store.current.entries.first(where: { $0.id == entryID }) {
                Text(entry.displayTitle).yubaiFont(YubaiFont.lead).accessibilityIdentifier("entryDetailTitle")
                AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts, role: .display,
                            sign: entry.nature.inflow ? .inflow : .outflow, fractionDigits: 2)
                classificationCard(entry)
                sourceCard(entry)
                if entry.deletedAt == nil {
                    Button("删除记录", role: .destructive) { delete() }.frame(minHeight: YubaiSize.tapMin)
                } else {
                    Text("已删除").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                        .accessibilityLabel("这笔记录已删除，不计入汇总")
                    Button("恢复") {
                        store.update("恢复记录") { ledger in
                            if let i = ledger.entries.firstIndex(where: { $0.id == entryID }) { ledger.entries[i].deletedAt = nil }
                        }
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("restoreEntry")
                }
            } else { EmptyState("doc.questionmark", "记录已不存在", action: "返回", onAction: { dismiss() }) }
        }.navigationTitle("记录详情").yubaiNavigation()
    }
    private func delete() {
        if store.update("删除记录", { ledger in
            if let i = ledger.entries.firstIndex(where: { $0.id == entryID }) { ledger.entries[i].deletedAt = Date() }
        }) { dismiss() }
    }
    private func classificationCard(_ entry: Entry) -> some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                LabeledContent("时间", value: Dates.text(entry.date, time: true)).frame(minHeight: YubaiSize.rowSingle)
                LabeledContent("账户", value: store.current.accountName(entry.accountID)).frame(minHeight: YubaiSize.rowSingle)
                if let other = entry.otherAccountID { LabeledContent("关联账户", value: store.current.accountName(other)).frame(minHeight: YubaiSize.rowSingle) }
                EntrySubcategoryRow(entry: entry)
                if !entry.note.isEmpty { Text(entry.note) }
                if let id = entry.planID, let plan = store.current.plans.first(where: { $0.id == id }) { Text("已关联：" + plan.title) }
                if let id = entry.rentID, let rent = store.current.rents.first(where: { $0.id == id }) { Text("已关联：" + rent.title) }
            }.yubaiFont(YubaiFont.row)
        }
    }
    private func sourceCard(_ entry: Entry) -> some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                SectionHeading(title: "明细")
                Text(entry.title)
                LabeledContent("来源", value: entry.source)
                if let row = entry.sourceRow { LabeledContent("原文件行号", value: String(row)) }
                if !entry.externalID.isEmpty { LabeledContent("交易单号", value: entry.externalID).textSelection(.enabled) }
                if !entry.classificationReason.isEmpty && !(entry.source == "手动" && entry.classificationReason == "手动选择") {
                    Text(entry.classificationReason).foregroundStyle(YubaiColor.labelSecondary)
                }
            }.yubaiFont(YubaiFont.callout)
        }
    }

}
