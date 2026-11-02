# 余白 · 设计约定与资源登记

## 2026-10-29 · 第二十五轮「整理完剩下的」

来源为 owner 本轮已确认的三张第二十五轮页面稿，上一轮整理中页面只作参照。本轮仅在本机只读核对，未复制原稿、私有地址或设计链接；不增加依赖、不提交。

现在页的导入问题采用纵向 amber 卡片，具体问题在前、兜底在后；问题标题、日期／对方事实及选项直接呈现。原工资、待整理和其他管家卡继续用原分页。Core 的 answerQuestion 排在 unknownInflow 前，问题覆盖 ID 使用完整集合去重，不受卡片 evidence 的 1000 笔上限影响。至少两张未覆盖的有效进账提醒折成 raised 底、最小 44pt 行「N 笔进账没说来源／稍后」，点开复用 ButlerListView 与原卡片，读取完整队列；一张保留原卡。折叠在五张窗口之前完成，避免被折叠的提醒占掉提问名额。

ImportQuestion 新增可空 groupsByParty 标记，无需提高存档 schema；缺字段可解码，旧标题以「其余这」开头且两个选项精确为「都是日常收支／稍后写用途」也识别为兜底，旧批量答案和自由补充均不再允许直接应用。新兜底只保存原覆盖 ID，选项为空；跨段合并保留同一问题 ID，将具体问题留在前四张，其余合入一个兜底。标题在界面按实时记录数显示「N 笔还没分类」，归类、删除、关联或已确定特殊性质的记录退出；零笔隐藏，撤销后重新出现，不永久删覆盖或标记卡片已完成。导入结果页也使用同一兜底卡，问题数排除已清空兜底。

UnsortedGroups.swift 为纯函数：按原始 title 的「 · 」前半部和收支方向分组，笔数降序、相同笔数按稳定 ID 排序；组内日期倒序、同日按 UUID 排序。它只读兜底覆盖且仍待整理的有效记录，不修改金额、日期或原始文本。按对方分页使用 ScrollView／LazyVStack／CardRows，一张列表卡内逐行展示，搜索仅匹配对方，顶部计数始终为全部剩余记录。普通提问页改为外层 LazyVStack 和 Set 查找，CardRows 的 ForEach 每个 ID 固定一个行容器，避免为条件分隔线预建所有行；样式和分隔线保持。

一组页复用衬线 quote 标题、SuggestionChip、PrimaryButtonStyle(compact:) 与 AmountLabel，展示最多四笔日期／金额；普通收支才出现该方向可选主项，无选择或未选分类时禁用确认。特殊选项不要求分类。确认从当前账本重取组，只生成一个 ChangeSet，经 AppStore.apply 保存一次，并记录整批撤销差量，沿用已有撤销及版本留存，然后返回列表。各控件均有 accessibilityIdentifier。

对稿取舍：遵守不新增视觉样式，顶部数字用现有 amountLarge（30pt，原稿为34pt），其余字号、页边距、卡片和芯片都取现有 token／组件；原稿示例中个别行笔数并非严格递减，实现依 owner 明确要求按笔数降序。标准导航与原有其余卡片分页保持；本轮导入问题纵排。模型的 transfer 是转出方向，本轮选「转给自己」后要求选择未归档、且不属于本组任何原账户的另一个账户，无可选账户就隐藏该选项；进账转账按转出形式保存，但严格校验原进账账户的金额、方向、入账日均不变，不生成虚构记录。此选择也防止同组跨账户时选到某笔自己的原账户。

本次新增或改动的可见中文：标题「按对方分」「一组」「这些钱是」「分类」「转到哪个账户」「最近几笔」；数字事实「N 笔还没分类」「笔还没分类」「N 笔」「N 笔 · 合计金额」「N 笔进账没说来源」及日期、对方／账户／分类名称和带符号两位金额；控件「搜对方」「日常支出」「日常收入」「买基金」「卖基金」「转给自己」「还款」「借给别人」「收回借款」「这 N 笔都这样记」「都不是」「稍后」和原问题选项。批量完成提示复用既有状态「整理完成」和撤销入口。兜底旧问题与两项旧选项不再显示；新页面无说明句。所有字属于标题、数字事实、控件或状态，无额外文案例外。

工程：UnsortedViews.swift 已登记 App target，UnsortedGroupsTests.swift 已登记 Xcode Core 测试 target；UnsortedGroups.swift 由本地 Swift Package 的 YubaiCore target 自动收录，与其余 Core 文件相同。

验证：指定命令 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出0，599项、595通过／4项原有实网opt-in跳过／0失败，新增9项Core测试覆盖旧数据、跨段合并、收支拆组、分类门槛、所有性质、双向转账、完整覆盖去重、零笔隐藏及4,200笔分组。新增2项UI测试源码覆盖首页顺序／折叠去重和按对方分→日常支出→选分类→确认→组数／剩余数减少并重启持久化。全部App源码通过iOS26模拟器Debug、设备Release、macOS14Debug条件语法解析，UI测试通过模拟器Debug解析；完整UITestSupport／UITestTransport和提取的实际store.apply、applyUnsortedGroup方法以Swift6严格并发离线编译执行，使用持久化替身核对2张问题先于6笔未覆盖进账、9笔／2组→一次apply→3笔／1组、磁盘与恢复版本、清零隐藏及整批撤销通过。该替身不代替完整AppStore或Apple SDK类型检查。Apple SDK 编译、XCTest UI 实跑、VoiceOver／深色／大字号及4,200笔真机滚动仍待 Mac，条件语法解析和离线夹具检查不代替这些验收。原稿保持只读，外部画布、截图和分发包未同步；未提交、未推送、未调用 DeepSeek 或任何付费 API。
## 2026-10-29 · 小项截断与账目搜索卡顿修复

来源为 owner 在 `fix/subcategory-truncation-ledger-hang`（基于 `main e6eff03`）提供的 4,200 笔 DeepSeek 导入反馈与 Mac `hang.sample.txt`。本轮只修行为和性能，不采用新设计，不改业务分类规则、外观、可见文案或操作入口。

小项原每段 80 笔、沿用默认 4096 输出 token 且没有禁用默认思考，思考与 JSON 共用预算。`Subcategories.swift` 改为每段 40 笔，预算 `512 + 条数 × 128`（整段 5632），注释列明 UUID／主项／小项与 JSON 外壳估算；显式 `thinking: false`，用 `JSONValue.parseModelResponse` 接收围栏 JSON，原字段白名单、分类校验、取消及整轮原子应用保持。

已遍历 Sources 的全部 ChatRequest 构造及通用 chat 调用：

| 调用 | 本轮处理 |
|---|---|
| `SubcategoryBatch.run` | 上述分段、预算、禁用思考及共享解析 |
| `AIImportColumnMapper.map` | 禁用思考；保留足够容纳列索引对象的 4000 预算，改用共享解析后解码 |
| `ButlerWording.word` | 禁用思考；最多 12 张、每张 14 字标题／60 字正文，按 `256 + 张数 × 256` 预算；共享解析 |
| `MemoryReflection.run` | 禁用思考、共享解析；保留显式 4096，用于选择性记忆提炼，不要求逐笔返回输入账目 |
| `ImportOrganizer.organize` | 已有每段最多 30 笔、6000、禁用思考及共享解析，保持 |
| `AssistantAgent` 主循环／金额核对 | 工具推理与自然语言答复，不是要求逐项 JSON 的批量任务，保持 |
| `AskYubaiSession` 对话摘要 | 800 的纯文本摘要，保持 |
| `CloudBackend.reflectPurchase` | 450、禁用思考的纯文本，保持 |
| `DeepSeekClient.chat` 及洞察文字／搜索扩展／连接测试调用 | 通用方法转传预算与 thinking；三个调用已分别显式设置 220／80／64 和禁用思考，均非批量 JSON，保持 |

账目页原在 `body` 每次执行月筛选、两次 timeline 分组及搜索金额格式化，每行又携带包含导入来源等元数据的完整 Entry；懒列表的 ForEach 还为每项产生行与条件分隔线两个可变子项。这些成本与 sample 的 LazyStack 布局／Entry、LedgerEntryRow 复制热点吻合，实际 Mac 修复效果仍待复验。`ManualBookkeeping.swift` 增加纯输入的 `EntryTimeline.snapshot`，保持旧搜索字段、金额匹配、月总额不随筛选变化及房租个人份额／退款口径；行只投影 UUID、金额、收支／分类状态、分类名、备注和图标。`AppStore` 用不参与观察的缓存保存结果，以月份／搜索词／筛选／日历为键，在每次账本替换时失效，不依赖 updatedAt；`EntriesView` 只读取快照，行的隐藏金额／新行状态由父级传入。日期与 UUID 原稳定 ID 保持，CardRows 将行与原分隔线包在零间距 VStack 内，每项固定一个子容器，继续使用原行高、分隔线、transition 与动画参数。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出 0；595 项，591 通过／4 原有实网 opt-in 跳过／0 失败。新增 5 项 Core 测试，覆盖 4,200 笔搜索的 1400 个匹配、全部筛选／带符号金额与旧 timeline 一致、月汇总、稳定 ID、只读输入／快照、账户与分类变化、房租／退款、月界与显式时区，以及整批卡片和每周回看的 thinking／预算／围栏解析。现有小项多段测试改为 40 笔分段并验证预算／thinking／围栏回复，保留失败原子性与敏感信息检查；列识别 HTTP 测试补禁用思考断言。

三份 App 改动通过 iOS 26 模拟器 Debug／设备 Release、macOS 14 Debug 条件语法解析；提取实际 AppStore 缓存属性／方法，隔离平台发布桥后，以 Swift 6 严格并发编译并链接 Core 离线执行，4,200 笔下一万次命中复用数组存储，月份／搜索／筛选和相同时间戳的账本替换失效均通过。Linux 内存布局 Entry 为 497 字节、行投影为 80 字节。此检查不代替完整 AppStore／SwiftUI Apple SDK 编译或实际滚动测试。Apple 编译、Mac 搜索「5.00」后滚动、手势／动画及视觉复验待做；原稿／Figma／分发资源保持。新增／改动可见中文字符串：无。未提交、未新增依赖、未调用 DeepSeek 或其他实网 API。

## 2026-10-28 · 第二十四轮大量流水导入界面

来源为 owner 本轮明确确认的第二十四轮文字规格，在 `fix/large-import-organize` 的 `5409003` 上续作；未附独立 HTML／图片或私有原稿链接。继承上一轮认工资、错误映射、逐段保存与已完成 ID 记录，本轮完成范围选择和整理状态界面。

`ImportPreview` 在 `Import.swift` 公开 `recentThreeMonthsStart` 与 `selectingEntries(onOrAfter:)`：以完整有效记录的最晚时间往前推三个公历月，仅最早时间严格早于阈值时提供范围选择；阈值包含在最近范围内。筛选只在副本取消范围外行的勾选，不重新选中手动取消或重复行，不改变 `latestBalance`。`WelcomeView` 在已导入行上方显示双行两段控件，neutralSoft 底、选中 raised 底与共用 knob 轻阴影，默认最近三个月，数字千分位；辅助功能字号改纵排。摘要和提交沿用所选副本，核对 sheet 只显示当前范围并按行 ID 合回勾选，切换范围保留范围外原选择。余额、锚点与保存的完整原件仍来自原始流水。`ImportView` 源码及其导入页保持，不增加范围控件。

`PendingImportsCard` 标题沿用每段保存后刷新出的剩余计数，账户／完整批次日期范围保持。整理中替换原转圈与按钮区：6pt neutralSoft／brand 进度、圆角 3；下行 13pt 数字字体／labelSecondary 的千分位已整理／总数、12pt labelSecondary 提醒、raised 底 36pt「停下」（触控至少 44pt）。空间不足时进度数字与提醒／停下分行。进度 AX 标识 `organizeProgress`、value 为无空格的数字 `completed/total`，停止标识 `stopOrganizing`。失败原文放到详情之后、按钮之前，13pt amberInk，移除开头的「记录已保存。」时不改其余原因，标识 `organizeError`；按钮保留「整理」「自己分」。若原错误对应云端不可用，再点整理进入既有智能设置，配置恢复后仅发送剩余记录。

`AppStore` 持有待整理任务与当前批次任务，停下取消两者；直接调用 `organizeImport` 的父任务取消也会传到子任务。取消不写失败原因，已持久化的段保留；保存前在 MainActor 再检查取消。待整理运行的总数汇总全部批次可整理 ID，批次之间不重置分子／分母；导入页单批次调用仍独立计数。失败原因继续用上一轮 `ImportOrganizer.failureMessage`，不更换错误映射或已完成 ID 规则。

新增可见中文仅「最近 3 个月」「全部」「N 笔」「停下」「整理时别离开余白」。前两项与停下为控件，N 笔与进度为数字事实；既有「已导入 N 笔」「N 笔还没分类」仅随范围／保存更新数字，失败原文复用已有文案。提醒是 owner 本轮明确指定的稿内文字：删除会丢失整理期间的前台要求，分组／字重不能表达该要求，进度数字与停下控件也无法表达；已限于整理发生时显示，故按本轮确认稿保留这一句，不增加其他说明。

测试沿用现有工程已登记的 `ImportBalanceTests.swift`、`AppFlowTests.swift`，没有新增 Swift 文件。新增 5 项 Core 覆盖跨年计数、严格三个月边界／空与单行、月底与闰二月、手动／重复勾选保留、两范围提交后的账目数／余额锚点／完整原件。扩展严格门控的 salary／welcome-import 脚本：70 笔、30＋30＋10 三段；第二请求可持续等待取消或抛出既有 HTTP 503 原文，重试时延迟回复便于观察进度。新增观察值仅在显式测试开关或整理场景下包含真实账目数／已分类数／重发已成功 ID 数，原脚本的 `requests=N` 保持。

新增 UI 测试（源码，未在 Apple 平台实跑）：

- `testWelcomeAnnualStatementDefaultsToRecentThreeMonthsAndCommitsSelectedCount`：一年 13 笔，默认最近 4 笔、切换 13 笔、范围内手动勾选跨切换保持、余额固定 1234.56，提交／重启后实际账目数为 4。
- `testWelcomeAnnualStatementAllRangeCommitsFullCount`：相同流水选择全部，提交／重启后实际账目数为 13。
- `testPendingImportsStopKeepsCompletedChunkAndRemainingCount`：30/70 进度、停下、剩余 40，30 笔已分类与重启持久化。
- `testPendingImportsSecondChunkFailureShowsReasonAndRetriesOnlyRemaining`：第二段失败原文、剩余 40、详情不变，再点整理的分母 40／中途剩余 10；总请求 4 次且不重发已完成 ID，完成／重启不再出现卡片。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出 0，584 项、580 通过／4 原有实网 opt-in 跳过／0 失败。改动 App 文件通过 iOS 26 模拟器 Debug／设备 Release、macOS 14 Debug 条件语法解析，UI 测试通过 iOS 26 模拟器 Debug 条件语法解析。另提取实际任务方法、实际 `ActiveLedgerTransport` 与 `UITestSupport`，移除平台门控后以 Swift 6 严格并发类型检查，并链接 Core、配持久化替身离线执行：停下保留 30／剩余 40、HTTP 503 后只重试 30＋10、无已完成 ID 重发、多批次 0→30→45→70 且分母始终 70、直接调用父任务取消传递均通过。该替身不代替完整 AppStore／Apple SDK 类型检查或 XCTest UI 实跑。`git diff --check` 通过；Apple 编译、AX／VoiceOver、字号与视觉验收待 Mac，Figma／截图／分发资源未同步。未提交、未推送，未调用 DeepSeek 或任何付费 API。

## 2026-10-28 · 第二十三轮固定收付「以后」

来源为 owner 本轮明确确认的第二十三轮文字规格；未附独立 HTML／图片或私有页面链接。此轮扩展第十一轮仅显示当月期次的边界，原月内要付／要收、逾期及还能花算法保持。

`FixedFlows.swift` 为 `FixedFlowMonth` 增加 `later: [FixedFlowUpcoming]`，包含 Plan ID、标题、金额、收支方向、频率、下一期及原排期锚点。只纳入 active、未停掉、仍有未来期且本月无任何排期的 Plan；本月已收付或跳过的期也阻止重复。下一期复用 `Plan.scheduledDate`，遵循分期数、结束日期、跳过及 monthlyDay 的月底夹取；无 90 天截断。按下一期日期、同日 Plan ID 排序，金额复用估额规则，独立于当月汇总。`ManualBookkeeping.swift` 的既有频率文案补可选 monthlyDay，旧调用保持；`Models.swift` 恢复到 HEAD，scheduledDate 保持原可见性。

`FixedFlowsView.swift` 在要收之后、已停掉之前采用同一 `CardRows` 卡片与内分隔线，基础行高 52pt，次行用 13pt callout／labelSecondary；实际字号放大可撑高。进账 brandInk 带 +，支出 label，金额固定两位，行尾无操作按钮，保留 36pt 空位。有以后内容即隐藏月空态。分组标识 `fixedFlowLater`、行标识 `fixedFlowLater_<planID>`；分组含标题与行，分别保留 AX 容器。

owner 同日跟进明确收窄范围：现有 App 没有编辑安排页面，编辑页设计未经确认，本轮不加。撤回上一轮自行新增的 `AppSheet.editPlan`、`FixedFlowEditor(original:)` 及初始化／保存分支、本月行 summary 点按；`YubaiApp.swift`、`FixedFlowBillRow` 与完整 `FixedFlowEditor` 均恢复到 HEAD。表单的 monthlyDay 排期文案参数和 scheduledDate 预览也一并撤回；添加场景没有原工资锚点可复用，沿用原添加行为。「以后」行仅展示，移除 onTapGesture、contentShape 与 isButton trait，保留内容、布局和 AX 容器／标识。

新增／改动可见中文：标题「以后」；事实「每月N日」「每年M月D日」「X月X日起」「明年X月X日起」，组合为「频率 · 日期起」。其他频率复用既有「每周X」「每季N日」和一次性日期文案，仅按稿收紧空格；安排名复用原标题。均为标题、日期／频率事实，无文案例外。本次收窄不新增可见中文，添加表单标题恢复「添加」（标题），其余可见文字保持。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出 0，561 项、557 通过／4 项原有实网 opt-in 跳过／0 失败。新增 9 项 FixedBillsTests 覆盖下月工资、月内已付／未付／未到／跳过去重、停掉／结束／期数耗尽、次年与同年年费、日期排序、31 日跨短月／闰二月、其他频率及未来跳过边界。本次收窄后重新执行同一完整命令，退出 0，仍为 561 项、557 通过／4 项原有实网 opt-in 跳过／0 失败。对照 HEAD 确认编辑表单、本月行、App 路由、Models、salary 夹具与其余全部 UI 测试保持原样。改动 App 文件通过 iOS 26 模拟器 Debug／设备 Release、macOS 14 Debug 条件语法解析，UI 测试通过 iOS 26 模拟器 Debug 条件语法解析；`git diff --check` 通过。另从实际未改动的 salaryLedger 提取夹具方法，链接当前 Core 离线执行 2026 年及闰年 2028 年全部 731 个日历日，验证工资识别／确认后在 10 日前进入要收、10 日及之后进入以后且不重复。该检查验证夹具与 Core 分组，不代替 Apple UI 实跑。

新增 `testConfirmedSalaryAppearsInFixedFlowsLaterGroup`：salary → 是工资 → 既有固定收付入口。沿用未改动的 salary 夹具与公历／模拟器时区：当月 10 日及之后，断言以后组工资一行、+8,000.00、每月10日、要收无工资，并检查点击后仍在固定收付且未打开表单；10 日前，断言要收卡片工资一行、+8,000.00、10 日排期，以后无工资且分组不显示。两支都无月空态；撤回打开编辑和保存的测试断言，原工资确认／撤销等用例保持。UI 未实跑，Apple SDK 编译、AX／VoiceOver、视觉与手势待 Mac 复验；Figma、截图与分发包未同步。未提交、未推送、未调用 DeepSeek 或任何付费 API。

## 2026-10-28 · PR #48 现在页卡片无障碍容器修复

