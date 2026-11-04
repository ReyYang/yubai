# 15ab722 跨文件访问控制排查

2026-11-04，worktree `/home/user/yubai-xfix2`，分支 `fix/xcode-build-15ab722`，基线 `15ab722`。按 owner 的 Xcode 27.1／iPhoneOS 27.1 SDK 报错修复。本机为 Linux Swift 6.2.4，无 Apple SDK；静态排查和条件语法解析不代表完成 Xcode 构建或 UI 执行。

## 代码修改

| 文件:行 | 修改与原因 |
|---|---|
| `Sources/YubaiApp/YubaiApp.swift:333` | 增加默认 internal 的 `clearUndo()`，在声明文件内同时清空 `undoLedger`／`undoLabel`。保留 `undoLedger` 的 private，避免把完整账本快照的读写权限扩给整个 App 模块。其他撤销流程不变。 |
| `Sources/YubaiApp/IntelligenceRuntime.swift:498` | `undoUnsorted` 成功保存后调用 `clearUndo()`，替换两个直接赋值。原先跨文件 extension 无权访问 `private undoLedger`；失败／过期通知的 guard、恢复内容、toast 和 trigger 顺序保持。 |
| `Sources/YubaiApp/CloudAssistantViews.swift:602` | 将 `Text + Text + Text` 换为一个 `Text` 字符串插值。保留 reduce 顺序、首项无分隔符、后续「、」以及 `scalar()` 返回的数字／布尔字体和颜色、null／字符串颜色；外层修饰器不变。 |

生产源码合计 3 文件、6 行增加／2 行删除；没有改访问级别、工程、测试断言、依赖、布局或业务规则。新增／改动的可见中文字符串：**无**。

## 扫描范围、复跑和边界

新增 `scripts/audit-swift-access.py`，仅用 Python 标准库，读取 App／UI 的 Swift 源码（或指定 Git revision），不读取配置或密钥。扫描 41 个 App 文件和 1 个 UI 测试文件，审计声明限定在 App 目录。

脚本跳过注释和字符串字面量，保留字符串插值中的 Swift 引用；覆盖所有条件编译分支，记录声明所属类型／extension。它枚举 private／fileprivate 属性、方法、类型、init、subscript、typealias，并包含属性的 `$name`／`_name` 投影和存储引用；`private(set)` 单列，两个 `private extension` 的默认私有成员补录。extension 的目标类型自身不会被误判为私有类型。

```sh
python3 scripts/audit-swift-access.py --revision 15ab722 \
  --output /tmp/yubai-15ab-access-before.json \
  --summary /tmp/yubai-15ab-candidates-before.tsv
python3 scripts/audit-swift-access.py \
  --output /tmp/yubai-15ab-access-after.json \
  --summary /tmp/yubai-15ab-candidates-after.tsv
```

覆盖 **1,194 处显式访问修饰声明＋2 个私有扩展的隐含成员＝1,196 条记录**（包括两个 extension 容器）。其中 var 783、let 13、func 300、struct 89、enum 9、extension 2；`private(set)` 5。当前源码没有显式 private／fileprivate init、subscript、typealias、class、actor 或 protocol 声明，仍按相同词法规则检查，并以合成 private init 样例验证提取。

原始名称匹配产生 **601 个声明候选／126,676 次跨文件同名命中**；修后为 **600／126,675**。数量包含常见的 `store`、`title`、`value`、`save` 等其他类型成员、形参标签、局部变量和 SDK API，不是编译错误数量。[完整 601 项疑点与归类](XCODE-15AB-ACCESS-CANDIDATES.tsv)列出基线声明位置、名称、命中数、示例引用位置与结论；JSON 包含每条原始命中的文件／行／所属类型。

该工具是保守的词法候选生成器，不做 Swift 类型求解、重载绑定或完整数据流分析；同一类型的跨文件访问可直接定位，其他接收者须结合源码复核。没有把原始同名匹配全当作错误，也没有以扫描零命中替代 Apple SDK 类型检查。脚本的注释／字符串／插值、private init、private(set)、隐含扩展成员合成样例检查通过，全部显式 private／fileprivate token 均对应了记录。

## 疑点结论

