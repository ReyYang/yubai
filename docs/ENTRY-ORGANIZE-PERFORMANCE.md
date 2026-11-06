# 记账与整理性能修复（2026-11-05）

范围：`fix/entry-organize-stutter`，基于 `main a0f21da`。不改变资金口径、界面、文案、动效或分类交互。不调用付费 API。

## 改动

- `LedgerRepository` 保存并复用最后一次已验证的元数据及原始字节。CAS 仍从实际文件计算 digest；恢复合并命中时省去第二次读盘、解码和压缩。`put` 从内存取得旧附件 checksum。
- 恢复元数据按规范化 URL、大小、修改时间、inode 和创建时间缓存引用与可读性；附件文件身份也参与失效判断。新快照直接记录已知引用，并校验恢复 payload 的可读性。历史剪枝使用刚写入的账本，不重复解码历史及当前文件。保留时间分布、数量／字节预算、损坏文件／可读后备保护、附件引用保护和路径别名规则。
- 普通元数据保存继续采用原有的附件延迟校验策略；读取／导出／恢复仍校验附件。恢复缓存会重新检查发生变化的文件，损坏的恢复版本不能触发合并跳过。缓存元数据移除 repository 定位引用，避免持有自身的引用环。
- 手动变更先在 MainActor 校验并发布，`LedgerWriteQueue` 同步入队、后台串行写盘。首次手动保存失败后，拒绝依赖它的后续快照，重新读取磁盘的最后一致状态并清空相关撤销、提示与动效状态，使用现有错误提示。
- 整理保存、预整理快照与手动保存共用写入队列。checkpoint 保留 `ledgerRevision` 与 repository revision 的 CAS；准备或写入期间接受了手动修改，就等待手动写入完成并重新应用本次整理回复。停止期间已完成的原子写入仍会发布。
- scenePhase 进入 background 时排空已提交写入；Mac 正常终止时也排空。后台整理继续使用原队列及现有后台任务。存储清理和位置切换先排空写入；同步只上传已落盘的最新快照；接收远端副本在等待落盘期间若有手动修改，仍进入现有的版本选择流程。
- `Ledger` 的运行时计算缓存不进入 Codable／相等比较；任一存储字段及其嵌套修改都会使副本的缓存失效。资金缓存覆盖未来记账时刻、日界、账户提醒阈值与时区，验证缓存同时覆盖日历／格式器时区。
- 单条新增不再构建全量操作索引和原始 Entry 字典；其他单条操作按需查找。预览复用 funds，以受影响账户、债务、未明确流入的增量计算；历史支出／退款及固定收付关联才重算相应预留。新增 Entry 编辑预览重用保存前处理，只验证受影响记录及退款关系。
- 现金图复用日期格式器和日标签，避免对窗口外流水计算日界；日常开销使用预先建立的日历窗口。工资检测复用重复付款方与未变账本的结果。
- checkpoint 在后台准备资金、现金图、排序／ID 索引、固定收付、软线进度及管家队列，与账本一起发布。账户余额／关联记录、洞察索引、软线进度与固定收付使用 AppStore 缓存。

四个并行分支的表单文件均保持字节不变：`QuickEntryView.swift`、`EntryEditView.swift`、`EntryFormComponents.swift`、`FixedFlowsView.swift`。

新增或改动的可见中文字符串：**无**。新增错误处理复用现有提示。

## Linux release 测量

相同的用户脱敏 CSV，4,200 条，`ledger.json` 2,476,753 字节，测量开始时已有 8 份恢复历史。临时账本位于系统临时目录，测试结束后删除；CSV 和账本内容未纳入仓库、报告或提交。

“修复前”采用任务说明提供的数据；“修复后”来自本轮最终 release profile，单位 ms。缓存命中和首次计算分开标注，数值为脚本指定次数的平均值。

