import XCTest
@testable import YubaiCore

final class SendLogTests: XCTestCase {
    func testGroupsAggregateInterleavedRequestsFailuresAndRedactions() throws {
        let log = SendLog(), groupID = UUID(), otherID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let body = Data(#"{"messages":[{"role":"user","content":"联系人A ****8000 [已隐藏]"}]}"#.utf8)
        let first = log.record(time: start, purpose: "问余白", model: "m", body: body, apiKey: "key",
            groupID: groupID, groupTitle: "记四笔")
        let other = log.record(time: start.addingTimeInterval(1), purpose: "导入整理", model: "m", body: body, apiKey: "key",
            groupID: otherID, groupTitle: "整理导入")
        let second = log.record(time: start.addingTimeInterval(2), purpose: "问余白·金额核对", model: "m", body: body, apiKey: "key",
            groupID: groupID, groupTitle: "记四笔")
        log.complete(id: first, response: SendLogResponse(durationMilliseconds: 12, httpStatus: 200), apiKey: "key")
        log.complete(id: other, response: SendLogResponse(durationMilliseconds: 20, httpStatus: 200), apiKey: "key")
        let pending = try XCTUnwrap(log.groups.first { $0.id == groupID })
        XCTAssertEqual(pending.requestCount, 2); XCTAssertEqual(pending.totalDurationMilliseconds, 12)
        XCTAssertFalse(pending.hasFailure)
        log.complete(id: second, response: SendLogResponse(durationMilliseconds: 23, httpStatus: 503, errorDescription: "暂时不可用"), apiKey: "key")
        let groups = log.groups, group = try XCTUnwrap(groups.first { $0.id == groupID })
        XCTAssertEqual(groups.map(\.id), [otherID, groupID])
        XCTAssertEqual(group.title, "记四笔"); XCTAssertEqual(group.purpose, "问余白"); XCTAssertEqual(group.startedAt, start)
        XCTAssertEqual(group.requestCount, 2); XCTAssertEqual(group.totalBytes, body.count * 2)
        XCTAssertEqual(group.totalDurationMilliseconds, 35); XCTAssertTrue(group.hasFailure)
        XCTAssertEqual(group.failureReasons, ["暂时不可用"])
        XCTAssertEqual(group.redactionSummary, ["联系人": 2, "长号码": 2, "标识符": 2])
        XCTAssertEqual(group.items.map(\.id), [first, second])
        XCTAssertNil(pending.items.last?.response, "Aggregates must be immutable snapshots")
        XCTAssertFalse(groups.first!.hasFailure)
        let network = log.record(purpose: "问余白", model: "m", body: body, apiKey: "key", groupID: groupID, groupTitle: "记四笔")
        log.complete(id: network, response: SendLogResponse(durationMilliseconds: 5, errorDescription: "网络超时"), apiKey: "key")
        XCTAssertEqual(log.groups.first { $0.id == groupID }?.failureReasons, ["暂时不可用", "网络超时"])
    }

    func testLegacyItemsStaySeparateDecodeWithoutGroupFieldsAndGroupTitlesHideSecrets() throws {
        let log = SendLog(), body = Data(#"{"messages":[]}"#.utf8)
        log.record(purpose: "legacy", model: "m", body: body, apiKey: "key")
        log.record(purpose: "legacy", model: "m", body: body, apiKey: "key")
        XCTAssertEqual(log.groups.count, 2); XCTAssertTrue(log.groups.allSatisfy { $0.requestCount == 1 && $0.title == "legacy" })
        let original = try XCTUnwrap(log.items.first)
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        encoded.removeValue(forKey: "groupID"); encoded.removeValue(forKey: "groupTitle")
        let legacy = try JSONDecoder().decode(SendLogItem.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertNil(legacy.groupID); XCTAssertNil(legacy.groupTitle)
        let key = "private-\"key\\value"
        let title = "给张三买书，订单123456789012，" + key + String(repeating: "后续说明", count: 20)
        let id = log.record(purpose: "问余白", model: "m", body: body, apiKey: key, groupID: UUID(), groupTitle: title)
        log.complete(id: id, response: SendLogResponse(durationMilliseconds: 3, httpStatus: 500), apiKey: key)
        let group = try XCTUnwrap(log.groups.first)
        XCTAssertEqual(group.title.count, 30)
        XCTAssertFalse(group.title.contains("张三")); XCTAssertFalse(group.title.contains("123456789012")); XCTAssertFalse(group.title.contains(key))
        XCTAssertTrue(group.title.contains("[密钥已隐藏]")); XCTAssertEqual(group.failureReasons, ["HTTP 500"])
    }

    func testAskGroupsToolLoopAndAmountRetryButSeparatesTurnsAndKeepsMetadataLocal() async throws {
        let log = SendLog(), context = AssistantFixtures.context(), session = AskYubaiSession()
        let stub = CloudTestStub(rawResponse: true, sendLog: log) { request in
            let payload = try CloudTestStub.payload(in: request)
            XCTAssertNil(payload["groupID"]); XCTAssertNil(payload["groupTitle"])
            let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
            if !messages.contains(where: { $0["role"] as? String == "tool" }) {
                return #"{"choices":[{"message":{"tool_calls":[{"id":"profile","type":"function","function":{"name":"get_profile","arguments":"{}"}}]}}]}"#
            }
            if messages.last?["role"] as? String == "tool" {
                return #"{"choices":[{"message":{"content":"未经核对的金额 ¥9999.00。"}}]}"#
            }
            return #"{"choices":[{"message":{"content":"请先核对记录。"}}]}"#
        }
        defer { stub.close() }
        let question = "给张三买书，订单123456789012，" + String(repeating: "核对这些记录", count: 10)
        _ = try await session.ask(question, ledger: context.ledger, transport: stub.backend, now: context.now)
        XCTAssertEqual(log.groups.count, 1)
        let first = try XCTUnwrap(log.groups.first)
        XCTAssertEqual(first.requestCount, 3); XCTAssertEqual(first.purpose, "问余白")
        XCTAssertEqual(first.title.count, 30); XCTAssertFalse(first.title.contains("张三")); XCTAssertFalse(first.title.contains("123456789012"))
        XCTAssertEqual(Set(first.items.compactMap(\.groupID)), [first.id])
        XCTAssertEqual(Set(first.items.compactMap(\.groupTitle)), [first.title])
        XCTAssertEqual(first.items.last?.purpose, "问余白·金额核对")
        XCTAssertEqual(first.totalBytes, first.items.reduce(0) { $0 + $1.byteSize })
        XCTAssertEqual(first.totalDurationMilliseconds, first.items.reduce(0) { $0 + ($1.response?.durationMilliseconds ?? 0) })
        XCTAssertFalse(first.hasFailure)
        _ = try await session.ask(question, ledger: context.ledger, transport: stub.backend, now: context.now)
        XCTAssertEqual(log.groups.count, 2); XCTAssertEqual(log.groups.map(\.requestCount), [3, 3])
        XCTAssertNotEqual(log.groups[0].id, log.groups[1].id)
        _ = try await session.ask(String(repeating: "问", count: 27) + "test-key", ledger: context.ledger, transport: stub.backend, now: context.now)
        XCTAssertEqual(log.groups.first?.title, String(repeating: "问", count: 27) + "[密钥")
    }

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
        XCTAssertEqual(log.groups.flatMap(\.items).map(\.id), [recent, middle])
        XCTAssertLessThanOrEqual(log.retainedByteSize, log.byteBudget)
        log.complete(id: old, response: SendLogResponse(content: "迟到回复", durationMilliseconds: 1), apiKey: "key")
        XCTAssertEqual(log.items.map(\.id), [recent, middle])
        log.complete(id: recent, response: SendLogResponse(content: String(repeating: "大回复", count: unit), durationMilliseconds: 12), apiKey: "key")
        XCTAssertTrue(log.items.isEmpty); XCTAssertEqual(log.retainedByteSize, 0)
        XCTAssertTrue(log.groups.isEmpty)
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
