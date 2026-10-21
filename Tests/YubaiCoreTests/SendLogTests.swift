import XCTest
@testable import YubaiCore

final class SendLogTests: XCTestCase {
    func testStructuredRequestAndRedactionSummaryKeepCompleteJSON() throws {
        let redactor = Redactor()
        let content = redactor.text("和张三吃饭，给李四买书，订单123456789012") + " [已隐藏]" + String(repeating: "合成内容", count: 1000)
        let messages = [ChatMessage(role: .user, content: content),
            ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "call-1", name: "query_entries", arguments: #"{"keyword":"午餐"}"#)]),
            ChatMessage(role: .tool, content: #"{"count":2}"#, toolCallID: "call-1")]
        let body = try JSONValue.object([
            "messages": JSONValue.parse(String(decoding: JSONEncoder().encode(messages), as: UTF8.self)),
            "tools": .array([.object(["function": .object(["name": .string("query_entries")])])]),
            "temperature": .number(0.2), "max_tokens": .number(4000)]).jsonText()
        let log = SendLog()
        let id = log.record(purpose: "结构化", model: "test", body: Data(body.utf8), apiKey: "private-key")
        let item = try XCTUnwrap(log.items.first)
        XCTAssertEqual(item.id, id); XCTAssertEqual(item.messages, messages)
        XCTAssertEqual(item.tools, ["query_entries"]); XCTAssertEqual(item.temperature, 0.2); XCTAssertEqual(item.maxTokens, 4000)
        XCTAssertNil(item.response)
        XCTAssertEqual(item.redactionSummary, ["联系人": 2, "长号码": 1, "标识符": 1])
        XCTAssertGreaterThan(item.requestText.utf8.count, 4096)
        XCTAssertNoThrow(try JSONValue.parse(item.requestText))
        XCTAssertFalse(item.requestText.contains("张三")); XCTAssertFalse(item.requestText.contains("123456789012"))
    }
    func testBudgetEvictsOldestAndAccountsForResponseUpdates() throws {
        let body = Data(#"{"messages":[{"role":"user","content":"合成正文"}]}"#.utf8)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let reference = SendLog()
        reference.record(time: stamp, purpose: "test", model: "m", body: body, apiKey: "key")
        let unit = reference.retainedByteSize
        let log = SendLog(byteBudget: unit * 2)
        let old = log.record(time: stamp, purpose: "test", model: "m", body: body, apiKey: "key")
        let middle = log.record(time: stamp, purpose: "test", model: "m", body: body, apiKey: "key")
        let recent = log.record(time: stamp, purpose: "test", model: "m", body: body, apiKey: "key")
        XCTAssertEqual(log.items.map(\.id), [recent, middle]); XCTAssertEqual(log.totalCount, 3)
        XCTAssertLessThanOrEqual(log.retainedByteSize, log.byteBudget)
        log.complete(id: old, response: SendLogResponse(content: "迟到回复", durationMilliseconds: 1), apiKey: "key")
        XCTAssertEqual(log.items.map(\.id), [recent, middle])
        log.complete(id: recent, response: SendLogResponse(content: String(repeating: "大回复", count: unit), durationMilliseconds: 12), apiKey: "key")
        XCTAssertTrue(log.items.isEmpty); XCTAssertEqual(log.retainedByteSize, 0)
        let tiny = SendLog(byteBudget: 1)
        tiny.record(purpose: "test", model: "m", body: body, apiKey: "key")
        XCTAssertTrue(tiny.items.isEmpty); XCTAssertEqual(tiny.totalCount, 1)
    }
    func testKeyHygieneIncludesEscapedJSONAndResponseFields() throws {
        let key = "private-\"key\\value"
        let body = try JSONValue.object(["messages": .array([.object(["role": .string("user"), "content": .string(key)])])]).jsonText()
        let log = SendLog()
        let id = log.record(purpose: key, model: key, body: Data(body.utf8), apiKey: key)
        log.complete(id: id, response: SendLogResponse(content: key, toolCalls: [key], finishReason: key,
            durationMilliseconds: 2, httpStatus: 200, errorDescription: key), apiKey: key)
        let item = try XCTUnwrap(log.items.first)
        XCTAssertFalse(String(describing: item).contains(key))
        XCTAssertEqual(item.messages.first?.content, "[密钥已隐藏]")
        XCTAssertEqual(item.response?.content, "[密钥已隐藏]")
        XCTAssertEqual(item.response?.toolCalls, ["[密钥已隐藏]"])
        XCTAssertEqual(item.purpose, "[密钥已隐藏]"); XCTAssertEqual(item.model, "[密钥已隐藏]")
        XCTAssertNoThrow(try JSONValue.parse(item.requestText))
        let noKey = SendLog()
        noKey.record(purpose: "test", model: "m", body: Data("abc".utf8), apiKey: "")
        XCTAssertEqual(noKey.items.first?.requestText, "abc")
    }
    func testTransportBackfillsSuccessToolReplyAndFailures() async throws {
        let log = SendLog()
        let success = CloudTestStub(rawResponse: true, sendLog: log) { _ in
            #"{"choices":[{"finish_reason":"tool_calls","message":{"content":"test-key 已收到","tool_calls":[{"id":"call-1","type":"function","function":{"name":"get_profile","arguments":"{}"}}]}}]}"#
        }
        defer { success.close() }
        _ = try await success.send(ChatRequest(messages: [ChatMessage(role: .user, content: "你好")]))
        let response = try XCTUnwrap(log.items.first?.response)
        XCTAssertEqual(response.content, "[密钥已隐藏] 已收到"); XCTAssertEqual(response.toolCalls, ["get_profile"])
        XCTAssertEqual(response.httpStatus, 200); XCTAssertEqual(response.finishReason, "tool_calls")
        XCTAssertGreaterThanOrEqual(response.durationMilliseconds, 0); XCTAssertNil(response.errorDescription)
        let failure = CloudTestStub(rawResponse: true, statusCode: 401, sendLog: log) { _ in "test-key" }
        defer { failure.close() }
        do { _ = try await failure.send(ChatRequest(messages: [])); XCTFail("Expected HTTP failure") } catch { }
        let failed = try XCTUnwrap(log.items.first?.response)
        XCTAssertEqual(failed.httpStatus, 401); XCTAssertTrue(failed.errorDescription?.contains("密钥无效") == true)
        XCTAssertNil(failed.content); XCTAssertFalse(String(describing: log.items).contains("test-key"))
        let network = CloudTestStub(sendLog: log) { _ in throw URLError(.timedOut) }
        defer { network.close() }
        do { _ = try await network.send(ChatRequest(messages: [])); XCTFail("Expected timeout") } catch { }
        XCTAssertNil(log.items.first?.response?.httpStatus)
        XCTAssertTrue(log.items.first?.response?.errorDescription?.contains("网络或超时") == true)
    }
}
