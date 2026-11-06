# 第四十轮 · 记一笔收口与细节打磨

2026-11-06；owner 已批准本轮，工作分支 feat/round40-polish。改动仅留工作树，未建分支、未提交、未推送，未调用网络或真实模型。保留原 Batch A 的读屏播报、账本示例题与 token 整理，以及已合入的 sections 分类选择器。

下表「完成」指实现已接线；Apple SDK 编译、UI 测试执行及原生视觉验收仍待 Mac／设备，语法解析不等于类型检查。

| 项 | 状态 | 文件与实现位置 |
|---|---|---|
| 1 | 完成 | Core `EntryHistory.swift:EntryHistory.suggestion`；App `QuickEntryView:effectiveCategory/save`、`EntryEditForm`、`EntryCategoryChips`。同用途最后一笔优先，否则同方向、跨午夜 ±2h 的主类频次；无历史保持没分类。`ChangeSet.addedEntry` 尊重显式选择，防止旧关键词分类器补分类／小项。 |
| 2 | 完成 | Core `EntryHistory.recentPurposes`；`EntryFormFields`、`RecentPurposeChips` 回填最近同用途记录的主项、小项、账户。按次数／(1 + 距今的天数／30) 排序，时间相同稳定排序；过滤删除、未来和仅分类名的用途。 |
| 3 | 完成 | `EntryFormComponents.swift:EntryCategoryChips` 继续使用 `CategoryPicker(style: .sections)`；纸面、固定头部、收支选择、主类及小项路径保留。切方向后选中分类才回填表单方向。退款／已关联账单等受约束入口保持原方向。 |
| 4 | 完成 | `AmountKeypadKey.pressChanged`、`AmountKeypadFeedback`、`EntryAmountCursor`：点删一位，0.4s 后每 150ms 开始、每次加快 15ms、最快 45ms；到空停止，最后一次轻触感。离开、取消按下或视图消失即取消。数字及主键保留按下触感，运算符沿用中等／无效输入沿用 rigid；光标 500ms 翻转，Reduce Motion 常亮。 |
| 5 | 完成 | `AmountKeypad` 的 46pt 次键与 `QuickEntryView.receipt/save`：按下 success、原地回执、4s 消退。会话 N 随保存／撤销更新；撤销只移除最后一次保存的记录及其新建且无其他引用的重复计划，不恢复整本旧快照。 |
| 6 | 完成 | `EntryDiscardGuard`、`DismissAttempt`；记一笔、`EntryEditForm`（含 Ask）、`FixedFlowEditor`、这期金额编辑、`AccountEditor`。空表直接关闭，变更后拦截取消及下滑；使用系统 `confirmationDialog`，UIKit delegate 转发保留 SwiftUI 的 dismiss 回调。 |
| 7 | 完成 | `QuickEntryView` 的 `afterEntryAvailable`，负数用 amberInk。 |
| 8 | 完成 | `EntryDateRow`／`EntryDateChip`：今天、昨天、44pt 日历；改一笔及 Ask 草稿有时刻。Core `ManualBookkeeping.saveDate/change` 用保存当刻的时分秒；账单结清原本的历史中午口径保持。 |
| 9 | 完成 | `EntryForm` 统一固定头部和滚动容器，`EditableAmountDisplay`、`EntryFormFields`、`AmountKeypad` 共用。`QuickEntryView`、`EntryEditForm`、`FixedFlowEditor` 与 `AskDraftEditor` 均复用；Ask 直接调用编辑表单，主键为放回。账单的日程／期数是同一字段卡的插槽。 |
| 10 | 完成 | Core `EntryTimeline.snapshot/months`：搜索时跨全部月份，投影 month/day 的合计、笔数及行值；`EntriesView` 显示全部月份 N 笔、净合计与月分组。保留原有支出、退款和个人房租口径。 |
| 11 | 完成，原生外观适配 | `EntriesView` 改为原生 List sections；`LedgerEntryRow` 用 `swipeActions(allowsFullSwipe: true)` 与 `contextMenu`。自定义 pan／offset／resting 全部移除，不新增手势逐帧写入；门槛触感与回弹由系统提供，滑动删除跳过应用触感，菜单／辅助功能／详情／编辑删除保留 medium impact，保留删除撤销。复记用 `QuickEntryPrefill(entry:)`，日期为现在。 |
| 12 | 完成 | `EntriesView.monthPicker` 年月 wheel、本月胶囊；Core `EntryTimeline.Day.income` 与 `dayTotal` 收支并列。 |
| 13 | 完成 | `FixedFlowCheck` 长按系统菜单：付了金额、改金额再记、跳过这期；替代原隐藏长按手势。 |
| 14 | 完成 | `FixedFlowEditor`：共几期减加连续按钮，nil 对应 0／一直，最大沿 Core 2400；取消／改账单／保存；底部停掉用 `DestructiveButtonStyle`。 |
| 15 | 完成 | `UpcomingPaymentsView` 使用 `NativeCardRows` 原生 List，行内结束按钮移除；系统左滑停掉，复用原结束安排与确认／撤销语义。账单行也转为原生 List swipe。 |
| 16 | 完成 | `DestructiveButtonStyle`：52pt 起、满宽胶囊、card、amberInk、16/500；编辑账目、详情、账单、记忆、小项、映射、密钥、旧截图等采用。最近删除的全部清掉按本轮专稿保留。 |
| 17 | 完成 | `ManualSheetHeader` 扩展后由 `EntryForm`／`manualSheetHeader` 共用；账户、两种分类选择／新增、自定时间、导入、问答、存储等 App sheet 统一。只读关闭、编辑取消；纯推入页的系统返回保持。系统文件／照片选择器继续使用系统界面。 |
| 18 | 完成／既有保留 | `AppStore.resultToast/update/apply` 移除 reason + 完成，按真实变化取对象；固定账单回执也统一结果在前。`Toast` 的 1pt separator 描边及 Batch A 播报原已具备，保留。 |
| 19 | 完成 | `InlineFieldError`：13pt amberInk、16pt 左缩进。账户重名、金额／额度、账单、分类名字／小项、目标、消费观次数／金额、记忆、欢迎余额、模型等输入错误就地显示并禁用保存。真实失败保留全局 alert；权限可去设置、加载失败可恢复账本，问答／导入既有重试保留。 |
| 20 | 完成，待设备确认挂载 | `View.numericInput`／`NumberKeyboardAccessory`：使用原生 UIToolbar 的完成，brandInk／medium。避免再绑定一个 FocusState，覆盖账户、目标、欢迎页、消费观等系统数字键盘；不干扰自定义金额托盘。 |
| 21 | 完成 | `EmptyState` 统一纸卡、44pt paperInset 图标、15pt 事实和一个动作；账目、下一笔、待付款、账单、账户、发送记录、导入、记忆、来信、证据、版本等空列表替换。已有首页账户空态的专用纸布占位保持。 |
| 22 | 完成 | 可见用词改为会回来的账单、改一笔、账户、删掉、停掉；类型、标识符、存档键及历史资料不重命名。 |
| 23 | 完成 | `YubaiColor.toggleOn` 与品牌绿相同；全部 Toggle 逐一显式 tint(toggleOn)，包括原来直接 tint(brand) 的云端智能。 |
| 24 | 完成 | Core `RecentlyDeleted.entries/restore/purge/cutoff`；`BackupView` 入口、`RecentlyDeletedView` 今天／更早分组、原记日期／删除时间、剩余天数、放回及清空确认。启动／回到前台自动清过期，清空／过期清理移除旧撤销快照。 |
| 25 | 完成 | `InsightsView.donut` 隐藏金额仍绘形状，值为四点；收支 Menu 在环心，移除重复分段，读屏值也尊重隐藏。 |
| 26 | 完成，待设备验证冷／热启动 | `FloatingTabBar.contextMenu`；`AppStore.lastRecordedEntry` 是按 recordedAt 更新且变更守卫的镜像，避免后台标签栏反复扫历史；`HomeActionDelegate/HomeActionSceneDelegate` 通过 `requestCaptureSheet` 路由。`Info.plist` 加 UIApplicationShortcutItems 三项；无 entitlement 变化。 |
| 27 | 完成 | `AskConversationState` 由 AppStore 持有当天消息与 session；关闭重开恢复，清空按钮有对话才出现；跨日过期，换账本隔离。锁屏停止任务而不清掉当天内存对话。 |
| 28 | 完成（iOS） | `RootView.scrollTo/tabNavigation`：根页再点当前标签，用 `RootTabScroll` 及 ScrollPosition 回顶部；保留清 NavigationPath 的分支。浮栏在推入页、sheet 及日期选择器中隐藏，移除推入页额外底部留白；横向四栈 pager 保留，推入页仍禁横翻。Mac 保持原侧栏导航。 |
| 29 | 完成，只核对未修改 | `DesignSystem.swift:NavigationBackPaper`，完整行为见下文。 |
| 30 | 完成 | iOS `rootPageHeader` 移除内容 mask；`rootScrollContentMargins` 加 top soft、保留 clipped 和 bottom hidden。macOS 保留原遮罩及原边缘路径。 |

