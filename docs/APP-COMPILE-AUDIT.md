# App 编译陷阱排查（2026-10-23）

分支 `feat/butler-saving-core`，范围按 `git diff main --name-only -- Sources/YubaiApp` 确定：37 个 Swift 文件及 5 个资源文件。来源为 owner 在 iPhoneSimulator 27.1 SDK 下报告的 `SubcategoryViews.swift:59` 类型推断错误。本轮没有提交、联网调用 API 或修改 Core；唯一 App 源码变化是下面的 toolbar 包装及 owner 指定的左右位置。

## 修复

`SubcategoryViews.swift:58` 将裸 `CloseButton()` 改为：

```swift
ToolbarItem(placement: .cancellationAction) { CloseButton() }
```

同一块中已有 `ToolbarItem(placement: .confirmationAction)`。裸 View 与 ToolbarContent 混用会让 `.toolbar` 的重载／result builder 推断失败。现在两个子项均为 ToolbarItem，「完成」在左，「换主项」仍在右，按钮动作、文案、内容与保存逻辑保持。

## 全分支核对

全部 37 个 Swift 文件都检查了 toolbar 内容种类、同名类型、builder 返回路径、ForEach 身份、Binding／可选性、Core 访问级别及签名、私有声明作用域和 iOS 26 API 使用。下表列出各文件的主要核对点；除上述 toolbar 外，未发现可据本地源码确认的新增编译问题。

| 文件（均在 `Sources/YubaiApp/`） | 主要核对点 |
| --- | --- |
| AskYubaiView.swift | 回复分支的 @ViewBuilder、消息身份、草稿 Binding、Memory.apply、共享输入条泛型 |
| ButlerViews.swift | 卡片／来信 ForEach、CardAction／CardKind 分支、Core 反馈和消费观 API、ChartContent |
| CaptureControlIntent.swift | AppIntent 返回协议、AppStore 跨文件方法、iOS 条件分支 |
| CaptureNotifications.swift | Entry 参数、通知回调中的 Core 撤销 API 与 AppStore 方法 |
| CaptureWidgetSupport.swift | QuickCaptureSnapshot 构造器、可选共享容器、URL 参数 |
| CloudAssistantViews.swift | 仅含 View 的 toolbar、模型／日志行身份、SendLogPresentation public API、sheet 状态 |
| DesignSystem.swift | ViewModifier.body 的继承 builder、单表达式平台分支、CardRows 元素约束、手势协议、iOS 26 修饰符与 macOS 回退 |
| Editors.swift | 统一 ToolbarItem、Account 构造器、Picker tag／Binding、表单辅助视图返回 |
| EntriesView.swift | EntryDay／Entry 身份、展开 ID 的 Binding、平台条件与手势闭包 |
| EntryDetailView.swift | 查找可选 Entry、分类／来源辅助视图、记录字段的 public 访问 |
| EntryEditView.swift | State 初始化、可选账户 Binding、枚举选择值、ManualBookkeeping.edit |
| EntryFormComponents.swift | Layout 协议签名、UUID? 账户选择、DatePicker Binding、ForEach 的显式 id |
| FixedFlowsView.swift | FixedFlowOccurrence 身份、月份／日历返回、结清与安排 API、可选期数／账户、平台分支 |
| ImportReviewSupport.swift | 公开的跨文件辅助类型与方法、日期／导入类型 |
| ImportView.swift | ToolbarItem 配对、ImportDayGroup 身份、账户可选 tag、三组 BillImporter.preview 重载、公开扩展与枚举标签 |
| InsightsView.swift | categoryDestination／donutSlice 的 @ViewBuilder、扇区 id、Core 汇总、日期 sheet Binding |
| IntelligenceRuntime.swift | transport 协议、Core 异步方法／标签、关联枚举、AppStore 扩展私有方法的文件内使用 |
| LedgerSync.swift | Core 同步公开 API、冲突枚举标签、可选云端目录、iCloud 条件分支 |
| MemoryView.swift | MemoryKind／MemoryNote 身份、Memory 的公开方法、仅含 View 的 toolbar、编辑状态 |
| MotionState.swift | 跨文件调用的 claim／hasAppeared 等方法可见性、平台导入 |
| OverviewView.swift | 多语句辅助函数的显式 return、到期记录身份、可选账单及金额 |
| ProfileConversationView.swift | 仅含 View 的 toolbar、消息显式 id、共享输入条、ProfileColdStart.next 的模式／上下文参数 |
| ProfileView.swift | 消费观／领域身份、areaUsage 等 builder、编辑 Binding、可选 softLimit、Core 类型和签名 |
| QuickCaptureIntents.swift | AppIntent／SnippetIntent／AppShortcutsProvider 声明、结果协议、Entry 身份、QuickCapture API |
| QuickCaptureSettingsView.swift | 映射 sheet 的 Identifiable 包装、UUID? tag／Binding、ToolbarItem 配对、字典可选值 |
| QuickCaptureSupport.swift | 深链可选值、QuickEntryPrefill 参数、泛型 captureUpdate、截图草稿 id、QuickCapture.record |
| QuickEntryView.swift | 可选账户／关联账单 Binding、预填枚举构造、Core change／available／suggestions 签名 |
| SavingPurchaseViews.swift | 多视图问题块的 @ViewBuilder、选项 id、JSONValue 可选链、购买与心愿 API |
| SavingViews.swift | WishItem／SubscriptionCandidate 身份、关联枚举匹配、订阅分支 builder、可选日期、Savings／RestrainProgress API |
| SettingsView.swift | 可选值与金额表达式、偏好 Binding、备份导入／导出签名、恢复 sheet 状态 |
| StorageView.swift | 数组索引 id、可选统计值、存储 API、StorageSheet 的 builder 初始化、presentation 修饰符 |
| SubcategoryViews.swift | 修复混合 toolbar；Category 限定名、网格 id、辅助函数 return、setCategory 标签与分类 API |
| SyncVersionsView.swift | LedgerVersion／Entry 身份、账本位置 Binding、Core 同步方法 |
| UITestSupport.swift | Debug＋模拟器分支、Core 模型公开构造器、脚本关联枚举／工具参数 |
| WeeklyPush.swift | UserNotifications 签名、跨文件 AppStore 扩展方法、偏好访问 |
| WishlistView.swift | WishItem 身份、wishActions 的 @ViewBuilder、可选冷静期／回访字段、Wishlist 公开 API |
| YubaiApp.swift | Destination／AppSheet 枚举与 builder 穷举、sheet Binding、跨文件 AppStore 接口、分页修饰符 |

