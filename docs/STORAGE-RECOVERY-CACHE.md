# 存储恢复历史与云端缓存（2026-11-04）

基线为 main `43a9e2a`，工作分支 `fix/storage-recovery-cache`。本轮按 owner 真机取证修复存储策略，不提交、不推送、不加依赖、不写设计稿链接、不读密钥、不请求真实 DeepSeek；未改页面、样式或交互。以下是 Linux 离线模拟，不是真机空间复测。SplashBoard 的系统快照不处理。

## 已采用的行为

Recovery 整个目录预算为 **4 MiB（4,194,304 字节）／最多 8 份**，包含 gzip、旧 JSON／sidecar 和共享附件。按实际时间跨度优先保留最新与最早，中间选择最接近等距时间点的版本；超出字节预算时减少目标份数并重新选取，首尾都放不下时最早版本可让位。无按天到期规则。

同类自动操作以第一份为锚合并 **10 分钟**：导入整理及重试共一类，回答整理问题、按商户整理应用、批量记账各为独立类别；另覆盖自动记下、归小项、更新管家卡片与每周来信。不会随每次操作滑动窗口；恰好 600 秒即开启下一窗口。文件名足以在重启后识别，旧文件启动时也合并。手动导入、恢复前、删除批次和未知原因均不合并，照常产生各自快照后参与总预算修剪。已存在的“抹掉本机全部数据会清空恢复历史”语义保持。

最新一份与最后完整可读的一份是硬保护；可读包含附件大小和校验和检查，元数据可解码但附件缺失不能取代回退。窗口锚损坏时必须另存。共享附件只在当前账本和所有保留版本均无引用时回收；任一保留元数据不可读时保守保留。必要附件／受保护版本本身超预算、引用不可读或文件删除失败，可超过预算。启动合并遇到最新文件恰好是窗口内重复项时，窗口第一份和最新硬保护文件同时保留。

单次整理运行仍只在运行前调用 preserveRecovery，段内仍原子落盘，不新增中途快照；运行间的重试再由时间窗口合并。即时撤销仍回到本次运行前，ImportUndo 的差量及旧格式保持。App 的多条纯 addEntry 应用统一使用恢复操作事实名「批量记账」，单笔／混合大操作保持原名；提示与撤销标签保持原值。异步 iCloud 上传携带原保存原因，避免被默认「修改」绕过合并；真实 iCloud 尚未实测。

## 4,200 笔离线测量

用给定 masked.csv 经 BillImporter 实际导入 4,200 笔，保留原件与原字段。使用相同导入种子，在旧提交和新实现分别执行：导入一次、初始整理＋三次重试运行（每次对 1,050 笔实际 apply／finish／save）、四次旧问题回答、四次分组用途应用、四次批量用途应用。分类／用途是合成数据；答题走实际 ImportQuestion.answer，整理走真实 ChangeSet、ImportOrganization.finish 与 Repository，未调用模型传输。所有操作均落在 10 分钟内。这是持久化压力模拟，不是模型效果或真实 HTTP 重试测试。

| 同一流程 | Recovery 份数 | 整个目录字节 | 十进制 MB |
|---|---:|---:|---:|
| 改前 `43a9e2a` | 17 | 9,178,931 | 9.18 |
| 改后新操作 | 5 | 2,487,398 | 2.49 |
| 复制改前历史后，仅新版本 load | 6 | 3,071,715 | 3.07 |

新操作减少 **72.90%**。四次整理运行后的累计份数由 `[2, 3, 4, 5]` 变为 `[2, 2, 2, 2]`。5 份为导入前、第一次整理前、第一次答题前、第一次分组应用前与第一次批量应用前。升级得到 6 份是因为必须保留原目录最新一份；即使它与窗口第一份重复也不删。各次运行的时间与新建 ChangeSet UUID 不同，gzip 可有小幅差异。

目录总量均包含一份 **360,368 字节** CSV 共享附件。改前 gzip 为 2,339～583,813 字节／份；改后为 `[583646, 583614, 583568, 373865, 2337]` 字节。账本前后均为 **3,522,664 字节**，重新加载后整批撤销移除全部导入记录的断言通过。原始 CSV、生成账本及未整理日志全部留在 `/tmp`，未纳入仓库。

## ledger.json 字段占比

百分比的分母统一为 3,522,664 字节。顶层按对应 JSON 值计量：entries **2,582,646（73.32%）**，imports **932,950（26.48%）**，categories 5,603（0.16%），preferences 558（0.02%），accounts 195、attachments 元数据 194，其余及顶层键／分隔符不足 0.02%。数组原始附件字节不在 ledger.json 内。

下表条目字段计量包含字段名、值、冒号及分配给该字段的分隔逗号；与顶层行及后面的 imports 子项为不同层级，不能叠加求和。

| entries 字段 | 字节 | 占账本 |
|---|---:|---:|
| fingerprint | 340,200 | 9.66% |
| classificationReason | 247,800 | 7.03% |
| title | 246,017 | 6.98% |
| note | 230,120 | 6.53% |
| attachmentID | 226,800 | 6.44% |
| accountID | 214,200 | 6.08% |
| batchID | 205,800 | 5.84% |
| id | 184,800 | 5.25% |
| purpose | 130,200 | 3.70% |
| category | 106,176 | 3.01% |
| nature | 79,730 | 2.26% |
| source | 75,600 | 2.15% |
| userEdited | 75,600 | 2.15% |
| date | 71,400 | 2.03% |
| sourceRow | 70,296 | 2.00% |
| amount | 57,391 | 1.63% |
| subcategory | 12,115 | 0.34% |
| sourceIdentity／externalID | 0 | 0% |

