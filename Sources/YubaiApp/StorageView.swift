import SwiftUI
import YubaiCore

struct StorageView: View {
    @Environment(AppStore.self) private var store
    @State private var usage: StorageUsage?
    @State private var clearing = false
    @State private var sheet: StorageSheetDestination?
    private var attachments: StorageAttachments.Classification { StorageAttachments.classify(in: store.current) }
    private var attachmentSummary: String {
        var parts: [String] = []
        if !attachments.screenshots.isEmpty { parts.append("\(attachments.screenshots.count) 张截图") }
        if !attachments.originals.isEmpty { parts.append("\(attachments.originals.count) 份账单原件") }
        if let date = attachments.oldest { parts.append("最早 " + storageDate(date, format: "yyyy年M月")) }
        return parts.isEmpty ? "还没有" : parts.joined(separator: " · ")
    }
    private var recoverySummary: String {
        guard let usage else { return "正在读取…" }
        return "\(usage.recoveryCount) 份" + (usage.oldestRecovery.map { " · 最早 " + storageDate($0, format: "M月d日") } ?? "")
    }
    var body: some View {
        Page(spacing: YubaiSpace.gapSection) {
            VStack(alignment: .leading, spacing: YubaiSpace.none) {
                Text("占用").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                    if let usage {
                        let parts = StorageSize.text(usage.totalBytes).split(separator: " ")
                        Text(String(parts[0])).yubaiFont(YubaiFont.amountDisplay)
                        Text(String(parts[1])).yubaiFont(YubaiFont.lead)
                    }
                    else { Text("正在读取…").yubaiFont(YubaiFont.lead) }
                }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("storageHeadline")
            if let usage { usageCard(usage) }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    cardHeading("截图和账单原件", subtitle: attachmentSummary)
                    EntryFormDivider()
                    Button { sheet = .photos } label: { actionRow("删除旧截图", chevron: true) }
                        .accessibilityIdentifier("openStoragePhotos")
                }
            }
            Card(style: .list) {
                VStack(spacing: YubaiSpace.none) {
                    cardHeading("恢复历史", subtitle: recoverySummary)
                    EntryFormDivider()
                    NavigationLink { RecoveryVersionsView() } label: { actionRow("查看恢复历史", chevron: true) }
                        .accessibilityIdentifier("openStorageHistory")
                    EntryFormDivider()
                    Button { clearing = true } label: { actionRow("清除恢复历史") }
                        .disabled(usage == nil || usage?.recoveryCount == 0 || store.syncBusy)
                        .accessibilityIdentifier("clearStorageHistory")
                }
            }
        }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("storagePage")
            .safeAreaInset(edge: .bottom) {
                Button { sheet = .erase } label: {
                    Text("抹掉全部数据").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.amberInk)
                        .frame(maxWidth: .infinity, minHeight: YubaiSize.headerHeight)
                        .background(YubaiColor.card, in: Capsule())
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("openStorageErase")
                    .padding(.horizontal, YubaiSpace.insetPage).padding(.bottom, YubaiSpace.gapSection)
                    .padding(.top, YubaiSpace.gapGroup).frame(maxWidth: 1080).frame(maxWidth: .infinity)
                    .background(YubaiColor.canvas)
            }
            .navigationTitle("存储空间").yubaiNavigation()
            .toolbar { ToolbarItem(placement: .principal) { Text("存储空间").yubaiFont(YubaiFont.navTitle) } }
            .task(id: store.current.updatedAt) { await refreshUsage() }
            .confirmationDialog("清除恢复历史？", isPresented: $clearing, titleVisibility: .visible) {
                Button("清除 \(usage?.recoveryCount ?? 0) 份恢复历史", role: .destructive) {
                    if store.clearStorageHistory() { Task { await refreshUsage() } }
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(item: $sheet, onDismiss: { Task { await refreshUsage() } }) { destination in
                Group {
                    switch destination {
                    case .photos: StoragePhotosSheet()
                    case .erase: StorageEraseSheet(recoveryCount: usage?.recoveryCount)
                    }
                }.environment(store).environment(\.yubaiSheetSurface, true).appErrors()
            }
    }
    private func refreshUsage() async {
        let repository = store.localRepository
        do { usage = try await Task.detached(priority: .utility) { try repository.storageUsage() }.value }
        catch { store.error = error.localizedDescription }
    }
    private func usageCard(_ usage: StorageUsage) -> some View {
        let values = [usage.ledgerBytes, usage.attachmentBytes, usage.recoveryBytes]
        let labels = ["账本", "截图和账单原件", "恢复历史"]
        let colors = [YubaiColor.brand, YubaiColor.series2, YubaiColor.neutralStrong]
        let visible = values.indices.filter { values[$0] > 0 }
        return Card(style: .compact) {
            VStack(spacing: YubaiSpace.gapGroup) {
                GeometryReader { geometry in
                    HStack(spacing: YubaiSpace.space4) {
                        ForEach(visible, id: \.self) { i in
                            colors[i].frame(width: max(0, geometry.size.width - CGFloat(max(0, visible.count - 1)) * YubaiSpace.space4) * CGFloat(values[i]) / CGFloat(max(1, usage.totalBytes)))
                        }
                    }.clipShape(Capsule())
                }.frame(height: YubaiSpace.gapGroup).background(YubaiColor.neutralSoft, in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(values.indices.map { labels[$0] + " " + StorageSize.text(values[$0]) }.joined(separator: "，"))
                VStack(spacing: YubaiSpace.gapGroup) {
                    ForEach(values.indices, id: \.self) { i in
                        HStack(spacing: YubaiSpace.space8) {
                            Circle().fill(colors[i]).frame(width: YubaiSize.marker, height: YubaiSize.marker).accessibilityHidden(true)
                            Text(labels[i]).yubaiFont(YubaiFont.callout)
                            Spacer(minLength: YubaiSpace.space8)
                            Text(StorageSize.text(values[i])).yubaiFont(YubaiFont.amountSmall)
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
    private func cardHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
            Text(title).yubaiFont(YubaiFont.rowTitle)
            Text(subtitle).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.rowDouble, alignment: .leading)
    }
    private func actionRow(_ title: String, chevron: Bool = false) -> some View {
        HStack(spacing: YubaiSpace.gapGroup) {
            Text(title).yubaiFont(YubaiFont.row)
            Spacer(minLength: YubaiSpace.space8)
            if chevron { Image(systemName: "chevron.right").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).accessibilityHidden(true) }
        }.frame(maxWidth: .infinity, minHeight: YubaiSize.headerHeight).contentShape(Rectangle())
    }
}

private enum StorageSheetDestination: String, Identifiable {
    case photos, erase
    var id: Self { self }
}

private struct StoragePhotosSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var months = 6
    @State private var now = Date()
    private var selected: [Attachment] { StorageAttachments.oldScreenshots(in: store.current, months: months, now: now) }
    var body: some View {
        StorageSheet(title: "删除旧截图") {
            Text("删除多久以前的").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                .padding(.top, YubaiSpace.gapSection)
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: YubaiSpace.space8)) : AnyLayout(HStackLayout(spacing: YubaiSpace.space8))
            layout {
                ForEach([3, 6, 12], id: \.self) { value in
                    Button { months = value } label: {
                        Text(value == 3 ? "3 个月前" : value == 6 ? "半年前" : "一年前")
                            .yubaiFont(YubaiFont.callout, weight: months == value ? .medium : .regular)
                            .foregroundStyle(months == value ? YubaiColor.brandInk : YubaiColor.labelMuted)
                            .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.chipHeight)
                            .background(months == value ? YubaiColor.brandTint : YubaiColor.card, in: Capsule())
                            .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                    }.buttonStyle(PressButtonStyle()).accessibilityAddTraits(months == value ? .isSelected : [])
                }
            }.padding(.top, YubaiSpace.space8).accessibilityElement(children: .contain).accessibilityLabel("删除多久以前的截图")
            StorageSummaryCard(rows: [("截图", "\(selected.count) 张"), ("腾出", StorageSize.text(Int64(selected.reduce(0) { $0 + $1.byteCount }))), ("账目", "都留着")])
                .padding(.top, YubaiSpace.gapSection)
            StorageSummaryCard(rows: [("账单原件", "不删")], muted: true)
                .disabled(true).accessibilityLabel("账单原件不删，导入记录里仍可撤销")
                .padding(.top, YubaiSpace.gapGroup)
            Button("删除 \(selected.count) 张截图") {
                if store.deleteOldScreenshots(months: months, now: now) { dismiss() }
            }.buttonStyle(PrimaryButtonStyle()).disabled(selected.isEmpty).padding(.top, YubaiSpace.gapSection)
                .accessibilityIdentifier("deleteStoragePhotos")
            Button { dismiss() } label: {
                Text("取消").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.labelMuted)
                    .frame(maxWidth: .infinity, minHeight: YubaiSize.headerHeight).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).padding(.top, YubaiSpace.gapGroup)
        }
    }
}

