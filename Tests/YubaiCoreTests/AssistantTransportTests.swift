import XCTest
@testable import YubaiCore

final class AssistantTransportTests: XCTestCase {
    func testModelUnavailableErrorsAreRecognizableWithoutEchoingResponseBodies() async throws {
        for (status, body) in [(400, #"{"error":{"message":"Invalid model: secret-key"}}"#),
                               (404, #"{"error":{"message":"MODEL does not exist"}}"#),
                               (422, #"{"error":{"code":"model_not_found"}}"#)] {
            let stub = CloudTestStub(rawResponse: true, statusCode: status) { _ in body }
            defer { stub.close() }
            do {
                _ = try await stub.send(ChatRequest(messages: [ChatMessage(role: .user, content: "你好")]))
                XCTFail("An unavailable model must fail")
            } catch {
                XCTAssertEqual(error as? DeepSeekError, .modelUnavailable(DeepSeekConfiguration.defaultModel))
                XCTAssertFalse(error.localizedDescription.contains("secret-key"))
            }
        }
    }
    func testOtherHTTPFailuresDoNotBecomeModelErrors() async throws {
        for (status, body) in [(400, "invalid temperature"), (404, "route not found"), (401, "model access denied"), (500, "model temporarily busy")] {
            let stub = CloudTestStub(rawResponse: true, statusCode: status) { _ in body }
            defer { stub.close() }
            do {
                _ = try await stub.send(ChatRequest(messages: [ChatMessage(role: .user, content: "你好")]))
                XCTFail("HTTP failure must throw")
            } catch { XCTAssertNil(error as? DeepSeekError) }
        }
    }
    func testOpenAIEnvelopeAndNullContentToolResponse() async throws {
        let stub = CloudTestStub(rawResponse: true) { request in
            let payload = try CloudTestStub.payload(in: request)
            XCTAssertEqual(payload["model"] as? String, DeepSeekConfiguration.defaultModel)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["system", "user", "assistant", "tool"])
            let content = try XCTUnwrap(messages[1]["content"] as? String)
            XCTAssertTrue(content.contains("联系人")); XCTAssertTrue(content.contains("****5678")); XCTAssertFalse(content.contains("张三"))
            XCTAssertEqual(messages[3]["tool_call_id"] as? String, "prior")
            let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
            XCTAssertEqual(tools.first?["type"] as? String, "function")
            let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
            XCTAssertEqual(function["name"] as? String, "get_funds"); XCTAssertNotNil(function["parameters"])
            return #"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-1","type":"function","function":{"name":"get_funds","arguments":"{}"}}]}}]}"#
        }
        defer { stub.close() }
        let request = ChatRequest(messages: [ChatMessage(role: .system, content: "只读"),
            ChatMessage(role: .user, content: "微信转账-张三 12345678"),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "prior", name: "get_funds")]),
            ChatMessage(role: .tool, content: #"{"available":{"text":"¥1.00","cents":100}}"#, toolCallID: "prior")],
            tools: [ChatToolDefinition(name: ReadOnlyTool.getFunds.name, description: ReadOnlyTool.getFunds.description, parameters: ReadOnlyTool.getFunds.parameters)])
        let reply = try await stub.send(request)
        XCTAssertNil(reply.content); XCTAssertEqual(reply.role, .assistant)
        XCTAssertEqual(reply.toolCalls?.first?.function.name, "get_funds")
        XCTAssertEqual(reply.toolCalls?.first?.function.arguments, "{}")
    }

    func testTransportLogsSanitizedRequestWithoutHeaders() async throws {
        let stub = CloudTestStub { _ in "连接正常" }; defer { stub.close() }
        let purpose = "日志验证-" + UUID().uuidString
        _ = try await stub.send(ChatRequest(messages: [ChatMessage(role: .user, content: "红包-王五 62220212345678")], purpose: purpose))
        let item = try XCTUnwrap(SendLog.shared.items.first { $0.purpose == purpose })
        XCTAssertFalse(item.requestText.contains("王五")); XCTAssertFalse(item.requestText.contains("62220212345678"))
        XCTAssertFalse(item.requestText.contains("Bearer")); XCTAssertFalse(item.requestText.contains("test-key"))
        XCTAssertGreaterThan(item.byteSize, 0)
    }
    func testEmptyContentDistinguishesTruncationReasoningAndEmptyOrMalformedReplies() async throws {
        let cases = [
            (#"{"choices":[{"finish_reason":"length","message":{"content":"","reasoning_content":"推理中"}}]}"#, "云端回复被截断"),
            (#"{"choices":[{"finish_reason":"stop","message":{"content":null,"reasoning_content":"推理中"}}]}"#, "只返回了推理内容"),
            (#"{"choices":[{"finish_reason":"stop","message":{"content":"  "}}]}"#, "云端返回空内容"),
            ("not-json", "云端响应无法解析")
        ]
        for (body, expected) in cases {
            let log = SendLog()
            let stub = CloudTestStub(rawResponse: true, sendLog: log) { _ in body }
            defer { stub.close() }
            do { _ = try await stub.send(ChatRequest(messages: [])); XCTFail("Empty body should fail") }
            catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
            XCTAssertTrue(log.items.first?.response?.errorDescription?.contains(expected) == true)
            XCTAssertEqual(log.items.first?.response?.httpStatus, 200)
        }
    }

}
