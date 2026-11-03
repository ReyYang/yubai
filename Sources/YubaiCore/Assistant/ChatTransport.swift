import Foundation

public struct ChatToolCall: Codable, Equatable, Sendable {
    public struct Function: Codable, Equatable, Sendable {
        public var name: String
        /// Kept as text so malformed model JSON can become a readable tool error.
        public var arguments: String
    }
    public var id: String
    public var type = "function"
    public var function: Function
    public init(id: String, name: String, arguments: String = "{}") {
        self.id = id; self.function = Function(name: name, arguments: arguments)
    }
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case system, user, assistant, tool }
    public var role: Role
    public var content: String?
    public var toolCalls: [ChatToolCall]?
    public var toolCallID: String?
    public init(role: Role, content: String? = nil, toolCalls: [ChatToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role; self.content = content; self.toolCalls = toolCalls; self.toolCallID = toolCallID
    }
    private enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls", toolCallID = "tool_call_id"
    }
}

public struct ChatToolDefinition: Codable, Equatable, Sendable {
    public struct Function: Codable, Equatable, Sendable {
        public var name: String
        public var description: String
        public var parameters: JSONValue
    }
    public var type = "function"
    public var function: Function
    public init(name: String, description: String, parameters: JSONValue) {
        function = Function(name: name, description: description, parameters: parameters)
    }
}

public struct ChatRequest: Sendable {
    public var messages: [ChatMessage]
    public var tools: [ChatToolDefinition]
    public var temperature: Double
    public var maxTokens: Int
    public var thinking: Bool?
    public var purpose: String
    public var responseFormat: JSONValue?
    /// Local log metadata only; never encoded into the HTTP payload.
    public var groupID: UUID?
    public var groupTitle: String?
    public var timeout: TimeInterval?
    /// Applies to this request only; never changes the saved model preference.
    public var model: String?
    public init(messages: [ChatMessage], tools: [ChatToolDefinition] = [], temperature: Double = 0.2,
                maxTokens: Int = 4096, thinking: Bool? = nil, purpose: String = "财务管家", responseFormat: JSONValue? = nil,
                groupID: UUID? = nil, groupTitle: String? = nil, timeout: TimeInterval? = nil, model: String? = nil) {
        self.messages = messages; self.tools = tools; self.temperature = temperature
        self.maxTokens = maxTokens; self.thinking = thinking; self.purpose = purpose; self.responseFormat = responseFormat
        self.groupID = groupID; self.groupTitle = groupTitle; self.timeout = timeout; self.model = model
    }
}

public protocol ChatTransport: Sendable {
    func send(_ request: ChatRequest) async throws -> ChatMessage
}
