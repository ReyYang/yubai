import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Bounded retries for import organization only. Header values never enter logs.
public enum DeepSeekRetryPolicy {
    public static let delays: [TimeInterval] = [1, 3, 8, 20]
    public static let maximumWait: TimeInterval = 30
    public static func retries(status: Int) -> Bool { [429, 500, 502, 503, 504].contains(status) }
    public static func retries(network error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
    }
    public static func retryAfter(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let seconds = Double(header), seconds.isFinite, seconds >= 0 { return min(maximumWait, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: header) else { return nil }
        return min(maximumWait, max(0, date.timeIntervalSince(now)))
    }
    /// retry starts at 1; jitter in 0...1 gives ±20% without exceeding the cap.
    public static func delay(retry: Int, header: String? = nil, now: Date = Date(), jitter: Double) -> TimeInterval {
        if let seconds = retryAfter(header, now: now) { return seconds }
        let base = delays[min(max(0, retry - 1), delays.count - 1)]
        return min(maximumWait, base * (0.8 + 0.4 * min(1, max(0, jitter))))
    }
}

/// Shared by both phases (and all batches) in one explicit organization run.
/// Existing HTTP attempts finish when congestion is detected; new attempts wait.
public actor ImportRequestController {
    public let models = ImportModelRouting()
    private var capacity = ImportOrganizer.partyConcurrency
    private var consecutiveSuccesses = 0
    private var active = 0
    private struct Waiter {
        var id: UUID; var ceiling: Int; var continuation: CheckedContinuation<Void, Error>
    }
    private var waiters: [Waiter] = []
    public init() {}
    public func limit(ceiling: Int) -> Int { min(capacity, ceiling) }
    public func congested(status: Int) {
        guard status == 429 || status == 503 else { return }
        capacity = 1; consecutiveSuccesses = 0
    }
    public func failed() { consecutiveSuccesses = 0 }
    public func succeeded() {
        consecutiveSuccesses += 1
        if consecutiveSuccesses >= 3 {
            capacity = min(ImportOrganizer.partyConcurrency, capacity + 1); consecutiveSuccesses = 0
            drain()
        }
    }
    public func acquire(ceiling: Int) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if active < limit(ceiling: ceiling), waiters.isEmpty {
                    active += 1; continuation.resume()
                } else { waiters.append(Waiter(id: id, ceiling: ceiling, continuation: continuation)); drain() }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    public func release() { active -= 1; drain() }
    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        drain()
    }
    private func drain() {
        while let first = waiters.first, active < limit(ceiling: first.ceiling) {
            active += 1; waiters.removeFirst().continuation.resume()
        }
    }
}

/// Per-run fallback. Concurrent requests re-read it before each HTTP attempt.
public actor ImportModelRouting {
    private var fallback: String?
    private var requests = 0
    public init() {}
    func begin(preferred: String) -> (model: String, first: Bool) {
        requests += 1; return (fallback ?? preferred, requests == 1)
    }
    func current(preferred: String) -> String { fallback ?? preferred }
    func recovered(using model: String) { fallback = model }
}

/// In-memory, credential/endpoint-scoped catalog, shared across ephemeral clients.
/// Coalesces concurrent lookups; failed lookups are cached briefly as well.
public actor DeepSeekModelCatalog {
    public static let shared = DeepSeekModelCatalog()
    private struct Key: Hashable { let endpoint: URL; let credential: String }
    private struct Cached { var names: [String]?; var expires: Date }
    private var cache: [Key: Cached] = [:]
    private var pending: [Key: Task<[String], Error>] = [:]
    public init() {}
    private func key(_ configuration: DeepSeekConfiguration) -> Key {
        Key(endpoint: DeepSeekClient.chatCompletionsURL(baseURL: configuration.baseURL), credential: configuration.apiKey)
    }
    func cached(for configuration: DeepSeekConfiguration) -> [String]? {
        guard let value = cache[key(configuration)], value.expires > Date() else { return nil }
        return value.names
    }
    func store(_ names: [String], for configuration: DeepSeekConfiguration) {
        cache[key(configuration)] = Cached(names: names, expires: Date().addingTimeInterval(300))
    }
    func models(for configuration: DeepSeekConfiguration,
                fetch: @escaping @Sendable () async throws -> [String]) async throws -> [String]? {
        try Task.checkCancellation()
        let key = key(configuration)
        if let value = cache[key], value.expires > Date() { return value.names }
        let task: Task<[String], Error>
        if let existing = pending[key] { task = existing }
        else { task = Task { try await fetch() }; pending[key] = task }
        do {
            let names = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            cache[key] = Cached(names: names, expires: Date().addingTimeInterval(300)); pending[key] = nil
            return names
        } catch {
            pending[key] = nil
            if Task.isCancelled { throw CancellationError() }
            cache[key] = Cached(names: nil, expires: Date().addingTimeInterval(30))
            return nil
        }
    }
}

