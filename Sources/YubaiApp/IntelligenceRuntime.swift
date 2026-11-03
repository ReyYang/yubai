import Foundation
import Observation
import YubaiCore
import os
#if os(iOS)
import BackgroundTasks
import UIKit
#endif

/// Owns the system assertion for one explicit run; the organizer remains the
/// same async checkpoint pipeline whether or not submission succeeds.
@MainActor final class ImportOrganizationExecution {
    private static let logger = Logger(subsystem: "app.yubai.personal", category: "background-organize")
    let id: UUID
    private var progress: ImportOrganizationProgress
    private let cancel: @MainActor () -> Void
    private var completion: Bool?
    private let authorizedConfiguration: DeepSeekConfiguration?
    #if os(iOS)
    private let identifier: String
    private var backgroundTask: BGContinuedProcessingTask?
    private var originalIdleTimerDisabled: Bool?
    private var submitted = false
    #endif

    init(id: UUID, progress: ImportOrganizationProgress, cancel: @escaping @MainActor () -> Void) {
        self.id = id; self.progress = progress; self.cancel = cancel
        authorizedConfiguration = APIKeyStore.shared.configuration()
        #if os(iOS)
        identifier = "app.yubai.personal.organizeImports." + id.uuidString
        #endif
    }
    func start() -> Bool {
        let logger = Self.logger
        let executionID = id.uuidString
        #if os(iOS)
        originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        #if DEBUG && targetEnvironment(simulator)
        if UITestSupport.script != nil && !UITestSupport.allowsBackground {
            logger.info("run=\(executionID, privacy: .public) start=false: simulator UI script disallows background")
            return false
        }
        #endif
        guard progress.total > 0 else {
            logger.info("run=\(executionID, privacy: .public) start=false: progress.total=\(self.progress.total, privacy: .public)")
            return false
        }
        guard UIApplication.shared.applicationState == .active else {
            logger.info("run=\(executionID, privacy: .public) start=false: applicationState=\(UIApplication.shared.applicationState.rawValue, privacy: .public) (not active)")
            return false
        }
        // Register/submit the concrete suffix of Info.plist's bundle-ID wildcard
        // immediately on the user action. .fail avoids a detached, queued rerun.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main, launchHandler: { [weak self] task in
            logger.info("run=\(executionID, privacy: .public) launch handler called at=\(Date().ISO8601Format(), privacy: .public)")
            // The scheduler guarantees .main here; BGTask is not Sendable.
            nonisolated(unsafe) let deliveredTask = task
            MainActor.assumeIsolated {
                guard let self, let task = deliveredTask as? BGContinuedProcessingTask else {
                    logger.error("run=\(executionID, privacy: .public) launch handler rejected: execution released or unexpected task type")
                    deliveredTask.setTaskCompleted(success: false); return
                }
                self.attach(task)
            }
        })
        logger.info("run=\(executionID, privacy: .public) register success=\(registered, privacy: .public) identifier=\(self.identifier, privacy: .public)")
        guard registered else { return false }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "整理导入记录", subtitle: progress.subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("run=\(executionID, privacy: .public) submit succeeded; start=true")
            submitted = true
            return true
        }
        catch {
            let error = error as NSError
            logger.error("run=\(executionID, privacy: .public) submit failed; start=false domain=\(error.domain, privacy: .public) code=\(error.code, privacy: .public) localizedDescription=\(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        logger.info("run=\(executionID, privacy: .public) start=false: non-iOS platform")
        return false
        #endif
    }
    func configurationForTransport() -> DeepSeekConfiguration? {
        #if os(iOS)
        if UIApplication.shared.applicationState != .active {
            // Keep this run's foreground-authorized key in memory: the existing
            // WhenUnlocked Keychain item cannot be reread after device lock.
            guard authorizedConfiguration?.model == DeepSeekConfiguration.modelName() else { return nil }
            return authorizedConfiguration
        }
        #endif
        return APIKeyStore.shared.configuration()
    }
    func update(_ progress: ImportOrganizationProgress) {
        self.progress = progress
        #if os(iOS)
        // Report real saved checkpoints: minimal/no progress can cause the
        // system to terminate the task; never invent progress during a request.
        backgroundTask?.progress.totalUnitCount = Int64(progress.total)
        backgroundTask?.progress.completedUnitCount = Int64(progress.completed)
        backgroundTask?.updateTitle("整理导入记录", subtitle: progress.subtitle)
        #endif
    }
    func finish(success: Bool) {
        Self.logger.info("run=\(self.id.uuidString, privacy: .public) finish(success: \(success, privacy: .public)) alreadyFinished=\(self.completion != nil, privacy: .public)")
        guard completion == nil else { return }
        completion = success
        #if os(iOS)
        if let backgroundTask {
            backgroundTask.expirationHandler = nil
            backgroundTask.setTaskCompleted(success: success)
            self.backgroundTask = nil
        } else if submitted {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        if let originalIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
            self.originalIdleTimerDisabled = nil
        }
        #endif
    }
    #if os(iOS)
    private func attach(_ task: BGContinuedProcessingTask) {
        backgroundTask = task
        update(progress)
        if let completion {
            task.setTaskCompleted(success: completion)
            backgroundTask = nil
            return
        }
        let logger = Self.logger
        let executionID = id.uuidString
        task.expirationHandler = { [weak self] in
            logger.info("run=\(executionID, privacy: .public) expiration triggered at=\(Date().ISO8601Format(), privacy: .public)")
            Task { @MainActor in
                guard let self, self.completion == nil else { return }
                // System Stop and resource expiration share the in-app Stop path.
                self.cancel()
                self.finish(success: false)
            }
        }
    }
    #endif
}

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
    var staleMessage: String? = nil
    let isCurrent: @MainActor @Sendable () -> Bool
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        try Task.checkCancellation()
        guard await isCurrent() else {
            if let staleMessage { throw YubaiError.invalid(staleMessage) }
            throw CancellationError()
        }
        let reply: ChatMessage
        do {
            reply = try await base.send(request)
            if let model { await IntelligenceRuntime.cloud.succeeded(model: model) }
        } catch {
            if let model { await IntelligenceRuntime.cloud.failed(error, model: model) }
            throw error
        }
        guard await isCurrent() else {
            if let staleMessage { throw YubaiError.invalid(staleMessage) }
            throw CancellationError()
        }
        return reply
    }
}

