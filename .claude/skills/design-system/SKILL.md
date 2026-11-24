---
name: design-system
description: Use when writing or changing any SwiftUI screen in Yubai; apply the generated tokens, shared components, spring motion, and acceptance checks.
---

# 余白 SwiftUI 设计系统

先读仓库 `AGENTS.md` 和 `CONTEXT.md`。设计变更先进入设计系统与设计稿，经 owner 确认后再写代码；本技能不授权发布、触发工作流或更改外部设计页。界面可见文字限标题、数字和事实、控件、状态；不在代码中补说明句。交付列出新增或改动的可见中文字符串。

## 真源与生成

`design-tokens.json` 是唯一 token 真源。运行：

```bash
python3 scripts/generate-design-tokens.py
python3 scripts/generate-design-tokens.py --check
```

不要手改 `DSTheme.swift` / `DSMotion.swift`。网页预览也应读取同一 JSON；不要从旧预览的 CSS 反写 token。SwiftUI 实现位于 `Sources/YubaiApp`，项目只 glob 该目录第一层；增加 Swift 文件后运行 `python3 scripts/generate-project.py`，不手改 pbxproj。

命名保持 JSON 顺序，去掉连字符并转 lowerCamel：

| JSON | Swift |
|---|---|
| `color.ink-2` / `accent-soft` | `DS.Color.ink2` / `.accentSoft` |
| `typography.styles.n-spine-lg` | `DS.Font.nSpineLg`，类型 `DS.TextStyle` |
| `spacing.space-12` | `DS.Space.s12` |
| `radius.radius-xs/s/m/sheet/float` | `DS.Radius.xs/s/m/sheet/float` |
| `radius.radius-pill` | `DS.Shape.pill`，`DS.Radius.isPill`，不转换成大半径 |
| `stroke.hairline` / `size.row-bill-2` | `DS.Stroke.hairline` / `DS.Size.rowBill2` |
| `size.segmented-inset` | `DS.Size.segmentedInset`（3） |
| `size.bar-calm/amber/mini` | `DS.Size.barCalm/barAmber/barMini`（4/6/3） |
| `size.day-bar-gap/day-bars-h` | `DS.Size.dayBarGap/dayBarsH`（3/36） |
| `size.donut/donut-stroke` | `DS.Size.donut/donutStroke`（136/18） |
| `size.legend-swatch/brand-tile/menu-w` | `DS.Size.legendSwatch/brandTile/menuW`（10/18/208） |
| `shadow.shadow-float/near/key` | `DS.Shadow.float/near/key`，仅 color/radius/x/y |
| `material.bar` | `DS.Material.bar` 描述符，交给 `.dsBarMaterial(in:)` |
| `icon.symbols.cat-food` | `DS.Icon.catFood`，字重 `DS.Icon.Weight.list/nav/chevron` |
| `motion.springs.smooth` | `DSMotion.smooth`、`.smoothToken`、`.smoothAnimation` |

颜色自动适配 light/dark，包含 sRGB alpha；不要再通过 `.opacity` 还原 `icon-quiet` 的 alpha。SF 数字使用 rounded + monospacedDigit；`dsText` 根据 relativeTo 缩放字号、tracking 和行盒。iOS 用 `@ScaledMetric`，macOS 保留基础字号；行盒只补 token 行高相对原生字体行高缺少的 leading，不重复加系统已有的 leading。

Never derive a size by arithmetic on unrelated tokens — add a token to `design-tokens.json` instead.

图例色块用 `DS.Size.legendSwatch`，订阅日历品牌小方块用 `DS.Size.brandTile`；两者圆角用 `DS.Radius.xs`（4）。`DSInteraction` 只保留 `reducedPressOpacity`、`warningFraction` 和 `floatScale`，不存派生几何。

数量不是几何；在 `DSStyle.swift` 的 `DSLayout` 定义整数，不把 `DS.*` 或 `DSInteraction.*` 转成 `Int`：

```swift
enum DSLayout {
    static let keypadColumns = 4
    static let categoryRow = 5
    static let heroBudgets = 3
    static let weekdays = 7
}
```

Gallery 的柱高和金额是 fixture 数据；柱高在 `private enum GallerySample` 中写普通 `[CGFloat]` 数值数组，金额直接写样例数值，不从 token 凑数。展示标签用现有 token 或 `.fixedSize()`。

所有 Swift 文件都检查 token 转数量和不相关 token 算术：跨 token family 的运算，以及包含两个以上几何 token 引用的乘除式都被拒绝。完整表达式只允许以下已记录的布局关系：同心内圆角 `DS.Radius.<x> - DS.Size.segmentedInset`；分隔线缩进 `DS.Size.icon + DS.Space.s12` 和 `DS.Space.s12 + DS.Size.iconTile + DS.Space.s12`。这些例外不能再拼乘除式来派生尺寸。

## 组件调用

以下签名与 `DSComponents.swift` 一致；数据类型均为组件旁的 struct 或嵌套类型。默认闭包为空，业务由调用者提供。

