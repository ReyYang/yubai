import Foundation

/// The four 「云端能看到」 switches. Nil in an older ledger means these defaults.
public struct CloudShareSettings: Codable, Equatable, Sendable {
    public var amount: Bool
    public var category: Bool
    public var note: Bool
    public var account: Bool
    public init(amount: Bool = true, category: Bool = true, note: Bool = false, account: Bool = false) {
        self.amount = amount; self.category = category; self.note = note; self.account = account
    }
    public static let defaults = CloudShareSettings()

    private enum CodingKeys: String, CodingKey { case amount, category, note, account }
    /// Unknown keys from a newer version are ignored; missing keys take the default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        amount = try c.decodeIfPresent(Bool.self, forKey: .amount) ?? d.amount
        category = try c.decodeIfPresent(Bool.self, forKey: .category) ?? d.category
        note = try c.decodeIfPresent(Bool.self, forKey: .note) ?? d.note
        account = try c.decodeIfPresent(Bool.self, forKey: .account) ?? d.account
    }
}

extension Preferences {
    public var cloudShareSettings: CloudShareSettings {
        get { cloudShare ?? .defaults }
        set { cloudShare = newValue == .defaults ? nil : newValue }
    }
}

/// Second privacy layer on top of `Redactor`: what the user switched off never leaves
/// the phone. Applied by `ModelRouter` only to providers that leave the device.
public struct CloudSharePolicy: Sendable {
    public var settings: CloudShareSettings
    private let accountAliases: [(name: String, alias: String)]
    private let categoryCodes: [(name: String, code: String)]
    private let notes: [String]

    public init(settings: CloudShareSettings = .defaults, ledger: Ledger? = nil) {
        self.settings = settings
        let accounts = ledger?.accounts ?? []
        // Same aliases the read-only tools already send («账户N», ledger order).
        accountAliases = accounts.enumerated().map { (name: $0.element.name, alias: "账户\($0.offset + 1)") }
            .filter { $0.name.count >= 2 }.sorted { $0.name.count > $1.name.count }
        var codes: [(String, String)] = []
        for (index, category) in (ledger?.categories ?? Category.defaults).enumerated() {
            codes.append((category.name, "分类\(index + 1)"))
            for (subIndex, sub) in category.subcategories.enumerated() { codes.append((sub, "分类\(index + 1)-\(subIndex + 1)")) }
        }
        var seen = Set<String>()
        categoryCodes = codes.filter { !$0.0.isEmpty && seen.insert($0.0).inserted }.sorted { $0.0.count > $1.0.count }
            .map { (name: $0.0, code: $0.1) }
        notes = Array(Set((ledger?.entries ?? []).map(\.note).filter { $0.count >= 2 })).sorted { $0.count > $1.count }
    }

    public var sharesEverything: Bool { settings.amount && settings.category && settings.note && settings.account }

    public func apply(to request: ChatRequest) -> ChatRequest {
        guard !sharesEverything else { return request }
        var request = request
        for index in request.messages.indices {
            // Tool-call arguments are the model's own output (ids, echoed values); leave them.
            if let content = request.messages[index].content { request.messages[index].content = self.content(content) }
        }
        return request
    }

    public func content(_ input: String) -> String {
        if let json = try? JSONValue.parse(input), json.objectValue != nil || json.arrayValue != nil,
           let clean = try? value(json).jsonText() { return clean }
        return text(input)
    }

    public static func band(cents: Int64) -> String {
        let magnitude = cents.magnitude
        return magnitude < 10_000 ? "小额" : magnitude < 100_000 ? "中额" : "大额"
    }

    private static let noteKeys: Set<String> = ["note", "notes", "memo", "remark"]
    private static let categoryKeys: Set<String> = ["category", "subcategory", "categories", "subcategories"]
    private static let accountKeys: Set<String> = ["account_name", "accountname", "account_title"]

    public func value(_ input: JSONValue) -> JSONValue {
        switch input {
        case .string(let s): return UUID(uuidString: s) != nil ? input : .string(text(s, notes: false))
        case .array(let values): return .array(values.map { value($0) })
        case .object(let fields):
            if !settings.amount, Set(fields.keys) == ["text", "cents"], case let .number(cents)? = fields["cents"] {
                return .object(["band": .string(Self.band(cents: Int64(cents)))])
            }
            var result: [String: JSONValue] = [:]
            for (key, item) in fields {
                let normalized = key.lowercased()
                if !settings.note, Self.noteKeys.contains(normalized) { continue }
                if !settings.category, Self.categoryKeys.contains(normalized) { result[key] = codes(item); continue }
                if !settings.account, Self.accountKeys.contains(normalized), let name = item.stringValue {
                    result[key] = .string(accountAliases.first { $0.name == name }?.alias ?? "账户"); continue
                }
                result[key] = value(item)
            }
            return .object(result)
        case .null, .bool, .number: return input
        }
    }

    private func codes(_ item: JSONValue) -> JSONValue {
        switch item {
        case .string(let name): return .string(categoryCodes.first { $0.name == name }?.code ?? "分类")
        case .array(let values): return .array(values.map { codes($0) })
        default: return value(item)
        }
    }

    public func text(_ input: String) -> String { text(input, notes: true) }

    /// Inside JSON the note fields are dropped by key, so the ledger-wide note scan
    /// (one pass per distinct note) only runs on free text such as the user's question.
    private func text(_ input: String, notes scanNotes: Bool) -> String {
        var value = input
        if !settings.note, scanNotes {
            for note in notes { value = value.replacingOccurrences(of: note, with: "[备注]") }
        }
        if !settings.account {
            for pair in accountAliases { value = value.replacingOccurrences(of: pair.name, with: pair.alias) }
        }
        if !settings.amount { value = replaceAmounts(in: value) }
        if !settings.category { value = replaceCategories(in: value) }
        return value
    }

    private func replaceCategories(in input: String) -> String {
        var value = input
        for pair in categoryCodes { value = value.replacingOccurrences(of: pair.name, with: pair.code) }
        return value
    }

    /// Only text that reads as money: a ¥ sign, a 元/块 unit, or exactly two decimals.
    /// Dates, counts and ids stay as they are.
    private func replaceAmounts(in input: String) -> String {
        let pattern = #"[¥￥]\s?-?[0-9][0-9,]*(?:\.[0-9]{1,2})?|-?[0-9][0-9,]*(?:\.[0-9]{1,2})?\s?(?:块钱|元|块)|(?<![0-9.\-/:])-?[0-9][0-9,]*\.[0-9]{2}(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        var value = input
        let ns = value as NSString
        for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed() {
            let raw = ns.substring(with: match.range)
            let digits = raw.filter { "0123456789.".contains($0) }
            let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
            let yuan = Int64(parts.first ?? "") ?? 0
            let fraction = parts.count > 1 ? Int64(String(parts[1].prefix(2)).padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0 : 0
            value = (value as NSString).replacingCharacters(in: match.range, with: Self.band(cents: yuan * 100 + fraction))
        }
        return value
    }
}
