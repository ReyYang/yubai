# 整理失败取证报告
- 设备 / iOS 版本：阿雨的 iPhone，iPhone 16 Pro Max（iPhone17,2）；iOS 27.0（24A437）。DEV / UDID：`00008140-00163C340128401C`；CoreDevice Identifier：`A84CBAB1-B341-5750-BA9B-32F10683CB91`。
- 装在手机上的提交（看 App 内或问用户）：`main 29700179e48866c2eb047612c888734a2578c0f8`。用户确认了提交，本轮重新安装也使用该提交已有的 Debug 真机包。新 CPU 报告的主程序 UUID `32271ED4-6EA9-3187-98EE-2C0F8E55173B` 与该包一致；报告内重栈镜像 UUID `91C5A161-D112-3F7C-937F-92AE5B3392D7` 与包内 Yubai.debug.dylib 一致。
- 本报告当前取证对象：用户在重装后手动导入、由 App 自动开始整理并出现失败的新一轮；不是重装前的旧账本。用户依次确认「已打开正在导入」「导入完成，已自动开始整理」「已经出现了一次整理失败」。
- 导入时间：2026-11-03T14:39:33.491102+08:00；账本最后更新时间：2026-11-03T14:44:01.423388+08:00；失败后只读快照：2026-11-03T14:44:41.310077+08:00。
- 新一轮原始产物：`~/deepresearch/yubai-evidence-2026-11-03/post-reinstall-failure-144441/`；旧轮原始归档、旧报告及错误记录继续保留在父目录。
- Agent 未修改应用或测试代码，未点击整理或重试，未测试云端连接，未调用 DeepSeek API、未读取密钥，未创建 worktree / 模拟器，未运行 GitHub Actions。本次自动整理由用户导入触发；其实际 API 次数和费用未在本轮核验，不能把 Agent 0 次请求等同于设备总请求 0 次。重新安装只按用户后续明确要求进行，Agent 未卸载或启动 App。

## 1. 日志：所有 run= 行（按时间，原样）
新归档 `device.logarchive` 采集最近六小时成功（sudo，退出码 0），大小 1,015,733,635 bytes。按指定子系统导出实际 [yubai.log](yubai.log)，大小 1176 bytes；低于 5 MB，完整提交。另做了 info / debug 的跨子系统 background-organize 补查，并与系统导出交叉核对。

三种导出中去重后共有 4 条字面 `run=` 行，均为运行 `DA7D426F-035A-48E4-8390-CF14E6A33747`，原样如下。未找到该运行更早的 register / submit 自定义日志；第 2 节系统框架日志记录了它的提交与启动。
```text
2026-11-03 14:44:06.293593+0800 0x5cdc28   Info        0x0                  72206  0    Yubai: (Yubai.debug.dylib) [app.yubai.personal:background-organize] run=DA7D426F-035A-48E4-8390-CF14E6A33747 expiration triggered at=2026-11-03T06:44:06Z
2026-11-03 14:44:06.509817+0800 0x5cce8f   Info        0x0                  72206  0    Yubai: (Yubai.debug.dylib) [app.yubai.personal:background-organize] run=DA7D426F-035A-48E4-8390-CF14E6A33747 finish(success: false) alreadyFinished=false
2026-11-03 14:44:06.511759+0800 0x5cce8f   Info        0x0                  72206  0    Yubai: (Yubai.debug.dylib) [app.yubai.personal:background-organize] run=DA7D426F-035A-48E4-8390-CF14E6A33747 finish(success: false) alreadyFinished=true
2026-11-03 14:44:16.681786+0800 0x5cce8f   Info        0x15ef81f            72206  0    Yubai: (Yubai.debug.dylib) [app.yubai.personal:background-organize] run=DA7D426F-035A-48E4-8390-CF14E6A33747 finish(success: false) alreadyFinished=true
```

系统日志原始导出 47,070,036 bytes / 325007 行。因超过 20 MB，按要求只保留含 `app.yubai.personal`、`organizeImports`、`BGContinued`、`expir`、`watchdog`、`jetsam`、`hang`、`terminat` 的行（不区分大小写）；保留后 12,322,931 bytes / 39280 行。完整日志与归档仅留本地，不上传。

