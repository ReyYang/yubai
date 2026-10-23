# 帮你省钱 · 第一阶段非界面交付

2026-10-23，分支 `feat/butler-saving-core`，基于 `main 18889f8`。采用依据是 owner 本轮八项任务；没有联网调用 API，没有提交或推送。

## 实现与存档

- 该不该买：本机给允许的结论及事实，模型通过 `submit_verdict` 提交结论，越界会收到可重试错误。理由检查单句、60 字及金额／次数／原话／心愿单回答的引用；原话检查基于片段匹配，不是自然语言语义证明。`ask_purchase_questions` 成功后立即结束本轮，保留此前记下的生活事实，题目和选项进入下一轮上下文。「直接给结论」会拒绝提问工具。
- 心愿单：从结论加入时按金额设置 0／3／7 天；到期卡按 wish id 去重，`keep` 清除日期、`drop` 记录真实放弃时刻，买下后清除冷静期并关闭旧卡。
- 省下的钱：只计带 `droppedAt` 的 dropped 心愿；订阅按停用后已到期、没有实际支出的每一期计入，不提前计算未来。停用快照保留原定结束日、分期数和当时每期金额；恢复后停止该停用区间的累计，再次停用创建新区间。关联付款及同商户未关联付款均可排除虚假的省下。
- 克制进度：复用卡片及消费观的匹配和退款口径；比例取已设置次数、金额两者较高值，达到 80% 为 near，超过 100% 为 over，恰好 100% 仍为 near。购买次数边界另按任务要求，在已到次数时不允许 buy。
- 订阅体检：每月实际生成的第一封来信携带候选；候选包括仍在进行的小额周期支出及通过共享 recurring 周期校验的小额商户。`stillUsing` 记下月份，`stop` 复用 ChangeSet 的停用路径；商户候选会先建固定收付并关联历史依据。
- 分类：统一 `Category.defaults`，每个主项带预置小项和「其他」。`Category.subcategories` 是可编辑数据，支持自定义主项的小项；本轮不做分类编辑界面。本机优先小项记忆，再按明确关键词归类，京东／淘宝自身不决定小项。手动更改小项会记住并保护，手动清空也不再自动填写；只改主项会清除不适用的小项并允许重新归小项。导入保留有效的主项和小项。
- 小项批量归类：每日一轮、每请求 80 笔、整轮无笔数上限。只发送脱敏标题／用途／商户、主项及金额区间，不发送账户；purpose 为「小项归类」。严格检查 JSON 结构、记录 id、重复、主项及所属小项；仅未分类主项允许改主项，支出不得改到收入。全部块成功后才写入，取消或任一块失败不写入。结果应用需原账本快照仍有效。App 只在云端智能开启时调度，关闭时保留本机归类。
- 模型名：按 owner 给定名称切换 Flash／Pro；环境变量、保存偏好和配置初始化均映射旧名，未知名称继续保留。
- 消费观对话：`automatic` 在已有消费观时进入再聊；可显式选择模式并传入每周来信、心愿单有点后悔、克制超额三类开场上下文。再聊没有三问终止条件，修改仍需用户确认。

账本升级为 schema 3，兼容读取 schema 1／2；新增持久字段用 `decodeIfPresent` 或可选字段的合成解码提供默认值。旧分类、分类记忆、别名、消费观匹配、固定收付及快速记账商户映射一起迁移，保留自定义主项；存储保留升级前版本。没有放弃日期的旧心愿不会补造日期或计入省下。

## 新增与扩展的公开 API