private struct StorageEraseSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var backingUp = false
    @State private var currentRecoveryCount: Int?
    let recoveryCount: Int?
    private var backupDays: Int? {
        store.current.preferences.lastBackupAt.map { max(0, Calendar.current.dateComponents([.day], from: Dates.day($0), to: Dates.day(Date())).day ?? 0) }
    }
    private var entriesSinceBackup: Int? {
        guard let date = store.current.preferences.lastBackupAt else { return nil }
        let batches = Dictionary(uniqueKeysWithValues: store.current.imports.map { ($0.id, $0.importedAt) })
        return store.current.activeEntries.filter { entry in
            (entry.recordedAt ?? entry.batchID.flatMap { batches[$0] }).map { $0 > date } ?? false
        }.count
    }
    var body: some View {
        StorageSheet(title: "抹掉全部数据") {
            StorageSummaryCard(rows: [
                ("账目", "\(store.current.activeEntries.count.formatted()) 笔"),
                ("账户", "\(store.current.accounts.count) 个"),
                ("余白记得的", "\(store.current.memories.count) 条"),
                ("截图和账单原件", attachmentCount),
                ("恢复历史", currentRecoveryCount.map { "\($0) 份" } ?? "正在读取…")
            ]).padding(.top, YubaiSpace.gapSection)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) { backupStatus }
                VStack(alignment: .leading, spacing: YubaiSpace.space8) { backupStatus }
            }.padding(.top, YubaiSpace.gapGroup)
            Button("先加密备份") { backingUp = true }.buttonStyle(PrimaryButtonStyle()).padding(.top, YubaiSpace.gapAction)
                .accessibilityIdentifier("backupBeforeErase")
            Text("输入「抹掉」确认").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                .padding(.top, YubaiSpace.gapSection)
            TextField("抹掉", text: $confirmation).textFieldStyle(.plain).yubaiFont(YubaiFont.body)
                .padding(.horizontal, YubaiSpace.gapGroup).frame(minHeight: YubaiSize.tapMin)
                .background(YubaiColor.canvas, in: RoundedRectangle(cornerRadius: YubaiRadius.control))
                .overlay { RoundedRectangle(cornerRadius: YubaiRadius.control).stroke(YubaiColor.borderDashed, lineWidth: 1) }
                .accessibilityLabel("输入「抹掉」确认").accessibilityIdentifier("storageEraseConfirmation")
                .padding(.top, YubaiSpace.space8)
            Button { if store.eraseAllDeviceData() { dismiss() } } label: {
                Text("抹掉这台手机上的全部数据").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.amberInk)
                    .frame(maxWidth: .infinity, minHeight: YubaiSize.headerHeight)
                    .background(YubaiColor.card, in: Capsule()).opacity(confirmation == "抹掉" ? 1 : 0.55)
            }.buttonStyle(PressButtonStyle()).disabled(confirmation != "抹掉" || currentRecoveryCount == nil || store.syncBusy || store.checkingCloudAvailability)
                .padding(.top, YubaiSpace.gapGroup).accessibilityIdentifier("eraseDeviceData")
            Button { dismiss() } label: {
                Text("取消").yubaiFont(YubaiFont.row).foregroundStyle(YubaiColor.labelMuted)
                    .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).padding(.top, YubaiSpace.space8)
        }.task(id: backingUp) {
            guard !backingUp else { return }
            if currentRecoveryCount == nil { currentRecoveryCount = recoveryCount }
            let repository = store.localRepository
            do { currentRecoveryCount = try await Task.detached(priority: .utility) { try repository.storageUsage().recoveryCount }.value }
            catch { currentRecoveryCount = nil; store.error = error.localizedDescription }
        }.sheet(isPresented: $backingUp) {
            NavigationStack { BackupView() }.environment(store).environment(\.yubaiSheetSurface, true).appErrors()
                .presentationDragIndicator(.visible)
                #if os(macOS)
                .frame(minWidth: 540, minHeight: 600)
                #endif
        }
    }
    @ViewBuilder private var backupStatus: some View {
        Pill(text: backupDays.map { "上次备份 \($0) 天前" } ?? "还没备份过", variant: .amber, showsDot: false)
        if let count = entriesSinceBackup { Text("之后记了 \(count) 笔").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary) }
    }
    private var attachmentCount: String {
        let classified = StorageAttachments.classify(in: store.current)
        return "\(classified.screenshots.count + classified.originals.count) 份"
    }
}

