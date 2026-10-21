import Foundation

/// Outbound allowlists live in the tools. This is a second pass for free text and JSON.
/// Narrow name heuristics use transfer prefixes or common social phrases and surnames.
/// Merchant words are excluded; arbitrary free-form names are not inferred to be people.
public final class Redactor: @unchecked Sendable {
    private final class Aliases: @unchecked Sendable {
        let lock = NSLock()
        let salt = UUID().uuidString
        var names: [Int: String] = [:]
        func alias(_ name: String) -> String {
            lock.lock(); defer { lock.unlock() }
            var hash = Hasher(); hash.combine(salt); hash.combine(name)
            let key = hash.finalize()
            if let existing = names[key] { return existing }
            var index = names.count; var letters = ""
            repeat {
                letters = String(UnicodeScalar(65 + index % 26)!) + letters
                index = index / 26 - 1
            } while index >= 0
            let value = "联系人" + letters; names[key] = value; return value
        }
    }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var ledgers: [UUID: Aliases] = [:]
        func aliases(for id: UUID) -> Aliases {
            lock.lock(); defer { lock.unlock() }
            if let value = ledgers[id] { return value }
            let value = Aliases(); ledgers[id] = value; return value
        }
    }
    private static let registry = Registry()
    public static let shared = Redactor()
    private let aliases: Aliases
    private let secrets: Set<String>
    public init(ledger: Ledger? = nil) {
        aliases = ledger.map { Self.registry.aliases(for: $0.id) } ?? Aliases()
        let entries = ledger?.entries ?? []
        secrets = Set(entries.flatMap { [$0.externalID, $0.sourceIdentity, $0.fingerprint] }.filter { !$0.isEmpty })
        // Register in ledger order, so query order does not change a person's alias.
        if let ledger {
            for entry in ledger.entries { _ = text(entry.title); _ = text(entry.note) }
        }
    }

    public func text(_ input: String) -> String {
        var value = input
        if secrets.contains(value) { return "[已隐藏]" }
        // Match whole identifier tokens in O(text length), rather than scanning the
        // entire ledger's identifiers for each title. Dates and money stay intact.
        if !secrets.isEmpty, let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_]+(?:[.\-:/@|][A-Za-z0-9_]+)*"#) {
            let ns = value as NSString
            for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed() {
                if secrets.contains(ns.substring(with: match.range)) {
                    value = (value as NSString).replacingCharacters(in: match.range, with: "[已隐藏]")
                }
            }
        }
        let patterns = [
            #"(?:微信转账|支付宝转账|转账给|红包|转账)[\s\-—:：]*([\p{Han}]{2,4})(?=$|[\s，。；、,:：;\-\"}])"#,
            #"(?:和|跟|给|请|与|陪)\s*([\p{Han}]{2,3}?)(?=吃饭|聚餐|合租|买|一起|的|[，。\s]|$)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = value as NSString
            for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed() {
                let name = ns.substring(with: match.range(at: 1))
                let surnames = "赵钱孙李周吴郑王冯陈褚卫蒋沈韩杨朱秦许何吕施张孔曹严华金魏陶姜谢邹苏潘葛范彭鲁韦马苗方任袁柳唐罗薛伍余米姚孟顾尹江钟廖赖邓黄梁宋徐高林刘郭曾萧程董叶杜卢丁汪田蔡胡谭陆于戴夏邱石白熊侯邵毛龙万贺龚文欧阳司马上官诸葛"
                let merchant = ["咖啡", "外卖", "公司", "商店", "超市", "酒店", "餐厅", "商户", "银行", "王者", "荣耀", "周末", "周一", "周二", "周三", "周四", "周五", "周六", "周日"].contains { name.contains($0) }
                if let first = name.first, surnames.contains(first), !merchant {
                    value = (value as NSString).replacingCharacters(in: match.range(at: 1), with: aliases.alias(name))
                }
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"[0-9]{8,}"#) {
            let ns = value as NSString
            for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).reversed() {
                let digits = ns.substring(with: match.range)
                value = (value as NSString).replacingCharacters(in: match.range, with: "****" + String(digits.suffix(4)))
            }
        }
        return value
    }

    /// Counts the actual placeholders used by this redactor. Long numbers may be
    /// cards, phone numbers or orders, so the summary does not claim a finer type.
    public static func placeholderSummary(in contents: [String]) -> [String: Int] {
        let patterns = ["联系人": #"联系人[A-Z]+"#, "长号码": #"\*{4}[0-9]{4}"#, "标识符": #"\[已隐藏\]"#]
        var counts: [String: Int] = [:]
        for (kind, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let count = contents.reduce(0) { total, text in
                total + regex.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            }
            if count > 0 { counts[kind] = count }
        }
        return counts
    }

    /// Parse structured content before masking so money cents and local evidence UUIDs survive.
    public func content(_ input: String) -> String {
        if let json = try? JSONValue.parse(input), let clean = try? value(json).jsonText() { return clean }
        return text(input)
    }
    public func value(_ input: JSONValue) -> JSONValue {
        switch input {
        case .string(let s): return UUID(uuidString: s) != nil && !secrets.contains(s) ? input : .string(text(s))
        case .array(let values): return .array(values.map { value($0) })
        case .object(let fields):
            let blocked = Set(["externalid", "sourceidentity", "fingerprint", "attachment", "attachments", "attachmentid", "rawfile", "rawfiles"])
            var result: [String: JSONValue] = [:]
            for (key, item) in fields {
                let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
                guard !blocked.contains(normalized) else { continue }
                if key == "entry_ids", let ids = item.arrayValue {
                    result[key] = .array(ids.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }.map { .string($0.uuidString) })
                } else if key == "id", let s = item.stringValue, UUID(uuidString: s) != nil {
                    result[key] = item
                } else { result[key] = value(item) }
            }
            return .object(result)
        case .null, .bool, .number: return input
        }
    }
}