```swift
DSListRow(icon: String, name: String, amount: String, detail: String? = nil,
          tag: DSInlineTag? = nil, separator: Bool = true)
DSInlineTag(title: String, tone: DSInlineTag.Tone = .warning) // .warning / .positive
DSDayHeader(title: String, total: String)
DSBudget(id: String, name: String, total: String, remaining: String, usedFraction: Double)
DSBudgetRow(budget: DSBudget) // usedFraction ≥ 0.85 时显示 AmberTile
DSAmberTile(budget: DSBudget)
DSAccordion(items: [DSAccordion.Item], expandedID: Binding<String?>,
            onSelect: (String, String) -> Void = { _, _ in }, onAdd: (String) -> Void = { _ in })
DSHero(amount: String, daily: String, remainingDays: Int, days: [DSHero.Day],
       budgets: [DSBudget], onAmount: () -> Void = {})
DSTabBar(selection: Binding<DSTabBar.Tab>, onEntry: () -> Void)
DSAskBar(onAsk: () -> Void = {}, onVoice: () -> Void = {})
DSEntryPills(account: String, time: Binding<DSEntryPills.Time>, timeExpanded: Binding<Bool>,
             repeats: Binding<Bool>, exception: Binding<DSEntryPills.Exception>, repeatDay: Int,
             onAccount: () -> Void = {}, onCalendar: () -> Void = {})
DSKeypad(onKey: (String) -> Void = { _ in })
DSCategoryPicker(categories: [DSCategoryPicker.Category], subcategories: [String],
                 selectedID: Binding<String>, selectedSubcategory: Binding<String?>,
                 onAll: () -> Void = {}, onAdd: () -> Void = {})
DSResultStrip(title: String, detail: String, value: String, unchanged: Bool = false)
DSFloatingMenu(onEdit: () -> Void = {}, onRecategorize: () -> Void = {},
               onDuplicate: () -> Void = {}, onDelete: () -> Void = {})
DSFloatingCard(name: String, amount: String, impact: String, metadata: String,
               note: String? = nil, warning: String? = nil, showsMenu: Bool = false,
               onMore: () -> Void = {}, onDone: () -> Void = {}, onEdit: () -> Void = {},
               onRecategorize: () -> Void = {}, onDuplicate: () -> Void = {}, onDelete: () -> Void = {})
DSSheet(title: String) { Content() }
DSSegmented(options: [String], selection: Binding<String>)
DSButton(_ title: String, kind: DSButton.Kind = .primary, enabled: Bool = true,
         action: @escaping () -> Void) // .primary / .secondary / .text
DSAlertCard(title: String, detail: String, value: String, tone: DSAlertCard.Tone = .warning,
            onTap: () -> Void = {}) // .warning / .positive
DSDonut(slices: [DSDonut.Slice], onSelect: (String) -> Void = { _ in })
DSSubCalendar(days: [DSSubCalendar.Day], leadingEmptyDays: Int = 0, onSelect: (Int) -> Void = { _ in })
DSSwitch(title: String, isOn: Binding<Bool>)
```

`DSAccordion.Item(id:icon:title:subitems:)`；`expandedID` 只存一个 ID。`DSHero.Day(id:height:state:)` 的 state 为 `.past/.warning/.today/.future`。`DSCategoryPicker.Category(id:name:icon:suggested:)` 最后一项是「全部」。`DSDonut.Slice(id:name:value:amount:)` 按 value 降序，最多五段。`DSSubCalendar.Day(number:brand:color:)` 的品牌色是调用者数据，不进入通用 palette。

`DSFloatingCard` 自带 scrim，放在稳定页面的 ZStack 上层。菜单最后一项为「删除」，由业务接确认与删除逻辑。Sheet 必须通过稳定页面的 `.dsSheet(isPresented:content:)` 呈现，内部放 `DSSheet`；原生 presentation 管理弹簧、拖动与 grabber，不把 presenter 放进 ForEach/列表行。内容测量决定 detent，不写固定空白高度。

## 修饰器

```swift
.dsSurface(_ color: Color, radius: CGFloat, padding: EdgeInsets? = nil)
.dsCard() // raised + radius-m + space-16
.dsPill(_ color: Color = DS.Color.surface, padding: EdgeInsets? = nil)
.dsText(_ style: DS.TextStyle)
.dsShadow(_ shadow: DS.Shadow)
.dsBarMaterial(in: some Shape)
.dsFillWidth() // maxWidth infinity, leading
.dsPressStyle() // 或 .buttonStyle(DSPressStyle())
.dsRowEnter(index: Int)
.dsBreathe()
.dsShimmer()
.dsSheet(isPresented: Binding<Bool>) { Content() }
```

圆角 surface 的顺序固定为 padding → background → clipShape → shadow。`DSPressStyle` 在按下瞬间给一次轻触感，缩放 0.97；减弱动态时不缩放，改为 opacity 0.7。视觉胶囊可以是 34pt，但透明可点区域至少 `DS.Size.tapMin`，放在 Button label 内。纯图标按钮必须有完整 accessibilityLabel。

