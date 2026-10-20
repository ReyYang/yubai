import SwiftUI
import YubaiCore

struct ProfileConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var errorText = ""
    @State private var busy = false
    @State private var revising = false
    @State private var proposalID: UUID?
    @State private var runningTask: Task<Void, Never>?
    private var proposal: ChangeSet? { store.current.pendingChanges.first { $0.id == proposalID } }
    var body: some View {
        Page {
            Text("聊三件小事，留一份可以慢慢改的消费观。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                HStack {
                    if message.role == .user { Spacer(minLength: YubaiSpace.space24) }
                    Card(background: message.role == .user ? YubaiColor.raised : YubaiColor.card) {
                        VStack(alignment: .leading, spacing: YubaiSpace.space6) {
                            Text(message.role == .user ? "你" : "余白").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                            Text(message.content ?? "").yubaiFont(YubaiFont.body).textSelection(.enabled)
                        }
                    }
                    if message.role == .assistant { Spacer(minLength: YubaiSpace.space24) }
                }
            }
            if busy { ProgressView("余白在听，也在想…") }
            if let proposal, !revising {
                ProfileProposalCard(change: proposal, confirm: {
                    if store.apply(proposal, label: "修改消费观") { dismiss() }
                }, secondaryTitle: "再改改") { revising = true }
            } else if !messages.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: YubaiSpace.space12) {
                        TextField(revising ? "想改哪里？直接告诉余白" : "写下你的想法，也可以说暂时没想好", text: $input, axis: .vertical).lineLimit(2...6)
                        Button("发送") { ask() }.buttonStyle(PrimaryButtonStyle()).disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            if !errorText.isEmpty {
                InlineNote(text: errorText)
                Button("重试") { ask() }.disabled(busy)
            }
        }.navigationTitle("和余白聊几句").yubaiNavigation().toolbar { CloseButton() }
            .task { if messages.isEmpty && proposalID == nil { ask() } }
            .onDisappear { runningTask?.cancel() }
            .onChange(of: store.current.id) { _, _ in runningTask?.cancel(); dismiss() }
            .onChange(of: store.locked) { _, locked in if locked { runningTask?.cancel(); dismiss() } }
            .onChange(of: store.current.preferences.cloudAIEnabled) { _, enabled in if !enabled { runningTask?.cancel(); dismiss() } }
    }
    @MainActor private func ask() {
        guard !busy else { return }
        let before = store.current
        guard !store.locked, before.preferences.cloudAIEnabled, let transport = store.assistantTransport(for: before) else {
            errorText = "请先在设置中填写 DeepSeek 密钥并开启云端智能。"; return
        }
        var turn = messages
        let answer = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !messages.isEmpty {
            guard !answer.isEmpty else { return }
            turn.append(ChatMessage(role: .user, content: answer))
        }
        let conversation = turn
        let previousProposal = proposalID
        busy = true; errorText = ""
        runningTask = Task { @MainActor in
            defer { busy = false }
            do {
                let reply = try await ProfileColdStart(transport: transport).next(ledger: before, messages: conversation)
                try Task.checkCancellation()
                guard store.current == before, !store.locked else {
                    errorText = "账本刚有变化，请重试这一步。"; return
                }
                if let change = reply.proposedChangeSets.first {
                    guard store.update("保存待确认消费观", { ledger in
                        ledger.pendingChanges.removeAll { $0.id == previousProposal }
                        ledger.pendingChanges.append(change)
                    }) else { return }
                    proposalID = change.id; revising = false; messages = conversation
                } else {
                    messages = conversation + [ChatMessage(role: .assistant, content: reply.text)]
                }
                input = ""
            } catch is CancellationError { errorText = "对话已暂停，可以重试。" }
            catch { errorText = error.localizedDescription }
        }
    }
}