imports 内 `organization.changeSet` 为 **768,739（21.82%）**，其中 items 为 768,601 字节：4,200 条分类和4,200 条用途修改，条目 ID 在两种操作中各出现一次。`organizedEntryIDs` 为 **163,801（4.65%）**。organization.skipped、questions、comments 均为 `[]`，各2字节；undo 为 **70 字节（约0.002%）**，没有嵌套账本。

本样本没有交易单号，sourceIdentity／externalID 未写入；不能由这个零值推断真机字段占比。真机 ledger.json 内容未读取，3.6 MB 的真实分布仍需另外取证。合成分类与用途也不代表真实模型结果；真实 skipped 的分布未测。

**未进行账本格式瘦身。** changeSet 目前直接用于导入详情预览和分类／配对统计；重复 ID 是每个操作的目标，不是无用途副本。删除明细、借用现有条目重建旧结论会丢历史信息；换成字典／索引压缩需要存储格式调整。organizedEntryIDs 用于不重发已处理记录，note 保留对手原文，fingerprint／sourceIdentity 用于去重，classificationReason／userEdited 的已有解码默认值也不能代替实际值。原实现已经省略 Entry 空值和默认值，本例无额外 slash 转义可省；仅删极小的空数组也会破坏现有必填字段解码约定。因此保留 schema 4、全部详情与撤销能力。

## URLCache 与其他缓存

DeepSeek chat、模型目录和 CloudBackend 默认统一用 `CloudNetworking.session`。会话从默认配置复制，只设 `urlCache = nil` 和 `requestCachePolicy = .reloadIgnoringLocalCacheData`；单个请求也显式忽略缓存，涵盖注入会话的调用。原有请求超时、墙钟超时、系统代理／cookie／协议行为保持，没有换成 ephemeral。

AppStore 初始化、读取账本及使用云端会话前，删除 Caches 根及本 App bundle 命名空间的 `Cache.db*` 和整个 `fsCachedData`。涵盖观察到的 `Library/Caches/app.yubai.personal/Cache.db-wal`，每次启动重试，删除失败返回路径但不新增界面。Mac 的 Caches 根与其他 App 共用，不递归删除别的 App 缓存；不查看旧数据库或响应内容。

源码核对未发现其他生产代码主动写 Caches：另两处为 `--test-ledger`／Debug 模拟器的 `YubaiUITests` 合成测试账本及 CSV，不清理。SendLog 为有字节上限的内存缓冲；模型目录同样只在内存。账本、附件和待同步标记仍在 Application Support／既有 App Group 位置，临时导出不在 Caches。SplashBoard 保持不处理。

## 验证与保留项

- 指定完整命令 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test`：**721 项，717 通过／4 项原有实网 opt-in 跳过／0 失败，99.106 秒**。新增10项策略／缓存测试及1项可选离线测量；更新旧20份和重试另留快照的断言。覆盖固定／边界／跨启动窗口、类别独立、手动操作、均匀保留、字节预算、损坏与附件缺失、共享附件和启动清理；缓存测试只用 URLProtocol 假 HTTP。
- 初始 SwiftPM 取依赖被环境代理阻断；复制本机已有同版本 repository 缓存后完成离线构建，Package.swift／Package.resolved 均未改。
- 真实 AppStore update／apply／persist 提取到 Linux 平台替身，Swift 6 严格并发类型检查并离线执行：多笔应用合并、单笔各留一份、原撤销标签、上传携带原因与落盘相等通过。同一程序复制改前目录后 load，实测上述6份／3.07 MB。
- 两份新增Core测试已登记Xcode测试分组及sources，标识唯一性与引用检查通过。App 全文件 iOS 26、macOS 14＋YUBAI_ICLOUD 条件语法解析通过；不代表 Apple SDK 编译或 UI 运行通过。
- Apple SDK／真机启动后 Cache.db 是否仍被系统组件重建、最终设备磁盘占用、系统代理实跑、真实 iCloud／后台、真实模型、真机 ledger 字段分布均未验证。
- owner同日追加授权将 RecoveryVersionsView 的「最近 20 份账本」改为「最近 8 份账本」，属于数字事实；historyCountLimit为Core内部常量，采用静态Text并添加注释指向LedgerRepository.historyCountLimit。该同步项已完成，控件与布局保持。此前新增恢复记录名称「批量记账」属于操作事实；无其他新增／改动可见中文。
- 数字补修后再次运行完整命令 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test`：**721项，717通过／4项原有实网opt-in跳过／0失败，103.522秒**。SettingsView的iOS26／macOS14条件语法解析通过；Apple SDK编译／真机显示未验证，未提交／推送。

可复跑离线测量（输入和输出都应在仓库外）：为 StorageProfileTests.testMaskedImportStorageProfile 设置 `YUBAI_STORAGE_PROFILE_CSV` 与 `YUBAI_STORAGE_PROFILE_OUTPUT`，然后用 `YUBAI_LIVE_EVAL=0 swift test --filter StorageProfileTests`。旧实现使用 `43a9e2a` 源码加同一测量测试；新旧输出的同级 import-seed.json 共用同一批导入 UUID。默认全量运行不读取 CSV，不生成测量资料。
