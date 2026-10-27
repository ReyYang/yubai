# 2026-10-26 合并验证报告

**第四轮（重跑）**

- 总结论: #37、#38、#39、#41、#42、#43 PASS；#40 未完成（模拟器没有密钥，真实连接未验证）。
- 分支与提交: test/combined-verify-2026-10-26 @ 0e8b2ed3f80e4e669b25526605439630c5f22e79
- 时间: 2026-10-27T12:04:58+08:00
- Xcode: Xcode 27.1；Build version 27A9275
- 模拟器: iPhone 17 Pro Max, iOS 26.5 (23F77), id 37FDA39F-AF08-48EA-9E35-0AAB017AAFE0

## 逐个 PR 结论

| PR | 结论 | 一句话理由 |
|---|---|---|
| #37 不稳定 UI 测试 + 撤销提示 | PASS | 72 项 UI 全部第一次通过；指定滑动测试额外 10/10 通过。 |
| #38 金额两位小数 | PASS | 第三轮已 PASS，本轮 UI 无归属失败。 |
| #39 记一笔键盘 | PASS | 第三轮已 PASS，本轮 UI 无归属失败。 |
| #40 测试连接 | 未完成 | 两个 thinking 测试通过；模拟器没有密钥，未发真实请求。 |
| #41 分类模型 | PASS | 第三轮已 PASS，本轮 UI 无归属失败；本轮唯一 Core 失败是第三轮 main 已有的存储测试失败。 |
| #42 转账可就地添加账户 | PASS | 编译成功、指定 UI 首次通过，E1–E5 符合且无其他 UI 失败。 |
| #43 始终留着是目标 | PASS | 编译成功、除已知存储测试外 Core 无失败；G2–G5 符合，G6 因需要云端智能未做，相关 UI 首次通过。 |

## 编译

- 结果: 成功；唯一一次 build-for-testing，10:55–10:56，退出码 0。

## Core 测试

- 通过 / 失败 / 跳过: 504 / 1 / 4，共 509 项，退出码 1；日志的 2 failures 是同一个失败测试中的两条断言。
- 失败名: `StorageTests.testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten`。断言原文：

```text
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:235: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-10-27 02:57:06 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:235: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-10-27 02:57:06 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
```

- main 对照：按第四轮要求本轮跳过。第三轮在 main `cfe155c` 单独运行同一测试也失败，位置同为 `StorageTests.swift:235`，实际 `2026-10-27 02:06:28 +0000`，期望 `1970-01-01 00:01:40 +0000`；因此依约作为已知失败，不归属 PR。该对照不证明根因。
- CategoryModelTests 32/32、ManualBookkeepingTests 20/20、`testThinkingSwitchIsEncodedOnlyWhenSpecified` 和 `testShortCloudTasksDisableThinking` 全部通过。

## UI 测试

- 总数 / 第一次通过 / 时好时坏 / 稳定失败 / 跳过: 72 / 72 / 0 / 0 / 0。
- 耗时: 约 51.3 分钟（xcresult 记录 3080.394 秒）；一轮完整测试、未中断、未重跑，退出码 0。
- 稳定失败: 无。时好时坏: 无；因此无失败截图与层级。
- 上次 22 个名单：

- `testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop`: 第一次通过。
- `testClosedLedgerRowPagesRightAndRevealedRowClosesFirst`: 第一次通过。
- `testDueCardIncludesPreviousMonthAndLinksOverflowToBills`: 第一次通过。
- `testFixedBillCheckMarksPaidAndUndoRestoresIt`: 第一次通过。
- `testFixedBillGroupedSwipesKeepCardAndContentGeometry`: 第一次通过。
- `testFixedBillsStateTextAndUpcomingHasOnlyContextAction`: 第一次通过。
- `testFixedBillStopAndResumeBothSupportUndo`: 第一次通过。
- `testFixedBillStopHandlesEveryUnsettledPeriod`: 第一次通过。
- `testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow`: 第一次通过。
- `testFixedIncomeStopSkipCancelPersistenceAndUndo`: 第一次通过。
- `testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible`: 第一次通过。
- `testLedgerRevealClosesAfterTabSelectionAndPaging`: 第一次通过。
- `testLedgerSwipeDeleteAndUndoRestoresRow`: 第一次通过。
- `testManualAndAskActionsPreserveTheSelectedPage`: 第一次通过。
- `testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt`: 第一次通过。
- `testRevealedLedgerRowConsumesSwipesInBothDirections`: 第一次通过。
- `testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab`: 第一次通过。
- `testTabTapReturnsToLedgerAfterRightSwipe`: 第一次通过。
- `testUndoReceiptDismissesAfterProductionLifetime`: 第一次通过。
- `testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo`: 第一次通过。
- `testCancelledNestedBackKeepsTabBarHiddenUntilSettingsRoot`: 第一次通过。
- `testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet`: 第一次通过。

- 指定测试：

