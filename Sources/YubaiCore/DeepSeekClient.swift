import Foundation

/// Configuration for optional DeepSeek cloud calls. Keys are read from the process environment only —
/// never log, persist, or embed the API key.
public struct DeepSeekConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var timeout: TimeInterval

    public static let defaultBaseURL = URL(string: "https://api.deepseek.com")!
    /// Prefer a fast chat model; override with `DEEPSEEK_MODEL` when needed.
    /// Current DeepSeek catalog commonly exposes `deepseek-flash` / `deepseek-v4-pro`.
    public static let defaultModel = "deepseek-flash"

    public init(
        apiKey: String,
        baseURL: URL = DeepSeekConfiguration.defaultBaseURL,
        model: String = DeepSeekConfiguration.defaultModel,
        timeout: TimeInterval = 60
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
    }

    /// Reads `DEEPSEEK_API_KEY` (required), optional `DEEPSEEK_BASE_URL` / `DEEPSEEK_MODEL`.
    /// Returns `nil` when the key is missing or blank — callers must degrade gracefully.
    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DeepSeekConfiguration? {
        guard let raw = environment["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let base: URL = {
            if let s = environment["DEEPSEEK_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty,
               let url = URL(string: s)
            {
                return url
            }
            return defaultBaseURL
        }()
        let model: String = {
            if let s = environment["DEEPSEEK_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s
            }
            return defaultModel
        }()
        return DeepSeekConfiguration(apiKey: raw, baseURL: base, model: model)
    }

    /// Redacted description safe for logs / diagnostics (never includes the key).
    public var diagnosticsLabel: String {
        "DeepSeek(\(baseURL.host ?? "?")/\(model))"
    }
}

/// Minimal OpenAI-compatible chat client for DeepSeek. Does not print credentials.
public struct DeepSeekClient: Sendable {
    public var configuration: DeepSeekConfiguration

    public init(configuration: DeepSeekConfiguration) {
        self.configuration = configuration
    }

    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DeepSeekClient? {
        guard let config = DeepSeekConfiguration.fromEnvironment(environment: environment) else { return nil }
        return DeepSeekClient(configuration: config)
    }

    public func chat(
        system: String,
        user: String,
        temperature: Double = 0.2,
        maxTokens: Int = 400,
        session: URLSession = .shared
    ) async throws -> String {
        let endpoint = Self.chatCompletionsURL(baseURL: configuration.baseURL)
        var request = URLRequest(url: endpoint, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        // Avoid opaque compressed / hung chunked bodies on some edge paths.
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let payload: [String: Any] = [
            "model": configuration.model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw YubaiError.invalid("云端请求失败：网络或超时。可稍后重试，或关闭云端增强改用规则 / 本机路径。")
        }

        guard let http = response as? HTTPURLResponse else {
            throw YubaiError.invalid("云端响应异常。")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Never include response bodies that might echo auth headers; keep message generic.
            if http.statusCode == 401 || http.statusCode == 403 {
                throw YubaiError.invalid("云端密钥无效或无权访问。请检查环境变量配置（不会写入账本）。")
            }
            throw YubaiError.invalid("云端服务返回错误（HTTP \(http.statusCode)）。可关闭云端增强继续使用规则路径。")
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw YubaiError.invalid("云端响应无法解析。")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw YubaiError.invalid("云端返回空内容。")
        }
        return trimmed
    }

    /// `DEEPSEEK_BASE_URL` should be the API root (e.g. `https://api.deepseek.com` or `…/v1`), not the full completions path.
    public static func chatCompletionsURL(baseURL: URL) -> URL {
        var root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if root.hasSuffix("/chat/completions") {
            return URL(string: root)!
        }
        return URL(string: root + "/chat/completions")!
    }
}

/// Post-process model text so amounts stay program-owned.
public enum ModelAmountGuard {
    /// True when text appears to invent currency amounts (¥… or x.xx元).
    public static func containsInventedAmount(_ text: String) -> Bool {
        if text.range(of: #"¥\s*\d"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"￥\s*\d"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"\d+\.\d{2}\s*元"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Strip invented amount tokens from free-form advice. Returns nil if nothing usable remains.
    public static func stripInventedAmounts(_ text: String) -> String? {
        var s = text
        s = s.replacingOccurrences(of: #"¥\s*[\d,]+(\.\d{1,2})?"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"￥\s*[\d,]+(\.\d{1,2})?"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\d+\.\d{2}\s*元"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
