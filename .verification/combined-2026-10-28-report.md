# 2026-10-28 合并验证报告（#46 #47 #48）

- 总结论: 有 FAIL（#47、#48）
- 分支与提交: test/combined-verify-2026-10-28 @ cd4576b6d91778b5bcebc9876437ba960b867268
- 时间: 2026-10-28（Asia/Shanghai）；UI 2026-10-28T11:19:40+0800 至 2026-10-28T12:16:48+0800
- Xcode: Xcode 27.1；Build version 27A9275
- 模拟器: iPhone 17 Pro Max，iOS 26.5 (23F77)，id 37FDA39F-AF08-48EA-9E35-0AAB017AAFE0

## 逐个 PR 结论

| PR | 结论 | 一句话理由 |
|---|---|---|
| #46 银行卡流水导入 | PASS | 编译、重点 Core 和导入 UI 通过，B1–B3 符合。 |
| #47 记一笔 sheet | FAIL | 五个指定 UI 首次通过，但 M6 短用途“午饭”在芯片上只显示“午”。 |
| #48 认出工资 / 还没分类 / 云端入口 | FAIL | 两个指定 UI 稳定失败；S5 固定收付页未显示新工资。 |

## 编译

- 结果: 成功（新一轮 `build-for-testing` 一次成功）。

## Core 测试

- 通过 / 失败 / 跳过: 546 / 1 / 4；551 个用例，失败用例内有两条断言失败。
- 失败: `StorageTests.testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten`（`StorageTests.swift:235`，main 原有）。
- 重点 8 组全部通过：SalaryDetectionTests 14、BankStatementImportTests 12、ImportTests 17、ImportBalanceTests 13、BeeCountImportTests 7、ImportColumnTests 5、CategoryModelTests 34、FinanceTests 31。

## UI 测试

