# 2026-10-27 PR #45 验证报告

- 总结论: **FAIL**；新增有余额 UI 测试三次失败，且欢迎页导入余额显示 `12986`，未显示要求的两位小数。
- 分支与提交: feat/onboarding-bank-balance @ da44ee9a996751718678cdc2700229100335e0be
- 时间: 2026-10-27T18:13:55+08:00
- Xcode: Xcode 27.1
  Build version 27A9275
- 模拟器: iPhone 17 Pro Max, iOS 26.5 (23F77), id 37FDA39F-AF08-48EA-9E35-0AAB017AAFE0

## 编译

- 结果: 成功；只运行一次 build-for-testing。

## Core 测试

- 通过 / 失败 / 跳过: **517 / 1 / 4**，共 522 项；日志的 2 failures 为同一失败测试的两条断言，命令退出码 1。
- 失败名: `StorageTests.testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten`，main 原有（前轮在 main 对照同一测试也失败，不推断根因）。本轮断言原文：

```text
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:235: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-10-27 09:10:53 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:235: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-10-27 09:10:53 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
```

- ImportBalanceTests 13/13、ImportTests 17/17、BeeCountImportTests 7/7、ImportColumnTests 5/5，全部通过。

## UI 测试

- 总数 / 第一次通过 / 时好时坏 / 稳定失败 / 跳过: **74 / 72 / 1 / 1 / 0**，共 77 次执行；退出码 65。
- 耗时: 约 52.3 分钟（Xcode 观察时间 3138.237 秒）；整轮未中断或重跑。
- 稳定失败: `testWelcomeStatementBalanceReviewAndCommit` | `Tests/YubaiUITests/AppFlowTests.swift:1540` | `/Users/yang/deepresearch/yubai/Tests/YubaiUITests/AppFlowTests.swift:1540: error: -[YubaiUITests.AppFlowTests testWelcomeStatementBalanceReviewAndCommit] : XCTAssertGreaterThanOrEqual failed: ("51.99999999999994") is less than ("52.0")` | 截图显示欢迎页选中招行储蓄卡，流水导入入口可见、金额为空、开始按钮禁用，尚未点击导入 | 归属 #45 | [首次截图](pr45/ui/testWelcomeStatementBalanceReviewAndCommit.png) | [首次层级](pr45/ui/testWelcomeStatementBalanceReviewAndCommit.txt)。三次均失败：高度 `51.99999999999994` 未满足 `>= 52.0`；这是断言结果，不据此断言实际触控区域有明显视觉缺陷。
- 时好时坏: `testFixedIncomeCheckIncreasesAvailableAndPersists` | 失败 1 次 / 共 2 次 | `Tests/YubaiUITests/AppFlowTests.swift:202` | `/Users/yang/deepresearch/yubai/Tests/YubaiUITests/AppFlowTests.swift:202: error: -[YubaiUITests.AppFlowTests testFixedIncomeCheckIncreasesAvailableAndPersists] : XCTAssertTrue failed` | 截图仍在“我”页，显示固定收付入口和账户 1,000.00，未进入固定收付页面 | 归属不确定 | [首次截图](pr45/ui/testFixedIncomeCheckIncreasesAvailableAndPersists.png) | [首次层级](pr45/ui/testFixedIncomeCheckIncreasesAvailableAndPersists.txt)。
- 指定测试：`testWelcomeStatementBalanceReviewAndCommit` 三次失败；`testWelcomeStatementWithoutBalanceAndAccountSwitch` 第一次通过；`testFirstLaunchEmptyLedgerAccountAndAvailableFunds` 第一次通过。所有名称包含 Import 的 UI 测试第一次通过（`testImportOrganizeAnswerAndUndoEntireBatch`）。
- [无余额测试截图](pr45/ui/welcome-statement-no-balance.png)已导出；有余额测试在截图步骤前失败，因此没有 `welcome-statement-balance` 附件。

