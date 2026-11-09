import SwiftUI
import YubaiCore

private func partShare(_ value: Int) -> String {
    let names = ["零", "一", "两", "三", "四", "五", "六", "七", "八", "九", "十"]
    return (names.indices.contains(value) ? names[value] : String(value)) + "成"
}

extension YubaiFont {
    static let partBalance = Style(size: 14, lineHeight: 20, weight: .semibold, family: .num, relativeTo: .footnote)
}

struct SpendingPartsCard: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if !store.current.spendingParts.isEmpty {
            let summary = SpendingParts.summary(store.current)
            TabNavigationLink(.spendingParts("账本")) { SpendingPartsView(backTitle: "账本") } label: {
                VStack(spacing: 0) {
                    ForEach(summary.parts) { value in
                        balanceRow(name: value.part.name, remaining: value.remaining, allowance: value.allowance, overflow: value.overflow)
                    }
                    balanceRow(name: "没分的", remaining: summary.unassigned)
                }.padding(.vertical, 8).padding(.horizontal, 16)
                    .paperCardSurface(in: RoundedRectangle(cornerRadius: 22))
            }.buttonStyle(PressButtonStyle()).accessibilityLabel("分项，查看和编辑这个月还能花的分配")
                .accessibilityValue(summary.parts.map { value in
                    value.part.name + (value.overflow > 0 ? "超出" : "剩余") + number(value.overflow > 0 ? value.overflow : value.remaining)
                }.joined(separator: "，") + "，没分的剩余" + number(summary.unassigned))
                .accessibilityIdentifier("spendingPartsCard")
        }
    }
    private func number(_ value: Int64) -> String { store.preferences.hideAmounts ? "••••" : savingNumber(value) }
    private func balanceRow(name: String, remaining: Int64, allowance: Int64? = nil, overflow: Int64 = 0) -> some View {
        HStack(spacing: 12) {
            Text(name).yubaiFont(YubaiFont.callout).frame(width: 52, alignment: .leading).lineLimit(1)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(YubaiColor.card)
                    Capsule().fill(overflow > 0 ? YubaiColor.amberDot : allowance == nil ? YubaiColor.grabber : YubaiColor.brand)
                        .frame(width: geometry.size.width * (overflow > 0 || allowance == nil ? 1 : min(1, max(0, Double(remaining) / Double(max(1, allowance ?? 1))))))
                }
            }.frame(height: 6).accessibilityHidden(true)
            HStack(spacing: 0) {
                Text((overflow > 0 ? "超 " : "剩 ") + number(overflow > 0 ? overflow : remaining))
                    .yubaiFont(YubaiFont.partBalance).foregroundStyle(overflow > 0 ? YubaiColor.amberInk : YubaiColor.label)
                if let allowance {
                    Text(" / " + number(allowance)).yubaiFont(YubaiFont.amountCaption).foregroundStyle(YubaiColor.labelSecondary)
                }
            }.fixedSize()
        }.frame(minHeight: 36).foregroundStyle(YubaiColor.label)
    }
}