- 总数 / 第一次通过 / 时好时坏 / 稳定失败 / 跳过: 79 / 73 / 0 / 6 / 0；耗时约 57.1 分钟。
- 稳定失败（每项三次均失败；以下保留首次原始断言）：
- `testButlerFastLongSwipeDismissesWithoutPaging` | AppFlowTests.swift:1321 | 画面显示咖啡提醒卡，测试找不到其容器标识 | #48（按本轮归属规则；根因未确认） | [截图](combined-2026-10-28/ui/testButlerFastLongSwipeDismissesWithoutPaging.png) | [层级](combined-2026-10-28/ui/testButlerFastLongSwipeDismissesWithoutPaging.txt) | 首次断言原文: Failed to get matching snapshot: No matches found for first query match sequence: `Descendants matching type Any` -> `Elements matching predicate '"butlerCard_restrain" IN identifiers'`, given input App element pid: 87580
- `testButlerFastShortSwipeDismisses` | AppFlowTests.swift:1309 | 画面显示咖啡提醒卡，测试找不到其容器标识 | #48（按本轮归属规则；根因未确认） | [截图](combined-2026-10-28/ui/testButlerFastShortSwipeDismisses.png) | [层级](combined-2026-10-28/ui/testButlerFastShortSwipeDismisses.txt) | 首次断言原文: Failed to get matching snapshot: No matches found for first query match sequence: `Descendants matching type Any` -> `Elements matching predicate '"butlerCard_restrain" IN identifiers'`, given input App element pid: 87837
- `testButlerRightSwipeAtFirstPagePreservesCardAndPaging` | AppFlowTests.swift:1334 | 画面显示咖啡提醒卡，测试找不到其容器标识 | #37（已知右滑测试，本次稳定失败） | [截图](combined-2026-10-28/ui/testButlerRightSwipeAtFirstPagePreservesCardAndPaging.png) | [层级](combined-2026-10-28/ui/testButlerRightSwipeAtFirstPagePreservesCardAndPaging.txt) | 首次断言原文: Failed to get matching snapshot: No matches found for first query match sequence: `Descendants matching type Any` -> `Elements matching predicate '"butlerCard_restrain" IN identifiers'`, given input App element pid: 87931
- `testButlerSwipeDismissesWithoutSwitchingTabs` | AppFlowTests.swift:1284 | 画面显示咖啡提醒卡，测试找不到其容器标识 | #48（按本轮归属规则；根因未确认） | [截图](combined-2026-10-28/ui/testButlerSwipeDismissesWithoutSwitchingTabs.png) | [层级](combined-2026-10-28/ui/testButlerSwipeDismissesWithoutSwitchingTabs.txt) | 首次断言原文: Failed to get matching snapshot: No matches found for first query match sequence: `Descendants matching type Any` -> `Elements matching predicate '"butlerCard_restrain" IN identifiers'`, given input App element pid: 88052
- `testPendingImportsOrganizesOnlyAfterTapWithFakeTransport` | AppFlowTests.swift:88 | 画面显示待分类卡，测试找不到其容器标识 | #48（按本轮归属规则；根因未确认） | [截图](combined-2026-10-28/ui/testPendingImportsOrganizesOnlyAfterTapWithFakeTransport.png) | [层级](combined-2026-10-28/ui/testPendingImportsOrganizesOnlyAfterTapWithFakeTransport.txt) | 首次断言原文: Failed to get matching snapshot: No matches found for first query match sequence: `Descendants matching type Any` -> `Elements matching predicate '"pendingImportsCard" IN identifiers'`, given input App element pid: 97642
- `testWelcomeCloudSettingsPersistThroughStatementOnboarding` | AppFlowTests.swift:119 | 画面显示待分类卡，测试找不到其容器标识 | #48（按本轮归属规则；根因未确认） | [截图](combined-2026-10-28/ui/testWelcomeCloudSettingsPersistThroughStatementOnboarding.png) | [层级](combined-2026-10-28/ui/testWelcomeCloudSettingsPersistThroughStatementOnboarding.txt) | 首次断言原文: Failed to get matching snapshot: No matches found for first query match sequence: `Descendants matching type Any` -> `Elements matching predicate '"pendingImportsCard" IN identifiers'`, given input App element pid: 1741
- 时好时坏: 无。
- 必须第一次通过的 14 个:
  - `testSalaryConfirmationChangesHorizonAndUndoRestoresCard`：第一次通过。
  - `testRejectedSalaryStaysDismissedAfterRelaunch`：第一次通过。
  - `testPendingImportsPageOpensCloudSettingsWithoutRequests`：第一次通过。
  - `testPendingImportsOrganizesOnlyAfterTapWithFakeTransport`：第一次失败，三次均失败。
  - `testWelcomeCloudSettingsPersistThroughStatementOnboarding`：第一次失败，三次均失败。
  - `testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator`：第一次通过。
  - `testManualKeypadOperatorsAndPurposeKeyboard`：第一次通过。
  - `testManualKeypadSaveTodayEditAndDelete`：第一次通过。
  - `testTransferWithOneAccountCanAddDestinationWithoutLosingDraft`：第一次通过。
  - `testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet`：第一次通过。
  - `testWelcomeStatementBalanceReviewAndCommit`：第一次通过。
  - `testWelcomeStatementWithoutBalanceAndAccountSwitch`：第一次通过。
  - `testFirstLaunchEmptyLedgerAccountAndAvailableFunds`：第一次通过。
  - `testImportOrganizeAnswerAndUndoEntireBatch`：第一次通过。

## 手动检查

- B1 #46：符合，已导入 5 笔、余额 16872.71，不导入 0。[B1-read](combined-2026-10-28/pr46/B1-read.png)
- B2 #46：符合，4 笔支出 228.58、1 笔收入 100.70，标题无账号尾巴。[B2-review](combined-2026-10-28/pr46/B2-review.png)
  - 源源烧烤 · 快捷支付：支出 200.00，餐饮；Cotti+Coffee · 快捷支付：支出 5.90，餐饮／咖啡饮品；蚂蚁（杭州）基金销售有限公司 · 快捷支付：支出 5.88，没分类；杭州崇宇信息科技有限公司 · 银联快捷支付：收入 100.70，没分类；杭州全家便利店 · 快捷支付：支出 16.80，购物／日用百货。细分类由提交后的合成账本读回。
