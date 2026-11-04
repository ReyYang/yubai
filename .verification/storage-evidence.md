# 存储取证报告

- 已装提交 / 设备：本聊天前一轮从 main `43a9e2aeadea81679ec46bd1fe4adc05a6da0cf4` 编译并覆盖安装成功；启动被 iOS 安全检查拒绝，本轮未重新安装或启动。设备为 iPhone 16 Pro Max；UDID `00008140-00163C340128401C`，本轮查询的 CoreDevice ID 为 `A84CBAB1-B341-5750-BA9B-32F10683CB91`。
- 日期：2026-11-04；本轮仅文件复制和路径/大小/数量统计，未读取账本、缓存或请求内容，未读取密钥，DeepSeek 请求 0 次。未改代码、未整理、未卸载/重装，未新建 worktree/模拟器。
- 原始产物：`~/deepresearch/yubai-evidence-2026-11-04-storage/`，不入库；仅提交本报告。当前仓库未找到 `verification/2026-11-04-storage-evidence.md`，执行用户消息中附带的完整说明。
- **取证期间用户确认“我抹掉了余白的数据”。首次设备清单仍含账本和 Recovery，随后复制及第二次清单中这些文件已消失。以下明确分开前后状态，不将抹掉后的空目录当成原始占用。**

## 1. 系统设置与 App 内存储数字

已请求 iPhone 设置中的 App 大小/文稿与数据，以及 App 内存储空间页截图；本轮尚未收到，均未知。没有用容器字节数代替系统设置数字；App 安装包大小也不在数据容器统计范围内。

## 2. 容器总大小及前 40 大路径

首次设备递归文件清单：43 个普通文件，逻辑大小合计 **42,475,817 bytes（42.48 MB，40.51 MiB）**。第二次清单：24 个普通文件，**28,152,127 bytes**。此处不包含目录元数据/文件系统分配开销；前后状态不是原子快照。

App Group 完整复制成功，设备文件清单为 0 个普通文件、0 bytes；本地 `du -sh .` 为 `0B`。

完整 App 容器复制因 SplashBoard 文件读取权限失败。本地不完整 `container` 的 `du -sh .` 为 `3.0M`，不能视为设备完整容器占用；原始 `du -ah . | sort -rh | head -40` 结果保存在本地 `container-du.txt`，App Group 对应 `appgroup-du.txt`。

以下前 40 大文件/目录按**首次设备清单的逻辑大小**排序，目录为其普通文件之和；父子项重复包含，不可相加。Recovery 文件名中的操作描述省略，避免将账本操作内容写入报告；时间戳和短 ID 保留以便本地对应。

