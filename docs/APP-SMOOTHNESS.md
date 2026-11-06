# 2026-11-06 全应用流畅度性能整理

范围来自 owner 的 P1／P2／P3／P5／P6 清单，续接网络中断留下的三份 diff；分支 `fix/app-wide-smoothness`。保留四个常驻 NavigationStack 的横向 pager。没有采用新的产品或视觉决定，没有改 token、文案、动效时长／曲线、触感、手势阈值、辅助功能标识或测试 value；未提交、未推送，无新增依赖。

| 项目 | 最终实现位置与行为 |
|---|---|
| P1-1 | `YubaiApp.swift / AppStore.invalidateDerived, refreshTimeDerived`：preferences／accounts／cards 及 profile／plans／rents／imports／mutedTopics／categoryAliases 使用存储镜像，先比较再赋值；funds／cashTimeline／butlerVisibility／pendingOrganization／sortedEntries／entryTimeline／salary／restrainProgress 使用独立 revision，仅在已有缓存结果改变时递增。首次尚无订阅时保持惰性计算。源账本与缓存写入全部 ObservationIgnored，保留 current。funds 的时区、时钟回拨、午夜、未来入账／关联日期、14 天对账阈值到期规则保留；整理 checkpoint 的预计算缓存继续接入。 |
| P1-2 | 四个根页、TabRootHeader、NowActionCards／ButlerCardView、CashTimelineCard、HeroCard 调用、记一笔／改一笔的账户读取及其他 AmountLabel 的隐私偏好读取迁移镜像。`AppStore.accountName` 保留原「未指定账户」回退。根页不再读取整本账本；洞察／设置统计仍按 ledgerRevision 刷新自身缓存。 |
| P1-3 | `YubaiApp.swift / ButlerRefreshTask, WeeklyPushTask, LedgerPrivacyCover`：任务身份及隐私遮盖在独立观察作用域里读取数据；根 body 不再订阅 id／updatedAt。sheet 同样使用独立隐私遮盖。 |
| P2-1 | `IntelligenceRuntime.swift / refreshButler`：可取消的 800ms 等待，保留分类／记忆反思调用；Sendable ledger 快照在 detached utility task 中执行 detect／WeeklyLetter／PendingImportOrganization。取消传给后台任务，回主线程前后保留取消／current == before／锁／整理 guard。 |
| P2-2 | `Finance.swift / LedgerPresentationCache.cashFlow, cashFlowSlices`、`AppStore`、`InsightsView.body`：每个账本 revision 缓存汇总和两个方向的分片。实时 Date() 末端用记录日期的二分边界键复用相同成员的半开区间；不舍入日期，越过未来记录时正确失效。 |
| P2-3 | `SavingViews.swift / LetterSubscriptionCard.currentCandidates`：改读 AppStore 的每 revision 候选缓存。 |
| P2-4 | `Finance.swift / LedgerPresentationCache.flowRecords`、`InsightsView.swift / FlowRecordsView.body`：缓存完整索引、稳定日期排序及分类／方向／区间／小项查询，首帧同步取得行。保留跨期退款追溯和分类别名。 |
| P2-5 | `SettingsView.accountsCard, thinkingCount, followUpCount, memoryCount, fixedFlowsDetail`：缓存现金账户余额、心愿／记忆计数与固定收付标题；未来入账／回访时间／午夜／时区和时钟回拨可失效。磁盘用量 task 移到独立 modifier。 |
| P2-6 | `ImportView.open, screenshotOriginal`：打开待核对文件时解码 UIImage／NSImage 到 State，body 复用图片。 |
| P2-7 | `SubcategoryViews`：小项统计、汇总、记录筛选复用缓存；`ButlerViews`／`SavingPurchaseViews`：证据行按 IDs＋是否排除删除缓存；`EntryEditView`／`EntryDetailView`／小项弹窗与心愿已买记录检查：复用 entriesByID；`EntriesView.noteText`：手记用途字典改在 AppStore 按结果变化通知，移除整页 ledgerRevision 的 onChange 扫描；`ButlerCardView.exceedsRestraint` 复用 restrainProgress。`SavingViews / SavingsHeader` 省钱合计、`SavingPurchaseViews` 购买建议、`QuickCaptureSettingsView` 近七天流水也加入缓存；省钱缓存保留月合计 `< now` 与总合计 `< now + 1ms` 的差别，捕获记录保留 recordedAt 和跨日边界。低频操作中的扫描及原本已有 task／缓存的计算保留。 |
| P3-1 | `DesignSystem.swift / PaperShadowCache, PaperShadowImage, PaperCardSurface`：iOS 用 SwiftUI Canvas 的 shadowOnly 保留 near → far 链式 alpha 组合，经 ImageRenderer／UIGraphicsImageRenderer 生成一张带 capInsets 的阴影图。缓存包含圆角／样式、色彩方案、比例、对比度；短边保留实际尺寸，长边仅拉伸恒定中段。外扩 padding 不参与布局、交互或读屏。填充、顶部高光和增强对比描边仍为原有实时形状。macOS 和未来非圆角矩形形状保留原双阴影。 |
| P3-2 | `DesignSystem.swift / BambooRasterCache, BambooShadow`：按色彩方案／比例预渲染原 tinted 230×299 分支和 blur 6，保留模糊外扩区与原对齐尺寸；旋转、翻转、offset、opacity、sway 和两种减少效果偏好保持。 |
| P3-3 | `YubaiApp.swift / FloatingTabBar.body`：float 阴影移至同材质和 tint 的 Capsule 背景；ask 阴影移至加号 Circle 背景。 |
| P3-4 | `rootPageHeader` 顶部 fade mask 保持原样。 |
| P5-1 | `EntriesView.swift / LedgerEntryRow.body`：只在不同 ID 时写 revealedEntryID；分页锁写入均先比较。SwipeActionRow 保持原样。 |
| P5-2 | `CashTimelineCard.swift / touchSurface, CashTimelineTextMetrics, CashTimelineBaseChart, selectionOverlay`：清除选择／进入 holding／plotWidth 写入先比较；按 text＋width＋字号缓存原测量算法；基础 marks／axes 放入不含 selectedDay 的 Equatable 子视图。选择竖线／点放在 chartOverlay，使用相同 ChartProxy 坐标及原 1pt／5pt／9pt 几何；读数、标注显隐、胶囊与原动态 bandHeight 保持。 |
| P5-3 | `YubaiApp.swift / RootView.mainContent`：visibleTab／pagingAligned／pagingPhase／destination 写入前比较，pager 结构与导航规则保持。 |
| P6-1 | `DesignSystem.swift / CardRows.init, body`：每个 rows view value 构造时用原 ID 序列计算一次 Hasher 值，body 用标量触发动效；不再每次构造和比较 ID 数组。沿用原动画参数。 |
| P6-2 | 跳过后台页的数值转场禁用。横向滑动时两页可同时露出，按当前 tab 禁用会影响进入页可见转场；为保持视觉与时机一致，保留原动画。 |

