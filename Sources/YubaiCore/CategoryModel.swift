import Foundation

/// One result for both levels. A main-only memory deliberately has no small item.
public struct CategoryAssignment: Equatable, Sendable {
    public var category: String
    public var subcategory: String?
    public init(category: String, subcategory: String? = nil) { self.category = category; self.subcategory = subcategory }
    public init(path: String) {
        let parts = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        category = parts[0]; subcategory = parts.count == 2 && !parts[1].isEmpty ? parts[1] : nil
    }
    public var path: String { category + (subcategory.map { "/" + $0 } ?? "") }
}

/// A user-confirmed addition can be committed together with the selected rows.
public struct CategoryAddition: Equatable, Sendable {
    public var name: String
    public var parent: String?
    public var income: Bool
    public init(name: String, parent: String? = nil, income: Bool) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines); self.parent = parent; self.income = income
    }
    public var assignment: CategoryAssignment { .init(category: parent ?? name, subcategory: parent == nil ? nil : name) }
    public func apply(to ledger: inout Ledger) throws {
        if let parent {
            guard ledger.selectableCategories.contains(where: { $0.name == parent && $0.income == income }) else { throw YubaiError.invalid("这个分类不能修改。") }
            try CategoryModel.addSubcategory(name, to: parent, in: &ledger)
        } else { try CategoryModel.add(Category(name, income: income), in: &ledger) }
    }
}

public extension Ledger {
    var selectableCategories: [Category] { categories.filter { !$0.system && !$0.hidden } }
    /// Preference order with stable table-order fallback; catch-alls stay last.
    func orderedCategories(income: Bool, hidden: Bool = false) -> [Category] {
        let table = categories.filter { !$0.system && $0.hidden == hidden && $0.income == income }
        let other = income ? "其他收入" : "其他支出"
        var seen = Set<String>()
        let names = (preferences.categoryOrder + table.map(\.name)).filter { seen.insert($0).inserted && $0 != other }
        let byName = Dictionary(uniqueKeysWithValues: table.map { ($0.name, $0) })
        return (names + [other]).compactMap { byName[$0] }
    }
    func categoryNames(including current: String? = nil, income: Bool? = nil) -> [String] {
        var names = selectableCategories.filter { income == nil || $0.income == income }.map(\.name)
        if let current, !names.contains(current), !categories.contains(where: { $0.name == current && ($0.system || $0.hidden) }) { names.append(current) }
        return names
    }

    func categoryAssignment(category: String, subcategory: String? = nil) -> CategoryAssignment {
        var value = CategoryAssignment(category: category, subcategory: subcategory == "其他" ? nil : subcategory)
        var seen = Set<String>()
        while seen.insert(value.path).inserted {
            if let path = categoryAliases[value.path] {
                value = CategoryAssignment(path: path)
            } else if let main = categoryAliases[value.category] {
                let mapped = CategoryAssignment(path: main)
                value = .init(category: mapped.category, subcategory: value.subcategory ?? mapped.subcategory)
            } else { break }
        }
        if Classification.isPending(value.category) { return .init(category: Classification.pendingCategory) }
        return value
    }
    /// Shared statistics/read model. Callers scanning rows pass their cached index.
    func normalizedCategory(for entry: Entry, entriesByID: [UUID: Entry]? = nil) -> CategoryAssignment {
        var source = entry
        if entry.nature == .refund, let id = entry.relatedEntryID,
           let original = entriesByID.map({ $0[id] }) ?? entries.first(where: { $0.id == id }), original.nature == .expense {
            source = original
        }
        if source.nature == .transfer { return .init(category: "内部移动") }
        if Classification.isPending(source) { return .init(category: Classification.pendingCategory) }
        return categoryAssignment(category: source.category, subcategory: source.subcategory)
    }
}