## 2. 日志：Yubai 进程的终止、expire、watchdog、hang、jetsam 相关行（原样，最多 80 行）
按时间摘录 45 行，含少量旧轮过期 / 卸载上下文，以及新轮任务完整的关键生命周期和全部 19 条重装后 always-on HangTracer 记录；紧邻的 telemetry 重复行不重复计数。未把 Changing 或 watchdogd 普通状态更新当成卡死 / watchdog 杀进程证据。

新轮事实链：PID 72206 的任务于 14:39:40 提交并运行；14:41:05，系统记录未按预期节奏报告进度，标记 stalled；14:44:06，Activity Progress Policy 给出 `tracker.health == 2` / `AMNP`，随后挂起任务、调用 expiration handler，App 回报 success: 0。自定义 run 日志与该系统任务 UUID 一致。失败任务窗口内有 12 条 HangTracer 记录，最长 11.36 秒；这些说明系统观察到卡顿，尚不定位具体代码原因。
```text
2026-11-03 11:52:44.264097+0800 0x5ae0ed   Error       0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:ProgressTracker] [0x7d84827a80:bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44] Task has not reported progress within expected cadence, marking stalled (time without update: -38.09956693649292)
2026-11-03 11:52:44.270934+0800 0x5ae163   Default     0x0                  70398  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Expiring task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C (整理导入记录)>
2026-11-03 11:52:44.271270+0800 0x5adbb6   Default     0x0                  70398  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Marking task <BGContinuedProcessingTask: app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C (整理导入记录)> complete with success: 0
2026-11-03 12:03:23.528892+0800 0x5afecd   Default     0x1587da7            36     0    runningboardd: (RunningBoard) [com.apple.runningboard:connection] Received termination request from [osservice<com.apple.installcoordinationd>:57256] on <RBSProcessPredicate <RBSProcessBundleIdentifierPredicate "app.yubai.personal">> with context <RBSTerminateContext| explanation:IX terminating bundleIDs for uninstallation: {(
2026-11-03 12:03:23.543561+0800 0x5afecd   Default     0x1587da7            36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:70398] Terminating with context: <RBSTerminateContext| explanation:IX terminating bundleIDs for uninstallation: {(
2026-11-03 12:03:23.576199+0800 0x5afe46   Default     0x0                  1      0    launchd: [user/501/UIKitApplication:app.yubai.personal[dd6d][rb-legacy] [70398]:] exited with exit reason (namespace: 15 code: 0x0) - OS_REASON_RUNNINGBOARD | <RBSTerminateContext| explanation:IX terminating bundleIDs for uninstallation: {(
2026-11-03 14:39:34.907256+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.27s (always-on hang reporting)
2026-11-03 14:39:35.836228+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.93s (always-on hang reporting)
2026-11-03 14:39:36.507494+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.45s (always-on hang reporting)
2026-11-03 14:39:36.909806+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.40s (always-on hang reporting)
2026-11-03 14:39:38.803286+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.88s (always-on hang reporting)
2026-11-03 14:39:40.497646+0800 0x5cce8f   Default     0x15ef81f            72206  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747, (title: 整理导入记录, subtitle: 已整理 0 / 4,200, resources: Default, submissionStrategy: Fail)>
2026-11-03 14:39:40.499025+0800 0x5ccb27   Default     0x15ef81f            58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] SUBMITTED bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE at priority 90 (Sat Dec 30 08:06:00 0000 - Tue Nov  3 14:39:40 2026)
2026-11-03 14:39:40.501465+0800 0x5cceaa   Default     0x0                  72206  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Running task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747 (整理导入记录)>
2026-11-03 14:39:40.663749+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.50s (always-on hang reporting)
2026-11-03 14:39:40.664080+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Starting task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747 (整理导入记录)>
2026-11-03 14:39:41.094652+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.42s (always-on hang reporting)
2026-11-03 14:40:00.609802+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.59s (always-on hang reporting)
2026-11-03 14:40:00.962729+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.35s (always-on hang reporting)
2026-11-03 14:40:02.621267+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.43s (always-on hang reporting)
2026-11-03 14:41:05.822675+0800 0x5cd43c   Error       0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:ProgressTracker] [0x7d84d11260:bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE] Task has not reported progress within expected cadence, marking stalled (time without update: -65.21277689933777)
2026-11-03 14:43:10.271823+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.66s (always-on hang reporting)
2026-11-03 14:43:45.322545+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 11.36s (always-on hang reporting)
2026-11-03 14:43:45.711024+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.39s (always-on hang reporting)
2026-11-03 14:43:46.261784+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.55s (always-on hang reporting)
2026-11-03 14:44:01.789380+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.92s (always-on hang reporting)
2026-11-03 14:44:02.173887+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.38s (always-on hang reporting)
2026-11-03 14:44:02.709180+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.54s (always-on hang reporting)
2026-11-03 14:44:06.215347+0800 0x5cdcdf   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:scoring] bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE:[
	{name: Activity Progress Policy, policyWeight: 0.001, response: {AMNP, 0.00, [{tracker.health == 2}]}}
 ], Decision: AMNP}
2026-11-03 14:44:06.215363+0800 0x5cdcdf   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] Suspending bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE - required criterion is not satisfied.
2026-11-03 14:44:06.219562+0800 0x5cdc28   Default     0x0                  72206  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Calling expiration handlers for tasks: {(
    <_BGTaskExpirationRequest: bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE, reason: 0 task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747 (整理导入记录)>
)}
2026-11-03 14:44:06.268381+0800 0x5cd9d4   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:ActivityProgress] Finishing progress (incomplete) to <NSProgress: 0x7d842d4080> : Parent: 0x0 (portion: 0) / Fraction completed: 0.0000 / Completed: 0 of 0 CANCELLED  for bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE
2026-11-03 14:44:06.290739+0800 0x5cdc28   Default     0x0                  72206  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Expiring task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747 (整理导入记录)>
2026-11-03 14:44:06.509848+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Marking task <BGContinuedProcessingTask: app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747 (整理导入记录)> complete with success: 0
2026-11-03 14:44:06.510690+0800 0x5cdb78   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] COMPLETED <_DASActivity: "bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE", UserInitiated, 900s, [1/1/1 08:06:00 - 2026/11/3 14:39:40], Started at 2026/11/3 14:39:40, Group: com.apple.dasd.continuedProcessing, InternalGroups: {(
    "com.apple.dasd.continuedProcessing"
)}, Priority: 999999999, PID: 72206> with runtime limit -1
2026-11-03 14:44:06.511234+0800 0x5cdb78   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle(activityGroup)] NO LONGER RUNNING bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE ...Tasks running in group [com.apple.dasd.continuedProcessing] are 0!
2026-11-03 14:44:06.511367+0800 0x5cdd5d   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:ActivityProgress] Finishing progress (incomplete) to <NSProgress: 0x7d842d4080> : Parent: 0x0 (portion: 0) / Fraction completed: 0.0000 / Completed: 0 of 0 CANCELLED  for bgContinuedProcessing-app.yubai.personal.organizeImports.DA7D426F-035A-48E4-8390-CF14E6A33747:45A9EE
2026-11-03 14:44:08.861336+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.29s (always-on hang reporting)
2026-11-03 14:44:17.032357+0800 0x5cce8f   Default     0x0                  72206  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.35s (always-on hang reporting)
```

