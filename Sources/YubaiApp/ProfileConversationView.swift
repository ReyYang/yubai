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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("三个问题 · 第 \(min(3, max(1, messages.filter { $0.role == .assistant }.count))) 个")
                        .yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary).frame(maxWidth: .infinity)
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        HStack {
                            if message.role == .user { Spacer(minLength: 40) }
                            VStack(alignment: .leading, spacing: 6) {
                                if message.role == .assistant {
                                    HStack(spacing: 6) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白助手").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                                }
                                Text(message.content ?? "").yubaiFont(message.role == .user ? YubaiFont.body : YubaiFont.cardTitle)
                                    .foregroundStyle(message.role == .user ? YubaiColor.onBrand : YubaiColor.label).textSelection(.enabled)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == .user ? YubaiColor.brand : YubaiColor.card,
                                            in: UnevenRoundedRectangle(topLeadingRadius: message.role == .user ? 18 : 6, bottomLeadingRadius: 22, bottomTrailingRadius: message.role == .user ? 6 : 22, topTrailingRadius: 22))
                            if message.role == .assistant { Spacer(minLength: 24) }
                        }
                    }
                    if busy { HStack { AssistantMark(thinking: true); Text("余白在听，也在想…").yubaiFont(YubaiFont.callout) } }
                    if let proposal, !revising {
                        ProfileProposalCard(change: proposal, confirm: {
                            if store.apply(proposal, label: "修改消费观") { dismiss() }
                        }, secondaryTitle: "再改改") { revising = true }
                    }
                    if !errorText.isEmpty {
                        InlineNote(text: errorText)
                        Button("重试") { ask() }.disabled(busy).frame(minHeight: 44)
                    }
                }.padding(18).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
            if proposal == nil || revising {
                HStack(spacing: 8) {
                    TextField(revising ? "想改哪里？" : "写下你的想法…", text: $input, axis: .vertical).lineLimit(1...6)
                        .accessibilityLabel("告诉余白你的消费观")
                    Button { ask() } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44).background(YubaiColor.brand, in: Circle()).foregroundStyle(YubaiColor.onBrand) }
                        .accessibilityLabel("发送").disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(8).background(YubaiColor.raised, in: RoundedRectangle(cornerRadius: 26)).yubaiShadow(YubaiShadow.input).padding(18)
            }
        }.background(YubaiColor.canvas).navigationTitle("和余白聊几句").yubaiNavigation()
            .toolbar {
                CloseButton()
                if proposal == nil && !messages.isEmpty {
                    Button("先跳过") { input = "暂时没想好，先跳过"; ask() }.disabled(busy).frame(minHeight: 44)
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
                if let change {
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
