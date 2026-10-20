# 共享云端助手

实现放在 `Sources/YubaiCore/Assistant/`；数字工具只读账本快照，修改工具只生成待确认的 ChangeSet。金额来自 `Finance` 或账本整数分，并同时提供 `{text: Money.text(cents), cents: 整数分}`。密钥保存在本机钥匙串，开发环境变量作为回退；不进入账本或备份。模型默认值仍为 `DeepSeekConfiguration.defaultModel`，可用 `DEEPSEEK_MODEL` 覆盖。

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
                 temperature: Double = 0.2, maxTokens: Int = 4096, purpose: String = "财务管家")
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
                   characterBudget: Int = 120_000) async throws -> AssistantReply
AssistantReply // text, evidenceEntryIDs: [UUID], toolTrace: [AssistantToolTrace], unverifiedAmounts: [String]
AssistantToolTrace // name: String, args: JSONValue
AskYubaiSession.init(characterBudget: Int = 120_000)
ProfileColdStart.init(transport: any ChatTransport, characterBudget: Int = 120_000)
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

- `get_funds {}`：保守可动用、现金、负债、已承诺付款、目标、应急、生活、未知流入、预计收入与警示。默认使用固定 90 天观察期；底线读取消费观，生活预留自动估算。
- `forecast {date | days, amount?}`：二选一；日期为今天至365天内。用显式范围参数调用 `Finance.funds`，多展开一天后取目标日的预测点，以包含当天零点后的付款，不读写旧观察期偏好。已到期付款也计入；信用还款不重复扣本金。购买比较用当日保守预测余额，返回 `enough`、`after_purchase`、`short_by`，保留原引擎口径。
- `query_entries {start_date?, end_date?, category?, nature?, keyword?, min_amount?, max_amount?, limit?, offset?}`：日期均含当天，金额为元且按原始记录金额筛选，关键词查原标题/备注及其脱敏版本（支持模型用联系人别名回查）。`nature=spending` 包含支出与退款，`income` 只含真实收入，`transfer` 对应 `Nature.paired`。默认20条，单页最多50条；offset为非负整数，默认0；还有后续记录时返回next_offset，按相同筛选继续翻页。排序为日期倒序，同日按UUID稳定排序。返回本地ID、日期、原金额、消费口径金额、方向、性质、标题、分类、账户类型；不发送账户名、来源信息或备注全文。备注允许用于筛选及脱敏提示词。
- `summarize`：相同筛选加 `group_by=day/week/month/category`，周从周一开始；默认全部匹配记录。显式limit时仅汇总限定的最近记录，同时报告matched_count/truncated。各组有笔数、消费净额、真实收入、内部移动量；退款跟随原消费分类，房租用个人承担额。最多附50个证据ID，并标记证据截断。
- `compare_to_habit {category?, keyword?, amount?}`：至少一个匹配条件，同时给出取交集。近90个自然日截至now的实际支出；不将退款作为购买样本。单笔金额用 `Finance.spendingAmount`，均值/中位数截到分；每周频次=count×7/90。位置为历史金额小于等于给定金额的百分比。没有样本时均值、中位数和位置为null；最近5笔附证据ID。有数据时附last_year（去年同一天、同一时刻向前90个自然日的average/count/window_days）；无数据不返回该字段。匹配想克制领域时附soft_limits（领域ID、标题、per_week_count/per_month_amount），购买判断的habit直接复用。
- `get_profile {}`：愿意多花、想克制和柔性提醒、原则、底线、储蓄目标与近90天习惯，以及提案需要的本地账户／安排标识。领域包含confirmed_at（yyyy-MM-dd或null）和days_since_confirmed（无日期为null）；原则为`[{text, confirmed_at}]`。recent_followups提供最近10条已回答心愿回访：title、amount（money对象）、judgment（前200字）、answer、bought_date（无购买记录为null），统一经过Redactor。按followUpAnsweredAt倒序，旧数据依次回退followUpAt、createdAt。

参数格式错误、未知工具、工具执行失败均转为可读JSON错误，模型可自行修正。工具循环持续到模型返回最终文字或Task取消，没有轮数或单轮调用数量上限；仍校验调用ID和类型。与上一轮工具调用同名且规范化参数相同（解析JSON、排序键、统一数值表示）时，复用上次结果，绑定当前tool_call_id，并附system提示「这个调用刚执行过，结果相同；请换个查询或直接回答」。不同参数、不同工具名和隔轮再次查询会执行；提案复用时不重复创建ChangeSet。

每次请求前按字符预算压缩conversation，默认120,000，可注入较小值测试。字符统计包含文字、调用名、参数和ID；优先将最早的tool内容替换为`{"omitted":true,"note":"早期工具结果已省略，需要时重新查询"}`，保留tool_call_id和助手调用配对。保留system、全部用户／助手文字及最近一组工具结果；不截断这些受保护内容，故它们自身超过预算时预算是软约束。省略后需要原始依据可重新查询。

证据只收集工具结果中的entry_ids，并核对属于当前快照的未删除记录。金额不匹配时额外做一次无工具重写，再不匹配则返回unverifiedAmounts供UI提示。maxTokens默认4096，只控制单次回答长度。

金额护栏统一货币符号、千位分隔与小数形式，排除日期、UUID、百分比及明确数量单位；它是保守的文本启发式，不证明事实或语义正确。中文大写金额等非阿拉伯数字表达尚不支持。除明确数量外，裸数字按可能金额处理。

## 画像与长期记忆