## 看板与规则的取舍

- 便签曾将数字键盘工具条、破坏性按钮、统一头部留到下一轮；以本次明确的合并工作清单为准一起实施。
- Bills Edit／Ask Draft 的主胶囊是 brand 底、onBrand 字，与通则的全 card 底不同。共用组件用 primary 参数表达，看板优先；记一笔的导入仍用 card。记账标题按专稿 17/600，其余按通则 15/500。
- Bills Edit 稿里的停掉以后的、Patterns 里的删掉这笔，以本次明确词表统一为停掉／删掉。金额按工程要求固定两位，取代稿中输入区的 0、38.5 等简写。
- 最近用途按工程要求完整换行，不沿稿子的压缩省略号；用途空值按已批准的第 33／40 轮稿保留 labelSecondary「可不填」，账单名字不加。大字号的头部、日期、字段和行值允许换行／上下排。
- 为实现系统 full swipe，账目卡组转成 List sections，圆角分组、动作宽度、弹性和门槛由系统负责；纸面色与内容层级保留。账目分组不再手工画外投影；其余 PaperCardSurface／PaperShadowCache 的缓存九宫格阴影保持。此处不是自绘滑动的像素复刻。
- 放弃确认使用系统 confirmationDialog；尽管声明 amberInk，系统 destructive 角色可能仍显示系统破坏性色。未用自制底部面板伪装系统行为。
- 第 28 项遵守已批准组件规则：iOS 推入页及 sheet 隐藏浮栏，重选回顶在根页可达；清栈分支保留。Mac 侧栏保持原导航行为。
- `v40pn` 提到最近删除尚待确认，本次任务已明确要求，按已授权实施。

