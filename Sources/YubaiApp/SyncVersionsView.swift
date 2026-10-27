import SwiftUI
import YubaiCore

struct SyncVersionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        Page {
            if let choice = store.syncChoice {
                let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.gapGroup)) : AnyLayout(HStackLayout(alignment: .top, spacing: YubaiSpace.gapGroup))
                layout {
                    ForEach(choice.versions) { version in
                        versionCard(version, other: choice.versions.first { $0.id != version.id }, choice: choice)
                    }
                }
                if choice.switching { Button("取消切换", role: .cancel) { store.cancelSyncLocationChoice() }.disabled(store.syncBusy) }
                if store.syncBusy { ProgressView("正在保存…") }
            } else { Text("没有待选择的版本").yubaiFont(YubaiFont.callout) }
        }.navigationTitle("选择账本版本").yubaiNavigation().toolbar { CloseButton() }
    }
    private func versionCard(_ version: LedgerVersion, other: LedgerVersion?, choice: SyncChoice) -> some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                Text(version.deviceName ?? (version.id == "current" ? "iCloud 当前版本" : "另一版本")).yubaiFont(YubaiFont.cardTitle)
                Text(Dates.text(version.ledger.updatedAt, time: true)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    .accessibilityLabel("账本更新：" + Dates.text(version.ledger.updatedAt, time: true))
                Text(Dates.text(version.date, time: true)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                    .accessibilityLabel("版本时间：" + Dates.text(version.date, time: true))
                Text("\(version.ledger.activeEntries.count) 笔 · \(version.ledger.accounts.count) 个账户 · \(version.ledger.attachments.count) 份附件").yubaiFont(YubaiFont.caption)
                if let other {
                    Divider().overlay(YubaiColor.separator)
                    Text("差异").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    let metrics = differences(version.ledger, other.ledger)
                    if metrics.isEmpty { Text("0 项").yubaiFont(YubaiFont.amountSmall) }
                    ForEach(metrics, id: \.title) { metric in
                        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space4) {
                            Text(metric.title).yubaiFont(YubaiFont.caption)
                            Spacer(minLength: YubaiSpace.none)
                            Text("\(metric.count) 项").yubaiFont(YubaiFont.amountSmall).foregroundStyle(YubaiColor.amberInk)
                        }.accessibilityElement(children: .combine)
                    }
                    ForEach(version.differingEntries(from: other.ledger)) { entry in
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                            Text(entry.displayTitle).yubaiFont(YubaiFont.row)
                            Text(Dates.text(entry.date, time: true)).yubaiFont(YubaiFont.meta)
                            AmountLabel(cents: entry.amount, hide: store.current.preferences.hideAmounts)
                            Text(entry.nature.entryLabel + " · " + Classification.displayCategory(entry.category)).yubaiFont(YubaiFont.caption)
                            Text(version.ledger.accountName(entry.accountID)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            if !entry.note.isEmpty { Text(entry.note).yubaiFont(YubaiFont.caption).lineLimit(3) }
                            if entry.deletedAt != nil { Text("已删除").yubaiFont(YubaiFont.caption) }
                        }
                    }
                }
                Button("使用这份账本") { Task { await store.chooseSyncVersion(choice, id: version.id) } }
                    .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(store.syncBusy || store.locked)
                    .accessibilityLabel("使用" + (version.deviceName ?? "这份") + "账本")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func changed<T: Identifiable & Equatable>(_ left: [T], _ right: [T]) -> Int {
        let a = Dictionary(uniqueKeysWithValues: left.map { ($0.id, $0) })
        let b = Dictionary(uniqueKeysWithValues: right.map { ($0.id, $0) })
        return Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.count
    }
    private func differences(_ a: Ledger, _ b: Ledger) -> [(title: String, count: Int)] {
        let metrics: [(title: String, count: Int)] = [
            ("账目", changed(a.entries, b.entries)),
            ("账户", changed(a.accounts, b.accounts)),
            ("想克制的", changed(a.profile.restrain, b.profile.restrain)),
            ("愿意多花的", changed(a.profile.generous, b.profile.generous)),
            ("原则", Set(a.profile.principles).symmetricDifference(Set(b.profile.principles)).count),
            ("始终留着", a.profile.floorAmount == b.profile.floorAmount ? 0 : 1),
            ("消费观时间", a.profile.updatedAt == b.profile.updatedAt && a.profile.principleDates == b.profile.principleDates ? 0 : 1),
            ("安排", changed(a.plans, b.plans)),
            ("房租", changed(a.rents, b.rents)),
            ("存钱", changed(a.goals, b.goals)),
            ("附件", changed(a.attachments, b.attachments)),
            ("导入记录", changed(a.imports, b.imports)),
            ("分类", changed(a.categories, b.categories)),
            ("分类规则", a.categoryAliases == b.categoryAliases && a.classificationMemory == b.classificationMemory ? 0 : 1),
            ("余白记得的", changed(a.memories, b.memories)),
            ("心愿单", changed(a.wishlist, b.wishlist)),
            ("提醒", changed(a.cards, b.cards)),
            ("待确认修改", changed(a.pendingChanges, b.pendingChanges)),
            ("偏好设置", a.preferences == b.preferences ? 0 : 1),
            ("不再提醒", Set(a.mutedTopics).symmetricDifference(Set(b.mutedTopics)).count),
            ("每周来信", a.lastReflectionWeek == b.lastReflectionWeek ? 0 : 1),
            ("账本资料", a.schema == b.schema && a.id == b.id && a.isSample == b.isSample ? 0 : 1)
        ]
        return metrics.filter { $0.count > 0 }
    }
}

struct LedgerSyncSection: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Section("账本位置") {
            Picker("保存在", selection: Binding(get: { store.ledgerLocation }, set: { target in
                Task { await store.switchLedgerLocation(to: target) }
            })) {
                Text("仅本机").tag(LedgerLocation.local)
                if store.iCloudAvailable { Text("iCloud").tag(LedgerLocation.iCloud) }
            }.disabled(store.syncBusy || store.syncChoice != nil)
            if let status = store.syncStatus { Text(status).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
            if store.syncChoice != nil { Button("选择账本版本") { store.sheet = .syncVersions } }
            else if store.ledgerLocation == .iCloud {
                Button("重新读取与同步") { Task { await store.synchronizeLedger() } }.disabled(store.syncBusy)
            }
            Text("恢复历史与设备解锁设置：仅本机")
                .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.listRowBackground(YubaiColor.card)
    }
}