public enum CategoryGuesser {
    /// Memory keys are examined in purpose/merchant/title order, then table words.
    /// An existing main is a constraint: only pending can acquire a different main.
    public static func guess(_ entry: Entry, in ledger: Ledger, billLabel: String? = nil) -> CategoryAssignment? {
        if entry.nature == .transfer { return .init(category: "内部移动") }
        let current = ledger.categoryAssignment(category: entry.category, subcategory: entry.subcategory)
        let pending = Classification.isPending(entry) || Classification.isPending(current.category)
        let income = entry.nature != .refund && entry.nature.inflow
        var table = ledger.selectableCategories.filter { $0.income == income && (pending || $0.name == current.category) }
        if !pending && ["其他支出", "其他收入"].contains(current.category) { return nil }
        for key in SubcategoryClassifier.keys(entry) + [CategoryMemory.key(UnsortedGroups.party(for: entry))] {
            guard let path = ledger.classificationMemory[key] else { continue }
            let value = CategoryAssignment(path: path)
            let choice = ledger.categoryAssignment(category: value.category, subcategory: value.subcategory)
            if table.contains(where: { $0.name == choice.category && (choice.subcategory == nil || $0.subcategories.contains(choice.subcategory!)) }) { return choice }
        }
        var hint: CategoryAssignment?
        if pending, let billLabel { hint = CategoryMapping.match(billLabel, in: ledger, income: income) }
        if let hint {
            if hint.subcategory != nil || ["其他支出", "其他收入"].contains(hint.category) { return hint }
            table = table.filter { $0.name == hint.category }
        }
        let text = [entry.purpose ?? "", entry.quickCapture?.merchant ?? "", entry.title].joined(separator: " ")
        // Longest evidence wins: "电影会员" must beat "电影"; stable table order
        // breaks ties. All matching words, including priorities, live in the table.
        var best: (choice: CategoryAssignment, length: Int)?
        for main in table {
            for word in main.keywords + [main.name] where !word.isEmpty && text.localizedCaseInsensitiveContains(word) {
                if word.count > (best?.length ?? 0) { best = (.init(category: main.name), word.count) }
            }
            for sub in main.subcategories {
                for word in (main.subcategoryKeywords[sub] ?? []) + [sub] where !word.isEmpty && text.localizedCaseInsensitiveContains(word) {
                    if word.count > (best?.length ?? 0) || (word.count == best?.length && best?.choice.category == main.name && best?.choice.subcategory == nil) {
                        best = (.init(category: main.name, subcategory: sub), word.count)
                    }
                }
            }
        }
        var result = best?.choice
        // Time is evidence only for meal-like text already constrained to dining.
        if !pending, current.category == "餐饮", result?.subcategory == nil,
           ["吃饭", "饭", "食堂"].contains(where: text.contains) {
            let hour = Dates.calendar.component(.hour, from: entry.date)
            let meal = (5..<10).contains(hour) ? "早餐" : (10..<15).contains(hour) ? "午餐" : (17..<22).contains(hour) ? "晚餐" : nil
            if let meal, table.contains(where: { $0.name == "餐饮" && $0.subcategories.contains(meal) }) { result = .init(category: "餐饮", subcategory: meal) }
        }
        return result ?? hint
    }
    public static func guess(_ text: String, nature: Nature, date: Date = Date(), in ledger: Ledger) -> CategoryAssignment? {
        guess(Entry(date: date, amount: 1, nature: nature, accountID: UUID(), title: text, category: Classification.pendingCategory), in: ledger)
    }
}

