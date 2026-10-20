import XCTest
@testable import YubaiCore

/// The script checks that the harness supplied real locally computed numbers before
/// quoting fixture expectations. This is an offline contract check, not an AI quality score.
private actor EvalScriptTransport: ChatTransport {
    let sample: AssistantEvalCase
    private var turns = 0
    private let context: ToolContext
    init(_ sample: AssistantEvalCase, context: ToolContext) { self.sample = sample; self.context = context }
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        turns += 1
        if turns <= sample.scriptedCalls.count {
            let call = sample.scriptedCalls[turns - 1]
            let args = try call.args.jsonText().replacingOccurrences(of: "$last_week_meituan", with: context.ledger.entries[1].id.uuidString)
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "eval-\(turns)", name: call.name, arguments: args)])
        }
        guard turns == sample.scriptedCalls.count + 1 else { throw YubaiError.invalid("评测产生了多余请求。") }
        let messages = request.messages.filter { $0.role == .tool }
        guard messages.count == sample.scriptedCalls.count else { throw YubaiError.invalid("缺少工具结果。") }
        let results = try messages.map { try JSONValue.parse($0.content ?? "") }
        let text = "本机记录显示：" + (sample.expectedNumbers.isEmpty ? "为长期有用的事物花钱。" : sample.expectedNumbers.joined(separator: "、") + "。")
        guard AssistantAmountGuard.unverified(in: text, results: results).isEmpty else { throw YubaiError.invalid("夹具金额与真实工具结果不一致。") }
        return ChatMessage(role: .assistant, content: text)
    }
}

final class AssistantEvalTests: XCTestCase {
    func testAssistantEvalSeedWithScriptedResponses() async throws {
        let samples = try AIBenchRunner.loadAssistantEval(bundle: .module)
        XCTAssertEqual(samples.count, 8)
        let context = AssistantFixtures.context()
        for sample in samples {
            let result = try await AIBenchRunner.runAssistantCase(sample, transport: EvalScriptTransport(sample, context: context), context: context)
            XCTAssertTrue(result.passed, sample.id)
            XCTAssertEqual(result.reply.toolTrace.map(\.name), sample.expectedTools, sample.id)
        }
    }

    func testLiveAssistantEvalOnlyWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["YUBAI_LIVE_EVAL"] == "1",
              let client = DeepSeekClient.configured(environment: environment) else {
            throw XCTSkip("Set YUBAI_LIVE_EVAL=1 with a configured key for live assistant eval; synthetic data only.")
        }
        let samples = try AIBenchRunner.loadAssistantEval(bundle: .module)
        let context = AssistantFixtures.context()
        for sample in samples {
            let result = try await AIBenchRunner.runAssistantCase(sample, transport: client, context: context)
            XCTAssertTrue(result.passed, sample.id)
        }
    }
}
