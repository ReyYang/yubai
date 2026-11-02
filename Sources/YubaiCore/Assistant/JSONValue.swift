import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(_ key: String) -> JSONValue? { objectValue?[key] }
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public func jsonText() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
    /// Accept JSON wrapped in a Markdown fence or surrounding model commentary.
    public static func parseModelResponse(_ text: String) throws -> JSONValue {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
            if clean.lowercased().hasPrefix("json") { clean = String(clean.dropFirst(4)) }
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.hasSuffix("```") { clean = String(clean.dropLast(3)) }
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do { return try parse(clean) }
        catch {
            guard let first = clean.firstIndex(of: "{"), let last = clean.lastIndex(of: "}"), first < last else { throw error }
            return try parse(String(clean[first...last]))
        }
    }
    static func money(_ cents: Int64) -> JSONValue {
        .object(["text": .string(Money.text(cents)), "cents": .number(Double(cents))])
    }
    static func strings(_ values: [String]) -> JSONValue { .array(values.map { .string($0) }) }
}
