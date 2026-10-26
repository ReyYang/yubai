# 分类模型 · schema 4

2026-10-26，owner 明确委托，分支 `refactor/category-model`，基于 main `cfe155c`。仅 Core 数据与逻辑重构及必要 App 接线；没有新增页面，没有修改布局、样式、静态界面文案或动效，没有修改 Money／Keypad，没有新增依赖，没有提交 Git。

同日收尾：owner 确认「允许自己加主项」，导入页明确点击「新建」后才创建自定义主项，自动流程仍不创建；同时授权将 Apple Pay 通知的错误分类文案修正为「没分类」，布局、通知格式和其他句式保持原样。

## 已采用的模型与入口

- 分类表是主项、小项、关键词的唯一来源：支出 12 项、收入 5 项，顺序按 owner 本轮清单；另有 `system` 的「内部移动」。完整小项与关键词见 `Category.defaults`。旧三套规则的全部关键词由回归测试逐词检查。
- 主项未知保存 `Classification.pendingCategory`，通过 `Classification.displayCategory` 显示「没分类」；小项未知保存 nil。明确选的「其他支出／其他收入」不被本地分类、每日 AI 或导入整理改主项。
- `CategoryGuesser.guess` 返回 `CategoryAssignment(category:subcategory:)`，先按用途、商户、标题顺序查统一记忆，再匹配表中的词；词证据最长优先，同长度按表顺序。账单分类线索在记忆之后、关键词之前映射，手动指定的导入对应优先于自动线索。
- 早餐／午餐／晚餐的时间推断只在已有主项为餐饮、文本像正餐且没有明确小项时使用 `entry.date`：5–9 点早餐、10–14 点午餐、17–21 点晚餐；其余留空。
- `classificationMemory: [String: String]` 保存「归一键 → 主项或主项/小项」。归一函数只有 `CategoryMemory.key`；`QuickCapture.key` 委托给它。卡名与 Apple Pay 去重身份继续使用保留数字和标点的 `cardKey`，保持历史去重凭据兼容。
- `categoryMemory`、`subcategoryMemory` 是同一份存储的源码兼容投影，不单独编码。旧商户字段仅解码时暂存并迁入。旧字段合并优先级为主项记忆 < 商户记忆 < 小项记忆 < 新记忆；同一旧字段内部按原键排序，避免字典遍历导致冲突结果随机。
- `Ledger.normalizedCategory(for:entriesByID:)` 统一解析 alias 与退款原账。Finance、收入分组、小项汇总、消费观／习惯、只读工具与洞察记录列表共用它；批量扫描传入索引。
- 每日批量先用统一本地猜测，再向 AI 提交剩余项；AI 只见可选分类，只有 pending 能改主项，可以只归主项而保留空小项。返回结果应用时再次校验主项与小项。
- 快选读取 `preferences.categoryOrder`，默认表顺序，缺少的自定义项补在后面；不受账目次数影响，排除隐藏项和 system。
- 问余白编辑后的草稿用可选 `EntryDraft.categoryUserEdited` 标记用户选择，再写统一记忆；自动推断的草稿不学习成用户偏好。新增可选小项字段保持旧草稿可解码。

## 迁移规则

解码 schema 1／2／3 时串接历史旧名转换与本轮拆分，最终为 4；schema 4 不重复迁移。保存前保留原始旧文件的仓库存档逻辑升为 `< 4`。

| 原路径或数据 | schema 4 |
|---|---|
| 娱乐旅行/旅行住宿 | 旅行/住宿 |
| 娱乐旅行/会员订阅 | 会员订阅，小项空 |
| 娱乐旅行/电影演出、游戏、运动健身 | 娱乐/同名小项 |
| 娱乐旅行，无小项 | 娱乐 |
| 学习工作/课程 | 学习成长/课程 |
| 学习工作/书籍、办公用品 | 购物/书和文具 |
| 学习工作/软件工具 | 会员订阅/软件云服务 |
| 学习工作，无小项 | 学习成长 |
| 小项「其他」 | nil |
| 空主项、字面「没分类」、其他支出＋旧没分类原因 | pendingCategory |
| 日用购物／日用，工资／奖金，兼职，理财收益 | 继续兼容历史迁移：购物/日用百货，工资奖金/对应小项，兼职劳务，投资收益 |
| 自定义／历史导入建出的主项 | 等名、别名、包含默认主项或小项名时并入；否则保留自定义主项 |
| 旧记忆三字段 | 归一键后合并到 classificationMemory，再改写主项与小项路径 |

