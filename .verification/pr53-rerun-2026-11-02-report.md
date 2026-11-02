# 2026-11-02 PR #53 复测报告
- 总结论: FAIL（仅模拟器后台：register=true，submit 返回 BGTaskSchedulerErrorDomain code=1／Unavailable；B1 不符合、B2 按条件跳过；B3–B5 符合）
- 分支与提交 / 时间 / Xcode / 模拟器: feat/organize-by-party-groups @ 47d7f03e44bb00a01a0f38ee7ff15e1a3e10abb2（#53 1328755 + #54）；2026-11-02，Asia/Shanghai，2026-11-02T13:50:43.547460+08:00 开始，14:05 完成模拟器数据恢复；Xcode 27.1 (27A9275)；iPhone 17 Pro Max / iOS 26.5 / 37FDA39F-AF08-48EA-9E35-0AAB017AAFE0
- 本轮只验证，不修代码、不 merge、不改 main；不创建 worktree／模拟器，不进行真实 DeepSeek 或真机安装／整理。没有修改系统后台设置或新增插桩，使用本提交已有日志取证。

## 编译: 成功
一次 build-for-testing，退出0，`** TEST BUILD SUCCEEDED **`，无 error: 行。[命令](pr53-rerun-2026-11-02/build-command.json) / [结果](pr53-rerun-2026-11-02/build-summary.json)。

## Core: 通过 610 / 失败 1 / 跳过 4；失败名
一次 `YUBAI_LIVE_EVAL=0 swift test`，Mac 实际615项、退出1；文档 Linux 616项，本轮没有补跑凑数。唯一失败为已知 `StorageTests.testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten`，同一测试触发两条相同断言，XCTest 汇总的2 failures不是两个失败测试。4项实网 opt-in 测试按设计跳过。[完整统计](pr53-rerun-2026-11-02/core-summary.json)。

```text
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:235: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-11-02 05:53:11 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:235: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-11-02 05:53:11 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
```

ImportOrganizerTests：35通过、0失败、1项真实云端跳过；#54 的按对方统计／脱敏、组展开、超千笔问题、组与单笔问题合并、检查点中断续跑及不重发等测试通过。仅证明假传输与本地逻辑，不证明真实 DeepSeek 分类质量、费用或真机后台资格。

## UI（10 个）: 各一行第一次通过 / 失败
全在 YubaiUITests/AppFlowTests，同一条 test-without-building、串行、一次运行，无重试。10通过、0失败、0跳过，退出0，无失败断言或失败截图／层级。[命令](pr53-rerun-2026-11-02/ui-command.json) / [结果时长](pr53-rerun-2026-11-02/ui-summary.json) / [xcresult 独立汇总](pr53-rerun-2026-11-02/xcresult-summary.json)。

- `testFallbackGroupsByPartyAppliesCategoryAndUpdatesRemainingCount`：第一次通过，43.752 seconds。
- `testImportOrganizeAnswerAndUndoEntireBatch`：第一次通过，78.191 seconds。
- `testOrganizationDefersSavedQuestionsUntilCompletion`：第一次通过，23.460 seconds。
- `testOrganizationFailureReleasesSavedQuestionsAndRestoresIdleTimer`：第一次通过，20.091 seconds。
- `testOrganizationRelaunchReleasesCheckpointedQuestionsWithoutRestarting`：第一次通过，13.687 seconds。
- `testOrganizationStopReleasesSavedQuestionsAndRestoresIdleTimer`：第一次通过，19.384 seconds。
- `testOrganizedQuestionsPrecedeCollapsedUncoveredInflows`：第一次通过，17.157 seconds。
- `testPendingImportsOrganizesOnlyAfterTapWithFakeTransport`：第一次通过，36.225 seconds。
- `testPendingImportsSecondChunkFailureShowsReasonAndRetriesOnlyRemaining`：第一次通过，30.831 seconds。
- `testPendingImportsStopKeepsCompletedChunkAndRemainingCount`：第一次通过，23.796 seconds。