## 动效角色

| `DSMotion.Role` | Spring | 附加参数 |
|---|---|---|
| `.segmentedThumb` | smooth | matchedGeometryEffect |
| `.accordion` | standard | 展开与收起 |
| `.chevronRotate` | snappy | 箭头旋转 |
| `.rowEnter` | smooth | offsetY 8，staggerDelay 0.04，首次出现 |
| `.barGrow` | standard | staggerDelay 0.012 |
| `.number` | standard | numericText，仅变化的位 |
| `.floatCard` | bouncy | 0.96 → 1 + opacity |
| `.sheet` | system | 原生 sheet，自定义 animation 为 nil |

直接传 `DSMotion.snappyAnimation/smoothAnimation/standardAnimation/bouncyAnimation`；需要 additive 行为时 `DSMotion.interpolating(DSMotion.snappyToken)`。不要把物理参数转换成 duration/bounce。`DSMotion.animation(role, reduceMotion:)` 在减弱动态时对 movement 返回 nil；对单独的 opacity 写 `property: .opacity`，始终得到 smooth 弹簧。数字直接跳变。不要把 opacity 的 animation 加给同时包含 offset/scale 的外层。循环使用 PhaseAnimator / KeyframeAnimator + SpringKeyframe；hold 是停留，staggerDelay 是启动间隔，都不是缓动时长。

触感：`DSMotion.Haptic.save` success、`.overspend` warning、`.toggle` selection、`DSMotion.Press.haptic` light impact。快照用 `dsAnimationsEnabled = false` 冻结入场与循环，`dsReduceMotionOverride = false` 保持非减弱动态的终态；生产代码不覆盖系统无障碍设置。

## CSS → SwiftUI

- 半径只用 `.rect(cornerRadius: DS.Radius.x, style: .continuous)` 或 `Capsule(style: .continuous)`；分段内边距直接用 `DS.Size.segmentedInset`，同心内圆角为 `DS.Radius.s - DS.Size.segmentedInset`。高度通过 padding 表达内缩，不用其他 token 凑数。
- HTML block 填满，SwiftUI 默认贴内容；明确写 `.frame(maxWidth: .infinity)` / `.dsFillWidth()`。`calc(100% - 40px)` 是父容器两侧各 space-20，再填宽；`top:50%; translateY(-50%)` 用 ZStack/overlay 居中；`inset:0` 的 scrim 用 `.ignoresSafeArea()`。
- 毛玻璃只用 `.ultraThinMaterial` / `.regularMaterial` / `.glassEffect()`。底栏走 `.dsBarMaterial`，macOS 14 用 regularMaterial fallback。
- 阴影仅 `DS.Shadow` 的 color/radius/x/y；网页 blur = SwiftUI radius × 2。spread 环用 shape.strokeBorder overlay；内描边用 strokeBorder。
- 字体只用 `Font.system` 的 SF Pro / SF Pro Rounded，数字 `.monospacedDigit()`，weight 只 regular/medium/semibold。不要通过 custom font 实现 Dynamic Type。
- 图标只用 `DS.Icon.*` 的 SF Symbols 与 `DS.Icon.Weight`。新代码不画 SVG/Path 图标；环图是 Circle.trim 圆弧，不引入 Charts。
- 动效只用 DSMotion 弹簧；按压用 DSPressStyle；循环用相位或关键帧动画。

禁止：页面硬写 hex、radius、padding；`.cornerRadius()`；非 continuous 圆角；毫秒 easing、timingCurve；任意玻璃 blur；spread/inset 阴影；Font.custom；自制 SVG 图标；serif。旧装饰深度 blur 仅在系统材质无法替代时保留，并逐行注明 `// ds-allow-blur: 原因`；不要给新页面加豁免。

## 验收

```bash
python3 scripts/ui_consistency.py --self-test
python3 -m pytest -q scripts/tests
```

DEBUG 启动参数 `-YubaiDesignSystemGallery` 或 `YUBAI_DS_GALLERY=1` 打开 gallery；Release 无入口。单节快照用 `DesignSystemGalleryView(section:)`。

Xcode 上运行 `YubaiDesignSystemTests`；`DS_SNAPSHOT_RECORD=1` 记录全部，否则 `.missing` 记录缺失并校验现有基线。`DS_SNAPSHOT_EXPORT_DIR` 导出本次实际 PNG；通过 xcodebuild 传递时加 `TEST_RUNNER_` 前缀。基线固定 393pt、3×、zh_CN、大号默认字体、明暗各七节，动画冻结。

`.github/workflows/design-system.yml` 仅支持手动 dispatch，record 默认 false，video 默认 true。仅在任务明确授权时触发；取回 PNG、`__Snapshots__` 与 MP4 审阅。`design-system-motion` 分片只在显式选择时运行，排除默认门禁。仓库变私有时先问 owner：macOS 计费倍率 10×。完整管线与可见文案清单见 `docs/design-tokens.md`。