保留旧主项名和拆分路径为 alias。引用改写覆盖 entries（含软删除记录）、plans、wishlist、generous／restrain 的主项与路径、记忆、aliases、快选顺序、pendingChanges 中的 setCategory／addEntry／addPlan／画像、停掉的安排快照、导入撤销快照、导入问题选项，并同步关联退款。

## Core API

`CategoryModel` 的以下操作均先改副本，再 validate 后整体写回，失败不产生部分修改：

- `add(_:in:)`
- `rename(_:to:in:)`
- `merge(_:into:in:)`
- `setHidden(_:category:in:)`
- `addSubcategory(_:to:keywords:in:)`
- `renameSubcategory(_:in:to:ledger:)`
- `removeSubcategory(_:from:in:)`
- `setOrder(_:in:)`

改名保留旧名 alias 和旧名关键词；合并只允许相同收支方向，保留来源小项与关键词。并入「其他」时清空小项。删除小项清空相应引用与记忆中的小项，并将画像中该路径提升为主项匹配；这一实现选择避免留下失效路径。system 不可改，其他支出／其他收入不可改名、作为合并来源或加小项；它们可隐藏。未提供主项删除界面或 API。

`BillImporter.commit(_:data:confirmedNewCategories:to:)` 的确认集合默认空；仅处理有选中记录的来源分类，先调用 `CategoryModel.add`，再把该来源选中记录归到新主项、清空旧小项并标记用户纠正。收支方向取该来源首笔选中记录，退款按支出方向；未选中或无对应记录的名称不创建。新建与导入共用副本事务，名称已存在（含 alias）、名称无效或后续入账失败均不产生部分修改；App 沿用 `store.update` 的错误提示路径。确认集合按队列文件保存／恢复，改点「归到」或在分类对应中改选时清除，普通对应和自动线索不能触发创建。

## 测试变更逐项说明

新增 `CategoryModelTests.swift` 26 项：覆盖默认表及旧词完整性、迁移各分支和幂等、schema 1 fixture、三份记忆解码与冲突优先级、单一未分类、猜测优先级与领域边界、正餐时间、跨入口纠正、未知捕获、导入不建主项与别名、快选顺序与隐藏、自定义 API 的引用改写和回滚、退款与统计一致性、AI 保护、草稿纠正与旧草稿兼容、兼容投影不丢小项、每日批量优先用户记忆。

收尾补 6 项（该文件合计 32 项）：明确新建覆盖旧猜测／记忆并按支出、收入、退款方向建项；仅有分类对应或改归其他时不建项；只按选中记录建项并忽略未选中／无关名称；重名、alias 冲突和无效名原子失败；重复入账失败时回滚新项；没有选中记录时不遗留新项。保留金额、性质、去重指纹及其他默认分类断言。

受影响的旧测试仅更新模型变化的期望或输入：

