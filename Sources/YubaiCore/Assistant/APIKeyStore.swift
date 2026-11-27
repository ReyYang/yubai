import Foundation
#if canImport(Security)
import Security
#endif

/// Only this small boundary touches Security; tests can inject a memory implementation.
public protocol APIKeyStorage: Sendable {
    func read() throws -> String?
    func write(_ key: String) throws
    func delete() throws
}

public struct APIKeyStore: Sendable {
    public struct Status: Sendable {
        public let configuration: DeepSeekConfiguration?
        public let hasKeychainKey: Bool
    }
    public static let shared = APIKeyStore()
    private let storage: any APIKeyStorage
    public init(storage: any APIKeyStorage = KeychainAPIKeyStorage()) { self.storage = storage }
    public var isConfigured: Bool { configuration() != nil }
    public var hasKeychainKey: Bool { (try? storage.read())?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    /// Security may perform synchronous IPC. UI callers await a worker and
    /// publish this one-read snapshot instead of reading Keychain in a body.
    public func status(environment: [String: String] = ProcessInfo.processInfo.environment) async -> Status {
        await Task.detached(priority: .utility) {
            let key = (try? storage.read())?.trimmingCharacters(in: .whitespacesAndNewlines)
            var environment = environment
            let hasKey = key?.isEmpty == false
            if hasKey { environment["DEEPSEEK_API_KEY"] = key }
            return Status(configuration: DeepSeekConfiguration.fromEnvironment(environment: environment), hasKeychainKey: hasKey)
        }.value
    }
    public func save(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw YubaiError.invalid("请输入 DeepSeek 密钥。") }
        try storage.write(value)
    }
    public func delete() throws { try storage.delete() }
    public func configuration(environment: [String: String] = ProcessInfo.processInfo.environment,
                              defaults: UserDefaults = .standard) -> DeepSeekConfiguration? {
        if let key = try? storage.read(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Retain environment model / endpoint overrides without using the environment key.
            var values = environment; values["DEEPSEEK_API_KEY"] = key
            return DeepSeekConfiguration.fromEnvironment(environment: values, defaults: defaults)
        }
        return DeepSeekConfiguration.fromEnvironment(environment: environment, defaults: defaults)
    }
}

public struct KeychainAPIKeyStorage: APIKeyStorage {
    public init() {}
    /// The cause the user can act on; the old text blamed the lock for every status.
    public static func failureMessage(_ status: Int32, action: String = "保存") -> String {
        switch status {
        case -25308: return "设备锁定时无法\(action)密钥，解锁后重试。" // errSecInteractionNotAllowed
        case -34018: return "这个安装包没有钥匙串权限，无法\(action)密钥。" // errSecMissingEntitlement
        default: return "钥匙串错误 \(status)，无法\(action)密钥。"
        }
    }
    #if canImport(Security)
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
            throw YubaiError.invalid(Self.failureMessage(status == errSecSuccess ? errSecDecode : status, action: "读取"))
        }
        return key
    }
    public func write(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw YubaiError.invalid(Self.failureMessage(status, action: "删除")) }
    }
    private func failure(_ status: OSStatus) -> YubaiError { .invalid(Self.failureMessage(status)) }
    #else
    // Linux 仅在进程内保存；不同实例共享，不写入文件或 UserDefaults。
    private final class State: @unchecked Sendable {
        let lock = NSLock(); var key: String?
    }
    private static let state = State()
    public func read() throws -> String? {
        Self.state.lock.lock(); defer { Self.state.lock.unlock() }
        return Self.state.key
    }
    public func write(_ key: String) throws {
        Self.state.lock.lock(); defer { Self.state.lock.unlock() }
        Self.state.key = key
    }
    public func delete() throws {
        Self.state.lock.lock(); defer { Self.state.lock.unlock() }
        Self.state.key = nil
    }
    #endif
}