struct SpendingPartsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var backTitle = "账本"
    @State private var adding = false
    @State private var newName = ""
    @State private var categoryPart: SpendingPart?
    private var summary: SpendingPartsSummary { SpendingParts.summary(store.current) }
    var body: some View {
        Page(spacing: 12, topPadding: 12) {
            VStack(spacing: 0) {
                Text(heroTitle).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                Text(store.preferences.hideAmounts ? "••••" : Money.text(store.funds.available))
                    .yubaiFont(YubaiFont.savingsHero)
            }.frame(maxWidth: .infinity).padding(.bottom, 4)
            Segmented(choices: [(PartsMode.amount, "按金额"), (.share, "按几成")], selection: Binding(get: { store.current.partsMode }, set: { mode in
                store.update("分项", showToast: false) { $0.partsMode = mode }
            })).accessibilityLabel("怎么分")
            VStack(spacing: 0) {
                ForEach(store.current.spendingParts) { part in
                    SpendingPartEditorRow(part: part, addCategory: { categoryPart = part })
                    Rectangle().fill(YubaiColor.separator).frame(height: 1)
                }
                HStack {
                    Text("没分的").yubaiFont(YubaiFont.row)
                    Spacer()
                    Text(unassignedText).yubaiFont(YubaiFont.amountSummary).padding(.trailing, 12)
                }.foregroundStyle(YubaiColor.labelSecondary).frame(minHeight: 52)
            }.padding(.horizontal, 16).paperCardSurface(in: RoundedRectangle(cornerRadius: 22))
            HStack(spacing: 8) {
                Button { newName = ""; adding = true } label: {
                    Label("加一份", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                        .background(YubaiColor.raised, in: Capsule())
                }.accessibilityLabel("加一份，输入分项名字")
                Button("按前三个月分", action: suggest)
                    .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(YubaiColor.brandInk)
                    .background(YubaiColor.brandTint, in: Capsule()).accessibilityLabel("按前三个月的分类支出分配")
                    .disabled(store.current.spendingParts.isEmpty)
            }.yubaiFont(YubaiFont.callout).buttonStyle(PressButtonStyle())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { Text("月底没花完"); Spacer(minLength: 0); leftoverChoices }
                VStack(alignment: .leading, spacing: 8) { Text("月底没花完"); leftoverChoices }
            }.yubaiFont(YubaiFont.body).frame(minHeight: 52).padding(.horizontal, 16)
                .paperCardSurface(in: RoundedRectangle(cornerRadius: 22)).padding(.top, 2)
        }.safeAreaInset(edge: .top, spacing: 0) { header.padding(.horizontal, 20) }
            .navigationTitle("分项").yubaiNavigation().accessibilityIdentifier("spendingPartsPage")
            .alert("加一份", isPresented: $adding) {
                TextField("", text: $newName).accessibilityLabel("分项名字")
                Button("取消", role: .cancel) {}
                Button("加一份") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    store.update("分项", showToast: false) { $0.spendingParts.append(SpendingPart(name: name, amount: 0)) }
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newName.count > 100)
            }
            .sheet(item: $categoryPart) { part in
                NavigationStack {
                    Page(topPadding: 8) {
                        CategoryPicker(income: false, style: .sections) { choice, addition in
                            if store.update("分项", showToast: false, { ledger in
                                if let addition { try addition.apply(to: &ledger) }
                                SpendingParts.assign(category: choice.category, to: part.id, in: &ledger)
                            }) { categoryPart = nil; return true }
                            return false
                        }
                    }.manualSheetHeader("分类", showsAction: false, cancel: { categoryPart = nil })
                }.environment(store).appErrors().yubaiSheetBackground().presentationDetents([.medium, .large])
            }
            .onAppear {
                if store.current.spendingParts.isEmpty && store.current.partsMode == .amount && !store.funds.cycleIsPayday {
                    store.update("分项", showToast: false) { $0.partsMode = .share }
                }
            }
    }
    private var heroTitle: String {
        if store.current.partsMode == .share, !store.funds.cycleIsPayday, case .share(let percent) = store.current.savingRule {
            return "已到账 " + (store.preferences.hideAmounts ? "••••" : savingNumber(store.funds.cycleIncome)) + " · 留" + savingShare(percent) + "后"
        }
        return "这个月还能花"
    }
    private var unassignedText: String {
        if store.current.partsMode == .share { return partShare(10 - store.current.spendingParts.compactMap(\.share).reduce(0, +)) }
        return store.preferences.hideAmounts ? "••••" : Money.text(summary.unassigned, currency: false)
    }
    private var header: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: { Label(backTitle, systemImage: "chevron.left").frame(width: 88, height: 48, alignment: .leading) }
                .foregroundStyle(YubaiColor.brandInk).accessibilityLabel("返回" + backTitle)
            Text("分项").yubaiFont(YubaiFont.navTitle).frame(maxWidth: .infinity)
            Button("完成") { dismiss() }.yubaiFont(YubaiFont.callout).padding(.horizontal, 12).frame(height: 36)
                .background(YubaiColor.card, in: Capsule()).frame(width: 88, alignment: .trailing).accessibilityLabel("完成分项设置")
        }.yubaiFont(YubaiFont.body).buttonStyle(PressButtonStyle())
    }
    private var leftoverChoices: some View {
        HStack(spacing: 6) {
            leftover("并进存着不动", .mergeIntoFixedSavings)
            leftover("留给下个月", .rollOver)
        }
    }
    private func leftover(_ title: String, _ value: PartLeftover) -> some View {
        let selected = store.current.partLeftover == value
        return Button(title) {
            store.update("分项", showToast: false) { ledger in
                ledger.partLeftover = value
                if value == .mergeIntoFixedSavings { ledger.partCarry = [:]; ledger.partCarryCycleStart = nil }
            }
        }.yubaiFont(YubaiFont.caption).padding(.horizontal, 12).frame(height: 32)
            .background(selected ? YubaiColor.selected : YubaiColor.raised, in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(YubaiColor.brand, lineWidth: 1.5) } }
            .buttonStyle(PressButtonStyle()).accessibilityLabel("月底没花完，" + title).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func suggest() {
        let suggestions = SpendingParts.suggestions(ledger: store.current)
        store.update("分项", showToast: false) { ledger in
            for value in suggestions {
                guard let i = ledger.spendingParts.firstIndex(where: { $0.id == value.partID }) else { continue }
                ledger.spendingParts[i].amount = value.amount; ledger.spendingParts[i].share = value.share
            }
        }
    }
}