| 疑点 | 结论 |
|---|---|
| `AppStore.undoLedger`：`YubaiApp.swift:222` → `IntelligenceRuntime.swift:498` | **唯一确认的跨文件私有访问错误，已修复。** 基线同一类型 extension 命中 1 项，修后为 0。 |
| `YubaiColor.adaptive`：`DesignSystem.swift:47`（fileprivate） | 同文件由颜色 token／阴影 token 使用，合法；外部 5 次命中是 `GridItem(.adaptive(...))`，与 YubaiColor 无关。 |
| `CloudAIStatus.configured`／`unavailableModel`（private(set)） | 外部只读取这两个成员，更新由同文件的 `refresh`／`succeeded`／`failed` 完成；其他页面的 `configured =` 是各自的 @State。 |
| `AppStore.ledger`／`ledgerRevision`／`navigationRevision`（private(set)） | `ledgerRevision` 外部只读，`navigationRevision` 无文件外同名命中。其他文件中 `ledger` 的写入均为回调的 inout 参数、局部账本／元组字段；AppStore 替换账本经 `update`、`adoptSyncedLedger`、`publishOrganizationCheckpoint` 等声明文件内的方法。未发现越权 setter。 |
| `private extension View.manualFormChip`：`FixedFlowsView.swift:618` | 隐含私有，所有使用均在同文件；无文件外名称命中。 |
| `private extension PendingImportOrganization.sessionCardKey`：`NowActionCards.swift:110` | 隐含私有，所有使用均在同文件；无文件外名称命中。 |
| 89 个 private struct／9 个 private enum | 类型名无文件外引用；其同名成员候选由其他类型／局部符号产生。未发现私有类型或显式私有初始化器被跨文件构造。 |
| 其他同名属性／方法候选 | 按所属类型、调用接收者和声明复核，未发现第二处确定的跨文件私有访问；完整名称列表保留在上链 TSV，原始引用保留在 JSON。仍需 Mac 的完整类型检查覆盖推导接收者和 SDK 重载。 |

## fb0e4f3..15ab722 的符号核对

审读该区间 11 个 App 文件和 1 个 UI 文件的新增／改动调用及相关声明；6 个改动的 Core 测试文件由全量 swift test 实际编译执行。

| 文件 | 核对的符号与结果 |
|---|---|
| `ButlerViews.swift` | `CardDismissAnimation`／`SwipeDismissCard` 为 internal，供 NowActionCards／WishlistView 使用；`SwipeRevealValue` 保留 private 且仅本文件使用。AppStore 三个卡片动作的 Bool 返回值与闭包一致。 |
| `CashTimelineCard.swift` | `CashTimelineWindow`、cycle／previous／endpoint／difference／annotations、`CashTimelineScale` 与实际 Core public 声明一致；`HorizontalPan` 的共享声明为 internal。私有绘图助手没有跨文件调用。 |
| `Editors.swift` | 关闭已确认校准卡的 `cards`／`action`／`dismissedAt` 与 Core public 模型一致。 |
| `FixedFlowsView.swift` | `FixedFlowEditor(planID:)` 为可从 YubaiApp 使用的 internal 构造；`FixedFlows.edit/categories/update/unsettled/stop` 及 `FixedFlowEdit` 字段为 public。私有确认框和 manualFormChip 仅本文件使用。 |
| `IntelligenceRuntime.swift` | 批量／单组 apply、undo、卡片及心愿动作存在，参数标签与调用方一致；`showUnsortedUndo` 仅本文件调用。修复唯一的 undoLedger 越权。 |
| `NowActionCards.swift` | `SwipeDismissCard`／`ButlerCardView(nudgesOnce:)` 可访问；`NowCardPage`、SalaryCard、PendingImportsCard 及 sessionCardKey 未跨文件泄露。移除的翻页构造参数无残留调用。 |
| `OverviewView.swift` | `FixedFlowCheck` 的编辑入口与 `.editPlan` 均存在且为 internal；移除的今天行无生产调用残留。 |
| `UITestSupport.swift` | 新夹具调用的 Account／Entry／ButlerCard／Plan 及公开字段存在；测试夹具继续受 Debug 模拟器条件保护。 |
| `UnsortedViews.swift` | `UnsortedQuickSession`／`UnsortedGroupsUndo` 的 public init／方法、UnsortedGroups 的数组重载与 Core 一致；两个跨文件通知类型、UnsortedUndoBar／UnsortedQuickSortView 是 internal；私有 route／sheet／controls 无文件外引用。 |
| `WishlistView.swift` | `CardDismissAnimation`／`SwipeDismissCard` 以及 AppStore 的回答／关闭方法存在且可访问；闭包返回 Bool 一致。 |
| `YubaiApp.swift` | `.quickSortUnsorted`／`.editPlan` 在路由枚举与两个分派 switch 接入，目标 View／通知／批量 changeSet 方法可访问。新增 clearUndo 供本模块 extension 调用。 |
| `Tests/YubaiUITests/AppFlowTests.swift` | 交互测试仅 import XCTest，通过 XCUI 查询、accessibilityIdentifier 和显示事实断言操作 App；没有 import／@testable import App 或直接访问 AppStore／View／业务模型。新增 quickSort、unsorted、fixedFlow、butler、cashTimeline ID 已对照实际源码，含动态前缀拼接。todayEntries／todayEntrySummary 等已移除 ID 的剩余改动断言是 XCTAssertFalse，不是正向查找。 |

