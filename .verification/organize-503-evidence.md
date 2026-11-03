# 503 取证报告

- 设备 / iOS / 已装提交：iPhone 16 Pro Max（iPhone17,2），iOS 27.0（24A437），USB wired；UDID `00008140-00163C340128401C`。已装提交按用户任务说明为 `3805da2`；本地 main 同为该提交，未独立读取安装包验证其 Git hash。
- 取证日期：2026-11-03，时间均为 Asia/Shanghai。App 数据快照约 17:48；系统日志约 17:49 采集最近 3h。
- 原始材料仅在 `~/deepresearch/yubai-evidence-2026-11-03-503/`。仅提交本报告；无账本内容、交易明细、请求内容、截图或完整日志入库。
- Agent 未改代码、未点整理或重试、未调用 DeepSeek（0 次）、未读密钥、未卸载/重装/退出 App，未创建 worktree 或模拟器。设备既有请求不能计入 Agent 的 0 次。
- 复用上一轮取证报告及本地已验证命令。未找到任务提及的 `verification/2026-11-03-organize-503-evidence.md`，按用户消息内完整要求执行。

## 1. 发送记录摘要

截图显示本次打开共 3 组、10 次发出、142 KB；3 组均没成功。三组原文共 10 次发出，与截图计数一致：7 次显示 HTTP 503、3 次显示取消。用户补充“一共三次导入”；发送组不等于当前落盘的导入批次数。

| 组时间 | 次数 | 页面显示耗时 |
|---|---:|---:|
| 17:39 | 4 | 0.4 秒 |
| 17:44 | 4 | 4.6 秒 |
| 17:45 | 2 | 0.2 秒 |

页面耗时按当前源码 `SendLogGroup.totalDurationMilliseconds` 为各请求耗时之和，不是整次整理墙钟耗时，也不能均分作为逐请求耗时。17:39、17:44 由用户按指定组复制；最初两次请求按截图唯一 2 来回组对应 17:45，用户未另行明确确认该对应。

| 组 / 请求序号 | 逐次时间 | 逐次耗时 | HTTP 状态 | finish_reason | 错误原文 |
|---|---|---|---|---|---|
| 17:39 / 1 | 未导出 | 未导出 | 503 | 未提供 | DeepSeek 返回错误（HTTP 503）。 |
| 17:39 / 2 | 未导出 | 未导出 | 503 | 未提供 | DeepSeek 返回错误（HTTP 503）。 |
| 17:39 / 3 | 未导出 | 未导出 | 未知（取消） | 未提供 | 请求已取消。 |
| 17:39 / 4 | 未导出 | 未导出 | 未知（取消） | 未提供 | 请求已取消。 |
| 17:44 / 1 | 未导出 | 未导出 | 503 | 未提供 | DeepSeek 返回错误（HTTP 503）。 |
| 17:44 / 2 | 未导出 | 未导出 | 503 | 未提供 | DeepSeek 返回错误（HTTP 503）。 |
| 17:44 / 3 | 未导出 | 未导出 | 503 | 未提供 | DeepSeek 返回错误（HTTP 503）。 |
| 17:44 / 4 | 未导出 | 未导出 | 503 | 未提供 | DeepSeek 返回错误（HTTP 503）。 |
| 17:45（按截图唯一 2 来回组对应） / 1 | 未导出 | 未导出 | 503 | 未提供 | DeepSeek 返回错误（HTTP 503）。 |
| 17:45（按截图唯一 2 来回组对应） / 2 | 未导出 | 未导出 | 未知（取消） | 未提供 | 请求已取消。 |

三份原文均未包含 Retry-After 或其他响应头，也没有 finish_reason。不能据此断言服务端没有这些头：当前 `SendLog` 不保存 headers，`SendLogRawPresentation.copyText` 不导出逐次时间/耗时。错误原文是 App 导出的错误描述，未取得服务端错误响应体。首次接收 17:39 时剪贴板仅 15 bytes、没有请求标记，该无效捕获保留但不计入组数；再次复制取得完整四次请求。

