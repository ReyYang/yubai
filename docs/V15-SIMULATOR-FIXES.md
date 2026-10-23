# V15 模拟器显示修复与 UI 测试核对 · 2026-10-23

基线：`feat/butler-saving-core`，`57ac7bf`；开始时工作树干净。owner 报告该基线 Xcode 编译通过、55 个 UI 测试 34 过／21 失败。本轮没有 Mac／Apple SDK，不能把下面的源码判断写成修后 UI 实跑通过。

已逐张查看 `scratchpad/shots/` 的全部 15 张 PNG，并对照 `scratchpad/mockups/V15-*.dc.html` 的全部 12 稿和 DS-README／NOTE。给定原稿和原截图保持原样；采用 owner 本轮修正及「少写字」，没有增加说明句。

## 八项显示修复

1. **再聊输入条**：`ProfileConversationView` 的透明 leading 改为固定宽、零高；`ChatInputBar` 的 leading／accessory 各限制在图标高度，输入条按内容取理想高度，文字框仍为 1–5 行。消费观 toolbar 同时统一成 ToolbarItem，保留完成和先跳过。
2. **发送即气泡**：两处发送原已在起 Task 前清空输入／写入用户消息；实际可见性还被 `MessageEntrance` 从透明开始的动画延迟。本轮让用户气泡第一帧即不透明、无位移；保留助手入场、失败回填与重试替换。再聊截图夹具可延迟最终回复 3 秒，在回复前检查气泡和清空输入。
3. **追问卡**：消息有稳定滚动 id，追问回复按消息 `.top` 定位，其他消息仍滚到最新底部；新断言检查第 1 题在导航栏下。
4. **购买主按钮**：`ViewThatFits` 的横排候选按完整文字固有宽度测量，避免先折行后误报能放下；放不下走全宽竖排，两种候选均 `lineLimit(1)`，Ask／Wait／Buy／Skip 共用规则。
5. **心愿单**：冷静到期的在想行不再生成冷静状态；本月增加额与主数字共用 `AmountLabel.text(..., decimals: 0)`；回访标签只写买了一个月，标题保留 X，用得怎么样？，卡内不再重复独立问题。
6. **每周来信**：Core 零变化模板改为还能花和上周持平；删除模板正文内省钱合计与订阅问句。改写提示和接收检查同时阻止模型补回这些重复项。旧存档通过展示函数去掉精确旧模板重复句，不修改存档；数字事实和订阅数据保持。三个订阅夹具扣款日为当月 3／12／24 日。
7. **我的消费观**：额度已在进度事实中出现，去掉独立额度行；标题前缀／空格／金额格式等归一后与额度等价的原话不显示，含额外背景的原话仍保留。芯片复用 ChipFlow，水平／垂直间距均为 YubaiSpace.space8。
8. **记录详情**：时间、账户、关联账户与分类行统一以 rowSingle 为最小高度；来源为手动且归类理由只是手动选择时去掉末行，其他非空归类理由继续保留。

## 手势的代码修复与验证边界

- `HorizontalPan` 先决定方向，再允许祖先 UIScrollView 的 pan 开始；原来只等待横向滚动，外层竖向列表仍可能先抢走横拖。竖向起手立即失败，放行竖滚；未展开账目／管家卡继续只接左滑。筛选自己的子滚动可同时识别，不为它建立相互等待。
- 固定收付 iOS 从独立的 DragGesture／GestureState 复位链改为同一 HorizontalPan；保留 macOS 原分支。这样不再依赖 dragging 复位与 onEnded 的执行先后。
- 根分页继续原生 paging；中途位置只记入 visibleTab，滚动停稳才更新 destination，避免半程切换无障碍页面和触发关闭状态。
- 这些路径属于行为问题，不能归因于少写字或 V15 导航。源码存在争抢／复位风险，已作修正；具体哪条 Mac 失败由哪种时序触发，仍需原失败日志和 Mac 实跑确认，不声称 Linux 已复现全部手势失败。

## UI 测试逐项判断（全部 55 条）

owner 没有提供完整 21 条失败的方法／失败行列表，因此下面列出全部 55 条的判断，覆盖已点名的失败和相关手势／固定收付用例；未把关联用例臆记为已失败。没有删除、跳过或减少用例。测试的隐藏动作检查使用不可点击；删除记录和收起卡片仍要求真正消失。