| 路径 | 大小（bytes） |
|---|---:|
| `.` | 42,475,817 |
| `Library` | 42,475,817 |
| `Library/SplashBoard` | 24,969,360 |
| `Library/SplashBoard/Snapshots` | 24,969,360 |
| `Library/SplashBoard/Snapshots/app.yubai.personal - {DEFAULT GROUP}` | 16,646,240 |
| `Library/Application Support` | 14,394,237 |
| `Library/Application Support/app.yubai.personal` | 14,394,237 |
| `Library/Application Support/app.yubai.personal/Recovery` | 10,352,108 |
| `Library/SplashBoard/Snapshots/sceneID:app.yubai.personal-default` | 8,323,120 |
| `Library/SplashBoard/Snapshots/app.yubai.personal - {DEFAULT GROUP}/0A2C6E75-5B4D-45D2-BF40-8397FA6F2453@3x.ktx` | 4,161,560 |
| `Library/SplashBoard/Snapshots/app.yubai.personal - {DEFAULT GROUP}/8A323810-B6CB-4EE8-927C-620F474DE7B6@3x.ktx` | 4,161,560 |
| `Library/SplashBoard/Snapshots/app.yubai.personal - {DEFAULT GROUP}/A6B5C67F-0E6F-4850-AA12-2348470EF759@3x.ktx` | 4,161,560 |
| `Library/SplashBoard/Snapshots/app.yubai.personal - {DEFAULT GROUP}/C2A7DB71-9760-4E12-8810-3981E5D54646@3x.ktx` | 4,161,560 |
| `Library/SplashBoard/Snapshots/sceneID:app.yubai.personal-default/244ABCDC-696F-4B2B-A83D-78A7F1A2C803@3x.ktx` | 4,161,560 |
| `Library/SplashBoard/Snapshots/sceneID:app.yubai.personal-default/CDF2FE01-6C7E-42F9-8238-9CFE9DECE6CA@3x.ktx` | 4,161,560 |
| `Library/Application Support/app.yubai.personal/ledger.json` | 3,643,794 |
| `Library/Caches` | 3,042,744 |
| `Library/Caches/app.yubai.personal` | 2,938,896 |
| `Library/Caches/app.yubai.personal/Cache.db-wal` | 2,373,152 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756142514-B7BB1728-[操作名省略].json.gz` | 629,006 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756139878-AE3FA308-[操作名省略].json.gz` | 628,920 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756055994-4AD7D24A-[操作名省略].json.gz` | 628,722 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756136894-AB759469-[操作名省略].json.gz` | 628,722 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756053920-A9F18F92-[操作名省略].json.gz` | 628,699 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756024969-56526C05-[操作名省略].json.gz` | 628,320 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756005553-7A0E2E15-[操作名省略].json.gz` | 628,041 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755945586-F208FEF2-[操作名省略].json.gz` | 628,010 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755925271-1CA9A443-[操作名省略].json.gz` | 627,441 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755921359-EF7E01BD-[操作名省略].json.gz` | 627,411 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755907172-59BABA5C-[操作名省略].json.gz` | 627,402 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755903775-C402B494-[操作名省略].json.gz` | 627,391 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755900909-30EFBE9E-[操作名省略].json.gz` | 627,378 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755812941-C403815E-[操作名省略].json.gz` | 609,363 |
| `Library/Caches/app.yubai.personal/com.apple.metal` | 406,000 |
| `Library/Application Support/app.yubai.personal/Attachments` | 398,335 |
| `Library/Application Support/app.yubai.personal/Attachments/CCAE80B0-BB10-49AF-81B1-4F0CD0A4BAE4` | 398,335 |
| `Library/Application Support/app.yubai.personal/Recovery/Payloads` | 398,335 |
| `Library/Application Support/app.yubai.personal/Recovery/Payloads/CCAE80B0-BB10-49AF-81B1-4F0CD0A4BAE4` | 398,335 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755668475-D9D56432-[操作名省略].json.gz` | 397,223 |
| `Library/Application Support/app.yubai.personal/Recovery/1793699126690-43856FDC-[操作名省略].json.gz` | 390,935 |

## 3. 分项表

大小与文件数来自首次设备清单，抹掉后列来自第二次设备清单。路径未列出与已存在但空目录分别标注。

| 路径 | 抹掉前大小（bytes） | 文件数 | 抹掉后大小（bytes） / 文件数 |
|---|---:|---:|---|
| `Library/Caches` | 3,042,744 | 10 | 3,113,291 / 11 |
| `Library/Caches/app.yubai.personal` | 2,938,896 | 9 | 3,009,443 / 10 |
| `Library/Caches/app.yubai.personal/Cache.db` | 126,976 | 1 | 126,976 / 1 |
| `Library/Caches/app.yubai.personal/Cache.db-shm` | 32,768 | 1 | 32,768 / 1 |
| `Library/Caches/app.yubai.personal/Cache.db-wal` | 2,373,152 | 1 | 2,439,072 / 1 |
| `Library/Caches/app.yubai.personal/fsCachedData` | 0 | 0 | 4,627 / 1 |
| `Library/Application Support/app.yubai.personal/ledger.json` | 3,643,794 | 1 | 0 / 0 |
| `Library/Application Support/app.yubai.personal/Recovery` | 10,352,108 | 18 | 0 / 0 |
| `Library/Application Support/app.yubai.personal/Attachments` | 398,335 | 1 | 0 / 0 |
| `Documents` | 0 | 0 | 0 / 0 |
| `tmp` | 0 | 0 | 0 / 0 |
| `Library/HTTPStorages` | 65,736 | 3 | 65,736 / 3 |
| `Library/Saved Application State` | 3,254 | 3 | 3,254 / 3 |
| `Library/SplashBoard` | 24,969,360 | 6 | 24,969,360 / 6 |
| `Library/Preferences` | 486 | 1 | 486 / 1 |

Library/Caches 包括 URLCache 的 Cache.db、WAL、SHM 和 fsCachedData；未打开数据库。分项复制 Documents、tmp、Application Support、Caches、HTTPStorages、Preferences、Saved Application State 均退出 0，但已跨越用户抹掉动作；其中 Application Support 仅余空的 app.yubai.personal 目录，不能证明原账本已备份。缓存 WAL 在两次清单/复制间亦有变化，因此不把它们拼成一个一致快照。

### 复制失败原文

完整容器和 Library 均因同一 SplashBoard 快照读取失败；未改变权限或绕过限制。Documents、tmp 首次复制报本地目标不存在，预建本地目标目录后复制成功；设备清单显示两者为空目录，首次报错不作为设备目录缺失证据。

copy-container：

```text
ERROR: The specified file could not be transferred. (com.apple.dt.CoreDeviceError error 7000 (0x1B58))
       NSURL = file:///Users/yang/deepresearch/yubai-evidence-2026-11-04-storage/container
       ----------------------------------------
           File system operation failed: The file could not be opened for writing. (com.apple.dt.remoteservices.error error 11001 (0x2AF9))
           NSLocalizedFailureReason = The file could not be opened for writing.
       ----------------------------------------
               The operation couldn’t be completed. Failed to open the requested file for reading. (NSPOSIXErrorDomain error 5 (0x05))
               NSURL = Library/SplashBoard/Snapshots/sceneID:app.yubai.personal-default/244ABCDC-696F-4B2B-A83D-78A7F1A2C803@3x.ktx -- file:///private/var/mobile/Containers/Data/Application/B498739A-6BF9-4073-8196-9DDA428275A2/
               NSLocalizedFailureReason = Failed to open the requested file for reading.
       ----------------------------------------
                   Failed to open Library/SplashBoard/Snapshots/sceneID:app.yubai.personal-default/244ABCDC-696F-4B2B-A83D-78A7F1A2C803@3x.ktx for reading, openat(2) returned POSIX error code 1 (parentParam = 5) (NSPOSIXErrorDomain error 1 (0x01))
