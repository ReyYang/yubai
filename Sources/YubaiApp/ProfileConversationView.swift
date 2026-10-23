import SwiftUI
import YubaiCore

struct ProfileConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var openingContext: ProfileColdStart.OpeningContext? = nil
    @State private var startedAsRevisit: Bool?
    @State private var notes: [MemoryNote] = []
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var errorText = ""
    @State private var busy = false
    @State private var pendingUserTurn = false
    @State private var revising = false
    @State private var proposalID: UUID?
    @State private var runningTask: Task<Void, Never>?
    private var revisit: Bool {
        if let startedAsRevisit { return startedAsRevisit }
        let profile = store.current.profile
        return openingContext != nil || !profile.generous.isEmpty || !profile.restrain.isEmpty || !profile.principles.isEmpty || profile.floorAmount != nil
    }
    private var proposal: ChangeSet? { store.current.pendingChanges.first { $0.id == proposalID } }
    var body: some View {
        VStack(spacing: YubaiSpace.none) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                        if !revisit {
                            HStack(spacing: YubaiSpace.space8) {
                                ForEach(0..<3, id: \.self) { index in
                                    Circle().fill(index < max(1, messages.filter { $0.role == .assistant }.count) ? YubaiColor.brand : YubaiColor.neutralSoft)
                                        .frame(width: YubaiSpace.space8, height: YubaiSpace.space8)
                                }
                            }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                                .accessibilityLabel("消费观，三个问题，第 \(min(3, max(1, messages.filter { $0.role == .assistant }.count))) 个")
                        }
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            HStack(spacing: YubaiSpace.gapGroup) {
                                if message.role == .user { Spacer(minLength: YubaiSpace.messageIndent) }
                                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                                    if message.role == .assistant {
                                        HStack(spacing: YubaiSpace.space8) { AssistantMark(size: 14).accessibilityHidden(true); Text("余白").yubaiFont(YubaiFont.meta) }.foregroundStyle(YubaiColor.brandInk)
                                    }
                                    Text(message.content ?? "").yubaiFont(message.role == .user ? YubaiFont.body : YubaiFont.cardTitle)
                                        .foregroundStyle(message.role == .user ? YubaiColor.onBrand : YubaiColor.label).textSelection(.enabled)
                                    if revisit, index == 0, message.role == .assistant, !messages.contains(where: { $0.role == .user }) {
                                        VStack(alignment: .leading, spacing: YubaiSpace.gapGroup) {
                                            ForEach(["最近花钱的感觉变了", "加一条想克制的", "看看这个月我做得怎么样"], id: \.self) { starter in
                                                Button { input = starter; ask() } label: {
                                                    Text(starter).yubaiFont(YubaiFont.callout).padding(.horizontal, YubaiSpace.gapGroup)
                                                        .frame(minHeight: YubaiSize.chipHeight).background(YubaiColor.raised, in: Capsule()).yubaiHitTarget()
                                                }.buttonStyle(PressButtonStyle()).disabled(busy)
                                            }
                                        }
                                    }
                                }.padding(YubaiSpace.insetCard).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(message.role == .user ? YubaiColor.brand : YubaiColor.card,
                                                in: UnevenRoundedRectangle(topLeadingRadius: message.role == .user ? 18 : 6, bottomLeadingRadius: 22, bottomTrailingRadius: message.role == .user ? 6 : 22, topTrailingRadius: 22))
                                if message.role == .assistant { Spacer(minLength: YubaiSpace.gapSection) }
                            }.messageEntrance(user: message.role == .user)
                        }
                        if busy {
                            HStack(spacing: YubaiSpace.space8) {
                                AssistantMark(thinking: true).accessibilityHidden(true)
                                HStack(spacing: YubaiSpace.space4) {
                                    ForEach(0..<3, id: \.self) { _ in Circle().fill(YubaiColor.labelMuted).frame(width: 4, height: 4) }
                                }
                            }.accessibilityElement(children: .ignore).accessibilityLabel("余白正在思考")
                        }
                        RememberedRows(notes: notes)
                        if let proposal, !revising {
                            ProfileProposalCard(change: proposal, confirm: {
                                if store.apply(proposal, label: "修改消费观") { dismiss() }
                            }, secondaryTitle: "再改改") { revising = true }
                        }
                        if !errorText.isEmpty {
                            InlineNote(text: errorText)
                            Button("重试") { ask() }.disabled(busy).frame(minHeight: YubaiSize.tapMin)
                        }
                        Color.clear.frame(height: 1).id("latestProfileMessage")
                    }.padding(YubaiSpace.insetPage).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in proxy.scrollTo("latestProfileMessage", anchor: .bottom) }
                    .onChange(of: busy) { _, _ in proxy.scrollTo("latestProfileMessage", anchor: .bottom) }
            }
            if proposal == nil || revising {
                ChatInputBar(text: $input, placeholder: revising ? "想改哪里？" : "写下你的想法…",
                    accessibilityLabel: "告诉余白你的消费观", inputID: "profileInput", sendID: "sendProfile",
                    busy: busy, send: ask, leading: { Color.clear.frame(width: YubaiSpace.space8).accessibilityHidden(true) }, accessory: { EmptyView() })
                    .padding(YubaiSpace.insetPage)
            }
        }.paperBackground().navigationTitle("和余白聊聊").yubaiNavigation()
            .toolbar {
                CloseButton()
                if !revisit && proposal == nil && !messages.isEmpty {
                    Button("先跳过") { input = "暂时没想好，先跳过"; ask() }.disabled(busy).frame(minHeight: YubaiSize.tapMin)
                }
            }
            .task {
                guard messages.isEmpty && proposalID == nil else { return }
                startedAsRevisit = revisit
                ask()
            }
            .onDisappear { runningTask?.cancel() }
            .onChange(of: store.current.id) { _, _ in runningTask?.cancel(); dismiss() }
            .onChange(of: store.locked) { _, locked in if locked { runningTask?.cancel(); dismiss() } }
            .onChange(of: store.current.preferences.cloudAIEnabled) { _, enabled in if !enabled { runningTask?.cancel(); dismiss() } }
    }
    @MainActor private func ask() {
        guard !busy else { return }
        let before = store.current
        guard !store.locked, before.preferences.cloudAIEnabled, let transport = store.assistantTransport(for: before) else {
            errorText = "还没配密钥"; return
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
                let reply = try await ProfileColdStart(transport: transport).next(ledger: before, messages: conversation, mode: revisit ? .revisit : .coldStart, openingContext: openingContext)
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
                for note in reply.rememberedNotes + reply.updatedNotes.map(\.note) {
                    if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note }
                    else { notes.append(note) }
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