| 用途 | API |
| --- | --- |
| 购买建议 | `PurchaseVerdict`（含 `label`）、`PurchaseNeed`、`PurchaseBounds.compute(ledger:amount:title:category:subcategory:now:)`、`SubmittedPurchaseVerdict`、`PurchaseQuestion` |
| 助手工具 | `SubmitVerdictTool`（含 `submit`）、`AskPurchaseQuestionsTool`（含 `questions`）；`AssistantReply.purchaseVerdict`／`.purchaseQuestions`；`PurchaseJudgment.subcategory` |
| 本机判断 | `PurchaseAssessment.verdict`／`.reason`；`Finance.assessPurchase` 增加标题、主项、小项输入 |
| 冷静期 | `CooldownChoice`、`Wishlist.defaultCooldownDays(amount:)`、`.add(fromVerdict:title:amount:category:subcategory:purpose:in:now:)`、`.cooldownDue(_:now:)`、`.answerCooldown(_:choice:in:now:)`；`CardKind.cooldownDue` |
| 省下的钱 | `StoppedSubscription`、`SavingsLine`（含 Source）、`SavingsSummary`；`Savings.summary(ledger:from:to:now:)`（now 可省略）、`.total(ledger:now:)` |
| 克制进度 | `RestrainProgress`（含 Status）、`.current(ledger:now:)` |
| 订阅 | `SubscriptionCandidate`、`SubscriptionAnswer`、`SubscriptionCheck.candidates(ledger:now:)`、`.answer(_:choice:in:now:)`；`RecurringDetection.matches(_:frequency:)` |
| 分类迁移与小项 | `CategoryMigration.canonical(_:)`／`.apply(to:)`；`SubcategoryChoice`；`SubcategoryClassifier.keys`／`.isUnclassified`／`.valid`／`.local`／`.classify`／`.remember`／`.set` |
| 小项批量处理 | `SubcategoryBatch.isDue`（两种参数标签）／`.pending`／`.run(transport:ledger:now:)`；`SubcategoryBatchResult.apply(to:now:)` |
| 汇总 | `Finance.subcategoryBreakdown(_:category:during:)`；summarize 支持 `group_by: subcategory` 并携带小项汇总；query_entries 和 compare_to_habit 支持小项 |
| 兼容工具 | `DeepSeekConfiguration.canonicalModel(_:)`；`CloudBackend.reflectPurchase` 必须传程序 verdict，新增可注入假 transport 的静态版本；基准样本 `PurchaseCase.verdict` 可选兼容旧夹具 |
| 再聊 | `ProfileColdStart.Mode`／`.OpeningContext`，`next` 增加 `mode`／`openingContext` |
| 数据字段 | `Entry.subcategory`／`.subcategoryUserEdited`；`Category.subcategories`；`AreaMatch.subcategories`；`WishItem.coolUntil`／`.droppedAt`／`.source`／`.category`／`.subcategory` |
| 账本与来信 | `Ledger.subcategoryMemory`／`.lastSubcategoryBatchDay`／`.subscriptionChecks`／`.stoppedSubscriptions`；`LetterFacts.weeklySavings`／`.totalSavings`／`.subscriptions` |
| 退款联动 | `LedgerOperations.syncLinkedRefundCategories` 同步小项，并可用 `expenseIDs` 限定关联范围 |

## 界面代码范围

`ChatInputBar` 放在已登记的 `AskYubaiView.swift` 中，共用文字框、发送按钮和原有样式；问余白的＋菜单、语音、触控范围和外观保留。消费观发送后立即清空并显示用户气泡，失败恢复输入，重试不重复增加用户气泡。没有更改消费观标题或入口。

此外只同步模型说明的两个键名、挂接后台分类调度，并在 `ButlerViews.swift` 的枚举穷举映射补一行 `.cooldownDue` 的「心愿单」标签，避免新增 Core 枚举导致 App 无法编译。没有增加购买结论、问题、冷静期、订阅、省钱或小项的新界面与交互。Xcode 工程由原生成器重建，登记测试源码。

## 验证

```sh
export PATH=/opt/swift-rootfs/usr/bin:$PATH
export XDG_CACHE_HOME=/tmp/yubai-swift-cache
export CLANG_MODULE_CACHE_PATH=/tmp/yubai-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/yubai-swift-module-cache
export YUBAI_LIVE_EVAL=0
swift build --target YubaiCore && swift test
```

构建退出 0；448 项测试，444 通过、4 项原有实网 opt-in 测试跳过、0 失败。新增 42 项分布在四个 `*Saving*Tests.swift`／`SavingConversationTests.swift` 文件，现有 406 项均保留；更新了 schema、分类、必传 verdict 和显式冷启动模式的断言。本轮新增智能测试全部使用假 ChatTransport，既有 HTTP 测试继续使用假 URLProtocol；没有实网 API 调用。

五个改动的 App 文件通过 iOS 26／macOS 14 条件语法解析，`git diff --check` 通过。当前 Linux 环境没有 Apple SDK，尚未执行 SwiftUI 类型检查、UI 测试、设备布局或输入交互验证。

