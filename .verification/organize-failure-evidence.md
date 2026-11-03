# 整理失败取证报告
- 设备 / iOS 版本：阿雨的 iPhone，iPhone 16 Pro Max（iPhone17,2）；iOS 27.0（24A437）。DEV / UDID：`00008140-00163C340128401C`；CoreDevice Identifier：`A84CBAB1-B341-5750-BA9B-32F10683CB91`。
- 装在手机上的提交（看 App 内或问用户）：用户在本轮确认 `main 2970017`；仓库 HEAD 为 `29700179e48866c2eb047612c888734a2578c0f8`。本轮没有启动 App 读取版本。
- 取证开始：2026-11-03 14:20:00 +08:00。原始产物：`~/deepresearch/yubai-evidence-2026-11-03/`。
- 本报告补充了 USB 重连后成功取得的六小时日志，替代首次仅有 Jetsam 的部分证据报告。日志归档在本轮重新安装 App 前完成。
- 范围：未改应用或测试代码，未重新整理、未测试云端连接、未调用 DeepSeek（本轮执行 0 次 API 请求）、未读取密钥，未创建 worktree 或模拟器。用户后续明确要求「你要先重新安装」，本轮仅据此重新安装同一提交，未卸载、未启动 App。设备原先自行发生的请求不计作本轮执行，本轮没有主动增加云端请求。

## 1. 日志：所有 run= 行（按时间，原样）
USB 重连后，`sudo log collect --device-udid 00008140-00163C340128401C --last 6h` 成功，退出码 0；`device.logarchive` 大小为 1,046,426,267 bytes，保留在仓库外。

按指定谓词 `subsystem == "app.yubai.personal"`，含 info / debug 导出的 [yubai.log](yubai.log) 为 180 bytes、4 行归档标题，无事件正文，`run=` 行数为 0。它是成功导出的实际结果，不是人为创建的空占位文件。导出的系统日志中也未找到字面 `run=` 行。不能因此断言没有执行过整理：第 2 节有系统框架记录的整理任务 UUID 和生命周期。

`system.log` 原始导出为 43,495,022 bytes / 304,818 行；超过 20 MB，已按要求只保留含 `app.yubai.personal`、`organizeImports`、`BGContinued`、`expir`、`watchdog`、`jetsam`、`hang`、`terminat` 的行（不区分大小写），保留后为 10,505,984 bytes / 33,536 行，仅留本地。该文件不随报告上传。

## 2. 日志：Yubai 进程的终止、expire、watchdog、hang、jetsam 相关行（原样，最多 80 行）
以下按时间摘录 67 行：后台任务的关键生命周期、最长的 12 条 HangTracer 样本及进程终止记录。排除了仅包含 Changing 字样的行，未把 watchdogd 的普通状态更新当成 watchdog 杀进程证据。完整筛选日志保留在本地。

可直接核对的事实：09:23 的 4,200 笔任务收到前台标识不匹配错误；09:39 的 1,867 笔任务在 09:53 标记 success: 1；11:51 的 4,200 笔任务在 11:52:44 因未按预期节奏报告进度而被标记 stalled，随后系统 Expiring task、应用回报 success: 0。该系统行为不等同于已定位代码原因，success: 1 也不证明分类结果符合预期。

HangTracer 的 always-on hang reporting 共 191 条，最长 2.40 秒；未将紧邻的 under capture threshold / emitting telemetry 重复行再计一次。12:03:23 的进程终止上下文明确为 uninstallation，早于本轮 14:20 开始取证及 14:29 重装；未据此认定具体由谁卸载。