## 手动: B1–B5
- B1：不符合。全新 UUID 使用 allow_background=1、background_fixture=1、salary、configured_key=1、空 scenario／环境 API key；[启动参数](pr53-rerun-2026-11-02/B1-launch.json)。[开始](pr53-rerun-2026-11-02/B1-start.png) / [层级](pr53-rerun-2026-11-02/B1-start.txt) 有0/150进度但立即显示「整理时别离开余白」。HOME 后 [约11秒](pr53-rerun-2026-11-02/B1-home-1.png) / [约21秒](pr53-rerun-2026-11-02/B1-home-2.png) / [约31秒](pr53-rerun-2026-11-02/B1-home-3.png) / [约41秒](pr53-rerun-2026-11-02/B1-home-4.png) / [约51秒](pr53-rerun-2026-11-02/B1-home-5.png) 均未见系统进度／横幅、任务标题或增长数字；[时序](pr53-rerun-2026-11-02/B1-timing.json)。切回 [App](pr53-rerun-2026-11-02/B1-done.png) / [层级](pr53-rerun-2026-11-02/B1-done.txt) 仍30/150，不是后台完成150。为核对 finish，保持同一进程／run 在前台继续，最终 [出现提问](pr53-rerun-2026-11-02/B1-foreground-done.png)，[存档](pr53-rerun-2026-11-02/B1-ledger-summary.json) 为150个 organizedEntryIDs、needsOrganization=false、问题1；这段前台补充不替代约50秒后台验收。
- B2：跳过：B1 未出现系统进度。按本轮明确条件不尝试系统停止，也未用 App 内「停下」替代。[记录](pr53-rerun-2026-11-02/B2-skip.txt)。
- B3：符合。新UUID、allow_background=1、慢夹具开启；约21秒 [60/150](pr53-rerun-2026-11-02/B3-mid.png) / [层级](pr53-rerun-2026-11-02/B3-mid.txt)，[存档](pr53-rerun-2026-11-02/B3-mid-ledger.json) 已保存60个ID及1个问题，首页无本次提问；约29秒 [90/150](pr53-rerun-2026-11-02/B3-mid-2.png) / [层级](pr53-rerun-2026-11-02/B3-mid-2.txt)，[存档](pr53-rerun-2026-11-02/B3-mid-2-ledger.json) 保存90个ID及1个问题，仍无提问。约45秒 [结束](pr53-rerun-2026-11-02/B3-done.png) / [层级](pr53-rerun-2026-11-02/B3-done.txt) 出现一张「这笔支出是什么用途？」；[存档](pr53-rerun-2026-11-02/B3-done-ledger.json) 为150个ID、needsOrganization=false、问题1。这里验证前台提问延迟展示，不把 allow_background=1 当作提交成功。
- B4：符合。新UUID只将 allow_background 改成0，background_fixture仍为1，保持150笔慢夹具；[参数](pr53-rerun-2026-11-02/B4-launch.json)。[回退提示](pr53-rerun-2026-11-02/B4-fallback.png) / [层级](pr53-rerun-2026-11-02/B4-fallback.txt) 显示0/150和「整理时别离开余白」；约44秒 [结束提问](pr53-rerun-2026-11-02/B4-done.png) / [层级](pr53-rerun-2026-11-02/B4-done.txt) 出现「这笔支出是什么用途？」。[存档](pr53-rerun-2026-11-02/B4-ledger-summary.json) 为150个ID、needsOrganization=false、问题1。[App日志](pr53-rerun-2026-11-02/B4-applog.txt) 确认因脚本开关 start=false，随后 finish(success:true)；[系统日志](pr53-rerun-2026-11-02/B4-syslog.txt) 保留。
- B5：符合。最后按只读例外打开 我→智能与隐私→发给云端的内容，[截图](pr53-rerun-2026-11-02/B5-cloud.png) / [层级](pr53-rerun-2026-11-02/B5-cloud.txt) 为「本次打开后发送0次，共0.0KB」「还没有发送记录」。未改设置、未点测试连接／问余白／清空。此计数仅为末次B4进程；全轮假传输隔离依据见其他部分。

系统进度：桌面没有出现任务进度、活动横幅或可用停止控件。B1在提交时即被系统拒绝，未收到系统任务；没有将通知中心／锁屏写成已看到进度。本轮未另做这两处的交互检查。

## B1 诊断
本轮 B1 为 PID **66884**、run **64288AE5-E681-41AD-BF21-2EACBC46C629**。下方3分钟日志还包含此前 UI 测试进程，诊断仅按本 PID/run 归属；其他 run 的“script disallows background”和 finish 不属于 B1。