旧轮分开处理：11:52 失败任务为 PID 70398；14:04 Jetsam 里的 Yubai 是 PID 68462；本轮失败为 PID 72206。三者不合并成同一次故障。12:03 的终止上下文为卸载，早于本轮 14:20 开始取证和 14:29 重装；没有推断具体是谁卸载。

## 3. 导入批次统计（表格）
本表只属于新轮 14:44:41 的失败后快照，旧轮账本没有取到，不能用本表回填旧轮统计。

| 批次 id | entryIDs 数量 | needsOrganization | organizedEntryIDs 数量 | organization.skipped 前 10 条 | organization.questions 数量 |
|---|---:|---|---:|---|---:|
| `8CE85684-EE69-4626-8FAE-CDC73F3BC918` | 4200 | true | 2661 | 第 1–10 条完全相同，均为「已跳过不在当前分类中的分类」 | 1 |

该提交的 ImportBatch 不保存 `entryIDs` 字段，数量按 `entries[].batchID == 批次 id` 反查，并与 importedCount = 4,200 核对一致。organizedEntryIDs 均属于该批次，没有外部 id；未记录整理覆盖的数量为 1,539。organizedEntryIDs 表示成功请求覆盖，包含仍不确定的记录，不等于已分类数量。

organization.skipped 总数为 1,314 条；以上只是要求的前 10 条。它们是诊断字符串条数，不能视为 1,314 笔交易或 1,314 次 API 失败。没有摘录标题、金额、对手或备注等交易明细。