enum ImportRequestScope {
    struct Context: Sendable { var controller: ImportRequestController; var ceiling: Int }
    @TaskLocal static var current: Context?
}

/// Configuration for optional DeepSeek cloud calls. Never log or embed credentials.
public struct DeepSeekConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String
    public var timeout: TimeInterval

    public static let defaultBaseURL = URL(string: "https://api.deepseek.com")!
    /// Used only when no model has been selected. Organization discovers its
    /// preferred model from the authenticated catalog instead.
    public static let defaultModel = "deepseek-flash"
    public static let modelPreferenceKey = "DeepSeek.model"

    public static func canonicalModel(_ name: String, availableModels: [String]? = nil) -> String {
        guard let availableModels, !availableModels.contains(name) else { return name }
        let candidates: [String]
        switch name {
        case "deepseek-chat": candidates = ["deepseek-v4-flash", "deepseek-flash"]
        case "deepseek-flash": candidates = ["deepseek-v4-flash", "deepseek-chat"]
        case "deepseek-v4-flash": candidates = ["deepseek-flash", "deepseek-chat"]
        case "deepseek-reasoner": candidates = ["deepseek-v4-pro"]
        case "deepseek-v4-pro": candidates = ["deepseek-reasoner"]
        default: candidates = []
        }
        return candidates.first(where: availableModels.contains) ?? name
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

    public func model(for request: ChatRequest, availableModels: [String]? = nil) -> String {
        request.model ?? Self.canonicalModel(model, availableModels: availableModels)
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
        if text.contains("model_not_found") || ([400, 404, 503].contains(status) && (text.contains("model") || text.contains("模型"))) {
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
    private let retrySleep: @Sendable (TimeInterval) async throws -> Void
    private let retryJitter: @Sendable () -> Double
    private let modelCatalog: DeepSeekModelCatalog

    public init(configuration: DeepSeekConfiguration, redactor: Redactor = .shared, sendLog: SendLog = .shared,
                retrySleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }, retryJitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
                modelCatalog: DeepSeekModelCatalog = .shared) {
        self.configuration = configuration; self.redactor = redactor; self.sendLog = sendLog
        self.retrySleep = retrySleep; self.retryJitter = retryJitter
        self.modelCatalog = modelCatalog
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

    public func listModels(session: URLSession = .shared, timeout: TimeInterval? = nil) async throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { var id: String }
            var data: [Model]
        }
        let root = Self.chatCompletionsURL(baseURL: configuration.baseURL).deletingLastPathComponent().deletingLastPathComponent()
        var request = URLRequest(url: root.appendingPathComponent("models"), timeoutInterval: timeout ?? configuration.timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try Task.checkCancellation()
        let data: Data; let response: URLResponse
        do { (data, response) = try await Self.attemptData(for: request, session: session) }
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
        await modelCatalog.store(models, for: configuration)
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
        let organizing = input.purpose == "导入整理" || input.purpose == "导入整理·按对方" || ImportRequestScope.current != nil
        let names: [String]?
        if organizing {
            names = try await modelCatalog.models(for: configuration) {
                try await self.listModels(session: session, timeout: min(5, configuration.timeout))
            }
        } else { names = await modelCatalog.cached(for: configuration) }
        let selectedModel = DeepSeekConfiguration.canonicalModel(configuration.model, availableModels: names)
        let preferred = organizing ? names?.first(where: { $0.localizedCaseInsensitiveContains("flash") }) ?? selectedModel
            : configuration.model(for: input, availableModels: names)
        let routing = ImportRequestScope.current?.controller.models ?? ImportModelRouting()
        let initial = organizing ? await routing.begin(preferred: preferred) : (model: preferred, first: false)
        var model = initial.model
        var payload = Payload(model: model, messages: messages,
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
            var number = 0, retry = 0
            var fallbackTried = false
            while true {
                try Task.checkCancellation()
                number += 1
                model = fallbackTried ? selectedModel : await routing.current(preferred: preferred)
                payload.model = model
                let attemptBody = try JSONEncoder().encode(payload)
                request.httpBody = attemptBody
                loggedResponse = SendLogResponse(durationMilliseconds: 0)
                var retryable = false, fallbackAllowed = false
                var retryHeader: String?
                let attemptStarted = DispatchTime.now().uptimeNanoseconds
                sendLog.attempt(id: logID, number: number, model: model,
                    body: model == initial.model ? nil : attemptBody, apiKey: configuration.apiKey)
                do {
                    let data: Data; let response: URLResponse
                    do {
                        let scope = ImportRequestScope.current
                        if let scope { try await scope.controller.acquire(ceiling: scope.ceiling) }
                        do {
                            try Task.checkCancellation()
                            (data, response) = try await Self.attemptData(for: request, session: session)
                            if let http = response as? HTTPURLResponse {
                                await scope?.controller.congested(status: http.statusCode)
                            }
                            await scope?.controller.release()
                        } catch {
                            await scope?.controller.release()
                            throw error
                        }
                    } catch {
                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                        retryable = DeepSeekRetryPolicy.retries(network: error)
                        throw DeepSeekError.network
                    }
                    try Task.checkCancellation()
                    guard let http = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
                    loggedResponse.httpStatus = http.statusCode
                    guard (200..<300).contains(http.statusCode) else {
                        // Error bodies may echo credentials. Never retain or expose them.
                        retryable = DeepSeekRetryPolicy.retries(status: http.statusCode)
                        fallbackAllowed = [400, 404, 503].contains(http.statusCode) &&
                            (Self.isModelFailure(status: http.statusCode, body: data, model: model) || (initial.first && number == 1))
                        retryHeader = http.value(forHTTPHeaderField: "Retry-After")
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
                    loggedResponse.durationMilliseconds = Int((DispatchTime.now().uptimeNanoseconds - attemptStarted) / 1_000_000)
                    sendLog.attempt(id: logID, number: number, response: loggedResponse, model: model,
                        body: model == initial.model ? nil : attemptBody, apiKey: configuration.apiKey)
                    if fallbackTried { await routing.recovered(using: selectedModel) }
                    return ChatMessage(role: .assistant, content: message.content, toolCalls: message.tool_calls)
                } catch {
                    await ImportRequestScope.current?.controller.failed()
                    loggedResponse.durationMilliseconds = Int((DispatchTime.now().uptimeNanoseconds - attemptStarted) / 1_000_000)
                    loggedResponse.errorDescription = error is CancellationError ? "请求已取消。" : error.localizedDescription
                    let fallback = organizing && fallbackAllowed && !fallbackTried && model != selectedModel && !Task.isCancelled
                    let delay = !fallback && organizing && retryable && retry < DeepSeekRetryPolicy.delays.count && !Task.isCancelled
                        ? DeepSeekRetryPolicy.delay(retry: retry + 1, header: retryHeader, jitter: retryJitter()) : nil
                    sendLog.attempt(id: logID, number: number, response: loggedResponse, retryDelay: delay, model: model,
                        body: model == initial.model ? nil : attemptBody, apiKey: configuration.apiKey)
                    if fallback { fallbackTried = true; continue }
                    guard let delay else { throw error }
                    retry += 1
                    try await retrySleep(delay)
                    try Task.checkCancellation()
                }
            }
        } catch {
            loggedResponse.errorDescription = error is CancellationError ? "请求已取消。" : error.localizedDescription
            throw error
        }
    }

    private static func isModelFailure(status: Int, body: Data, model: String) -> Bool {
        DeepSeekError.modelError(status: status, body: body, model: model) != nil
    }

    /// A wall-clock bound as well as URLSession's inactivity timeout.
    private static func attemptData(for request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await session.data(for: request) }
            group.addTask {
                try await Task.sleep(for: .seconds(request.timeoutInterval))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
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
