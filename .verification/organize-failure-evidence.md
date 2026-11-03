# 整理失败取证报告
- 设备 / iOS 版本：阿雨的 iPhone，iPhone 16 Pro Max（iPhone17,2）；iOS 27.0（24A437）。DEV / UDID：`00008140-00163C340128401C`；CoreDevice Identifier：`A84CBAB1-B341-5750-BA9B-32F10683CB91`。
- 装在手机上的提交（看 App 内或问用户）：用户在本轮明确确认 `main 2970017`；本机仓库 HEAD 为 `29700179e48866c2eb047612c888734a2578c0f8`。本轮未启动 App 核对版本。
- 取证开始：2026-11-03 14:20:00 +08:00。原始产物：`~/deepresearch/yubai-evidence-2026-11-03/`。
- 范围：只读设备查询、日志采集和文件复制；未改应用代码，未整理、未测试连接、未调用 DeepSeek（本轮执行 0 次 API 请求），未读取密钥，未卸载、重装或启动 App；未创建 worktree / 模拟器。

## 1. 日志：所有 run= 行（按时间，原样）
未取得。六小时系统日志归档采集失败，`device.logarchive` 未生成，不能导出 `yubai.log`；不能把缺失日志解释为没有 `run=` 记录。未生成伪造的空日志文件。

## 2. 日志：Yubai 进程的终止、expire、watchdog、hang、jetsam 相关行（原样，最多 80 行）
未取得六小时统一日志，`system.log` 未导出，因此无可摘录的统一日志行。第 6 节保留了一份包含 Yubai 的 Jetsam 报告摘录；它不能替代本节所需的统一日志。

## 3. 导入批次统计（表格）
| 批次 id | entryIDs 数量 | needsOrganization | organizedEntryIDs 数量 | organization.skipped 前 10 条 | organization.questions 数量 |
|---|---:|---|---:|---|---:|
| 未取得 ledger.json | 未知 | 未知 | 未知 | 未知 | 未知 |

App 数据容器和 App Group 的只读复制均失败，未读取交易明细，未将 ledger.json 或任何交易明细写入报告或仓库。

## 4. 待整理 / 其他支出 / 总数
未知：未取得 ledger.json，无法统计 activeEntries 中「待整理」「没分类」「其他支出」及总数。上述数值不是 0。

## 5. 存储：ledger.json 大小、Recovery 大小与份数
未知：未取得 App 数据，不能确认 ledger.json 大小，也不能确认 Recovery 的总大小、文件数量或恢复副本份数。

## 6. 崩溃 / 卡死报告摘录
设备 systemCrashLogs 递归列表共有 234 个条目；没有名字包含 Yubai 的条目。Mac 上 `~/Library/Logs/CrashReporter/MobileDevice/` 目录不存在。

为核对通用文件名的 Jetsam 报告，额外只读复制了今天的 3 份 `JetsamEvent-2026-11-03-*.ips`：00:16:32、01:50:38 两份不含 Yubai；14:04:15 这一份含 Yubai / YubaiWidgets。完整原件仅保留在仓库外 `crashes/`，未提交。

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

结构化核对：报告内 Yubai 的 pid 为 68462，状态为 suspended，reason 为 long-idle-exit；largestProcess 为 Aweme。这是报告中的字段事实，不能据此断定本次整理失败或卡顿的根因，也不能证明该进程属于当前提交。未获得 Yubai 专属 hang、cpu_resource、wakeups 或 watchdog 报告。

## 7. 哪一步失败了、报错原文

第 2 步：sudo 采集最近六小时日志（退出码 74）：
```text
log: failed to create archive: Device not configured (6)
```

第 2 步：按流程不加 sudo 重试（退出码 77）：
```text
log: Must be root to collect logs from attached device
```

第 3 步：appDataContainer 只读复制：
```text
ERROR: An unknown error occurred. (com.apple.dt.CoreDeviceError error -1 (0xFFFFFFFF))
       ----------------------------------------
           The operation couldn’t be completed. (ContainerLookupErrorDomain error -1.)
```

第 3 步：appGroupDataContainer 只读复制：
```text
ERROR: An unknown error occurred. (com.apple.dt.CoreDeviceError error -1 (0xFFFFFFFF))
       ----------------------------------------
           The operation couldn’t be completed. (ContainerLookupErrorDomain error 7.)
```

连接核对：CoreDevice 显示已配对，实际 transportType 为 localNetwork；`xctrace list devices` 将该 iPhone 列为 Offline。USB IORegistry 和 `idevice_id -l` 未枚举到这台 iPhone。当前 macOS 的 USB profiler 类型为 `SPUSBHostDataType`，该类型也未发现 iPhone；原流程 `SPUSBDataType` 返回空输出。

App 元数据核对：指定 `app.yubai.personal` 的查询为空；包含所有类型 App 的列表返回 153 项，未找到 bundle/name 含 yubai 或余白的条目。这里记录查询结果，不据此推断用户删除过 App，也没有进行重装。已请求用户重新插拔数据线并保持解锁。

未能执行 `log show` 的原因是归档不存在，不是已成功取得一个没有事件的归档。没有用实时日志或其他设备日志冒充六小时历史日志。

## 结论：EVIDENCE PARTIAL（写明缺哪项）
已取得设备 / iOS 信息、仓库提交、用户确认的安装提交、系统崩溃文件目录，以及一份含 Yubai 的 Jetsam 报告；缺少六小时日志、所有 run= 行与相关终止日志、ledger.json、导入批次 / 分类统计、Recovery 大小与份数。证据不足以定位整理失败或卡顿根因。

本轮只发布这份报告；因没有取得 yubai.log，不伪造或提交空日志。原始设备目录、其他 App 元数据和完整崩溃报告均留在仓库外，不上传。报告分支完成后返回原分支，原有 stash 和未跟踪文件保持不动。