## 4. 待整理 / 其他支出 / 总数
activeEntries 按当前提交 `deletedAt == nil` 的定义统计：

| 项目 | 数量 |
|---|---:|
| 待整理 | 2,345 |
| 没分类 | 0 |
| 待整理或没分类合计 | 2,345 |
| 其他支出 | 75 |
| activeEntries 总数 | 4,200 |
| 已删除条目 | 0 |

这些是重装后新导入失败时已保存的数据，不代表重装前的旧账本。

## 5. 存储：ledger.json 大小、Recovery 大小与份数
- ledger.json：3,394,652 bytes；SHA-256：`d080c072b6cbdda1112d104d231f4cd268418361a7fb33952caae1f8349a90d0`。
- Recovery 总大小：1,572,025 bytes；4 份 `.json.gz` 恢复快照，另有 1 个附件负载文件；合计 5 个普通文件。
- 只读复制所得数据共 7 个普通文件、5,365,012 bytes，JSON 可解析。ledger.json、Recovery 和附件都只保存在上述仓库外目录，未上传。

## 6. 崩溃 / 卡死报告摘录
本轮 systemCrashLogs 目录共 235 项，新增今天名字含 Yubai 的 `Yubai.cpu_resource-2026-11-03-144137.ips`，已完整复制到本地，报告仅摘录前 60 行。

该报告与本轮 PID 72206、当前安装包 UUID 对应。它记录 14:39:21–14:41:35 期间，134 秒内使用 90 秒 CPU，平均 67%，超过所列 CPU 限额；`Action taken: none`。该时间窗跨越导入和整理，不能把其中所有 CPU 消耗归给某个具体操作，更不能据此认定系统因 CPU 超限杀掉 App。