```text
2026-11-03 09:23:26.201359+0800 0x589881   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [extension<app.yubai.personal.widgets[config:6E69CA09-34E3-3493-B8FC-B5021E1ACB71]((null):121)>[uuid:7B4C5371-D198-447F-9DBB-CF9DA5489F03]:68123] termination reported by launchd (1, 17, 9)
2026-11-03 09:23:26.201412+0800 0x589881   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [extension<app.yubai.personal.widgets[config:6E69CA09-34E3-3493-B8FC-B5021E1ACB71]((null):121)>[uuid:7B4C5371-D198-447F-9DBB-CF9DA5489F03]:68123]
2026-11-03 09:23:53.159865+0800 0x589952   Default     0x14653a7            68217  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.C8884D1E-5EEB-4902-B7CB-E9B37D719947, (title: 整理导入记录, subtitle: 已整理 0 / 4,200, resources: Default, submissionStrategy: Fail)>
2026-11-03 09:23:53.161711+0800 0x5894d1   Error       0x14653a7            58290  8    dasd: [com.apple.duetactivityscheduler:BackgroundTasks] bgContinuedProcessing-app.yubai.personal.organizeImports.C8884D1E-5EEB-4902-B7CB-E9B37D719947: Foregrounded apps (<private>) don't include expected identifier: <private>
2026-11-03 09:24:30.037301+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.85s (always-on hang reporting)
2026-11-03 09:32:05.373711+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.95s (always-on hang reporting)
2026-11-03 09:32:26.315440+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.88s (always-on hang reporting)
2026-11-03 09:34:56.461811+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.85s (always-on hang reporting)
2026-11-03 09:37:01.072444+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.88s (always-on hang reporting)
2026-11-03 09:37:11.553609+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.85s (always-on hang reporting)
2026-11-03 09:37:22.433778+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.87s (always-on hang reporting)
2026-11-03 09:37:33.267389+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.87s (always-on hang reporting)
2026-11-03 09:37:52.792047+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.87s (always-on hang reporting)
2026-11-03 09:38:03.419000+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.84s (always-on hang reporting)
2026-11-03 09:38:15.317613+0800 0x589952   Default     0x0                  68217  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.95s (always-on hang reporting)
2026-11-03 09:38:24.664862+0800 0x58d37c   Default     0x1477286            36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:68217] terminate_with_reason() success
2026-11-03 09:38:24.779430+0800 0x58d37c   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:68217] termination reported by launchd (15, 0, 9)
2026-11-03 09:38:24.779985+0800 0x58d37c   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:68217]
2026-11-03 09:38:24.786971+0800 0x58d3ef   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [xpcservice<com.apple.DocumentManagerUICore.Service([app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:68217])>{vt hash: 0}{definition:com.apple.DocumentManagerUICore.Service[extension][client]}:68230] termination reported by launchd (2, 9, 9)
2026-11-03 09:38:24.787216+0800 0x58d3ef   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [xpcservice<com.apple.DocumentManagerUICore.Service([app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:68217])>{vt hash: 0}{definition:com.apple.DocumentManagerUICore.Service[extension][client]}:68230]
2026-11-03 09:38:24.796929+0800 0x58c681   Default     0x14772e5            128    8    audiomxd: (MediaExperience) [com.apple.mediaexperience:Session] -CMSessionMgr- CMSessionMgrHandleApplicationStateChange:18436 Client app.yubai.personal with session sid:0x814a4, Yubai(68217), 'auxi' [0x787a0cdc00] with pid '68217' is now Terminated. Background entitlement: NO ActiveLongFormVideoSession: NO IsLongFormVideoApp NO
2026-11-03 09:39:05.167971+0800 0x58d82d   Default     0x1477dad            68462  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59, (title: 整理导入记录, subtitle: 已整理 0 / 1,867, resources: Default, submissionStrategy: Fail)>
2026-11-03 09:39:05.168396+0800 0x58d82d   Default     0x1477dad            68462  0    Yubai: (DuetActivityScheduler) [com.apple.backgroundtasks:framework] Submitting task request activity: bgContinuedProcessing-app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59:584124
2026-11-03 09:39:05.169774+0800 0x58daa4   Default     0x1477dad            58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] SUBMITTED bgContinuedProcessing-app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59:584124 at priority 90 (Sat Dec 30 08:06:00 0000 - Tue Nov  3 09:39:05 2026)
2026-11-03 09:39:05.171801+0800 0x58db2a   Default     0x0                  68462  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Running task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59 (整理导入记录)>
2026-11-03 09:39:05.476218+0800 0x58d82d   Default     0x0                  68462  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Starting task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59 (整理导入记录)>
2026-11-03 09:44:05.979973+0800 0x58f031   Error       0x1477dad            58290  8    dasd: [com.apple.duetactivityscheduler:ProgressTracker] [0x7d8488ed60:bgContinuedProcessing-app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59:584124] Slow warmup ROP: 0.0777757093006242 / minute
2026-11-03 09:53:18.754458+0800 0x58d82d   Default     0x1477dad            68462  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Marking task <BGContinuedProcessingTask: app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59 (整理导入记录)> complete with success: 1
2026-11-03 09:53:18.754509+0800 0x58d82d   Default     0x1477dad            68462  0    Yubai: (DuetActivityScheduler) [com.apple.backgroundtasks:framework] Complete task request activity: bgContinuedProcessing-app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59:584124 (Succeeded)
2026-11-03 09:53:18.755142+0800 0x59088f   Default     0x1477dad            58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] COMPLETED <_DASActivity: "bgContinuedProcessing-app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59:584124", UserInitiated, 900s, [1/1/1 08:06:00 - 2026/11/3 09:39:05], Started at 2026/11/3 09:39:05, Group: com.apple.dasd.continuedProcessing, InternalGroups: {(
2026-11-03 09:53:18.756522+0800 0x59088f   Default     0x1477dad            58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle(activityGroup)] NO LONGER RUNNING bgContinuedProcessing-app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59:584124 ...Tasks running in group [com.apple.dasd.continuedProcessing] are 0!
2026-11-03 09:53:18.757920+0800 0x5908fa   Default     0x1477dad            58290  8    dasd: [com.apple.duetactivityscheduler:ActivityProgress] Finishing progress (completed) to <NSProgress: 0x7d84ee7e80> : Parent: 0x0 (portion: 0) / Fraction completed: 1.0000 / Completed: 1 of 1   for bgContinuedProcessing-app.yubai.personal.organizeImports.5C462955-E2F9-4E99-98D5-4CC0E37EEA59:584124
2026-11-03 10:18:56.434376+0800 0x595315   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [extension<app.yubai.personal.widgets[config:6E69CA09-34E3-3493-B8FC-B5021E1ACB71]((null):121)>[uuid:7B4C5371-D198-447F-9DBB-CF9DA5489F03]:68467] termination reported by launchd (1, 17, 9)
2026-11-03 10:18:56.434490+0800 0x595315   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [extension<app.yubai.personal.widgets[config:6E69CA09-34E3-3493-B8FC-B5021E1ACB71]((null):121)>[uuid:7B4C5371-D198-447F-9DBB-CF9DA5489F03]:68467]
2026-11-03 10:58:46.777174+0800 0x59ea65   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:68462] termination reported by launchd (1, 17, 9)
2026-11-03 10:58:46.777859+0800 0x59ea65   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:68462]
2026-11-03 10:58:46.820042+0800 0x59f0af   Default     0x15388b3            128    8    audiomxd: (MediaExperience) [com.apple.mediaexperience:Session] -CMSessionMgr- CMSessionMgrHandleApplicationStateChange:18436 Client app.yubai.personal with session sid:0x814b0, Yubai(68462), 'auxi' [0x78793fa000] with pid '68462' is now Terminated. Background entitlement: NO ActiveLongFormVideoSession: NO IsLongFormVideoApp NO
2026-11-03 11:45:59.739916+0800 0x5abff2   Default     0x1577dd1            36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] [app<app.yubai.personal((null))>:70267] terminate_with_reason() success
2026-11-03 11:45:59.746315+0800 0x5ac69a   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [app<app.yubai.personal((null))>:70267] termination reported by launchd (15, 0, 9)
2026-11-03 11:45:59.750084+0800 0x5ac69a   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [app<app.yubai.personal((null))>:70267]
2026-11-03 11:51:21.344641+0800 0x5adbb6   Default     0x0                  70398  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 2.40s (always-on hang reporting)
2026-11-03 11:51:42.696376+0800 0x5adbb6   Default     0x1580229            70398  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C, (title: 整理导入记录, subtitle: 已整理 0 / 4,200, resources: Default, submissionStrategy: Fail)>
2026-11-03 11:51:42.697887+0800 0x5ad9bb   Default     0x1580229            58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] SUBMITTED bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44 at priority 90 (Sat Dec 30 08:06:00 0000 - Tue Nov  3 11:51:42 2026)
2026-11-03 11:51:42.700531+0800 0x5adf91   Default     0x0                  70398  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Running task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C (整理导入记录)>
2026-11-03 11:51:42.853618+0800 0x5adbb6   Default     0x0                  70398  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Starting task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C (整理导入记录)>
2026-11-03 11:52:31.326173+0800 0x5ae249   Default     0x0                  52     8    powerd: [com.apple.powerd:assertions] Process dasd.58290 Summary PreventUserIdleSystemSleep "DASActivity:bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C" age:00:00:48  id:4295004713 [System: PrevIdle SysAct] [Qualifiers: AllowsDeviceRestart]
2026-11-03 11:52:44.264097+0800 0x5ae0ed   Error       0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:ProgressTracker] [0x7d84827a80:bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44] Task has not reported progress within expected cadence, marking stalled (time without update: -38.09956693649292)
2026-11-03 11:52:44.264474+0800 0x5ae0ed   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:scoring] bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44:[
2026-11-03 11:52:44.264515+0800 0x5ae0ed   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] Suspending bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44 - required criterion is not satisfied.
2026-11-03 11:52:44.270934+0800 0x5ae163   Default     0x0                  70398  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Expiring task: <BGContinuedProcessingTask: app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C (整理导入记录)>
2026-11-03 11:52:44.271270+0800 0x5adbb6   Default     0x0                  70398  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Marking task <BGContinuedProcessingTask: app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C (整理导入记录)> complete with success: 0
2026-11-03 11:52:44.272317+0800 0x5ae3bf   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle] COMPLETED <_DASActivity: "bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44", UserInitiated, 900s, [1/1/1 08:06:00 - 2026/11/3 11:51:42], Started at 2026/11/3 11:51:42, Group: com.apple.dasd.continuedProcessing, InternalGroups: {(
2026-11-03 11:52:44.273565+0800 0x5ae3bf   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:lifecycle(activityGroup)] NO LONGER RUNNING bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44 ...Tasks running in group [com.apple.dasd.continuedProcessing] are 0!
2026-11-03 11:52:44.273848+0800 0x5ae319   Default     0x0                  52     8    powerd: [com.apple.powerd:assertions] Process dasd.58290 SessionEnded PreventUserIdleSystemSleep "DASActivity:bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C" age:00:01:01  id:4295004713 [System: PrevIdle SysAct]
2026-11-03 11:52:44.274927+0800 0x5ae0ec   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:ActivityProgress] Finishing progress (incomplete) to <NSProgress: 0x7d842de500> : Parent: 0x0 (portion: 0) / Fraction completed: 0.0000 / Completed: 0 of 0 CANCELLED  for bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44
2026-11-03 11:52:44.279599+0800 0x5ae0ec   Default     0x0                  58290  8    dasd: [com.apple.duetactivityscheduler:ActivityProgress] Finishing progress (incomplete) to <NSProgress: 0x7d844ba400> : Parent: 0x0 (portion: 0) / Fraction completed: 0.0000 / Completed: 0 of 0 CANCELLED  for bgContinuedProcessing-app.yubai.personal.organizeImports.2432B7ED-5978-422C-9B49-CEBF0F034F2C:005D44
2026-11-03 12:02:03.092858+0800 0x5afa17   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [xpcservice<com.apple.DocumentManagerUICore.Service([app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:70398])>{vt hash: 0}{definition:com.apple.DocumentManagerUICore.Service[extension][client]}:70408] termination reported by launchd (1, 17, 9)
2026-11-03 12:02:03.092883+0800 0x5afa17   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [xpcservice<com.apple.DocumentManagerUICore.Service([app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:70398])>{vt hash: 0}{definition:com.apple.DocumentManagerUICore.Service[extension][client]}:70408]
2026-11-03 12:02:03.163486+0800 0x5afa1c   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [extension<app.yubai.personal.widgets[config:6E69CA09-34E3-3493-B8FC-B5021E1ACB71]((null):121)>[uuid:7B4C5371-D198-447F-9DBB-CF9DA5489F03]:70315] termination reported by launchd (1, 17, 9)
2026-11-03 12:02:03.163540+0800 0x5afa1c   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [extension<app.yubai.personal.widgets[config:6E69CA09-34E3-3493-B8FC-B5021E1ACB71]((null):121)>[uuid:7B4C5371-D198-447F-9DBB-CF9DA5489F03]:70315]
2026-11-03 12:03:23.528892+0800 0x5afecd   Default     0x1587da7            36     0    runningboardd: (RunningBoard) [com.apple.runningboard:connection] Received termination request from [osservice<com.apple.installcoordinationd>:57256] on <RBSProcessPredicate <RBSProcessBundleIdentifierPredicate "app.yubai.personal">> with context <RBSTerminateContext| explanation:IX terminating bundleIDs for uninstallation: {(
2026-11-03 12:03:23.543561+0800 0x5afecd   Default     0x1587da7            36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:70398] Terminating with context: <RBSTerminateContext| explanation:IX terminating bundleIDs for uninstallation: {(
2026-11-03 12:03:23.543626+0800 0x5afecd   Default     0x1587da7            36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:70398] terminate_with_reason() success
2026-11-03 12:03:23.576199+0800 0x5afe46   Default     0x0                  1      0    launchd: [user/501/UIKitApplication:app.yubai.personal[dd6d][rb-legacy] [70398]:] exited with exit reason (namespace: 15 code: 0x0) - OS_REASON_RUNNINGBOARD | <RBSTerminateContext| explanation:IX terminating bundleIDs for uninstallation: {(
2026-11-03 12:03:23.577172+0800 0x5afecd   Default     0x0                  36     7    runningboardd: (RunningBoard) [com.apple.runningboard:ttl] [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:70398] termination reported by launchd (15, 0, 9)
2026-11-03 12:03:23.577917+0800 0x5afecd   Default     0x0                  36     0    runningboardd: (RunningBoard) [com.apple.runningboard:process] Removing assertions for terminated process: [app<app.yubai.personal(BBD18117-F06C-4072-A801-7DD278579A85)>:70398]
2026-11-03 12:03:23.582807+0800 0x5afd3b   Default     0x1587df4            128    8    audiomxd: (MediaExperience) [com.apple.mediaexperience:Session] -CMSessionMgr- CMSessionMgrHandleApplicationStateChange:18436 Client app.yubai.personal with session sid:0x81558, Yubai(70398), 'auxi' [0x787a0cf800] with pid '70398' is now Terminated. Background entitlement: NO ActiveLongFormVideoSession: NO IsLongFormVideoApp NO
```