按 owner 提供的 iOS 26.5 层级现象，对比 `main` 的 `ButlerSection` 与本分支 `NowCardsSection`：main 直接呈现带 `.contain`／`butlerCard_<kind>` 的卡片；本分支外层又加 `.contain`／`nowCards`，非当前页则隐藏于 AX。[SwiftUI 的 `.contain` 规则](https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/contain)明确，唯一子元素已有子项时会复用该元素，而不创建新父容器。结合层级中只剩 `nowCards`、内部按钮／文字仍在的现象，原因是当前卡片容器被外层复用并覆盖标识，而非测试查错元素类型；只移动 offset／opacity 或重复加 `.contain` 不能保证独立节点。

`NowActionCards.swift` 在原 ZStack 上叠加独立的页码 AX 元素（透明、1pt、不参与布局或触摸），使外层始终有「当前卡片＋页码」两个 AX 子元素，按上述规则创建独立的 `nowCards` 父容器。工资／待整理／管家卡原有 `.contain`、标识、按钮、动作及测试值保留；非当前卡继续隐藏于 AX。外层显式设置页码 value，保留「下一张卡片／上一张卡片」动作。原源码未单独设置 `nowCards` value，复用节点上的 `closed`／`requests=0` 属于卡片测试值，修复后留在相应卡片。卡片内视觉页码不再单独导出 AX，由分页层统一朗读同一页码事实；`ButlerViews.swift` 仅相应隐藏视觉页码的 AX。原卡片尺寸、offset／opacity、动画、手势门控与滑动阈值保持。

四项管家测试的 `descendants(matching: .any).matching(identifier: "butlerCard_restrain").firstMatch` 与 main 一致；待整理／工资测试沿用同一查询方式，无需调整。所有既有测试源码保持，未放松断言。新增／改动可见中文字符串：无；仅调整原有页码事实的 AX 归属。

验证：设置 `YUBAI_LIVE_EVAL=0` 后执行 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test`，退出 0，552 项、548 通过／4 项原有实网 opt-in 跳过／0 失败。两份改动 App 文件通过 iOS 26 模拟器 Debug／设备 Release、macOS 14 Debug 条件语法解析，UI 测试通过 iOS 26 模拟器 Debug 条件语法解析；main 查询对照及 diff 检查通过。Apple SDK 编译、六项原失败 UI 测试及工资翻页用例、实际层级／VoiceOver 仍须 Mac 复验，不能把语法解析当作 Apple 类型检查或 AX 实测。选定稿、Figma、截图与分发包保持；未提交、未推送、未调用付费 API。

## 2026-10-28 · 第二十一轮工资与整理入口

来源为 owner 本轮明确确认的第二十一轮逐项文字规格；未附独立 HTML／图片或私有原稿链接。本轮直接按文字规格实现，继续遵守少写字，不将条件语法解析视为原生视觉验收。

| 源码 | 采用行为 |
|---|---|
| `SalaryDetection.swift`、`Models.swift`、`Finance.swift` | 本机纯函数按付款方、26–35 日间隔、日号偏差不超过 3 日和中位数金额 ±10% 识别；月底按当月天数夹取，众数平票取较晚日。只认未删除、截至当前的 income，最近金额最大者优先；已有 active 每月收入 Plan 则不提示。拒绝 key 作为账本集合持久化，旧账缺字段为空，不提升 schema。确认创建「工资」Plan，金额／账户取最近一笔，优先工资收入分类、否则其他收入；下次日期严格晚于今天。可空 `monthlyDay` 保留 31 日锚点，首次 2 月 28 日后仍排 3 月 31 日，旧 Plan 缺字段保持原排期。 |
| `PendingImportOrganization.swift` | 汇总未撤销且 needsOrganization 的批次；条数采用仍可整理的未手改记录，加上手改后仍没分类的记录；删除记录不计入。账户按批次顺序去重，日期范围汇总全部有效记录。 |
| `NowActionCards.swift`、`ButlerViews.swift`、`OverviewView.swift` | 还能花／目标行下的同一容器按工资、待分类、既有管家卡排序；横向翻页、右上页码、非当前卡隐藏于 AX，保留 DS 字体／颜色／动效。工资底色 brandTint、标题 serif 16、事实 13／日期 12、金额 num 15 两位小数、按钮可见高 36／触控高 44。确认用 store.update 整本撤销，指定提示条；拒绝不再提醒该付款方。单独工资卡左滑本次隐藏，多卡横滑翻页；无障碍另有本次收起动作。既有单张管家卡保留原收起手势，多卡翻页时用原菜单收起；隐藏缺口卡不提前触发触觉反馈。 |
| `EntriesView.swift`、`YubaiApp.swift` | 「自己分」进入账目并选没分类，月份定位到最新未分类导入记录（无则最新导入日期）。复用智能与隐私 sheet、关闭按钮和根页撤销条；欢迎阶段不要求先有账户。 |
| `DesignSystem.swift`、`CloudAssistantViews.swift` | Welcome leading 为 cloud＋云端智能（15pt label），已启用并配好时附 brandInk 勾，读屏「已开」；trailing 恢复备份保留。设置沿用既有钥匙串保存与 ledger.preferences.cloudAIEnabled，无 onboarding 限制；欢迎、云端未开或有待整理批次时不自动取模型列表。 |
| `IntelligenceRuntime.swift` | 删除根页前台 organizePendingImports task；同名方法只供现在页「整理」点击，逐批调用 organizeImport，期间 ProgressView、失败保留卡片。待整理批次存在时，仅在自动小项归类／记忆回看各自入口跳过云端任务，卡片润色传 nil transport、沿用本机候选文案；ButlerCards.detect、每周来信本机候选与 ButlerCards.refresh 照常执行，防止这批流水绕过点击发送，同时保持本机提醒刷新。保留导入页「现在整理」与用户提交导入后两处调用；没有其他后台导入整理调用。 |
| `UITestSupport.swift`、测试、工程 | 新增 `salary`：一个账户、最近三个月每月 10 日 8,000.00、90 天日常支出、一个 needsOrganization 批次；提供本机 fake 回复。现有 Debug 模拟器＋UUID 账本＋脚本门控保持，零请求断言只在测试 AX 暴露。App 新文件与 Core 测试新文件已登记工程；Core 源码沿用本地 Swift Package 自动发现。 |

本轮新增／改动的可见中文：标题「这是工资吗？」「N 笔还没分类」；控件「是工资」「不是」「打开云端智能」「自己分」「整理」「云端智能」「撤销」（沿用）；事实「每月 N 日」、付款方／账户名、「N 个账户」、日期范围／最近日期、正向金额和页码；状态「工资已加到会回来的账单」；Plan 标题「工资」。既有「到 X月X日发工资」随资金期限显示，未新增该模板。勾为图标，「已开」仅用于读屏。错误原因沿用现有整理错误，不新增说明句或文案例外。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出 0，552 项、548 通过／4 原有实网 opt-in 跳过／0 失败，其中 SalaryDetectionTests 14 项。App／UI 的 iOS 26 模拟器 Debug、App 的 iOS 26 设备 Release／macOS 14 Debug 条件语法解析通过；实际 UITestSupport 去平台外壳后通过 Swift 6 严格并发类型检查，离线执行 4 个日历时点的 salary 夹具校验、确认前后资金及 fake 导入整理通过。工程引用、链接与 diff 检查通过。新增 5 项 UI 测试源码覆盖确认／撤销、拒绝后重启、待分类卡翻页及设置零请求／手动筛选、fake 点击整理／重启、欢迎偏好跨建账保留，尚未实跑。Apple SDK 类型检查、UI／视觉、VoiceOver、字号与手势设备验收待 Mac；原稿／Figma／截图／分发包未同步。未提交、未推送、未调用 DeepSeek 或任何付费 API。

同日本机刷新回归小修验证：设置 `YUBAI_LIVE_EVAL=0` 后按要求运行 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test`，退出 0，552 项、548 通过／4 原有实网跳过／0 失败，包含现有 nil transport 本机文案兜底测试。Linux 不编译 AppStore，本次不新增无法覆盖实际入口的 Core 测试；49 份既有 Core／UI 测试源码与本次修改前哈希一致。改动 runtime 通过 iOS 26 模拟器 Debug／设备 Release、macOS 14 Debug 条件语法解析，UI 测试通过 iOS 26 模拟器 Debug 条件语法解析；UI 实跑与 Apple SDK 类型检查仍待 Mac。同步修正上表与产品票的行为记录；新增／改动可见中文字符串无，未提交／推送，未调用付费 API。

## 2026-10-28 · 最近用途短芯片 M6 修复

来源为 owner 的 Mac 验证 M6 FAIL：两个长用途与「午饭」同排时，原同比压缩使短芯片只显示「午」。按本轮明确要求，`ChipRow.arrangement` 改用 `YubaiCore.ChipWidthAllocation` 纯函数：扣除 8pt 固定间距后，求共同宽度上限 cap，逐项取 `min(natural, cap)`；放得下时保留全部自然宽度。排序仅用于求 cap，返回宽度与排布顺序仍沿用原顺序，保持靠左、单行、长文本尾部省略，样式／点按／无障碍保持。

新增 `ChipWidthAllocationTests` 六项 Core 测试，覆盖 M6 长长短的三种顺序、放得下／刚好／无约束、多个短项、全长项、分数宽度、空行／单项／空间耗尽；仅将新测试登记进 Xcode 测试 target，保留原有测试引用。

验证：指定 PATH 后执行 `swift test`，退出 0，544 项、540 通过／4 项原有实网 opt-in 跳过／0 失败，新增六项全部通过；进程显式设 `YUBAI_LIVE_EVAL=0`，未调用付费 API。改动 App 文件通过 iOS 26 设备 Release／模拟器 Debug、macOS 14 Debug 条件语法解析；纯函数通过 Swift 6 严格并发类型检查，App 字符串字面量不变，`git diff --check` 通过。当前为 Linux，无 Apple SDK，iOS 26 真编译、Mac 验证 M6 视觉复验与大字号仍待 Mac。原稿／Figma／分发资源未同步；新增／改动可见中文字符串：无，未提交／推送。

## 2026-10-28 · 最近用途固定单行

本节保留首版记录；同比压缩已由上方 M6 修复的水位线分配取代。

采用 owner 本轮已确认规格：`DesignSystem.swift` 新增 `ChipRow`，用未约束测量取得自然宽度，扣除固定 8pt 列间距后同比压缩，单行左排、高度取最高子视图；`SuggestionChips.singleLine` 默认关闭，仅 `EntryFormComponents.swift` 的 `RecentPurposeChips` 开启。最多三个、用途行下的位置、上下 8pt、单行尾省略、样式、选中态、填值行为、无障碍标识与标签、最小点按高度均保持。

静态核对与 `git diff --check` 通过，未编译；环境无 Apple SDK，iOS 26 真机长文本／大字号与点按区域待验证。原稿／Figma／分发资源未同步；新增／改动可见中文无，未提交／推送。

## 2026-10-28 · 记一笔 sheet 还原

来源为 owner 本轮提供的「记一笔 · 数字键盘」设计事实与真机问题说明。`QuickEntryView.swift` 在 iOS 的 `.presentationDetents` 旁显式设置 canvas 呈现背景；底部键盘与「记下，再记一笔」在全宽 frame 后铺 canvas，延伸到底部安全区。现有上下内边距 `YubaiSpace.gapGroup` 已为 12，保持不变；全局 PaperBackground 与其他 sheet 源码保持。

`DesignSystem.swift` 的 SuggestionChips 占满可用宽度并左对齐，SuggestionChip 的文字限制单行并尾部省略；ChipFlow 保留 `min(width, ideal.width)` 测量约束，列间距仍为 8。已核对全部调用：消费观「愿意多花的」在 [V15 修复记录](../docs/V15-SIMULATOR-FIXES.md)中明确采用 8pt 横纵间距，因此新增默认 8 的 `rowSpacing` 参数，仅 SuggestionChips 指定 `YubaiSpace.gapGroup`（12）；其余调用保持原行距。

静态核对确认 token 数值、背景修饰符顺序、宽度约束及全部 Swift 字符串字面量不变，`git diff --check` 通过。当前环境无 swiftc／Apple SDK，未构建或执行 UI 测试；iOS 26 真机底色、滚动遮挡、长文本省略与大字号效果待验证。原稿／Figma／分发资源未同步；新增／改动可见中文无，未提交／推送。

## 2026-10-27 · PR #45 欢迎页 Mac 验证修复

按 owner 反馈，`WelcomeView.readStatement` 余额回填改用新增的 `Money.editableText`：用整数分生成固定两位、无千分位的可编辑字符串，负五分为 `-0.05`。`Money.input`、余额来源标记与开始时的金额／日期判断保持；`Money.parse` 可还原原分值。流水行高度的 UI 断言保留，增加 `0.01pt` 容差。

验证：`YUBAI_LIVE_EVAL=0 swift test --disable-automatic-resolution --filter FinanceTests` 31 项通过，新增一项覆盖正数、负数、整额、零与正负金额上限共 9 组格式及解析往返；改动 App 文件通过 macOS 14／iOS 26 模拟器 Debug 条件语法解析，UI 测试文件通过 iOS 26 模拟器 Debug 条件语法解析，diff 检查通过。Apple 编译与 UI 实跑待 Mac；原稿／Figma／分发包未同步。新增／改动可见中文字符串无，仅金额数字格式变化；未提交、未推送、未调用付费 API。

## 2026-10-27 · 第十九轮「始终留着」

来源为 owner 本轮提供的已批准第十九轮逐项文字规格；本轮未附独立 HTML／图片或私有原稿链接。此节接续下方同日 Core 记录，首页目标行不再等待设计。

- `DesignSystem.swift`：HeroCard 增加默认 nil 的 `floor` 参数。已设目标且 `available >= floor` 时，原还能花段内领先部分为实色 brand，余量为 brand 的 0.55 透明度，两部分相接；要付与原 reserved 段及间隔保持。未达目标／未设置沿用单一实色段；明确 0 仍为已设目标。实色目标段存在时，无障碍说明加入「其中始终留着 X」。隐藏金额仍无条与图例。
- `OverviewView.swift`：Hero 与目标行放在无额外间距的同组内，普通字号只增加 `tapMin = 44pt`，不替换既有内容；沿用 150／96／0pt 图表适配及原有滚动兜底。共用 `FloorLine` 使用 8pt 状态点、callout／caption、numeric 金额与两位小数，达到目标为 brand／brandInk「能留住」，不足为 amberDot／amberInk「还差 X」。金额隐藏时目标为「••••」，不足状态为「还差一点」；差额通过 AmountLabel 的 `.none` 显示绝对值，不出现负号。
- 现在页以既有 `TabNavigationLink(.profile)` 推入 `ProfileView`，有 chevron 与 `floorLine` 标识；计算页公式 Card 下面复用同一行，采用只读、无 chevron，也有 `floorLine` 标识。辅助功能字号纵排，触控区域不小于 44pt。计算式不加目标扣减行，购买判断 UI 与 Core 均不改。

本次新增／改动可见中文：行名「始终留着」（控件字／事实）、金额及缺口数字（事实）、状态「能留住」「还差 X」「还差一点」。没有新增说明句；「其中始终留着 X」仅用于无障碍标签。

验证：`swift build` 通过，`swift test` 471 项、467 通过／4 项原有实网跳过／0 失败，含 InterfaceVocabularyTests 3 项；两份改动 App 文件通过 iOS 26 设备／模拟器与 macOS 14 条件语法解析，使用的颜色／字号／尺寸 token 均在现有设计系统中核对。已检索 `Tests/YubaiUITests` 的「始终留着／emergency」，无匹配，不改也不加 UI 测试；diff 检查通过。Linux 无 Apple SDK，SwiftUI 类型检查、设备单屏适配、VoiceOver 与 UI 实跑尚未验证。文字规格已落实，无已知功能偏离；原稿／Figma／截图／分发包未同步，未提交。

## 2026-10-27 · 始终留着改为目标

