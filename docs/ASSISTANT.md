# 共享云端助手（2.0 step 2）

实现放在 `Sources/YubaiCore/Assistant/`；只读账本快照，不写账本。金额来自 `Finance` 或账本整数分，并同时提供 `{text: Money.text(cents), cents: 整数分}`。密钥保存在本机钥匙串，开发环境变量作为回退；不进入账本或备份。模型默认值仍为 `DeepSeekConfiguration.defaultModel`，可用 `DEEPSEEK_MODEL` 覆盖。

## 公开接口

```swift
// Codable / Sendable / Equatable，number关联值为Double。
JSONValue // null, bool, number, string, array, object
JSONValue.parse(_ text: String) throws -> JSONValue
JSONValue.jsonText() throws -> String

ChatMessage.init(role: Role, content: String? = nil,
                 toolCalls: [ChatToolCall]? = nil, toolCallID: String? = nil)
ChatToolCall.init(id: String, name: String, arguments: String = "{}")
ChatToolDefinition.init(name: String, description: String, parameters: JSONValue)
ChatRequest.init(messages: [ChatMessage], tools: [ChatToolDefinition] = [],
                 temperature: Double = 0.2, maxTokens: Int = 1200, purpose: String = "财务管家")
ChatTransport.send(_ request: ChatRequest) async throws -> ChatMessage
DeepSeekClient.send(_ request: ChatRequest) async throws -> ChatMessage
DeepSeekClient.send(_ request: ChatRequest, session: URLSession) async throws -> ChatMessage
DeepSeekClient.configured(keyStore: APIKeyStore = .shared,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    redactor: Redactor = .shared) -> DeepSeekClient?

ToolContext.init(ledger: Ledger, now: Date = Date())
AssistantTool // Sendable; name, description: String; parameters: JSONValue
AssistantTool.run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue
ReadOnlyTool.all: [any AssistantTool]
AssistantAgent.init(transport: any ChatTransport, context: ToolContext)
AssistantAgent.run(system: String, messages: [ChatMessage], tools: [any AssistantTool],
                   maxSteps: Int = 8) async throws -> AssistantReply
AssistantReply // text, evidenceEntryIDs: [UUID], toolTrace: [AssistantToolTrace], unverifiedAmounts: [String]
AssistantToolTrace // name: String, args: JSONValue
AssistantAmountGuard.unverified(in text: String, results: [JSONValue]) -> [String]

Redactor.init(ledger: Ledger? = nil)
Redactor.text(_ input: String) -> String
Redactor.content(_ input: String) -> String
Redactor.value(_ input: JSONValue) -> JSONValue
SendLog.shared.items: [SendLogItem] // 最近的在前
SendLogItem // id, time, purpose, model, byteSize, requestText
APIKeyStorage // Sendable; read() throws -> String?, write(_:) throws, delete() throws
APIKeyStore.init(storage: any APIKeyStorage = KeychainAPIKeyStorage())
APIKeyStore.save(_ key: String) throws
APIKeyStore.delete() throws
APIKeyStore.configuration(environment: [String: String] = ProcessInfo.processInfo.environment) -> DeepSeekConfiguration?
APIKeyStore.isConfigured: Bool // 包括环境变量回退
```

## 工具契约和取舍

- `get_funds {}`：保守可动用、现金、负债、已承诺付款、目标、应急、生活、未知流入、预计收入与警示。使用现有偏好的预测范围。
- `forecast {date | days, amount?}`：二选一；日期为今天至365天内。用临时快照调用 `Finance.funds`，多展开一天后取目标日的预测点，以包含当天零点后的付款，不改偏好。已到期付款也计入；信用还款不重复扣本金。购买比较用当日保守预测余额，返回 `enough`、`after_purchase`、`short_by`，保留原引擎口径。
- `query_entries {start_date?, end_date?, category?, nature?, keyword?, min_amount?, max_amount?, limit?}`：日期均含当天，金额为元且按原始记录金额筛选，关键词查原标题/备注及其脱敏版本（支持模型用联系人别名回查）。`nature=spending` 包含支出与退款，`income` 只含真实收入，`transfer` 对应 `Nature.paired`。默认20条，最多50条。返回本地ID、日期、原金额、消费口径金额、方向、性质、标题、分类、账户类型；不发送账户名、来源信息或备注全文。备注允许用于筛选及脱敏提示词。
- `summarize`：相同筛选加 `group_by=day/week/month/category`，周从周一开始；默认全部匹配记录。显式limit时仅汇总限定的最近记录，同时报告matched_count/truncated。各组有笔数、消费净额、真实收入、内部移动量；退款跟随原消费分类，房租用个人承担额。最多附50个证据ID，并标记证据截断。
- `compare_to_habit {category?, keyword?, amount?}`：至少一个匹配条件，同时给出取交集。近90个自然日截至now的实际支出；不将退款作为购买样本。单笔金额用 `Finance.spendingAmount`，均值/中位数截到分；每周频次=count×7/90。位置为历史金额小于等于给定金额的百分比。没有样本时均值、中位数和位置为null；最近5笔附证据ID。
- `get_profile {}`：当前稳定字段为 `purchaseValues`，后续扩展结构不删除工具。

参数格式错误、未知工具、工具执行失败均转为可读JSON错误，模型可自行修正。步骤耗尽抛 `AssistantAgentError.stepLimit`。证据只收集工具结果中的 `entry_ids`，并核对属于当前快照的未删除记录。普通模型回合最多maxSteps次；金额不匹配时最多额外一次无工具重写，再不匹配则返回 `unverifiedAmounts` 供UI提示。

金额护栏统一货币符号、千位分隔与小数形式，排除日期、UUID、百分比及明确数量单位；它是保守的文本启发式，不证明事实或语义正确。中文大写金额等非阿拉伯数字表达尚不支持。除明确数量外，裸数字按可能金额处理。

## 外发边界

工具采用字段白名单，绝不编码整个Entry或Ledger。`Redactor` 递归移除来源标识、指纹、附件和原文件字段，并在已知账本自由文本中替换完整来源标识token；8位以上连续数字只留末4位。证据UUID、结构化数值不当作卡号遮盖。所有传输路径（包括旧四项云端功能）再做一次脱敏并记录实际HTTP正文，不记录请求头。发送记录仅在内存保留最近50次，每条正文约4KB，包含失败请求的发送尝试；关闭应用后消失。

姓名识别限定为转账/红包前缀后、以常见姓氏开头的2–4个汉字；咖啡、外卖等商户后缀排除。它不识别自由文本中的任意姓名，稀有姓名或人名式商户仍可能漏判/误判，需后续实际样本调整。别名使用每份账本的内存随机salt加Swift Hasher索引，共享锁保护；同次应用运行、同一ledger.id保持稳定，重启后不保证相同。商户和备注允许发送，不做泛化隐藏。

## 当前验证状态

新增脚本传输测试、六工具合成账本断言、金额护栏、中文脱敏、内存密钥存储、传输JSON和发送日志测试，并保留旧AIBench。六例eval夹具与执行说明见 `docs/ai-bench/README.md`。本环境无Swift工具链：仅做源码、语法树及工程引用静态检查；没有运行构建、测试、Keychain或UI。实网只在 `YUBAI_LIVE_EVAL=1` 且密钥已配置时可执行，本次没有请求DeepSeek。