## 3. 导入批次统计（表格）
| 批次 id | entryIDs 数量 | needsOrganization | organizedEntryIDs 数量 | organization.skipped 前 10 条 | organization.questions 数量 |
|---|---:|---|---:|---|---:|
| 旧 ledger.json 未取得 | 未知 | 未知 | 未知 | 未知 | 未知 |

USB 重连前后，旧 App 的 appDataContainer / appGroupDataContainer 复制均失败。CoreDevice 和 MobileInstallation 的指定 bundle 查询均未找到 App，用户随后确认「已没有余白图标」。用户明确要求重装后，原 Application Support 路径仍不存在。没有把重装后的数据作为故障现场统计；未取得或上传 ledger.json，报告没有交易明细。

## 4. 待整理 / 其他支出 / 总数
未知：没有取得故障现场 ledger.json，无法统计 activeEntries 中「待整理」「没分类」「其他支出」及总数。上述数值不是 0。

## 5. 存储：ledger.json 大小、Recovery 大小与份数
未知：没有取得故障现场 App 数据，不能确认 ledger.json 大小，也不能确认 Recovery 总大小、文件数量或恢复副本份数。

## 6. 崩溃 / 卡死报告摘录
设备 systemCrashLogs 初次递归列表共 234 个条目，没有名字包含 Yubai 的条目；Mac 上 `~/Library/Logs/CrashReporter/MobileDevice/` 目录不存在。没有取得 Yubai 专属的 hang、cpu_resource、wakeups 或 watchdog `.ips`。 USB 重连后再次按 Yubai 筛选 systemCrashLogs，结果仍为 0 项。