## 2. 所有 run= 行

指定子系统 info/debug 导出 `yubai.log` 为 89 bytes，仅表头，0 条事件。`system.log` 及补充的 Yubai 进程 info/debug `run=` 查询也没有字面 `run=` 行。不能将“未导出”解释为任务未运行。

系统 BackgroundTasks 的对应提交与失败完成行如下（不是伪造的 run= 行）：

```text
2026-11-03 17:39:08.503366+0800 0x5ed35f   Default     0x166ce64            74321  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.385A7D93-E16D-4EAF-A24C-672166904B1E, (title: 整理导入记录, subtitle: 已整理 0 / 1,630, resources: Default, submissionStrategy: Fail)>
2026-11-03 17:39:11.111908+0800 0x5ed35f   Default     0x166ce64            74321  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Marking task <BGContinuedProcessingTask: app.yubai.personal.organizeImports.385A7D93-E16D-4EAF-A24C-672166904B1E (整理导入记录)> complete with success: 0
2026-11-03 17:44:01.145681+0800 0x5ed35f   Default     0x16754a7            74321  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.98647E95-B12F-4AFC-8DED-20AF3392F597, (title: 整理导入记录, subtitle: 已整理 0 / 1,630, resources: Default, submissionStrategy: Fail)>
2026-11-03 17:44:05.179923+0800 0x5ed35f   Default     0x16754a7            74321  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Marking task <BGContinuedProcessingTask: app.yubai.personal.organizeImports.98647E95-B12F-4AFC-8DED-20AF3392F597 (整理导入记录)> complete with success: 0
2026-11-03 17:45:26.908125+0800 0x5ed35f   Default     0x1676b08            74321  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] submitTaskRequest: <BGContinuedProcessingTaskRequest: app.yubai.personal.organizeImports.D6E2BACA-B1E3-4192-B53A-A3F637FCDB8B, (title: 整理导入记录, subtitle: 已整理 0 / 4,200, resources: Default, submissionStrategy: Fail)>
2026-11-03 17:45:36.353542+0800 0x5ed35f   Default     0x1676b08            74321  0    Yubai: (BackgroundTasks) [com.apple.BackgroundTasks:Framework] Marking task <BGContinuedProcessingTask: app.yubai.personal.organizeImports.D6E2BACA-B1E3-4192-B53A-A3F637FCDB8B (整理导入记录)> complete with success: 0
```

三段 submit→success:0 约 2.61、4.03、9.45 秒，包含本机准备/收尾，并非逐请求耗时。17:39 与 17:44 系统任务标示 1,630 笔，17:45 标示 4,200 笔。所查日志中未见这三段对应的 stalled / expiration 证据，不能沿用上一轮 14:44 的过期结论。

## 3. Yubai 的 expire / stalled / hang / jetsam / 终止 / 网络错误行

下列为 17:00 后网络请求错误与 HangTracer 实际检测行，按时间排列；重复 telemetry 行略去，少于 80 行。17:37–17:38 的 PID 74211 与 17:39 起的 PID 74321 分开看待；前者只作较早旁证。URL 为系统隐私占位，无法把所有网络任务逐一映射到发送记录。未将 remote view controller 的 termination、普通 XPC cancellation 或 Change 字样误当 App 被杀/卡死。

