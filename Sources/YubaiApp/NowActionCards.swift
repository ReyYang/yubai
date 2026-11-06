import SwiftUI
import YubaiCore

@MainActor extension AppStore {
    var cloudAIReady: Bool {
        preferences.cloudAIEnabled && IntelligenceRuntime.isConfigured && IntelligenceRuntime.cloud.unavailableModel == nil
    }
    var organizationAIReady: Bool { preferences.cloudAIEnabled && IntelligenceRuntime.isConfigured }
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
        case .imports(let pending): "imports:" + pending.sessionCardKey
        case .butler(let card): card.id.uuidString
        }
    }
}

/// Only the first card is mounted; the remaining cards appear as quiet deck edges.
struct NowCardsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var butlerCards: [ButlerCard] {
        store.butlerVisibility.collapsed
    }
    private var pages: [NowCardPage] {
        var result: [NowCardPage] = []
        if let salary = store.nowSalaryCandidate, !store.hiddenSalaryKeys.contains(salary.key) { result.append(.salary(salary)) }
        let pending = store.pendingOrganization
        if !pending.batchIDs.isEmpty, !store.hiddenPendingImportKeys.contains(pending.sessionCardKey) { result.append(.imports(pending)) }
        result += butlerCards.filter { $0.importQuestion == nil && $0.kind != .unknownInflow }.map(NowCardPage.butler)
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
            if !pages.isEmpty { deck }
            ForEach(butlerCards.filter { $0.importQuestion != nil }) { card in
                if let question = card.importQuestion, let batch = store.imports.first(where: { $0.undoneAt == nil && $0.organization?.questions.contains(where: { $0.id == question.id }) == true }) {
                    ImportQuestionCard(question: question, batchID: batch.id, cardID: card.id)
                }
            }
            let inflows = store.butlerVisibility.queued.filter { $0.kind == .unknownInflow }
            if inflows.count >= 2 {
                TabNavigationLink(.unknownInflows) { ButlerListView(unknownInflowsOnly: true) } label: {
                    HStack(spacing: YubaiSpace.gapGroup) {
                        Text("\(inflows.count) 笔进账没说来源").yubaiFont(YubaiFont.row, weight: .medium)
                        Spacer(minLength: YubaiSpace.none)
                        Text("稍后").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    }.padding(.horizontal, YubaiSpace.insetCard).frame(minHeight: YubaiSize.tapMin)
                        .paperCardSurface(in: RoundedRectangle(cornerRadius: YubaiRadius.row))
                }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("unknownInflowsSummary")
            } else if let card = butlerCards.first(where: { $0.kind == .unknownInflow }) {
                ButlerCardView(card: card)
            }
        }
    }
    private var deck: some View {
        let pages = self.pages
        let edges = min(2, max(0, pages.count - 1))
        return ZStack(alignment: .bottom) {
            ForEach(Array((1..<(edges + 1)).reversed()), id: \.self) { depth in
                RoundedRectangle(cornerRadius: YubaiRadius.card, style: .continuous)
                    .fill(YubaiColor.neutralSoft).frame(height: 40)
                    .padding(.horizontal, CGFloat(depth) * 10).offset(y: CGFloat(depth) * 6)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            ForEach(Array(pages.prefix(1))) { page in
                card(page)
                    .transition(.asymmetric(insertion: reduceMotion ? .opacity : .scale(scale: 0.97), removal: .identity))
            }
        }.padding(.bottom, CGFloat(edges) * 6)
            .animation(YubaiMotion.layout(reduceMotion: reduceMotion), value: pages.map(\.id))
    }
    @ViewBuilder private func card(_ page: NowCardPage) -> some View {
        switch page {
        case .salary(let candidate):
            SwipeDismissCard(onDismiss: { store.hiddenSalaryKeys.insert(candidate.key); return true }, nudgesOnce: true) { _ in
                SalaryCard(candidate: candidate)
            }
        case .imports(let pending):
            SwipeDismissCard(onDismiss: { store.hiddenPendingImportKeys.insert(pending.sessionCardKey); return true }, nudgesOnce: true, reportsRevealState: false) { _ in
                PendingImportsCard(pending: pending)
            }
        case .butler(let card): ButlerCardView(card: card, nudgesOnce: true)
        }
    }
}

