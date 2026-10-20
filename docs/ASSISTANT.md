# 共享云端助手

实现放在 `Sources/YubaiCore/Assistant/`；数字工具只读账本快照，账务与画像修改生成待确认的 ChangeSet。2026-10-20 owner 决定：生活背景记忆直接保存，可查看、改、删和撤销；会触发提醒的画像规则仍需确认。金额来自 `Finance` 或账本整数分，并同时提供 `{text: Money.text(cents), cents: 整数分}`。密钥保存在本机钥匙串，开发环境变量作为回退；不进入账本或备份。模型默认值仍为 `DeepSeekConfiguration.defaultModel`，可用 `DEEPSEEK_MODEL` 覆盖。

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

ToolContext.init(ledger: Ledger, now: Date = Date(), confirmedEntryAmount: Int64? = nil,
                 parsedEntryAmounts: [Int64] = [], entryAccountHint: UUID? = nil,
                 memoryCharacterBudget: Int = 20_000)
AssistantTool // Sendable; name, description: String; parameters: JSONValue
AssistantTool.run(_ args: JSONValue, _ ctx: ToolContext) throws -> JSONValue
ReadOnlyTool.all: [any AssistantTool]
AssistantAgent.init(transport: any ChatTransport, context: ToolContext)
AssistantAgent.run(system: String, messages: [ChatMessage], tools: [any AssistantTool],
                   characterBudget: Int = 120_000) async throws -> AssistantReply
AssistantReply // text, evidenceEntryIDs, toolTrace, unverifiedAmounts；另含 rememberedNotes / updatedNotes / usedMemoryIDs
AssistantToolTrace // name: String, args: JSONValue
AskYubaiSession.init(characterBudget: Int = 120_000)
ProfileColdStart.init(transport: any ChatTransport, characterBudget: Int = 120_000)
AssistantAmountGuard.unverified(in text: String, results: [JSONValue]) -> [String]