```text
2026-11-03 17:37:02.768215+0800 0x5eb0cf   Default     0x0                  74211  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.57s (always-on hang reporting)
2026-11-03 17:37:03.066720+0800 0x5eb0cf   Default     0x0                  74211  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.30s (always-on hang reporting)
2026-11-03 17:37:06.404712+0800 0x5eb0cf   Default     0x0                  74211  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.53s (always-on hang reporting)
2026-11-03 17:38:02.825865+0800 0x5eceab   Error       0x166b39a            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <B87194F6-4BD2-4617-A758-4B8BF77EB1A3>.<2> finished with error [-1001] Error Domain=NSURLErrorDomain Code=-1001 UserInfo={_kCFStreamErrorCodeKey=-2102, NSUnderlyingError=0x135795f50 {Error Domain=kCFErrorDomainCFNetwork Code=-1001 UserInfo={_kCFStreamErrorCodeKey=-2102, _kCFStreamErrorDomainKey=4}}, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>, NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _kCFStreamErrorDomainKey=4}
2026-11-03 17:38:02.830840+0800 0x5ecead   Default     0x166b39a            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <44FFC756-4408-4B66-8026-7F092984260A>.<5> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:02.830917+0800 0x5ecead   Default     0x166b39a            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <463CDBDC-BC89-4EE4-B79B-CC8EC12FA012>.<7> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:02.830969+0800 0x5ecead   Default     0x166b39a            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <FB56E729-7E0D-4905-A89F-6A6BD6968C71>.<8> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:08.586504+0800 0x5ecbc7   Default     0x166bdb1            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <C1E8D55C-800F-475C-98CE-63D7D4B24B51>.<12> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:08.586533+0800 0x5ecbc7   Default     0x166bdb1            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <D010836A-11BD-4C5E-A97F-F77F13B86AED>.<9> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:08.586557+0800 0x5ecbc7   Default     0x166bdb1            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <CC468EBD-2A1B-4FD2-9184-D70A8D9F5259>.<10> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:13.476038+0800 0x5ecead   Default     0x166bf80            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <2AAE04DB-6840-4E46-A7F1-10FB01213005>.<14> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:13.476074+0800 0x5ecead   Default     0x166bf80            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <BE94A8C1-5DA3-4711-84B3-E682900A9734>.<13> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:38:13.476098+0800 0x5ecead   Default     0x166bf80            74211  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <B01D65F3-F678-4C05-BAEF-2FC23C05946B>.<15> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:39:11.108897+0800 0x5ed366   Default     0x166ce64            74321  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <EE302AD9-3463-43A3-8EA3-A7254D28A169>.<4> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:39:11.108953+0800 0x5ed366   Default     0x166ce64            74321  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <3EA51A1C-DB16-4787-AC84-7200763BFF12>.<3> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
2026-11-03 17:39:29.964272+0800 0x5ed35f   Default     0x0                  74321  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 3.40s (always-on hang reporting)
2026-11-03 17:39:30.283310+0800 0x5ed35f   Default     0x0                  74321  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.32s (always-on hang reporting)
2026-11-03 17:39:37.214616+0800 0x5ed35f   Default     0x0                  74321  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 1.30s (always-on hang reporting)
2026-11-03 17:39:38.116816+0800 0x5ed35f   Default     0x0                  74321  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.40s (always-on hang reporting)
2026-11-03 17:45:23.502524+0800 0x5ed35f   Default     0x0                  74321  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.57s (always-on hang reporting)
2026-11-03 17:45:23.775334+0800 0x5ed35f   Default     0x0                  74321  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.27s (always-on hang reporting)
2026-11-03 17:45:25.367393+0800 0x5ed35f   Default     0x0                  74321  0    Yubai: (HangTracer) [com.apple.hangtracer:] Hang detected: 0.50s (always-on hang reporting)
2026-11-03 17:45:35.418441+0800 0x5eeff0   Default     0x1676b08            74321  0    Yubai: (CFNetwork) [com.apple.CFNetwork:Default] Task <32A0F4B1-D731-46F6-B166-6FC12865DA67>.<10> finished with error [-999] Error Domain=NSURLErrorDomain Code=-999 UserInfo={NSErrorFailingURLStringKey=<private>, NSErrorFailingURLKey=<private>, _NSURLErrorRelatedURLSessionTaskErrorKey=<private>, _NSURLErrorFailingURLSessionTaskErrorKey=<private>, NSLocalizedDescription=<private>}
```