## 手动检查 H

- H1 **符合**：默认微信零钱，没有导入行。 [截图](pr45/manual/H1-wechat.png)
- H2 **符合**：支付宝没有导入行。 [截图](pr45/manual/H2-alipay.png)
- H3 **符合**：招行储蓄卡显示分隔线、文件图标、绿色导入行和箭头；金额为空，开始禁用。 [截图](pr45/manual/H3-bank.png)
- H4 **不符合**：数值 12986、时间 10月26日 21:14、已导入 3 笔、日期 10月24日–26日、开始可用均正确；金额显示 12986，缺少要求的 .00。 [截图](pr45/manual/H4-read.png)
- H5 **符合**：核对页显示三笔且可取消，没有导入提交按钮、账户选择或分类对应卡片。 [截图](pr45/manual/H5-review.png)
- H6 **不符合**：取消午餐后显示已导入 2 笔，数值仍为 12986，但显示缺少 .00。 [截图](pr45/manual/H6-after-review.png)
- H7 **符合**：切换微信零钱清空金额与流水状态、开始禁用；切回银行卡恢复初始导入入口，没有自动重读。 [截图](pr45/manual/H7-switch.png)
- H8 **符合**：重新导入三笔并建账后进入现在页，无错误，还能花 12,986.00。 [截图](pr45/manual/H8-start.png)
- H9 **符合**：计算页现金 12,986.00，未重复加减流水。 [截图](pr45/manual/H9-formula.png)
- H10 **符合**：账目可见合成工资、午餐、早餐三笔；另观察到工资 +8,000.00 的“昨天”日合计显示 0.00，未在本轮诊断原因。 [截图](pr45/manual/H10-entries.png)
- H11 **不符合**：倒序识别最新时间和数值正确，但显示 12986，缺少要求的 .00。 [截图](pr45/manual/H11-desc.png)
- H12 **符合**：手工把余额改为 13000。 [截图](pr45/manual/H12-edit.png)
- H13 **符合**：建账后计算页现金 13,000.00。 [截图](pr45/manual/H13-edit-formula.png)
- H14 **符合**：无余额提示、琥珀点、已导入 1 笔；金额为空，光标和键盘出现，开始禁用。 [截图](pr45/manual/H14-nobal.png)
- H15 **符合**：输入 1000 后开始启用。 [截图](pr45/manual/H15-nobal-typed.png)
- H16 **符合**：自定义账户测试卡显示导入入口。 [截图](pr45/manual/H16-other.png)
- H17 **符合**：改名测试卡2后，三笔及读取的余额仍保留。 [截图](pr45/manual/H17-rename.png)

- H8/H9：还能花 **12,986.00**；计算页现金 **12,986.00**。
- H18 深色模式：文字可辨，[截图](pr45/manual/H18-dark.png)；已恢复浅色。
- 读取动效：录屏抽帧未观察到“读取中”文字或进度，结果切换时旧导入文字与新状态短暂重叠，随后稳定；仅针对该小型合成文件，不代表慢文件读取时的状态。

## 其他

- 运行中断、整轮重跑、模拟器异常：无。未修改应用或测试代码，未发 DeepSeek 请求，未运行 GitHub Actions。
- 数据：备份保留在 `/Users/yang/yubai-sim-data-before-pr45-2026-10-27`；已恢复，203 个文件的路径与 SHA-256 均匹配，恢复后未再启动 App。
- 收尾：已切回 `main`；`before pr45 verify` 已恢复并移除；`xcode signing before v16 check` 仍在。`before combined verify round4 rerun` 在本轮开始前已不存在（前一次按用户要求恢复并移除），本轮结束后仍不存在；其余三个原有 stash 身份和顺序未变。Git 状态和 tracked diff 与开始前一致，project、Package.resolved 与 Xcode 忽略的界面状态文件均与本轮备份一致；验证分支的本地副本已删除。
