import Foundation

/// What a model can do. The router picks by capability, never by vendor name, so a
/// new model (an on-device one later) only needs a provider that declares these.
public struct ModelCapabilities: Equatable, Sendable {
    public var contextTokens: Int
    public var toolCalling: Bool
    public var structuredOutput: Bool
    public var imageInput: Bool
    /// True when the request leaves the phone; the cloud share policy then applies.
    public var leavesDevice: Bool
    public init(contextTokens: Int, toolCalling: Bool, structuredOutput: Bool, imageInput: Bool, leavesDevice: Bool) {
        self.contextTokens = contextTokens; self.toolCalling = toolCalling; self.structuredOutput = structuredOutput
        self.imageInput = imageInput; self.leavesDevice = leavesDevice
    }
}

/// What one request needs from a model.
public struct ModelRequirements: Equatable, Sendable {
    public var contextTokens: Int
    public var toolCalling: Bool
    public var structuredOutput: Bool
    public var imageInput: Bool
    public init(contextTokens: Int = 0, toolCalling: Bool = false, structuredOutput: Bool = false, imageInput: Bool = false) {
        self.contextTokens = contextTokens; self.toolCalling = toolCalling
        self.structuredOutput = structuredOutput; self.imageInput = imageInput
    }

    /// Rough size: one token per two characters of Chinese-heavy text, plus the reply budget.
    public static func estimate(for request: ChatRequest) -> ModelRequirements {
        var characters = 0
        for message in request.messages {
            characters += message.content?.count ?? 0
            for call in message.toolCalls ?? [] { characters += call.function.arguments.count }
        }
        for tool in request.tools {
            characters += tool.function.description.count
            characters += (try? tool.function.parameters.jsonText())?.count ?? 0
        }
        return ModelRequirements(contextTokens: characters / 2 + request.maxTokens, toolCalling: !request.tools.isEmpty,
                                 structuredOutput: request.responseFormat != nil)
    }

    public func isMet(by capabilities: ModelCapabilities) -> Bool {
        capabilities.contextTokens >= contextTokens
            && (!toolCalling || capabilities.toolCalling)
            && (!structuredOutput || capabilities.structuredOutput)
            && (!imageInput || capabilities.imageInput)
    }
}

public enum ModelUnavailableReason: String, Codable, Equatable, Sendable {
    /// The user has not turned cloud AI on.
    case cloudOff
    /// Cloud AI is on but no API key is saved.
    case missingKey
    /// The system or device cannot run this model.
    case unsupportedSystem
    /// The model exists but is not ready yet, e.g. still downloading.
    case notReady
    /// No available model meets the request's needs.
    case insufficientCapability
}

public enum ModelAvailability: Equatable, Sendable {
    case available
    case unavailable(ModelUnavailableReason)
}

/// One model behind the router. Conforming types wrap a concrete backend; the shape
/// follows Foundation Models' `LanguageModel` so an iOS 27 adapter can sit beside it.
public protocol LanguageModelProvider: ChatTransport {
    var id: String { get }
    var capabilities: ModelCapabilities { get }
    func availability() async -> ModelAvailability
}

/// DeepSeek through the existing client. Nil backend means cloud AI is off or has no key.
public struct DeepSeekProvider: LanguageModelProvider {
    public static let defaultCapabilities = ModelCapabilities(contextTokens: 128_000, toolCalling: true,
                                                              structuredOutput: true, imageInput: false, leavesDevice: true)
    public let id = "deepseek"
    public let capabilities: ModelCapabilities
    private let transport: (any ChatTransport)?
    private let unavailableReason: ModelUnavailableReason

    public init(transport: (any ChatTransport)?, unavailableReason: ModelUnavailableReason = .missingKey,
                capabilities: ModelCapabilities = DeepSeekProvider.defaultCapabilities) {
        self.transport = transport; self.unavailableReason = unavailableReason; self.capabilities = capabilities
    }

    /// The reason the app shows when this feature has no model, without touching the keychain.
    public static func status(preferences: Preferences, feature: AIFeature, keyConfigured: Bool) -> ModelAvailability {
        guard preferences.isAIEnabled(for: feature) else { return .unavailable(.cloudOff) }
        return keyConfigured ? .available : .unavailable(.missingKey)
    }

