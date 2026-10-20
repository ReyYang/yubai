import Foundation
import Security

/// Only this small boundary touches Security; tests can inject a memory implementation.
public protocol APIKeyStorage: Sendable {
    func read() throws -> String?
    func write(_ key: String) throws
    func delete() throws
}

public struct APIKeyStore: Sendable {
    public static let shared = APIKeyStore()
    private let storage: any APIKeyStorage
    public init(storage: any APIKeyStorage = KeychainAPIKeyStorage()) { self.storage = storage }
    public var isConfigured: Bool { configuration() != nil }
    public func save(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw YubaiError.invalid("请输入 DeepSeek 密钥。") }
        try storage.write(value)
    }
    public func delete() throws { try storage.delete() }
    public func configuration(environment: [String: String] = ProcessInfo.processInfo.environment) -> DeepSeekConfiguration? {
        if let key = try? storage.read(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Retain environment model / endpoint overrides without using the environment key.
            var values = environment; values["DEEPSEEK_API_KEY"] = key
            return DeepSeekConfiguration.fromEnvironment(environment: values)
        }
        return DeepSeekConfiguration.fromEnvironment(environment: environment)
    }
}

public struct KeychainAPIKeyStorage: APIKeyStorage {
    public init() {}
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.yubai.deepseek", kSecAttrAccount as String: "api-key"]
    }
    public func read() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else {
            throw YubaiError.invalid("暂时无法读取钥匙串中的密钥。")
        }
        return key
    }
    public func write(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw failure() }
        } else if status != errSecSuccess { throw failure() }
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure() }
    }
    private func failure() -> YubaiError { .invalid("无法更新钥匙串中的密钥，请解锁设备后重试。") }
}
