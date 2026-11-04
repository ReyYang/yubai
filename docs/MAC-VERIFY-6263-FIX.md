# PR #62／#63 Mac 验证修复

2026-11-04，`fix/mac-verify-6263`，基于 main `55d6687`。输入为 owner 的 Xcode 27.1／iOS 26 模拟器报告：Core 735 项、4 项原有实网跳过、4 个失败用例／5 个失败断言；App 构建阻塞，UI 实际执行 0 项。本轮在 Linux 修复，没有 Apple SDK，不能把条件语法解析当作 Apple 编译通过。

## 根因与修改

| 问题 | 根因、修改与证据 |
|---|---|
| `CashTimelineCard.swift:184` 编译失败 | `CashTimelinePress` 与 `HorizontalPan` 都遵循 `UIGestureRecognizerRepresentable`，不是 SwiftUI `Gesture`；原 `simultaneousGesture(_:including:)` 的泛型约束不成立。两个 recognizer 都通过 `.gesture(_ representable:)` 挂载；长按 coordinator 显式返回不同时识别，图内 `HorizontalPan` 的 `allowsSubgestures` 默认为 false，也不允许两者同时识别。 |
| 长按／拖动仲裁 | 保持 0.25 秒、10pt 长按门槛，`.began` 即选点，`.changed` 逐日读取，结束清选择；提前横移由方向门控的 `HorizontalPan` 平移窗口。两个 recognizer 互斥，且保留 `!holding` 门控及 `pan()` 的防护。两者的 `shouldBeRequiredToFailBy` 都让根 `UIScrollView.panGestureRecognizer` 等待图内手势失败，避免翻根 tab；竖移失败后仍可交给列表。实际 UIKit 仲裁仍待 Mac／真机重验。 |
| Widget 找不到 `YubaiCore` | 工程引用完整：Widget target `FAD79F600E79F84B420BD567` 的 `packageProductDependencies` 含 `CD24E247C09566F51B159FBA`；Frameworks phase `112482586DC9325ECD958FF1` 含 build file `064EF1DFF473D18F8B843BD3`，后者的 `productRef` 指回同一 product；product 指向本地 package `582681C2EAE02B3F3D399C0C` 的 `YubaiCore`。脚本遍历该链通过。报告中 x86_64 失败、加 arm64 后消失，证据指向架构／构建环境差异，不是缺少 package 或 Frameworks 登记；未改 pbxproj，也未强制架构。具体缓存／module slice 状态无法仅凭摘要确定。 |
| `StorageTests...LegacySidecars...:239` | Foundation 枚举返回 `/private/var/...`，测试预期由 `/var/...` 输入拼出；URL 字面相等不是文件身份相等。断言两侧均解析符号链接并标准化，仍精确要求最新损坏版本和最后可读版本这两份及原有次序；sidecar 删除、未知附件保留断言不变。 |
| `StoragePolicyTests...LastCompleteRecovery:115` | 同样是枚举 URL 与输入 URL 的路径别名比较。版本顺序优先从文件名毫秒时间戳得到，此夹具所有时间均明确且不同，不依赖 macOS 文件 mtime 或目录枚举顺序。成员断言比较解析后的 URL，仍保留读取“完整”、最新缺件必然报错、份数上限的独立断言。 |
| `ImportOrganizerTests...NeverResendsGroups:1358` | 生产代码允许 4 个请求并发，按 `TaskGroup.next()` 完成顺序串行保存；原测试把 `sent[0]` 当作已保存的那一段。发送顺序不保证完成顺序，与字典顺序无关。测试现在强制第一个发送一直等待取消，让其他请求先保存，再按实际 `organizedEntryIDs` 定位已保存组；检查所有续跑组都与其不相交，且剩余组集合和数量精确吻合，未保存的组允许重发。生产并发和续跑规则保持。 |
| `StorageTests...ImmutablePayloads...:341` | 旧断言通过 `URL.resourceValues` 读 mtime，Darwin 会缓存 URL 资源值。不可变附件保存路径在大小／checksum 相同后立即返回，并无应当刷新原件的步骤。改为直接读 `FileManager.attributesOfItem(atPath:)`，严格比较同一个 1970-01-01 00:01:40；还在设定时间后立即核验，并预先读取 URL mtime，覆盖存在旧缓存的情况。懒加载、权限、损坏检测和同 ID 不同内容拒绝等原断言全部保留。缓存解释来自代码路径和 Apple 文档；本轮没有在 Darwin 读取实际文件 mtime，需下一次 Mac 执行新断言确认。 |

