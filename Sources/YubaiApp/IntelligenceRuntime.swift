import Foundation
import Observation
import YubaiCore

@MainActor enum IntelligenceRuntime {
    static let cloud = CloudAIStatus()
    static var isConfigured: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if let configured = UITestSupport.configuredKeyOverride { return configured }
        #endif
        return cloud.configured
    }
}

@MainActor @Observable final class CloudAIStatus {
    private static let unavailableKey = "DeepSeek.unavailableModel"
    var model = DeepSeekConfiguration.modelName()
    private(set) var configured = APIKeyStore.shared.isConfigured
    private(set) var unavailableModel: String? = UserDefaults.standard.string(forKey: CloudAIStatus.unavailableKey)
    init() { refresh() }
    func refresh() {
        model = DeepSeekConfiguration.modelName()
        configured = APIKeyStore.shared.isConfigured
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil { unavailableModel = nil; return }
        #endif
        if unavailableModel != model { clear() }
    }
    func saveModel(_ name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 200, !clean.contains(where: { $0.isNewline }) else { throw YubaiError.invalid("请输入有效的模型名字。") }
        UserDefaults.standard.set(clean, forKey: DeepSeekConfiguration.modelPreferenceKey)
        model = DeepSeekConfiguration.modelName(); clear()
    }
    func succeeded(model: String) {
        guard model == DeepSeekConfiguration.modelName() else { return }
        clear()
    }
    func failed(_ error: Error, model: String) {
        guard model == DeepSeekConfiguration.modelName(), let failure = error as? DeepSeekError,
              case .modelUnavailable = failure else { return }
        unavailableModel = model; UserDefaults.standard.set(model, forKey: Self.unavailableKey)
    }
    private func clear() { unavailableModel = nil; UserDefaults.standard.removeObject(forKey: Self.unavailableKey) }
}

struct ActiveLedgerTransport: ChatTransport {
    let base: any ChatTransport
    var model: String? = nil
    let isCurrent: @MainActor @Sendable () -> Bool
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        try Task.checkCancellation()
        guard await isCurrent() else { throw CancellationError() }
        let reply: ChatMessage
        do {
            reply = try await base.send(request)
            if let model { await IntelligenceRuntime.cloud.succeeded(model: model) }
        } catch {
            if let model { await IntelligenceRuntime.cloud.failed(error, model: model) }
            throw error
        }
        guard await isCurrent() else { throw CancellationError() }
        return reply
    }
}

@MainActor extension AppStore {
    func assistantTransport(for snapshot: Ledger) -> (any ChatTransport)? {
        guard snapshot.preferences.cloudAIEnabled, !locked, IntelligenceRuntime.cloud.unavailableModel == nil else { return nil }
        #if DEBUG && targetEnvironment(simulator)
        if let script = UITestSupport.script {
            guard IntelligenceRuntime.isConfigured else { return nil }
            return ActiveLedgerTransport(base: UITestTransport(script: script)) { self.current == snapshot && !self.locked }
        }
        #endif
        guard let client = DeepSeekClient.configured(redactor: Redactor(ledger: snapshot)) else { return nil }
        return ActiveLedgerTransport(base: client, model: client.configuration.model) {
            self.current == snapshot && !self.locked && APIKeyStore.shared.configuration() == client.configuration
        }
    }
    // Called only by the now-page's explicit organization button.
    func organizePendingImports() async {
        guard !organizingPendingImports, !locked, loadFailure == nil, current.preferences.cloudAIEnabled else { return }
        organizingPendingImports = true
        defer { organizingPendingImports = false }
        let ids = current.imports.filter { $0.needsOrganization == true && $0.undoneAt == nil }.map(\.id)
        for id in ids {
            guard !Task.isCancelled else { return }
            await organizeImport(id)
            if organizationErrors[id] != nil { return }
        }
    }
    func organizeImport(_ batchID: UUID) async {
        guard organizingBatchID == nil, !locked,
              let batch = current.imports.first(where: { $0.id == batchID }), batch.needsOrganization == true,
              batch.undoneAt == nil, current.preferences.cloudAIEnabled,
              let transport = assistantTransport(for: current) else { return }
        let before = current
        organizingBatchID = batchID; organizationErrors[batchID] = nil
        defer { organizingBatchID = nil }
        do {
            let ids = before.activeEntries.filter { $0.batchID == batchID && !$0.userEdited }.map(\.id)
            let result = try await ImportOrganizer(transport: transport).organize(ledger: before, entryIDs: ids)
            try Task.checkCancellation()
            guard current == before, !locked else {
                organizationErrors[batchID] = "账本已更新，本次整理未写入。可以点「现在整理」再试。"; return
            }
            if apply(result.changeSet, label: "导入整理", finishing: { ledger in
                result.finish(batchID: batchID, before: before, in: &ledger)
            }), !result.skipped.isEmpty { toast = "整理完成；" + result.skipped.joined(separator: "；") }
        } catch is CancellationError { }
        catch { organizationErrors[batchID] = "记录已保存，整理暂未完成。联网后可再试。" }
    }
    func answerImportQuestion(_ question: ImportQuestion, batchID: UUID, option: Int) {
        guard let change = question.answer(option, in: current) else { return }
        let before = current
        apply(change, label: "回答整理问题") { ledger in
            if let i = ledger.imports.firstIndex(where: { $0.id == batchID }) {
                ledger.imports[i].organization?.questions.removeAll { $0.id == question.id }
            }
            for i in ledger.cards.indices where ledger.cards[i].importQuestion?.id == question.id { ledger.cards[i].dismissedAt = Date() }
            ImportOrganization.recordUndo(batchID: batchID, before: before, in: &ledger)
        }
    }
    func describeImportQuestion(_ question: ImportQuestion, batchID: UUID, text: String) {
        update("回答整理问题") { try question.describe(text, batchID: batchID, in: &$0) }
    }
    func undoImport(_ batchID: UUID) {
        if update("整批撤销", preservingUpdatedAt: true, entryMotion: false, { ledger in BillImporter.undo(batchID: batchID, in: &ledger) }) { cancelEntrySaveMotion(); undoTrigger &+= 1 }
    }
}