Core 迁移逻辑的新增测试位于 `Tests/YubaiCoreTests/PresentationCacheTests.swift`，13 项覆盖半开区间／实时末端与分片、跨期退款／别名／小项、稳定排序／删除策略、同时间戳更新／撤销／不同账本、未来入账／时间回拨、回访阈值／跨周、订阅变化及小项分类变化、省钱严格时间边界／停订计提与撤销、近七天捕获的未来／跨日／回拨。所有新增缓存均有容量上限或按 revision 丢弃旧数据。

验证：Swift 6.2.4 Linux `swift build --target YubaiCore` 和 `YUBAI_LIVE_EVAL=0 swift test` 通过；全量 887 项，883 通过／4 项原有实网 opt-in 跳过／0 失败。缓存环境移到 `/tmp/yubai-smooth-{clang,cache}`，最终日志 `/tmp/yubai-smooth-{build,test}-final.log`。33 个改动 App Swift 文件逐个以 Linux、iOS26 simulator Debug、macOS14 Debug 解析，共 99 次通过，记录 `/tmp/yubai-smooth-parse.json`。从实际 AppStore／SavingCardVisibility／LedgerDerivedSnapshot／EntryNotePresentation 源码抽取的 Foundation 平台探针在 `-swift-version 6` 下编译并执行，24 个观察断言通过，覆盖无关备注不通知镜像／资金等、相关变化通知、相同赋值不通知及其他月份 timeline 不通知；仅平台桥接与导航生命周期用空替身，不代替 App 编译。访问审计输出 `/tmp/yubai-smooth-access.{json,tsv}`，`git diff --check` 通过。

Apple SDK 类型检查、Xcode／XCTest UI、真机帧耗与逐像素比对尚未运行。尤其应验证浅／深色及增强对比、不同 displayScale、短卡片／长日卡片九宫格阴影边缘、竹影动画、现金图选中点／竖线和极值处裁切；Linux 解析不能证明这些原生渲染结果。没有声称获得新的帧耗或逐像素验收证据。外部画布、截图与分发资源未同步。新增／改动产品可见中文字符串：无；辅助功能标识与 uiTestAccessibilityValue 字符串保留。

原生 API 依据：[Apple shadow filter](https://developer.apple.com/documentation/swiftui/graphicscontext/filter/shadow%28color%3Aradius%3Ax%3Ay%3Ablendmode%3Aoptions%3A%29)、[ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer)。它们支持此次离屏生成方案，不能替代本项目的像素核对。