| 测试 | 修改与原因 |
|---|---|
| BeeCountImportTests.testLocalBOMWhitespaceFallbacksTransferAndReimport | 转账分类改为系统「内部移动」 |
| BeeCountImportTests.testCategoryOverridesPersistThroughCommitWithoutChangingSourceIdentity | sourceCategory 保留原账单「周游」，方便写 alias；显式对应、指纹及去重断言保留 |
| BeeCountImportTests.testNewCategoryAndKnownExportOverridesStayLocal → testKnownCategoryAndKnownExportOverridesStayLocal | 「旅行」已是默认项，移除手工 append；导入不再创建主项 |
| ChangeSetTests.ledger 共享夹具 | 将原本供自动整理的「其他支出」改为 pending；全部 14 项测试和金额不可变断言保留 |
| FinanceTests.testRecordedAtRoundTripsAndOldLedgersDecodeWithoutIt | 旧账解码升级为 schema 4 |
| ImportColumnTests.testMapperExtractsFirstJSONObjectFromFenceAndProse | 「职业收入」账单线索与「奖金」文字映射到工资奖金，不新建主项 |
| CategoryMemoryTests.testRememberedCategoryIsAcceptedBeforeModelAndConflictsAreIgnored | 待 AI 整理的输入改 pending，明确「其他」不再是待归类占位；提示词区分用户记忆、已有主项与表规则，不把本地推断称为用户确认 |
| LedgerSyncTests.testEmbeddedAttachmentMigratesOnLoadWithoutChangingSchemaOrLosingSource | 编码 schema 为 4，附件兼容断言不变 |
| ManualBookkeepingTests.testFrequentCategoriesIgnoreDeletedAndOtherNaturesAndFillDefaults | 固定快选顺序；先定义自定义「工作餐」再测试其记忆，记忆不能创建分类 |
| QuickCaptureTests.testLocalParserSharesAmountsAndMultipleDrafts | 无用途金额的标题使用既有显示函数得到「没分类」，存储主项为 pending |
| QuickCaptureTests.testApplePayRulesAndUnclassifiedFallback | 未知 Apple Pay 主项为 pending |
| QuickCaptureTests.testArchivedCardMappingFallsBackAndRuleReplacement | 商户规则计数检查统一记忆，仍验证旧名「日用」和账户回退 |
| Schema2Tests.testMigrationAndStableSchema2RoundTrip | 迁移与编码最终版本为 4，原稳定往返验证保留 |
| Schema2Tests.testDefaultPurchaseValuesDoNotBecomePrincipleAndNewFieldsHaveDefaults | 最终版本为 4，画像旧兼容断言保留 |
| StorageTests.testLegacyAIPreferencesDecodeAndMigrateWithoutReencodingOldKeys | 旧配置组合解码均升级为 4 |
| SubcategorySavingTests.testUnifiedCategoryTableHasTwoLevelsAndOtherForEveryMain → testUnifiedCategoryTableHasTwoLevelsWithoutAutomaticOther | 12 项默认支出，排除 system，不再自动补其他小项 |
| SubcategorySavingTests.testLegacyCategoriesMigrateEntriesMemoriesAliasesProfileAndKeepCustom | 最终 schema 4，娱乐为独立主项 |
| SubcategorySavingTests.testLocalKeywordsDontGuessMarketplacesAndRespectMainCategory → testLocalKeywordsCanGuessMainWithoutSmallItemAndRespectMainCategory | 「滴滴」自动归类输入改 pending；淘宝／京东从统一表给出主项、小项留空；明确其他的保护另有新回归 |
| SubcategorySavingTests.testBatchChunksAllRowsAndLogsRedactedAllowlistedPayloadOncePerDay | 161 笔待整理输入改 pending，保持三段请求与脱敏验证 |
| SubcategorySavingTests.testBatchStrictJSONRejectsUnknownDuplicateCrossCategoryAndWrongIncome | 错误收入方向场景改用 pending，确保仍真正进入 AI 校验 |

## 验证与界面边界

上一轮验证：`swift build --target YubaiCore` 通过；`swift test` 共 490 项，486 通过、4 项原有实网测试跳过、0 失败，新增 CategoryModelTests 26 项全部通过。`git diff --check` 通过。使用既有 Swift 6.2 工具链；沙盒 `/root/.cache` 只读，设置 `CLANG_MODULE_CACHE_PATH=/tmp/yubai-clang-cache`、`SWIFTPM_MODULECACHE_OVERRIDE=/tmp/yubai-swift-cache` 后执行指定 build／test；没有改 HOME 或项目依赖。

收尾验证：沿用上述缓存环境，执行 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，共 496 项，492 通过、4 项原有实网测试跳过、0 失败；CategoryModelTests 共 32 项全过（本次新增 6 项）。改动的 ImportView／CaptureNotifications 在 iOS 26／27.1 模拟器 DEBUG、iOS 26 设备 Release、macOS 14 DEBUG 四组条件下语法解析通过；人工核对 Core 参数顺序／`Set<String>` 类型、Button／Binding 闭包返回、逐文件确认状态保存／恢复／清除及既有错误提示链，未发现 Xcode 编译接线问题。Linux 没有 Apple SDK，实际 Xcode 类型检查与 UI 实跑仍待 Mac；`git diff --check` 通过，未提交 Git。

