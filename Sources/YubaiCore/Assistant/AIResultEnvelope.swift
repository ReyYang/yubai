import Foundation

/// Stored AI output (approval cards, answers, memories) carries a schema version so a
/// newer app can still read what an older one saved, and an older one skips what it
/// cannot read instead of failing the whole ledger.
public struct AIResultEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    /// Bump when `Payload` changes in a way old readers cannot ignore.
    public var schemaVersion: Int
    public var payload: Payload

    public init(schemaVersion: Int, payload: Payload) {
        self.schemaVersion = schemaVersion; self.payload = payload
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, payload }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Results saved before versioning count as version 1.
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        payload = try c.decode(Payload.self, forKey: .payload)
    }

    /// Nil when the data comes from a newer schema this build does not understand
    /// or cannot be decoded; callers drop that item and keep the rest.
    public static func decodeIfSupported(_ data: Data, upTo supported: Int, decoder: JSONDecoder = JSONDecoder()) -> AIResultEnvelope? {
        guard let envelope = try? decoder.decode(AIResultEnvelope.self, from: data), envelope.schemaVersion <= supported else { return nil }
        return envelope
    }
}
