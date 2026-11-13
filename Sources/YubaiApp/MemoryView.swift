import SwiftUI
import YubaiCore

struct MemoryView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: MemoryNote?
    private var notes: [MemoryNote] {
        store.current.memories.sorted { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        Page(topPadding: YubaiSpace.space8) {
            if notes.isEmpty {
                EmptyState("text.book.closed", "还没有记下的事", action: "问余白", onAction: { store.sheet = .ask("") }).accessibilityIdentifier("emptyMemories")
            } else {
                NativeCardRows(notes) { note in
                    NavigationLink { MemoryEditor(note: note) } label: {
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                            Text(store.preferences.hideAmounts ? "金额已隐藏" : note.text).yubaiFont(YubaiFont.row)
                            Text(metadata(note)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }.padding(.vertical, YubaiSpace.space8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.hidesListDisclosure().accessibilityIdentifier("memory_" + note.id.uuidString)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删掉") { remove(note) }.tint(YubaiColor.amberTint).accessibilityIdentifier("swipeDeleteMemory_" + note.id.uuidString)
                            Button("改一下") { editing = note }.tint(YubaiColor.card).accessibilityIdentifier("swipeEditMemory_" + note.id.uuidString)
                        }
                }
            }
        }.amountPrivacy(store.preferences.hideAmounts).navigationTitle("余白记得的").yubaiNavigation().accessibilityIdentifier("memoriesPage")
            .sheet(item: $editing) { note in
                NavigationStack { MemoryEditor(note: note) }.environment(store).appErrors().yubaiSheetBackground()
            }
            .toolbar { ToolbarItem(placement: .primaryAction) { Text("\(notes.count) 条").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) } }
    }
    private func remove(_ note: MemoryNote) {
        store.update("删除记忆") { ledger in Memory.reject(lineMemoryID: note.id, in: &ledger) }
    }
    private func metadata(_ note: MemoryNote) -> String {
        day(note.updatedAt) + " · " + source(note)
    }

    private func day(_ date: Date) -> String { date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) }
    private func source(_ note: MemoryNote) -> String {
        switch note.source {
        case .chat, .user: return "你说的"
        case .reflection: return "从账目里看出来的"
        case .importAnswer, .feedback: return "你改过一次"
        case .followUp: return "买了一个月"
        }
    }
}

private struct MemoryEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.yubaiSheetSurface) private var inSheet
    @State private var note: MemoryNote
    @State private var text: String
    init(note: MemoryNote) { _note = State(initialValue: note); _text = State(initialValue: note.text) }
    var body: some View {
        Group {
            if inSheet { form.manualSheetHeader("编辑记忆", actionTitle: "保存", enabled: valid, actionIdentifier: "saveMemory", action: save) }
            else { form.toolbar { Button("保存", action: save).disabled(!valid).accessibilityIdentifier("saveMemory") } }
        }
    }
    private var valid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 200 && !text.contains(where: { $0.isNewline }) }
    private var form: some View {
        Form {
            Section {
                CardTextFieldRow(title: "", text: $text, placeholder: "记忆文字", identifier: "memoryText", multiline: true)
                InlineFieldError(message: text.count > 200 || text.contains(where: { $0.isNewline }) ? "记忆须在一行内，最多 200 字" : nil)
            }.listRowBackground(YubaiColor.card)
            Section {
                Button("删掉") {
                    if store.update("删除记忆", { ledger in
                        try check(ledger); Memory.reject(lineMemoryID: note.id, in: &ledger)
                    }) { dismiss() }
                }.buttonStyle(DestructiveButtonStyle()).accessibilityIdentifier("deleteMemory")
            }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("编辑记忆").yubaiNavigation()
    }
    private func save() {
        if store.update("修改记忆", { ledger in try check(ledger); try Memory.edit(noteID: note.id, text: text, in: &ledger) }) { dismiss() }
    }
    private func check(_ ledger: Ledger) throws {
        guard var current = ledger.memories.first(where: { $0.id == note.id }) else { throw YubaiError.invalid("这条记忆已删掉。") }
        current.lastUsedAt = note.lastUsedAt
        guard current == note else { throw YubaiError.invalid("这条记忆已更新，请返回后重新打开。") }
    }
}

struct RememberedRows: View {
    @Environment(AppStore.self) private var store
    let notes: [MemoryNote]
    @State private var undone = Set<UUID>()
    private var visible: [MemoryNote] {
        notes.filter { note in
            guard !undone.contains(note.id), var current = store.current.memories.first(where: { $0.id == note.id }) else { return false }
            current.lastUsedAt = note.lastUsedAt
            return current == note
        }
    }
    var body: some View {
        ForEach(visible) { note in
            VStack(spacing: YubaiSpace.space8) {
                Rectangle().fill(YubaiColor.separator).frame(height: 1).accessibilityHidden(true)
                HStack(spacing: YubaiSpace.space8) {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                    Text("已记下：" + note.text).frame(maxWidth: .infinity, alignment: .leading)
                    Button("撤销") {
                        if store.update("撤销记忆", { ledger in
                            guard var current = ledger.memories.first(where: { $0.id == note.id }) else { throw YubaiError.invalid("这条记忆已删掉。") }
                            current.lastUsedAt = note.lastUsedAt
                            guard current == note else { throw YubaiError.invalid("这条记忆后来已更新，请在余白记得的里查看。") }
                            Memory.undo(noteID: note.id, in: &ledger)
                        }) { undone.insert(note.id) }
                    }.buttonStyle(SmallActionStyle()).accessibilityLabel("撤销记忆：" + note.text)
                }.yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
            }.padding(.top, YubaiSpace.space4)
        }
    }
}
