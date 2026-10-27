# 2026-10-27 PR #45 复验报告

- 总结论: PASS（编译成功，指定 Core 和三个 UI 测试通过，R1–R4 均符合）
- 分支与提交: feat/onboarding-bank-balance @ a12fa2181bec83ce28e1a46ee0c0a8c9115f9103
- 时间 / Xcode / 模拟器: 2026-10-27 18:30–18:37（北京时间）；Xcode 27.1 (27A9275)；iPhone 17 Pro Max，iOS 26.5 (23F77)，37FDA39F-AF08-48EA-9E35-0AAB017AAFE0

## 编译: 成功

`build-for-testing` 一次成功。

## Core（FinanceTests / ImportBalanceTests / ImportTests）: 通过 61 / 失败 0

分别通过 31、13、17 项；指定过滤表达式还匹配 BeeCountImportTests，7 项通过。合计 68 项通过、0 失败。

## UI

- `testWelcomeStatementBalanceReviewAndCommit`：第一次通过；[welcome-statement-balance 截图](pr45-reverify/ui/welcome-statement-balance.png)。
- `testWelcomeStatementWithoutBalanceAndAccountSwitch`：第一次通过。
- `testFirstLaunchEmptyLedgerAccountAndAvailableFunds`：第一次通过。

三项均未重试，0 失败、0 跳过。

## 手动

- R1：符合，正序流水识别余额 **12986.00**；[截图](pr45-reverify/manual/R1-read.png)。
- R2：符合，取消一笔后余额仍为 **12986.00**；[截图](pr45-reverify/manual/R2-after-review.png)。
- R3：符合，倒序流水识别余额 **12986.00**；[截图](pr45-reverify/manual/R3-desc.png)。
- R4：符合，从 R1 直接点「开始」后当前现金为 **12,986.00**；[截图](pr45-reverify/manual/R4-start.png)。测试账本读回锚点余额为 1,298,600 分，对账时间为流水时间 2026-10-26 21:14（北京时间），旧流水未重复计入当前现金。

## 其他

- 中断异常：无。未调用 DeepSeek 或其他付费 API，未运行 GitHub Actions；未运行完整 UI 测试套件。
- 模拟器数据：新备份保存在 `~/yubai-sim-data-before-pr45-reverify-2026-10-27`，恢复后独立核对 203 个文件的路径和 SHA-256 全部一致，恢复后未再启动应用。第一轮备份保留。
- 收尾 stash / git status 与开始前一致：是。原有三个 stash 的顺序和对象均一致，签名 stash 未动；原始工作区修改、未跟踪文件及 Xcode 工作区状态已核对一致。
