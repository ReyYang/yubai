import SwiftUI
import YubaiCore

/// 问余白 building blocks. They take display strings only; YubaiCore computes the values.
struct AskChangeLine: View {
    let label: String
    let from: String
    let to: String
    var toColor: Color = DS.Color.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AskSpec.rowsGap) {
            Text(label).dsText(DS.Font.tPill).foregroundStyle(DS.Color.ink2).dsFillWidth()
            Text(from + " →").dsText(AskSpec.number14).foregroundStyle(DS.Color.ink3).fixedSize()
            Text(to).dsText(DS.Font.nSpineLg).foregroundStyle(toColor).lineLimit(1)
                .minimumScaleFactor(HomeSpec.numberMinimumScale).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}

/// The answer card surface: raised, 1 pt separator, radius 18.
struct AskCardSurface: ViewModifier {
    var bottom: CGFloat = DS.Space.s16
    func body(content: Content) -> some View {
        content.padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s16).padding(.bottom, bottom)
            .dsFillWidth()
            .background(DS.Color.raised, in: .rect(cornerRadius: AskSpec.bubbleRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AskSpec.bubbleRadius, style: .continuous)
                .strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
    }
}

extension View {
    func askCard(bottom: CGFloat = DS.Space.s16) -> some View { modifier(AskCardSurface(bottom: bottom)) }
}

/// 该不该买: verdict word, change line, the model's one reason line, optional expanders and reminder.
struct AskVerdictCard: View {
    struct Expander: Identifiable {
        let id: String
        let title: String
        let rows: [AskFact]
    }
    let word: String
    let tone: PurchaseVerdict
    let change: (label: String, from: String, to: String, warning: Bool)
    let reason: String
    var expanders: [Expander] = []
    var remind: String? = nil
    var onRemind: () -> Void = {}
    @State private var open: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.dsReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        let reduced = reduceMotionOverride ?? systemReduceMotion
        VStack(alignment: .leading, spacing: .zero) {
            Text(word).dsText(AskSpec.verdict).foregroundStyle(color).accessibilityIdentifier("askVerdict")
            AskChangeLine(label: change.label, from: change.from, to: change.to, toColor: change.warning ? DS.Color.warnInk : DS.Color.ink)
                .padding(.top, DS.Space.s12)
            if !reason.isEmpty {
                Text(reason).dsText(AskSpec.body).foregroundStyle(DS.Color.ink).dsFillWidth()
                    .fixedSize(horizontal: false, vertical: true).padding(.top, DS.Space.s8)
            }
            if !expanders.isEmpty {
                VStack(spacing: .zero) {
                    ForEach(expanders) { expander in
                        let isOpen = open.contains(expander.id)
                        Button {
                            withAnimation(reduced ? nil : DSMotion.smoothAnimation) {
                                if isOpen { open.remove(expander.id) } else { open.insert(expander.id) }
                            }
                        } label: {
                            HStack(spacing: DS.Space.s8) {
                                Text(expander.title).dsText(DS.Font.tPill).monospacedDigit().foregroundStyle(DS.Color.ink2).dsFillWidth()
                                DSIconView(icon: .chevronDown, size: AskSpec.chevron, color: DS.Color.chevron)
                                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                                    .animation(reduced ? nil : DSMotion.snappyAnimation, value: isOpen)
                            }.frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
                        }.dsPressStyle()
                            .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                            .accessibilityValue(isOpen ? "已展开" : "已收起")
                            .accessibilityIdentifier("askExpander_" + expander.id)
                        if isOpen {
                            VStack(spacing: .zero) {
                                ForEach(expander.rows) { AskFactRow(key: $0.key, value: $0.value) }
                            }.padding(.bottom, DS.Space.s8)
                                .transition(reduced ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }.padding(.top, DS.Space.s12).clipped()
            }
            if let remind {
                Button(action: onRemind) {
                    Text(remind).dsText(DS.Font.tLabelStrong).monospacedDigit().foregroundStyle(DS.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: DS.Size.tapMin).dsPill(DS.Color.surface)
                }.dsPressStyle().padding(.top, AskSpec.buttonsTop).accessibilityIdentifier("askRemind")
            }
        }.askCard(bottom: expanders.isEmpty ? DS.Space.s16 : DS.Space.s4)
            .accessibilityElement(children: .contain).accessibilityIdentifier("askVerdictCard")
    }

    private var color: Color {
        switch tone {
        case .skip: DS.Color.warnStrong
        case .wait: DS.Color.warnInk
        case .buy: DS.Color.accentInk
        }
    }
}

/// One key/value fact: 72 pt key column, right-aligned number.
struct AskFactRow: View {
    let key: String
    let value: String
    var separator = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
            Text(key).dsText(DS.Font.tSub).foregroundStyle(DS.Color.ink3).frame(width: AskSpec.factKey, alignment: .leading)
            Text(value).dsText(AskSpec.number14).foregroundStyle(DS.Color.ink).multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(.vertical, DS.Space.s8).frame(minHeight: AskSpec.factRow)
            .overlay(alignment: .top) { if separator { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
            .accessibilityElement(children: .combine)
    }
}

/// 审批卡.
struct AskApprovalCard: View {
    let title: String
    /// nil for a change dated after today: 还能花 does not move yet.
    let change: (label: String, from: String, to: String, better: Bool)?
    let facts: [AskFact]
    let action: String
    var onEdit: () -> Void = {}
    var onConfirm: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(title).dsText(AskSpec.approvalTitle).monospacedDigit().foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let change {
                AskChangeLine(label: change.label, from: change.from, to: change.to, toColor: change.better ? DS.Color.accentInk : DS.Color.ink)
                    .padding(.top, DS.Space.s12).padding(.bottom, DS.Space.s12)
            }
            VStack(spacing: .zero) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                    AskFactRow(key: fact.key, value: fact.value, separator: index > 0)
                }
            }.overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
                .padding(.top, change == nil ? DS.Space.s8 : .zero)
            AskTwoButtons(primary: action, onEdit: onEdit, onPrimary: onConfirm)
        }.askCard().accessibilityElement(children: .contain).accessibilityIdentifier("askApprovalCard")
    }
}

