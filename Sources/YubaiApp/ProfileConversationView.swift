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
                    let step = min(3, max(1, messages.filter { $0.role == .assistant }.count))
                    HStack(spacing: YubaiSpace.space4) {
                        ForEach(1...3, id: \.self) { index in
                            Capsule().fill(index <= step ? YubaiColor.brand : YubaiColor.neutralSoft)
                                .frame(width: index == step ? YubaiSpace.gapGroup + YubaiSpace.space8 : YubaiSize.marker, height: YubaiSize.marker)
                        }
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                        .accessibilityLabel("第 \(step) 题，共 3 题")
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
                    if busy {
                        HStack(spacing: YubaiSpace.gapGroup) {
                            AssistantMark(thinking: true)
                            ForEach(0..<3) { index in Circle().fill(YubaiColor.brand.opacity(1 - Double(index) * 0.3)).frame(width: YubaiSize.marker, height: YubaiSize.marker) }
                        }.padding(YubaiSpace.insetCard).frame(maxWidth: .infinity, alignment: .leading)
                            .background(YubaiColor.brandTint, in: RoundedRectangle(cornerRadius: YubaiRadius.card))
                            .accessibilityElement(children: .ignore).accessibilityLabel("余白正在思考")
                    }
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
                HStack(spacing: YubaiSpace.space8) {
                    TextField(revising ? "想改哪里？" : "写下你的想法…", text: $input, axis: .vertical).lineLimit(1...6)
                        .accessibilityLabel("告诉余白你的消费观")
                    Button { ask() } label: { Image(systemName: "arrow.up").frame(width: YubaiSize.tapMin, height: YubaiSize.tapMin).background(YubaiColor.brand, in: Circle()).foregroundStyle(YubaiColor.onBrand) }
                        .accessibilityLabel("发送").disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(YubaiSpace.space8).buttonStyle(PressButtonStyle()).floatingSurface(in: Capsule(), shadow: YubaiShadow.input).padding(YubaiSpace.insetPage)
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
        if !messages.isEmpty {
            guard !answer.isEmpty else { return }
            if pendingUserTurn, turn.last?.role == .user { turn.removeLast() }
            turn.append(ChatMessage(role: .user, content: answer))
        }
        let conversation = turn
        messages = conversation; pendingUserTurn = conversation.last?.role == .user
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
                pendingUserTurn = false
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