```

copy-Library：

```text
ERROR: The specified file could not be transferred. (com.apple.dt.CoreDeviceError error 7000 (0x1B58))
       NSURL = file:///Users/yang/deepresearch/yubai-evidence-2026-11-04-storage/fallback/Library
       ----------------------------------------
           File system operation failed: The file could not be opened for writing. (com.apple.dt.remoteservices.error error 11001 (0x2AF9))
           NSLocalizedFailureReason = The file could not be opened for writing.
       ----------------------------------------
               The operation couldn’t be completed. Failed to open the requested file for reading. (NSPOSIXErrorDomain error 5 (0x05))
               NSLocalizedFailureReason = Failed to open the requested file for reading.
               NSURL = Library/SplashBoard/Snapshots/sceneID:app.yubai.personal-default/244ABCDC-696F-4B2B-A83D-78A7F1A2C803@3x.ktx -- file:///private/var/mobile/Containers/Data/Application/B498739A-6BF9-4073-8196-9DDA428275A2/
       ----------------------------------------
                   Failed to open Library/SplashBoard/Snapshots/sceneID:app.yubai.personal-default/244ABCDC-696F-4B2B-A83D-78A7F1A2C803@3x.ktx for reading, openat(2) returned POSIX error code 1 (parentParam = 5) (NSPOSIXErrorDomain error 1 (0x01))