Apple 对 [URL 资源缓存的说明](https://developer.apple.com/documentation/foundation/nsurl/removeallcachedresourcevalues())说明了同步测试中一次 run loop 内旧值仍可存在；本轮通过直接读取文件属性验证“不重写”，没有放宽时间比较或恢复保护语义。

## 生产代码中的 URL 身份

`Storage.swift` 新增私有 `fileIdentity`。它解析最近存在的祖先，再补回不存在的路径组件，最后以标准化 URL 作身份；不改变调用者的公开 `directory`／`localDirectory`。

不仅是测试差异：新增回归在旧生产实现上稳定复现发现列表无法匹配路径别名。只给完整缺失 URL 调用 `resolvingSymlinksInPath()` 仍不足——Linux 上叶文件不存在时整个路径可保持未解析。因此同时覆盖“缺叶文件”和“多级父目录尚未物化”，双向发现均须命中。

| URL 判断／缓存 | 核对结果 |
|---|---|
| `protected`、`newestReadable`、`references`、`selected`、`remaining.removeAll` | 所有键来自同一次 `recoveries()` 的版本数组。现在在枚举边界统一解析 Recovery 目录，保留原文件名；之后按相同身份保护、查引用、选择、删除，无输入路径与枚举路径混用。保留文件名也使删除仍指向目录中的那一项。 |
| 当前账本引用去重 | 两个本机／迁移路径按同一身份去重后读取，仍保守保护当前元数据的附件引用。 |
| `discoveredFiles` | 写入与查询统一身份，支持未下载的文件及多级缺失目录。 |
| `payloadChecksums` | 写入、命中和回收使用同一身份；删除前先取 key，清历史时也比较解析后的目录。 |
| 云端附件识别／协调、孤立原件清理 | 父目录统一身份再比较；实际删除保留原 URL。避免符号链接目录下绕过云端协调，或漏删不再引用的本机原件。 |
| `readRecovery` 归属检查、本机与迁移目录比较 | 共用同一身份规则；归属检查依然拒绝别的恢复目录。 |

新增另一项显式符号链接流程覆盖：10 个缺件新版本不能挤掉最后完整版本；最新版本仍保留；共享原件保留、孤立 payload 删除；别名 URL 可读完整版本；移除当前附件会回收本机原件，恢复版本仍能读取。旧预算／压缩／不可读引用及 sidecar 测试继续运行。

## Apple API 签名核对

以下为使用到的协议／方法签名，`Context`、`CoordinateSpaceConverter` 均取自各 representable 的关联别名。`R` 在长按实现为 `UILongPressGestureRecognizer`，在横拖实现为 `UIPanGestureRecognizer`。

```swift
// iOS 18+，不要求参数遵循 Gesture，也没有 including 参数
func gesture(_ representable: some UIGestureRecognizerRepresentable) -> some View

func makeUIGestureRecognizer(context: Context) -> R
func updateUIGestureRecognizer(_ recognizer: R, context: Context)
func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator
func handleUIGestureRecognizerAction(_ recognizer: R, context: Context)

// UIGestureRecognizerRepresentableCoordinateSpaceConverter
func location(in coordinateSpace: some CoordinateSpaceProtocol) -> CGPoint

// UIGestureRecognizerDelegate（可选要求；实现不写 optional）
func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                       shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                       shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool

// UIPanGestureRecognizer
func translation(in view: UIView?) -> CGPoint
func velocity(in view: UIView?) -> CGPoint

// UIView
func isDescendant(of view: UIView) -> Bool
```

构造沿用 UIKit 的无参 `UILongPressGestureRecognizer()`／`UIPanGestureRecognizer()`。属性分别是 `minimumPressDuration: TimeInterval`、`allowableMovement: CGFloat`、`maximumNumberOfTouches: Int`（均可写）；`state: UIGestureRecognizer.State`、`view: UIView?`、`UIScrollView.panGestureRecognizer: UIPanGestureRecognizer`（只读）；`delegate` 接受 `UIGestureRecognizerDelegate`，coordinator 继承 `NSObject`。两个 representable 及使用点均只编入 `os(iOS)`，部署 iOS 26 覆盖 iOS 18 的可用性。

签名和语义按 Apple 的 [representable 协议](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable)、[坐标转换](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentablecoordinatespaceconverter/location(in:))、[delegate](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate)、[长按](https://developer.apple.com/documentation/uikit/uilongpressgesturerecognizer)核对。全 App 只有这两种 representable，共 7 个挂载点；修复后全部用 `.gesture`。其他 `simultaneousGesture` 的参数为 SwiftUI `TapGesture`／`DragGesture`，macOS 现金图的 sequence 也是真正的 SwiftUI Gesture。

`shouldRecognizeSimultaneouslyWith` 仅一侧返回 false 不能保证互斥；这里图内长按与横拖两侧均返回 false。`shouldBeRequiredToFailBy` 返回 true 建立的是其他 recognizer 等待当前 recognizer 失败的关系，保留原根滚动分页优先级。此为 Apple API 合约核对，尚未实际链接 Apple 框架或运行 recognizer。

## 验证与边界

- 定向：存储、策略、空间管理及乱序续跑共 55 项，0 失败，11.889 秒。
- 指定全量 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test` 退出 0：**738 项，734 通过／4 项原有实网 opt-in 跳过／0 失败，120.883 秒**。未新增跳过；本轮新增 2 项符号链接回归。日志 `/tmp/yubai-macfix-full-test.log`，定向日志 `/tmp/yubai-macfix-targeted-after.log`；新发现列表回归在修复前有 2 个确定失败断言，修复后通过。
- App 全目录：arm64 iOS 26 模拟器 Debug（iCloud／App Group 开）、x86_64 iOS 26 模拟器 Debug、arm64 iOS 26 设备 Release（iCloud／App Group 开）、arm64 macOS 14 Debug（iCloud 开）的 `swiftc -frontend -parse` 均退出 0；UI 测试与 Widget 的 iOS 26 模拟器 Debug 条件解析均退出 0。
- 新 worktree 仅向 ignored 的 `.build` 复用本机已有同版本依赖缓存；Package.swift／Package.resolved 未改。
- 未验证：Apple SDK 类型检查／构建、Darwin 新断言实跑、XCTest UI、UIKit 手势仲裁、真实 iCloud 协调和真机行为。四个重点 UI 用例仍需在 Mac 执行，Linux 解析不计为执行通过。
- 无新增／改动的界面可见中文字符串，无外观变化。未提交、未推送、未加依赖、未写设计稿链接、未读密钥、未调用真实 DeepSeek。外部设计与分发资源未同步。
