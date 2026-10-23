import SwiftUI
import YubaiCore

/// Evidence opens the original record, including its source and existing associations.
struct EntryDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var deleting = false
    var body: some View {
        Page {
            if let entry = store.current.entries.first(where: { $0.id == entryID }) {
                Text(entry.displayTitle).yubaiFont(YubaiFont.lead).accessibilityIdentifier("entryDetailTitle")
                AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts, role: .display,
                            sign: entry.nature.inflow ? .inflow : .outflow, fractionDigits: 2)
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        LabeledContent("时间", value: Dates.text(entry.date, time: true))
                        LabeledContent("账户", value: store.current.accountName(entry.accountID))
                        if let other = entry.otherAccountID { LabeledContent("关联账户", value: store.current.accountName(other)) }
                        EntrySubcategoryRow(entry: entry)
                        if !entry.note.isEmpty { Text(entry.note) }
                        if let id = entry.planID, let plan = store.current.plans.first(where: { $0.id == id }) { Text("已关联：" + plan.title) }
                        if let id = entry.rentID, let rent = store.current.rents.first(where: { $0.id == id }) { Text("已关联：" + rent.title) }
                    }.yubaiFont(YubaiFont.row)
                }
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                        SectionHeading(title: "明细")
                        Text(entry.title)
                        LabeledContent("来源", value: entry.source)
                        if let row = entry.sourceRow { LabeledContent("原文件行号", value: String(row)) }
                        if !entry.externalID.isEmpty { LabeledContent("交易单号", value: entry.externalID).textSelection(.enabled) }
                        Text(entry.classificationReason).foregroundStyle(YubaiColor.labelSecondary)
                    }.yubaiFont(YubaiFont.callout)
                }
                if entry.deletedAt == nil {
                    Button("删除记录", role: .destructive) { deleting = true }.frame(minHeight: YubaiSize.tapMin)
                } else {
                    Text("这笔记录已删除，不计入汇总。需要恢复时，请使用撤销或恢复版本。")
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                }
            } else { EmptyState("doc.questionmark", "记录已不存在", "可能已恢复了另一份账本。") }
        }.navigationTitle("记录详情").yubaiNavigation()
            .confirmationDialog("删除这笔记录？可通过撤销或恢复版本找回。", isPresented: $deleting) {
                Button("删除记录", role: .destructive) {
                    if store.update("删除记录", { ledger in
                        if let i = ledger.entries.firstIndex(where: { $0.id == entryID }) { ledger.entries[i].deletedAt = Date() }
                    }) { dismiss() }
                }
            }
    }
}
