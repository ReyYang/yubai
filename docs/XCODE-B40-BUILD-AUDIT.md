# b40bd4b Xcode 编译修复与 App 审读

2026-11-04，`fix/xcode-build-b40bd4b`，基线 `b40bd4b9d860e1242f7589c6cb2d9865b9762aa5`。依据 owner 的 Xcode 27.1／iOS 26 SDK 报错，在 Linux 修复并审读 `git diff fb0e4f3 HEAD`。本机 Swift 6.2.4，没有 Apple SDK；以下文档核对、Foundation 类型检查、条件语法解析均不代表 App／Widget／UI 已通过 Xcode 类型检查或运行。

## 实际修改

生产代码仅修改 `Sources/YubaiApp/CashTimelineCard.swift` 的 Canvas 标注函数：

| 当前行 | 修改与原因 |
|---|---|
| 212 | `CGSize(width: CGFloat.infinity, height: CGFloat.infinity)`，并标明测量结果为 `CGSize`。构造器有浮点重载，仅结果类型或参数的 `.infinity` 无法消除 `CGFloat`／`Double` 歧义。原式在 Linux Foundation 中也复现同一诊断，修后严格 Swift 6 类型检查通过。 |
| 210–211、223 | 标明 `Text` 和 `GraphicsContext.ResolvedText`；两处 `Text.foregroundColor` 改为 Apple 建议的 `Text.foregroundStyle`，消除已弃用调用。此处必须使用返回 `Text` 的重载，才能传给 `resolve(_ text: Text)`；颜色参数保持。弃用调用本身不是这次已复现的编译阻塞。 |
| 214–219 | 把原来嵌套的标注中心表达式拆为 `CGFloat` 半宽、半高、竖向偏移与中心坐标，缩短类型求解链。运算顺序、±12pt 偏移与边缘钳制保持；450 组数值对照完全一致。这是预防性拆分，没有声称原表达式已复现编译超时。 |

界面外观、布局参数、文案和业务规则均保持；本轮新增／改动的可见中文字符串：**无**。未修改 Core、测试断言、工程或依赖声明。

## 逐文件审读

输入清单为 owner 提供的 `b40-files.txt`，与 Git 实际改动交叉核对。目标目录合计 **12 文件、194 个 diff hunk**；以下逐段读完新增、删除及相邻调用点。`Sources/YubaiWidgets` 在该区间没有改动，仍纳入全目录解析。

| 文件（位于 Sources/YubaiApp，最后一行除外） | 核对内容与结论 |
|---|---|
| `ButlerViews.swift` | `CardDismissAnimation` 的两层逃逸闭包、ViewBuilder 存储闭包、CGFloat 拖动／阈值／旋转、`withAnimation` 完成回调、`.task`、几何变化、感官反馈、iOS representable／Mac SwiftUI 手势。完成回调是普通逃逸闭包，几何 transform 只读取参数，没有新增跨 actor 的发送。未见其他确定签名错误。 |
| `CashTimelineCard.swift` | 逐项检查 Charts 的 mark、series、symbol、坐标轴、scale、ChartProxy 坐标／Anchor、Canvas resolve／measure／draw、长按及横拖。修复上述歧义／弃用调用／长表达式；绘图仍返回 `some View`，没有把图表 mark 与 `ChartPlotContent` 混用。 |
| `Editors.swift` | 新增账户校准后卡片关闭循环使用 AppStore 同步更新闭包；UUID／枚举比较及可变账本操作与 Core 声明相符。 |
| `FixedFlowsView.swift` | 编辑入口、共用 ViewModifier、`@Binding` 确认框、可选 UUID、编辑状态、菜单／Picker、预览日期映射及 `try` 的传播。`FixedFlowEdit`、`FixedFlows.update`、`Plan` 和日期函数按实际声明核对；新增 ViewBuilder 条件返回一致。 |
| `IntelligenceRuntime.swift` | 批量／快速归类、撤销通知与返回 Bool 的卡片方法均处于 `@MainActor extension AppStore`；同步 update／apply 闭包没有新增 detached task 或 Sendable 边界。调用方与新返回类型、参数标签一致。 |
| `NowActionCards.swift` | 卡组 ForEach 的 Identifiable 数据、会话 key、SwipeDismissCard 泛型推导、CGFloat 边缘尺寸、AnyTransition。旧翻页参数与调用一并移除，未留旧构造调用。 |
| `OverviewView.swift` | 删除今天行及状态；到期行编辑入口、金额组件和 FixedFlowCheck 参数与声明一致，未引入平台专属 API。 |
| `UITestSupport.swift` | Debug 模拟器内合成账本，金额由 Core 初始化器约束为 Int64，日期偏移为 Int；新增夹具无 UIKit 引用。现有 UIApplication 使用仍位于 os(iOS) 内。 |
| `UnsortedViews.swift` | 选择集合、可选 sheet／navigation route、Hashable／Identifiable、`@State` 与 `$detailRoute` 绑定、撤销 `.task(id:)`、ForEach 数据及即时控件闭包。进度明确转换为 CGFloat，无 Int64／CGFloat 混算；各个 onChange 的输入均可 Equatable。 |
| `WishlistView.swift` | 可选动画闭包、逃逸保存动作、返回 Bool 的 store 方法及泛型卡片内容，调用参数一致。 |
| `YubaiApp.swift` | 路由／sheet 枚举新增分支在两个 switch 中均接入；新增通知和集合属性由 `@MainActor @Observable AppStore` 持有，无把 Observable 对象当 Binding 的用法。既有根页滚动回调的二参数 action 与签名相符。 |
| `Tests/YubaiUITests/AppFlowTests.swift` | 全部新增／修改测试及辅助方法，核对 XCUICoordinate 拖动、XCUIGestureVelocity、键盘删除值、XCUIElement 查询／属性、NSPredicate／XCTWaiter、Foundation 几何运算；未改测试断言。Apple XCTest 类型检查和实际 UI 执行仍待 Mac。 |