## NavigationBackPaper 的实际行为

本轮该 representable 逐字节保持：

1. 挂一个透明、不可交互、对辅助功能隐藏的 UIViewController。
2. 在 SwiftUI 更新、viewWillAppear、viewDidAppear 时取 UINavigationBar 的前一个 item，而不是重建当前导航栈。
3. 复用 previous.backBarButtonItem；没有时，用前一个 item 的标题创建 native plain back item，target／action 为 nil。
4. iOS 26 设置 hidesSharedBackground，去掉系统共享底。
5. 按明暗模式解析 raised 与 control shadow，离屏绘制 60×48 图片；内部 x6/y4 的 48×36、18 圆角暖纸胶囊及其阴影。
6. 图片以 top22/left24/bottom22/right24 九宫格拉伸，alignment inset 为 top4/left6/bottom8/right6，alwaysOriginal。
7. 给 normal 和 compact 两种 barMetrics 设置 backButtonBackgroundImage，写回前一个 item。保留系统的箭头、前页标题、返回操作、边缘返回手势和历史菜单；推入 sheet 的页面也会被处理。

## 新文件与工程成员

- `Sources/YubaiCore/EntryHistory.swift`：pbxproj 已登记文件；由现有本地 Swift Package 的 YubaiCore target 自动编译。App／Widget／Tests 通过既有 package product 使用 Core，不把同一 Core 文件重复加入 App sources。
- `Tests/YubaiCoreTests/Round40Tests.swift`：pbxproj 登记于 YubaiCoreTests group 和 sources build phase；SPM 测试自动发现。
- 没有新增 App-only 或 Widget Swift 文件，没有新包或 entitlement。仅 App 的 Info.plist 新增桌面三项快捷操作。

## 验证

- 复核修正后按指定 PATH 重跑，Swift 6.2.4：`swift build --target YubaiCore` 通过。
- 完整 `swift test`：908 项，904 通过、4 项原有实网 opt-in 跳过、0 失败，117.559 秒；禁用真实模型评测。新增 14 项本轮测试，旧月内搜索／手动关键词小项测试已按新行为更新，未删除 Core 测试。复核重跑日志：`/tmp/round40-followup-build-test.log`。
- 定向两组分别 98 项和 28 项通过；最终全量结果取上面的 908 项，不重复计数。
- 最终语法解析：iOS 26 设备、iOS 26 模拟器 DEBUG、macOS 14 三组，均覆盖 43 个 App＋1 个 Widget＋1 个 UI 测试文件，共 135 个文件／配置，全部通过。pbxproj 285 个对象标识唯一，43 个 App 文件均在 App sources；新测试恰好加入测试 sources 一次。Widget sources 保持原来的 YubaiWidgets.swift、CaptureWidgetSupport.swift、CaptureControlIntent.swift，未引入新的 App-only 文件。Info.plist 校验通过。parse 不代表 Apple SDK 类型检查。
- 126 项 UI 测试源码中，改写了自定义 pan 内部状态断言，新增放弃确认、跨月搜索、最近删除恢复、原生短滑／全滑／菜单、当天对话保留、推入页浮栏隐藏与根页标签重选回顶等覆盖。最近删除测试返回根页后再切标签。XCTest UI 在本环境未执行。
- 复核修正后的 App／Widget／UI 三组条件语法解析重跑 135／135 通过，记录：`/tmp/round40-followup-parse.json`；`git diff --check` 通过。Apple SDK／UI 实跑及触感仍待 Mac／设备。