| 测试 | 判断与本轮处理 |
| --- | --- |
| `testJudgeAskScreenshotFixture` | 显示回归：回复追问卡按顶部定位；新增第 1 题在导航栏下的坐标断言。 |
| `testJudgeWaitScreenshotFixture` | 显示回归：横排按完整文字测量，放不下改全宽竖排；新增按钮高度断言。 |
| `testJudgeBuyScreenshotFixture` | 同一购买按钮布局路径；保留买吧／记一笔断言。 |
| `testJudgeSkipScreenshotFixture` | 同一购买按钮布局路径；保留本机资金边界和 620 的事实断言。 |
| `testWishlistCoolScreenshotFixture` | 测试可视区 + 本轮文案变化：先保留首屏截图，再滚至放了 12 天；回访标签用 wishFollowUpAge；断言不出现 0 天冷静状态。 |
| `testLetterSavingScreenshotFixture` | 显示回归：断言正文不重复数字格／订阅卡；扣款日分别为 3／12／24 日。 |
| `testProfileRevisitScreenshotFixture` | 显示回归：限制输入条高度；脚本延迟回复 3 秒，在回复前断言用户气泡已出现且输入清空；新增发送后截图。 |
| `testSubcategoryScreenshotFixture` | V15 导航已是主项→小项→记录；现有完整路径保持，记录详情行高在源码修复。 |
| `testFixedBillCheckMarksPaidAndUndoRestoresIt` | 不是删文案：房租 300 已记下仍存在。改为 toastMessage 定位并等待，继续断言文字、已付／撤销／再付、金额和记录数。 |
| `testFixedIncomeCheckIncreasesAvailableAndPersists` | 业务行为仍有效：等待已收到／禁用状态，再验证还能花增加与重启持久化。 |
| `testFixedBillLongPressChangesAmountBeforeRecording` | 业务行为仍有效：保留长按改金额流程，等待已付状态；金额 900／1 笔仍为硬断言。 |
| `testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow` | 行为回归路径：固定收付 iOS 改用 HorizontalPan，停掉用 stopFixedFlow_ 定位；保留已收记录与重启断言。 |
| `testFixedBillStopAndResumeBothSupportUndo` | 同一左滑行为路径：修识别器，停掉按钮用 identifier；停掉、撤销、恢复、再撤销均保留。 |
| `testFixedBillEditorUsesInstallmentsAndAccountGatesAutomaticRecording` | 现有少写字表单断言已适配，未删业务检查；保留账户门槛、2 期、自动／大约和前台自动记。没有日志不能认定该条就是四项失败之一。 |
| `testDueCardIncludesPreviousMonthAndLinksOverflowToBills` | 测试定位：moreDueBills 源码文字未删，显式无障碍 label／数字 value 避免组合标签含箭头的精确匹配；仍断言溢出 1 笔、结清／撤销及进入固定收付。 |
| `testManualBillSuggestionRequiresSelectionAndCanBeCancelled` | 现有业务规则有效，保留选择／取消／改金额取消匹配／保存关联断言。 |
| `testAutomaticBillsRecordOnceOnLaunchWithoutToast` | 现有业务规则有效，保留只记一次、不出自动提示、重启仍已付断言。 |
| `testStorageEntryAndOverviewOpenFromMe` | 少写字：旧说明句已由账单原件／不删的灰色事实行替代。改为 storageOriginalsPreserved，不恢复说明句。 |
| `testDonutSelectionChangesSummaryAndCanBeCleared` | V15 导航变化：点主项进入餐饮 · 本月小项页；优先等 subcategoryInsights，仍核对新导航标题，环图选中／清除断言保留。 |
| `testModelMenuSelectsInlineAndKeepsCustomEditor` | 现有模型 identifier 与新模型名已匹配；保留内联选择与自定义编辑。 |
| `testRootSwipeSkipsAddTabAndPushedPageKeepsSystemBack` | 不是删文案：智能与隐私标题未变。按行为回归处理根分页停稳同步；新增页面 identifier 等待，仍硬断言原标题、push 后不分页、系统边缘返回。 |
| `testTabButtonsScrollToNonadjacentPagesAndPreservePageState` | 行为回归路径：根分页停稳再切当前页；保留非相邻跳转、重选和月份状态。 |
| `testTabTapReturnsToLedgerAfterRightSwipe` | 行为回归路径：同上；三次滑动后点回，仍校验唯一选中、内容可点和实际横向位置。 |
| `testTabTapReturnsToOverviewAfterLeftSwipe` | 行为回归路径：同上；三次滑动后点回与跨页切换检查保留。 |
| `testHorizontalFiltersKeepPagingAndVerticalScrollingSeparate` | 手势优先级：横向筛选子滚动可同时识别，其祖先列表／分页先等判向；筛选不翻页、竖滚不误开编辑器继续检查。 |
| `testButlerSwipeDismissesWithoutSwitchingTabs` | 知道了未被删；短滑回弹后应不可点，不要求无障碍节点永久移除。用 dismissButler_restrain／hittable 检查，超过 25% 必须真正移除卡片。 |
| `testButlerFastShortSwipeDismisses` | 行为回归路径：同一 HorizontalPan 优先级修复；保留 1200 速度短扫与真正移除卡片断言。 |
| `testButlerFastLongSwipeDismissesWithoutPaging` | 行为回归路径：同一修复；保留快速长扫、现在仍选中、内容可点与未翻页检查。 |
| `testButlerRightSwipeAtFirstPagePreservesCardAndPaging` | 行为回归路径：右滑继续让给分页边界；隐藏动作按专有 identifier／不可点击检查，后续左右翻页保留。 |
| `testClosedLedgerRowPagesRightAndRevealedRowClosesFirst` | 行为回归路径：列表先等横拖判向；未展开右滑翻页、展开后右滑先收回再翻页；显式控制行内拖动。 |
| `testRevealedLedgerRowConsumesSwipesInBothDirections` | 行为回归路径：同上；保留展开行／删除动作上的左右拖动、分页锁与轻点编辑检查。 |
| `testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt` | 行为回归路径：同上；仍要求只有一项删除动作、另一行收回及点外面关闭。 |
| `testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab` | 行为回归路径：同上；三次慢左滑仍展开且不翻页，右滑关闭后可翻页。 |
| `testLedgerRevealClosesAfterTabSelectionAndPaging` | 行为回归路径：横拖判向 + 根分页停稳同步；切页收回、展开时锁页、点外面后可翻页保留。 |
| `testLedgerRowSwipesDoNotOpenEditorAndTapStillWorks` | 行为回归路径：同上；仍检查慢拖、双向翻页、轻点编辑和记一笔。 |
| `testLedgerMonthFiltersAndSearchToggle` | 文案与 identifier 仍匹配，保留月份／筛选／搜索全部断言。 |
| `testLedgerSwipeDeleteAndUndoRestoresRow` | 行为回归路径：横拖不再与竖向列表争抢；显式行内慢拖；必须真正删除记录，再撤销恢复，不用不可点击代替记录删除。 |
| `testDonutSwipeDoesNotSelectSlice` | 行为回归路径：根分页停稳同步；环图滑过后必须未选中、未进小项页；额外从主项行左滑翻页并验证未误入小项。 |
| `testLedgerRowsStillScrollVerticallyAndOpenWithTap` | 行为回归路径：竖滑在判向阶段放行；保留竖滚收回删除、行离屏及轻点编辑检查。 |
| `testOverviewRowSwipeAtTabBoundaryDoesNotTapRow` | 边界滑动仍须不触发 todayEntries；保留随后点按进入账目。 |
| `testForecastHoldAndDragKeepsTheCurrentTab` | 现金图已有独立长按拖动；本轮保持，仍检查停在现在页。 |
| `testFirstLaunchEmptyLedgerAccountAndAvailableFunds` | 现有少写字欢迎页与五个导航控件断言保持。 |
| `testManualAndAskActionsPreserveTheSelectedPage` | 根分页联动复验：四页的问余白／记一笔与 sheet 返回保持，不移除用例。 |
| `testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible` | 保留键盘隐藏浮栏、末行在栏上及切页恢复滚动位置断言。 |
| `testManualKeypadSaveTodayEditAndDelete` | 保留手动金额、当天统计、编辑与删除的完整流程。 |
| `testImportOrganizeAnswerAndUndoEntireBatch` | 现有文案与 identifier 保持；保留导入、回答、撤销、重新导入与原有记录存续。 |
| `testRestrainCardCanBeMutedAcrossLaunches` | 保留以后别提与重启后的静音持久化。 |
| `testAskNumericAnswerEvidenceAndEntryDetail` | 保留真实离线工具取数、明细与记录详情入口；详情只清理重复来源文字。 |
| `testProfilePrinciplePersistsAndBackupOpens` | 保留消费原则持久化与备份入口。 |
| `testAskMemoryCanBeOpenedEditedAndDeletedFromMe` | 保留问答记忆、我页查看、编辑与删除流程。 |
| `testForecastPlaysOncePerVisitAcrossScrollingAndViewLifetimes` | MotionState 既有本机状态检查，本轮没有相关规则或文案变化；保留原断言。 |
| `testReducedMotionSkipsPlaybackAndDoesNotReplayDuringSameVisit` | MotionState 既有本机状态检查，本轮没有相关规则或文案变化；保留原断言。 |
| `testChartClaimsSurviveViewLifetimesAndStayIndependent` | MotionState 既有本机状态检查，本轮没有相关规则或文案变化；保留原断言。 |
| `testTabDirectionAndReselection` | MotionState 既有本机状态检查，本轮没有相关规则或文案变化；保留原断言。 |
| `testOnlyNewActiveEntriesTriggerSaveAndMissingActiveEntriesTriggerDeletion` | MotionState 既有本机状态检查，本轮没有相关规则或文案变化；保留原断言。 |