- B3 #46：符合，2025 年 10 月账目有 5 笔；抽查 Cotti+Coffee 备注保留「对手信息：Cotti+Coffee 2088111111111111」。[B3-entries](combined-2026-10-28/pr46/B3-entries.png)、[B3-detail](combined-2026-10-28/pr46/B3-detail.png)
- M1 #47：PASS，sheet 暖色空白处取色 #f7f4ea，和现在页对应位置一致。[M1-sheet](combined-2026-10-28/pr47/M1-sheet.png)
- M2 #47：PASS，三个长用途靠左同一行且显示省略号。[M2-recent](combined-2026-10-28/pr47/M2-recent.png)
- M3 #47：PASS，中间芯片变绿并填入完整「高德信息技术有限公司 · 快捷支付」。[M3-tap](combined-2026-10-28/pr47/M3-tap.png)
- M4 #47：PASS，键盘区同色，按键间未见底下文字；上拖松手后仍无透出，未捕捉按住时的画面。[M4-keypad](combined-2026-10-28/pr47/M4-keypad.png)、[M4-drag](combined-2026-10-28/pr47/M4-drag.png)
- M5 #47：PASS，日期和「记下后，还能花」均完整位于键盘上方。[M5-scroll](combined-2026-10-28/pr47/M5-scroll.png)
- M6 #47：FAIL，保存用途「午饭」后重开，三芯片同一行靠左，但短芯片画面仅显示「午」；无障碍标识仍为「午饭」。[M6-short](combined-2026-10-28/pr47/M6-short.png)
- M7 #47：PASS，添加账户的名称建议芯片靠左。[M7-other-chips](combined-2026-10-28/pr47/M7-other-chips.png)
- S1 #48：符合，欢迎页左侧云端智能及右侧恢复备份均在，云端入口无勾。[S1-welcome](combined-2026-10-28/pr48/S1-welcome.png)
- S2 #48：未做（关闭后欢迎页内容未单独读回）；已确认直接打开智能与隐私页，开关为关闭，未填密钥。[S2-settings](combined-2026-10-28/pr48/S2-settings.png)
- S3 #48：符合，工资卡第 1 张，共 2 张；每月 10 日、+8,000.00、最近 8/10、9/10、10/10，另有待分类卡。X1 = −2,500.00。[S3-salary-card](combined-2026-10-28/pr48/S3-salary-card.png)
- S4 #48：符合，工资卡收起、显示到 11/10 发工资，X2 = 1,350.00，并出现工资已添加提示及撤销。[S4-confirmed-toast](combined-2026-10-28/pr48/S4-confirmed-toast.png)
- S5 #48：不符合，固定收付页面显示「这个月还没有固定收付」，未显示工资；合成账本读回确有每月 10 日、11 月 10 日开始、金额 8,000.00 的工资收入计划。[S5-plan](combined-2026-10-28/pr48/S5-plan.png)
- S6 #48：符合，使用新夹具确认后立即撤销，工资卡恢复，90 天与 −2,500.00 恢复。[S6-undo](combined-2026-10-28/pr48/S6-undo.png)
- S7 #48：符合，点「不是」后卡收起，金额不变。[S7-reject](combined-2026-10-28/pr48/S7-reject.png)
- S8 #48：符合，同一 UUID 重开后工资卡未再出现。[S8-reject-relaunch](combined-2026-10-28/pr48/S8-reject-relaunch.png)
- S9 #48：符合，显示「6 笔还没分类」、账户与日期范围、打开云端智能及自己分，没有整理按钮。[S9-pending](combined-2026-10-28/pr48/S9-pending.png)
- S10 #48：符合，打开智能与隐私页，云端开关关闭，未填密钥。[S10-open-ai](combined-2026-10-28/pr48/S10-open-ai.png)
- S11 #48：符合，跳到账目并选中「没分类」，显示未分类账目。[S11-self](combined-2026-10-28/pr48/S11-self.png)
- S12 #48：符合，经「我 → 智能与隐私 → 发给云端的内容」读回本次打开 0 次、没有发送记录。[S12-send-log](combined-2026-10-28/pr48/S12-send-log.png)
- 动效：记录的视频未捕捉到点击后的过渡，无法判断收起和数字变化过程是否闪烁；上述终态截图不证明动效。

## 其他

- 运行中断：用户提供补全后的说明并要求从头运行，第一次 UI 进程由本任务中止，模拟器备份恢复后重新构建；新一轮 Core 曾被中断，按用户「继续」重新运行完整 Core。以上被中断结果未计入本报告；最终 UI 按指定失败重试，无额外重跑。
- 是否有任何 DeepSeek 请求发出：否，依据模拟器 UI 测试脚本使用假传输、Core 实网开关关闭，以及手动检查发送记录为 0；未做全程网络抓包。部分自动 UI 夹具为测试而开启其隔离账本的云端开关，未使用真实密钥；手动检查保持关闭。
- 数据：备份位于 `~/yubai-sim-data-before-combined-2026-10-28`，恢复后 203 个文件路径与 SHA-256 一致，恢复后未启动 App。
- 收尾：已切回 `main`；`before combined verify 2026-10-28` 已恢复；`xcode signing before v16 check` 及其余原有 stash 保持不变；git status、diff、原工程和工作区文件与开始前一致。