- `testUndoReceiptDismissesAfterProductionLifetime`: 第一次通过。
- `testManualKeypadOperatorsAndPurposeKeyboard`: 第一次通过。
- `testSubcategoryScreenshotFixture`: 第一次通过。
- `testLedgerMonthFiltersAndSearchToggle`: 第一次通过。
- `testTransferWithOneAccountCanAddDestinationWithoutLosingDraft`: 第一次通过。

- 名称包含 Funds / Judge / Overview / Butler 的测试均第一次通过：

- `testButlerFastLongSwipeDismissesWithoutPaging`
- `testButlerFastShortSwipeDismisses`
- `testButlerRightSwipeAtFirstPagePreservesCardAndPaging`
- `testButlerSwipeDismissesWithoutSwitchingTabs`
- `testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop`
- `testFirstLaunchEmptyLedgerAccountAndAvailableFunds`
- `testJudgeAskScreenshotFixture`
- `testJudgeBuyScreenshotFixture`
- `testJudgeSkipScreenshotFixture`
- `testJudgeWaitScreenshotFixture`
- `testOverviewAccessibilityXLScalesHeaderAndWrapsTodaySummary`
- `testOverviewRowSwipeAtTabBoundaryDoesNotTapRow`
- `testStorageEntryAndOverviewOpenFromMe`
- `testTabTapReturnsToOverviewAfterLeftSwipe`

## 手动检查

- A #41、B #38、C #39: 按第四轮要求跳过，沿用第三轮结果。
- D #40: 模拟器正常设置页面显示“还没配置密钥”，测试连接不可点（[截图](combined/pr40/D0-no-key.png)）；flash 和 pro 均未做，发送记录中的 thinking 和 max_tokens 未验证，实际发送 0 次请求；原模型 `deepseek-v4-pro`，未更改。

## E #42

- E1 PASS: 一账户，转出 / 转入两行、添加账户芯片、无分类芯片，保存禁用。[截图](combined/pr42/E1-one-account.png)
- E2 PASS: 新建账户页覆盖记一笔。[截图](combined/pr42/E2-editor.png)
- E3 PASS: 取消后金额 500、用途“测试转账”及转账类型保留，保存仍禁用。[截图](combined/pr42/E3-cancel-keeps-draft.png)
- E4 PASS: 新账户自动填入转入，保存启用；回到草稿后转入整行短暂出现浅绿色底色并淡出。[截图](combined/pr42/E4-added.png)；[过渡录像](combined/pr42/E4-transition.mp4)。
- E5 PASS: 保存后账目显示“内部移动 / 测试转账 / −500.00”。[截图](combined/pr42/E5-saved.png)
- `testTransferWithOneAccountCanAddDestinationWithoutLosingDraft`: 第一次通过。

## F #37 butler 10 次

- `testButlerRightSwipeAtFirstPagePreservesCardAndPaging` 独立运行 10 次，10 次通过、0 次失败；约 336 秒。每秒截图循环已停止；无失败时的截图已删除，`butler-shots`、`butler.xcresult`、`butler.log` 均已删除。

## G #43

- G1 PASS: 初始未设置，X = 1,000.00。[截图](combined/pr43/G1-before.png)
- G2 PASS: F = 500.00，仍为 1,000.00，显示“能留住”；进度条对应 500 的一半为实色，余下为浅色。[截图](combined/pr43/G2-floor-ok.png)
- G3 PASS: F = 1,500.00，仍为 1,000.00，显示“还差 500.00”。[截图](combined/pr43/G3-floor-short.png)
- G4 PASS: 点目标行打开“我的消费观”。[截图](combined/pr43/G4-tap.png)
- G5 PASS: 计算页显示同一目标行，点它无反应且不可编辑。[截图](combined/pr43/G5-formula.png)
- G6 未做: 目标设回 500.00；问余白显示“云端智能没开”，购买问题和输入框均禁用，未开启云端、未发请求。[截图](combined/pr43/G6-judge.png)
- G7 PASS: 上列 Funds / Judge / Overview / Butler UI 测试均第一次通过；这些自动测试不代替 G6 真实交互。

## 其他

- 本轮无运行中断、整轮重跑或模拟器异常。没有发送 DeepSeek 请求，没有运行 GitHub Actions，没有修改应用或测试代码。
- 数据: 备份 `/Users/yang/yubai-sim-data-before-combined-2026-10-27-round4-rerun` 保留；恢复到当前 App 数据容器后，207 个文件路径和 SHA-256 与备份一致，恢复后未启动 App。
- 收尾: 已切回 `main`，`git status --short --untracked-files=all` 与开始前一致；`project.pbxproj` 和 `Package.resolved` 的内容与原始备份一致。`stash pop` 报 `Package.resolved already exists, no checkout`，依要求停止：本次 `before combined verify round4 rerun` stash 仍保留，原 3 个 stash（包括 `xcode signing before v16 check`）仍在；验证分支保留。忽略文件 `UserInterfaceState.xcuserstate` 与备份不一致，未在冲突后改写，备份保留在 `/tmp/yubai-combined-verify-20261027-round4-rerun/workspace-backup/`。
