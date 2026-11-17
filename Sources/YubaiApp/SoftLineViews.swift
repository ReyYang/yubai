import SwiftUI
import YubaiCore

/// Shared wording for the same per-period watch in formula, entry and insights.
enum SoftLineText {
    static func number(_ line: SoftLineUsage, value: Int64, hide: Bool) -> String {
        line.mode == .count ? "\(value) 次" : amount2(value, hide: hide)
    }
    static func status(_ line: SoftLineUsage, hide: Bool, includesTitle: Bool = false) -> String {
        (includesTitle ? line.title : "") + (line.isExceeded ? "超出 " : "还剩 ")
            + number(line, value: line.isExceeded ? line.exceeded : line.remaining, hide: hide)
    }
}

/// The formula and category detail edit the existing 消费观 watches.
struct SoftLineSection: View {
    @Environment(AppStore.self) private var store
    var category: String? = nil
    var editable = false
    @State private var choosing = false
    @State private var pendingArea: ProfileArea?
    @State private var target: SoftLineEditTarget?
    private var hide: Bool { store.preferences.hideAmounts }
    private var lines: [SoftLineUsage] {
        if let category { return store.categorySoftLines[store.current.resolveCategory(category, income: false)] ?? [] }
        return store.softLineUsage
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            if !lines.isEmpty {
                SectionHeading(title: "想克制的").padding(.horizontal, YubaiSpace.space4)
                CardRows(lines) { line in watchRow(line) }
                    .accessibilityIdentifier("softLineWatches")
            }
            Button {
                if let category {
                    edit(SoftLines.area(named: category, in: store.current) ?? ProfileArea(title: category, match: AreaMatch(categories: [category])), mode: .amount)
                } else { choosing = true }
            } label: {
                Label(category.map { "盯住整个" + Classification.displayCategory($0) } ?? "盯住某个分类", systemImage: "plus")
                    .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                    .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("addSoftLine")
        }.sheet(isPresented: $choosing, onDismiss: {
            if let area = pendingArea { pendingArea = nil; edit(area, mode: .amount) }
        }) {
            EntryMoreCategorySheet(income: false, selection: CategoryAssignment(category: ""), choose: { choice in
                let title = choice.subcategory ?? Classification.displayCategory(choice.category)
                let match = choice.subcategory.map { AreaMatch(subcategories: [choice.category + "/" + $0]) } ?? AreaMatch(categories: [choice.category])
                pendingArea = store.profile.restrain.first { $0.match == match } ?? ProfileArea(title: title, match: match)
                choosing = false
            }, dismiss: { choosing = false })
        }.sheet(item: $target) { target in
            SoftLineLimitSheet(area: target.area, mode: target.mode).environment(store).appErrors().yubaiSheetBackground()
        }
    }
    private func watchRow(_ line: SoftLineUsage) -> some View {
        VStack(alignment: .leading, spacing: YubaiSpace.space8) {
            Button {
                if let area = store.profile.restrain.first(where: { $0.id == line.areaID }) { edit(area, mode: line.mode) }
            } label: {
                VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                    AdaptiveValueRow {
                        Text(line.title).yubaiFont(YubaiFont.rowTitle).foregroundStyle(YubaiColor.label)
                    } value: {
                        Text((editable ? "每期 " + SoftLineText.number(line, value: line.limit, hide: hide) + " · " : "") + SoftLineText.status(line, hide: hide))
                            .yubaiFont(YubaiFont.callout).foregroundStyle(line.isExceeded ? YubaiColor.amberInk : YubaiColor.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ProgressLine(value: line.fraction, tint: line.isExceeded ? YubaiColor.amberDot : YubaiColor.brand,
                                 track: YubaiColor.card, height: YubaiSpace.space4)
                }.frame(minHeight: YubaiSize.tapMin).contentShape(Rectangle())
            }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("softLine_" + line.id)
            if editable {
                ChipFlow {
                    Button("改数") { edit(line, mode: line.mode) }.accessibilityIdentifier("editSoftLine_" + line.id)
                    Button(line.mode == .amount ? "按次数" : "按金额") { edit(line, mode: line.mode == .amount ? .count : .amount) }
                        .accessibilityIdentifier("modeSoftLine_" + line.id)
                    Button("不盯了") {
                        store.update("不盯了", entryMotion: false) { ledger in
                            ledger.profile.restrain.removeAll { $0.id == line.areaID }
                            ledger.profile.updatedAt = store.financialNow
                        }
                    }.accessibilityIdentifier("removeSoftLine_" + line.id)
                }.buttonStyle(NowCardButtonStyle())
            }
        }.padding(.vertical, YubaiSpace.space8)
    }
    private func edit(_ line: SoftLineUsage, mode: SoftLineUsage.Mode) {
        if let area = store.profile.restrain.first(where: { $0.id == line.areaID }) { edit(area, mode: mode) }
    }
    private func edit(_ area: ProfileArea, mode: SoftLineUsage.Mode) { target = SoftLineEditTarget(area: area, mode: mode) }
}

private struct SoftLineEditTarget: Identifiable {
    let area: ProfileArea
    let mode: SoftLineUsage.Mode
    var id: UUID { area.id }
}

private struct SoftLineLimitSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let area: ProfileArea
    let mode: SoftLineUsage.Mode
    @State private var keypad: EntryKeypad
    init(area: ProfileArea, mode: SoftLineUsage.Mode) {
        self.area = area; self.mode = mode
        let initial = mode == .amount ? area.softLimit?.periodAmount ?? 0 : Int64(area.softLimit?.periodCount ?? 0) * 100
        _keypad = State(initialValue: EntryKeypad(amount: initial))
    }
    private var valid: Bool {
        guard let value = keypad.amount, value >= 0 else { return false }
        return mode == .amount || value % 100 == 0 && value <= 1_000_000
    }
    var body: some View {
        AmountEntrySheet(title: area.title, keypad: $keypad, primaryTitle: "好", primaryIdentifier: "saveSoftLine", canSave: valid, counting: mode == .count, save: save) {
            ResultBar(label: mode == .count ? "每期次数" : "每期金额",
                      value: mode == .count ? "\((keypad.amount ?? 0) / 100) 次" : amount2(keypad.amount ?? 0, hide: store.preferences.hideAmounts))
        }.accessibilityIdentifier("softLineLimitSheet")
    }
    private func save() {
        guard valid, let amount = keypad.resolve() else { return }
        var updated = area
        updated.softLimit = mode == .amount ? SoftLimit(perPeriodAmount: amount) : SoftLimit(perPeriodCount: Int(amount / 100))
        if store.update("盯住" + area.title, entryMotion: false, { try SoftLines.set(updated, in: &$0, now: store.financialNow) }) { dismiss() }
    }
}