| 项目 | 本轮观测 |
|---|---|
| register | true，13:59:18.298，identifier=app.yubai.personal.organizeImports.64288AE5-E681-41AD-BF21-2EACBC46C629 |
| submit | **失败**，13:59:18.300，domain=BGTaskSchedulerErrorDomain，code=1 |
| 错误描述原文 | localizedDescription=未能完成操作。（BGTaskSchedulerErrorDomain错误1。） |
| handler | 本 run 没有 launch handler called 日志；无调用时间 |
| expiration | 本 run 没有 expiration triggered 日志 |
| 初次窗口的 finish | 约50秒切回时尚未发生，整理仍30/150 |
| 同次任务最终 finish | 前台继续后，14:00:44.494，finish(success:true)，alreadyFinished=false |
| start=false原因 | submit failed；不是脚本禁止，也不是 register=false 或 applicationState 非active |

可确认的失败阶段为 **register 已成功，submit 在取得 BGContinuedProcessingTask 之前即抛出 Unavailable**。因此本轮不是“submit成功但handler丢失”，也没有证据指向 expiration 提前终止。

当前 Xcode27.1 的 BackgroundTasks.framework/Headers/BGTaskScheduler.h 定义 `BGTaskSchedulerErrorCodeUnavailable = 1`，注释列出的常见原因包括模拟器不支持后台处理、后台刷新关闭等，见 [SDK 原文摘录](pr53-rerun-2026-11-02/SDK-unavailable.txt)。本机确实运行在 iOS26.5 Simulator，观察结果符合该错误类别；但单凭code1不能穷尽区分所有环境原因，本轮未更改／验证系统后台刷新设置，不能由此断言真机必成功或必失败。按任务约定总结论记「FAIL（仅模拟器后台）」。

B1-applog.txt 全文（原文件 [下载](pr53-rerun-2026-11-02/B1-applog.txt)；含日志命令的uid提示）：

```text
Timestamp               Ty Process[PID:TID]
2026-11-02 13:57:46.447 I  Yubai[66495:1ded08c] [app.yubai.personal:background-organize] run=7DE40871-E6D9-41EA-8227-882F00B7A8F0 start=false: simulator UI script disallows background
2026-11-02 13:57:46.741 I  Yubai[66495:1ded08c] [app.yubai.personal:background-organize] run=7DE40871-E6D9-41EA-8227-882F00B7A8F0 finish(success: true) alreadyFinished=false
2026-11-02 13:58:00.814 I  Yubai[66524:1ded2ea] [app.yubai.personal:background-organize] run=EFCDBD4C-3144-455E-AD40-8CCF6CADF6A7 start=false: simulator UI script disallows background
2026-11-02 13:58:01.118 I  Yubai[66524:1ded2ea] [app.yubai.personal:background-organize] run=EFCDBD4C-3144-455E-AD40-8CCF6CADF6A7 finish(success: false) alreadyFinished=false
2026-11-02 13:58:06.772 I  Yubai[66524:1ded2ea] [app.yubai.personal:background-organize] run=FB77F95E-2ED5-4C93-BB9B-737B49B6D5C7 start=false: simulator UI script disallows background
2026-11-02 13:58:17.609 I  Yubai[66524:1ded2ea] [app.yubai.personal:background-organize] run=FB77F95E-2ED5-4C93-BB9B-737B49B6D5C7 finish(success: true) alreadyFinished=false
2026-11-02 13:58:32.649 I  Yubai[66661:1ded819] [app.yubai.personal:background-organize] run=A4E0C2E5-AF08-45AA-8C0E-C9903F417FBF start=false: simulator UI script disallows background
2026-11-02 13:58:38.787 I  Yubai[66661:1ded819] [app.yubai.personal:background-organize] run=A4E0C2E5-AF08-45AA-8C0E-C9903F417FBF finish(success: false) alreadyFinished=false
2026-11-02 13:58:38.788 I  Yubai[66661:1ded819] [app.yubai.personal:background-organize] run=A4E0C2E5-AF08-45AA-8C0E-C9903F417FBF finish(success: false) alreadyFinished=true
2026-11-02 13:59:18.298 I  Yubai[66884:1dee008] [app.yubai.personal:background-organize] run=64288AE5-E681-41AD-BF21-2EACBC46C629 register success=true identifier=app.yubai.personal.organizeImports.64288AE5-E681-41AD-BF21-2EACBC46C629
2026-11-02 13:59:18.300 E  Yubai[66884:1dee008] [app.yubai.personal:background-organize] run=64288AE5-E681-41AD-BF21-2EACBC46C629 submit failed; start=false domain=BGTaskSchedulerErrorDomain code=1 localizedDescription=未能完成操作。（BGTaskSchedulerErrorDomain错误1。）
getpwuid_r did not find a match for uid 501
```

