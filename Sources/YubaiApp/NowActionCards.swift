import SwiftUI
import YubaiCore

@MainActor extension AppStore {
    var cloudAIReady: Bool {
        current.preferences.cloudAIEnabled && IntelligenceRuntime.isConfigured && IntelligenceRuntime.cloud.unavailableModel == nil
    }
    func confirmSalary(_ candidate: SalaryCandidate) {
        guard SalaryDetection.candidate(in: current)?.key == candidate.key else { return }
        if update("工资", showToast: false, { ledger in
            SalaryDetection.confirm(candidate, in: &ledger)
        }) { toast = "工资已加到会回来的账单" }
    }
    func rejectSalary(_ candidate: SalaryCandidate) {
        if update("工资", showToast: false, { SalaryDetection.dismiss(candidate, in: &$0) }) { toast = nil }
    }
    func showUncategorizedImports(_ pending: PendingImportOrganization) {
        let ids = Set(pending.entryIDs)
        entryFilterDate = current.activeEntries.filter { ids.contains($0.id) && Classification.isPending($0) }.map(\.date).max()
            ?? pending.dates.max()
        entryFilterRequest = UUID()
        destination = .entries
    }
}

private enum NowCardPage: Identifiable {
    case salary(SalaryCandidate), imports(PendingImportOrganization), butler(ButlerCard)
    var id: String {
        switch self {
        case .salary(let candidate): "salary:" + candidate.key
        case .imports: "imports"
        case .butler(let card): card.id.uuidString
        }
    }
}

/// Intrinsic card height (including large type), with horizontal paging owned by
/// the same direction gate as the existing card gesture and root pager.
struct NowCardsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: String?
    @State private var width: CGFloat = 1
    @State private var drag: CGFloat = 0
    private var butlerCards: [ButlerCard] { SavingCardVisibility.visible(in: store.current, collapsingInflows: true) }
    private var pages: [NowCardPage] {
        var result: [NowCardPage] = []
        if let salary = SalaryDetection.candidate(in: store.current), !store.hiddenSalaryKeys.contains(salary.key) { result.append(.salary(salary)) }
        let pending = PendingImportOrganization(in: store.current)
        if !pending.batchIDs.isEmpty { result.append(.imports(pending)) }
        result += butlerCards.filter { $0.importQuestion == nil && $0.kind != .unknownInflow }.map(NowCardPage.butler)
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            if !pages.isEmpty { pagedCards }
            ForEach(butlerCards.filter { $0.importQuestion != nil }) { card in
                if let question = card.importQuestion, let batch = store.current.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                    ImportQuestionCard(question: question, batchID: batch.id, cardID: card.id)
                }
            }
            let inflows = ButlerCards.queued(store.current).filter { $0.kind == .unknownInflow }
            if inflows.count >= 2 {
                TabNavigationLink(.unknownInflows) { ButlerListView(unknownInflowsOnly: true) } label: {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("\(inflows.count) 笔进账没说来源").yubaiFont(YubaiFont.row, weight: .medium)
                        Spacer(minLength: YubaiSpace.none)
                        Text("稍后").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    }.padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.tapMin)
                        .background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: YubaiRadius.row))
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("unknownInflowsSummary")
            } else if let card = butlerCards.first(where: { $0.kind == .unknownInflow }) {
                ButlerCardView(card: card)
            }
        }
    }
    private var pagedCards: some View {
        let pages = self.pages
        let index = pages.firstIndex { $0.id == selected } ?? 0
        let ids = pages.map(\.id)
        let pageValue = pages.isEmpty ? "" : "\(index + 1) / \(pages.count)"
        return ZStack(alignment: .top) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { position, page in
                card(page, number: "\(position + 1) / \(pages.count)", paging: pages.count > 1, active: position == index)
                    .frame(maxWidth: .infinity)
                    .offset(x: CGFloat(position - index) * (width + YubaiSpace.gapGroup) + drag)
                    .opacity(position == index || drag != 0 ? 1 : 0)
                    .allowsHitTesting(position == index && drag == 0)
                    .accessibilityHidden(position != index)
                    .transition(YubaiMotion.cardTransition(reduceMotion: reduceMotion))
            }
        }
            // With only one visible card, .contain reuses that card's AX container.
            // A separate page-status element makes nowCards a new parent instead
            // of overwriting the card's identifier/value, without changing layout.
            .overlay(alignment: .topTrailing) {
                if !pages.isEmpty {
                    Color.clear.frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("第 \(index + 1) 张，共 \(pages.count) 张卡片")
                        .allowsHitTesting(false)
                }
            }
            .clipped().contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
            #if os(iOS)
            .gesture(HorizontalPan(shouldBegin: { _ in pages.count > 1 || isSalary(pages.first) }, changed: { distance in
                drag = max(-width, min(width, distance))
            }, ended: { distance, velocity in
                finishSwipe(distance: distance, velocity: velocity, pages: pages, index: index)
            }, cancelled: resetDrag))
            #else
            .simultaneousGesture(DragGesture(minimumDistance: 18).onChanged { value in
                guard pages.count > 1 || isSalary(pages.first), abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                drag = max(-width, min(width, value.translation.width))
            }.onEnded { value in
                guard drag != 0 else { return }
                finishSwipe(distance: value.translation.width, velocity: value.velocity.width, pages: pages, index: index)
            })
            #endif
            .onChange(of: ids) { old, new in
                if let first = new.first, first.hasPrefix("salary:"), !old.contains(first) { selected = first }
                else if !new.contains(selected ?? "") { selected = new.first }
                drag = 0
            }
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: ids)
            .accessibilityElement(children: .contain).accessibilityIdentifier("nowCards")
            .accessibilityValue(pageValue)
            .accessibilityAction(named: "下一张卡片") { move(1, in: pages, index: index) }
            .accessibilityAction(named: "上一张卡片") { move(-1, in: pages, index: index) }
    }
    @ViewBuilder private func card(_ page: NowCardPage, number: String, paging: Bool, active: Bool) -> some View {
        switch page {
        case .salary(let candidate): SalaryCard(candidate: candidate, pageNumber: number)
        case .imports(let pending): PendingImportsCard(pending: pending, pageNumber: number)
        case .butler(let card): ButlerCardView(card: card, pageNumber: paging ? number : nil, paging: paging, isCurrentPage: active)
        }
    }
    private func isSalary(_ page: NowCardPage?) -> Bool {
        if case .salary? = page { return true }; return false
    }
    private func finishSwipe(distance: CGFloat, velocity: CGFloat, pages: [NowCardPage], index: Int) {
        if abs(distance) > width * 0.25 || (abs(velocity) > 650 && abs(distance) > 20) {
            if pages.count == 1, distance < 0, case .salary(let candidate) = pages[0] { store.hiddenSalaryKeys.insert(candidate.key) }
            else { move(distance < 0 ? 1 : -1, in: pages, index: index) }
        }
        resetDrag()
    }
    private func move(_ step: Int, in pages: [NowCardPage], index: Int) {
        guard pages.indices.contains(index + step) else { return }
        withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { selected = pages[index + step].id; drag = 0 }
    }
    private func resetDrag() { withAnimation(YubaiMotion.layout(reduceMotion: reduceMotion)) { drag = 0 } }
}