/// The two action buttons sized 1 : 1.6.
struct AskTwoButtons: View {
    let primary: String
    var enabled = true
    let onEdit: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        AskSplit(share: AskSpec.primaryShare, gap: AskSpec.gap10) {
            Button(action: onEdit) {
                Text("修改").dsText(HomeSpec.medium).foregroundStyle(DS.Color.ink)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.tapMin).dsPill(DS.Color.surface)
            }.dsPressStyle().accessibilityIdentifier("askEdit")
            Button(action: onPrimary) {
                Text(primary).dsText(DS.Font.tLabelStrong).monospacedDigit().foregroundStyle(DS.Color.onAccent).lineLimit(1)
                    .minimumScaleFactor(HomeSpec.numberMinimumScale)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.tapMin).dsPill(DS.Color.accent)
                    .opacity(enabled ? 1 : DSInteraction.reducedPressOpacity)
            }.dsPressStyle().disabled(!enabled).accessibilityIdentifier("askPrimary")
        }.padding(.top, AskSpec.buttonsTop)
    }
}

/// Two children, the second `share` times as wide as the first.
struct AskSplit: Layout {
    let share: CGFloat
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let widths = split(width)
        let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, split(bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + gap
        }
    }

    private func split(_ width: CGFloat) -> [CGFloat] {
        let first = max(0, width - gap) / (1 + share)
        return [first, max(0, width - gap) - first]
    }
}

/// One recognized row in 截图批量记账.
struct AskBatchRow: View {
    let name: String
    let detail: String
    let amount: String
    let checked: Bool
    var duplicate = false
    /// Found on the screenshot but left out by the model: 「待确认」.
    var missed = false
    var income = false
    var separator = true
    var onToggle: () -> Void = {}

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AskSpec.gap10) {
                AskCheckbox(checked: checked)
                VStack(alignment: .leading, spacing: .zero) {
                    HStack(spacing: AskSpec.flagInset) {
                        Text(name).dsText(HomeSpec.medium).foregroundStyle(DS.Color.ink).lineLimit(1)
                        if duplicate || missed {
                            Text(missed ? "待确认" : "可能重复").dsText(AskSpec.badge).foregroundStyle(DS.Color.warnInk)
                                .padding(.horizontal, AskSpec.flagInset).frame(height: AskSpec.flagHeight)
                                .dsPill(DS.Color.warnSoft).fixedSize()
                        }
                    }
                    Text(detail).dsText(DS.Font.tCaption).foregroundStyle(DS.Color.ink3).lineLimit(1)
                }.dsFillWidth()
                Text(amount).dsText(AskSpec.number15Strong)
                    .foregroundStyle(income ? DS.Color.accentInk : (checked ? DS.Color.ink : DS.Color.ink3)).fixedSize()
            }.frame(minHeight: AskSpec.batchRow).contentShape(Rectangle())
        }.dsPressStyle()
            .overlay(alignment: .top) { if separator { DS.Color.separator.frame(height: DS.Stroke.hairline) } }
            .accessibilityAddTraits(checked ? .isSelected : [])
            .accessibilityValue(checked ? "记下" : "不记")
    }
}