**测试 bundle 的特殊同名命中**：文件末尾既有 `MotionStateTests` 引用了 `MotionSessionState`／`MotionEntryChange`。它们不是跨模块访问 App 的内部类型：工程 `project.pbxproj:154–156` 把 `MotionState.swift` 直接编入 UI 测试 Sources phase，生成器 `scripts/generate-project.py:72–78` 保留相同登记，所以测试 bundle 有自己的定义。该段早于 fb0e4f3，本区间没有改动；没有为修复放宽可见性或添加 App import。实际 MotionState.swift 配该段 XCTest 在 Linux 单独类型检查通过。交互测试类 AppFlowTests 不引用这两个类型。

额外使用独立模块的普通 `import YubaiCore`（**没有 @testable**），对上述整理／撤销／固定收付／现金图／卡片／心愿 Core 调用及返回字段做严格 Swift 6 类型检查，退出 0：`/tmp/yubai-15ab-public-api.swift`、`.log`。因此相关 Core 公共接口的可访问性不只依靠 @testable 单测推定。此检查不覆盖 SwiftUI／Charts／XCUI 的 Apple SDK 类型。

## 验证结果

- 指定命令 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出 **0**：**788 项，784 通过／4 项原有实网 opt-in 跳过／0 失败，112.438 秒**。日志 `/tmp/yubai-15ab-swift-test.log`。4 项在取配置前检查开关，没有读取密钥或请求真实 DeepSeek。
- 新 worktree 的依赖缓存为空，运行前仅向 ignored `.build` 复制 `/home/user/yubai-integ/.build` 的 checkouts／repositories／workspace-state。两个 Package.resolved 的 JSON 完全一致：swift-crypto 3.15.1、swift-asn1 1.7.3；未新增依赖，未改 Package.swift／Package.resolved。
- 41 个 App 文件逐个 `swiftc -parse -swift-version 5`：arm64 iOS 27.1 模拟器 Debug（iCloud／App Group）、x86_64 iOS 27.1 模拟器 Debug、arm64 iOS 27.1 设备 Release（iCloud／App Group）、arm64 macOS 14 Debug（iCloud）／Release。UI 文件覆盖两个模拟器配置。共 **207 次，0 失败、0 诊断**；完整命令和状态在 `/tmp/yubai-15ab-parse.json`。
- 从真实源文件提取 `undoLedger`／`undoLabel` 声明、`clearUndo`、`undoUnsorted` 及通知类型，保留两个文件边界、导入真实 Core 类型，用最小平台外壳做 `-typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors`：原始 undoUnsorted 复现 **undoLedger private protection level**，修后通过。证据 `/tmp/yubai-15ab-access-repro/before.log`／`after.log`。平台外壳有替身，不代表整个 @Observable AppStore 已通过 Apple SDK 类型检查。
- `git diff --check` 通过；未提交、未推送、未添加依赖、未读密钥、未调用真实 DeepSeek。界面外观和可见文案保持，外部设计／分发资源未同步。

**仍待 Mac**：Xcode 27.1＋iPhoneOS 27.1 SDK 的完整 App／UI 类型检查与构建、弃用警告确认、XCTest UI 实跑。此次没有把 Linux parse 作为这些检查已经通过的证据。