## 设计稿阶段需要接入

1. 购买结论与一个事实理由、可追溯明细，三种结论都表述为建议；模型被本机边界拒绝重选时不把内部错误作为界面内容。
2. 购买问题每题 2–3 个短选项、最多 3 题；选择后作为下一条 user 消息发送，题目也支持用户自己写答案。
3. 冷静期到期问「X，还想要吗？」并接 `keep`／`drop`；手动放弃入口同样需要写真实 `droppedAt`，不能只改 status。买下后的到期卡关闭、空心愿单和失败状态需验收。
4. 每周来信按数据可选显示本周及累计省下的钱，每月第一封显示「这些还在用吗？」；订阅停用当下不显示全年预计省下，明细按已到期且未发生的每一期呈现。
5. 克制进度可能同时有本周次数和本月金额；恰好达到次数时购买建议已不能选买吧，但进度尚未超过 100%。两者的文案应清楚区分。
6. 小项为空表示尚不能判断；主项／小项两级和各主项「其他」要区分。编辑小项名称时，界面接线需要同步已有账目、`subcategoryMemory` 及消费观中的「主项/小项」引用，不能只改分类表字符串。
7. 再聊的标题、入口、开场上下文和旧三问进度提示留待设计。检查首次开场失败后直接输入、发送后气泡立即出现、失败回填、编辑后重试，以及原问余白＋／语音／多行输入的外观与无障碍。

## 文件清单

下面列出本轮全部修改和新增文件。

### Core

- [Sources/YubaiCore/AIBench.swift](../Sources/YubaiCore/AIBench.swift)
- [Sources/YubaiCore/Assistant/AskYubai.swift](../Sources/YubaiCore/Assistant/AskYubai.swift)
- [Sources/YubaiCore/Assistant/AssistantAgent.swift](../Sources/YubaiCore/Assistant/AssistantAgent.swift)
- [Sources/YubaiCore/Assistant/ButlerWording.swift](../Sources/YubaiCore/Assistant/ButlerWording.swift)
- [Sources/YubaiCore/Assistant/ImportOrganizer.swift](../Sources/YubaiCore/Assistant/ImportOrganizer.swift)
- [Sources/YubaiCore/Assistant/ProfileColdStart.swift](../Sources/YubaiCore/Assistant/ProfileColdStart.swift)
- [Sources/YubaiCore/Assistant/ProposalTools.swift](../Sources/YubaiCore/Assistant/ProposalTools.swift)
- [Sources/YubaiCore/Assistant/ReadOnlyTools.swift](../Sources/YubaiCore/Assistant/ReadOnlyTools.swift)
- [Sources/YubaiCore/ButlerCards.swift](../Sources/YubaiCore/ButlerCards.swift)
- [Sources/YubaiCore/ChangeSet.swift](../Sources/YubaiCore/ChangeSet.swift)
- [Sources/YubaiCore/DeepSeekClient.swift](../Sources/YubaiCore/DeepSeekClient.swift)
- [Sources/YubaiCore/Finance.swift](../Sources/YubaiCore/Finance.swift)
- [Sources/YubaiCore/Import.swift](../Sources/YubaiCore/Import.swift)
- [Sources/YubaiCore/IntelligenceBackends.swift](../Sources/YubaiCore/IntelligenceBackends.swift)
- [Sources/YubaiCore/LedgerMemoryMerge.swift](../Sources/YubaiCore/LedgerMemoryMerge.swift)
- [Sources/YubaiCore/LedgerOperations.swift](../Sources/YubaiCore/LedgerOperations.swift)
- [Sources/YubaiCore/ManualBookkeeping.swift](../Sources/YubaiCore/ManualBookkeeping.swift)
- [Sources/YubaiCore/Models.swift](../Sources/YubaiCore/Models.swift)
- [Sources/YubaiCore/ProfileHabits.swift](../Sources/YubaiCore/ProfileHabits.swift)
- [Sources/YubaiCore/PurchaseDecision.swift](../Sources/YubaiCore/PurchaseDecision.swift)
- [Sources/YubaiCore/QuickCapture.swift](../Sources/YubaiCore/QuickCapture.swift)
- [Sources/YubaiCore/Savings.swift](../Sources/YubaiCore/Savings.swift)
- [Sources/YubaiCore/Storage.swift](../Sources/YubaiCore/Storage.swift)
- [Sources/YubaiCore/Subcategories.swift](../Sources/YubaiCore/Subcategories.swift)
- [Sources/YubaiCore/WeeklyLetter.swift](../Sources/YubaiCore/WeeklyLetter.swift)
- [Sources/YubaiCore/Wishlist.swift](../Sources/YubaiCore/Wishlist.swift)