`Yubai.cpu_resource-2026-11-03-144137.ips` 前 60 行（原样）：
```text
{"app_name":"Yubai","timestamp":"2026-11-03 14:41:37.00 +0800","app_version":"2.0.0","slice_uuid":"32271ED4-6EA9-3187-98EE-2C0F8E55173B","build_version":"1","bundleID":"app.yubai.personal","duration_ms":"134257","share_with_app_devs":1,"is_first_party":0,"bug_type":"202","os_version":"iPhone OS 27.0 (24A437)","roots_installed":0,"name":"Yubai","incident_id":"92CCE68C-B213-47D6-87B4-95849DCC19CB"}
Date/Time:        2026-11-03 14:39:21.029 +0800
End time:         2026-11-03 14:41:35.286 +0800
OS Version:       iPhone OS 27.0 (Build 24A437)
Architecture:     arm64e
Report Version:   73
Incident Identifier: 92CCE68C-B213-47D6-87B4-95849DCC19CB
Share With Devs:  Yes

Data Source:      Microstackshots
Shared Cache:     9073D4CB-BCF8-3B38-9823-1685D7A08544 slid base address 0x195668000

Command:          Yubai
Path:             /private/var/containers/Bundle/Application/CF995D35-90BB-4BB3-A6FC-1EA90C08D119/Yubai.app/Yubai
Identifier:       app.yubai.personal
Version:          2.0.0 (1)
Is First Party:   No
Beta Identifier:  914019BF-D344-4532-82A1-B4DA8FB374D2
Resource Coalition: "app.yubai.personal"(7428)
Architecture:     arm64
Parent:           UNKNOWN [1]
PID:              72206

Event:            cpu usage
Action taken:     none
CPU:              90 seconds cpu time over 134 seconds (67% cpu average), exceeding limit of 50% cpu over 180 seconds
CPU limit:        90s
Limit duration:   180s
CPU used:         90s
CPU duration:     134s
Duration:         134.26s
Duration Sampled: 128.39s (event starts 5.52s before samples, event ends 0.35s after samples)
Steps:            39 (10 gigacycles/step, 12 samples lost)

Hardware model:   iPhone17,2
Active cpus:      6
Memory size:      7.44 GB
HW page size:     16384
VM page size:     16384
Shared cache residency: 11.01% (753.64 MB / 6845.77 MB)

Time Since Boot:  522104s
Time Awake Since Boot: 371819s
Time Since Wake:  2782s

Total CPU Time:   137.303s
Advisory levels:  Battery -> 3, User -> 3, ThermalPressure -> 0, Combined -> 3
Free disk space:  79.59 GB/237.82 GB, low space threshold 150 MB
Vnodes Available: 61.59% (17245/28000, 14000 allocated, 14000 soft limit)
Models:           none

Preferred User Language: zh-Hans-CN, en-CN
Country Code:     CN
Keyboards:        en_US QWERTY, zh_Hans-Pinyin Pinyin10-Simplified
OS Cryptex File Extents: 3593

Heaviest stack for the target process:
  38  ??? (libswift_Concurrency.dylib + 30860) [0x19728488c]
  38  ??? (<91C5A161-D112-3F7C-937F-92AE5B3392D7> + 183112) [0x103304b48]
  35  ??? (<91C5A161-D112-3F7C-937F-92AE5B3392D7> + 248184) [0x103314978]
```

前 60 行内的两个应用镜像重栈地址做了本机离线符号核对，只得到 deduplicated symbol / 编译器生成的 async thunk，未据此锁定业务函数；未访问远程符号服务。

历史旁证 `JetsamEvent-2026-11-03-140415.ips` 前 60 行（原样）：
```text
{"bug_type":"298","timestamp":"2026-11-03 14:04:15.00 +0800","os_version":"iPhone OS 27.0 (24A437)","roots_installed":0,"incident_id":"BA3CE950-E781-42FA-B92F-9D3A5DAEC55C"}
{
  "build" : "iPhone OS 27.0 (24A437)",
  "product" : "iPhone17,2",
  "kernel" : "Darwin Kernel Version 27.0.0: Thu Aug 13 21:39:16 PDT 2026; root:xnu-13432.2.10~2\/RELEASE_ARM64_T8140",
  "incident" : "BA3CE950-E781-42FA-B92F-9D3A5DAEC55C",
  "crashReporterKey" : "19343860634b5c99a43e495e5b6485370aa06c57",
  "date" : "2026-11-03 14:04:15.62 +0800",
  "codeSigningMonitor" : 2,
  "bug_type" : "298",
  "developerMode" : 1,
  "appleIntelligenceStatus" : {"state":"unavailable"},
  "timeDelta" : 10623307,
  "memoryStatus" : {
  "compressorSize" : 123274,
  "compressions" : 94080960,
  "decompressions" : 60440555,
  "zoneMapCap" : 2911223808,
  "largestZone" : "APFS_4K_OBJS",
  "largestZoneSize" : 90570752,
  "pageSize" : 16384,
  "uncompressed" : 300783,
  "zoneMapSize" : 440729600,
  "memoryPages" : {
    "active" : 122740,
    "throttled" : 0,
    "fileBacked" : 141335,
    "wired" : 116846,
    "anonymous" : 103486,
    "purgeable" : 895,
    "inactive" : 114359,
    "free" : 10594,
    "speculative" : 7722
  }
},
  "largestProcess" : "Aweme",
  "genCounter" : 1,
  "processes" : [
  {
    "states" : [
      "daemon",
      "idle"
    ],
    "genCount" : 1,
    "purgeable" : 0,
    "rpages" : 174,
    "physicalPages" : {
      "internal" : [
        1,
        160
      ]
    },
    "mem_regions" : 58,
    "uuid" : "0e021475-aab1-39e4-a8dd-e287fb3fd3b1",
    "fds" : 25,
    "name" : "appleidsetupd",
    "priority" : 0,
    "csTrustLevel" : 9,
    "cpuTime" : 0.11482299999999999,
    "freeze_skip_reason:" : "none",
```