struct AskCheckbox: View {
    let checked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
        RoundedRectangle(cornerRadius: AskSpec.checkboxRadius, style: .continuous)
            .fill(checked ? DS.Color.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: AskSpec.checkboxRadius, style: .continuous)
                .strokeBorder(checked ? DS.Color.accent : DS.Color.separator, lineWidth: DS.Stroke.focus))
            .overlay {
                if checked {
                    DSIconView(icon: .done, size: AskSpec.check, color: DS.Color.onAccent)
                        .transition(reduced ? .opacity : .scale.combined(with: .opacity))
                }
            }
            .frame(width: AskSpec.checkbox, height: AskSpec.checkbox)
            .animation(reduced ? nil : DSMotion.snappyAnimation, value: checked)
            .sensoryFeedback(DSMotion.Haptic.toggle, trigger: checked)
    }
}

/// The pinned composer: 附图, the field and the mic.
struct AskComposer: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var recording = false
    var attachEnabled = true
    var onAttach: () -> Void = {}
    var onMic: () -> Void = {}
    var onSend: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: AskSpec.gap10) {
            Button(action: onAttach) {
                DSIconView(icon: .screenshot, size: DS.Size.icon, color: DS.Color.ink2)
                    .frame(width: DS.Size.askH, height: DS.Size.askH)
                    .background(DS.Color.surface, in: Circle())
                    .opacity(attachEnabled ? 1 : DSInteraction.reducedPressOpacity)
            }.dsPressStyle().disabled(!attachEnabled).accessibilityLabel("附图").accessibilityIdentifier("askAttach")
            HStack(spacing: .zero) {
                DSAskField(text: $text, focus: focus, onSubmit: onSend)
                Button(action: onMic) {
                    DSIconView(icon: .voice, size: DS.Size.brandTile, color: recording ? DS.Color.accent : DS.Color.ink2)
                        .frame(width: AskSpec.micBox, height: DS.Size.askH).contentShape(Rectangle())
                }.dsPressStyle().accessibilityLabel(recording ? "停止听写" : "语音输入").accessibilityIdentifier("askMic")
            }.padding(.leading, DS.Space.s16).padding(.trailing, AskSpec.fieldTrailing)
                .frame(height: DS.Size.askH)
                .background(DS.Color.raised, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.separator, lineWidth: DS.Stroke.hairline))
        }.padding(.horizontal, DS.Space.s16).padding(.top, AskSpec.composerTop)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(DS.Color.bg)
            .overlay(alignment: .top) { DS.Color.separator.frame(height: DS.Stroke.hairline) }
    }
}

/// A capsule chip: the follow-up answers.
struct AskChip: View {
    let title: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).dsText(selected ? AskSpec.chipSelected : DS.Font.tPill)
                .foregroundStyle(selected ? DS.Color.onAccent : DS.Color.ink).lineLimit(1)
                .padding(.horizontal, AskSpec.chipInset).frame(height: DS.Size.pillH)
                .background(selected ? DS.Color.accent : DS.Color.raised, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(selected ? DS.Color.accent : DS.Color.separator, lineWidth: DS.Stroke.hairline))
                .frame(minHeight: DS.Size.tapMin).contentShape(Rectangle())
        }.dsPressStyle()
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wrapping row for chips.
struct AskFlow: Layout {
    var spacing: CGFloat = DS.Space.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows.removeLast()
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows.append(row)
        }
        return rows
    }
}