为核对通用文件名的 Jetsam 报告，只读复制了今天 3 份 `JetsamEvent-2026-11-03-*.ips`：00:16:32、01:50:38 两份不含 Yubai；14:04:15 这一份含 Yubai / YubaiWidgets。完整原件仅保留在仓库外 `crashes/`，未提交。

`JetsamEvent-2026-11-03-140415.ips` 前 60 行（原样）：
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

结构化核对：这份 Jetsam 中 Yubai 的 pid 为 68462、状态 suspended、reason 为 long-idle-exit；largestProcess 为 Aweme。该记录不能直接作为 11:52 整理失败的原因，也不能证明其中所有进程对应同一安装提交。

## 7. 哪一步失败了、报错原文

第 2 步首次 sudo 采集失败；USB 重连后补采成功，此阻塞已解除（退出码 74）：
```text
log: failed to create archive: Device not configured (6)
```

第 2 步按流程不加 sudo 重试失败（退出码 77）：
```text
log: Must be root to collect logs from attached device
```

第 3 步 appDataContainer，USB 重连前后的报错相同：
```text
ERROR: An unknown error occurred. (com.apple.dt.CoreDeviceError error -1 (0xFFFFFFFF))
       ----------------------------------------
           The operation couldn’t be completed. (ContainerLookupErrorDomain error -1.)
```

