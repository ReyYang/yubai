# 2026-10-28 合并验证复跑报告
- 总结论: PASS（编译成功，除 main 已知 Storage 测试外 Core 通过，13 个指定 UI 测试首次通过，手动项符合）
- 分支与提交: main @ 1093adc14f45dd064e99bd822e923fcfeff17b0d
- 时间 / Xcode / 模拟器: 2026-10-28T15:30:15+08:00；Xcode 27.1，Build version 27A9275；iPhone 17 Pro Max，iOS 26.5 (23F77)，37FDA39F-AF08-48EA-9E35-0AAB017AAFE0。

## 编译: 成功
- Apple SDK `build-for-testing` 一次成功。

## Core: 通过 / 失败 / 跳过
- 561 / 1 / 4，共 566 个用例；XCTest 汇总的 2 failures 是同一用例内两条断言。
- 失败: `StorageTests.testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten`（`StorageTests.swift:235`，main 原有）。
- `ChipWidthAllocationTests` 6 / 6、`SalaryDetectionTests` 14 / 14、`FixedBillsTests` 50 / 50 通过。

## UI: 13 项，全部第一次通过
- `testButlerFastLongSwipeDismissesWithoutPaging`：第一次通过（10.909 秒）。
- `testButlerFastShortSwipeDismisses`：第一次通过（9.023 秒）。
- `testButlerRightSwipeAtFirstPagePreservesCardAndPaging`：第一次通过（33.390 秒）。
- `testButlerSwipeDismissesWithoutSwitchingTabs`：第一次通过（25.295 秒）。
- `testConfirmedSalaryAppearsInFixedFlowsLaterGroup`：第一次通过（26.226 秒）。
- `testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator`：第一次通过（20.916 秒）。
- `testFixedIncomeCheckIncreasesAvailableAndPersists`：第一次通过（46.384 秒）。
- `testManualKeypadOperatorsAndPurposeKeyboard`：第一次通过（34.056 秒）。
- `testPendingImportsOrganizesOnlyAfterTapWithFakeTransport`：第一次通过（36.535 秒）。
- `testPendingImportsPageOpensCloudSettingsWithoutRequests`：第一次通过（25.928 秒）。
- `testRejectedSalaryStaysDismissedAfterRelaunch`：第一次通过（13.730 秒）。
- `testSalaryConfirmationChangesHorizonAndUndoRestoresCard`：第一次通过（13.594 秒）。
- `testWelcomeCloudSettingsPersistThroughStatementOnboarding`：第一次通过（36.009 秒）。
- 未重试；共约 5.6 分钟。无需导出失败截图或层级。

## 手动
- M2：符合。三个长用途靠左、同一行，均显示省略号。[截图](combined-rerun-2026-10-28/pr47/M2-recent.png)
- M3：符合。中间芯片变绿，用途完整为「高德信息技术有限公司 · 快捷支付」，取消未保存。[截图](combined-rerun-2026-10-28/pr47/M3-tap.png)
- M6：符合。记下 1 元「午饭」后重开，午饭完整显示无省略号，另外两个长用途带省略号，三者靠左同一行。[截图](combined-rerun-2026-10-28/pr47/M6-short.png)
- M8：符合。现在页待分类卡可见右上角 1 / 1，与上一轮卡片外观一致，未见额外可见元素；层级中卡片及页码可分别读取。[截图](combined-rerun-2026-10-28/pr47/M8-butler-ax.png)
- S5b：符合。10 月 28 日确认工资后，「以后」显示「工资」「每月10日 · 11月10日起」「+8,000.00」，行内无按钮，未出现空状态。[原始截图](combined-rerun-2026-10-28/pr48/S5b-later.png)；随后在隔离夹具中添加本月合成收入、另添并停掉一条合成安排，实际看到「要收 → 以后 → 已停掉」顺序。[分组截图](combined-rerun-2026-10-28/pr48/S5b-groups.png)

## 其他
- 运行中断异常：测试无中断、无重跑。清理时，工具自动审查拒绝了包含 `rm -rf` 的组合命令；该组合命令未执行，随后改用精确路径清理任务产物并完成恢复。
- 是否发出任何 DeepSeek 请求：未发现；Core 设置 `YUBAI_LIVE_EVAL=0`，手动测试未开启云端、未填密钥。指定的两项自动 UI 测试会在隔离合成账本切换云端偏好，并使用假传输、清空真实 API 密钥；未进行全程网络抓包。
- 数据：备份保留在 `~/yubai-sim-data-before-combined-rerun-2026-10-28`；已恢复，203 个文件路径及 SHA-256 与备份一致，恢复后未再启动 App；上一轮备份未动。
- 收尾：已切回 `main` 原提交 `17df9f9`，没有修改 main；任务 stash `before combined rerun 2026-10-28` 已恢复，`xcode signing before v16 check` 和其余原有 stash 保留；git status、diff、原工程及 Package.resolved 均与开始前一致。测试报告分支以独立暂存索引提交，不影响工作区。
