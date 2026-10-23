import SwiftUI
import YubaiCore

struct ProfileConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var errorText = ""
    @State private var busy = false
    @State private var pendingUserTurn = false
    @State private var revising = false
    @State private var proposalID: UUID?
    @State private var runningTask: Task<Void, Never>?
    private var proposal: ChangeSet? { store.current.pendingChanges.first { $0.id == proposalID } }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                    Text("三个问题 · 第 \(min(3, max(1, messages.filter { $0.role == .assistant }.count))) 个")
                        .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).frame(maxWidth: .infinity)
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        HStack(spacing: YubaiSpace.gapGroup) {
                            if message.role == .user { Spacer(minLength: YubaiSpace.messageIndent) }
                            VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                                if message.role == .assistant {
                                    HStack(spacing: YubaiSpace.space8) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                                }
                                Text(message.content ?? "").yubaiFont(message.role == .user ? YubaiFont.body : YubaiFont.cardTitle)
                                    .foregroundStyle(message.role == .user ? YubaiColor.onBrand : YubaiColor.label).textSelection(.enabled)
                            }.padding(YubaiSpace.insetCard).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == .user ? YubaiColor.brand : YubaiColor.card,
                                            in: UnevenRoundedRectangle(topLeadingRadius: message.role == .user ? 18 : 6, bottomLeadingRadius: 22, bottomTrailingRadius: message.role == .user ? 6 : 22, topTrailingRadius: 22))
                            if message.role == .assistant { Spacer(minLength: YubaiSpace.gapSection) }
                        }.messageEntrance(user: message.role == .user)
                    }
                    if busy { HStack(spacing: YubaiSpace.gapGroup) { AssistantMark(thinking: true); Text("余白在听，也在想…").yubaiFont(YubaiFont.callout) } }
                    if let proposal, !revising {
                        ProfileProposalCard(change: proposal, confirm: {
                            if store.apply(proposal, label: "修改消费观") { dismiss() }
                        }, secondaryTitle: "再改改") { revising = true }
                    }
                    if !errorText.isEmpty {
                        InlineNote(text: errorText)
                        Button("重试") { ask() }.disabled(busy).frame(minHeight: YubaiSize.tapMin)
                    }
                }.padding(YubaiSpace.insetPage).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
            if proposal == nil || revising {
                ChatInputBar(text: $input, placeholder: revising ? "想改哪里？" : "写下你的想法…",
                    accessibilityLabel: "告诉余白你的消费观", inputID: "profileInput", sendID: "sendProfile",
                    busy: busy, send: ask, leading: { EmptyView() }, accessory: { EmptyView() })
                    .padding(YubaiSpace.insetPage)
            }
        }.paperBackground().navigationTitle("和余白聊几句").yubaiNavigation()
            .toolbar {
                CloseButton()
                if proposal == nil && !messages.isEmpty {
                    Button("先跳过") { input = "暂时没想好，先跳过"; ask() }.disabled(busy).frame(minHeight: YubaiSize.tapMin)
                }
            }
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
        if !answer.isEmpty {
            if pendingUserTurn, turn.last?.role == .user { turn.removeLast() }
            turn.append(ChatMessage(role: .user, content: answer))
        } else if !messages.isEmpty { return }
        let conversation = turn
        input = ""
        messages = conversation; pendingUserTurn = conversation.last?.role == .user
        let previousProposal = proposalID
        busy = true; errorText = ""
        runningTask = Task { @MainActor in
            var succeeded = false
            defer {
                busy = false
                if !succeeded, pendingUserTurn { input = answer }
            }
            do {
                let reply = try await ProfileColdStart(transport: transport).next(ledger: before, messages: conversation)
                try Task.checkCancellation()
                guard store.current == before, !store.locked else {
                    errorText = "账本刚有变化，请重试这一步。"; return
                }
                let change = reply.proposedChangeSets.first
                if !reply.rememberedNotes.isEmpty || !reply.updatedNotes.isEmpty || !reply.usedMemoryIDs.isEmpty || change != nil {
                    guard store.update("保存消费观对话", recordUndo: false, { ledger in
                        try Memory.apply(reply, to: &ledger)
                        if let change {
                            ledger.pendingChanges.removeAll { $0.id == previousProposal }
                            ledger.pendingChanges.append(change)
                        }
                    }) else { return }
                }
                pendingUserTurn = false
                if let change {
                    proposalID = change.id; revising = false; messages = conversation
                } else {
                    messages = conversation + [ChatMessage(role: .assistant, content: reply.text)]
                }
                succeeded = true
            } catch is CancellationError { errorText = "对话已暂停，可以重试。" }
            catch { errorText = error.localizedDescription }
        }
    }
}