    public static func configured(preferences: Preferences, feature: AIFeature, keyStore: APIKeyStore = .shared,
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  redactor: Redactor = .shared) -> DeepSeekProvider {
        guard preferences.isAIEnabled(for: feature) else { return DeepSeekProvider(transport: nil, unavailableReason: .cloudOff) }
        let backend = CloudBackend.configured(enabled: true, keyStore: keyStore, environment: environment, redactor: redactor)
        return DeepSeekProvider(transport: backend, unavailableReason: .missingKey)
    }

    public func availability() async -> ModelAvailability {
        transport == nil ? .unavailable(unavailableReason) : .available
    }

    public func send(_ request: ChatRequest) async throws -> ChatMessage {
        guard let transport else { throw ModelRouterError.noModel([unavailableReason]) }
        return try await transport.send(request)
    }
}

public enum ModelRouterError: LocalizedError, Equatable {
    /// Every provider was unavailable; the reasons come in provider order.
    case noModel([ModelUnavailableReason])
    public var errorDescription: String? { "AI 未连接" }
    public var reasons: [ModelUnavailableReason] { if case let .noModel(reasons) = self { return reasons }; return [] }
}

/// Picks the first available provider whose capabilities meet the request, applies
/// the cloud share policy to anything that leaves the phone, and falls through to the
/// next eligible provider when one fails. With no provider left, callers show only
/// what code computed (the "AI 未连接" state).
public struct ModelRouter: ChatTransport {
    public let providers: [any LanguageModelProvider]
    public let sharePolicy: CloudSharePolicy

    public init(providers: [any LanguageModelProvider], sharePolicy: CloudSharePolicy = CloudSharePolicy()) {
        self.providers = providers; self.sharePolicy = sharePolicy
    }

    /// This batch has one provider. An on-device provider goes first in this list once it ships.
    public static func configured(preferences: Preferences, feature: AIFeature, ledger: Ledger? = nil,
                                  keyStore: APIKeyStore = .shared,
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  redactor: Redactor = .shared) -> ModelRouter {
        ModelRouter(providers: [DeepSeekProvider.configured(preferences: preferences, feature: feature, keyStore: keyStore,
                                                            environment: environment, redactor: redactor)],
                    sharePolicy: CloudSharePolicy(settings: preferences.cloudShareSettings, ledger: ledger))
    }

    /// Same policy and order with a backend the caller already built (the app's
    /// per-request DeepSeek client). Nil means cloud AI is off or has no key.
    public static func configured(preferences: Preferences, feature: AIFeature, ledger: Ledger?,
                                  transport: (any ChatTransport)?) -> ModelRouter {
        let reason: ModelUnavailableReason = preferences.isAIEnabled(for: feature) ? .missingKey : .cloudOff
        return ModelRouter(providers: [DeepSeekProvider(transport: preferences.isAIEnabled(for: feature) ? transport : nil, unavailableReason: reason)],
                           sharePolicy: CloudSharePolicy(settings: preferences.cloudShareSettings, ledger: ledger))
    }

    /// The providers that could take this request right now, best first.
    public func candidates(for requirements: ModelRequirements) async -> (eligible: [any LanguageModelProvider], reasons: [ModelUnavailableReason]) {
        var eligible: [any LanguageModelProvider] = [], reasons: [ModelUnavailableReason] = []
        for provider in providers {
            switch await provider.availability() {
            case .unavailable(let reason): reasons.append(reason)
            case .available:
                if requirements.isMet(by: provider.capabilities) { eligible.append(provider) }
                else { reasons.append(.insufficientCapability) }
            }
        }
        return (eligible, reasons)
    }

    public func availability(for requirements: ModelRequirements = ModelRequirements()) async -> ModelAvailability {
        let found = await candidates(for: requirements)
        return found.eligible.isEmpty ? .unavailable(found.reasons.first ?? .cloudOff) : .available
    }

    public func send(_ request: ChatRequest) async throws -> ChatMessage {
        let found = await candidates(for: .estimate(for: request))
        guard !found.eligible.isEmpty else { throw ModelRouterError.noModel(found.reasons) }
        var lastError: Error?
        for provider in found.eligible {
            try Task.checkCancellation()
            do {
                return try await provider.send(provider.capabilities.leavesDevice ? sharePolicy.apply(to: request) : request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ModelRouterError.noModel(found.reasons)
    }
}