private struct SalaryCard: View {
    @Environment(AppStore.self) private var store
    let candidate: SalaryCandidate
    let pageNumber: String
    var body: some View {
        Card(style: .compact, background: YubaiColor.brandTint) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                NowCardHeading(title: "这是工资吗？", pageNumber: pageNumber)
                HStack(spacing: YubaiSpace.space8) {
                    Text(candidate.payer + " · 每月 \(candidate.dayOfMonth) 日")
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).lineLimit(1)
                    Spacer(minLength: YubaiSpace.none)
                    AmountLabel(cents: candidate.amount, hide: store.current.preferences.hideAmounts, role: .amount, sign: .inflow, currency: false)
                        .layoutPriority(1)
                }
                Text(candidate.recentDates.map(FixedFlowPresentation.monthDay).joined(separator: " · "))
                    .yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                HStack(spacing: YubaiSpace.space8) {
                    Button("是工资") { store.confirmSalary(candidate) }
                        .buttonStyle(NowCardButtonStyle(primary: true)).accessibilityIdentifier("confirmSalary")
                        .accessibilityLabel("是工资，将每月收入加到会回来的账单")
                    Button("不是") { store.rejectSalary(candidate) }
                        .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("rejectSalary")
                        .accessibilityLabel("不是工资，不再询问这个付款方")
                    Spacer(minLength: YubaiSpace.none)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("salaryCard")
            .accessibilityAction(named: "本次收起工资卡片") { store.hiddenSalaryKeys.insert(candidate.key) }
    }
}