第 3 步 appGroupDataContainer，USB 重连前后的报错相同：
```text
ERROR: An unknown error occurred. (com.apple.dt.CoreDeviceError error -1 (0xFFFFFFFF))
       ----------------------------------------
           The operation couldn’t be completed. (ContainerLookupErrorDomain error 7.)
```

按用户后续要求重新安装后，只读复制原 Application Support 路径失败（退出码 1）：
```text
ERROR: Failed to retrieve the file node for Library/Application Support/app.yubai.personal (com.apple.dt.CoreDeviceError error 7000 (0x1B58))
```

USB 重连后补采原始回执（退出码 0）：
```text
Archive successfully written to /Users/yang/deepresearch/yubai-evidence-2026-11-03/device.logarchive
```

连接核对：首次是 localNetwork / xctrace Offline，USB 列表没有该 iPhone；用户重新连接并解锁后，`idevice_id -l` 返回正确 UDID，CoreDevice 的 transportType 为 wired。当前 macOS USB profiler 类型为 SPUSBHostDataType，原流程的 SPUSBDataType 返回空输出。

重装时间：2026-11-03T14:29:52.962501+08:00。使用之前从 main 2970017 编译成功的现有 Debug 真机包；`devicectl device install app` 退出码 0、bundleID 为 app.yubai.personal。只安装，未启动 App。重新安装是本轮后续用户指令新增的动作，不改变前面已保存日志的来源和时间；没有以新账本冒充原账本。

## 结论：EVIDENCE PARTIAL（写明缺哪项）
已补齐六小时系统归档、两类日志导出、可核对的后台任务过期与卡顿记录、进程卸载终止记录，以及含 Yubai 的 Jetsam 报告。`run=` 自定义日志在指定归档导出中没有记录。仍缺故障现场 ledger.json、导入批次 / 分类统计、Recovery 大小与份数，不能定位具体代码原因。

只提交本报告与实际导出的 `.verification/yubai.log`；归档、system.log、完整崩溃报告、其他 App 元数据和任何账本数据均不上传。报告分支更新后返回原 main；原有 stash、未跟踪文件与 main 提交保持不变。
