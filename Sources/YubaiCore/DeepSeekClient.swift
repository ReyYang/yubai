import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for optional DeepSeek cloud calls. Never log or embed credentials.
public struct DeepSeekConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var timeout: TimeInterval

    public static let defaultBaseURL = URL(string: "https://api.deepseek.com")!
    /// Prefer a fast chat model; override with `DEEPSEEK_MODEL` when needed.
    /// Legacy saved names are mapped when reading configuration.
    public static let defaultModel = "deepseek-flash"
    public static let modelPreferenceKey = "DeepSeek.model"

    public static func canonicalModel(_ name: String) -> String {
        switch name {
        case "deepseek-chat", "deepseek-v4-flash": return "deepseek-flash"
        case "deepseek-reasoner": return "deepseek-v4-pro"
        default: return name
        }
    }
    public static func modelName(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 defaults: UserDefaults = .standard) -> String {
        for value in [environment["DEEPSEEK_MODEL"], defaults.string(forKey: modelPreferenceKey)] {
            if let name = value?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return canonicalModel(name) }
        }
        return defaultModel
    }

    public init(
        apiKey: String,
        baseURL: URL = DeepSeekConfiguration.defaultBaseURL,
        model: String = DeepSeekConfiguration.defaultModel,
        timeout: TimeInterval = 60
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = Self.canonicalModel(model)
        self.timeout = timeout
    }

    /// Reads `DEEPSEEK_API_KEY` (required), optional `DEEPSEEK_BASE_URL` / `DEEPSEEK_MODEL`.
    /// Returns `nil` when the key is missing or blank — callers must degrade gracefully.
    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
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
        let model = modelName(environment: environment, defaults: defaults)
        return DeepSeekConfiguration(apiKey: raw, baseURL: base, model: model)
    }

    public func model(for request: ChatRequest) -> String {
        request.model.map(Self.canonicalModel) ?? model
    }

    /// Redacted description safe for logs / diagnostics (never includes the key).
    public var diagnosticsLabel: String {
        "DeepSeek(\(baseURL.host ?? "?")/\(model))"
    }
}

public enum DeepSeekError: Error, LocalizedError, Equatable, Sendable {
    case modelUnavailable(String)
    case network
    case http(Int)
    case invalidResponse
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let model): return "模型「\(model)」现在用不了。请到智能与隐私换一个模型名字再试。"
        case .network: return "云端请求失败：网络或超时。本机计算结果已保留，可稍后重试。"
        case .http(let status): return "DeepSeek 返回错误（HTTP \(status)）。"
        case .invalidResponse: return "云端响应无法解析。"
        }
    }
    static func modelError(status: Int, body: Data, model: String) -> DeepSeekError? {
        let text = String(decoding: body, as: UTF8.self).lowercased()
        if text.contains("model_not_found") || ([400, 404].contains(status) && text.contains("model")) {
            return .modelUnavailable(model)
        }
        return nil
    }
}

/// Minimal OpenAI-compatible chat client for DeepSeek. Does not print credentials.
public struct DeepSeekClient: ChatTransport {
    public static let fallbackModels = ["deepseek-flash", "deepseek-v4-pro"]
    public var configuration: DeepSeekConfiguration
    private let redactor: Redactor
    private let sendLog: SendLog

    public init(configuration: DeepSeekConfiguration, redactor: Redactor = .shared, sendLog: SendLog = .shared) {
        self.configuration = configuration; self.redactor = redactor; self.sendLog = sendLog
    }

    public static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DeepSeekClient? {
        guard let config = DeepSeekConfiguration.fromEnvironment(environment: environment) else { return nil }
        return DeepSeekClient(configuration: config)
    }

    public static func configured(keyStore: APIKeyStore = .shared,
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  redactor: Redactor = .shared) -> DeepSeekClient? {
        guard let config = keyStore.configuration(environment: environment) else { return nil }
        return DeepSeekClient(configuration: config, redactor: redactor)
    }