| 操作 | 修复前 | 修复后 |
|---|---:|---:|
| 默认 save，保留恢复历史 | 1,313 | 140.2 |
| 合并窗口内 save（首轮含建立锚点） | — | 89.3 |
| save，不保留恢复历史 | 197 | 73.9 |
| encodeMetadata | 73 | 65.6 |
| decode | 91 | 100.7 |
| cashTimeline，复用 funds | 85 | 8.8 |
| available，连续新增预览 | 37 | 0.3 |
| available，首次新增预览（funds 已准备） | — | 0.4 |
| available，编辑预览 | — | 1.7 |
| ChangeSet.apply，单条新增 | 23.5 | 3.0 |
| QuickCaptureSnapshot，后台 | 58 | 38.8 |
| Finance.funds，首次计算 | 15 | 3.4 |
| Finance.funds，缓存命中 | — | <0.1 |
| Finance.balance | — | 0.1 |
| SalaryDetection，现金图后复用 | <6 | <0.1 |
| PendingImportOrganization | <6 | 3.9 |
| FixedFlows.month | <6 | 1.3 |
| FixedFlows.autoSettle | <6 | 0.4 |
| FixedFlows.suggestions | <6 | 0.5 |
| categories | <6 | <0.1 |
| guessCategory | <6 | 0.4 |
| defaultAccount | — | 0.1 |
| validate，已验证未变账本 | <6 | <0.1 |
| sort entries | — | 2.5 |
| EntryTimeline.snapshot | <6 | 0.1 |
| activeEntries | — | 0.8 |
| ledger == | — | <0.1 |
| RestrainProgress／ButlerCards.queued（本次输入无消费观／卡片） | — | <0.1 |

默认保存 ≤250 ms、现金图 ≤15 ms、连续新增／编辑预览 ≤3 ms 的目标均达到。decode 本身未优化，单次测量有波动。

## 验证与复现

```sh
export PATH=/opt/swift-rootfs/usr/bin:$PATH
swift test
PROF_CSV=/path/to/masked.csv swift test -c release -Xswiftc -enable-testing --filter PerformanceProfile
python3 scripts/audit-swift-access.py --output /tmp/yubai-stutter-access.json --summary /tmp/yubai-stutter-access.tsv
```

- 全量 `swift test`：**801 项，797 通过、4 项原有实网测试跳过、0 失败，110.080 秒**。未新增 skip；本轮没有调用真实 DeepSeek。
- opt-in `PerformanceProfileTests`：**1 项通过、0 失败，11.260 秒**。没有 `PROF_CSV` 时直接返回；保存、现金图、预览有宽松耗时上限。
- 默认运行的 `PerformanceScaleTests`：4,200 条合成数据，新增／编辑与完整 apply／edit + funds 等价；覆盖收入、支出、信用卡、转账、退款、未来日期、固定收付与房租关联、无工资／有工资现金图、日期窗口和缓存失效。只断言正确性，不断言耗时。现金图及日常开销保留优化前算法作测试 oracle。
- 写入队列测试覆盖两个交错顺序、过期 CAS、失败后依赖快照拒绝与重新读取磁盘；恢复缓存测试覆盖损坏元数据／payload 和外部当前文件变更。原有存储、恢复政策、路径符号链接与现金图测试全部通过。
- `audit-swift-access.py`：41 个 App 文件 + 1 个 UI 文件、1,202 个访问声明；没有同一 owner 的跨文件 private 越权匹配。新增访问成员逐项复核，ledger／undo 的修改仍留在声明文件。
- 41 个 App 文件分别以 iOS 27.1 simulator／macOS 14、iCloud／App Group 条件解析：**82 次通过**。
- 从实际源码提取 AppStore update／persist／undo／restore／checkpoint／发布方法、保留文件访问边界，用 Linux 平台外壳链接真实 Core：Swift 6 严格并发、warnings-as-errors 编译及立即发布、串行保存、撤销／恢复、checkpoint 重试、CAS 失败回滚实跑通过。外壳有替身，不能代替 Apple SDK 编译。

Apple SDK／Xcode 编译、真机卡顿复验、系统实际挂起／终止和 iCloud 实机验证仍需 Mac／设备。应用可排空已提交写入，不能承诺突然断电或强制终止时操作系统会提供生命周期回调。