```

copy-Documents：

```text
ERROR: The file “Documents” couldn’t be opened because there is no such file. (NSCocoaErrorDomain error 260 (0x104))
       NSURL = file:///Users/yang/deepresearch/yubai-evidence-2026-11-04-storage/fallback/Documents
       NSFilePath = /Users/yang/deepresearch/yubai-evidence-2026-11-04-storage/fallback/Documents
       ----------------------------------------
           The operation couldn’t be completed. No such file or directory (NSPOSIXErrorDomain error 2 (0x02))
```

copy-tmp：

```text
ERROR: The file “tmp” couldn’t be opened because there is no such file. (NSCocoaErrorDomain error 260 (0x104))
       NSURL = file:///Users/yang/deepresearch/yubai-evidence-2026-11-04-storage/fallback/tmp
       NSFilePath = /Users/yang/deepresearch/yubai-evidence-2026-11-04-storage/fallback/tmp
       ----------------------------------------
           The operation couldn’t be completed. No such file or directory (NSPOSIXErrorDomain error 2 (0x02))
```

## 4. Recovery

首次清单有 **17 份 .json.gz 快照**；快照合计 **9,953,773 bytes**。另有 1 个 Payloads 文件 **398,335 bytes**。Recovery 共 **18 个普通文件、10,352,108 bytes**。

| 快照路径（操作描述省略） | 大小（bytes） |
|---|---:|
| `Library/Application Support/app.yubai.personal/Recovery/1793699124997-FF0ABC86-[操作名省略].json.gz` | 390,789 |
| `Library/Application Support/app.yubai.personal/Recovery/1793699126690-43856FDC-[操作名省略].json.gz` | 390,935 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755668475-D9D56432-[操作名省略].json.gz` | 397,223 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755812941-C403815E-[操作名省略].json.gz` | 609,363 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755900909-30EFBE9E-[操作名省略].json.gz` | 627,378 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755903775-C402B494-[操作名省略].json.gz` | 627,391 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755907172-59BABA5C-[操作名省略].json.gz` | 627,402 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755921359-EF7E01BD-[操作名省略].json.gz` | 627,411 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755925271-1CA9A443-[操作名省略].json.gz` | 627,441 |
| `Library/Application Support/app.yubai.personal/Recovery/1793755945586-F208FEF2-[操作名省略].json.gz` | 628,010 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756005553-7A0E2E15-[操作名省略].json.gz` | 628,041 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756024969-56526C05-[操作名省略].json.gz` | 628,320 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756053920-A9F18F92-[操作名省略].json.gz` | 628,699 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756055994-4AD7D24A-[操作名省略].json.gz` | 628,722 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756136894-AB759469-[操作名省略].json.gz` | 628,722 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756139878-AE3FA308-[操作名省略].json.gz` | 628,920 |
| `Library/Application Support/app.yubai.personal/Recovery/1793756142514-B7BB1728-[操作名省略].json.gz` | 629,006 |

第二次设备清单不再列出 Recovery 或 ledger.json；本轮本地没有成功复制到 ledger.json，亦未取得这些恢复快照正文。上述抹掉前数据仅为成功获取的设备文件元数据。

## 结论：EVIDENCE PARTIAL

首次文件清单显示最大的占用为 SplashBoard：24,969,360 bytes / 6 个文件，其次为 Recovery：10,352,108 bytes / 18 个文件；ledger.json 3,643,794 bytes，Caches 3,042,744 bytes。URLCache fsCachedData 为空。App Group 为 0 个普通文件。

缺口：两张存储页面截图未取得，系统 App 大小/文稿与数据和 App 内显示数字无法对照；完整容器受 SplashBoard 读取权限阻断；用户在取证期间抹掉数据，原始 ledger/Recovery 未复制成功，无法得到抹掉前的完整一致副本。已保留前后文件清单、全部复制报错和取得的副本，未清理、恢复或更改设备数据。

仅报告进入 evidence 分支；原始文件、缓存、偏好、账本和请求内容不提交。不修改 UI，可见中文字符串无变化。