private struct PendingImportsCard: View {
    @Environment(AppStore.self) private var store
    let pending: PendingImportOrganization
    let pageNumber: String
    private var busy: Bool { store.organizingPendingImports || store.organizingBatchID != nil }
    private var accounts: String {
        pending.accountIDs.count > 1 ? "\(pending.accountIDs.count) 个账户" : store.current.accountName(pending.accountIDs.first)
    }
    private var organizationError: String? {
        guard !busy, let error = pending.batchIDs.compactMap({ store.organizationErrors[$0] }).first else { return nil }
        let prefix = "记录已保存。"
        return error.hasPrefix(prefix) ? String(error.dropFirst(prefix.count)) : error
    }
    var body: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                NowCardHeading(title: "\(pending.count) 笔还没分类", pageNumber: pageNumber)
                Text(accounts + (pending.dates.isEmpty ? "" : " · " + ImportStatementText.range(pending.dates)))
                    .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).lineLimit(1)
                if let error = organizationError {
                    Text(error).yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.amberInk)
                        .accessibilityIdentifier("organizeError")
                }
                if busy {
                    organizationProgress
                } else {
                    HStack(spacing: YubaiSpace.space8) {
                        if store.cloudAIReady || organizationError != nil {
                            Button("整理") {
                                if store.cloudAIReady { store.startOrganizingPendingImports() }
                                else { store.sheet = .intelligencePrivacy }
                            }
                                .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("organizeImports")
                                .accessibilityLabel("整理这 \(pending.count) 笔导入的账目")
                        } else {
                            Button("打开云端智能") { store.sheet = .intelligencePrivacy }
                                .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("openCloudAI")
                                .accessibilityLabel("打开云端智能设置")
                        }
                        Button("自己分") { store.showUncategorizedImports(pending) }
                            .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                            .buttonStyle(PressButtonStyle()).frame(minHeight: YubaiSize.tapMin)
                            .accessibilityLabel("自己分类，打开账目中的没分类筛选").accessibilityIdentifier("classifyImportsManually")
                        Spacer(minLength: YubaiSpace.none)
                    }
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("pendingImportsCard")
            #if DEBUG && targetEnvironment(simulator)
            .uiTestAccessibilityValue(UITestSupport.importRequestState(in: store.current))
            #endif
    }
    private var organizationProgress: some View {
        let progress = store.organizationProgress ?? (completed: 0, total: pending.count)
        let fraction = progress.total > 0 ? min(1, max(0, Double(progress.completed) / Double(progress.total))) : 0
        let numberStyle = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_US"))
        return VStack(spacing: YubaiSpace.space8) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 3).fill(YubaiColor.neutralSoft)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(YubaiColor.brand)
                            .frame(width: geometry.size.width * fraction)
                    }
            }.frame(height: 6)
                .accessibilityElement(children: .ignore).accessibilityLabel("正在整理导入的账目")
                .accessibilityValue("\(progress.completed)/\(progress.total)").accessibilityIdentifier("organizeProgress")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YubaiSpace.space8) {
                    progressCount(progress, style: numberStyle)
                    Spacer(minLength: YubaiSpace.none)
                    organizingReminder
                    stopButton
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    progressCount(progress, style: numberStyle)
                    HStack(spacing: YubaiSpace.space8) { organizingReminder; Spacer(minLength: 0); stopButton }
                }
            }
        }
    }
    private func progressCount(_ progress: (completed: Int, total: Int), style: IntegerFormatStyle<Int>) -> some View {
        Text(progress.completed.formatted(style) + " / " + progress.total.formatted(style))
            .yubaiFont(YubaiFont.amountSmall, weight: .regular).foregroundStyle(YubaiColor.labelSecondary)
            .fixedSize()
    }
    private var organizingReminder: some View {
        Text("整理时别离开余白").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
    }
    private var stopButton: some View {
        Button("停下") { store.stopOrganizingImports() }
            .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("stopOrganizing")
    }
}

private struct NowCardHeading: View {
    let title: String
    let pageNumber: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text(title).yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.label)
            Spacer(minLength: YubaiSpace.none)
            Text(pageNumber).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                .accessibilityHidden(true) // The pager exposes this status outside the card's AX container.
        }
    }
}

struct NowCardButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.callout, weight: .medium)
            .padding(.horizontal, YubaiSpace.space16).frame(minHeight: 36)
            .foregroundStyle(primary ? YubaiColor.onBrand : YubaiColor.brandInk)
            .background(primary ? YubaiColor.brand : YubaiColor.raised, in: Capsule())
            .frame(minHeight: YubaiSize.tapMin)
            .opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}