核对方法包括本机工具链 SwiftParser／SwiftSyntax 遍历、Core 定义对照与人工检查。静态调用和构造器共核对 128 个不同的 Core 目标；`BillImporter.preview(...columnMapper:)` 位于 `public extension BillImporter`，成员自身省略 public 仍对 App 可见。ForEach 的无显式 id 情况均对应 Identifiable 元素，其余使用显式 id；没有为没有身份的 Core 类型假设自动生成 id。

类型名方面：所有 Category 引用已使用 `YubaiCore.Category`；Card 为当前 App 模块中定义的泛型 View，优先解析到本地声明；没有裸 Letter／Profile 类型。Entry／Account／Memory 的使用与 Core 定义一致，本次静态核对没有发现需要额外限定名的冲突。没有 Apple SDK，不能将此结论当作 27.1 SDK 导出符号的实际类型检查。

builder 方面：普通多语句 `some View` 辅助函数已有显式 return，多视图片段已有 @ViewBuilder；View.body 与 ViewModifier.body 使用协议继承的 builder。平台 `#if` 内的单表达式函数保持单表达式语义，没有为消除误报改变结构。跨文件同名私有辅助函数分别属于自己的类型；没有发现使用另一个文件私有声明的调用。

API 方面未发现要求 iOS 27 的修饰符；分页／滚动观察与原生手势接口属于 iOS 26 及以前，glassEffect 等 iOS 26 接口保留原 availability／平台分支。未新增或替换系统 API；实际 SDK availability 仍需 Xcode 构建确认。

## 验证

- 按指定命令 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test`，退出 0：449 项，445 通过、4 项原有实网 opt-in 跳过、0 失败；没有修改测试或增加跳过。
- 全部 38 个现有 App Swift 文件（包含 main 未改的 AskCapture.swift）逐文件通过 `swiftc -frontend -parse`：`arm64-apple-ios26.0-simulator`、`arm64-apple-ios27.1-simulator` 和 `arm64-apple-macosx14.0`。
- iOS 解析开启 `DEBUG`、`YUBAI_APP_GROUP`、`YUBAI_ICLOUD`，并用 `-module-can-import AppIntents` 让语法解析覆盖该条件分支；macOS 解析开启 `YUBAI_ICLOUD`。这些开关不提供 Apple 模块，也不执行类型检查。
- 5 个改动资源分别通过 JSON、plist／entitlements、SVG XML 解析；未修改资源内容。
- 当前环境为 Linux／Swift 6.2.4，没有 Xcode 或 Apple SDK；未执行 iPhoneSimulator 真编译、UI 测试或设备视觉验收。语法解析与 Linux Core 测试都不能代替 SwiftUI 类型检查。

## 后续预防

修改 toolbar 时先确定整个闭包使用 ViewBuilder 还是 ToolbarContentBuilder：出现 ToolbarItem／ToolbarItemGroup 后，把其他按钮／菜单也放入相应 ToolbarItem，保留设计指定 placement。普通辅助函数返回多段视图时标注 @ViewBuilder；计算后返回单个视图时写显式 return。新增模型引用核对模块名，ForEach 核对元素身份，Core 调用同时核对标签、可选性与访问级别。

检查范围继续从 `git diff main --name-only -- Sources/YubaiApp` 获取，不能只复核最后一轮页面或 Xcode 当前报错的文件。Apple 环境中须在项目的 iOS 26 最低部署版本下完成 Simulator 构建，并修完第一处错误后继续构建，直至类型检查结束；本记录的 parse 结果不作为该步骤的替代。
