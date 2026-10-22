import SwiftUI
import YubaiCore

struct SyncVersionsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Form {
            if let choice = store.syncChoice {
                Section {
                    Text(choice.switching ? "两处账本不同，请选择继续使用哪一份。" : "账本有同步冲突，请选择继续使用哪一份。")
                    Text("请先核对下方的记录。")
                        .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    if choice.switching { Button("取消切换", role: .cancel) { store.cancelSyncLocationChoice() }.disabled(store.syncBusy) }
                }.listRowBackground(YubaiColor.card)
                ForEach(choice.versions) { version in
                    Section(version.deviceName ?? (version.id == "current" ? "iCloud 当前版本" : "另一版本")) {
                        Text("账本更新：\(Dates.text(version.ledger.updatedAt, time: true))")
                        Text("版本时间：\(Dates.text(version.date, time: true))").yubaiFont(YubaiFont.caption)
                        Text("\(version.ledger.activeEntries.count) 笔有效记录 · \(version.ledger.accounts.count) 个账户 · \(version.ledger.attachments.count) 份附件")
                        if let other = choice.versions.first(where: { $0.id != version.id }) {
                            let differences = version.differingEntries(from: other.ledger)
                            ForEach(differences) { entry in
                                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                                    Text("\(Dates.text(entry.date, time: true)) · \(entry.displayTitle) · \(Money.text(entry.amount))\(entry.deletedAt == nil ? "" : " · 已删除")")
                                    Text("\(entry.nature.entryLabel) · \(Classification.displayCategory(entry.category)) · \(version.ledger.accountName(entry.accountID))")
                                        .foregroundStyle(YubaiColor.labelSecondary)
                                    if !entry.note.isEmpty { Text(entry.note).lineLimit(3) }
                                }.yubaiFont(YubaiFont.caption)
                            }
                            let ids = Set(version.ledger.entries.map(\.id))
                            let missing = other.ledger.entries.filter { !ids.contains($0.id) }.count
                            if missing > 0 { Text("另一版本另有 \(missing) 笔记录。 ").yubaiFont(YubaiFont.caption) }
                            if differences.isEmpty && missing == 0 { Text("差异在账户、消费观、安排、附件或其他账本资料中。 ").yubaiFont(YubaiFont.caption) }
                        }
                        Button("使用这份账本") { Task { await store.chooseSyncVersion(choice, id: version.id) } }
                            .disabled(store.syncBusy || store.locked)
                    }.listRowBackground(YubaiColor.card)
                }
                if store.syncBusy { ProgressView(store.syncStatus ?? "正在保存…") }
            } else { Text("当前没有待选择的版本。") }
        }.editorForm().navigationTitle("选择账本版本").yubaiNavigation().toolbar { CloseButton() }
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
