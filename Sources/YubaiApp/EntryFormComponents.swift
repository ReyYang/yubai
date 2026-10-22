import SwiftUI
import YubaiCore

struct ManualSheetHeader: View {
    let title: String
    var actionTitle = "保存"
    var actionImage: String? = nil
    var primary = true
    var showsAction = true
    var enabled = true
    let cancel: () -> Void
    let action: () -> Void
    var body: some View {
        ZStack {
            Text(title).yubaiFont(YubaiFont.navTitle)
            HStack {
                Button("取消", action: cancel).yubaiFont(YubaiFont.row)
                    .padding(.horizontal, 16).frame(height: 36).background(YubaiColor.card, in: Capsule())
                    .frame(minHeight: YubaiSize.tapMin).accessibilityIdentifier("cancelManualSheet")
                Spacer()
                if showsAction { Button(action: action) {
                    HStack(spacing: 6) {
                        if let actionImage { Image(systemName: actionImage) }
                        Text(actionTitle)
                    }.yubaiFont(YubaiFont.row, weight: primary ? .medium : .regular)
                        .padding(.horizontal, 14).frame(height: 36)
                        .foregroundStyle(primary ? YubaiColor.onBrand : YubaiColor.label)
                        .background(primary ? YubaiColor.brand : YubaiColor.card, in: Capsule())
                }.frame(minHeight: YubaiSize.tapMin).disabled(!enabled).opacity(enabled ? 1 : 0.5)
                    .accessibilityIdentifier(actionTitle == "导入" ? "importFromEntry" : "saveManualSheet")
                }
            }
        }.frame(height: YubaiSize.headerHeight).buttonStyle(PressButtonStyle())
    }
}

/// Chips wrap at their intrinsic width, including at accessibility text sizes.
struct EntryChipLayout: Layout {
    var spacing: CGFloat = YubaiSpace.space8
    private func arrangement(_ subviews: Subviews, width: CGFloat) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0; var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width ?? 354).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = arrangement(subviews, width: bounds.width).1
        for (index, view) in subviews.enumerated() { view.place(at: CGPoint(x: bounds.minX + points[index].x, y: bounds.minY + points[index].y), anchor: .topLeading, proposal: .unspecified) }
    }
}

struct EntryCategoryChips: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let frequent: [String]
    let all: [String]
    @Binding var selection: String
    var didSelect: () -> Void = {}
    var limit = 5
    @State private var picking = false
    private var visible: [String] {
        var rows = Array(frequent.prefix(limit))
        if !rows.contains(selection), !selection.isEmpty {
            if rows.count == limit { rows.removeLast() }
            rows.append(selection)
        }
        return rows
    }
    var body: some View {
        EntryChipLayout {
            ForEach(visible, id: \.self) { name in
                Button { selection = name; didSelect() } label: {
                    Text(name).yubaiFont(YubaiFont.callout, weight: selection == name ? .medium : .regular)
                        .padding(.horizontal, 12).frame(height: YubaiSize.chipHeight)
                        .background(selection == name ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
                        .overlay { if selection == name { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
                }.chipSelection(selection == name).accessibilityAddTraits(selection == name ? .isSelected : [])
            }
            Button("更多") { picking = true }.yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted)
                .padding(.horizontal, 12).frame(height: YubaiSize.chipHeight)
                .overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: 1) }
        }.buttonStyle(PressButtonStyle()).animation(YubaiMotion.control(reduceMotion: reduceMotion), value: selection)
            .sheet(isPresented: $picking) {
                NavigationStack {
                    List(all, id: \.self) { name in
                        Button { selection = name; didSelect(); picking = false } label: {
                            HStack { Text(name); Spacer(); if name == selection { Image(systemName: "checkmark").foregroundStyle(YubaiColor.brandInk) } }.contentShape(Rectangle())
                        }.listRowBackground(YubaiColor.card)
                    }.scrollContentBackground(.hidden).navigationTitle("分类").yubaiNavigation()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { picking = false } } }
                }.presentationDragIndicator(.visible)
            }
    }
}

struct EntryFormRow<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        HStack(spacing: 12) {
            Text(title).yubaiFont(YubaiFont.row).fixedSize()
            Spacer(minLength: 0)
            content
        }.frame(minHeight: 46).yubaiFont(YubaiFont.row)
    }
}

struct EntryFormDivider: View {
    var body: some View { Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true) }
}

struct EntryAccountMenu: View {
    let accounts: [Account]
    let balances: [UUID: Int64]
    @Binding var selection: UUID?
    var showsBalance = false
    var optional = false
    var body: some View {
        Menu {
            if optional { Button("不指定") { selection = nil } }
            ForEach(accounts) { account in
                Button(account.name + " · 余额 " + balanceText(account.id)) { selection = account.id }
            }
        } label: {
            let account = accounts.first { $0.id == selection }
            Text((account?.name ?? (optional ? "不指定" : "选择账户")) + (showsBalance && account != nil ? " · 余额 " + balanceText(account!.id) : ""))
                .yubaiFont(YubaiFont.callout).lineLimit(1).padding(.horizontal, 12).frame(minHeight: 30)
                .background(YubaiColor.raised, in: Capsule())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel("账户")
    }
    @Environment(AppStore.self) private var store
    private func balanceText(_ id: UUID) -> String {
        store.current.preferences.hideAmounts ? "••••" : AmountLabel.text(balances[id] ?? 0, decimals: (balances[id] ?? 0) % 100 == 0 ? 0 : 2)
    }
}

struct EntryDateChip: View {
    @Binding var date: Date
    var time = false
    @State private var picking = false
    @State private var latestDate = Date()
    var body: some View {
        Button { latestDate = Date(); picking = true } label: {
            Text(time ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : ManualBookkeeping.dayLabel(date))
                .yubaiFont(time ? YubaiFont.amountSmall : YubaiFont.callout)
                .padding(.horizontal, 12).frame(minHeight: 30).background(YubaiColor.raised, in: Capsule())
        }.buttonStyle(PressButtonStyle()).popover(isPresented: $picking) {
            VStack {
                if time {
                    DatePicker("时间", selection: $date, in: ...latestDate, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 240).fixedSize()
                } else {
                    DatePicker("日期", selection: $date, in: ...latestDate, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().frame(width: 320, height: 360).fixedSize()
                }
                Button("完成") { picking = false }.frame(minHeight: YubaiSize.tapMin)
            }.padding(YubaiSpace.space18).transaction { $0.animation = nil }
                #if os(iOS)
                .presentationCompactAdaptation(.popover)
                #endif
        }
    }
}