## 设备验收重点

- 原生 List 的短滑、全滑阈值触感、滑动删除无重复触感及菜单／详情／编辑删除的单次中等触感、纸卡组圆角／无外投影、动作文字是否尊重 amberInk，以及与横向根 pager 的手势归属。
- NativeCardRows 嵌入卡片后的自适应高度、长名字／大字号／VoiceOver 按钮可达性，尤其账单付了菜单和待付款的停掉。
- 五类表单及这期金额的取消／下滑：无改动直关，有改动出现确认；继续记不丢输入；嵌套导航返回后 SwiftUI sheet binding 仍正确。
- 删除键按住加速、移出／松手／关闭即停止、到空触感，连续记账即时 success 是否只一次，4 秒回执及只撤销最后一笔。
- UIKit 数字键盘 accessory 在各个 SwiftUI TextField 的实际层级中挂载，完成能收键盘、不抢原 FocusState；大字号与横屏工具条。
- 静态桌面 Quick Actions 的冷启动、前台／后台、已锁定与未完成欢迎页路径；截图权限拒绝／有限照片访问；菜单复记采用最后记下时间而非账目日期。
- 隐藏金额的环形尺寸及读屏值；深色品牌绿、Reduce Motion 常亮光标、Reduce Transparency；系统确认的破坏性色。
- 根页标签重选回顶，其他标签栈保持；推入页及 sheet 隐藏浮栏、推入页无额外底部留白，系统边缘返回后浮栏恢复。
- NavigationBackPaper 在明暗、短／长前页标题、compact、sheet 内推入、交互返回取消以及返回历史菜单中的实际效果。

## 本次新增／改动的可见中文

以下列出可见模板，变量以尖括号表示，金额均格式化两位。重复出现在多处的同一词只列一次；辅助功能专用提示、标识符和合成 UI 夹具文字不计为产品可见文案。

- 标题／词表：会回来的账单、像是会回来的账单、这个月还没有会回来的账单、账户、改一笔、改这笔、改账单、添加账单、月份、分类、旧截图、最近删除。
- 控件：删掉、停掉、放回、放回去、全部清掉、放弃这笔、继续记、本月、清空、清空搜索、添加账单、导入账单、截图记一笔、再记一笔一样的、再记一笔「<用途> <金额>」、查看全部、查看全部支出、返回、问余白、去设置、恢复账本、合并、加上、关闭、好、保存、完成、多久以前。记下，再记一笔原文保留，改为带加号的托盘次键。
- 数字／事实：已记 <N> 笔；全部月份 · <N> 笔；支出 <X> · 收入 <Y>；最近删除 <N> 笔；今天；昨天；更早；没分类；删于 <时间> · 原记 <日期>；<N> 天后清掉；<N> 期；一直；已经填了 <金额> 元。
- 操作状态：已删掉 · <用途> <金额>、已删掉 · <N> 张截图、已删掉 · <对象>、已加好 · <账户／对象>、已停掉 · <账单>、已放回 · <用途>、已恢复 · <账单>、已记下 · <账单> <金额>、已改好 · <对象／操作>、已清掉最近删除、已删掉、密钥已删掉。原来由原因拼接完成的回执不再使用。
- 空状态事实：这个月还没有账目、还没有这类账目、没有找到这笔、还没有待付款、还没有账户、还没有收支记录、还没有发送记录、没有没成功的记录、还没有导入记录、还没有记下的事、还没有每周来信、还没有映射、没有匹配的支出、没有待选择的版本、记录已移除、最近删除里没有账目。去掉原句号，统一有下一步按钮。
- 行内错误状态：填写账户名称、已有同名账户、填写有效金额、填写账单名字、金额须大于 0.00 元、用途最多 4,000 字、填写名称、填写名字、分类名称无效、已有同名分类、想存金额须大于 0.00 元、已存金额不能超过想存金额、每周次数须为 0 至 10,000 的整数、记忆须在一行内，最多 200 字、模型名字须在一行内，最多 200 字。这笔已清掉为 Core 恢复过期项时的错误原因。已有 Core 分类校验原因现在在字段下显示，不另写解释句。
- 确认后果：全部清掉后无法放回。属于 AGENTS 明确允许的不可撤销操作确认例外。
- 占位：可不填，仅空用途字段使用 labelSecondary，账单名字不使用。owner 本次复核明确要求恢复第 33／40 轮已批准稿，作为四类之外的明确例外；不新增说明行。
- 删除／替代：删除这笔、删除记录、停掉以后的、结束这个安排、我的账户、编辑这一笔及固定收付的旧展示词被上述词表替代；一行灰色空状态及其句号删除。

除不可撤销确认后果及 owner 明确指定的「可不填」占位外，全部是标题、数字与事实、控件或状态；没有新增说明句、邀请、口号或步骤。