- 新测试已登记 Xcode 的手工枚举测试 target；Core 作为本地 Swift Package 自动包含新源码。
- App 全部 38 个文件在 iOS 26、iOS 27.1、macOS 14 DEBUG 条件下语法解析通过；Core 参数标签、类型、可选性人工核对。语法解析不代替 Apple SDK 类型检查。
- Tests/YubaiUITests 已检查：未发现依赖次数排序或「其他支出」缺省的断言。`testSubcategoryScreenshotFixture` 的「其他」是空小项的现有展示，保留并让下钻匹配归一后的 nil；`testLedgerMonthFiltersAndSearchToggle` 的已分类夹具与 0 笔没分类期望不变。UI 测试条件解析通过，Linux 无法实跑。
- 文案债务（同日收尾已处理）：导入原有「新建「X」」按钮文字保留，明确点击后在提交时实际创建并归到 X，自动流程无法映射仍 pending；Apple Pay 通知仅将「先放在 其他支出」替换为状态「没分类」，原有格式与句式不变。已扫描 Sources 的「其他支出」及相关“先放在／放入／暂放”表达，未发现其他声称未知记录放在其他支出的可见文案；没有新增界面元素或可见错误字符串。
- 数据驱动的分类标题按 owner 新表显示；其中新增独立主项为「娱乐」「旅行」「会员订阅」「学习成长」，小项新增／改动为「住宿」「门票游玩」「跟团包价」「影音会员」「软件云服务」「其他会员」「考试证书」「兴趣爱好」。它们都是分类标题；旧表「娱乐旅行」「学习工作」「旅行住宿」「书籍」「软件工具」「办公用品」作为独立标题退出默认表，仍保留迁移与别名兼容；自动附加小项「其他」退出分类表，洞察中空小项的既有显示不改。未知状态继续显示既有「没分类」。
- 新 Core API 错误信息（原因／状态，尚无新界面入口）：分类名称无效、这个分类不能修改、分类名称已存在、只能合并同一收支方向的不同分类、小项已存在、小项不存在或名称重复、小项不存在、分类顺序无效。现有校验错误去掉“需要保留其他”限制；新增快速捕获无效分类提示「请选择已有分类。」、批量响应校验「小项格式无效。」。不属于说明文案；只在失败时返回原因。

风险：Apple SDK 真编译与 UI 实跑待 Mac；schema 4 保存后旧 App 不支持降级读取，升级前原始文件仍按仓库存档机制保留；旧词／别名映射按规则确定，未使用真实账单证明分类准确率。设计稿、原型、分发包没有同步，本轮没有修改视觉。

## PR #41 · Xcode 27.1 编译修复与 App 复核

2026-10-26，owner 报告 `SubcategoryViews.swift:102:22: cannot find 'store' in scope`。这纠正了上文人工接线检查的遗漏；此前 Linux 条件解析通过不代表 SwiftUI 类型检查通过。本轮沿用 `refactor/category-model` 当前工作区，不改 Core、工程、依赖、视觉、文案或行为，不提交 Git。

范围通过 `git diff origin/main --stat -- Sources/YubaiApp Sources/YubaiWidgets` 确认：全部 8 个 App Swift 文件，Widgets 无 PR 改动。逐处核对修改及其所属类型的 store／环境声明、Core 参数标签与顺序、可选性、返回类型、访问级别、actor／Sendable 边界与表达式推断。