private struct StorageSummaryCard: View {
    let rows: [(String, String)]
    var muted = false
    var body: some View {
        Card(style: .list) {
            VStack(spacing: YubaiSpace.none) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                        Text(rows[i].0).yubaiFont(YubaiFont.row)
                        Spacer(minLength: YubaiSpace.space8)
                        Text(rows[i].1).yubaiFont(YubaiFont.row).fontDesign(.rounded).monospacedDigit().multilineTextAlignment(.trailing)
                    }.foregroundStyle(muted ? YubaiColor.labelSecondary : YubaiColor.label)
                        .frame(minHeight: YubaiSize.rowSingle).accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct StorageSheetHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct StorageSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 600
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YubaiSpace.none) {
                Text(title).yubaiFont(YubaiFont.amountSummary).fontDesign(.default).frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                content
            }.padding(.horizontal, YubaiSpace.insetPage).padding(.top, YubaiSpace.gapGroup).padding(.bottom, YubaiSpace.gapSection)
                .background { GeometryReader { geometry in Color.clear.preference(key: StorageSheetHeight.self, value: geometry.size.height) } }
        }.scrollDismissesKeyboard(.interactively).foregroundStyle(YubaiColor.label).background(YubaiColor.raised)
            .onPreferenceChange(StorageSheetHeight.self) { contentHeight = $0 + YubaiSpace.gapSection }
            .presentationDetents([.height(contentHeight), .large]).presentationDragIndicator(.visible)
            .presentationBackground(YubaiColor.raised).presentationCornerRadius(28)
            #if os(macOS)
            .frame(minWidth: 540, idealWidth: 620, minHeight: 600, idealHeight: 720)
            #endif
    }
}

private func storageDate(_ date: Date, format: String) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = format
    return formatter.string(from: date)
}