## 可见中文变更（含条件删除）

| 位置 | 变更 | 四类规则 |
| --- | --- | --- |
| 来信正文 | 还能花比上周保持原样 → **还能花和上周持平** | 事实 |
| 来信正文 | 删除 **本周省下 X。累计省下 Y。** 和 **这些还在用吗？A、B、C。**；数字格、订阅卡原题继续保留 | 去重；无新增说明 |
| 心愿单本月 | **这个月 +1,299.00 → 这个月 +1,299**（实际金额动态） | 数字事实 |
| 心愿单到期行 | 删除 **冷静中 · 还有 0 天**，未到期仍显示剩余天数 | 状态 |
| 买后卡 | **买了一个月 · 用得怎么样？ → 买了一个月**；删正文 **用得怎么样？**；保留标题 **X，用得怎么样？** | 状态／标题 |
| 想克制的 | 去掉独立 **每周最多 N 次／每月最多 ¥X.XX**；去掉与标题和额度同义的用户原话，例如夹具的 **外卖每周最多 3 次／数码电器每月 800**；保留进度事实与独特背景 | 去重，未删除用户数据 |
| 记录来源 | 来源已为手动时，删除重复 **手动选择** | 去重 |
| 来信夹具 | 三条 **每月 24 日** 改为分别 **每月 3 日／每月 12 日／每月 24 日** | 日期事实 |