PID 74321 可见两次 17:39 网络取消、一次 17:45 网络取消，以及最长 3.40 秒的 HangTracer 事件；尚无证据将该卡顿定位为“看原文”或“拷贝原文”。所查材料未取得这三组的 App jetsam / 进程终止证据。HTTP 503 事实来源为发送记录，不能仅凭状态码确定故障发生于 DeepSeek 源站还是中间网络服务。

## 4. 导入批次统计、skipped 全部条目

当前 ledger.json 仅有以下 1 个 imports 批次；笔数按 entries[].batchID 反查。用户所述三次导入和三个发送组是历史操作证据，不能补造为当前三个落盘批次。

| 批次 ID | 笔数 | needsOrganization | organizedEntryIDs 数量 | organization.skipped 全部条目 | questions 数量 |
|---|---:|---|---:|---|---:|
| `04BD869A-9DB6-4758-8410-0D129EA64AD4` | 4200 | true | 82 | `[]` | 0 |

organizedEntryIDs 是记录覆盖标记，不等于成功分类笔数；skipped 为空数组，无省略条目。

## 5. 待整理 / 其他支出 / 总数，以及存储大小

- 待整理：3585
- 没分类：0
- 其他支出：56
- 有效总笔数：4200
- 已删除：0
- ledger.json bytes：2537562
- Recovery bytes：1571636
- Recovery 快照份数：4
- Recovery 普通文件总数：5

有效记录按 deletedAt == nil 统计；Recovery 4 份快照之外另有 1 个文件。ledger.json SHA-256：`fa39ce9ff45802f4749bab05a2c19e4a643796b27d658a06590b8e21d35b95a9`。

## 6. 崩溃 / 卡死报告摘录

`devicectl device info files --domain-type systemCrashLogs` 成功列出 248 项。今天 17:00 之后、名字含 Yubai 的 .ips 为 0 项，因此没有符合条件的前 60 行可摘录。当天唯一名字含 Yubai 的条目为 14:41:37 的 cpu_resource 报告，早于本次窗口，未冒充本次证据。无 .ips 不等于无卡顿，HangTracer 事实见第 3 节。

## 7. 用户回答与看原文、拷贝原文耗时

- tab 栏消失时机：“导入整理后就消失了”。
- 后续恢复：“tab 页在划到后台然后过几秒重新打开余白就恢复了”。该表述记录为后台返回恢复，不自行解释为杀进程重启；Agent 未操作 App 生命周期。
- 切其他页面再回来是否恢复、整理多久后报错、报错前灵动岛/锁屏进度是否走、看原文/拷贝原文分别耗时：用户回复“不记得”。之后仅补充了后台返回恢复，其他项仍未知。
- 用户最终确认“一共三次导入”，替代此前“只有这一组”的早期回答；截图和三份原文为三组。

## 结论：EVIDENCE PARTIAL

已取得三组全部导出原文、三小时系统归档、指定两类日志、当前账本全部批次统计和 Recovery 大小、崩溃目录检查及用户反馈。可确认 7 次 503 / 3 次取消、当前 3,585 笔待整理，以及用户观察到 tab 栏在后台返回后恢复。

缺口：逐请求准确时间/耗时、finish_reason、响应头（含 Retry-After）及服务端错误体未由当前导出提供；自定义 run= 日志未取得；操作耗时及当时进度用户不记得；最初两次请求与 17:45 的对应是截图推定；安装提交尚无二进制独立核验。因此不能宣称完整证据或已定位 503/tab 根因。

采集状态：首次 sudo -n 因需要密码退出 1；随后用户在本地 Terminal 完成认证，三小时归档采集退出 0。两类日志导出退出 0；system.log 4,997,732 bytes，未超过 20 MB，保留完整本地版本；App 数据复制和崩溃目录读取均退出 0。报告无新增/改动 UI 中文字符串。仅推送本报告到指定 evidence 分支，不推送 main，不运行 Actions；原工作区的 project.xcworkspace 未跟踪文件保持。