ProfileArea.confirmedAt和SpendingProfile.principleDates记录用户最近新增／修改的时间，旧JSON缺失分别解码为nil／空字典。ChangeSet按createdAt盖戳；手动画像编辑调用stamp(changedFrom:at:)，仅更新改变的领域（含移动立场）和新原则，删除原则时清理日期。未改变的原话保留原日期。日期沿用账本的有效范围校验，原则日期不能引用已删除的原则。judge_purchase.values中的领域引用和原则均带confirmed_at。问答逐字引用时说明写下时间，超过180天提醒用户可能已经变化，不自动删除或代改画像。

用户在对话中明确表达长期愿意多花／想克制／原则／底线时，先get_profile，再propose_profile_change，等确认，不声称已保存。临时情绪或一次性决定不提案。心愿回访保留当时判断与实际感受，供之后的判断参考。

卡片反馈统一使用最近60天（feedbackAt，旧数据缺失回退createdAt，排除未来反馈）。同领域两次有点后悔提案收紧：次数减一最低0、金额乘0.8，无线时沿用当前使用量设线。同一想克制领域两次值得：有线则次数加一、金额乘1.25并四舍五入到整分，沿用现有字段有效范围；无线则提案移到愿意多花。同领域已有待确认领域提案时不再生成；参与提案的反馈写feedbackProposalID，之后不重复使用。所有调整均待用户确认。

Ledger.categoryMemory保存规范化标题到用户确认分类的对照；CategoryMemory.key去首尾空白、转小写并移除数字和标点。非「导入整理」的setCategory在ChangeSet应用时学习，模型自动导入分类不学习；core批量纠正分类也学习。目前Editors／EntryDetail无记录分类保存入口，因此没有新增界面或编辑路径。导入整理在请求前accept命中的有效分类，将命中列表写known_categories；模型返回的冲突分类不采用。失效／已删除分类回退模型处理。该表包含在备份、相等判断与校验中，旧数据缺失为空。

refresh压缩dismissedAt早于365天的卡片正文、facts、evidence、letter和importQuestion，保留身份、标题、主题去重键、时间、反馈与提案标记、领域ID；不会按归档删除卡片。无变化刷新不产生写入。

iCloud选定版本后、持久化前调用LedgerMemoryMerge，仅合并同ledger.id的记忆：领域按id取较新confirmedAt（同时间chosen优先，缺失日期视为未知）；chosen缺失的领域／原则，仅在对侧确认时间（无时间时用对侧profile.updatedAt）晚于chosen.profile.updatedAt时加入，避免复活较早删除项。原则按文字和principleDates合并。保留任一侧反馈，冲突取较早的反馈时间（缺失用卡片createdAt），dismissedAt取较早的非空值，保留feedbackProposalID；静音主题取并集，分类对照chosen优先。资金、记录、底线和其余账本内容仍沿用用户选择；未选原始版本照旧存入恢复历史。合并后校验失败不会写回或标记冲突已解决。

## 会话生命周期

AskYubaiSession只在当前打开的问答会话内存中保留问答文字，不持久化工具结果或画像快照；关闭／新建会话后重新开始，每轮使用新账本快照。history没有轮数上限；每次发送前使用同一字符预算，超出时整对删除最早问答，在开头保留一条system「更早的对话已省略」。预算包含本次系统提示与新问题，保留未删除问答原文；当前问题自身过长也不截断。只有成功完成且未取消的回答加入history。本地金额候选也仅在会话内保留。

## 外发边界

工具采用字段白名单，绝不编码整个Entry或Ledger。`Redactor` 递归移除来源标识、指纹、附件和原文件字段，并在已知账本自由文本中替换完整来源标识token；8位以上连续数字只留末4位。证据UUID、结构化数值不当作卡号遮盖。所有 DeepSeek 传输路径再做一次脱敏并记录实际HTTP正文，不记录请求头。发送记录仅在内存保留最近50次，每条正文约4KB，包含失败请求的发送尝试；关闭应用后消失。

姓名识别包括转账/红包前缀后、以常见姓氏开头的2–4个汉字；以及「和／跟／给／请／与／陪」后、以常见姓氏开头的2–3个汉字，后接吃饭／聚餐／买／一起／的／逗号句号／空白／结尾。共用联系人别名；咖啡、外卖等商户词、王者荣耀和部分非人名词保守排除。它不识别自由文本中的任意姓名，稀有姓名或人名式商户仍可能漏判/误判，需后续实际样本调整。别名使用每份账本的内存随机salt加Swift Hasher索引，共享锁保护；同次应用运行、同一ledger.id保持稳定，重启后不保证相同。商户和备注允许发送，不做泛化隐藏。

## 当前验证状态

包含脚本传输测试、六工具合成账本断言、金额护栏、中文脱敏、内存密钥存储、传输JSON和发送日志测试，并保留旧AIBench。合成 eval 夹具与执行说明见 `docs/ai-bench/README.md`。本环境无Swift工具链：本轮仅做源码通读、词法括号／字符串、JSON夹具、差异及工程引用静态检查；本机没有Swift解析器，未进行Swift语法树或类型检查，没有运行构建、测试、Keychain或UI。实网只在 `YUBAI_LIVE_EVAL=1` 且密钥已配置时可执行，本次没有请求DeepSeek。

应用中的问答、导入整理和管家文字共用 `ActiveLedgerTransport`：每次发送前后都核对账本快照、锁与密钥配置。UI 测试的脚本只在 Debug simulator 且使用 UUID 隔离账本时可用，见 [开发说明](DEVELOPMENT.md)。