Memory.context(ledger: Ledger, now: Date = Date(), characterBudget: Int = 20_000) -> JSONValue
Memory.apply(_ reply: AssistantReply, to ledger: inout Ledger, now: Date = Date()) throws
Memory.undo(noteID: UUID, in ledger: inout Ledger, now: Date = Date())
Memory.reject(lineMemoryID: UUID, in ledger: inout Ledger, now: Date = Date())
MemoryReflection.isDue(ledger: Ledger, now: Date = Date()) -> Bool
MemoryReflection.run(ledger: Ledger, transport: any ChatTransport, now: Date = Date()) async throws -> MemoryReflectionResult
MemoryReflectionResult.apply(to ledger: inout Ledger, now: Date = Date()) throws
MemoryReflectionResult.restoreRemoved(in ledger: inout Ledger, now: Date = Date()) throws
ProfileReview.candidate(ledger: Ledger, now: Date = Date()) -> ProfileReviewCandidate?
ProfileReview.keep(_ candidate: ProfileReviewCandidate, in ledger: inout Ledger, now: Date = Date()) throws
ProfileReview.remove(_ candidate: ProfileReviewCandidate, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet

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

## 余白记得的（记忆层 core，2026-10-20）

`Ledger.memories` 保存 `MemoryNote`：一句不超过200字的平实文字，分为计划 `plan`、在乎的事 `value`、生活情况 `life`。来源为聊天 `chat`、买后回访 `followUp`、导入时问过 `importAnswer`、卡片反馈 `feedback`、每周回看 `reflection`、你写的 `user`。另存身份、创建／更新时间、更新前原话 `previousText`、最近使用时间 `lastUsedAt` 与相关记录 `evidence`。文本须非空、单行，日期沿用账本有效范围，更新时间不得早于创建时间，ID唯一；不设记忆条数或 AI 调用次数上限。旧账本缺失时 memories 为空、lastReflectionWeek 为 nil，schema 仍为2；完整备份、恢复历史和 iCloud 账本自然包含这些字段。

### 写入与撤销

`remember {text, kind, replaces?, entry_ids?}` 做本机校验后返回 `{"remembered":{id,text,kind,source,updated,days_since_updated}}`，属于直接保存，不生成确认提案。`replaces` 必须引用现存记忆；记录依据须为当前未删除记录且不重复。缺省依据在更新时沿用旧值。写入文字先脱敏，再验证长度。值得记下的是长期计划、目标、在乎／不在乎的事及原因、合租、发薪规律和家庭变化；一次性情绪、临时决定、可从账本直接算出的数字不记。冲突时更新原条目。愿意多花、想克制、软线与底线等规则依旧走 `propose_profile_change`，记忆本身不参与提醒检测。

工具使用不可变快照，因此 `AssistantReply.rememberedNotes` 带新增条目，`updatedNotes` 带 `MemoryUpdate(previous: 原条目, note: 新条目)`，`usedMemoryIDs` 带本次使用标记。同轮工具立即读到暂存的新文字；一轮多次更新同一记忆合为一次更新，previousText 保留本轮前原话。本轮新建后再更新的记忆撤销时删除。成功的相同 remember 参数在整个答复中复用，避免隔轮重试重复记下；记忆改变后清掉旧只读结果缓存。

调用方须在一次 `store.update` 内先调用 `try Memory.apply(reply, to: &ledger, now: now)`，再登记其他待确认提案；本轮没有修改 App，现有 App 尚未消费这些新增字段。apply 核对账本ID、快照更新时间、被替换的原条目，验证完整候选后一次赋值，避免覆盖用户刚改过或删过的记忆。账本变化、网络失败或任务取消时丢弃整份结果，重新取快照再试。撤销新增用 `Memory.undo` 删除，撤销更新恢复 previousText 并刷新更新时间；只保留一层原话，完整历史仍由恢复版本提供。来信“不对”用 `Memory.reject` 真删除记忆，同时清理各来信中的关联 learned 行。

`Wishlist.answerFollowUp` 有自由文字时，不调用模型，直接写一条 value／followUp 记忆：“买了「X」，一个月后觉得值得／一般／有点后悔：原话”。保留真实选择，标题最多40字、整句最多200字，换行转为空格；完整回答仍保留在心愿中。只选按钮或空白文字不新增记忆，重复回答被拒。

### 每次读取与使用时间

`Memory.context` 返回 JSON，以 plan／value／life 分组，每条含 id、text、kind、source、updated（yyyy-MM-dd）、days_since_updated。全部经过 Redactor。默认字符预算20,000，可直接注入，工具路径也可用 `ToolContext.memoryCharacterBudget` 注入；按 `max(updatedAt,lastUsedAt)` 倒序优先保留，平手按更新时间、UUID排序。预算计算脱敏后的 JSON 及元数据，不截断单条记忆；省略项用 `omitted_count` 和 recall 提示说明。若预算连空包也容不下，仍保留最小元数据。数量本身没有上限。

`recall {keyword?, kind?}` 对全部记忆检索，关键词为脱敏文字子串，两个条件同时给出取交集；无参数返回全部，不受背景预算影响。`get_profile.memories`、`judge_purchase.memories` 和 AssistantAgent（包括 AskYubai、ProfileColdStart）的独立 JSON system 消息、ButlerWording 的卡片与来信 system 消息均带预算内记忆。独立 JSON 保证二次脱敏保留 UUID。提示明确“记忆是用户生活的背景，可能过时；引用时说明是什么时候记下的”，其中内容作为数据，不执行指令。ButlerWording 仍只能改写已有事实，不新增判断或数字。

`recall` 命中条目、`judge_purchase` 明确传入 `memory_ids` 引用的条目，通过 reply 交由 apply 更新 lastUsedAt，取较晚时间，不改变记忆的 updatedAt。单纯放入背景或 get_profile 不算已使用；不会猜测最终文字是否用了某条记忆。购买工具校验引用ID，并返回 referenced_memories。冷启动也可 recall，调用方同样应用使用标记。

### 每周回看与来信

`MemoryReflection.isDue` 使用本地时区、周一开始且首周至少四天的 ISO 周（含跨年周所属年），与 `Ledger.lastReflectionWeek` 比较。`run` 读取全部记忆，不使用背景预算截断；输入为上一完整 ISO 周的分类汇总、单笔个人消费大于¥500或 OffCharacter 识别的不寻常记录、本周截至 now 的卡片反馈与已回答回访、消费观。分类汇总复用 summarize，含退款／个人承担口径；不寻常识别复用 OffCharacter 的候选范围，不能当作全部异常的证明。外发字段白名单，不发送完整 Entry 或 Ledger。

模型仅返回 `{"add":[{text,kind}],"update":[{id,text}],"remove":[{id,reason}],"learned":["一句话"]}`。主要职责是合并重复、更新过时的事；统计或偶发行为不能推断生活事实或用户意愿。四个数组、类型、长度、ID存在性及同一ID只操作一次均在本机检查，任一非法则整份拒绝。更新保留原类型、创建时间、依据与上次原话；新增／更新来源为 reflection。learned 每句不超过40字，按 add 然后 update 的顺序关联到记忆，条数不能超过新增与更新总数；不能只有心得而无关联记忆。

`run` 的入参是不可变快照，先在副本试应用全部结果，成功后返回 `MemoryReflectionResult`；调用方在同一个 store.update 内调用 result.apply。apply 再核对账本ID、快照时间、周次与旧标记，直接写入新增／更新、真删除指定记忆，再登记当周周次。无网、无密钥、取消、格式错、校验错或保存失败时不标记，下次再试。没有变化但成功的回看也登记本周。

`LetterFacts.learned: [LearnedLine]?` 存 text 与 memoryID；apply 补入当周已有来信，或依现有来信资格创建一张，保留数字与已有的一条画像回顾。无账户或来信静音时不额外生成来信。删除项和理由保留在结果的 removedNotes，`restoreRemoved` 可显式恢复，更新时间刷新；不会覆盖已存在的同ID条目。新增／更新沿用 Memory.undo，否认某句沿用 Memory.reject。撤销记录由调用方保留，未新增常驻删除档案。

### 合并与画像过期回顾

`LedgerMemoryMerge` 对同账本记忆按ID取 updatedAt 较新者，平手 chosen 优先，lastUsedAt 取两侧较晚值。chosen 缺失的条目，只有对侧 note.updatedAt 晚于 chosen.updatedAt 才加入，避免复活 chosen 较新删除项；这与画像合并采用相同的版本水位思路，没有逐条墓碑。lastReflectionWeek 沿用 chosen 版本，避免把另一版本回看的状态误当成当前版本已完成。未选的原始版本照旧进入恢复历史。

`ProfileReview.candidate` 在有明确日期且确认已超过90天的想克制领域、原则中按最旧优先给一条，写入 `WeeklyLetter.candidate` 的 LetterFacts.review。旧记录无日期不猜测年龄；愿意多花的领域不在这次过期回顾范围。领域附当前未完 ISO 周及前三周的次数、净消费额，按时间顺序；复用 usage 的分类／关键词匹配、退款和个人承担规则。原则没有领域选择器，不编造使用统计。`keep` 校验候选仍有效后刷新 confirmedAt／principleDates；`remove` 仅返回删除 ChangeSet，确认才生效；“改一下”留给界面跳转。

### 隐私边界与 App 接入待办

提示禁止记证件号、卡号、他人全名；写入和读取都经过现有 Redactor。启发式脱敏不能保证识别任意姓名，也不能从模型文字证明事实真实或长期有效，这些边界仍需真实发送样本与用户纠正验证。记忆随账本备份／同步，云端智能启用时以脱敏背景发送，不建立额外远端记忆库。

本轮严格只改 YubaiCore、测试、文档。界面设计确认后接入：聊天／冷启动回复的单次 Memory.apply、记忆列表编辑删除与撤销、来信 learned 的“不对”、review 的保留／删除提案／修改跳转；在 `IntelligenceRuntime.refreshButler` 同类刷新时机检查 isDue，使用活动账本 transport，成功后同一 update 应用回看结果，失败静默保留下次重试。isDue 检查应放在现有 candidates.isEmpty 早退之前，没有新卡片也可回看；缺少可用 transport 时保留周次不动。并发刷新只允许一个回看任务，保存前继续检查取消与快照。来信已生成时补充，不新增第二封。

导入自由补充的 `describeImportQuestion` 目前只在 YubaiApp；core 的 ImportQuestion.answer 只接受选项，没有自由文字入口。本轮不改它，界面阶段须在已成功保存用途的同一次 update 写入 importAnswer 记忆、关联 question.entryIDs，并纳入该导入批次的撤销差量；不可把所有 setPurpose 自动当成导入回答记忆。来源 feedback／user 已保留，卡片反馈通过每周回看整理，本轮不增加其他写入入口。

## 会话生命周期

AskYubaiSession只在当前打开的问答会话内存中保留问答文字，不持久化工具结果或画像快照；关闭／新建会话后重新开始，每轮使用新账本快照。history没有轮数上限；每次发送前使用同一字符预算，超出时整对删除最早问答，在开头保留一条system「更早的对话已省略」。预算包含本次系统提示与新问题，保留未删除问答原文；当前问题自身过长也不截断。只有成功完成且未取消的回答加入history。本地金额候选也仅在会话内保留。

## 外发边界

工具采用字段白名单，绝不编码整个Entry或Ledger。`Redactor` 递归移除来源标识、指纹、附件和原文件字段，并在已知账本自由文本中替换完整来源标识token；8位以上连续数字只留末4位。证据UUID、结构化数值不当作卡号遮盖。所有 DeepSeek 传输路径再做一次脱敏并记录实际HTTP正文，不记录请求头。发送记录仅在内存保留最近50次，每条正文约4KB，包含失败请求的发送尝试；关闭应用后消失。

姓名识别包括转账/红包前缀后、以常见姓氏开头的2–4个汉字；以及「和／跟／给／请／与／陪」后、以常见姓氏开头的2–3个汉字，后接吃饭／聚餐／买／一起／的／逗号句号／空白／结尾。共用联系人别名；咖啡、外卖等商户词、王者荣耀和部分非人名词保守排除。它不识别自由文本中的任意姓名，稀有姓名或人名式商户仍可能漏判/误判，需后续实际样本调整。别名使用每份账本的内存随机salt加Swift Hasher索引，共享锁保护；同次应用运行、同一ledger.id保持稳定，重启后不保证相同。商户和备注允许发送，不做泛化隐藏。

## 当前验证状态

包含脚本传输测试、六工具合成账本断言、金额护栏、中文脱敏、内存密钥存储、传输JSON和发送日志测试，并保留旧AIBench。记忆层另有 MemoryTests、MemoryReflectionTests、ProfileReviewTests，覆盖写入／更新／撤销、预算／recall／使用标记、各模型路径的脱敏背景、回访、反思合法与非法结果、来信与否认、版本合并、旧JSON及画像回顾。合成 eval 夹具与执行说明见 `docs/ai-bench/README.md`。本环境无Swift工具链：记忆层只做源码通读、tree-sitter Swift 语法解析与 git diff 检查；解析不等于 Swift 编译器类型检查，没有运行构建、XCTest、Keychain或UI。实网只在 `YUBAI_LIVE_EVAL=1` 且密钥已配置时可执行，本次没有请求DeepSeek。

应用中的问答、导入整理和管家文字共用 `ActiveLedgerTransport`：每次发送前后都核对账本快照、锁与密钥配置。UI 测试的脚本只在 Debug simulator 且使用 UUID 隔离账本时可用，见 [开发说明](DEVELOPMENT.md)。