public enum CategoryMapping {
    /// Bill labels are evidence, never new category definitions. Exact/alias first,
    /// then the longest contained main or small-item name, constrained by direction.
    public static func match(_ label: String, in ledger: Ledger, income: Bool? = nil) -> CategoryAssignment? {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Classification.isPending(label) else { return nil }
        let table = ledger.selectableCategories.filter { income == nil || $0.income == income }
        let parts = CategoryAssignment(path: label)
        let direct = ledger.categoryAssignment(category: parts.category, subcategory: parts.subcategory)
        if let main = table.first(where: { $0.name == direct.category }) {
            let small = direct.subcategory ?? (main.subcategories.contains(label) ? label : nil)
            return .init(category: main.name, subcategory: small.flatMap { main.subcategories.contains($0) ? $0 : nil })
        }
        let legacy = CategoryMigration.canonical(label)
        if table.contains(where: { $0.name == legacy.category }) { return .init(category: legacy.category, subcategory: legacy.subcategory) }
        var best: (CategoryAssignment, Int)?
        for main in table {
            for name in [main.name] + main.subcategories where label.localizedCaseInsensitiveContains(name) {
                if name.count > (best?.1 ?? 0) || (name.count == best?.1 && best?.0.category == main.name && name != main.name) { best = (.init(category: main.name, subcategory: name == main.name ? nil : name), name.count) }
            }
        }
        return best?.0
    }
}

/// The same traversal is used by migration and user category operations. It also
/// rewrites retained undo snapshots and question options, so they cannot resurrect
/// removed names after an import undo or a delayed proposal is accepted.
enum CategoryReferences {
    static func rewrite(_ ledger: inout Ledger, using map: (CategoryAssignment) -> CategoryAssignment) {
        func entry(_ old: Entry) -> Entry {
            var value = old
            let choice = old.nature == .transfer ? CategoryAssignment(category: "内部移动") : map(.init(category: Classification.isPending(old) ? Classification.pendingCategory : old.category, subcategory: old.subcategory))
            value.category = choice.category; value.subcategory = choice.subcategory
            return value
        }
        func plan(_ old: Plan) -> Plan { var value = old; value.category = map(.init(category: old.category)).category; return value }
        func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
        func area(_ old: ProfileArea) -> ProfileArea {
            var value = old
            value.match.categories = unique(old.match.categories.map { map(.init(category: $0)).category })
            // A deleted small item becomes its main match rather than a dangling path.
            value.match.subcategories = []
            for path in old.match.subcategories {
                let choice = map(CategoryAssignment(path: path))
                if choice.subcategory != nil { value.match.subcategories.append(choice.path) }
                else if !value.match.categories.contains(choice.category) { value.match.categories.append(choice.category) }
            }
            value.match.subcategories = unique(value.match.subcategories)
            return value
        }
        func item(_ old: ChangeItem) -> ChangeItem {
            switch old {
            case .setCategory(let id, let name): return .setCategory(entry: id, category: map(.init(category: name)).category)
            case .addEntry(var draft):
                let choice = map(.init(category: draft.category, subcategory: draft.subcategory))
                draft.category = choice.category; draft.subcategory = choice.subcategory; return .addEntry(draft)
            case .addPlan(let old): return .addPlan(plan(old))
            case .updatePlan(let old): return .updatePlan(plan(old))
            case .profile(.upsertArea(let old, let stance)): return .profile(.upsertArea(area(old), stance: stance))
            default: return old
            }
        }
        ledger.entries = ledger.entries.map(entry)
        ledger.plans = ledger.plans.map(plan)
        for i in ledger.stoppedSubscriptions.indices { ledger.stoppedSubscriptions[i].plan = plan(ledger.stoppedSubscriptions[i].plan) }
        for i in ledger.wishlist.indices {
            guard let main = ledger.wishlist[i].category else { continue }
            let choice = map(.init(category: main, subcategory: ledger.wishlist[i].subcategory))
            ledger.wishlist[i].category = choice.category; ledger.wishlist[i].subcategory = choice.subcategory
        }
        ledger.profile.generous = ledger.profile.generous.map(area); ledger.profile.restrain = ledger.profile.restrain.map(area)
        ledger.classificationMemory = ledger.classificationMemory.mapValues { map(CategoryAssignment(path: $0)).path }
        ledger.categoryAliases = ledger.categoryAliases.mapValues { map(CategoryAssignment(path: $0)).path }
        ledger.preferences.quickCapture.merchantCategories = ledger.preferences.quickCapture.merchantCategories.mapValues { map(CategoryAssignment(path: $0)).path }
        ledger.preferences.categoryOrder = unique(ledger.preferences.categoryOrder.map { map(.init(category: $0)).category })
        for i in ledger.pendingChanges.indices { ledger.pendingChanges[i].items = ledger.pendingChanges[i].items.map(item) }
        for i in ledger.imports.indices {
            if ledger.imports[i].undo != nil { ledger.imports[i].undo!.entries = ledger.imports[i].undo!.entries.map(entry) }
        }
        for i in ledger.cards.indices {
            guard var question = ledger.cards[i].importQuestion else { continue }
            for j in question.options.indices { question.options[j].items = question.options[j].items.map(item) }
            ledger.cards[i].importQuestion = question
        }
        LedgerOperations.syncLinkedRefundCategories(in: &ledger)
    }
}

