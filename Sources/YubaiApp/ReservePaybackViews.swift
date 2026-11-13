import SwiftUI
import YubaiCore

/// 每一笔提款只问一次；不补也由 Core 保存。
struct ReservePaybackOfferCard: View {
    @Environment(AppStore.self) private var store
    let offer: ReservePaybackOffer
    private var hide: Bool { store.preferences.hideAmounts }
    private var monthly: Int64 { (offer.amount + 2) / 3 }
    private var title: String {
        let amount = amount2(offer.amount, hide: hide)
        return offer.title.isEmpty ? "补回来 " + amount : "把" + offer.title + " " + amount + " 补回来"
    }
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                Text(title).yubaiFont(YubaiFont.rowTitle, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                ChipFlow {
                    Button("3 个月，每月多存 " + amount2(monthly, hide: hide)) { answer(3) }
                        .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("reservePaybackAccept")
                    Button("不补") { answer(nil) }
                        .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("reservePaybackDecline")
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("reservePaybackOffer")
    }
    private func answer(_ cycles: Int?) {
        let withdrawal = offer.withdrawal
        _ = store.update("补回来", entryMotion: false, showToast: false) { ledger in
            try Reserve.answerPayback(withdrawal, cycles: cycles, in: &ledger, now: Date())
        }
    }
}

struct ReservePaybackProgressList: View {
    @Environment(AppStore.self) private var store
    let identifier: String
    var body: some View {
        let rows = store.paybackProgress
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                Text("补回来").yubaiFont(YubaiFont.callout, weight: .semibold).foregroundStyle(YubaiColor.labelSecondary)
                    .padding(.horizontal, YubaiSpace.space4)
                CardRows(rows) { row in progressRow(row) }
            }.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        }
    }
    private func progressRow(_ row: ReservePaybackProgress) -> some View {
        let hide = store.preferences.hideAmounts
        let name: String = {
            if case .purchase(let id) = row.withdrawal { return store.entriesByID[id]?.displayTitle ?? "补回来" }
            return "补回来"
        }()
        return VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) {
                    Text(name).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle)
                    Spacer(minLength: YubaiSpace.space8)
                    progressAmount(row, hide: hide)
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    Text(name).accessibilityIdentifier("truncatableName").yubaiFont(YubaiFont.rowTitle)
                    progressAmount(row, hide: hide)
                }
            }
            ProgressLine(value: row.amount > 0 ? Double(row.paid) / Double(row.amount) : 1, tint: YubaiColor.brand)
            if !row.completed {
                Text("剩下 " + amount2(row.remaining, hide: hide)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }
        }.padding(.vertical, YubaiSpace.space8).accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier + "_" + row.id.uuidString)
    }
    private func progressAmount(_ row: ReservePaybackProgress, hide: Bool) -> some View {
        HStack(spacing: YubaiSpace.space4) {
            if row.completed { Image(systemName: "checkmark").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.brandInk) }
            Text(amount2(row.paid, hide: hide) + " / " + amount2(row.amount, hide: hide)).yubaiFont(YubaiFont.amountSmall).fixedSize()
        }
    }
}