@MainActor extension AppStore {
    func assistantTransport(for snapshot: Ledger, reportingLedgerChanges: Bool = false) -> (any ChatTransport)? {
        let continuingOrganization = reportingLedgerChanges && organizationContinuesInBackground
        guard snapshot.preferences.cloudAIEnabled, !locked || continuingOrganization, IntelligenceRuntime.cloud.unavailableModel == nil else { return nil }
        #if DEBUG && targetEnvironment(simulator)
        if let script = UITestSupport.script {
            guard IntelligenceRuntime.isConfigured else { return nil }
            return ActiveLedgerTransport(base: UITestTransport(script: script), staleMessage: reportingLedgerChanges ? ImportOrganizer.ledgerChangedMessage : nil) {
                self.current == snapshot && (!self.locked || (continuingOrganization && self.organizationContinuesInBackground))
            }
        }
        #endif
        let configuration = continuingOrganization ? organizationExecution?.configurationForTransport() : APIKeyStore.shared.configuration()
        guard let configuration else { return nil }
        let client = DeepSeekClient(configuration: configuration, redactor: Redactor(ledger: snapshot))
        return ActiveLedgerTransport(base: client, model: client.configuration.model, staleMessage: reportingLedgerChanges ? ImportOrganizer.ledgerChangedMessage : nil) {
            let configuration = continuingOrganization ? self.organizationExecution?.configurationForTransport() : APIKeyStore.shared.configuration()
            return self.current == snapshot && (!self.locked || (continuingOrganization && self.organizationContinuesInBackground)) && configuration == client.configuration
        }
    }
    // Called only by the now-page's explicit organization button.
    func startOrganizingPendingImports() {
        guard pendingOrganizationTask == nil, organizationExecution == nil, !organizingPendingImports, organizingBatchID == nil,
              !locked, loadFailure == nil, current.preferences.cloudAIEnabled else { return }
        let ids = PendingImportOrganization(in: current).batchIDs
        guard !ids.isEmpty else { return }
        beginImportOrganization(batchIDs: ids)
        pendingOrganizationTask = Task { @MainActor in
            defer { pendingOrganizationTask = nil }
            await organizePendingImports()
        }
    }
    func stopOrganizingImports() {
        pendingOrganizationTask?.cancel()
        importOrganizationTask?.cancel()
        organizationExecution?.finish(success: false)
    }
    private func beginImportOrganization(batchIDs: [UUID]) {
        let progress = ImportOrganizationProgress(completed: 0, total: batchIDs.reduce(0) {
            $0 + ImportOrganizer.pendingEntryIDs(in: current, batchID: $1).count
        })
        organizationProgress = progress
        organizingImportBatchIDs = Set(batchIDs)
        let id = UUID()
        let execution = ImportOrganizationExecution(id: id, progress: progress) { [weak self] in
            guard let self, self.organizationExecution?.id == id else { return }
            self.stopOrganizingImports()
        }
        organizationExecution = execution
        organizationContinuesInBackground = execution.start()
    }
    private func finishImportOrganization() {
        let complete = organizationProgress.map { $0.completed == $0.total } ?? false
        organizationExecution?.finish(success: complete && !Task.isCancelled &&
            organizingImportBatchIDs.allSatisfy { organizationErrors[$0] == nil })
        organizationExecution = nil
        organizationContinuesInBackground = false
        organizingImportBatchIDs = []
        organizationProgress = nil
    }
    func organizePendingImports() async {
        // A synchronous button submission may already own this run. Always
        // release it even if settings changed before the Task's first turn.
        guard !organizingPendingImports, organizingBatchID == nil else { return }
        defer { organizingPendingImports = false; finishImportOrganization() }
        guard !Task.isCancelled, !locked || organizationContinuesInBackground,
              loadFailure == nil, current.preferences.cloudAIEnabled else { return }
        let ids = current.imports.filter {
            $0.needsOrganization == true && $0.undoneAt == nil && (organizationExecution == nil || organizingImportBatchIDs.contains($0.id))
        }.map(\.id)
        if organizationExecution == nil { beginImportOrganization(batchIDs: ids) }
        organizingPendingImports = true
        for id in ids {
            guard !Task.isCancelled else { return }
            await organizeImport(id)
            if organizationErrors[id] != nil { return }
        }
    }
    func organizeImport(_ batchID: UUID) async {
        guard !Task.isCancelled, importOrganizationTask == nil else { return }
        let ownsExecution = organizationExecution == nil
        if ownsExecution {
            guard !locked, loadFailure == nil, current.preferences.cloudAIEnabled,
                  current.imports.contains(where: { $0.id == batchID && $0.needsOrganization == true && $0.undoneAt == nil }) else { return }
            beginImportOrganization(batchIDs: [batchID])
        }
        let task = Task { @MainActor in await performImportOrganization(batchID) }
        importOrganizationTask = task
        defer {
            importOrganizationTask = nil
            if ownsExecution { finishImportOrganization() }
        }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
    }
    private func performImportOrganization(_ batchID: UUID) async {
        guard !Task.isCancelled, organizingBatchID == nil, !locked || organizationContinuesInBackground,
              let batch = current.imports.first(where: { $0.id == batchID }), batch.needsOrganization == true,
              batch.undoneAt == nil, current.preferences.cloudAIEnabled,
              assistantTransport(for: current, reportingLedgerChanges: true) != nil else { return }
        let before = current
        let ids = ImportOrganizer.pendingEntryIDs(in: before, batchID: batchID)
        organizingBatchID = batchID; organizationErrors[batchID] = nil
        defer { organizingBatchID = nil }
        do {
            let organizer = ImportOrganizer { snapshot in
                try await MainActor.run {
                    guard self.current == snapshot, !self.locked || self.organizationContinuesInBackground,
                          let transport = self.assistantTransport(for: snapshot, reportingLedgerChanges: true) else {
                        throw YubaiError.invalid(ImportOrganizer.ledgerChangedMessage)
                    }
                    return transport
                }
            }
            _ = try await organizer.organize(ledger: before, entryIDs: ids) { result, completedIDs, snapshot in
                try Task.checkCancellation()
                return try await MainActor.run {
                    try Task.checkCancellation()
                    guard self.current == snapshot, !self.locked || self.organizationContinuesInBackground else {
                        throw YubaiError.invalid(ImportOrganizer.ledgerChangedMessage)
                    }
                    guard self.apply(result.changeSet, label: "导入整理", silently: true, continuingImportOrganization: true, finishing: { ledger in
                        result.finish(batchID: batchID, before: snapshot, in: &ledger, entryIDs: completedIDs)
                    }) else { throw YubaiError.invalid(self.error ?? ImportOrganizer.ledgerChangedMessage) }
                    let progress = ImportOrganizationProgress(completed: (self.organizationProgress?.completed ?? 0) + completedIDs.count,
                                                              total: self.organizationProgress?.total ?? ids.count)
                    self.organizationProgress = progress
                    self.organizationExecution?.update(progress)
                    return self.current
                }
            }
            let skipped = current.imports.first { $0.id == batchID }?.organization?.skipped ?? []
            toast = skipped.isEmpty ? "导入整理完成" : "整理完成；" + skipped.joined(separator: "；")
        } catch is CancellationError { }
        catch {
            if !Task.isCancelled { organizationErrors[batchID] = ImportOrganizer.failureMessage(error) }
        }
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
    @discardableResult func applyUnsortedGroup(questionID: UUID, groupID: String, use: UnsortedUse,
                                               category: String?, otherAccount: UUID?, entryIDs: Set<UUID>? = nil,
                                               purpose: String? = nil) -> Bool {
        guard let snapshot = unsortedGroups(questionID: questionID),
              let change = unsortedChangeSet(questionID: questionID, groupID: groupID, use: use,
                                            category: category, otherAccount: otherAccount,
                                            entryIDs: entryIDs, purpose: purpose) else { return false }
        let before = current
        return apply(change, label: "整理") { ledger in
            ImportOrganization.recordUndo(batchID: snapshot.batchID, before: before, in: &ledger)
        }
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