没有新增标题／数字事实／控件／状态以外的可见文字。prompt、accessibilityIdentifier 和完整读屏文案属于非可见内容。

## 验证

- 最终 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test`：**451 项，447 通过、4 项原有实网 opt-in 测试跳过、0 失败**；实网用例保持 opt-in，没有调用真实 API。
- 38 个 App Swift 文件：iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug 的 `swiftc -frontend -parse` 通过。`AppFlowTests.swift` iOS 26 条件解析通过。
- 新增 Core 两项：零变化句式；旧存来信有／无数字格与订阅卡时只删除重复模板。现有脚本 transport 测试补充模型重复问句回退断言。
- 八个截图夹具从 App 源文件去掉 Debug／模拟器外壳后离线编译链接真实 YubaiCore，全部通过账本校验；letter-saving 扣款日核对为 [3, 12, 24]。这会改变实际周比较（2026-10-23 为减少 ¥12），UI 不把夹具写死为持平；零变化句式另由 Core 用例验证。
- `git diff --check`：通过。
- **尚待 Mac**：Apple SDK 类型检查、全部 55 条 UI 测试、修后截图／实际字号和手势复验；Linux 语法解析不替代 SwiftUI 类型检查。
- 未提交、未推送、不联网调 API；HTML／Figma／分发包未同步。
