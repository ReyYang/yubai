import SwiftUI
import YubaiCore

struct HomeReceiptView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.yubaiReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let receipt: DailyReceipt
    private var hide: Bool { store.preferences.hideAmounts }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            header
            Capsule().fill(YubaiColor.keyFn)
                .overlay(alignment: .top) { Capsule().fill(YubaiColor.labelSecondary.opacity(0.25)).frame(height: YubaiSize.separator) }
                .frame(height: YubaiSize.receiptSlotHeight).accessibilityHidden(true)
            paper.padding(.horizontal, YubaiSize.receiptInset).padding(.top, -YubaiSpace.space4)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("todayEntries")
    }
    private var header: some View {
        HStack {
            Text("今天记的").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
            Spacer(minLength: YubaiSpace.gapGroup)
            Button(action: openToday) {
                HStack(spacing: YubaiSpace.space2) {
                    Text("账本")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
            }.buttonStyle(TextLinkStyle(alignment: .trailing)).accessibilityIdentifier("receiptOpenLedger")
        }.padding(.horizontal, YubaiSpace.space4)
    }
    private var paper: some View {
        VStack(spacing: YubaiSpace.none) {
            VStack(spacing: YubaiSpace.space8) {
                masthead
                ReceiptRule()
                if receipt.count == 0 { ghost }
                else {
                    if receipt.omittedCount > 0 {
                        Button("还有 \(receipt.omittedCount) 笔", action: openToday)
                            .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                            .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
                            .buttonStyle(TextLinkStyle(alignment: .leading)).accessibilityIdentifier("receiptMoreEntries")
                    }
                    VStack(spacing: YubaiSpace.none) {
                        ForEach(receipt.entries) { entry in line(entry) }
                    }
                    ReceiptRule()
                    total
                }
            }.padding(.horizontal, YubaiSpace.space20).padding(.top, YubaiSpace.space16).padding(.bottom, YubaiSpace.space20)
                .background(YubaiColor.receiptPaper(for: scheme))
                .overlay(alignment: .topTrailing) {
                    BrandBambooShadow(opacity: 0.09).frame(width: YubaiSize.firstOpenRule, height: YubaiSize.firstOpenRule)
                        .rotationEffect(.degrees(-12)).offset(x: YubaiSpace.space20, y: -YubaiSpace.space4)
                }
                .clipped()
            ReceiptTornEdge().fill(YubaiColor.receiptPaper(for: scheme)).frame(height: YubaiSize.receiptTearHeight).accessibilityHidden(true)
        }.yubaiShadow(YubaiShadow.card)
    }
    private var masthead: some View {
        VStack(spacing: YubaiSpace.space2) {
            HStack(spacing: YubaiSpace.space6) {
                AssistantMark(size: YubaiFont.callout.size, color: YubaiColor.label).accessibilityHidden(true)
                Text("余白").yubaiFont(YubaiFont.heroLabel).tracking(YubaiSpace.space4)
            }.frame(maxWidth: .infinity)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) { date.fixedSize(); number }
                VStack(spacing: YubaiSpace.space2) { date; number }
            }.yubaiFont(YubaiFont.receiptTime).monospacedDigit().foregroundStyle(YubaiColor.labelSecondary)
        }
    }
    private var date: some View {
        let parts = Dates.calendar.dateComponents([.year, .month, .day], from: receipt.day)
        let stamp = String(format: "%04d.%02d.%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return Text(stamp + " " + receipt.day.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))))
            .lineLimit(1).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
            .yubaiTextLineBox(YubaiFont.receiptTime).accessibilityIdentifier("receiptDate")
    }
    @ViewBuilder private var number: some View {
        if receipt.count > 0 { Text("No.\(receipt.count)").fixedSize().accessibilityIdentifier("receiptNumber") }
    }
    private var ghost: some View {
        Button { store.homeEntrySession = true; store.beginFirstEntry() } label: {
            Group {
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text("--:--").yubaiFont(YubaiFont.receiptTime)
                        HStack(spacing: YubaiSpace.space8) { Text("第一笔").yubaiFont(YubaiFont.row); ReceiptRule(dotted: true); amount(0) }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                        Text("--:--").yubaiFont(YubaiFont.receiptTime)
                        Text("第一笔").yubaiFont(YubaiFont.row)
                        ReceiptRule(dotted: true)
                        amount(0)
                    }
                }
            }.foregroundStyle(YubaiColor.labelSecondary).opacity(0.40)
                .frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("记下今天第一笔").accessibilityIdentifier("receiptFirstEntry")
    }
    private var total: some View {
        VStack(spacing: YubaiSpace.space4) {
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text("合计").yubaiFont(YubaiFont.row, weight: .semibold).fixedSize()
                Spacer(minLength: YubaiSpace.none)
                amount(receipt.total, total: true).fixedSize()
              }
              VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text("合计").yubaiFont(YubaiFont.row, weight: .semibold)
                amount(receipt.total, total: true).frame(maxWidth: .infinity, alignment: .trailing)
              }
            }.frame(minHeight: YubaiSize.receiptRowHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(hide ? "金额已隐藏" : AmountLabel.text(receipt.total)).accessibilityIdentifier("receiptTotal")
            Rectangle().fill(YubaiColor.label.opacity(0.4)).frame(height: YubaiSize.separator)
            Rectangle().fill(YubaiColor.label.opacity(0.4)).frame(height: YubaiSize.separator)
        }
    }
    private func line(_ entry: Entry) -> some View {
        let highlighted = store.receiptEntryIDs.contains(entry.id)
        return ReceiptSwipeRow(enabled: store.receiptUndoEntryIDs.contains(entry.id), identifier: "undoReceipt_" + entry.id.uuidString, undo: { undo(entry) }) {
            Button { store.sheetSource = nil; store.homeEntrySession = false; store.sheet = .editEntry(entry.id) } label: {
                lineContents(entry)
                    .receiptPrint(highlighted: highlighted, trigger: store.receiptFeedbackTrigger)
                    .padding(.horizontal, YubaiSpace.space8).padding(.vertical, YubaiSpace.space2)
                    .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading)
                    .background(highlighted ? YubaiColor.brandTint : .clear, in: RoundedRectangle(cornerRadius: YubaiSpace.space6))
                    .contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("ledgerEntry_" + entry.id.uuidString)
                .accessibilityLabel(time(entry.date) + "，" + entry.displayTitle + "，" + amount2(entry.amount, hide: hide))
                .accessibilityValue(highlighted ? "已记下" : "")
        }.padding(.horizontal, -YubaiSpace.space8)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
    @ViewBuilder private func lineContents(_ entry: Entry) -> some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                Text(time(entry.date)).yubaiFont(YubaiFont.receiptTime).foregroundStyle(YubaiColor.labelSecondary)
                Text(entry.displayTitle).yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail).accessibilityIdentifier("truncatableName")
                HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) { ReceiptRule(dotted: true); entryAmount(entry).layoutPriority(1) }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
                Text(time(entry.date)).yubaiFont(YubaiFont.receiptTime).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
                Text(entry.displayTitle).yubaiFont(YubaiFont.row).lineLimit(1).truncationMode(.tail).accessibilityIdentifier("truncatableName")
                ReceiptRule(dotted: true).frame(minWidth: YubaiSpace.space8)
                entryAmount(entry).layoutPriority(1)
            }
        }
    }
    private func amount(_ cents: Int64, total: Bool = false) -> some View {
        Text(hide ? "••••" : AmountLabel.text(cents)).yubaiFont(total ? YubaiFont.receiptTotal : YubaiFont.receiptAmount)
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
            .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            .accessibilityLabel(hide ? "金额已隐藏" : AmountLabel.text(cents))
    }
    private func entryAmount(_ entry: Entry) -> some View { amount(entry.nature == .refund ? -entry.amount : entry.amount) }
    private func time(_ date: Date) -> String {
        let parts = Dates.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    private func openToday() {
        store.resetRootNavigation()
        store.ledgerPreset = LedgerPreset(mode: .detail, interval: DateInterval(start: receipt.day, end: Dates.addDays(1, to: receipt.day)))
        store.entryFilterDate = receipt.day; store.destination = .ledger
    }
    private func undo(_ entry: Entry) {
        guard store.receiptUndoEntryIDs.contains(entry.id) else { return }
        if store.update("撤销", entryMotion: false, showToast: false, { ledger in
            QuickCapture.undo(entryID: entry.id, in: &ledger)
        }) {
            store.receiptEntryIDs.remove(entry.id); store.receiptUndoEntryIDs.remove(entry.id)
        }
    }
}