private struct SpendingPartEditorRow: View {
    @Environment(AppStore.self) private var store
    let part: SpendingPart
    let addCategory: () -> Void
    @State private var amount = ""
    @State private var deleting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(part.name).yubaiFont(YubaiFont.row, weight: .medium)
                Spacer()
                if store.current.partsMode == .amount {
                    Text(amount.isEmpty ? "0.00" : amount).yubaiFont(YubaiFont.amountSummary).hidden()
                        .overlay {
                            TextField("", text: $amount).multilineTextAlignment(.trailing).yubaiFont(YubaiFont.amountSummary)
                                .accessibilityLabel(part.name + "的本周期金额").onChange(of: amount) { _, value in
                                    guard let cents = try? Money.parse(value), cents != part.amount else { return }
                                    update { $0.amount = cents }
                                }
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        .padding(.horizontal, 12).frame(height: 36).background(YubaiColor.card, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Menu {
                        let other = store.current.spendingParts.filter { $0.id != part.id }.compactMap(\.share).reduce(0, +)
                        ForEach(1...10, id: \.self) { share in
                            Button(partShare(share)) { update { $0.share = share } }.disabled(other + share > 10)
                                .accessibilityLabel("把" + part.name + "分为" + partShare(share))
                        }
                    } label: {
                        Text(part.share.map(partShare) ?? "—").yubaiFont(YubaiFont.amountSummary).padding(.horizontal, 12)
                            .frame(height: 36).background(YubaiColor.card, in: RoundedRectangle(cornerRadius: 12))
                    }.accessibilityLabel(part.name + "的成数，" + (part.share.map(partShare) ?? "未分配"))
                }
            }.frame(minHeight: 40)
            ChipFlow(rowSpacing: 6) {
                ForEach(part.categories, id: \.self) { category in
                    Button(category) { update { $0.categories.removeAll { $0 == category } } }
                        .padding(.horizontal, 10).frame(height: 28).background(YubaiColor.card, in: Capsule())
                        .accessibilityLabel("从" + part.name + "移除分类" + category)
                }
                Button(action: addCategory) {
                    Image(systemName: "plus").frame(width: 32, height: 28).overlay { Capsule().strokeBorder(YubaiColor.grabber, lineWidth: 1) }
                }.accessibilityLabel("给" + part.name + "加分类")
            }.yubaiFont(YubaiFont.caption).buttonStyle(PressButtonStyle())
        }.padding(.top, 10).padding(.bottom, 12).contentShape(Rectangle())
            .contextMenu { Button("删掉", role: .destructive, action: remove).accessibilityLabel("删掉分项" + part.name) }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -44 && abs(value.translation.width) > abs(value.translation.height) { deleting = true }
                if value.translation.width > 44 && abs(value.translation.width) > abs(value.translation.height) { deleting = false }
            })
            .overlay(alignment: .trailing) {
                if deleting {
                    Button("删掉", role: .destructive, action: remove).padding(12).background(YubaiColor.raised, in: Capsule())
                        .accessibilityLabel("删掉分项" + part.name)
                }
            }
            .accessibilityAction(named: "删掉分项") { remove() }
            .onAppear { amount = Money.text(part.amount ?? 0, currency: false) }
            .onChange(of: part.amount) { _, value in
                if (try? Money.parse(amount)) != value { amount = Money.text(value ?? 0, currency: false) }
            }
    }
    private func update(_ edit: (inout SpendingPart) -> Void) {
        store.update("分项", showToast: false) { ledger in
            if let i = ledger.spendingParts.firstIndex(where: { $0.id == part.id }) { edit(&ledger.spendingParts[i]) }
        }
    }
    private func remove() {
        store.update("分项", showToast: false) { ledger in
            ledger.spendingParts.removeAll { $0.id == part.id }; ledger.partCarry[part.id] = nil
        }
    }
}