依据 owner 明确任务，沿用 V16 的少写字规则，只从 `OverviewView` 的 HeroCard `reserved` 合计移除 `funds.emergency`，并删除计算页「始终留着」扣减行，使显示公式与 Core 一致。不新增行、视图或视觉方案；首页目标与差额新行等待设计稿。消费观现有展示／编辑保持。Core 的购买事实与目标缺口理由均为金额事实，[全部可见中文及口径](../docs/DEVELOPMENT.md#始终留着是目标2026-10-27)。原稿、Figma、截图与分发包未同步；改动 Swift 文件共 19 项条件语法解析通过，含 OverviewView 的 iOS 26 设备／模拟器及 macOS 14；Core 单测因依赖下载受阻未运行，Apple SDK 编译与设备验收待 Mac。

## 2026-10-27 · 第十八轮单账户转账

来源为 owner 本轮明确批准的 `V18-Transfer-One.dc.html` 与 `V18-Transfer-Added.dc.html`（设计稿「第十八轮 · 转账」）。此处覆盖记一笔的转账账户行与分类芯片呈现，不改变 Core 转账校验或入账规则。

`QuickEntryView.swift`：转账账户行采用「转出／转入」；没有其他未归档账户时，转入行显示 SF Symbol `plus` 与「添加账户」，复用 `brandInk`／`raised`／`chipHeight`／`yubaiHitTarget`。通过独立嵌套 sheet 和 NavigationStack 呈现现有 AccountEditor，保留金额、用途、日期与性质。关闭编辑器后比较打开前的账户 ID，仅选中新建的未归档账户；取消不改草稿。转入行复用 `brandTint`、`YubaiMotion.claim` 和 `YubaiMotion.wash(reduceMotion:)` 洗色一次。两个保存入口在转入有效前继续禁用；已有其他账户时沿用默认选择。转账隐藏 EntryCategoryChips，内部分类保持原实现。账户菜单区分转出／转入读屏标签，添加按钮标识为 `transferAddAccount`、读屏标签为「添加账户」。

新增／改动可见中文：「账户」在转账页改为「转出」（标题），新增「＋ 添加账户」（控件；＋为图标）；转账页移除分类芯片。没有新增说明文字；原有 AccountEditor 文案保持。

`AppFlowTests.testTransferWithOneAccountCanAddDestinationWithoutLosingDraft` 复用单账户 `manual` 夹具，覆盖两个保存入口禁用、分类芯片隐藏、取消保留草稿、添加后自动选中、保存后读回金额／转账性质／两个账户，以及后续转账默认选中第二账户。无新测试钩子、依赖或 Core 改动，未提取 Core 纯逻辑。

验证：Linux 按指定 PATH 执行 `swift test`，464 项、460 通过／4 项原有实网跳过／0 失败；iOS 26 模拟器 Debug 的改动 App／UI 文件及 macOS 14 Debug 的 QuickEntryView 条件语法解析、`git diff --check` 通过。Linux 无 Apple SDK，Apple 类型检查、UI 实跑、洗色视觉与 VoiceOver 验收待 Mac；语法解析不代表 Apple 编译通过。原稿未改写或导出，Figma、历史原型与分发包未同步。按指定提交信息尝试提交时，`git add` 因 `.git/index.lock` 所在文件系统只读退出 128；四个相关文件保留为工作区修改，未提交、未推送。

## 2026-10-26 · PR #37 第三轮证据修复

基于 `fix/flaky-ui-tests`／`287ffec`，先读合并验证全部 8 份相关失败层级，再逐项核对测试失败行与截图：5 项账目停在初始关闭检查，固定收付停在展开几何检查通过后的收回检查，2 项管家停在右滑后的关闭检查。均为 `assertGone(action)` 的 AX 不存在等待，未发生展开等待失败。管家 `closed` 卡仍导出宽 0 的「知道了」，账目／固定收付仍导出 78pt 的删除／停掉；这证明上一轮移动 `.accessibilityHidden` 没有解决实际 AX 节点残留，覆盖上一节对该修复效果的推定。

`SwipeActionRow` 仅在 `offset != 0 || revealed` 时挂载背景 Button，`ButlerCardView` 仅在 `swipe != 0` 时挂载背景 Button；两处加 `.transition(.identity)`，不额外引入默认插入过渡。原内容决定布局大小，动作保留在 `.background(alignment: .trailing)`，原 frame、padding、opacity、偏移、裁切、颜色／字体和点击条件保持；没有增加占位尺寸，现有手势／动画调用及 Reduce Motion tokens 保持。现有中文读屏动作及生产 AX 值门控不变，无新英文生产 VoiceOver 输出。

全部 70 项 UI 测试文件原样保留，不改手势坐标／断言／等待或 `testUndoReceiptDismissesAfterProductionLifetime` 的金额文字。两个改动文件的 iOS 26／27.1 Debug 模拟器、iOS 26 Release 设备和 macOS 14 Debug 共 8 组条件语法解析通过，静态比对除条件挂载／identity transition／注释缩进外相同，字符串不变。此环境没有 Apple SDK／模拟器，AX 消失、实际几何及拖动／收回动画仍待 Mac 实跑与视觉比较；选定稿／Figma／分发资源保持，新增／改动可见中文无，未提交。

## 2026-10-26 · 金额固定两位小数

owner 明确要求所有金额展示固定两位小数：整额写 `12.00`，带分写 `12.50`，不进位为整元、不省略分。`DesignSystem.swift / AmountLabel` 删除按角色选择精度、`fractionDigits`／`decimals` 参数及整元进位分支，显示与读屏共用同一文本；保留千位分隔、正负号、币种符号和隐藏金额行为。余额、固定收付、还能花、日／月汇总、洞察／小项、省钱和快捷指令调用点移除精度参数；心愿生成的两处提问改用 `Money.text(..., currency: false)`。

Core 使用 Int64 分计算，`Money.text`、助手金额对象及小组件已固定两位，核查后无需修改。输入解析／编辑中的原始金额与键盘表达式保持；百分比、图表坐标缩放、次数、文件大小和布局／字体／颜色保持。新增／改动可见中文措辞：无；既有提示如「房租 300 已记下」只将数字改为「房租 300.00 已记下」，既有两处心愿提问同样只改插值金额。

验证：通过 `/opt/swift-rootfs/usr/bin` 工具链、`/tmp` 可写缓存运行 Core build 与 `YUBAI_LIVE_EVAL=0 swift test`，464 项中 460 通过、4 项原有实网跳过、0 失败。直接提取实际 `AmountLabel.text`／`Money.text` 执行 357 项检查，覆盖零、整额、分、半元边界、正负号／币种符号、千位分隔、Money.limit 和 Int64 极值；未新增 Core 测试。38 个 App 文件、小组件及 UI 测试共 40 个文件通过 iOS 26 模拟器／macOS 14 Debug 条件语法解析；已有 UI 金额断言更新为两位，输入断言保留。`git diff --check` 通过。Apple SDK 类型检查、UI 实跑与长金额实际显示仍待 Mac；原稿／Figma／历史原型及分发包未同步，未提交。

## 2026-10-26 · PR #37 第二轮证据修复

owner 在 `1821b9b` 的 Mac 两轮验证为 20 项稳定失败、2 项时好时坏；已逐份读完 21 份现有失败层级／截图及中断证据缺口。账目 `closed` 行仍暴露删除 Button，固定收付同样暴露停掉：共用 `SwipeActionRow` 的 identifier／hidden 移到全部 frame、padding、opacity、hit-testing 之后，关闭断言加强为 AX 中不存在；原按钮仍挂载，所有视觉与手势修饰不变。待付 Card 增加 `.contain`，阻止 `dueBills` 传播覆盖 `moreDueBills` 与各期按钮标识；不加 label／value。

撤销缺失属于真实应用缺陷：`1d84959` 引入初始为空的 `Group`，`.task` 无宿主却负责设置显示状态；`062f4fa` 将其接入根 overlay。改为单子项 `ZStack` 生命周期宿主，保留原 surface、overlay、计时、transition、颜色与文案，恢复既定提示条；没有把提示条移入 sheet。生产 4 秒测试原样保留，测试保留开关及生产 AX 值门控保持。没有证据将缺失归因于 PR #34／#36 的遮挡。

原生 alert 的同 ID 父子 Button 用 scoped `.firstMatch`，保留标签、启用、可点击和边界断言；键盘拖动从 inputView／assistant 区上方开始；记一笔横拖以现存自定义 header 定位；取消返回改短拖，完整 pop 和导航栏断言保留。已选、可见、idle 且几何对齐时，根 pager 不再发起没有位移的 scrollTo，其他滚动继续原动画；原失败层级截断 pager 值，具体失配状态仍需 Mac 验证，新诊断会输出完整值。无新增英文生产 VoiceOver 值。

70 项测试保留，无跳过／禁用／预期失败；一个 signal term 用例缺少失败截图和层级，保持原用例且不推定原因。Linux 条件解析、语言级核对与静态不变量见交付记录，不能代替 Apple SDK 类型检查、UI／VoiceOver 或像素验证。选定稿、Figma、分发资源未改变；新增／改动可见中文无，未提交。

## 2026-10-24 · UI 测试观测与稳定性

按 `619564f` 的 23 项失败调整[测试](../Tests/YubaiUITests/AppFlowTests.swift)等待、手势与撤销；展开值／pager 值及撤销保留仅限 Debug 模拟器、有效 UUID 测试账本与白名单脚本，保留另需 `YUBAI_UI_TEST_KEEP_UNDO=1`。生产账目／管家卡不加 AX 值，固定收付保持原财务值，测试时才追加展开状态；财务查询用前缀匹配。
`rootPage_*` 先 `.accessibilityElement(children: .contain)` 再标识；`fixedFlowsScroll` 沿用 settings／insights 的 Page→ScrollView 标识方式，`rootPager` 标识原生 ScrollView，保留内部标识。原 69 项测试保留，新增 1 项覆盖原 4 秒提示；条件解析／静态核对通过，Apple 编译与 AX／UI 实跑待 Mac。布局、可见中文、动画、业务与外部设计资源无变化；未提交。

## 2026-10-23 · PR #34 名单外 UI 失败修复

按 owner 的 Mac 验证报告，在 `4b7c0f7` 逐个核对 `a23e179` 的测试名与准确失败点。[全部测试的判断、改法与验证](../docs/PR34-NEW-UI-FAILURES.md)。`OverviewView` 的三档静态内容均放不下时，新增复用大字号 ScrollView 的最终兜底，固定 header、暖纸渐隐和底部 margin 沿用既有组件；避免「还有 N 笔」落入浮栏下且无法滚到。导航路径／分页同步保持，报告没有证明取消侧滑后浮栏状态回归。

小项页既有非交互汇总区增加 `subcategoryInsightsSummary`，既有 Toast 撤销增加 `undoLastChange`；测试避免新小项链接落点并立即处理 4 秒提示。停止继续采用系统 alert 及 destructive「停掉以后的」，合并重复测试覆盖取消／确认和关闭计算 sheet 后根页撤销。不改业务规则／夹具／Core，18 个已知测试方法体保持，新增／改动可见中文无。

Linux 464 项、460 通过／4 原有实网跳过／0 失败，全部 38 个 App 文件四组及 UI 两组条件解析通过；69 项 UI 尚未实跑，Apple 类型检查、提示时序、滚动与手势实际几何待 Mac。选定稿、Figma、旧原型和分发包未同步；本轮未提交、未联网调 API。

## 2026-10-23 · 第三、第四次 V16 截图修正合并

owner 要求将 `0acb32b`／`86524fd` 带入省钱分支，保留 V15／Core／小项、main #32／#35、编译／显示／问余白修复及全部 UI 方法和夹具。采用下方第三、第四次复查的四根页固定 TabRootHeader、canvas 暖纸底／8pt 渐隐、欢迎账户卡片自动滚动、记一笔底部 safeAreaInset；导航继续以本分支值路由／独立路径为准。固定收付与账目继续共用 CardRows／SwipeActionRow／96pt 左移与 12pt gapAction；将靠右对齐意图适配到 main 的描边「付了／收到了」按钮点击区，不恢复旧实心勾。已记灰勾、旧期结算／跳过、恢复／撤销和系统 alert 保留。此处覆盖下方第四次历史分支中圆形勾选控件的具体适配方式，原产品状态规则保持。

[五个冲突、自动合并核对与可见中文](../docs/MERGE-V16-THIRD-FOURTH-FIXES.md)。没有新增或改写可见中文措辞。Linux 464 项、460 通过／4 原有实网跳过／0 失败，38 个 App 文件四组与 UI 两组条件解析通过；UI 方法并集 70 个，无遗漏／重名，24 个夹具保持。计算页停止确认与撤销分别保留测试，撤销先关闭 sheet。Apple 类型检查、UI 实跑和实际几何待 Mac，原稿／Figma／分发包未同步；未提交、未终止 merge、未联网调 API。git add 因 .git 只读退出 128，索引仍有五个未合并文件，暂存命令见交付记录。

## 2026-10-23 · 两次 V16 截图修正合并

owner 要求将 `65928a9`／`205edde` 两次截图修正完整带入省钱分支，同时保留 main #32／#35、V15／小项及此前编译与显示修复。两边历史记录保留；本节覆盖下方 main 合并记录的自定义停止 sheet 和 V16 历史分支仅 endPlan 的具体呈现／调用方式，不改变已经采用的旧期处理规则。

固定收付采用新 CardRows／SwipeActionRow，仍保留 V14 状态、提前标记、已停掉唯一行与旧期处理。停止确认统一系统 alert：无待结算期用「停掉以后的／取消」且不写 message；有待结算期保留原 main 的结算／跳过／取消和期数／日期事实。调用 FixedFlows.stop，仍一次处理全部未结算期并经省钱停订快照，恢复／撤销保持。计算页保留 paymentRow 子视图并接入行级 alert；心愿同时保留 V15 省钱／冷静／后悔入口及新已买状态／日期／无再问动作，采用 rowTitle 与当前可展示内容空态。问余白拆分、纸色导航、追问移焦点／滚动保持；自动合并的欢迎键盘、根页裁切／留白、图标缩放、导入流向及字体修正均带入。

[逐文件取舍、全部可见中文与验证](../docs/MERGE-V16-SCREENSHOT-FIXES.md)。Linux 464 项、460 通过／4 原有实网跳过／0 失败；全部 38 个 App 文件四组及 UI 两组条件解析、24 个夹具准备和八个截图工具流程通过。两边 UI 方法并集 68 个，无遗漏／重名；Apple 类型检查／UI 实跑／截图验收待 Mac，选定稿／Figma／分发包未同步。未提交、未终止 merge、未联网调 API；git add 因 .git 只读退出 128，索引仍有八个未合并文件，暂存命令见交付记录。

## 2026-10-23 · main 与省钱分支合并

owner 要求将 `origin/main`／`9703831` 合入 `feat/butler-saving-core` 的当前 merge，保留 #32 固定收付、#35 标准推入与取消侧滑返回修复，以及本分支 V15／V16、八个夹具、编译与显示修复；本轮仅合并已有采用决定，不新增视觉方案。下方两边历史记录及原验证范围全部保留。

`InsightsView.categoryLink` 使用 `TabNavigationLink`，单一主项经新增 `TabRoute.subcategoryInsights` 推入原 `SubcategoryInsightsView`，仍传当前收支方向、期间和标题；合并扇区使用 `flowRecords`。分类入口移除成对 zoom，记录详情保留 main 的标准推入与本分支小项行。`RootView` 每个 tab 独立 `NavigationPath` 决定浮栏与分页锁定，同时保留本分支 `pagingPhase` 停稳同步；取消侧滑返回不会依赖出现回调，sheet／macOS 保持原目的视图导航。问余白纸色实底、追问移焦点及滚至按钮行的修复保留。

固定收付采用 main 的 V14 状态、逾期金额、已停掉旧期原地处理和 `FixedFlowStopSheet`，覆盖下方 V16 历史中的单一「停掉以后的」确认。保留本分支 iOS `HorizontalPan` 和停止按钮 identifier；停止调用 `FixedFlows.stop`，继续经过省钱分支的 `endPlan` 停订快照和恢复逻辑。文案只合入已有 V14 标题、事实、状态及结果按钮；[完整可见中文清单及八文件取舍](../docs/MERGE-MAIN-SAVING-CORE.md)。

验证：Linux 指定 swift test 退出 0，464 项、460 通过／4 原有实网 opt-in 跳过／0 失败；38 个 App 文件分别通过 iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug 的 `swiftc -frontend -parse`，UI 文件通过两组模拟器条件解析。两边 UI 方法并集 62 个，无遗漏或重名，main 新增测试的标题／状态入口已对齐 V15／V16，固定收付用例共用慢拖及 `isHittable` 查询。实际合并后的 UITestSupport 通过离线 Core 类型检查，八个截图脚本及 `bills-clarity`／`bills-multiple` 执行通过；diff 与源码标记／私有链接检查通过。Apple SDK 类型检查、UI 实跑及视觉仍待 Mac，原稿／Figma／分发包未同步。未提交、未终止 merge、未联网调 API；暂存因 `.git` 只读失败，索引仍有八个未合并文件，命令见交付记录。

## 2026-10-23 · 问余白追问与导航遮挡修复

来源为 owner 对 `feat/butler-saving-core`／`2a51c45` 的两处显示反馈及两处 UI 测试查询错误。沿用 V15 追问卡与 V16 少写字规则，本次新增／改动可见中文字符串：无。

`AskYubaiView.swift` 拆出 conversation 子视图，共用 `ChatInputBar` 接受可选焦点绑定。追问卡进入时先移开输入焦点再保持卡顶定位；`SavingPurchaseViews.swift / PurchaseQuestionsCard` 每次点选芯片先移开焦点，所选状态变化后通过按钮行的独立稳定 id 滚至 `.bottom`，覆盖「就这样回答」「直接给结论」。仅问余白在 `yubaiNavigation()` 后覆盖 iOS 导航栏的纸色实底与可见背景，共用导航样式及其他页面不变。`AppFlowTests.swift` 的两个固定收付停止按钮查询改为 `isHittable == true`，原截图流程与业务断言保留。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出 0，451 项、447 通过／4 原有实网跳过／0 失败；38 个 App 文件逐一通过 iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug 的 `swiftc -frontend -parse`，UI 测试文件通过 iOS 26／27.1 模拟器 Debug 条件解析；`git diff --check` 通过。Linux 没有 Apple SDK，SwiftUI 类型检查、`testJudgeAskScreenshotFixture` 与固定收付 UI 实跑、键盘时序和导航视觉待 Mac 复验。原稿／Figma／分发包未同步，未提交、未联网调 API。

## 2026-10-23 · V15 模拟器显示与 UI 测试修复

来源为 owner 在 `57ac7bf` 的 15 张模拟器截图、12 张 V15 原稿及本轮八项明确修正，继续遵守少写字。输入条槽位限高、用户气泡即时可见、追问卡顶部定位、购买按钮按完整文字测量后横／竖切换；心愿冷静到期状态、买后问题、来信合计／订阅与克制额度去重，愿意多花的复用 8pt ChipFlow，记录分类与其他行等高。原稿不修改，采用本轮截图反馈修正；[逐项源码映射与可见中文](../docs/V15-SIMULATOR-FIXES.md)。

iOS 页内横拖先判方向再放行祖先列表／分页，筛选子滚动仍允许同时识别；固定收付采用同一识别器，根分页停稳才回写当前标签。未展开账目／管家只接左滑，系统返回、竖滚、现金图与 macOS 分支继续保留；这些属于行为回归路径，具体设备时序仍待实跑确认。55 个 UI 测试全部保留，旧存储说明／洞察导航断言按 V16／V15 更新，其余不按文案变化豁免。

Linux 451 项测试，447 通过／4 原有实网跳过／0 失败；38 个 App 文件在 iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug 与 UI 测试 iOS 26 条件解析通过；八个夹具经离线 Core 类型检查／执行。修后 Apple SDK 类型检查、55 个 UI 实跑、视觉／手势仍待 Mac 验证；owner 的基线编译通过与 34 过／21 失败不代表修后结果。未提交或联网调 API，HTML／Figma／分发包未同步。

## 2026-10-23 · 少写字与帮你省钱合并

按 owner 本轮合并任务，同时采用下方 V15 功能与 V16 文案规则，历史记录与验证边界全部保留。[八个冲突文件的取舍与可见文字](../docs/MERGE-NO-EXPLANATORY-COPY.md)。保留 `ChatInputBar`、拆分子视图、小项 `ToolbarItem`／`YubaiCore.Category` 和八个截图夹具；将 V16 状态／控件落实到本分支子视图，未恢复被删的说明句或旧购买卡。消费观合并成页底一处品牌浅底聊天行，无密钥／云端未开／模型不可用显示状态并进入设置；覆盖下方 V15 当时“入口仅禁用”的历史记录。

心愿后悔卡删除邀请句，动作改“写进消费观”／“收起”，仍传原上下文；来信动作改“聊聊这周”。买后日期用日历图标与日期事实，可选补充收到更多，操作说明移入读屏；冷静期、省钱、订阅、克制进度、再聊及三处入口、小项与洞察行为保持。全部文案按四类复核，词汇测试通过；原稿未改，Figma／分发资源未同步。

Linux swift test：449 项，445 通过、4 原有实网跳过、0 失败，包含 3 项词汇检查；全部 38 个 App 文件通过 iOS 26／27.1 模拟器 Debug、iOS 26 设备 Debug／Release、macOS 14 Debug 语法解析；55 个 UI 测试方法保留并通过 iOS 26 语法解析。Apple SDK 类型检查与 UI 实跑待做。本轮不提交、不终止 merge、不调用实网 API。

验证后 `git add` 因 `.git` 文件系统只读失败，索引仍有 8 个未合并文件；源文件无冲突标记，暂存命令见合并报告。

## 2026-10-23 · Simulator 27.1 toolbar 编译修复

按 owner 的报错与明确位置要求，`SubcategoryViews.swift:58` 将 CloseButton 包进 `.cancellationAction` 的 ToolbarItem，「完成」位于左侧；「换主项」继续使用右侧 `.confirmationAction`。两个子项统一为 ToolbarContent，避免与裸 View 混用引发 `.toolbar` 重载推断失败。沿用 V15-Entry-Sub 右上换主项的规则，按钮动作、保存逻辑、文案、样式和其他页面保持，未改原稿。

[本轮逐文件检查与验证](../docs/APP-COMPILE-AUDIT.md)覆盖相对 main 的全部 37 个 Swift App 文件及 5 个资源。Linux 449 项测试（445 通过、4 原有跳过、0 失败）、全部 38 个现有 App 文件的 iOS 26／27.1 模拟器与 macOS 14 语法解析通过；当前无 Apple SDK，Xcode 类型检查与 UI 实跑仍待做。Figma／HTML／分发包未同步，未联网调 API、未提交。

## 2026-10-23 · 第十六轮：少写字，让版式说话

owner 已在本轮明确确认规则与 11 张页面／片段板，并授权在 `feat/no-explanatory-copy` 接入 SwiftUI。另有 1 张规则板；[完整规则、原始 54 项审计及 HTML 原样归档](mockups/no-explanatory-copy-v16/README.md)。取代下方历史界面中的常驻导语、副标题、操作路径与步骤说明；业务计算、数据模型和存档格式保持，以下历史执行证据仍属于原日期。

本轮规则：可见文字只有标题、数字和事实、控件字、状态。先删，再用层级／控件／状态表达，再挪到发生时；仍无法表达才保留一行事实。不可撤销确认的一句后果、带按钮的错误原因、完整读屏文字和系统权限说明为例外。可选字段收到更多，空态只保留标题与动作；EmptyState 的说明默认 nil。建议芯片是可直接填值的控件，不是常驻的「例如」。

| 选定稿／范围 | 源码映射 |
|---|---|
| V16-Welcome | `DesignSystem.swift / WelcomeView`：欢迎页直接输入首个账户余额／名称，按开始走原 store 更新链；既有恢复备份入口保留。 |
| V16-Lock | `YubaiApp.swift`：水位与两个解锁控件，后台只留水位；手机密码／Mac 设备密码调用既有 LAContext。 |
| V16-Ask-Offline | `AskYubaiView.swift`、`AskCapture.swift`：禁用输入条、可处理的状态胶囊，原生网络状态监测与语音权限刷新；未调用云端测试。 |
| V16-Import | `ImportView.swift`：截图专用列表、勾框／›、所选计数与金额，保留原图确认与账户选择；来源胶囊可查看本机事实／原发送记录。 |
| V16-Profile-Empty／V16-Wishlist-Empty | `ProfileView.swift`、`WishlistView.swift`：虚线添加／条形占位，密钥状态聊天行，心愿空态主动作。 |
| V16-AI | `SettingsView.swift`、`CloudAssistantViews.swift`：钥匙串状态、两组隐私芯片、模型菜单去副标题、发送记录本次打开分组。 |
| V16-Quick | `QuickCaptureSettingsView.swift`：添加到快捷指令打开系统 App；三种系统入口暂为缩略图与名称的不可点静态行，设置图示未实现，属于任务允许的降级；映射与截图导入入口保持。 |
| V16-Storage | `StorageView.swift`：占用＋真实体积，原件不删使用灰色行。 |
| V16-Forms | `Editors.swift`、`ProfileView.swift`、`FixedFlowsView.swift`、`OverviewView.swift`：建议／关键词芯片、更多、停掉以后的按钮。 |
| V16-Moments | `ButlerViews.swift`、`AskYubaiView.swift`、`ProfileConversationView.swift`：新记得的 N 条与来源日期、实时听写、进度点和思考水波；降低动态效果沿用既有实现。 |
| 无独立画板的其余审计 | `EntriesView.swift`、`EntryDetailView.swift`、`EntryEditView.swift`、`EntryFormComponents.swift`、`QuickEntryView.swift`、`WeeklyPush.swift`、`SyncVersionsView.swift` 及上述页面：只保留事实和动作，相关信息保留在读屏。Core 仅一条 Finance 空账户字符串与参考测试同步。 |

[交付总结](no-explanatory-copy-v16.md)逐条列出 54 项：53 项源码已改，1 项按授权部分完成（系统入口图示）；并列出全部新增／改动可见中文及其规则分类。所有 47 个 UI 测试方法保留，旧文案、欢迎直接输入与停掉／删除流程断言已同步；未新增 skip。

验证边界：改动的 24 个 App Swift 文件 iOS 26／macOS 14 条件语法解析通过，UI 测试 iOS 26 语法解析通过，最终复验详见交付总结。Linux swift test 结果见交付总结。Apple SDK 类型检查、UI 实跑与设备验收待做。工程／依赖和存档格式未改；未运行 Actions、未访问付费模型 API、未提交／推送；Figma 与旧原型／分发包未同步。

同日截图复查续作：按 owner 的 14 项清单及 main `18889f8` 差异修正欢迎禁用底色、Debug 显式模拟密钥、消费观行尾箭头、我页计数／实际滚动底部留白、心愿列表空态与已买状态、用途空占位、行级停掉确认、iOS 固定收付独立滑动按钮、导入流出／流入展示、存储／快速记账字体及 tab 图标缩放。固定收付左滑与 tab bar 旧问题依 owner 明确例外修复；账户详情／计算页旧布局、push 页多余完成、现在页旧 header／今日行按本轮组件范围保留，依据与可见中文见[截图复查修正](no-explanatory-copy-v16.md#截图复查修正)。15 个 App 文件与 UI 测试 iOS 26 DEBUG 条件语法解析、App macOS 14 条件解析通过；保留原 47 个测试方法并新增 2 个，35 个 App 文件通过原禁用词扫描。本次未改 Core／存档／依赖／原稿，未构建／提交／推送；Apple 类型检查、49 个测试方法实跑及 iOS 26.4 截图／无障碍复验待做。

同日第二次截图复查：owner 要求修复 `65928a9` 的六项设备问题，取代上一段对应项的实现状态。固定收付回到与账目相同的 CardRows 固定卡片，二者共用 SwipeActionRow 的原宽 offset／行裁切／独立按钮层；停掉确认统一系统 alert（现有恢复／撤销可用，按本轮条件不写 message）。Page 与我页恢复 main 原滚动底部 margin 路径，根页滚动内容明确裁切；欢迎用底部 safeAreaInset 为键盘与按钮保留滚动空间；共用 HeaderIconButton 以 ScaledMetric 限制图标 22–32pt、容器随动，今天行在 accessibility 字号换行；存储空间移除 principal，使用与快速记账完全相同的系统导航标题。[逐项原因、token、测试与可见中文](no-explanatory-copy-v16.md#第二次截图复查修正)。快速记账三静态行、账户详情／来信旧导航继续保留。8 个 App 文件 iOS 26／macOS 14 和 UI 测试 iOS 26 条件解析通过；既有测试产物运行 InterfaceVocabularyTests 3 项通过，原 49 个 UI 方法保留并新增 4 个。Apple 类型检查／53 个 UI 方法实跑／iOS 26.4 截图复验待做；Core、工程、依赖与原始画板未改，外部资源未同步，未构建／提交／推送。

同日第三次截图复查：按 owner 对 `205edde` 的反馈，进一步修正欢迎页与根页结构。欢迎原先已经有 safeAreaInset，但系统只保证金额输入框可见；本次给账户卡片独立滚动 ID，聚焦和安全区可用尺寸变化时用 ScrollViewReader 对齐卡片底部，保留键盘上方的底部按钮与完整读屏。根页原先把 header 放在滚动内容里，再对整体 `.clipped()`，少量滚动也会切到圆钮；现在／洞察／我改用共用 rootPageHeader，把 header 放在 ScrollView 之外，仅裁切其下正文，保持原顶部／组间 token 与底部滚动 margin；账目仍用系统 navigationTitle。固定收付／账目 96pt 左滑不改。[第三次截图复查修正](no-explanatory-copy-v16.md#第三次截图复查修正)区分源码修正与待做的设备验收，并说明计算页撤销原在 sheet 后方，测试仅保留取消／确认。4 个 App 文件三平台条件解析、UI 测试 iOS 26 解析及禁用词 3 项通过；53 个 UI 方法未实跑，Apple 类型检查与 iOS 26.4 复截图待做；Core／依赖／工程／原画板未改，外部资源未同步，未提交／推送。

同日第四次截图复查：按 owner 对 `0acb32b` 的六项反馈，选择让账目也使用 TabRootHeader／rootPageHeader，以原自定义 header 为基准统一四页标题；现在的眼睛按钮并入同一组件。账目月份／搜索／筛选／行及各 tab 的 NavigationStack 保留，push 页继续使用系统返回。header 用页面 `canvas` 实色底，正文顶部复用 `space8` 做同色短渐隐，无玻璃底板、无新增 token。固定收付 40pt 勾选圆钮在 44pt 框内右对齐并保留完整点击区，消除多余 2pt，与账目共用 `gapAction = 12`；96pt 左移、标题裁切和原 12±1 测试断言保持。记一笔键盘／保存移入底部 safeAreaInset，独立滚动表单容纳用途芯片。[第四次截图复查修正](no-explanatory-copy-v16.md#第四次截图复查修正)记录六项处理、可见中文和验证边界。5 个 App 文件 iOS 26／macOS 14、UI 测试 iOS 26 条件解析及禁用词 3 项通过，diff 检查通过；54 个 UI 方法未实跑。Apple 类型检查、iOS 26.4 视觉与读屏／键盘验收待做；Core／依赖／工程／夹具／原画板未改，外部资源未同步，未提交／推送。

## 2026-10-23 · 少写字，让版式说话

owner 在项目规则「设计驱动代码」下新增：“Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.” 设计系统 README 第一节改为同名规则（四种可写的字、六步替换顺序、不写的东西、例外、实现检查），`EmptyState` 去说明行、`InlineNote` 去解释卡和脚注、`EditorForm` 去「例如」和「（可选）」。设计稿新增「第十六轮 · 少写字」：规则、按 main `18889f8` 逐屏审计的 54 处说明文字及改法、11 张改后画板。前几轮画板中与本轮冲突的说明文字以第十六轮为准。owner 确认画板后在 `feat/no-explanatory-copy` 实现（见上一节）；实现约束同时写入根目录 `AGENTS.md`。

## 2026-10-23 · 取消侧滑返回的标签栏修复

来源为 owner 在 `fix/insights-push-inset`／HEAD `0838156` 的 vphone 反馈：洞察分类明细等二级页左边缘返回到一半后取消，浮栏错误留在二级页；明确要求修复状态来源、保持 push 锁分页及 sheet 隔离、macOS 不变，补 UI 回归且不删／跳旧测试，不提交／推送。既有实色浮栏、留白与原稿保持，本轮没有新增视觉选择。

Agent 实现选择：`YubaiApp.swift / RootView` 为四个常驻 NavigationStack 分别绑定 `NavigationPath`，`tabBarHidden` 直接读取当前 tab 路径是否非空，同时供 FloatingTabBar 条件与外层 `.scrollDisabled` 使用。`OverviewView`、`InsightsView`、`SettingsView` 和根页管家卡的全部首层 push 改用 `TabRoute` 值导航；普通目的视图链接不会加入可观察路径，所以不能只给原有 NavigationStack 增加 path 绑定。首层值保留在路径底部，深层普通链接或 Boolean 导航返回时仍保持隐藏；只有回到根页才恢复浮栏及分页。macOS 和 sheet 中的 `TabNavigationLink` 沿用原目的视图闭包，sheet 的 NavigationStack 不绑定 tab 路径。依据 [Apple 导航栈说明](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack)，值目的地与上层视图目的地可以组合。

`DesignSystem.swift` 删除 `TabBarVisibility`、环境绑定和出现回调写入，`EntriesView` 移除旧隐藏参数，`FlowRecordsView` 调整为模块内可见以供集中路由使用。取消交互返回不再依赖根页／二级页的 onAppear、onDisappear 顺序；系统导航决定路径，浮栏与分页只派生状态。

验证：指定 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，406 项、402 通过／4 项原有实网 opt-in 跳过／0 失败。全部 App 文件在 `arm64-apple-ios26.0`／`arm64-apple-macosx14.0`、UI 测试在 iOS 26 下通过 `swiftc -frontend -parse`，`git diff --check` 通过。原 47 个 UI 测试方法全部保留，新增 4 个：洞察反复取消返回后浮栏隐藏且双向横拖不翻页、深层 Boolean 导航取消／完成返回到我页、现在页完成返回才恢复浮栏及 tab 切换、sheet 内取消／完成返回后根页浮栏与分页正常。用 XCUICoordinate 从左边缘慢拖至 42% 并停住释放触发取消，95% 拖动覆盖完成返回；同时覆盖导航按钮返回。当前没有 Xcode／vphone 工具，Apple SDK 类型检查及 UI 实跑待做，语法解析不等于设备手势验收。未改 Core、依赖、`docs/`、HTML 原稿、Figma 或分发包，未提交／推送。

## 2026-10-22 · 分页同步与右滑归属复验

来源为 owner 在 `fix/tabbar-gesture-regression`／`bd8b1b2` 的 vphone 复测：账目右滑到洞察后点账目、现在左滑到洞察后点现在，出现只切高亮、不切页面；其余手势已通过，本轮只修这两条同步路径及明确调整的右滑规则，macOS 保持。

`YubaiApp.swift / RootView` 原先让 `scrolledTab` 同时承担滚动命令与当前位置，再与 `destination` 双向观察；回写滞后或 ID 与实际页不一致时，相等 guard 会跳过必要滚动，源码不能单独确认是否由 `.center` 的系统回写触发。本次移除该绑定，点击 tab 每次直接调用 `ScrollViewReader.scrollTo`，包括重选；实际 `contentOffset.x + contentInsets.leading` 除以容器宽度、取最近页后回写 `destination` 与只读位置报告 `visibleTab`。外部 destination 变化仍可切页，位置报告用于阻止滚动回写再次发出命令；高亮随实际页面同步，不抢先改选中状态。保留原 paging、四个 NavigationStack、动画／Reduce Motion、锁页和导航规则。[Apple API](https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto%28_%3Aanchor%3A%29)、[实际滚动几何](https://developer.apple.com/documentation/swiftui/scrollgeometry)。

`HorizontalPan.shouldBegin` 在原位移横向判断后过滤起手方向，协调器随视图更新闭包；账目未展开只接左滑，右滑交给分页，已展开仍左右都接收并锁分页；管家卡只接左滑，右滑交给分页（现在是首根页，右滑保持边界回弹）。既有删除露出／关闭协调、管家 25%／快扫阈值、现金图、筛选、竖滚、点击和 macOS 分支保持。下方手势小节同步此规则，原稿只读保留。

验证：指定 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，406 项、402 通过／4 项原有实网 opt-in 跳过／0 失败。改动的四个 App 文件在 iOS 26／macOS 14、`AppFlowTests.swift` 在 iOS 26 下通过 `swiftc -frontend -parse`。原 43 个测试方法保留，新增 4 个：两条滑动后点回路径各重复三次，并核对唯一选中、内容可点击及实际屏内横向位置；账目未展开右滑翻页、展开后先收回再右滑翻页；管家快慢右滑的首页边界及后续双向分页。当前无 Xcode／vphone，Apple SDK 类型检查与 UI 实跑仍待做。`docs/`、设计稿、依赖和分发包未改，未提交／推送。

## 2026-10-22 · 页内横滑复验修复

来源为 owner 在 `fix/tabbar-gesture-regression`／`2be7adb` 的 vphone 实测：账目已露出删除后横滑翻页、可同时展开多行；管家快速左扫翻到洞察、慢拖不收起。此次只修页内手势与展开协调，取代下方起手速度 1.3 倍与 UIKit 祖先判定；既有视觉与原稿保持。

`DesignSystem.swift` 的 iOS `HorizontalPan` 以 `abs(translation.x) > abs(translation.y)` 且横向位移非零决定开始；瞬时速度仅保留给松手处理。动态失败关系只针对 UIScrollView 自身的 pan，条件为 `contentSize.width > bounds.width + 1` 或 `isPagingEnabled`，删除 SwiftUI 挂载视图必须是 UIKit 子视图的假设。竖向 ScrollView 不增加等待；横拖开始后仍由原生 pan 取消轻点，未加全页拖动。管家 `ButlerViews.swift` 的收起规则原已符合本轮要求：左拖超过卡宽 25%，或速度 < -650 且位移 < -20 时 dismiss，其余回弹；此次通过共用识别器修正归属，无需改阈值。

`EntriesView.swift` 共享 `revealedEntryID`：未展开行只接左滑，右滑让给分页；另一行开始左滑即关闭旧行，已展开行继续左滑保持，任意已识别右滑松手收回；展开时包含删除按钮区域的横拖由行处理并锁分页。列表轻点、竖滚进入 interacting、destination／sheet 改变和页面消失均关闭展开；删除后也清理状态。列表轻点采用 simultaneous tap，保留按钮动作；竖滚由 ScrollView 的 phase 观察关闭，不增加竖拖识别器。全部新协调逻辑限定 iOS，macOS 原拖动、阈值与点击抑制保持。

验证：指定 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，406 项、402 通过／4 项原有实网 opt-in 跳过／0 失败。改动的两个 App 文件在 `arm64-apple-ios26.0`／`arm64-apple-macosx14.0`、`AppFlowTests.swift` 在 iOS 26 下通过 `swiftc -frontend -parse`。保留原 38 个测试方法，新增 4 个覆盖展开后左右滑及删除按钮区域、单行展开／外部点按、切 tab／分页关闭、管家长距离快扫；扩充原快短扫、慢拖与竖滚断言。当前 Linux 无 Xcode／vphone 工具，Apple SDK 类型检查、UI 实跑及设备上竖滚／点按和快慢横拖复验仍待做，不能将语法解析视为手势验收。未修改 Core、依赖、`docs/`、设计稿、Figma 或分发包，未提交／推送。

## 2026-10-22 · 标签栏与分页回归修复

来源为 owner 对 main `146e379` 的真机验收反馈及本轮明确要求，在 `fix/tabbar-gesture-regression` 修复。用户于 2026-10-22 选定实色暖纸 raised 胶囊，不用玻璃；随后要求「位置稍微往下一点」，标签栏底边改为距 home indicator 安全区上沿 8pt，整体下移 14pt。取代下方方案 B 的玻璃底板与历史 22pt 底部间距、add 缩放源、根页 safeAreaInset，以及第十一轮自绘横拖；历史选定稿只读保留，不修改 `docs/`、HTML、Figma 或分发包。

根因核对使用 `git diff 5ae3882..HEAD` 及相关提交：`02fe751` 将系统标签栏换成带 72% raised tint 的 interactive regular glass，玻璃会参与模糊、折射与系统底色合成，不能保证实色暖纸和静态清晰度；截图中＋的变形是否还受 matchedTransitionSource 影响，在 Linux 无法分离确认。本轮直接移除 FloatingTabBar 的 GlassEffectContainer／glassEffect，采用不透明 raised Capsule、1pt separator 与 float 阴影；形状、66pt 高、左右 18pt、底部安全区上方 8pt、50pt matchedGeometryEffect 选中胶囊、54pt 绿色＋和全部原 identifier 保留。未选中改 labelSecondary，选中保持 brandInk／card。＋移除 add 源及 addEntry 默认 zoom 目的地，清空 sheetSource 后打开原记一笔 sheet，避免没有源仍请求 zoom。

白条与裁切来自布局链，而非缺少一层颜色：旧 TabRootSwipe 在安全区尺寸的 GeometryReader 内强制 frame，并 clipped；`02fe751` 又在外侧加入 88pt safeAreaInset，缩短该裁切区域。因此列表在栏上方就结束，放在外侧的 canvas 背景无法越过裁切覆盖导航与底部；隐藏系统 tabBar 后仍保留 TabView 的系统容器，PaperBackground 又没有延伸安全区，导航栏未明确采用透明背景，露出了系统底色。本轮删除该 GeometryReader／clipped／占位 inset 与普通 TabView；各 NavigationStack 内外及 iOS 非 sheet 的 PaperBackground 延伸 canvas 到安全区，导航栏透明。分页 ScrollView 允许绘制到安全区；根页滚动用 contentMargins 留出 86pt（66 + 8 + 12）滚动余量，不缩短视口，最后一行仍可完整滚到栏上方，至少留出 12pt；rootBottomPadding 与 toast 底部间距均随 floatingTabbarBottom 自动更新。筛选横条覆写底部 margin 为 0。底部 scroll edge effect 关闭，避免浮栏附近再叠系统模糊；它不是已确认的独立白条根因。

旧 simultaneous DragGesture 同时驱动根页与页内控件，只有当前页位移，没有相邻页；`7453f94` 又临时切换整页 hit testing／disabled 来压制误点，仍未建立原生手势优先关系。本轮采用横向 ScrollView + 零间距 HStack，四个 NavigationStack 常驻以保留状态；containerRelativeFrame(.horizontal)、scrollTargetLayout 与 paging 提供跟手、回弹。初版 scrollPosition 双向同步已由上方复验修复替换：点击直接 scrollTo，实际分页偏移回写 destination。点击标签以 YubaiMotion.layout 滚动，Reduce Motion 时无程序动画。push 可见性、AppSheet 或洞察日期 sheet 禁止外层滚动；NavigationStack 内恢复 isScrollEnabled，二级页竖向滚动与系统边缘返回继续工作。非当前页对无障碍隐藏，防止四页常驻时相同控件 identifier 重复暴露。

管家卡与现有账目行删除改由 iOS HorizontalPan（UIGestureRecognizerRepresentable + UIPanGestureRecognizer）识别：按横向位移判方向，再按 shouldBegin 过滤起手；可横滚／paging 的 UIScrollView pan 等待它失败，已开始的横拖由系统取消轻点。管家与未展开账目行的右拖让给分页；展开行左右都接收并锁分页。管家短左拖回弹，超过四分之一或快速左甩仍 dismissCard；账目保留原来的删除按钮、阈值与撤销。筛选横条／现金图使用同一原生优先关系，同时允许控件内部的滚动／长按拖动识别。删除 iOS 的 tabSwipeReserved、区域 preference、tapsBlocked、TabRootSwipe 和 TabContentEntrance。macOS 的侧栏、底部按钮、背景、滚动余量与原有卡片／账目拖动保持；账目原有点击抑制仅在 macOS 条件分支保留。

### 手势

- 只在现在／洞察／账目／我四个根页横滑翻页，按顺序分页。
- push 后禁止翻 tab，只保留系统左边缘返回；有 sheet 时不翻页。
- 现金图、筛选 chips 或横向列表的横拖交给页内操作；账目未展开只接左滑露出删除，右滑让给分页，展开后左右都由行处理并锁分页。
- 管家卡只接明显横向左滑，右滑让给分页；左滑收起阈值保持。
- iOS 左滑露出的操作按钮是独立圆角按钮（`control` 连续圆角，上下及右侧内缩 6pt，与内容间距 12pt），不依赖卡片裁切，首行、中间行与末行一致。
- 竖向拖动交给竖向滚动；横拖不触发行点击。
- 每次点击标签都直接发出滚动命令，实际分页位置同步高亮；平滑切页，降低动态效果时直接定位，各页保留导航和滚动状态。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，406 项、402 通过／4 项原有实网 opt-in 跳过／0 失败，未修改 Core 或依赖。App 全部 Swift 的 iOS 26／macOS 14 条件语法解析，以及 UI 测试 iOS 26 条件语法解析通过；这不是 Apple SDK 类型检查。`AppFlowTests.swift` 原 36 个测试方法全部保留，新增 2 个；覆盖双向分页、短拖回弹、push 内横拖不翻页与系统返回、非相邻标签点击及月份状态保持、管家／账目／筛选／现金图归属、sheet 横拖、竖向滚动和最后一行。UI 测试尚未运行。导航背景与 home indicator 实际颜色、底部穿透、嵌套识别器竞争、长按现金图、快速连滑／点击、深色／大字号／Reduce Motion 和 VoiceOver 仍需 Apple 设备验收。未提交／推送。

Apple 官方签名核对：[scrollPosition(id:anchor:)](https://developer.apple.com/documentation/SwiftUI/View/scrollPosition(id:anchor:)) 使用 Binding<(some Hashable)?>；[containerRelativeFrame(_:alignment:)](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:alignment:)) 使用 Axis.Set；[paging](https://developer.apple.com/documentation/swiftui/scrolltargetbehavior/paging) 按容器分页；[UIGestureRecognizerRepresentable](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable) 使用 makeUIGestureRecognizer(context:)、handleUIGestureRecognizerAction(_:context:) 与 makeCoordinator(converter:)；[动态失败关系](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate/gesturerecognizer(_:shouldberequiredtofailby:)) 在开始识别前决定；[isScrollEnabled](https://developer.apple.com/documentation/swiftui/environmentvalues/isscrollenabled) 是可覆写的环境值。

## 2026-10-22 · 标签栏方案 B：暖色 Liquid Glass

来源为 owner 明确选定的 `/tmp/claude-0/r11/canvas12/project/V12-TabBar-Options.dc.html` 中间 B 方案与 `V12-TabBar.dc.html` 的规则，只读引用。该选择取代历史系统标签栏与系统玻璃＋的外观；现在／洞察／账目／我、横滑、记一笔及各标签导航状态保持。

`YubaiApp.swift` 保留四个 Tab 与各自 NavigationStack，隐藏系统栏，在 RootView 叠加 `FloatingTabBar`：左右 18pt、66pt 高、距底部安全区 22pt，内部 50pt 选中胶囊和 54pt 品牌绿＋；20pt 线性图标、10pt 标签、card 高亮、brandInk 选中色、label 未选中色。高亮以 matchedGeometryEffect 配合 YubaiMotion.layout 移动，Reduce Motion 时无动画。中央按钮沿用 addEntry sheet 与 add 缩放源，不改变 destination。容器按「主导航」分组，保留按钮 identifier 与 selected trait。各根页以 safeAreaInset 留出 88pt；键盘出现期间隐藏栏、释放预留，键盘完全收起后恢复。TabView／NavigationStack 下方以 canvas 铺满安全区。

`DesignSystem.swift` 通过每个标签独立的 environment binding，让 yubaiNavigation 默认隐藏自绘栏、根页出现时恢复；账目根页的 hidesTabBar:false 保留，sheet 的 yubaiSheetSurface 隔离这些更新。新增字体与白色 token，iOS 专用栏／状态不进入 macOS 分支。玻璃底放在 GlassEffectContainer 内，使用 regular.tint(raised.opacity(0.72)).interactive()；降低透明度时使用不透明 raised。按 B 采用 72% 暖色 tint 与淡白色内描边；早一张规则稿的 88%／neutralStrong 描边不再作为这两个参数的依据。原生玻璃的折射、饱和度与阴影不会逐像素等于 HTML backdrop-filter；底部 22pt 以设备安全区为起点。

Apple 官方签名已核对：[glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) 的 Glass 默认为 regular、shape 为 some Shape；[tint(_:)](https://developer.apple.com/documentation/swiftui/glass/tint(_:)) 接收 Color? 并返回 Glass；[interactive(_:)](https://developer.apple.com/documentation/swiftui/glass/interactive(_:)) 的 Bool 默认为 true；[GlassEffectContainer 初始化](https://developer.apple.com/documentation/swiftui/glasseffectcontainer/init(spacing:content:)) 的 spacing: CGFloat? 默认为 nil。

UI 测试全部改为 app.buttons[identifier]，沿用 isSelected；保留全部原用例，补充 push 隐藏／返回恢复、导航分组／按钮顺序、键盘隐藏／恢复、最后一行可见与切换后滚动位置保持。Linux swift test 退出 0：401 项、397 通过、4 项原有实网 opt-in 跳过、0 失败，未改 Core。App 在 arm64-apple-ios26.0／arm64-apple-macosx14.0、UI 测试在 iOS 26 条件下语法解析通过；Apple SDK 类型检查、UI 实跑、玻璃／深色／降低透明度／Reduce Motion／VoiceOver 与导航生命周期设备验收仍待做。`docs/`、HTML 原稿、Figma 与分发包未改，未提交／推送。

## 2026-10-22 · 固定收付「会回来的账单」

### 第十四轮 · 状态与停掉

owner 已确认 `/tmp/claude-0/-home-user-yubai/6e32a199-4f05-5193-b31e-1a97e336dde7/scratchpad/r14canvas/project/` 的 `V14-Bills.dc.html`、`V14-Bills-Stop.dc.html`、`V14-Bills-After.dc.html` 与 `canvas.json / notes.v14n`。本轮在 `fix/fixed-bills-clarity` 采用以下规则，原稿只读保留；下方第十一轮日期点和圆形结清按钮作为历史记录。

`FixedFlowsView.swift` 移除顶部日期点和账单行状态点；分区为「要付／要收／已停掉」。副标题统一「日期 · 状态」，当天到期写「22日 · 今天到期」／「22日 · 今天该收到」，其余为还没到、已付／已收到或「过了 N 天还没记／还没收到」，逾期两种流向均用 amberInk，保留账户、自动、分期和大约。已记的自动标志按实际记账来源，手动结算显示记下日期。只有到期未处理的 Plan 行显示透明描边「付了／收到了」胶囊；已处理为 neutralSoft 灰底勾、整行 0.7 不透明度；提前标记放在未到行的长按菜单。结算继续复用 `settle → store.apply`、长按改金额、提示与快照撤销；VoiceOver 读取状态、副标题、操作名及恢复名称。标题金额下在同一琥珀色行显示「其中 120 已过期 · 5,000 过期没收到」，只有收入逾期时为「5,000 过期没收到」，金额用数字字体并遵循隐藏设置。Core `FixedFlowMonth.overdueInflow` 与支出同源，计算本月未收余额及已停掉旧期，扣除部分已收、排除已收／跳过／今天／未来。页面 20pt、卡片内容 16pt、分区标题内缩 16pt、列表上下 4pt、同组 12pt、区块 24pt、点按区至少 44pt，颜色和字体沿用 token。

停掉统一用 `.sheet(item:)` 底部呈现 `FixedFlowStopSheet`，替换 vphone 发现会指向首行且缺取消的 `confirmationDialog`。按内容测量高度设置 `presentationDetents`，raised 背景、28pt 圆角、serif 20 semibold 标题「停掉「X」？」。有到期未处理项时，正文显示「10月16日这期还没记。」或「还有 N 期没记。」，全宽 50pt 胶囊依次为品牌绿底白字「付了／收到了，记一笔再停」、card 底「没付／没收到，这期也不要了」、labelSecondary 文字「取消」；没有未记期时正文「只停以后的，付过的记录保留。」，保留主按钮「停掉」与「取消」。跨月与今天稍晚的发生时刻均按日纳入。`FixedFlows.stop` 将所有待处理期的结算或跳过与 `endPlan` 合为一个 ChangeSet，失败不部分写入，可整体撤销。`Plan.skippedOccurrences` 缺省为空、兼容旧存档；新增 `skipOccurrence` 验证发生日、保留已有部分付款，已付不作废，跳过不生成账目且拒绝重新关联。月汇总、预测／还能花、自动记、手动匹配与下次发薪复用跳过结果，恢复仍保留跳过。已停掉安排不再生成本月行，停止副标题显示实际停止日期与最近一期「已记／没要」。

适配与差异：sheet 使用系统拖拽条与安全区，内容可滚动、标题与正文高度随字号测量；未到行长按可提前标记。保留全部原 accessibility identifier，新增 `fixedFlowStopSheet`、`fixedFlowStopConfirm`、`fixedFlowStopSkip`、`fixedFlowStopCancel`。专用 rentID 合租记录沿用此前只读边界。旧版 `endPlan` 遗留的到期未结算期（含跨月）归并到唯一的已停掉行，副标题和金额显示全部待处理期，行内「收到了／付了」「不要了」通过 `settle`／`skipOccurrence` 一次处理全部，完成后只留结果与恢复，头部与该行共用余额，Finance 的未付预留／预期收入随之清零，未收款不提前增加还能花；新停掉流程仍在停止前处理全部到期未结算期。示例日期、名字和金额都取实际账本，HTML／Figma／分发包未同步。

验证：指定 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，413 项、409 通过／4 项原有实网 opt-in 跳过／0 失败；固定收付 35 项，其中新增 7 项，覆盖日历天数／夏令时、逾期余额、收支两种停掉分支、跨月多期／部分付款、跳过持久化／恢复／幂等／原子性及当天时刻。Core 原有 28 个、UI 原有 47 个测试方法全部保留，UI 新增 3 个并更新已记状态及停止断言。两个改动 App 文件通过 iOS 26／macOS 14 条件语法解析，UI 测试通过 iOS 26 条件语法解析；`git diff --check` 通过。当前 Linux 环境没有 Apple SDK，App 类型检查／iOS 与 Mac 构建、UI 实跑和设备视觉／VoiceOver 验收仍待做。没有新增依赖，没有修改 `docs/` 或设计稿，未提交／推送。

同日 vphone 三处对齐（本轮）：按 owner 反馈，只修停掉 sheet、当天副标题和逾期收入提示；只读核对 `/tmp/claude-0/r11/canvas14/project/V14-Bills-Stop.dc.html`。指定 swift test 退出 0，419 项、415 通过／4 项原有跳过／0 失败。Core 原有 39 个测试全部保留，新增 2 个覆盖逾期收入余额及合租分摊，扩充当天收付与已停掉跨月／部分收款的断言；UI 原有 50 个测试全部保留，更新 sheet／取消／50pt 全宽按钮、多期文案及收入单独逾期断言。全部 App 与 UI 测试文件均通过 `swiftc -frontend -parse -target arm64-apple-ios26.0`，diff 检查通过；Apple SDK 类型检查、UI 实跑及设备视觉仍待做。仅改相关源码、测试与本设计记录，未提交／推送。

### 第十一轮历史实现

来源为 owner 本轮明确确认的 `/tmp/claude-0/r11/canvas/project/` 四张 HTML 与便签规则；只读引用，不复制或修改原稿。本轮接入已合入的 #25 Core，不改变其规则，取代第四轮固定收付的 90 天汇总、到什么时候与点行结束菜单；保留此前第十一轮交互、系统玻璃＋、TabView 和我页副标题。

| 选定稿 | 采用源码与行为 |
|---|---|
| `V11-Bills.dc.html` | `FixedFlowsView.swift`：当月剩余要付／要收、每日一个状态点、付款／收款分卡；账户、自动、期数、大约、已记组合副标题；绿色收入、估额 ~、已付淡化。共享 `FixedFlowCheck` 以 `settle → store.apply` 结清，长按输入实际金额；复用现有 Toast／完整账本撤销，轻震。左滑露出中性色「停掉」，确认后 `.endPlan`，并提供同名无障碍动作。rentID 行无结清与停掉动作。 |
| `V11-Bills-Add.dc.html` | 同文件 `FixedFlowEditor`：频率／首次日期沿用 popover，月度 chip 写「每月 X 号」；2–60 期或一直；账户未指定时 chip 提示、自动记禁用；保存 autoPay／今天的 autoPaySince／estimated／installments。第二卡两个开关；底部最多四期点阵，移除结束日期和 90 天预留卡。 |
| `V11-Home-Due.dc.html` | `OverviewView.swift`：今天行下最多两条到期付款，含历史未付项；超出链接进固定收付，没有到期项时保留下一笔。`HeroCard` 标题旁显示实际发薪期限或接下来 90 天；计算页文字和付款明细使用同一期限，预测图仍保留原 Core 观察路径。 |
| `V11-Add-Match.dc.html` | `QuickEntryView.swift`：金额、用途、日期、性质、账户及账本变化时刷新首项建议；键盘上方琥珀胶囊需主动选择、可取消，失去匹配即清空选择；保存和还能花预览都传递选定 link。保持已有记一笔布局和加减键盘。 |

`YubaiApp.swift` 为 ChangeSet 应用增加默认关闭的静默选项，启动、前台及解锁后调用自动记账，保留存储／同步／完整快照撤销；自动记账不触发落笔动效、触感或提示。固定收付月数据随原时间派生版本刷新，避免跨日返回前台仍显示旧状态。`DesignSystem.swift` 只为金额补可选 token 色、HeroCard 补期限文字；`EntryFormComponents.swift` 补账户空值提示和可访问值，不引入依赖。

实现适配与差异：系统导航、sheet、菜单、日期选择器、开关和现有系统字体沿用原生外观，未逐像素复刻 HTML。画板样例金额／日期替换为账本实际值；当月列表遵循 `FixedFlows.month`，不会为了画板里的下月工资示例插入下月行。日期点超过七个时换行；同一天多笔以未付优先汇总一个点，VoiceOver 读取全部状态。一次性安排禁用共几期，预览按真实可发生期数最多显示四个。rentID 按本轮明确要求只读，因此与画板普通 Plan「房租」的可结清按钮不同。原额付清已预留付款时 Core 保持还能花不变；收款或变动金额会按真实现金与预留变化更新，未人为扣减两次。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，396 项、392 通过／4 项原有实网 opt-in 跳过／0 失败；没有修改 Core 或删除／跳过测试。`AppFlowTests.swift` 新增 8 项，覆盖付清／撤销、收款后还能花变化及持久化、长按改金额、左滑停掉保留已付期、分期／账户自动记开关与前台结算、历史到期卡与溢出导航、手动建议选择／取消／失效及保存关联、启动自动记账幂等且无提示。现有 UI 用例没有旧结束日期或点行结束菜单流程需要迁移。全部 App Swift 的 iOS 26／macOS 14 条件语法解析及 UI 测试的 iOS 26 条件语法解析通过，`git diff --check` 通过；没有 Apple SDK 类型检查或已执行 UI 测试证据。390pt／大字号／深色、长短按区分、滑动与系统返回、VoiceOver、Reduce Motion 和实际自动记账生命周期仍待 Apple 设备验收。`docs/`、原稿、Figma 和分发包未改；未提交／推送。

接口静态核对参考：[Apple 高优先级手势](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:))、[命名无障碍动作](https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:))。

## 2026-10-22 · 第十一轮交互

来源为 owner 本轮明确批准的 `/tmp/claude-0/r11/canvas/project/` 中五张 V11 HTML；该目录只读引用，没有复制或修改原稿。本轮只接交互，保留 #23 修复、#24 系统标签栏和 #25 固定收付 Core，不扩展固定收付页面范围。

| 选定稿 | 采用源码与行为 |
|---|---|
| `V11-Swipe.dc.html` | `YubaiApp.swift`：根内容的 simultaneous DragGesture 跟手位移，30% 宽度或同方向快速甩动后切换 `store.destination`。顺序为现在／洞察／账目／我，＋不参与；方向在起手时锁定，竖向交给滚动。管家卡和现金图通过根坐标系区域登记排除，根内容以外的 push 页面继续系统返回；Reduce Motion 关闭跟手位移。 |
| `V11-Home.dc.html` | `ButlerViews.swift`：单向左滑露出中性色「知道了」，短滑停在动作位，超过卡宽一半松手调用既有 `dismissCard`，下一条按原有布局动效顶上。右滑不响应，保留 ··· 菜单；容器保留子控件并提供「知道了」无障碍动作。 |
| `V11-Home-Scrub.dc.html` | `DesignSystem.swift / ForecastChart`：0.2 秒长按后逐日拖动，竖线、气泡显示真实日期／星期、`ForecastPoint.conservative` 及当天全部发生项，负数带缺口说明；换日 selection 触感，松手和取消淡出。不拖时只显示 Funds horizon，发薪日取 `horizonEnd`，预测路径仍按 Core 保留的完整观察期。图表提供逐日 adjustable action，不暴露隐藏金额。 |
| `V11-Insights-Tap.dc.html` | `InsightsView.swift`：环形扇区按钮按实际弧形命中，点选增加外径、其余淡化，中心显示分类／占比、金额和总额，对应行高亮；重复点击或中心清除，轻震反馈；行仍进入原类别账目。保留 ChartSegments 的首现登记、时长与配色，筛选窗口变化清除选择。 |
| `V11-Model.dc.html` | `SettingsView.swift`、`CloudAssistantViews.swift`：模型原生 Menu，已选项勾选，两个已知模型有原文副标题，未知模型只显示名字；成功获取显示实际 HH:mm，失败／未配置显示「内置模型」，最后一项「自己填…」进入原 CloudModelEditor。选中复用原保存与生效路径。`DeepSeekClient.swift` 提供带密钥的 GET `/models`，保留可注入 URLSession、版本路径及 Linux FoundationNetworking 约定，不发 chat、不计问答发送记录。 |

实现差异：系统 TabView 和 Menu 使用原生外观与现有系统字体；洞察保留现有时间窗筛选和汇总区，本轮没有采用画板里简化的整页排版。横滑仅移动当前根页，露出区域使用 canvas，相邻内容在松手切换后出现，没有复刻稿中的邻页预览。图中示例金额与日期全部换为真实 Funds／收支；未拖动的提示依本轮规则采用 horizon，取列表失败不显示「刚从 DeepSeek 取到」。这些是实现范围与状态差异，不能视为 owner 额外确认。

验证：Linux `swift build --target YubaiCore && swift test` 通过，396 项、392 通过／4 项原有实网 opt-in 跳过／0 失败；模型列表新增 4 项，覆盖 GET 与鉴权、未知 ID／去重、版本 URL、错误／空响应／离线／取消，不访问真实服务。`AppFlowTests.swift` 新增 5 项，覆盖饼图中心与还原／分类导航、模型菜单与手填、四页横滑与系统返回、管家卡手势、现金图手势归属。App 全部 Swift 和 UI 测试以 iOS 26 条件、App 以 macOS 14 条件语法解析通过，`git diff --check` 通过；这些不是 Apple SDK 类型检查或已执行 UI 测试。设备手势、辅助字号、VoiceOver、Reduce Motion 和视觉仍待 Apple 环境验证。沿用既有文件，工程引用无需增加；`docs/`、原稿、Figma、旧原型及分发包未改，未提交／推送。

接口核对参考：[DeepSeek 模型列表](https://api-docs.deepseek.com/api/list-models/)、[Apple 原生菜单副标题](https://developer.apple.com/documentation/swiftui/populating-swiftui-menus-with-adaptive-controls)、[DragGesture 速度](https://developer.apple.com/documentation/swiftui/draggesture/value/velocity)。

## 2026-10-22 · App Group 默认开启

按 owner 本轮明确要求，`Config/AppGroup.xcconfig` 改为默认 YES，取代第九轮记录中的默认关闭；依据为 [Apple 官方 iOS 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios)的免费 Apple Developer 支持。App 与 Widget 保留先加载共享默认、再加载本机配置的顺序，`Local.xcconfig` 可设 NO 回退为按钮；App 的 `YUBAI_APP_GROUP` 编译条件限定 iPhone SDK，Mac 权限／条件和测试 target 保持独立。iCloud 默认值及开关含义保持。

继续采用已确认 V9 Widget 版式，没有改稿或新增布局：共享容器可用且 App 已发布快照时按尺寸显示还能花、今日统计、最多三项常记。`AppStore` 账本变化／时间刷新发布，锁账本或隐藏金额时删除；`CaptureSnapshotBridge.read` 失败／跨日返回 nil，由现有 Widget 视图显示入口。这些运行路径仅核对源码，没有修改 Swift。生成器没有另设默认，在临时目录生成的 pbxproj／scheme 与仓库逐字节一致，因此不重写工程。

[验证记录](../docs/VALIDATION.md#app-group-默认开启2026-10-22)包含 Linux build／373 项测试、54 组配置静态检查及 App／Widget 语法检查；Apple SDK 类型检查、Personal Team 自动注册／签名与隐私清除的设备行为仍待[清单](../docs/V2-TEST-CHECKLIST.md#app-group-默认开启2026-10-22待-apple-设备验证)。未提交／推送，原始 V9 稿、Figma、历史原型和分发包未同步。

## 2026-10-21 · 快速记账、存储与五个概念合并

本轮按 owner 的 merge2 任务整合 `origin/fix/storage-attachments-compaction`，不新增产品或视觉决定。第九轮快速入口、五个概念、V7 卡片与记一笔日期／分段控件修复均保留；第八轮存储空间、附件按需读取、共享恢复 payload／gzip、对话压缩完整纳入。存储页沿用当前 `DesignSystem.swift` 的符号与展示用词，「余白记得的」只指具体记忆条数；保留已删除指南的决定。我页同时提供快速记账和存储空间。

`LedgerSync.persist` 采用存储接口返回的轻量账本，同时保留 `requiringUnchanged` 与专用锁屏记账权限；`Models.Preferences` 同时编码 `quickCapture` 和 `lastBackupAt`，缺失时分别回退默认配置和 nil。`ScreenshotCaptureView` 保存前复用 `ImageCompression`；抹掉本机数据同时清除待打开的快速记账 sheet，账本替换继续触发原有 Widget 快照更新。原始 V8／V9 画板不改写；设计记录按新到旧、产品票按旧到新保留三路条目。

生成器已核对：App／Widget 源文件与 CoreTests 均自动发现，保留 App、CoreTests、UITests、Widget 四个 target 和两个扩展共用文件；运行生成脚本重建 pbxproj，无手工拼接。[验证记录](../docs/VALIDATION.md#快速记账存储与五个概念合并2026-10-21)包含完整 Linux 测试、兼容性／存储组合回归及 App／Widget 语法检查。Apple SDK 类型检查、UI 测试、设备与真实 iCloud 验收待做；未提交／推送，Figma、历史原型、截图和分发包未同步。

## 2026-10-21 · 快速记账与五个界面概念合并

按本轮合并任务保留双方已采用范围，不新增产品或视觉决定。`SettingsView.swift` 保持消费观内记忆计数、心愿单／每周来信共卡及指南删除，同时保留「快速记账」入口，移除底部重复的旧来信行。`EntryEditView.swift` 保留 Apple Pay 来源胶囊、商户分类映射、删除／好了按钮与普通记录编辑，性质使用 `entryLabel`，购买问题统一为「该不该买」。`DesignSystem.swift` 保留「没分类」标签、新主数字文案与分段控件尺寸修复；`EntryFormComponents.swift` 保留日期弹窗尺寸及可隐藏表头动作。

Siri 结果、截图列表、通知、商户映射与编辑页的分类文案复用 `Classification.displayCategory`，不修改分类存储原值或规则。V7 卡片检测／合并／日期／反馈逻辑保持。`scripts/generate-project.py` 已核对包含双方新增文件与四个 target，再生成工程；没有手工拼接 pbxproj。双方原始设计记录按新到旧保留于下方，产品票按旧到新保存。

合并后的 Linux 构建、346 项 Core 测试、iOS／Mac App 与 iOS Widget 语法解析及工程引用检查见[验证记录](../docs/VALIDATION.md#快速记账与五个界面概念合并2026-10-21)。Apple SDK 类型检查、UI 测试与设备验收仍待做；未提交／推送，Figma、历史原型与分发包未同步。

## 2026-10-21 · 第九轮「快速记账」

owner 在本轮 brief 明确确认 V9 八张画板及 DS「系统入口／动效」，[原稿与任务原文](mockups/quick-capture-v9/README.md)原样长期归档。本轮授权优先于下方旧轮次“不提交”的范围描述。选定稿不代表原生设备验收通过。

| 画板 | 采用源码与行为 |
|---|---|
| Lock／Home-Widget／Control | `YubaiWidgets/YubaiWidgets.swift`：两种圆形锁屏入口、矩形还能花、主屏 small／medium 常记预填、两个 ControlWidget；控制复用两 target 的 `CaptureControlIntent.swift` OpenIntent，所有点击打开 App。共享 `CaptureWidgetSupport.swift` 只传快照；App Group 配置默认关闭，关闭／无权限／跨日均不显示数字。主屏沿用暖纸浅深 token，锁屏单色交给系统。 |
| Siri-Snippet | `QuickCaptureIntents.swift`：本机记账、金额缺失追问、iOS 26 SnippetIntent 的只读结果、用途／金额／分类／账户／时间、还能花、编辑和按 id 撤销；账本锁启用时去掉金额以外的记录信息，隐藏金额时遮住数字。 |
| Pay-Auto／Add-Prefilled | `CaptureNotifications.swift`、`EntryEditView.swift`：本地通知及编辑／撤销动作；沿用改一笔，Apple Pay 状态使用顶部来源胶囊、底部商户分类保存与删除／好了两按钮，不新造编辑页；无把握的记录显示没分类标签。 |
| Screenshot | `QuickCaptureSupport.swift`：Vision 本机读取、多笔勾选、记下 N 笔、原件附件、打开核对进入原 ImportView；读不出金额时返回记一笔并把原图留在其导入入口。`ImportView.swift` 的启发式改为共用 Core 纯函数；Vision 仍留 App。 |
| Me-Quick | `QuickCaptureSettingsView.swift` + `SettingsView.swift`：近七天实际笔数／后台记账笔数、钱包自动化步骤与通知权限、卡到账户及商户到分类两个可增删改的原生列表。 |
| 预填与深链 | `YubaiApp.swift` 只接 sheet／URL 分发和 AppStore 单例，不改 TabView；`QuickEntryView.swift` 仅预填参数、携带截图进入导入及指定的还能花文案，不改日期与分段布局。`EntryFormComponents.swift` 给既有表头增加可隐藏尾部动作的默认参数，Apple Pay 确认在底部。 |

Core `QuickCapture.swift` 复用 EntryAmountParser、ManualBookkeeping 与 Finance；卡／商户偏好和可选来源字段向后兼容。Apple Pay 以原始卡、商户、金额身份和原付款时间做 120 秒去重，软删除后保留凭据；snippet 渲染不会再次记账。所有后台操作在 App 进程内复用同一 MainActor／AppStore／Repository、版本检查与 iCloud 待上传状态，账本锁下仅专用记账和撤销放行。App Group 快照在隐藏金额／启用账本锁时删除。

没有新增动效或包，界面沿用 YubaiMotion 与系统 sheet／导航。Siri／通知／WidgetKit 的外框交给系统，画板的手机背景、系统遮罩、外部字体不复制进应用。实现与原稿的映射不构成逐像素原生验证；390pt、大字号、深色、VoiceOver、减少动态效果、锁屏及系统自动化均待 Apple 设备按[清单](../docs/QUICK-CAPTURE.md#验证与限制)验证。Linux build 和 324 项完整 Core 测试结果见[验证报告](../docs/VALIDATION.md#第九轮快速记账2026-10-21)。Figma、历史原型及分发包未同步。

## 2026-10-21 · 第八轮「存储空间」

owner 明确确认 [storage-v8 三稿](mockups/storage-v8/README.md)并授权实现。原始 HTML 未改写，数字为样例，App 使用本机账本副本与实际文件长度。此轮补充第四轮「我」的维护入口，继续沿用 `DesignSystem.swift` 与 Motion v2；没有新增动效、依赖或独立样式体系。

| 选定稿 | 原生源码与采用范围 |
|---|---|
| `V8-Storage.dc.html` | `StorageView.swift / StorageView`：衬线两行占用标题、brand／series2／neutralStrong 分段条与三行图例、截图与原件卡、恢复历史卡、底部 amberInk／card 抹掉按钮。`SettingsView.swift` 在备份与恢复下一行加入存储空间和实际总大小。恢复历史仍打开现有 `RecoveryVersionsView`，清除使用系统 confirmationDialog。 |
| `V8-Storage-Photos.dc.html` | `StoragePhotosSheet`：3／6／12 个月单选，默认半年；截图数／主目录 payload 大小／账目都留着、原件说明、删除与取消。按附件 createdAt 判断；移除附件并清空账目与导入撤销快照中的截图引用，正常保存留下「删除旧截图」恢复版本，主目录 payload 删除后用既有 toast 显示张数。 |
| `V8-Storage-Erase.dc.html` | `StorageEraseSheet`：有效账目／账户／记忆／截图及原件／恢复历史数量，备份状态，先加密备份打开原 `BackupView`，精确输入「抹掉」才启用抹掉操作。`Preferences.lastBackupAt` 可选兼容字段只在导出成功后记录；之后笔数取 recordedAt／导入时间，不伪造旧记录时间。`AppStore.eraseAllDeviceData` 与 `LedgerSync.swift` 切回仅本机、清除待上传状态与本机目录、换空账本并回到 onboarding；云端账本及钥匙串密钥保留。 |

Core 统计、分类和删除在 `YubaiCore/Storage.swift`／`StorageManagement.swift`。恢复占用包含共享 Payloads 与旧 sidecar；截图以账目引用且不属于任何导入原件判定，撤销过的批次仍保留原件。清理使用 repository 锁／恢复锁，云端截图 payload 经过原有下载与协调；删除失败回滚账本、恢复历史和涉及的 payload。App 实际只操作本机副本，再沿原有上传链同步截图删除。

适配：返回、标题栏、拖拽条与呈现采用原生导航／sheet；sheet 按内容高度呈现并可拉到大高度，小屏与大字号滚动，单选在辅助字号改纵排。复用 Card、Primary／PressButtonStyle、Pill、Toast 与既有列表／sheet 行为；32pt 视觉单选包在至少44pt触控区中。分段条和每条统计有 VoiceOver 文本，按钮／输入框有可访问名称与测试标识。

验证与限制见 [本轮记录](../docs/VALIDATION.md#第八轮存储空间2026-10-21)与 [人工验收](../docs/V2-TEST-CHECKLIST.md#第八轮存储空间2026-10-21待-apple-设备验证)。Linux 可验证 Core；SwiftUI 只做语法与源码核对，Apple 编译、UI 测试及视觉／交互／无障碍验收尚未执行。工程已重新生成；Figma、旧原型和分发包未同步，未提交。

## 2026-10-21 · 五个界面概念

来源为 owner 本轮完整任务；这是明确采用的文案与局部结构调整，不是新增视觉定稿。术语权威见 [CONTEXT.md](../CONTEXT.md#界面用词)，决定与边界见[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-21--五个界面概念owner-明确要求)。本条取代 V3／V4 稿中对应旧文案、我页独立记忆入口和指南；原稿归档保持原样。

| 范围 | 权威源码与采用方式 |
|---|---|
| 我 | `SettingsView.swift`：我的消费观内加记忆总数与本周新增数；下方心愿单／每周来信合为一张卡；保留账户、账目、固定收付及底部导入记录／智能与隐私／备份与恢复；删除指南行和实现 |
| 我的消费观 | `ProfileView.swift`：末节展示最近更新的两条记忆，带日期与中文来源；「全部 N 条 ›」push 原 `MemoryView`，空列表仍可进入；沿用现有暖纸卡片、字体与导航 |
| 还能花 | `OverviewView.swift`／`DesignSystem.swift`：主数字、图例、预测、每周来信与购买判断统一用词；明细页仅列现金、信用卡要还、接下来要付、在存钱、始终留着、日常开销、没写用途的进账、= 还能花，保留付款列表和事实提示 |
| 详情与欢迎页 | `EntryDetailView.swift` 不展示性质行；编辑／版本摘要只展示支出、收入、转账，底层 Nature 不变；`WelcomeView` 保留品牌、先记下此刻的余额与原按钮 |
| 需要留意与每周来信 | `ButlerViews.swift`：空卡片区不显示占位话；标题、标签和明细链接按新词；保留 PR #18 的 V7 检测、合并、日期、证据与反馈逻辑及所有入口 |
| Core 与生成文案 | 仅更新可见模板、错误提示及模型措辞约束；记忆来源使用展示属性，旧分类占位用展示映射；不迁移存档、不改计算、字段、Codable 键、枚举原值或去重键 |

验证见[本轮记录](../docs/VALIDATION.md#五个界面概念2026-10-21)。Linux 不编译 SwiftUI；Apple 构建、两端布局、大字号、VoiceOver 与真机验收仍待做。未提交；Figma、历史原型、截图和分发包未同步。

## 2026-10-21 · 管家的话 V7 异常消费卡

owner 在本轮任务提供已批准的 `V7-Butler-Unusual` 文案与行为，[文字归档](mockups/butler-unusual-v7.md)是本轮来源；没有取得原画板文件，也未新绘制或改动历史稿。采用以下范围，其他卡片沿用现有设计。

| 范围 | 权威源码与采用方式 |
|---|---|
| 原因、用途与日期 | `Assistant/ButlerWording.swift / OffCharacter`：偏高／少见／想克制的模板、用途约 10 字与 Money.text 金额、单笔倍数四舍五入、合并最小倍数向下取整、实际消费日期范围。 |
| 合并与存档 | 同原因同分类／克制领域合并；所有 entry IDs 留在 evidence 和稳定键中。`CardCandidate`／`ButlerCard` 仅新增可选 meta，旧卡片缺字段仍用现有展示。反馈、静音、导入撤销与每周回看复用既有入口。 |
| 原生展示 | `ButlerViews.swift / ButlerCardView`：复用 serif cardTitle、muted 正文按钮及现有依据页；单笔「看这笔 ›／值得」、合并「看看这 N 笔 ›／都值得」，「有点后悔」保持。隐藏金额时仍只显示隐藏提示与依据链接。 |

合并偏高正文的「平时一笔约」取各笔历史的去重并集、排除本卡记录后的均值；标题最低倍数仍按每笔自己的检测均值计算。合并少见／克制标题与有界事实摘要为授权内实现选择，非 owner 提供的额外画板。运行结果见 [本轮验证](../docs/VALIDATION.md#管家的话-v7-异常消费卡2026-10-21)。已通读核对 SwiftUI，Apple 编译、布局、辅助功能与真机验收未执行；Figma、旧原型、截图及分发包未同步，不提交。

## 2026-10-21 · 第四轮「手动优先」

owner 已批准本轮 V4 与 DS，原样保存在 [manual-first-v4](mockups/manual-first-v4/README.md)。任何记账、改账、看账与添加固定收付均有手动入口；问余白继续辅助。以下取代同日 Motion v2 中问余白圆形 tab 及相关缺屏描述，其他既有动效／iOS 26 系统玻璃约定不变。

| 选定稿 | 原生源码与采用范围 |
|---|---|
| `V4-Home.dc.html` / `V4-Home-Saved.dc.html` | `OverviewView.swift`：左眼睛／现在／40pt 问余白；主数字构成条下的今天行、笔数／最近用途／净额，zoom 到 `EntriesView`；仍用 150／96／一行的 `ViewThatFits`。`YubaiApp.swift` 与 `DesignSystem.swift` 复用 pendingEntrySave、数字换位、水面、触感和撤销 toast。 |
| `V4-Add.dc.html` / `DS-Keypad.md` | `QuickEntryView.swift` / `EntryFormComponents.swift`：支出／收入／转账、只用自定义键盘的金额与加减结果、常用分类／更多、用途／账户余额／日期、保存后余白预览、连续记账；通过手动 ChangeSet 保存。导入仅切换到参数为空的 `ImportView()`。 |
| `V4-Entries.dc.html` | `EntriesView.swift`：系统返回胶囊、右侧记一笔、搜索、逐月净收支／逐日进出与懒加载 EntryRow；新行洗色与删除让位复用原动效，隐藏金额同步处理。今天、我均可进入。 |
| `V4-Entry-Edit.dc.html` | `EntryEditView.swift`：原性质、金额、分类／更多、用途、账户、日期与时间、备注、source／recordedAt、就事提问、确认软删除及撤销；保存保留 id／source／recordedAt。洞察与账户的普通记录点开编辑，助手／管家依据仍走 `EntryDetailView`。 |
| `V4-Ask-Empty.dc.html` / `V4-Ask-Typing.dc.html` / `DS-AskBar.md` | `AskYubaiView.swift`：只改空态标题与输入区域；52pt 最小高度、6pt 内距、40pt 加号／单一尾钮、20pt 字行与10pt上下内距、最多5行、底部对齐、三条建议直发。消息列表、草稿卡、发送与听写实现保持其原逻辑。 |
| `V4-Me.dc.html` | `SettingsView.swift` / `DesignSystem.swift`：左空／我／右助手圆钮，账户后新增账目／固定收付卡，保留其余维护入口，指南仍在底部；`InsightsView` 使用同一助手顶栏。 |
| `P-Plans.dc.html` / `P-Plan-Edit.dc.html` | `FixedFlowsView.swift`：标题固定收付，90天非还款安排的要付／要收、活动安排与房租行、结束安排；`FixedFlowEditor` 的要付／要收、金额、名字、周期／首次日期、可选账户、结束日期及90天副本预览。按任务省略 AI 预填、租金与目标卡、进出图及解释性页脚。 |
| 三根页／系统圆钮 | `YubaiApp.swift`：系统 `Tab(role: .search)` 变为 plus／记一笔（`addEntry`，source `add`），保留当前 tab；根页助手为 `askYubai`／source `ask`。Mac 浮钮同样记一笔，⌘N 新建、⌘K 问余白。 |

非 UI 逻辑在 `YubaiCore/ManualBookkeeping.swift`：整数分键盘、分类频次与 CategoryMemory／关键词建议、最近应用内账户、日期落点、保存副本资金预览、编辑保留来源、按天／月汇总与搜索、安排周期和未来发生项。`ChangeSet.EntryDraft` 增加向后兼容的可选转入账户，保留 recordedAt 锚点修复；月收支与 Finance 共用支出／退款口径。

适配边界：样例数据由本机账本替换；字体沿用已采用的系统 rounded／serif，sheet／返回／菜单／日期使用系统控件，不自行模拟玻璃。输入金额、分类芯片和键盘复用现有 token，分类选中内描边 1.5pt。没有新增 spring 或动效；大字号／较小 sheet 允许表单滚动。固定收付直接复用 Finance.occurrences 的90天口径，保留尚未付完的逾期义务，排除信用还款避免本金重复预留。

验证：Linux Swift 6.2.4 的 Core 测试通过（运行结果见 [检查清单](../docs/V2-TEST-CHECKLIST.md#第四轮手动优先2026-10-21待-apple-设备验证)）；SwiftUI 按 iOS 26／macOS 14 目标仅做语法解析与人工 diff 核对，不能代替 Apple API 类型检查。新增手动记账 UI 流程源码尚未运行；390×844 首屏、输入条单行基线、保存顺序、转账、深色／大字号／VoiceOver／减少动态效果与 Mac 仍待设备验收。工程已按生成器的 App 顶层 swift glob 重新生成；没有改 ImportView 内部、AskEntryDraftCard 或网络服务，也未提交。Figma、旧原型与分发包未同步。

## 2026-10-21 · Motion v2 与 Liquid Glass

owner 本轮明确批准 motion v2 与 iOS 26 Liquid Glass，按所附 README 的「玻璃／动效／SwiftUI 对照」、tokens 和交互样机接入。三份输入[原样长期保存](motion-v2/README.md)，本轮指令中的已批准状态优先于原文件遗留的「待确认」。本次取代下方 V3 的 iPhone 自绘导航与 iOS 18 部署描述；V3 其余页面结构继续沿用，不改财务规则或 Core。

- `DesignSystem.swift`：集中三种 spring、时长与曲线；数字用 numericText，隐藏金额／减少动态效果用 160ms 淡入淡出或终态。首现图表与水位按进程登记，离开时结束；预测线横向揭示，低点下落与单次外圈，环图逐段长出／角度变形、柱从基线生长。环图着色放在动画 mask 外，避免颜色渐变。
- `YubaiApp.swift`：iOS 系统 TabView 三页，search role 作为问余白动作，selection binding 保留原页；新根页方向偏移 12pt，首开无入场。保留 `tab_*` 标签标识，UI 测试按系统标签文字查找。Mac 侧栏与旧版安全留白保持；系统栏接管 iOS 底部安全区。
- 浮层：顶栏圆钮、提示条、助手输入条和 Mac 问余白圆钮用系统 glassEffect；顶栏组合使用 GlassEffectContainer。sheet 容器不再强盖 canvas，内卡／列表仍为暖纸；iOS 系统导航提供返回控件，内容详情用 matchedTransitionSource／zoom，设置列表继续 push。所有新增玻璃 API 均有 macOS 26 可用性分支。
- 2026-10-23：洞察分类明细真机出现 zoom 期间首行被导航栏遮挡、结束后回落，源码排查指向目标 ScrollView 的导航栏安全区更新时序（尚无设备 inset 采样）；为避开该路径，仅分类明细及同结构的记录详情移除成对 zoom、回退标准 push，sheet zoom、分页与 macOS 行为保持，首帧稳定性及返回仍待真机复验，旧稿／Figma／分发包未同步。
- 保存：持久化成功后识别实际新增／删除记录；sheet 收起后英雄数字换位、水带 keyframe 单次晃动与成功触感，380ms 后提示条入场，名义时长至 680ms。撤销只换回数字与轻触感；整批撤销抑制删除触感。替换账本或锁屏会取消待播反馈。行插入／删除让位、首次新行洗色、管家收起、分段滑块、助手消息入场和 4 秒提示条下滑关闭已接线。
- 新增 `MotionState.swift` 的 Foundation 逻辑测试，直接与 App 共用源文件编入 UI 测试 bundle；新增问余白保留当前页的 UI 流程。工程生成器同步 iOS 26 与源文件引用；PackageDescription 升到 6.2 以使用 `.iOS(.v26)`，Swift 5 语言模式、macOS 14 与 Linux Core 排除 App 的规则保持。

缺屏：当前没有原型中的独立「记一笔」数字键盘／分类选中芯片、「今天 → 账目」总账页、独立「想一想」五道水位购买完成页；没有为本任务新造这些页面。现有问答补记、导入、分类／账户／依据记录列表已接入对应保存与行反馈。分类芯片的缩放 helper 已备好，但无该类选中芯片可接。

系统标签图标当前使用静态水位模板资产与 SF Symbols，原型的逐带／扇区／点头自定义图标动画未实现；标签栏的玻璃选择动作交给系统。问余白的 zoom 来源已绑到系统 Tab 标签，原生 Tab 标签提取是否保留来源几何、圆钮的 tint 效果仍需 Xcode 26 真机确认，不能当成已验收。

本轮只有[静态检查](../docs/VALIDATION.md#motion-v2--liquid-glass静态核对2026-10-21)，没有 Swift 类型检查、Apple 构建、Core／UI 测试运行或视觉、VoiceOver、减少动态效果设备验收。旧 Figma、历史 HTML、截图和发布包未同步；不提交、不推送。

## 2026-10-20 · 记忆与智能设置选定稿

owner 本轮明确确认八张记忆与智能设置画板，按当前 `feat/ai-memory-drift-fixes` 源码结构接入；批准设计稿不代表已经完成原生设备验收。[原样保存的画板](mockups/ai-memory-v3/README.md)补充并取代下方相应的「缺画板／界面待确认」历史状态。

| 用户确认的画板 | 对应权威源码与实现 |
|---|---|
| [V3-Ask-Remember](mockups/ai-memory-v3/V3-Ask-Remember.dc.html) | `AskYubaiView.swift` + `MemoryView.swift / RememberedRows`；一次 update 保存记忆及待确认提案，新增／更新各一行，撤销调用 Memory.undo，旧回答不会覆盖后来编辑过的记忆 |
| [V3-Memory](mockups/ai-memory-v3/V3-Memory.dc.html) | 新 `MemoryView.swift`；三组非空记忆、日期／中文来源／原话，原生列表支持左滑删除，点开编辑或删除；空状态沿用用户指定的唯一补充文案 |
| [V3-Me](mockups/ai-memory-v3/V3-Me.dc.html) | `SettingsView.swift`；消费观与心愿之间的记忆入口及本周新增计数，智能入口使用 brand-tint 已配好标签；Mac 的「我」复用同一页面 |
| [V3-Letter-Learned](mockups/ai-memory-v3/V3-Letter-Learned.dc.html) | `ButlerViews.swift / WeeklyLetterCard`；依据下方的 brand-tint 卡，每句“不对”调用 Memory.reject 后隐藏 |
| [V3-Letter-Review](mockups/ai-memory-v3/V3-Letter-Review.dc.html) | 同上，learned 后为 amber 回顾卡；保留刷新确认日期，修改进入消费观，删除经现有 ButlerProposalView 确认；过时问题不继续展示 |
| [V3-Ask-Judge](mockups/ai-memory-v3/V3-Ask-Judge.dc.html) | `AskYubaiView.swift / AskPurchaseCard`；本地引用读取带 confirmed_at 的原则／领域，显示“你 X 月写过”，未知时间和超过180天沿用 core 的提示约定 |
| [V3-AI](mockups/ai-memory-v3/V3-AI.dc.html) | `SettingsView.swift / IntelligencePrivacyView` + `CloudAssistantViews.swift`；云端与隐私两组、当前模型及编辑、钥匙串密钥输入、会话发送总数和原稿说明；原有来信提醒、设备锁与外观项继续保留在下方 |
| [V3-AI-ModelError](mockups/ai-memory-v3/V3-AI-ModelError.dc.html) | `CloudAssistantViews.swift / ModelUnavailableNote` + `IntelligenceRuntime.swift / CloudAIStatus`；按稿显示实际模型名，问答内提供设置入口；错误状态留本机，成功请求或保存模型后清除 |

只扩展 `DesignSystem.swift` 的小动作按钮与标签高度，继续使用现有语义颜色／字体／卡片。记忆列表使用原生分组 List 以提供两端删除能力，编辑器沿用原生 Form；原稿没有独立编辑画板。每周回看在管家刷新早退之前执行，成功原子保存并更新来信，失败静默。本轮重新生成 Xcode 工程，仅完成源码通读、Swift 语法解析和工程静态核对；编译、iPhone／Mac 布局、深色、大字号、VoiceOver、网络及 Keychain 验证待做，见 [验收清单](../docs/V2-TEST-CHECKLIST.md)。

**2026-10-20 第三轮选定稿**：本轮 owner 明确批准本地 `design-ref/mockups/V3-*.dc.html` 全 13 稿及 `design-ref/ds`（来源目录为 `/tmp/claude-0/-home-user-yubai/daae97b0-203d-51d2-aee2-e0a1c7360177/scratchpad/`）。`refactor/v2-design-alignment` 已以此对齐 SwiftUI：iPhone 三 tab 浮动同排导航，Mac 三项侧栏与根页问余白圆钮；现在只露一张管家卡、来信入口与可收缩图表，洞察复用 Finance 的净收支口径，其余稿沿用真实数据和已有目的地。图表仍展示现有引擎已扣预留的保守路径；无依据的示例内容不补造。仅语法与工程静态检查，编译、两端视觉、Dynamic Type、VoiceOver 与设备验收待做；下方候选／缺画板记载为对齐前历史，Figma、旧原型与分发包仍未同步。

更新：2026-10-20。当前为「余白 2.0 · 管家」，沿用暖纸设计系统与原生 SwiftUI 组件构建候选 UI；页面视觉尚未定稿，采用不等于用户已经完成个人体验验收。用户决定与 Agent 实现选择以[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-20--余白-20管家决策归档)为准。

## 2.0 设计资源与缺口（2026-10-20）

2026-10-19 的390pt 页面稿早于 2.0；它与暖纸设计系统提供既有风格依据，不覆盖 2.0 的全部页面。当前 UI 使用 [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift) 的 token、Card、Page、按钮、文字与图表组件直接构建，是实现候选，不能记为最终视觉。旧 Figma、HTML 原型、截图和发布包均未同步。本轮未绘图，页面稿 artifact 无法通过浏览工具读取，来源与日期沿用既有记录。

以下七类均**尚无对应的 2.0 画板**；源码存在只说明实现已写，不表示布局与交互已通过验证。

| 缺少的画板 | 当前候选实现 | 「同步设计稿」需覆盖的状态 |
|---|---|---|
| 消费观画像页 | `ProfileView.swift` | 愿意多花／想克制、软线、原则、底线、目标、空内容与待确认提案 |
| 冷启动对话 | `ProfileConversationView.swift` | 一次一问、跳过、等待／失败、整份画像提案确认与取消 |
| 心愿单 | `WishlistView.swift` | 考虑中／已买／放弃、交易匹配歧义、回访及反馈 |
| 每周来信 | `ButlerViews.swift` / `WeeklyLetter.swift` | 来信正文、七日曲线与数字、依据、数据不足与历史回算说明 |
| 导入问题 | `ImportView.swift` | 最多五题的分组、选项与自由补充、稍后处理、离线待整理与整批撤销 |
| 推送 | `WeeklyPush.swift` / `SettingsView.swift` | 默认关闭、主动开启、权限请求／拒绝、系统设置入口与每周提醒文案 |
| 问余白回答卡片 | `AskYubaiView.swift` | 数字与图表、依据详情、未核实金额、修改提案确认／拒绝、购买判断、心愿、语音与截图金额确认 |

下一次「同步设计稿」以 2.0 的现在／我／问余白和 owner 的规格为范围，补齐上述画板及两端、深色、大字号与异常状态，再记录候选反馈和采用情况。旧稿保留原位置与历史含义，不把实现截图反写为用户定稿。本轮只维护记录；owner 最后在 Mac 按[组合清单](../docs/V2-TEST-CHECKLIST.md)验收，当前仅有静态解析与工程引用检查，没有编译或运行证据。

下节为 2026-10-19 迁移及随后旧页面修复的历史，五项导航、本机模型、洞察页等描述已被当前 2.0 范围替代。

## 2026-10-19 · 设计系统迁移

- 本次采用的视觉依据是暖纸设计系统与390pt 页面设计稿；生产样式的长期权威仍是 [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift)。
- 已将 `Sources/YubaiApp` 的现有页面、编辑器与子页面迁移到 `YubaiColor` / `YubaiFont` / 间距与尺寸 token；移除兼容主题与图标方块。首页采用 `HeroCard`，分类占比改横条，现金预测采用台阶线，导入与购买结果使用水位记号，反馈使用 `Toast`。长列表用带分隔线的惰性列表卡；编辑器保留系统 Form。
- 已采用：按设计系统 SwiftUI 对照移除三套颜色主题，`Preferences.colorTheme` 仅为旧存储兼容保留，界面忽略其值；不打包字体，数字用系统 rounded 等宽数字、衬线用系统 serif、正文用系统字体。助手页面尚未实现，因此保留五项原生 `TabView` 与 Mac 侧栏；原有操作和数据流程不变，聊天、语音、自动备份不纳入本次迁移。
- Step 3 修复按钮样式作用域、购买水位映射、待明确记录元信息、金额精度与 Mac 底部留白；拆分图表表达式，洞察汇总每次渲染只计算一次。预计收入仍以虚线预测路径与直接文字标签显示。
- 已做 Swift 语法树解析、旧样式残留扫描，以及标识符、快捷键、store 更新动作与说明文案的静态对照。当前环境没有 Swift / Apple SDK；iOS 与 macOS 编译、390pt 真机布局、深色、大字号、辅助功能与长账本性能均未执行验证。
- 现有 Figma 画布、旧截图、历史原型和既有验证报告未同步，不代表这次迁移的视觉或运行验收。
- 合并 E10 / E14 / E18 修复时保留上述设计：资金偏好三项显示持久标签并保留相同的 accessibility label；导入历史的导出 / 撤销、本机模型的下载 / 删除使用独立按钮样式。保留退款分类跟随原支出的存储同步与跨统计区间查找；复核 AppStore 更新、撤销、恢复和示例切换均清空相关缓存，单次遍历资金计算保持原逻辑。此次仅完成差异与源码静态复核，未运行 Swift 构建或 UI / Core 测试；外部设计资源未同步。
- 2026-10-20 无障碍修复：洞察分类横条列表显式使用 `.accessibilityElement(children: .contain)`，容器标签为「分类消费分布」，各行继续独立朗读分类、笔数与金额；视觉样式不变。已静态检查应用中的其他 accessibility label，未发现其他同类容器覆盖子项标签的问题；未运行 Swift 构建或设备 AX 验证，外部设计资源未同步。

## 当前应用设计

2026-10-20 按用户批准的 2.0 范围采用「现在／我 + 问余白」。Agent 用两端共用 SwiftUI 导航容器底部 accessory 实现常驻入口（使用 safeAreaInset，不依赖 iOS 26 专属 accessory API，保持 iOS 18 / macOS 14 的部署范围）；Mac 侧栏仅有现在与我。现在保留来信、管家、保守可动用与计算依据、Finance 待付款列表、导入；移除原首页独立资金走势图与手工维护页面，图表继续用于来信和问余白回答，洞察 tab 已删除。记录详情从依据打开，删除只能通过撤销或恢复版本找回。目标编辑器仅由 ProfileView 使用，问余白直接展示自己的补记草稿，不需要旧记录编辑器。导入记录与恢复版本分开，后者在备份页面下。旧偏好和 isSample 不再控制运行界面，存档仍保留，SampleData 只在测试目标。数字默认看 90 天，底线只取消费观，日常生活自动估算；具体数值和算法属于 Agent 实现选择。现有 Figma、HTML 原型和历史截图均未同步；无 Swift / Apple SDK，布局、底部安全区、VoiceOver、类型检查与五条离线 UI 测试尚未运行验证。


「我」的备份入口现为「备份与同步」，两端共用 LedgerSyncSection / SyncVersionsView：默认仅本机，可用时才显示 iCloud；读取时显示「正在从 iCloud 读取…」。切换遇到不同账本或同步冲突时，展示各自更新时间、版本时间、设备名（如有）、有效记录数、附件数和最多三笔差异，用户明确选定一份；另一份留本机恢复历史。位置切换可取消；未解决的同步冲突保留入口并阻止继续修改。采用现有 Form、Picker、Section 与样式 token，没有新增主入口。当前仅静态核查，未执行两端编译、布局、VoiceOver 或真实 iCloud 冲突验证，外部画布和包未同步。

| 资源 | 权威位置与用途 |
|---|---|
| 颜色、字体、基础视图 | `Sources/YubaiApp/DesignSystem.swift`；暖纸浅/深色语义 token、衬线标题、系统中文正文与 rounded 等宽金额；品牌绿只强调动作和图表 |
| 应用信息架构 | `YubaiApp.swift`；iPhone 两个 tab、Mac 两项侧栏，问余白底部常驻按钮；根视图处理账本锁、文件打开和错误 |
| 现在 | `OverviewView.swift`；来信和管家、保守金额与计算依据、只读待付款及结束安排、导入账单，不展示无依据的「可放心花」承诺 |
| 依据与账户 | `EntryDetailView.swift` / `Editors.swift`；依据打开记录来源，账户编辑和核对保留；不再提供独立账本或关联页面 |
| 整理 | `ImportView.swift`；文件/截图入口 → 账户对应 → 自动归类与少量例外 → 保存结果 → 可直接离开；不强迫逐笔审核 |
| 消费观与问答 | `ProfileView.swift` / `AskYubaiView.swift` / `WishlistView.swift`；消费原则、领域、底线和目标，问答数字、依据、提案与心愿 |
| 我与维护 | `SettingsView.swift`；七个维护入口、导入批次整批撤销、加密备份、可选 iCloud 同步与版本选择、恢复版本、智能与隐私和指南 |
| 云端智能 | `IntelligenceRuntime` + `YubaiCore/Assistant/` 轻量 harness + DeepSeek，唯一模型路径；共用发送前后的快照保护，默认关闭；商户与备注可发送，敏感字段须脱敏，实际覆盖待验证，见 `docs/ASSISTANT.md` |
| 图标 | `Assets.xcassets/AppIcon.appiconset`；本项目生成的深青绿余白符号，不依赖远端素材 |

基础组件包括 `Page`、`Card` / `CardRows`、`AmountLabel`、`HeroCard`、`EntryRow`、`Pill`、`InlineNote`、`EmptyState`、`Toast`、`BrandMark`、`AssistantMark`、`WaterLevelView`、`ChartGrow` 和主次按钮；均有实际调用。使用 SwiftUI 原生表单、导航、选择器、sheet、文件选择、SF Symbols 和 Swift Charts；卡片无描边、阴影和渐变。

大字号下，金额与待付款行通过纵向排布保持可读；已移除旧筛选与示例提示。金额不只靠颜色说明；入/出、性质、未知和异常均有文字。输入错误留在当前编辑页，不丢弃表单。触控、VoiceOver、设备认证与所有尺寸并未穷尽验收，已执行范围见 [验证记录](../docs/VALIDATION.md)。

2026-10-02 按用户明确要求建立 [Figma 全动作派生稿](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=13-3367)。三页分别为全动作 UI/UX、组件与参考、Mac 与共用流程；包含 111 个手机状态、11 个 Mac 画板、42 个本地组件（含 28 个图标）、43 个变量和 8 个文字样式。这些数量属于 1.0，不包含上方七类 2.0 新画板。

原生源码仍是应用实现的权威来源；Figma 是可编辑实现映射与设计说明，没有自动双向同步，也没有因画布排版回写应用。Figma 使用 Noto 字体和 Lucide 图标替代，Apple UI Kit 已检索但无法导入；通用反馈及系统控件以明确标注的示意表达。详细来源、逐动作索引、截图验证和原型播放限制见 [Figma 交付说明](../docs/UI-UX-FIGMA.md)。本轮画图不代表用户已确认最终视觉，不替代当前业务或真机验收。历史 HTML 继续保留为早期行为候选。


2026-10-08 新增[当时版本的浏览基线](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=40-6983)：当时完整页面和状态映射，用于逐页讨论，没有因画图采用改版。保留旧 Figma 页面，尚未同步 2.0。字体、系统控件与交互表达边界见[交付说明](../docs/UI-UX-FIGMA.md)。用户当时确认喜欢风格，但认为信息密度过大；该反馈不等于 2.0 新页面已经视觉验收。

## 历史候选登记（2026-09-20）

以下保留原资料，描述当时阶段；当前采用状态以上文及第 13 票为准。

更新：2026-09-20。状态：基础约定已记录，视觉未定。产品事实以[决策地图](../.scratch/yubai-product/map.md)与子票为准；这里将其连接到设计任务，不替代未解决的业务决策。

## 证据和采用状态

- **已确认约束**：来自地图明确记载的用户决定，可直接约束方案。
- **候选行为/视觉**：Agent 建议或原型演示，可供比较，不等于用户已选定。
- **待决定**：影响资金、数据边界或产品范围的未决问题，回对应子票讨论。
- **已实现/已验证**：分别要求实际代码与对应运行证据，不能从设计稿推断。

目前没有用户选定的视觉方案，也没有委托 Agent 定稿的记录。

## 从真实任务开始

用户场景：每周集中整理多个渠道账单，日常可补充截图或手工记录，希望减少维护负担。朋友按月转来房租分摊、用户按季度付租，使账户余额不能直接代表可花金额。事实来源：[地图 Notes](../.scratch/yubai-product/map.md#notes)。

当前局部任务：**一批记录整理结束 → 用户看摘要，可直接离开，也可补充用途或批量纠正 → 系统显示结果并保留可恢复入口 → 用户不必逐笔审核即可结束这次整理。**

采用边界：自动分类、只询问特别不明的记录或放入其他，是已确认方向；具体摘要、分组补充、返回路径和撤销呈现属于[导入结果原型](../.scratch/yubai-product/issues/12-import-result-prototype.md)候选。导入解析、去重、资金核对与真实保存尚未实现，规则见[多入口记录](../.scratch/yubai-product/issues/04-import-and-reconciliation.md)。

原型输入是合成汇总：3,972 条明确记录、26 条其他支出、2 条用途未知，共 4,000 条，仅展开代表记录。不能据此推断 AI 准确率、耗时、真实数据分布或完整交易处理能力。

### 关键状态与缺口

| 情况 | 当前候选表达 | 需要继续的部分 |
|---|---|---|
| 导入结果可查看 | 摘要后提供返回总览与查看分类入口 | 用户反馈层级是否清楚；真实导入完成判定未定 |
| 普通消费用途不够细 | 留在“其他支出”，按需批量修改 | 初始分类集合与学习规则见[分类票](../.scratch/yubai-product/issues/11-automatic-categories.md) |
| 入账性质/用途不明 | 保留未知，可整组或分别补充，也可稍后再说 | 对可动用资金的影响见[资金票](../.scratch/yubai-product/issues/02-funds-and-obligations.md)，当前不展示推测金额 |
| 没有疑问 | 草稿有“全部明确”的演示切换 | 应用中的空状态文案和后续动作尚未选定 |
| 想纠正或反悔 | 批量改类、补充用途均留内存历史，可撤销 | 跨页面、持久保存和重新导入后的撤销边界未定；现有通用撤销文案待体验时审视 |
| 暂时离开后再回来 | 同一页面会话内可重新查看导入 | 刷新/关闭即重置，真实持久恢复尚未设计 |
| 正在等待、导入失败、部分成功、重复或余额冲突 | 当前原型未覆盖 | 在[完整整理体验票](../.scratch/yubai-product/issues/07-weekly-experience.md)及其依赖规则收敛后补充，不能把失败画成整理成功 |

### 能力范围的读取路线

本轮先整理上述导入结果任务及设计资料。它不等于首版唯一能力，也不自动把下面的能力变成开发清单。

| 用户要完成的事 | 已有依据 | 当前设计状态 |
|---|---|---|
| 了解资金与义务 | [账户、信用负债、基金](../.scratch/yubai-product/issues/02-funds-and-obligations.md) | 计算口径待决定 |
| 维护月收季付的房租 | [房租分摊](../.scratch/yubai-product/issues/03-shared-rent.md) | 分摊、预留与异常场景待决定 |
| 从现在安排未来资金 | [动态资金安排](../.scratch/yubai-product/issues/09-dynamic-money-plan.md) | 方向已确认，规划范围和自动调整边界待决定 |
| 导入、补记并纠正账本 | [多入口记录](../.scratch/yubai-product/issues/04-import-and-reconciliation.md)、[分类](../.scratch/yubai-product/issues/11-automatic-categories.md) | 局部原型候选；全流程未完成 |
| 犹豫购买时寻求建议 | [购买前咨询](../.scratch/yubai-product/issues/05-purchase-advice.md) | 用户主动发起已确认，依据与缺信息处理待决定 |
| 找到值得调整的消费 | [消费回顾](../.scratch/yubai-product/issues/06-spending-review.md) | 候选分析与反馈方式待决定 |

首版取舍由[首版边界票](../.scratch/yubai-product/issues/08-first-release-boundary.md)决定。用户已否定把固定周期、逐笔审核、人物编号维护作为产品前提；代用户执行真实转账和投资交易在现有产品范围之外。更完整的成熟产品能力全景留到参考调查阶段补齐。

## 指导取舍的原则

| 保护的体验 | 因此怎样设计 | 适用边界与来源 |
|---|---|---|
| 一次整理可以轻松结束 | 默认自动归类，普通细类未知允许归其他，纠正入口按需展开 | 不把性质不明当成确定收入；方向来自地图，具体分组与退出方案待反馈 |
| 理解钱实际能做什么 | 区分账面进出、用途与未来义务；待规则明确后展示依据 | 不自行编造可花金额公式；[资金票](../.scratch/yubai-product/issues/02-funds-and-obligations.md)未解决 |
| 资金安排跟着现实变化 | 从当前时间和已知付款日期推演，保留实际租金日期 | 固定账单导出区间仍可用于筛选；不因此固定资金管理周期 |
| 用户容易纠正系统 | 建议展示影响范围、支持批量修改和撤销，金额由用户修正 | 撤销持久性仍是候选；AI 不以“整理”名义改金额 |
| 补充的是钱的用途 | 用自然语言问这笔钱做什么，允许少量未知 | 必要字段见[云端边界票](../.scratch/yubai-product/issues/01-cloud-data-boundary.md)，姓名留本地的方向不代表具体外发字段已获批准 |

## 布局与视觉的当前依据

目标是个人自用的 iOS 应用，来源为已有产品地图；本轮未选择技术栈。现存 HTML 用左侧手机式页面展示结果，右侧展示演示状态和场景引导。右侧控制台帮助讨论，不属于正式应用的信息架构。

候选主任务依次呈现整理结果、分类摘要、少量未知用途、按需纠正与离开入口；原型还包含总览占位、分类概览、分组补充与批量修改。未决定底部导航、完整首页、深色模式、正式字号或品牌色。后续做移动端方案时，以实际设备尺寸和真实长度中文观察层级、触控与可读性。

现有 HTML 声明焦点样式、文本状态和 `aria-live`，只是源码证据；实际键盘、读屏、对比度与布局尚未验证。正式稿需要让未知、选中、成功与失败可由文字理解，并检查放大字体与关键动作是否可达。此为设计建议，不是已通过的无障碍验收。

## 样式与组件登记

唯一候选数值来源：[原型内嵌 CSS](../.scratch/yubai-product/prototypes/import-result.prototype.html)。本轮核对了源码，没有提取第二份 tokens.json；所有颜色、尺寸和字体仍为候选。原型之外尚无应用样式目录或生产组件库。

| 已有 CSS 名称/选择器 | 用途 | 来源与采用状态 |
|---|---|---|
| `--ink`、`--muted` | 主文字、次级说明 | 原型 `:root`；候选，正式数值未选 |
| `--green`、`--pale` | 主动作、选中及浅色提示底 | 同上；候选，尚未建立语义状态色体系 |
| `--line`、`--paper` | 分隔线、页面底 | 同上；候选 |
| `body`、`h1/h2/h3`、`.small` | 系统字体栈与文字层级 | 原型样式；未做 iOS 动态字体映射 |
| `.phone`、`.section`、`.choices` | 页面容器、分区、选项布局 | 原型样式；演示外框不能直接升级为应用组件 |

| 候选组件及源码入口 | 已出现的行为/状态 | 正式化前的缺口 |
|---|---|---|
| 摘要 `metrics()` / `.metrics` | 明确、其他、未知三组计数 | 标签是否易懂、窄屏与大字体表现 |
| 主动作 `button.primary` | 返回结果、返回总览等 | 明确页面主次与等待/失败状态 |
| 用途补充 `renderApp()` 的 `questions` 分支 | 整组选择、分别选择、稍后再说 | 分组依据、影响范围和未知对资金的含义 |
| 分类修改 `other` 分支 | 26 笔合成记录批量修改、撤销 | 真实筛选、个别排除、持久历史与反馈文案 |
| 反馈 `#status`、撤销历史 `ImportDemo` | 内存状态更新、文本提示 | 应用内反馈位置与持久恢复；控制台不可直接照搬 |

提取条件：视觉被用户选定或在明确委托范围内定稿，重复样式和组件已有实际用途。届时保留现成体系；若采用 CSS 则以工程样式为权威，若采用原生平台则登记实际样式文件。按用途命名，记录来源、派生画布及同步方向；无需求时不预建多主题或完整组件库。

## 下一轮设计与实现交接

继续可见设计时，先读取本文件、入口和原型记录，沿用本任务与合成数据边界，补足相关参考后制作或调整候选。按[启动协议](../产品设计启动协议.md)默认使用 Open Design，首次生成前落实模式与额度说明；已有选定模式时沿用。

只有选定方向后，才将其升级为正式视觉资源。交接须同时指向：本轮真实任务、选定画面、关键状态、样式来源、可复用组件和未决业务行为。现在能交接的是资料与局部候选，尚不能宣称资金计算、账单导入或正式 UI 已可直接实现。

本轮验证范围：文件存在、引用和来源一致、原有记录与原型保留。历史静态检查结论以原型票为准；本轮未运行原型或真实业务测试，也未设置使用成效指标。

## 2026-10-22 第十三轮 · 留白规范

来源为 owner 本轮明确的 Apple HIG + 4/8 网格修正清单；对应设计稿页面为「第十三轮 · 留白规范」。本轮采用这些留白与点按尺寸，权威数值仍在 `Sources/YubaiApp/DesignSystem.swift`，不调整业务规则、文案或颜色。按本轮写入范围，只更新 App 界面源码与本文；设计入口、产品票、HTML 原稿、Figma 与分发包未同步，未新建或宣称已更新设计稿页面。

公共约定：页面左右 20pt，卡片、列表与汇总小卡水平内边距 16pt，卡片文字距屏幕边 36pt；`Card.standard`／`.compact` 四边 16pt，`.list` 上下 4pt，行高由 `CardRows.rowHeight` 与行内容撑开，对齐「第十三轮 · 账目」的 `padding: 4px 16px`；区块之间 24pt，同组 12pt，标题到内容 8pt，操作到内容 12pt。保留全部旧 token，`space6`／`space10`／`space18` 标注「已停用，仅兼容」，本轮界面不再引用它们；H1 原有滑动内缩及标签几何另用专属 token 保留原值。44pt 最小点按区通过标签内部的 `yubaiHitTarget()` 和矩形 contentShape 建立，视觉背景先绘制，再透明外扩；相邻控件按各自占位排布，不叠加重叠的点击 overlay。

| 编号 | 源码位置与本轮采用的修正 |
|---|---|
| H2 | `YubaiApp.swift / FloatingTabBar`：栏高 66，屏幕左右 20，底部安全区上方 8；栏内左右 8；选中块高 50、圆角 25，上下左右边距按 8 排布；中央＋为 54，左右各留 8。保留现有实色、选择及分页逻辑。 |
| H3 | `EntryFormComponents.swift / EntryChipLayout、EntryCategoryChips`：分类与「更多」视觉高 32、点按区至少 44；横向间距 8、换行视觉间距 12。换行计算扣除点按框比芯片多出的 12，避免重复增加留白，纵向点击框相接而不重叠。 |
| H4 | `EntryFormComponents.swift / EntryAccountMenu、EntryDateChip`：账户、日期、时间胶囊视觉最小高 32，背景外扩至至少 44 的点按区。 |
| H5 | `OverviewView.swift / 顶栏`、`DesignSystem.swift / AskToolbarButton、TabRootHeader`：眼睛与问余白视觉 40、点按区至少 44；占位同步 44，标题居中。 |
| H6 | `AskYubaiView.swift / inputBar`：＋、麦克风／停止、发送均保留 40 视觉并增加至少 44 的点按区；推荐问题胶囊最小高 44，同组间距 12。 |
| M1 | `DesignSystem.swift / Page` 及 `OverviewView`、`EntriesView`、`QuickEntryView`、`EntryEditView`、`AskYubaiView`、`ProfileConversationView`、`ImportView`、`StorageView`、`CloudAssistantViews`、根页浮层：页面与底部操作栏的左右边距采用 `insetPage`。 |
| M2 | `DesignSystem.swift / Card、AssistantCard`、`EntriesView / total`、`InsightsView / tile`、`FixedFlowsView / bills、FixedFlowBillRow`：卡片／列表／汇总小卡水平内边距统一 16；`Card.list` 上下 4，`.standard`／`.compact` 四边 16；移除存储用量卡及汇总卡的重复内缩。保留 Card.Style 调用接口。 |
| M3 | `DesignSystem.swift / EntryRow、CardRows、editorForm`，以及 `EntriesView`、`EntryFormComponents`、`SettingsView`、`CloudAssistantViews`、`FixedFlowsView`、`OverviewView`、`Editors`、`QuickCaptureSettingsView`、`QuickCaptureSupport`、`StorageView`：单行最小高 48、两行最小高 56；账目页分类＋备注为两行，`CardRows(day.entries)` 统一使用 `rowHeight: YubaiSize.rowDouble`（56）。行内 padding 放在最小高度之前，长文、大字号与多内容行仍可自然增长。主按钮原 52pt 尺寸保留。 |
| M4 | `Page` 默认区块间距 24；`EntriesView` 日期组、`ImportView` 导入组、`SettingsView` 隐私分组、`ProfileView` 消费观分组、`Editors` 账户分组、`WishlistView` 心愿分组等采用标题间距 8；同组卡片及内容采用 12，操作与正文之间采用 12；现在页与存储页等同步公共 token。 |
| M5 | `EntriesView / 日期组标题`、`SettingsView / heading`、`FixedFlowsView / 要收、已停掉`、`ImportView / group.title`：标题内缩从 4 调到 16，与列表内容边缘对齐。 |
| M6 | `DesignSystem.swift / Segmented`：常规字号下，底板视觉高 40、选中块高 32、四边 4；按钮自身透明占位高 44，底板上下各内收 `(44−40)/2`，不被点按框撑高。大字号保留纵向排列和自然增高。 |
| M7 | `QuickEntryView / 记下，再记一笔`：最小高度由 40 改为 44。 |
| M8 | `EntriesView / monthPicker`：依「第十三轮 · 账目」排列为 `[<] 年月 [>]`、Spacer、搜索，HStack 间距 4；左箭头用 `yubaiPageArrowTarget` 贴页面左边距，44pt 点击框向左外扩；右箭头紧跟月份，用普通 44×44 点按区；搜索视觉 40、点按区 44，视觉右缘贴页面右边距。`InsightsView / 时间范围` 仍用 `yubaiPageArrowTarget` 将两端箭头贴页面左右边距；保留月份／时间切换与搜索动作。 |
| L1 | 本轮 25 个 App Swift 文件的显式 spacing、padding、Spacer minLength 使用 token；不再引用 2／6／10／18 的旧间距 token，也不保留裸数字的这些布局调用。原有字体、图形尺寸、线宽、圆角、手势阈值与 H1 专用几何不当作布局间距替换。 |
| L2 | `DesignSystem.swift / CardRows`、`EntriesView / CardRows(day.entries)`：有图标列表的分隔线从卡片边起 16 + 36 + 12 = 64，卡片内额外缩进 48；无图标列表从卡片边起 16。 |
| L3 | `InsightsView / legend`：取消内容左右额外 8 的内缩；选中背景用负 padding 向外扩 8，不移动文字与金额。 |
| L4 | `ButlerViews.swift / cardContent`：类型行与标题统一 trailing 留位 48，避让右上角 ⋯ 的 44pt 点按区。 |
| L5 | `QuickEntryView / 金额、记下后还能花`、`EntryEditView / 金额、来源说明、商户提示`、`FixedFlowsView / 添加金额`：移除多余的横向 4，贴齐页面 20pt 边距。 |

验证：`git diff --check` 通过；临时只读源码核对覆盖 25 个改动 Swift 文件，确认写入路径符合本轮限制、旧 token 名称全部保留、间距／尺寸 token 引用均有定义、显式布局调用无裸数字间距、旧 2／6／10／18 间距 token 引用为零；Swift 字符串字面量、颜色和字体定义保持，H1 三处左滑按钮背景及露出常量在解析 token 后与修改前一致。未修改 YubaiCore、业务测试断言或依赖，未提交。

已尝试对全部改动文件执行 `swiftc -parse`，但本会话容器未安装 `swiftc`（`command not found`），也没有历史记录中的 `/opt/swift-rootfs/usr/bin/swiftc`；尝试从 Swift 官方站点取得工具链时，配置的网络代理不可达，直连 DNS 也不可用，因此语法解析未执行，不能记为通过。Apple SDK 类型检查、iOS／macOS 构建、设备视觉与点按区实测均待有工具链的环境完成。macOS 条件分支和既有平台行为保留；源码核对不等于编译或视觉验收。


## 2026-10-23 · 帮你省钱第一阶段：输入组件与数据交接

owner 本轮只授权非界面能力与输入条复用／消费观发送反馈，不制作购买结论、追问、冷静期、省下的钱、订阅体检、克制进度或两级分类的新画板与界面。采用决定与实现区分见 [第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-23--帮你省钱第一阶段非界面owner-明确任务)。

指定交互：`AskYubaiView.swift` 中的文字框、发送按钮及其字体、行数、高度、内边距、颜色与按钮样式提为同文件内 `ChatInputBar`，问余白保留＋菜单和原语音／停止替换条件；消费观仅使用文字框与发送按钮，发送时即时清空、立即显示用户气泡，失败恢复输入，重试替换尚未成功的用户轮次。首次开场失败后也可直接输入。`ProfileConversationView` 标题／入口与旧三问提示保持，Core 自动再聊及三类开场上下文已可用，后续需按设计稿同步提示。此处按 owner 新要求复用，取代历史 DS-AskBar 中仅用于问余白的使用范围限制，原稿文件保留。

必要的数据适配：`CloudAssistantViews` 只替换两个模型说明键名；`IntelligenceRuntime` 挂接云端启用时的小项批处理；`ButlerViews` 仅为新增 `CardKind.cooldownDue` 补「心愿单」枚举标签，保证穷举编译完整，没有新增卡片样式或按钮。

[公开 API、文件清单、设计阶段七项注意及验证](../docs/SAVING-CORE-PHASE1.md)。Linux Core build 与448项测试通过，新增42项；5个改动 App 文件的 iOS 26／macOS 14 条件语法解析通过。SwiftUI 类型检查、输入／失败回填／语音／多行的设备与无障碍验收尚未做。HTML、Figma、截图与分发包没有同步，不把本轮数据接口视为已完成界面设计或设备验收。


## 2026-10-23 · 第十五轮「帮你省钱」界面

owner 指定 设计稿画布「第十五轮 · 帮你省钱」 的 12 张 `V15-*.dc.html`、NOTE.txt 与 DS-README.md 为本轮唯一依据，允许 App 接线，不提交、不联网调 API。采用记录见 [第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-23--第十五轮帮你省钱界面owner-指定稿)。取代上一节「留待设计」的界面缺口，不追改历史验证结论。

[交付记录](../docs/SAVING-UI-V15.md)逐稿登记源码、完整修改文件及新增可见文字：`SavingPurchaseViews` 承载 Ask／Wait／Buy／Skip；`SavingViews` 承载 Wishlist／Letter／Profile／Revisit／Entries／Restrain 的共享入口和数字；`SubcategoryViews` 承载 Entry-Sub／Insights-Sub。原页面只接线；旧文案清理分支的行保持，只有整块替换的旧购买卡与 owner 指定的消费观思考／进度例外。

复用现有 DesignSystem 颜色与字体，26px 衬线结论取 lead 22px，40px 数字取 amountInput 38px 并取整，未新造 token。近限额一行取 RestrainProgress 的较大比例、最多一条；≥80% 琥珀，over 仍用原卡。三处再聊带对应上下文，消费观内容决定冷启动／再聊，已开始模式保持；未配云端入口仅禁用。洞察保持所选期间，未归小项并入其他，和上月比取完整上月；首页合并扇区仍进原记录列表。来信原图、三个数字、记忆和提醒开关保留，新增成对省钱数字与订阅卡放在正文后。心愿邀请的「不用了」收起本次页面邀请。

Linux build／449 项测试通过（新增 1 项独立退款小项回归），全部 App 文件的 iOS 26／macOS 14 条件语法解析、工程引用、token 与保护文案核对通过。没有 Apple SDK 类型检查、UI 实跑或设备视觉验收；完整待验项见交付记录。HTML 原稿保留给定位置且未改，Figma、旧原型、截图和分发包未同步，未提交／推送。


## 2026-10-23 · PR #34 编译修复与截图夹具

沿用第十五轮已采用稿与「少写字」规则，不新增页面、外观或说明文字。按 owner 的 Xcode 真编译错误修正分类枚举调用标签、抽出小项网格选择芯片，并逐个复核 SavingPurchaseViews、SavingViews、SubcategoryViews 及八个接线页面；把复杂选择状态、筛选／汇总、聊天气泡、行和导航拆开，让 SwiftUI 分别求类型。Core 签名／访问与可选性逐项对照定义。模型名按 owner 提供的官方原文更正为 deepseek-flash／deepseek-v4-pro。

新增 judge-ask／judge-wait／judge-buy／judge-skip／wishlist-cool／letter-saving／profile-revisit／subcategory 八个合成截图脚本，限制仍为 Debug＋模拟器＋UUID 测试账本。问答继续通过脚本 transport 执行真实工具；来信通过真实 candidate 生成首封并保持未静音，周四以后从我页打开。截图入口、全部文件和验证见[交付续记](../docs/SAVING-UI-V15.md#2026-10-23--pr-34-编译修复与截图夹具)。Linux 449 项测试（445 通过／4 原有跳过／0 失败）、8 脚本离线 Core 执行及 App iOS／macOS 语法解析通过；新增 8 个 UI 流程仅静态检查，Apple 真编译／UI 实跑及截图验收待做。HTML、Figma 和分发包未改，无提交／推送。