private extension PendingImportOrganization {
    // A new set of batches can surface again; progress within a hidden set stays hidden.
    var sessionCardKey: String { batchIDs.map(\.uuidString).sorted().joined(separator: ":") }
}

private struct SalaryCard: View {
    @Environment(AppStore.self) private var store
    let candidate: SalaryCandidate
    var body: some View {
        Card(style: .compact, background: YubaiColor.brandTint) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                NowCardHeading(title: "这是工资吗？")
                HStack(spacing: YubaiSpace.space8) {
                    Text(candidate.payer + " · 每月 \(candidate.dayOfMonth) 日")
                        .yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelMuted).lineLimit(1)
                    Spacer(minLength: YubaiSpace.none)
                    AmountLabel(cents: candidate.amount, hide: store.preferences.hideAmounts, role: .amount, sign: .inflow, currency: false)
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
    }
}

private struct PendingImportsCard: View {
    @Environment(AppStore.self) private var store
    let pending: PendingImportOrganization
    private var busy: Bool { store.organizingPendingImports || store.organizingBatchID != nil }
    private var accounts: String {
        pending.accountIDs.count > 1 ? "\(pending.accountIDs.count) 个账户" : store.accountName(pending.accountIDs.first)
    }
    private var organizationError: String? {
        guard !busy, let error = pending.batchIDs.compactMap({ store.organizationErrors[$0] }).first else { return nil }
        let prefix = "记录已保存。"
        let reason = error.hasPrefix(prefix) ? String(error.dropFirst(prefix.count)) : error
        return ImportOrganizer.incompleteMessage(remaining: pending.count, reason: reason.trimmingCharacters(in: CharacterSet(charactersIn: "。")))
    }
    var body: some View {
        Card(style: .compact) {
            VStack(alignment: .leading, spacing: YubaiSpace.gapHeading) {
                NowCardHeading(title: "\(pending.count) 笔还没分类")
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
                        if store.organizationAIReady || organizationError != nil {
                            Button("整理") {
                                if store.organizationAIReady { store.startOrganizingPendingImports() }
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
        let progress = store.organizationProgress ?? ImportOrganizationProgress(completed: 0, total: pending.count)
        let fraction = progress.total > 0 ? min(1, max(0, Double(progress.completed) / Double(progress.total))) : 0
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
                    progressCount(progress)
                    Spacer(minLength: YubaiSpace.none)
                    organizingReminder
                    stopButton
                }
                VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                    progressCount(progress)
                    HStack(spacing: YubaiSpace.space8) { organizingReminder; Spacer(minLength: 0); stopButton }
                }
            }
        }
    }
    private func progressCount(_ progress: ImportOrganizationProgress) -> some View {
        Text(progress.countText)
            .yubaiFont(YubaiFont.amountSmall, weight: .regular).foregroundStyle(YubaiColor.labelSecondary)
            .fixedSize()
    }
    @ViewBuilder private var organizingReminder: some View {
        if !store.organizationContinuesInBackground {
            Text("整理时别离开余白").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary).fixedSize()
        }
    }
    private var stopButton: some View {
        Button("停下") { store.stopOrganizingImports() }
            .buttonStyle(NowCardButtonStyle()).accessibilityIdentifier("stopOrganizing")
    }
}

private struct NowCardHeading: View {
    let title: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: YubaiSpace.space8) {
            Text(title).yubaiFont(YubaiFont.cardTitle).foregroundStyle(YubaiColor.label)
            Spacer(minLength: YubaiSpace.none)
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