该历史 Jetsam 内 Yubai 的 pid 68462、状态 suspended、reason long-idle-exit，largestProcess 为 Aweme；它的主程序 UUID 与本轮包不同，因此只作历史旁证，不归因到本次 PID 72206 的失败。完整 `.ips` 原件都不上传。未取得本轮 Yubai 的 hang、wakeups 或 watchdog 专属 `.ips`；系统日志中的 HangTracer 事件已在第 2 节记录。

## 7. 哪一步失败了、报错原文
本次新失败后的 App 数据复制、日志采集、三类日志导出、CPU 报告复制均成功，退出码 0；日志导出 stderr 为空。用户密码仅在 Mac Terminal 中输入，Agent 未读取。新取证快照已具备批次、分类、Recovery 与日志证据；没有通过重新整理来补证据。

历史采集失败原文保留如下，避免掩盖早期缺口：

首次无 USB 时 sudo 采集（退出码 74）：
```text
log: failed to create archive: Device not configured (6)
```

按流程不加 sudo 重试（退出码 77）：
```text
log: Must be root to collect logs from attached device
```

旧 App 数据容器复制：
```text
ERROR: An unknown error occurred. (com.apple.dt.CoreDeviceError error -1 (0xFFFFFFFF))
       ----------------------------------------
           The operation couldn’t be completed. (ContainerLookupErrorDomain error -1.)
```

旧 App Group 复制：
```text
ERROR: An unknown error occurred. (com.apple.dt.CoreDeviceError error -1 (0xFFFFFFFF))
       ----------------------------------------
           The operation couldn’t be completed. (ContainerLookupErrorDomain error 7.)
```

14:29 重装后、用户重新导入前，原 Application Support 路径不存在（退出码 1）：
```text
ERROR: Failed to retrieve the file node for Library/Application Support/app.yubai.personal (com.apple.dt.CoreDeviceError error 7000 (0x1B58))
```

初次 transportType 为 localNetwork，USB 未枚举到 iPhone；用户重新插线并解锁后恢复 wired，后续采集成功。14:29 前 App 元数据查询为空，用户确认「已没有余白图标」，随后明确要求「你要先重新安装」；Agent 据此仅安装同一提交。用户后续手动打开并导入，App 自动整理，用户确认失败后 Agent 才取得新账本快照。没有把重装后空容器或新账本冒充旧失败现场。

## 结论：EVIDENCE COMPLETE（针对重装后的这一次失败）
本次 PID 72206 / run DA7D426F-035A-48E4-8390-CF14E6A33747 已具备六小时归档、全部可导出的 run= 行、对应任务提交 / stalled / 挂起 / expiration / success: 0 链路、卡顿记录、同一安装包的 CPU 资源报告，以及失败后账本的全部要求统计和 Recovery 信息。可以确认任务过期与高 CPU / 卡顿事实，尚不能确定具体代码原因。

重装前旧轮仍为 EVIDENCE PARTIAL：旧 ledger.json、旧批次与旧 Recovery 未取得；历史日志及报告版本继续保留，本轮数据不能补写成旧轮数据。

只提交本报告与实际导出的 `.verification/yubai.log`；归档、system.log、完整 `.ips`、ledger.json、Recovery、附件、统计原始 JSON 和其他 App 元数据均留在仓库外。报告更新后切回原 main，原有 stash / 工作区状态保持不变；没有推送 main、合并 PR 或运行 Actions。