/// Both entry forms keep the choice in their draft. Category reassignment is
/// committed with the entry, so cancelling either form leaves the ledger alone.
struct SpendingPartPicker: View {
    @Environment(AppStore.self) private var store
    let ledger: Ledger
    let category: String
    @Binding var partID: UUID?
    @Binding var remember: Bool
    var allowsRemember = true
    var body: some View {
        let summary = SpendingParts.summary(ledger)
        let selected = selectedPartID
        ScrollView {
            VStack(spacing: 12) {
                Text("花在哪一份").yubaiFont(YubaiFont.entrySheetTitle).frame(height: 32).padding(.top, 12)
                VStack(spacing: 0) {
                    ForEach(summary.parts) { value in
                        choice(value.part.name, id: value.id, remaining: value.remaining, selected: selected)
                        Rectangle().fill(YubaiColor.separator).frame(height: 1)
                    }
                    choice("没分的", id: nil, remaining: summary.unassigned, selected: selected)
                }.padding(.horizontal, 16).paperCardSurface(in: RoundedRectangle(cornerRadius: 22))
                if allowsRemember {
                    Toggle(Classification.displayCategory(category) + "以后都记到这份", isOn: $remember)
                        .yubaiFont(YubaiFont.body).tint(YubaiColor.brand).frame(minHeight: 52).padding(.horizontal, 16)
                        .paperCardSurface(in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityLabel(Classification.displayCategory(category) + "以后都记到选中的分项")
                }
            }.padding(.horizontal, 20).padding(.bottom, 34)
        }.paperBackground().yubaiSheetBackground().presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private var selectedPartID: UUID? {
        var sample = Entry(amount: 0, accountID: UUID(), title: category, category: category)
        sample.partID = partID
        return SpendingParts.part(for: sample, in: ledger)?.id
    }
    private func choice(_ name: String, id: UUID?, remaining: Int64, selected: UUID?) -> some View {
        Button { partID = id ?? SpendingPart.unassignedID } label: {
            HStack(spacing: 12) {
                Text(name).yubaiFont(YubaiFont.row, weight: selected == id ? .semibold : .regular)
                Spacer()
                Text("剩 " + (store.preferences.hideAmounts ? "••••" : Money.text(remaining, currency: false)))
                    .yubaiFont(YubaiFont.partBalance).foregroundStyle(YubaiColor.labelSecondary)
                Image(systemName: "checkmark").foregroundStyle(YubaiColor.brand).frame(width: 18).opacity(selected == id ? 1 : 0)
            }.frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(PressButtonStyle()).accessibilityLabel(name + "，剩余" + (store.preferences.hideAmounts ? "金额已隐藏" : Money.text(remaining)))
            .accessibilityAddTraits(selected == id ? .isSelected : [])
    }
}