public enum CategoryModel {
    /// Explicit UI choices also record nil: “main only” must override local guesses.
    public static func confirm(_ choice: CategoryAssignment, entryIDs: Set<UUID>, includingParty: Bool = false, in ledger: inout Ledger) throws {
        try update(&ledger) { next in
            for i in next.entries.indices where entryIDs.contains(next.entries[i].id) && next.entries[i].deletedAt == nil {
                guard SubcategoryClassifier.valid(choice, in: next, nature: next.entries[i].nature) else { throw YubaiError.invalid("这个小项不属于该主项。") }
                next.entries[i].category = choice.category; next.entries[i].subcategory = choice.subcategory
                next.entries[i].subcategoryUserEdited = true
                CategoryMemory.remember(next.entries[i], includingParty: includingParty, in: &next)
            }
            LedgerOperations.syncLinkedRefundCategories(in: &next, expenseIDs: entryIDs)
        }
    }
    private static func name(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Classification.isPending(value), value.count <= 200, !value.contains("/"), value != "其他" else { throw YubaiError.invalid("分类名称无效。") }
        return value
    }
    private static func index(_ category: String, in ledger: Ledger, protected: Bool = true) throws -> Int {
        guard let index = ledger.categories.firstIndex(where: { $0.name == category }),
              !ledger.categories[index].system,
              !protected || !["其他支出", "其他收入"].contains(category) else { throw YubaiError.invalid("这个分类不能修改。") }
        return index
    }
    private static func update(_ ledger: inout Ledger, _ body: (inout Ledger) throws -> Void) throws {
        var next = ledger; try body(&next); try next.validate(); ledger = next
    }
    public static func add(_ category: Category, in ledger: inout Ledger) throws {
        try update(&ledger) { next in
            let cleaned = try name(category.name)
            guard !category.system, !next.categories.contains(where: { $0.name == cleaned }), next.categoryAliases[cleaned] == nil else { throw YubaiError.invalid("分类名称已存在。") }
            var value = category; value.name = cleaned; next.categories.append(value)
        }
    }
    public static func rename(_ category: String, to rawName: String, in ledger: inout Ledger) throws {
        try update(&ledger) { next in
            let i = try index(category, in: next); let renamed = try name(rawName)
            guard renamed != category else { return }
            guard !next.categories.contains(where: { $0.name == renamed }), next.categoryAliases[renamed] == nil else { throw YubaiError.invalid("分类名称已存在。") }
            let before = next
            CategoryReferences.rewrite(&next) { old in
                var value = before.categoryAssignment(category: old.category, subcategory: old.subcategory)
                if value.category == category { value.category = renamed }; return value
            }
            next.categories[i].keywords.append(category)
            next.categories[i].name = renamed; next.categoryAliases[category] = renamed
        }
    }
    public static func merge(_ source: String, into target: String, in ledger: inout Ledger) throws {
        try update(&ledger) { next in
            let a = try index(source, in: next); let b = try index(target, in: next, protected: false)
            guard a != b, next.categories[a].income == next.categories[b].income else { throw YubaiError.invalid("只能合并同一收支方向的不同分类。") }
            // Keep source small items and words, except intentional catch-all targets.
            let catchAll = ["其他支出", "其他收入"].contains(target)
            if !catchAll {
                for sub in next.categories[a].subcategories where !next.categories[b].subcategories.contains(sub) { next.categories[b].subcategories.append(sub) }
                for (sub, words) in next.categories[a].subcategoryKeywords { next.categories[b].subcategoryKeywords[sub, default: []] += words }
                next.categories[b].keywords += next.categories[a].keywords + [source]
            }
            let before = next
            CategoryReferences.rewrite(&next) { old in
                var value = before.categoryAssignment(category: old.category, subcategory: old.subcategory)
                if value.category == source { value.category = target; if catchAll { value.subcategory = nil } }; return value
            }
            next.categories.remove(at: a); next.categoryAliases[source] = target
        }
    }
    public static func setHidden(_ hidden: Bool, category: String, in ledger: inout Ledger) throws {
        try update(&ledger) { next in let i = try index(category, in: next, protected: false); next.categories[i].hidden = hidden }
    }
    public static func addSubcategory(_ raw: String, to category: String, keywords: [String] = [], in ledger: inout Ledger) throws {
        try update(&ledger) { next in
            let i = try index(category, in: next); let sub = try name(raw)
            guard !next.categories[i].subcategories.contains(sub), next.categoryAliases[category + "/" + sub] == nil else { throw YubaiError.invalid("小项已存在。") }
            next.categories[i].subcategories.append(sub); next.categories[i].subcategoryKeywords[sub] = keywords
        }
    }
    public static func renameSubcategory(_ sub: String, in category: String, to raw: String, ledger: inout Ledger) throws {
        try update(&ledger) { next in
            let i = try index(category, in: next); let renamed = try name(raw)
            guard let j = next.categories[i].subcategories.firstIndex(of: sub), !next.categories[i].subcategories.contains(renamed), next.categoryAliases[category + "/" + renamed] == nil else { throw YubaiError.invalid("小项不存在或名称重复。") }
            let before = next
            CategoryReferences.rewrite(&next) { old in
                var value = before.categoryAssignment(category: old.category, subcategory: old.subcategory)
                if value.category == category && value.subcategory == sub { value.subcategory = renamed }; return value
            }
            next.categories[i].subcategories[j] = renamed
            next.categories[i].subcategoryKeywords[renamed] = (next.categories[i].subcategoryKeywords.removeValue(forKey: sub) ?? []) + [sub]
            next.categoryAliases[category + "/" + sub] = category + "/" + renamed
        }
    }
    public static func removeSubcategory(_ sub: String, from category: String, in ledger: inout Ledger) throws {
        try update(&ledger) { next in
            let i = try index(category, in: next)
            guard next.categories[i].subcategories.contains(sub) else { throw YubaiError.invalid("小项不存在。") }
            let before = next
            CategoryReferences.rewrite(&next) { old in
                var value = before.categoryAssignment(category: old.category, subcategory: old.subcategory)
                if value.category == category && value.subcategory == sub { value.subcategory = nil }; return value
            }
            next.categories[i].subcategories.removeAll { $0 == sub }; next.categories[i].subcategoryKeywords.removeValue(forKey: sub)
            next.categoryAliases[category + "/" + sub] = category
        }
    }
    public static func setOrder(_ names: [String], in ledger: inout Ledger) throws {
        try update(&ledger) { next in
            guard Set(names).count == names.count, names.allSatisfy({ name in next.categories.contains { $0.name == name && !$0.system } }) else { throw YubaiError.invalid("分类顺序无效。") }
            next.preferences.categoryOrder = names
        }
    }
}
