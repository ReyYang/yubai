# 2026-10-28 PR #46 验证报告

- 总结论: PASS（构建成功，除 main 已知失败外 Core 通过，4 个指定 UI 测试首次通过，手动 B1–B3 符合）
- 提交: main @ 17df9f9acf03e051dbba79438020f010f0972f99
- 时间 / Xcode / 模拟器: 2026-10-28 约 09:02–09:09（北京时间）；Xcode 27.1 (27A9275)；iPhone 17 Pro Max，iOS 26.5 (23F77)，`37FDA39F-AF08-48EA-9E35-0AAB017AAFE0`。

## 编译: 成功

`build-for-testing` 一次成功，使用 Apple SDK 和指定模拟器。

## Core: 通过 532 / 失败 1 / 跳过 4

- 537 个 XCTest 用例中，`StorageTests.testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten` 失败（`StorageTests.swift:235`，同一用例内两条断言失败）；这是已知的 main 原有失败，不归 #46。其余失败为 0。
- 重点 7 组全部通过：BankStatementImportTests 12、ImportTests 17、ImportBalanceTests 13、BeeCountImportTests 7、ImportColumnTests 5、CategoryModelTests 34、FinanceTests 31。
- 跳过的 4 个均是需要显式开启的实网评测；运行时设置 `YUBAI_LIVE_EVAL=0`。

## UI

实际运行以下 4 个 `AppFlowTests` 用例，均第一次通过，未重试：

- `testFirstLaunchEmptyLedgerAccountAndAvailableFunds`：通过（51.055 秒）。
- `testImportOrganizeAnswerAndUndoEntireBatch`：通过（77.942 秒）。
- `testWelcomeStatementBalanceReviewAndCommit`：通过（56.472 秒）。
- `testWelcomeStatementWithoutBalanceAndAccountSwitch`：通过（21.685 秒）。

0 失败、0 跳过；按测试名称筛选后确认均属于 `AppFlowTests`。

## 手动 B

- B1：符合；[截图](pr46/manual/B1-read.png)显示「已导入 5 笔」，余额 **16872.71**；核对页「不导入 0」。
- B2：符合；[截图](pr46/manual/B2-review.png)显示 4 笔流出共 228.58、1 笔流入 100.70，标题末尾均无账号。逐笔结果如下；截图显示一级分类，细分类由提交后的合成账本读回确认。
  - 源源烧烤 · 快捷支付：支出 200.00，餐饮。
  - Cotti+Coffee · 快捷支付：支出 5.90，餐饮／咖啡饮品。
  - 蚂蚁（杭州）基金销售有限公司 · 快捷支付：支出 5.88，没分类（账本内部为待整理）。
  - 杭州崇宇信息科技有限公司 · 银联快捷支付：收入 100.70，没分类（账本内部为待整理）。
  - 杭州全家便利店 · 快捷支付：支出 16.80，购物／日用百货。
- B3：符合；切到 2025 年 10 月后，[账目页](pr46/manual/B3-entries.png)显示 5 笔。打开 Cotti+Coffee，备注为「对手信息：Cotti+Coffee 2088111111111111」；[详情截图](pr46/manual/B3-detail.png)。

## 其他

- 未中断、未重跑。Xcode 测试完成后日志出现 `IDESchemeActionSDKRecord ... invalidDigitCount(94232)` 环境诊断，测试结果仍为成功；记录开始时间的辅助 `date -Is` 命令不被 macOS 支持，未影响构建，时间以其他记录为准。
- 未运行 GitHub Actions，未调用 DeepSeek 或付费 API。指定的 `import` UI 测试在隔离的合成账本中把云端智能偏好设为开启，但该测试使用模拟脚本传输，未连接真实云端；手动流水核对页显示本机读取。实际用户账本未用于测试。
- 模拟器数据已备份到 `~/yubai-sim-data-before-pr46-2026-10-28` 并恢复；203 个文件的路径和 SHA-256 读回一致，恢复后未再启动 App。
- 已切回原 `main`；本地 `main` 保持开始前的 `f38bd4e`。`before pr46 verify` 已恢复并移除；`xcode signing before v16 check` 原样保留；`before combined verify round4 rerun` 开始前不存在，未触碰。stash 列表、git status、原工作区修改和 Xcode 工作区状态与开始前一致。