同一 run 继续留在前台后的补充日志 [全文](pr53-rerun-2026-11-02/B1-after-foreground-applog.txt)，关键 finish 行：

```text
2026-11-02 14:00:44.494 I  Yubai[66884:1dee008] [app.yubai.personal:background-organize] run=64288AE5-E681-41AD-BF21-2EACBC46C629 finish(success: true) alreadyFinished=false
```

B1-syslog.txt 中与 app.yubai.personal.organizeImports 相关的原样摘录（1行，不超过40；[完整系统日志](pr53-rerun-2026-11-02/B1-syslog.txt) / [摘录文件](pr53-rerun-2026-11-02/B1-syslog-excerpt.txt)）：

```text
2026-11-02 13:59:18.299 Df Yubai[66884:1dee008] [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.64288AE5-E681-41AD-BF21-2EACBC46C629, (title: 整理导入记录, subtitle: 已整理 0 / 150, resources: Default, submissionStrategy: Fail)>
```

B4 独立 run 的回退与结束原文，用于确认慢夹具与提交开关已分开：

```text
2026-11-02 14:03:08.666 I  Yubai[68736:1df0ed9] [app.yubai.personal:background-organize] run=4D5E97F9-8965-4243-BA20-4335B2552917 start=false: simulator UI script disallows background
2026-11-02 14:03:51.410 I  Yubai[68736:1df0ed9] [app.yubai.personal:background-organize] run=4D5E97F9-8965-4243-BA20-4335B2552917 finish(success: true) alreadyFinished=false
```

## 其他: 真实云端请求；数据备份与恢复；收尾 stash / git status 一致 是/否
- 未观察到真实发送。所有测试／手动启动均 --test-ledger 随机UUID＋显式YUBAI_UI_TEST_SCRIPT；假传输处理「导入整理」「导入整理·按对方」等目的，不进入真实 DeepSeekClient。未改变用户密钥、钥匙串、模型；没有操作旁边的 DeepSeek 用量网页。
- 未运行 GitHub Actions（工作流仅 workflow_dispatch）。仅使用既有模拟器，未操作iPhone、未执行可选真机或付费步骤。
- 模拟器备份 /Users/yang/yubai-sim-data-before-pr53-rerun-2026-11-02 保留，共228文件；恢复后数据及备份自身的逐文件SHA-256均与开始一致，恢复后未再启动App。[证明](pr53-rerun-2026-11-02/restore-proof.json)。之前备份未动。
- 原分支main @ 2fa6b470f0aa4c83d2849d9ba152b5f88d03a0d2，原本地签名及未跟踪Package.resolved使用本轮stash f9e88aa99deac9bca8235144d880c411276ee32c 保存。三个原有stash未动。临时生成的Package.resolved已在恢复原文件前移除。
- 已知本会话SSH不可用，按允许的HTTPS读取同一仓库分支，未改remote／SSH／全局配置。
- 诊断使用用户指定的单次场景和已有日志；依“只验证、不修”范围，不做实现修复、额外插桩、系统配置试错或改夹具缩减。所有首次测试结果保留。
- 收尾 stash / git status 一致：是。独立回读确认分支、main SHA、完整status、stash的SHA／顺序／名称、二进制diff、签名文件和Package.resolved字节一致，正常index为空，测试分支与指定产物已移除，模拟器哈希仍匹配。[Git恢复证明](pr53-rerun-2026-11-02/git-restore-proof.json)。先完成本地报告提交和现场恢复，再用临时index仅更新报告提交，不改正常工作区／index。只推送指定复测报告分支，作者与提交者为ReyYang <29473272+ReyYang@users.noreply.github.com>。