    public func chat(system: String, user: String, temperature: Double = 0.2, maxTokens: Int = 400,
                     thinking: Bool? = nil, purpose: String = "云端智能", session: URLSession = .shared) async throws -> String {
        let reply = try await send(ChatRequest(messages: [ChatMessage(role: .system, content: system),
            ChatMessage(role: .user, content: user)], temperature: temperature, maxTokens: maxTokens,
            thinking: thinking, purpose: purpose), session: session)
        guard let text = reply.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw YubaiError.invalid("云端返回空内容。")
        }
        return text
    }

    public func send(_ request: ChatRequest) async throws -> ChatMessage {
        try await send(request, session: .shared)
    }

    public func listModels(session: URLSession = .shared) async throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { var id: String }
            var data: [Model]
        }
        let root = Self.chatCompletionsURL(baseURL: configuration.baseURL).deletingLastPathComponent().deletingLastPathComponent()
        var request = URLRequest(url: root.appendingPathComponent("models"), timeoutInterval: configuration.timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try Task.checkCancellation()
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw YubaiError.invalid("暂时取不到模型列表。")
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let result = try? JSONDecoder().decode(Response.self, from: data) else {
            throw YubaiError.invalid("暂时取不到模型列表。")
        }
        var seen: Set<String> = []
        let models = result.data.compactMap { model -> String? in
            let id = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, id.count <= 200, !id.contains(where: { $0.isNewline }), seen.insert(id).inserted else { return nil }
            return id
        }
        guard !models.isEmpty else { throw YubaiError.invalid("暂时取不到模型列表。") }
        return models
    }

    public func send(_ input: ChatRequest, session: URLSession) async throws -> ChatMessage {
        struct Payload: Encodable {
            var model: String; var messages: [ChatMessage]; var tools: [ChatToolDefinition]?
            var temperature: Double; var max_tokens: Int; var response_format: JSONValue?
            var thinking: [String: String]?
        }
        var messages = input.messages
        for i in messages.indices {
            if let content = messages[i].content { messages[i].content = redactor.content(content) }
            if var calls = messages[i].toolCalls {
                for j in calls.indices { calls[j].function.arguments = redactor.content(calls[j].function.arguments) }
                messages[i].toolCalls = calls
            }
        }
        var definitions = input.tools
        for i in definitions.indices {
            definitions[i].function.description = redactor.text(definitions[i].function.description)
            definitions[i].function.parameters = redactor.value(definitions[i].function.parameters)
        }
        let model = configuration.model(for: input)
        let organizing = input.purpose == "导入整理" || input.purpose == "导入整理·按对方"
        let payload = Payload(model: model, messages: messages,
            tools: definitions.isEmpty ? nil : definitions, temperature: input.temperature, max_tokens: input.maxTokens, response_format: input.responseFormat,
            thinking: input.thinking.map { ["type": $0 ? "enabled" : "disabled"] })
        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: Self.chatCompletionsURL(baseURL: configuration.baseURL), timeoutInterval: input.timeout ?? configuration.timeout)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        try Task.checkCancellation()
        let logID = sendLog.record(purpose: redactor.text(input.purpose), model: model, body: body, apiKey: configuration.apiKey,
            groupID: input.groupID ?? UUID(), groupTitle: redactor.text(input.groupTitle ?? input.purpose))
        let started = DispatchTime.now().uptimeNanoseconds
        var loggedResponse = SendLogResponse(durationMilliseconds: 0)
        defer {
            loggedResponse.durationMilliseconds = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            sendLog.complete(id: logID, response: loggedResponse, apiKey: configuration.apiKey)
        }
        do {
            let data: Data; let response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch {
                if Task.isCancelled { throw CancellationError() }
                throw DeepSeekError.network
            }
            guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
            loggedResponse.httpStatus = http.statusCode
            guard (200..<300).contains(http.statusCode) else {
                // Error bodies may echo credentials. Never retain or expose them.
                if organizing { throw DeepSeekError.http(http.statusCode) }
                if let error = DeepSeekError.modelError(status: http.statusCode, body: data, model: model) { throw error }
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw YubaiError.invalid("云端密钥无效或无权访问，请检查密钥设置。")
                }
                throw YubaiError.invalid("云端服务返回错误（HTTP \(http.statusCode)）。本机计算结果已保留。")
            }
            struct Response: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { var content: String?; var tool_calls: [ChatToolCall]?; var reasoning_content: String? }
                    var message: Message
                    var finish_reason: String?
                }
                var choices: [Choice]
            }
            guard let result = try? JSONDecoder().decode(Response.self, from: data), let choice = result.choices.first else {
                throw DeepSeekError.invalidResponse
            }
            let message = choice.message
            loggedResponse.content = message.content
            loggedResponse.toolCalls = message.tool_calls?.map { $0.function.name } ?? []
            loggedResponse.finishReason = choice.finish_reason
            let hasContent = !(message.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasTools = !(message.tool_calls?.isEmpty ?? true)
            guard hasContent || hasTools else {
                if organizing { throw DeepSeekError.invalidResponse }
                if choice.finish_reason == "length" { throw YubaiError.invalid("云端回复被截断。请重试或调整模型输出空间。") }
                if !(message.reasoning_content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    throw YubaiError.invalid("云端只返回了推理内容，没有返回正文。请重试或更换模型。")
                }
                throw YubaiError.invalid("云端返回空内容。")
            }
            return ChatMessage(role: .assistant, content: message.content, toolCalls: message.tool_calls)
        } catch {
            loggedResponse.errorDescription = error is CancellationError ? "请求已取消。" : error.localizedDescription
            throw error
        }
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
