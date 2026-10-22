import SwiftUI
import YubaiCore

struct MemoryView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            if store.current.memories.isEmpty {
                Text("还没有记下什么。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary).accessibilityIdentifier("emptyMemories")
            }
            ForEach(MemoryKind.allCases, id: \.self) { kind in
                let notes = store.current.memories.filter { $0.kind == kind }.sorted {
                    $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
                }
                if !notes.isEmpty {
                    Section {
                        ForEach(notes) { note in
                            NavigationLink { MemoryEditor(note: note) } label: {
                                VStack(alignment: .leading, spacing: YubaiSpace.space2) {
                                    Text(note.text).yubaiFont(YubaiFont.row)
                                    Text(metadata(note)).yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                                }.padding(.vertical, YubaiSpace.space6)
                            }.accessibilityIdentifier("memory_" + note.id.uuidString)
                                .listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
                        }.onDelete { offsets in
                            let ids = offsets.map { notes[$0].id }
                            store.update("删除记忆") { ledger in
                                for id in ids { Memory.reject(lineMemoryID: id, in: &ledger) }
                            }
                        }
                    } header: { Text(title(kind)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary) }
                }
            }
        }.editorForm()
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("余白记得的").yubaiNavigation()
    }
    private func title(_ kind: MemoryKind) -> String {
        switch kind { case .plan: "计划"; case .value: "在乎的事"; case .life: "生活情况" }
    }
    private func metadata(_ note: MemoryNote) -> String {
        if let previous = note.previousText {
            let date = ButlerCards.isoWeek(note.updatedAt) == ButlerCards.isoWeek(Date()) ? "这周更新" : day(note.updatedAt)
            return date + " · 原来记的是「" + previous + "」"
        }
        return day(note.createdAt) + " · " + source(note)
    }
    private func day(_ date: Date) -> String { date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN"))) }
    private func source(_ note: MemoryNote) -> String {
        switch note.source {
        case .chat: return note.source.label
        case .followUp:
            for choice in ["值得", "一般", "有点后悔"] where note.text.contains("一个月后觉得" + choice) { return "买了一个月 · 用得怎么样？「" + choice + "」" }
            return "买了一个月 · 用得怎么样？"
        case .importAnswer: return note.source.label
        case .feedback: return note.source.label
        case .reflection: return note.source.label
        case .user: return note.source.label
        }
    }
}

private struct MemoryEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var note: MemoryNote
    @State private var text: String
    init(note: MemoryNote) { _note = State(initialValue: note); _text = State(initialValue: note.text) }
    var body: some View {
        Form {
            Section {
                TextField("记忆文字", text: $text, axis: .vertical).lineLimit(2...8).accessibilityIdentifier("memoryText")
            }.listRowBackground(YubaiColor.card)
            Section {
                Button("删除这条记忆", role: .destructive) {
                    if store.update("删除记忆", { ledger in
                        try check(ledger); Memory.reject(lineMemoryID: note.id, in: &ledger)
                    }) { dismiss() }
                }.accessibilityIdentifier("deleteMemory")
            }.listRowBackground(YubaiColor.card)
        }.editorForm().navigationTitle("编辑记忆").yubaiNavigation()
            .toolbar {
                Button("保存") {
                    if store.update("修改记忆", { ledger in
                        try check(ledger); try Memory.edit(noteID: note.id, text: text, in: &ledger)
                    }) { dismiss() }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 200 || text.contains(where: { $0.isNewline }))
                    .accessibilityIdentifier("saveMemory")
            }
    }
    private func check(_ ledger: Ledger) throws {
        guard var current = ledger.memories.first(where: { $0.id == note.id }) else { throw YubaiError.invalid("这条记忆已删除。") }
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
                            guard var current = ledger.memories.first(where: { $0.id == note.id }) else { throw YubaiError.invalid("这条记忆已删除。") }
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