| 文件 | 复核内容与本轮修改 |
|---|---|
| `SubcategoryViews.swift` | `EntrySubcategoryRow`、`SubcategoryPicker`、记录下钻均已有 store。唯一缺失的是 `SubcategoryChoiceChip.selected`；父视图现在一次取得显式 `CategoryAssignment`，用原来的主项与小项比较式算好 `Bool`，芯片仅接收 `sub`、`selected` 和保存闭包，不新增环境或 store 注入。选中样式、无障碍 selected trait、保存／关闭路径保持。复核 `selectableCategories`、两种 normalizedCategory 调用及 resolveCategory 的返回类型。 |
| `AskYubaiView.swift` | 编辑草稿类型已有 store／dismiss，`categoryUserEdited` 为公开 `Bool?`，清小项与写用户纠正标记的顺序保持。将分类 selection 拆为 `Binding<String>` 属性，分类列表拆为 `[String]` 属性，保留 Set 去重、排序、当前分类及 Picker tag。 |
| `ImportView.swift` | 主视图与截图编辑器均已有 store。逐处核对 CategoryMapping 的可选结果、isPending 重载、分类列表的 including／income 标签、确认集合的 Set<String> 类型、按钮／Binding 的 Void 返回、队列保存／恢复及改选时清除确认的接线。commit 参数依次为 preview、data、confirmedNewCategories、to，抛错同步交给 store.update；返回 ImportBatch，再由原 MainActor Task 整理。本轮给对应 Picker 写明 `Binding<String>`，提前计算 `[String]`，截图编辑器分类数组拆为显式类型属性。 |
| `InsightsView.swift` | FlowRecordsView 已有 store。退款／收入归一读取 `normalizedCategory(for:entriesByID:)` 的非可选 CategoryAssignment.category；categories.contains 的闭包返回 Bool。为索引、记录数组、收支判断与分类名分别写明 `[UUID: Entry]`、`[Entry]`、`Bool`、`String`。 |
| `ProfileView.swift` | ProfileAreaEditor 已有 store；selectableCategories 为公开 `[YubaiCore.Category]`，income 为 Bool，元素满足 Identifiable，Toggle 的 Binding 与 Set<String> 更新匹配。不需修改。 |
| `QuickCaptureSettingsView.swift` | 主视图、规则列表与编辑器各自已有 store，编辑器另有 dismiss。classificationMemory 为公开 `[String: String]`，字典读取得 String?，resolveCategory 得 String，原 flatMap／map 链和默认值类型相符。cardKey 为公开 String → String，remember 的 merchant／category／in 标签及 throws 与 update 相符。未新增跨 actor 捕获，不需修改。 |
| `CaptureNotifications.swift` | PR 改动仅为既有 category 局部值中的状态字面量，不引用 store／环境；hasNoCaptureCategory 为公开 Bool，另一路 displayCategory 返回 String。原委托使用 MainActor Task 访问 AppStore，通知异步边界没有本轮新增捕获；不需修改。 |
| `SyncVersionsView.swift` | 分类规则比较两份公开 `[String: String]`，相等比较返回 Bool，三元结果为 Int。本轮把大数组与 filter 分开，为数组写明 `[(title: String, count: Int)]`，使用具名 count 过滤，原顺序、标题、数值不变。 |

`CategoryAssignment`、`CategoryMapping.match`、`QuickCapture.cardKey`／remember、BillImporter.commit 和相关模型字段均可从普通 `import YubaiCore` 访问。selectableCategories、categoryNames、normalizedCategory 在 `public extension Ledger` 中，访问级别为 public，无须再添加冗余修饰。App 内新 helper 留在所属 private 类型中，没有扩大可见性。

验证：

- `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0：496 项、492 通过、4 项原有实网测试跳过、0 失败。沿用 `/tmp/yubai-clang-cache` 和 `/tmp/yubai-swift-cache` 两个缓存环境变量；没有启用实网测试。
- 38 个 App 文件与 1 个 Widget 文件逐一通过 `swiftc -frontend -parse -swift-version 5`，共 156 次解析：iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug。Swift 5 是当前 Package／Xcode target 的语言模式；Debug 组显式设置 DEBUG。
- 临时 `/tmp/yubai-pr41-api-audit.swift` 使用普通 `import YubaiCore`，没有 `@testable`。分类列表、归一／匹配、草稿纠正、统一记忆、导入 commit、小项保存的调用以显式类型交给真实已构建 Core 模块检查，`-swift-version 6 -strict-concurrency=complete -warnings-as-errors` 类型检查退出 0；同时用泛型 Sendable 约束检查 Ledger、Entry、EntryDraft、ImportPreview、ImportBatch、CategoryAssignment、分类数组、确认集合与记忆字典。此项只证明相关 Core 调用与值类型，不包含 SwiftUI 或 Apple 通知模块。
- `git diff --check` 通过。没有新增或改动可见中文字符串，没有更改布局、样式、按钮动作或数据处理规则；原稿／原型／分发包不需同步本次内部接线修正。

当前 Linux 无 Apple SDK，仍须在 Mac 上重新执行 Xcode 27.1 App 真编译；SwiftUI 类型检查和 UI 实跑尚未验证。本轮没有把条件语法解析或 Core API 检查计为 Apple 编译成功。