### App 适配

- [Sources/YubaiApp/AskYubaiView.swift](../Sources/YubaiApp/AskYubaiView.swift)
- [Sources/YubaiApp/ButlerViews.swift](../Sources/YubaiApp/ButlerViews.swift)
- [Sources/YubaiApp/CloudAssistantViews.swift](../Sources/YubaiApp/CloudAssistantViews.swift)
- [Sources/YubaiApp/IntelligenceRuntime.swift](../Sources/YubaiApp/IntelligenceRuntime.swift)
- [Sources/YubaiApp/ProfileConversationView.swift](../Sources/YubaiApp/ProfileConversationView.swift)

### 测试

- [Tests/YubaiCoreTests/BeeCountImportTests.swift](../Tests/YubaiCoreTests/BeeCountImportTests.swift)
- [Tests/YubaiCoreTests/DeepSeekCloudTests.swift](../Tests/YubaiCoreTests/DeepSeekCloudTests.swift)
- [Tests/YubaiCoreTests/FinanceTests.swift](../Tests/YubaiCoreTests/FinanceTests.swift)
- [Tests/YubaiCoreTests/FixedBillsTests.swift](../Tests/YubaiCoreTests/FixedBillsTests.swift)
- [Tests/YubaiCoreTests/ImportOrganizerTests.swift](../Tests/YubaiCoreTests/ImportOrganizerTests.swift)
- [Tests/YubaiCoreTests/ImportTests.swift](../Tests/YubaiCoreTests/ImportTests.swift)
- [Tests/YubaiCoreTests/LedgerSyncTests.swift](../Tests/YubaiCoreTests/LedgerSyncTests.swift)
- [Tests/YubaiCoreTests/ManualBookkeepingTests.swift](../Tests/YubaiCoreTests/ManualBookkeepingTests.swift)
- [Tests/YubaiCoreTests/MemoryTests.swift](../Tests/YubaiCoreTests/MemoryTests.swift)
- [Tests/YubaiCoreTests/ProfileColdStartTests.swift](../Tests/YubaiCoreTests/ProfileColdStartTests.swift)
- [Tests/YubaiCoreTests/ProfileTests.swift](../Tests/YubaiCoreTests/ProfileTests.swift)
- [Tests/YubaiCoreTests/PurchaseSavingTests.swift](../Tests/YubaiCoreTests/PurchaseSavingTests.swift)
- [Tests/YubaiCoreTests/QuickCaptureTests.swift](../Tests/YubaiCoreTests/QuickCaptureTests.swift)
- [Tests/YubaiCoreTests/SavingConversationTests.swift](../Tests/YubaiCoreTests/SavingConversationTests.swift)
- [Tests/YubaiCoreTests/Schema2Tests.swift](../Tests/YubaiCoreTests/Schema2Tests.swift)
- [Tests/YubaiCoreTests/StorageTests.swift](../Tests/YubaiCoreTests/StorageTests.swift)
- [Tests/YubaiCoreTests/SubcategorySavingTests.swift](../Tests/YubaiCoreTests/SubcategorySavingTests.swift)
- [Tests/YubaiCoreTests/SubscriptionSavingTests.swift](../Tests/YubaiCoreTests/SubscriptionSavingTests.swift)

### 工程与交接资料

- [.design-meta/DESIGN.md](../.design-meta/DESIGN.md)
- [.design-meta/README.md](../.design-meta/README.md)
- [.scratch/yubai-product/issues/13-complete-personal-release.md](../.scratch/yubai-product/issues/13-complete-personal-release.md)
- [.scratch/yubai-product/map.md](../.scratch/yubai-product/map.md)
- [Yubai.xcodeproj/project.pbxproj](../Yubai.xcodeproj/project.pbxproj)
- [docs/SAVING-CORE-PHASE1.md](../docs/SAVING-CORE-PHASE1.md)