@MainActor extension AppStore {
    func refreshButler() async {
        guard !locked, loadFailure == nil, organizingBatchID == nil, !organizingPendingImports, current.preferences.onboardingComplete else { return }
        // Pending imports pause automatic cloud work, while local cards still refresh.
        await classifySubcategoriesIfDue()
        await reflectMemoriesIfDue()
        guard !Task.isCancelled, !locked, organizingBatchID == nil else { return }
        let before = current; let now = Date()
        var candidates = ButlerCards.detect(before, now: now)
        if let letter = WeeklyLetter.candidate(before, now: now) { candidates.append(letter) }
        guard !candidates.isEmpty else { return }
        let transport = PendingImportOrganization(in: before).batchIDs.isEmpty ? assistantTransport(for: before) : nil
        let worded = await ButlerWording.word(candidates, ledger: before, transport: transport)
        guard !Task.isCancelled, current == before, !locked, organizingBatchID == nil else { return }
        var next = before
        guard ButlerCards.refresh(&next, candidates: worded, now: now) else { return }
        update("更新管家卡片", recordUndo: false) { $0.cards = next.cards }
    }
    private func classifySubcategoriesIfDue() async {
        guard !reflectingMemories, PendingImportOrganization(in: current).batchIDs.isEmpty,
              current.preferences.cloudAIEnabled, SubcategoryBatch.isDue(current),
              !SubcategoryBatch.pending(current).isEmpty, syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion,
              let transport = assistantTransport(for: current) else { return }
        let before = current; let now = Date()
        reflectingMemories = true
        defer { reflectingMemories = false }
        do {
            let result = try await SubcategoryBatch.run(transport: transport, ledger: before, now: now)
            try Task.checkCancellation()
            guard current == before, !locked, current.preferences.cloudAIEnabled else { return }
            update("归小项", recordUndo: false) { try result.apply(to: &$0, now: now) }
        } catch { /* Keep the local classification and retry the unpersisted round later. */ }
    }
    private func reflectMemoriesIfDue() async {
        guard !reflectingMemories, PendingImportOrganization(in: current).batchIDs.isEmpty,
              MemoryReflection.isDue(ledger: current),
              syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion,
              let transport = assistantTransport(for: current) else { return }
        let before = current
        reflectingMemories = true
        defer { reflectingMemories = false }
        do {
            let result = try await MemoryReflection.run(ledger: before, transport: transport)
            try Task.checkCancellation()
            guard current == before, !locked, organizingBatchID == nil, loadFailure == nil,
                  syncChoice == nil, !switchingLedgerLocation, !choosingSyncVersion else { return }
            update("每周来信", recordUndo: false, reportError: false) { try result.apply(to: &$0) }
        } catch { /* Leave the week pending so a later refresh can retry. */ }
    }
    func dismissCard(_ id: UUID) {
        guard current.cards.contains(where: { $0.id == id && $0.dismissedAt == nil }) else { return }
        update("收起管家卡片") { ledger in
            if let i = ledger.cards.firstIndex(where: { $0.id == id }) { ledger.cards[i].dismissedAt = Date() }
        }
    }
    func muteCard(_ id: UUID) {
        update("以后不再提这个话题") { ButlerCards.mute(id, in: &$0, now: Date()) }
    }
    func cardFeedback(_ value: CardFeedback, id: UUID) {
        update("记下你点过的提醒") { ButlerCards.feedback(value, cardID: id, in: &$0, now: Date()) }
    }
    func performCardAction(_ card: ButlerCard) {
        switch card.action ?? .openEvidence {
        case .openEvidence: sheet = .cardEvidence(card.id)
        case .reconcileAccount(let id): sheet = .reconcile(id)
        case .confirmChangeSet(let id): sheet = .cardProposal(id)
        case .answerQuestion: sheet = .cardQuestion(card.id)
        case .openWish(let id): sheet = .wishlist(id)
        }
    }
}