目标改动中的其他 `.infinity` 均是 `View.frame` 的 `CGFloat?` 命名参数，未发现相同构造重载歧义；没有新增 `.zero`、`.pi`、`contentTransition` 或 `onScrollGeometryChange` 调用。现有 iOS 手势 representable 挂载均为 `.gesture`，Mac 分支使用真正的 SwiftUI Gesture；金额到 Charts 的转换仍为 `Double(cents) / 100`，屏幕坐标为 CGFloat。

## Apple 文档核对

以下为本轮访问的 Apple 官方签名或合约及其对应调用：

- [AxisMarks 数组初始化器](https://developer.apple.com/documentation/charts/axismarks/init(preset:position:values:content:)-1n9x7)：`Value: Plottable`、`values: [Value]`，content 接收 `AxisValue` 并由 `AxisMarkBuilder` 构造；本图分别传 `[Double]` 与 `[Date]`。`AxisMarks<Content>` 的 `Content: AxisMark`，自定义 AxisValueLabel 内部使用 View 内容。
- [ChartProxy](https://developer.apple.com/documentation/charts/chartproxy)、[plotFrame](https://developer.apple.com/documentation/charts/chartproxy/plotframe)、[value(atX:as:)](https://developer.apple.com/documentation/charts/chartproxy/value(atx:as:))：position 返回 `CGFloat?`；plotFrame 是 `Anchor<CGRect>?`；value 的位置为 CGFloat，返回可选 Plottable，当前用 Date 类型约束。没有使用已弃用的 plotAreaFrame／plotAreaSize。
- [Canvas](https://developer.apple.com/documentation/swiftui/canvas)、[resolve(Text)](https://developer.apple.com/documentation/swiftui/graphicscontext/resolve(_:)-4dx65)、[measure(in:)](https://developer.apple.com/documentation/swiftui/graphicscontext/resolvedtext/measure(in:))：renderer 接收 `inout GraphicsContext` 和 CGSize；resolve 接收 Text，返回 ResolvedText；measure 的参数和结果都是 CGSize。draw 的解析文本重载接受 ResolvedText 与 CGPoint。
- [Text.foregroundColor](https://developer.apple.com/documentation/swiftui/text/foregroundcolor(_:)) 已弃用；替代的 [Text.foregroundStyle](https://developer.apple.com/documentation/swiftui/text/foregroundstyle(_:)) 返回 Text，区别于 View 上返回 some View 的通用方法。
- [UIGestureRecognizerRepresentable](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable)：协议为 MainActor；挂载使用 `.gesture`。长按实现和共享 HorizontalPan 的 make／update／handle／coordinator 参数标签与协议一致，全部位于 iOS 条件中。
- [withAnimation 完成回调](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)) 是 `@escaping () -> Void`；[SwiftUI task 的 actor 继承](https://developer.apple.com/videos/play/wwdc2023/10248/) 与现有 UI 上下文一致。新增闭包没有用 detached task 绕过 AppStore 隔离。
- [onGeometryChange](https://developer.apple.com/documentation/swiftui/view/ongeometrychange(for:of:action:)) 的当前文档要求 transform 为 Sendable、结果 Equatable／Sendable；新增 transform 仅为 `$0.size.width`，返回 CGFloat，action 接一个新值。[onScrollGeometryChange](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)) 的 action 接旧值／新值，既有调用符合。
- [sensoryFeedback(_:trigger:)](https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)) 的 trigger 要求 Equatable；当前新增 Int 计数满足，调用限 iOS 分支。[navigationDestination(item:destination:)](https://developer.apple.com/documentation/swiftui/view/navigationdestination(item:destination:)) 需要 `Binding<D?>` 且 `D: Hashable`，当前 route 满足。
- [XCUICoordinate 拖动](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/press(forduration:thendragto:withvelocity:thenholdforduration:)) 的目标类型为 XCUICoordinate，速度为 XCUIGestureVelocity，时长为 TimeInterval；[NSPredicate(block:)](https://developer.apple.com/documentation/foundation/nspredicate/init(block:)) 的 Apple 声明是普通逃逸 Bool 闭包。

工程和 Package 当前都采用 Swift 5 语言模式。本轮已审查新增 actor／闭包边界，并单独用严格 Swift 6 类型检查 Foundation 修复；**未完成整个 App 或 XCTest 的 Swift 6／Apple SDK 类型检查，也未改变工程语言模式**。

## 验证结果

- 按要求执行 `export PATH=/opt/swift-rootfs/usr/bin:$PATH` 后运行 `YUBAI_LIVE_EVAL=0 swift test`，退出 0：**788 项，784 通过／4 项原有实网 opt-in 跳过／0 失败，118.540 秒**。日志 `/tmp/yubai-b40-swift-test.log`。4 项实网测试在求取配置前检查开关，本轮没有启用。
- 首次运行在测试启动前因本 worktree 依赖缓存为空、受限网络无法抓取而退出。随后只向 ignored 的 `.build` 复制 `/home/user/yubai-integ/.build` 中的 checkouts、repositories 和 workspace-state；两个 revision 与现有 Package.resolved 一致：swift-crypto 3.15.1／`95ba0316a9b733e92bb6b071255ff46263bbe7dc`，swift-asn1 1.7.3／`3b6410f7dee09eb33cdd26260c5fd47fda19b0e2`。上述全量结果来自复制缓存后重新执行的指定命令。Package.swift／Package.resolved 未改，未增加依赖。
- 41 个 App 文件**逐个** `swiftc -parse -swift-version 5`，覆盖 arm64 iOS 26 模拟器 Debug（iCloud／App Group）、x86_64 iOS 26 模拟器 Debug（无额外功能条件）、arm64 iOS 26 设备 Release（iCloud／App Group）、arm64 macOS 14 Debug（iCloud）及 Release。Widget 单文件覆盖上述三组 iOS，含 YUBAI_WIDGET_EXTENSION；UI 测试单文件覆盖两种模拟器架构。共 **210 次调用，0 失败、0 诊断**；每个文件的命令和退出码均在 `/tmp/yubai-b40-parse.log`。
- 原 `.infinity` 构造复现诊断，显式 CGFloat 修后通过 `swiftc -typecheck -swift-version 6 -strict-concurrency=complete -warnings-as-errors`。从原／新源码抽取的坐标计算也在相同严格参数下编译并执行，450 组完全一致；脚本／证据在 `/tmp/yubai-b40-geometry.swift` 和 `/tmp/yubai-b40-geometry.log`。
- `git diff --check` 通过。未提交、未推送、未调用真实 DeepSeek、未读取密钥；外部设计稿与分发资源未同步。Mac 上的 Xcode 构建、Widget 链接、UI／视觉／手势实跑仍待验证。
