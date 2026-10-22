# 余白 · 设计约定与资源登记

## 2026-10-22 · 页内横滑复验修复

来源为 owner 在 `fix/tabbar-gesture-regression`／`2be7adb` 的 vphone 实测：账目已露出删除后横滑翻页、可同时展开多行；管家快速左扫翻到洞察、慢拖不收起。此次只修页内手势与展开协调，取代下方起手速度 1.3 倍与 UIKit 祖先判定；既有视觉与原稿保持。

`DesignSystem.swift` 的 iOS `HorizontalPan` 以 `abs(translation.x) > abs(translation.y)` 且横向位移非零决定开始；瞬时速度仅保留给松手处理。动态失败关系只针对 UIScrollView 自身的 pan，条件为 `contentSize.width > bounds.width + 1` 或 `isPagingEnabled`，删除 SwiftUI 挂载视图必须是 UIKit 子视图的假设。竖向 ScrollView 不增加等待；横拖开始后仍由原生 pan 取消轻点，未加全页拖动。管家 `ButlerViews.swift` 的收起规则原已符合本轮要求：左拖超过卡宽 25%，或速度 < -650 且位移 < -20 时 dismiss，其余回弹；此次通过共用识别器修正归属，无需改阈值。

`EntriesView.swift` 共享 `revealedEntryID`：另一行开始左滑即关闭旧行，已展开行继续左滑保持，任意已识别右滑松手收回；包含删除按钮区域的横拖由行处理。列表轻点、竖滚进入 interacting、destination／sheet 改变和页面消失均关闭展开；删除后也清理状态。列表轻点采用 simultaneous tap，保留按钮动作；竖滚由 ScrollView 的 phase 观察关闭，不增加竖拖识别器。全部新协调逻辑限定 iOS，macOS 原拖动、阈值与点击抑制保持。

验证：指定 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，406 项、402 通过／4 项原有实网 opt-in 跳过／0 失败。改动的两个 App 文件在 `arm64-apple-ios26.0`／`arm64-apple-macosx14.0`、`AppFlowTests.swift` 在 iOS 26 下通过 `swiftc -frontend -parse`。保留原 38 个测试方法，新增 4 个覆盖展开后左右滑及删除按钮区域、单行展开／外部点按、切 tab／分页关闭、管家长距离快扫；扩充原快短扫、慢拖与竖滚断言。当前 Linux 无 Xcode／vphone 工具，Apple SDK 类型检查、UI 实跑及设备上竖滚／点按和快慢横拖复验仍待做，不能将语法解析视为手势验收。未修改 Core、依赖、`docs/`、设计稿、Figma 或分发包，未提交／推送。

## 2026-10-22 · 标签栏与分页回归修复

来源为 owner 对 main `146e379` 的真机验收反馈及本轮明确要求，在 `fix/tabbar-gesture-regression` 修复。用户于 2026-10-22 选定实色暖纸 raised 胶囊，不用玻璃；随后要求「位置稍微往下一点」，标签栏底边改为距 home indicator 安全区上沿 8pt，整体下移 14pt。取代下方方案 B 的玻璃底板与历史 22pt 底部间距、add 缩放源、根页 safeAreaInset，以及第十一轮自绘横拖；历史选定稿只读保留，不修改 `docs/`、HTML、Figma 或分发包。

根因核对使用 `git diff 5ae3882..HEAD` 及相关提交：`02fe751` 将系统标签栏换成带 72% raised tint 的 interactive regular glass，玻璃会参与模糊、折射与系统底色合成，不能保证实色暖纸和静态清晰度；截图中＋的变形是否还受 matchedTransitionSource 影响，在 Linux 无法分离确认。本轮直接移除 FloatingTabBar 的 GlassEffectContainer／glassEffect，采用不透明 raised Capsule、1pt separator 与 float 阴影；形状、66pt 高、左右 18pt、底部安全区上方 8pt、50pt matchedGeometryEffect 选中胶囊、54pt 绿色＋和全部原 identifier 保留。未选中改 labelSecondary，选中保持 brandInk／card。＋移除 add 源及 addEntry 默认 zoom 目的地，清空 sheetSource 后打开原记一笔 sheet，避免没有源仍请求 zoom。

白条与裁切来自布局链，而非缺少一层颜色：旧 TabRootSwipe 在安全区尺寸的 GeometryReader 内强制 frame，并 clipped；`02fe751` 又在外侧加入 88pt safeAreaInset，缩短该裁切区域。因此列表在栏上方就结束，放在外侧的 canvas 背景无法越过裁切覆盖导航与底部；隐藏系统 tabBar 后仍保留 TabView 的系统容器，PaperBackground 又没有延伸安全区，导航栏未明确采用透明背景，露出了系统底色。本轮删除该 GeometryReader／clipped／占位 inset 与普通 TabView；各 NavigationStack 内外及 iOS 非 sheet 的 PaperBackground 延伸 canvas 到安全区，导航栏透明。分页 ScrollView 允许绘制到安全区；根页滚动用 contentMargins 留出 86pt（66 + 8 + 12）滚动余量，不缩短视口，最后一行仍可完整滚到栏上方，至少留出 12pt；rootBottomPadding 与 toast 底部间距均随 floatingTabbarBottom 自动更新。筛选横条覆写底部 margin 为 0。底部 scroll edge effect 关闭，避免浮栏附近再叠系统模糊；它不是已确认的独立白条根因。

旧 simultaneous DragGesture 同时驱动根页与页内控件，只有当前页位移，没有相邻页；`7453f94` 又临时切换整页 hit testing／disabled 来压制误点，仍未建立原生手势优先关系。本轮采用横向 ScrollView + 零间距 HStack，四个 NavigationStack 常驻以保留状态；containerRelativeFrame(.horizontal)、scrollTargetLayout、paging 与 scrollPosition(id:anchor:.center) 提供跟手、回弹和双向 destination 同步。点击标签以 YubaiMotion.layout 滚动，Reduce Motion 时无程序动画。push 可见性、AppSheet 或洞察日期 sheet 禁止外层滚动；NavigationStack 内恢复 isScrollEnabled，二级页竖向滚动与系统边缘返回继续工作。非当前页对无障碍隐藏，防止四页常驻时相同控件 identifier 重复暴露。

管家卡与现有账目行删除改由 iOS HorizontalPan（UIGestureRecognizerRepresentable + UIPanGestureRecognizer）识别：开始时水平速度须超过竖向的 1.3 倍，祖先 UIScrollView pan 等待它失败，已开始的横拖由系统取消轻点。管家右拖不移动卡片，短左拖回弹，超过四分之一或快速左甩仍 dismissCard；账目保留原来的删除按钮、阈值与撤销。筛选横条／现金图使用同一原生优先关系，同时允许控件内部的滚动／长按拖动识别。删除 iOS 的 tabSwipeReserved、区域 preference、tapsBlocked、TabRootSwipe 和 TabContentEntrance。macOS 的侧栏、底部按钮、背景、滚动余量与原有卡片／账目拖动保持；账目原有点击抑制仅在 macOS 条件分支保留。

### 手势

- 只在现在／洞察／账目／我四个根页横滑翻页，按顺序分页。
- push 后禁止翻 tab，只保留系统左边缘返回；有 sheet 时不翻页。
- 从账目行、管家卡、现金图、筛选 chips 或横向列表开始的横拖交给页内操作。
- 管家卡只响应明显横向拖动，左滑收起，右滑不翻页。
- 竖向拖动交给竖向滚动；横拖不触发行点击。
- 点击标签平滑切页，降低动态效果时直接定位；各页保留导航和滚动状态。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，406 项、402 通过／4 项原有实网 opt-in 跳过／0 失败，未修改 Core 或依赖。App 全部 Swift 的 iOS 26／macOS 14 条件语法解析，以及 UI 测试 iOS 26 条件语法解析通过；这不是 Apple SDK 类型检查。`AppFlowTests.swift` 原 36 个测试方法全部保留，新增 2 个；覆盖双向分页、短拖回弹、push 内横拖不翻页与系统返回、非相邻标签点击及月份状态保持、管家／账目／筛选／现金图归属、sheet 横拖、竖向滚动和最后一行。UI 测试尚未运行。导航背景与 home indicator 实际颜色、底部穿透、嵌套识别器竞争、长按现金图、快速连滑／点击、深色／大字号／Reduce Motion 和 VoiceOver 仍需 Apple 设备验收。未提交／推送。

Apple 官方签名核对：[scrollPosition(id:anchor:)](https://developer.apple.com/documentation/SwiftUI/View/scrollPosition(id:anchor:)) 使用 Binding<(some Hashable)?>；[containerRelativeFrame(_:alignment:)](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:alignment:)) 使用 Axis.Set；[paging](https://developer.apple.com/documentation/swiftui/scrolltargetbehavior/paging) 按容器分页；[UIGestureRecognizerRepresentable](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable) 使用 makeUIGestureRecognizer(context:)、handleUIGestureRecognizerAction(_:context:) 与 makeCoordinator(converter:)；[动态失败关系](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate/gesturerecognizer(_:shouldberequiredtofailby:)) 在开始识别前决定；[isScrollEnabled](https://developer.apple.com/documentation/swiftui/environmentvalues/isscrollenabled) 是可覆写的环境值。

## 2026-10-22 · 标签栏方案 B：暖色 Liquid Glass

来源为 owner 明确选定的 `/tmp/claude-0/r11/canvas12/project/V12-TabBar-Options.dc.html` 中间 B 方案与 `V12-TabBar.dc.html` 的规则，只读引用。该选择取代历史系统标签栏与系统玻璃＋的外观；现在／洞察／账目／我、横滑、记一笔及各标签导航状态保持。

`YubaiApp.swift` 保留四个 Tab 与各自 NavigationStack，隐藏系统栏，在 RootView 叠加 `FloatingTabBar`：左右 18pt、66pt 高、距底部安全区 22pt，内部 50pt 选中胶囊和 54pt 品牌绿＋；20pt 线性图标、10pt 标签、card 高亮、brandInk 选中色、label 未选中色。高亮以 matchedGeometryEffect 配合 YubaiMotion.layout 移动，Reduce Motion 时无动画。中央按钮沿用 addEntry sheet 与 add 缩放源，不改变 destination。容器按「主导航」分组，保留按钮 identifier 与 selected trait。各根页以 safeAreaInset 留出 88pt；键盘出现期间隐藏栏、释放预留，键盘完全收起后恢复。TabView／NavigationStack 下方以 canvas 铺满安全区。

`DesignSystem.swift` 通过每个标签独立的 environment binding，让 yubaiNavigation 默认隐藏自绘栏、根页出现时恢复；账目根页的 hidesTabBar:false 保留，sheet 的 yubaiSheetSurface 隔离这些更新。新增字体与白色 token，iOS 专用栏／状态不进入 macOS 分支。玻璃底放在 GlassEffectContainer 内，使用 regular.tint(raised.opacity(0.72)).interactive()；降低透明度时使用不透明 raised。按 B 采用 72% 暖色 tint 与淡白色内描边；早一张规则稿的 88%／neutralStrong 描边不再作为这两个参数的依据。原生玻璃的折射、饱和度与阴影不会逐像素等于 HTML backdrop-filter；底部 22pt 以设备安全区为起点。

Apple 官方签名已核对：[glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) 的 Glass 默认为 regular、shape 为 some Shape；[tint(_:)](https://developer.apple.com/documentation/swiftui/glass/tint(_:)) 接收 Color? 并返回 Glass；[interactive(_:)](https://developer.apple.com/documentation/swiftui/glass/interactive(_:)) 的 Bool 默认为 true；[GlassEffectContainer 初始化](https://developer.apple.com/documentation/swiftui/glasseffectcontainer/init(spacing:content:)) 的 spacing: CGFloat? 默认为 nil。

UI 测试全部改为 app.buttons[identifier]，沿用 isSelected；保留全部原用例，补充 push 隐藏／返回恢复、导航分组／按钮顺序、键盘隐藏／恢复、最后一行可见与切换后滚动位置保持。Linux swift test 退出 0：401 项、397 通过、4 项原有实网 opt-in 跳过、0 失败，未改 Core。App 在 arm64-apple-ios26.0／arm64-apple-macosx14.0、UI 测试在 iOS 26 条件下语法解析通过；Apple SDK 类型检查、UI 实跑、玻璃／深色／降低透明度／Reduce Motion／VoiceOver 与导航生命周期设备验收仍待做。`docs/`、HTML 原稿、Figma 与分发包未改，未提交／推送。

## 2026-10-22 · 固定收付「会回来的账单」

来源为 owner 本轮明确确认的 `/tmp/claude-0/r11/canvas/project/` 四张 HTML 与便签规则；只读引用，不复制或修改原稿。本轮接入已合入的 #25 Core，不改变其规则，取代第四轮固定收付的 90 天汇总、到什么时候与点行结束菜单；保留此前第十一轮交互、系统玻璃＋、TabView 和我页副标题。

| 选定稿 | 采用源码与行为 |
|---|---|
| `V11-Bills.dc.html` | `FixedFlowsView.swift`：当月剩余要付／要收、每日一个状态点、付款／收款分卡；账户、自动、期数、大约、已记组合副标题；绿色收入、估额 ~、已付淡化。共享 `FixedFlowCheck` 以 `settle → store.apply` 结清，长按输入实际金额；复用现有 Toast／完整账本撤销，轻震。左滑露出中性色「停掉」，确认后 `.endPlan`，并提供同名无障碍动作。rentID 行无结清与停掉动作。 |
| `V11-Bills-Add.dc.html` | 同文件 `FixedFlowEditor`：频率／首次日期沿用 popover，月度 chip 写「每月 X 号」；2–60 期或一直；账户未指定时 chip 提示、自动记禁用；保存 autoPay／今天的 autoPaySince／estimated／installments。第二卡两个开关；底部最多四期点阵，移除结束日期和 90 天预留卡。 |
| `V11-Home-Due.dc.html` | `OverviewView.swift`：今天行下最多两条到期付款，含历史未付项；超出链接进固定收付，没有到期项时保留下一笔。`HeroCard` 标题旁显示实际发薪期限或接下来 90 天；计算页文字和付款明细使用同一期限，预测图仍保留原 Core 观察路径。 |
| `V11-Add-Match.dc.html` | `QuickEntryView.swift`：金额、用途、日期、性质、账户及账本变化时刷新首项建议；键盘上方琥珀胶囊需主动选择、可取消，失去匹配即清空选择；保存和还能花预览都传递选定 link。保持已有记一笔布局和加减键盘。 |

`YubaiApp.swift` 为 ChangeSet 应用增加默认关闭的静默选项，启动、前台及解锁后调用自动记账，保留存储／同步／完整快照撤销；自动记账不触发落笔动效、触感或提示。固定收付月数据随原时间派生版本刷新，避免跨日返回前台仍显示旧状态。`DesignSystem.swift` 只为金额补可选 token 色、HeroCard 补期限文字；`EntryFormComponents.swift` 补账户空值提示和可访问值，不引入依赖。

实现适配与差异：系统导航、sheet、菜单、日期选择器、开关和现有系统字体沿用原生外观，未逐像素复刻 HTML。画板样例金额／日期替换为账本实际值；当月列表遵循 `FixedFlows.month`，不会为了画板里的下月工资示例插入下月行。日期点超过七个时换行；同一天多笔以未付优先汇总一个点，VoiceOver 读取全部状态。一次性安排禁用共几期，预览按真实可发生期数最多显示四个。rentID 按本轮明确要求只读，因此与画板普通 Plan「房租」的可结清按钮不同。原额付清已预留付款时 Core 保持还能花不变；收款或变动金额会按真实现金与预留变化更新，未人为扣减两次。

验证：`export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0，396 项、392 通过／4 项原有实网 opt-in 跳过／0 失败；没有修改 Core 或删除／跳过测试。`AppFlowTests.swift` 新增 8 项，覆盖付清／撤销、收款后还能花变化及持久化、长按改金额、左滑停掉保留已付期、分期／账户自动记开关与前台结算、历史到期卡与溢出导航、手动建议选择／取消／失效及保存关联、启动自动记账幂等且无提示。现有 UI 用例没有旧结束日期或点行结束菜单流程需要迁移。全部 App Swift 的 iOS 26／macOS 14 条件语法解析及 UI 测试的 iOS 26 条件语法解析通过，`git diff --check` 通过；没有 Apple SDK 类型检查或已执行 UI 测试证据。390pt／大字号／深色、长短按区分、滑动与系统返回、VoiceOver、Reduce Motion 和实际自动记账生命周期仍待 Apple 设备验收。`docs/`、原稿、Figma 和分发包未改；未提交／推送。

接口静态核对参考：[Apple 高优先级手势](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:))、[命名无障碍动作](https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:))。

## 2026-10-22 · 第十一轮交互

来源为 owner 本轮明确批准的 `/tmp/claude-0/r11/canvas/project/` 中五张 V11 HTML；该目录只读引用，没有复制或修改原稿。本轮只接交互，保留 #23 修复、#24 系统标签栏和 #25 固定收付 Core，不扩展固定收付页面范围。

| 选定稿 | 采用源码与行为 |
|---|---|
| `V11-Swipe.dc.html` | `YubaiApp.swift`：根内容的 simultaneous DragGesture 跟手位移，30% 宽度或同方向快速甩动后切换 `store.destination`。顺序为现在／洞察／账目／我，＋不参与；方向在起手时锁定，竖向交给滚动。管家卡和现金图通过根坐标系区域登记排除，根内容以外的 push 页面继续系统返回；Reduce Motion 关闭跟手位移。 |
| `V11-Home.dc.html` | `ButlerViews.swift`：单向左滑露出中性色「知道了」，短滑停在动作位，超过卡宽一半松手调用既有 `dismissCard`，下一条按原有布局动效顶上。右滑不响应，保留 ··· 菜单；容器保留子控件并提供「知道了」无障碍动作。 |
| `V11-Home-Scrub.dc.html` | `DesignSystem.swift / ForecastChart`：0.2 秒长按后逐日拖动，竖线、气泡显示真实日期／星期、`ForecastPoint.conservative` 及当天全部发生项，负数带缺口说明；换日 selection 触感，松手和取消淡出。不拖时只显示 Funds horizon，发薪日取 `horizonEnd`，预测路径仍按 Core 保留的完整观察期。图表提供逐日 adjustable action，不暴露隐藏金额。 |
| `V11-Insights-Tap.dc.html` | `InsightsView.swift`：环形扇区按钮按实际弧形命中，点选增加外径、其余淡化，中心显示分类／占比、金额和总额，对应行高亮；重复点击或中心清除，轻震反馈；行仍进入原类别账目。保留 ChartSegments 的首现登记、时长与配色，筛选窗口变化清除选择。 |
| `V11-Model.dc.html` | `SettingsView.swift`、`CloudAssistantViews.swift`：模型原生 Menu，已选项勾选，两个已知模型有原文副标题，未知模型只显示名字；成功获取显示实际 HH:mm，失败／未配置显示「内置模型」，最后一项「自己填…」进入原 CloudModelEditor。选中复用原保存与生效路径。`DeepSeekClient.swift` 提供带密钥的 GET `/models`，保留可注入 URLSession、版本路径及 Linux FoundationNetworking 约定，不发 chat、不计问答发送记录。 |

实现差异：系统 TabView 和 Menu 使用原生外观与现有系统字体；洞察保留现有时间窗筛选和汇总区，本轮没有采用画板里简化的整页排版。横滑仅移动当前根页，露出区域使用 canvas，相邻内容在松手切换后出现，没有复刻稿中的邻页预览。图中示例金额与日期全部换为真实 Funds／收支；未拖动的提示依本轮规则采用 horizon，取列表失败不显示「刚从 DeepSeek 取到」。这些是实现范围与状态差异，不能视为 owner 额外确认。

验证：Linux `swift build --target YubaiCore && swift test` 通过，396 项、392 通过／4 项原有实网 opt-in 跳过／0 失败；模型列表新增 4 项，覆盖 GET 与鉴权、未知 ID／去重、版本 URL、错误／空响应／离线／取消，不访问真实服务。`AppFlowTests.swift` 新增 5 项，覆盖饼图中心与还原／分类导航、模型菜单与手填、四页横滑与系统返回、管家卡手势、现金图手势归属。App 全部 Swift 和 UI 测试以 iOS 26 条件、App 以 macOS 14 条件语法解析通过，`git diff --check` 通过；这些不是 Apple SDK 类型检查或已执行 UI 测试。设备手势、辅助字号、VoiceOver、Reduce Motion 和视觉仍待 Apple 环境验证。沿用既有文件，工程引用无需增加；`docs/`、原稿、Figma、旧原型及分发包未改，未提交／推送。

接口核对参考：[DeepSeek 模型列表](https://api-docs.deepseek.com/api/list-models/)、[Apple 原生菜单副标题](https://developer.apple.com/documentation/swiftui/populating-swiftui-menus-with-adaptive-controls)、[DragGesture 速度](https://developer.apple.com/documentation/swiftui/draggesture/value/velocity)。

## 2026-10-22 · App Group 默认开启

按 owner 本轮明确要求，`Config/AppGroup.xcconfig` 改为默认 YES，取代第九轮记录中的默认关闭；依据为 [Apple 官方 iOS 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios)的免费 Apple Developer 支持。App 与 Widget 保留先加载共享默认、再加载本机配置的顺序，`Local.xcconfig` 可设 NO 回退为按钮；App 的 `YUBAI_APP_GROUP` 编译条件限定 iPhone SDK，Mac 权限／条件和测试 target 保持独立。iCloud 默认值及开关含义保持。

继续采用已确认 V9 Widget 版式，没有改稿或新增布局：共享容器可用且 App 已发布快照时按尺寸显示还能花、今日统计、最多三项常记。`AppStore` 账本变化／时间刷新发布，锁账本或隐藏金额时删除；`CaptureSnapshotBridge.read` 失败／跨日返回 nil，由现有 Widget 视图显示入口。这些运行路径仅核对源码，没有修改 Swift。生成器没有另设默认，在临时目录生成的 pbxproj／scheme 与仓库逐字节一致，因此不重写工程。

[验证记录](../docs/VALIDATION.md#app-group-默认开启2026-10-22)包含 Linux build／373 项测试、54 组配置静态检查及 App／Widget 语法检查；Apple SDK 类型检查、Personal Team 自动注册／签名与隐私清除的设备行为仍待[清单](../docs/V2-TEST-CHECKLIST.md#app-group-默认开启2026-10-22待-apple-设备验证)。未提交／推送，原始 V9 稿、Figma、历史原型和分发包未同步。

## 2026-10-21 · 快速记账、存储与五个概念合并

本轮按 owner 的 merge2 任务整合 `origin/fix/storage-attachments-compaction`，不新增产品或视觉决定。第九轮快速入口、五个概念、V7 卡片与记一笔日期／分段控件修复均保留；第八轮存储空间、附件按需读取、共享恢复 payload／gzip、对话压缩完整纳入。存储页沿用当前 `DesignSystem.swift` 的符号与展示用词，「余白记得的」只指具体记忆条数；保留已删除指南的决定。我页同时提供快速记账和存储空间。

`LedgerSync.persist` 采用存储接口返回的轻量账本，同时保留 `requiringUnchanged` 与专用锁屏记账权限；`Models.Preferences` 同时编码 `quickCapture` 和 `lastBackupAt`，缺失时分别回退默认配置和 nil。`ScreenshotCaptureView` 保存前复用 `ImageCompression`；抹掉本机数据同时清除待打开的快速记账 sheet，账本替换继续触发原有 Widget 快照更新。原始 V8／V9 画板不改写；设计记录按新到旧、产品票按旧到新保留三路条目。

生成器已核对：App／Widget 源文件与 CoreTests 均自动发现，保留 App、CoreTests、UITests、Widget 四个 target 和两个扩展共用文件；运行生成脚本重建 pbxproj，无手工拼接。[验证记录](../docs/VALIDATION.md#快速记账存储与五个概念合并2026-10-21)包含完整 Linux 测试、兼容性／存储组合回归及 App／Widget 语法检查。Apple SDK 类型检查、UI 测试、设备与真实 iCloud 验收待做；未提交／推送，Figma、历史原型、截图和分发包未同步。

## 2026-10-21 · 快速记账与五个界面概念合并

按本轮合并任务保留双方已采用范围，不新增产品或视觉决定。`SettingsView.swift` 保持消费观内记忆计数、心愿单／每周来信共卡及指南删除，同时保留「快速记账」入口，移除底部重复的旧来信行。`EntryEditView.swift` 保留 Apple Pay 来源胶囊、商户分类映射、删除／好了按钮与普通记录编辑，性质使用 `entryLabel`，购买问题统一为「该不该买」。`DesignSystem.swift` 保留「没分类」标签、新主数字文案与分段控件尺寸修复；`EntryFormComponents.swift` 保留日期弹窗尺寸及可隐藏表头动作。

Siri 结果、截图列表、通知、商户映射与编辑页的分类文案复用 `Classification.displayCategory`，不修改分类存储原值或规则。V7 卡片检测／合并／日期／反馈逻辑保持。`scripts/generate-project.py` 已核对包含双方新增文件与四个 target，再生成工程；没有手工拼接 pbxproj。双方原始设计记录按新到旧保留于下方，产品票按旧到新保存。

合并后的 Linux 构建、346 项 Core 测试、iOS／Mac App 与 iOS Widget 语法解析及工程引用检查见[验证记录](../docs/VALIDATION.md#快速记账与五个界面概念合并2026-10-21)。Apple SDK 类型检查、UI 测试与设备验收仍待做；未提交／推送，Figma、历史原型与分发包未同步。

## 2026-10-21 · 第九轮「快速记账」

owner 在本轮 brief 明确确认 V9 八张画板及 DS「系统入口／动效」，[原稿与任务原文](mockups/quick-capture-v9/README.md)原样长期归档。本轮授权优先于下方旧轮次“不提交”的范围描述。选定稿不代表原生设备验收通过。

| 画板 | 采用源码与行为 |
|---|---|
| Lock／Home-Widget／Control | `YubaiWidgets/YubaiWidgets.swift`：两种圆形锁屏入口、矩形还能花、主屏 small／medium 常记预填、两个 ControlWidget；控制复用两 target 的 `CaptureControlIntent.swift` OpenIntent，所有点击打开 App。共享 `CaptureWidgetSupport.swift` 只传快照；App Group 配置默认关闭，关闭／无权限／跨日均不显示数字。主屏沿用暖纸浅深 token，锁屏单色交给系统。 |
| Siri-Snippet | `QuickCaptureIntents.swift`：本机记账、金额缺失追问、iOS 26 SnippetIntent 的只读结果、用途／金额／分类／账户／时间、还能花、编辑和按 id 撤销；账本锁启用时去掉金额以外的记录信息，隐藏金额时遮住数字。 |
| Pay-Auto／Add-Prefilled | `CaptureNotifications.swift`、`EntryEditView.swift`：本地通知及编辑／撤销动作；沿用改一笔，Apple Pay 状态使用顶部来源胶囊、底部商户分类保存与删除／好了两按钮，不新造编辑页；无把握的记录显示没分类标签。 |
| Screenshot | `QuickCaptureSupport.swift`：Vision 本机读取、多笔勾选、记下 N 笔、原件附件、打开核对进入原 ImportView；读不出金额时返回记一笔并把原图留在其导入入口。`ImportView.swift` 的启发式改为共用 Core 纯函数；Vision 仍留 App。 |
| Me-Quick | `QuickCaptureSettingsView.swift` + `SettingsView.swift`：近七天实际笔数／后台记账笔数、钱包自动化步骤与通知权限、卡到账户及商户到分类两个可增删改的原生列表。 |
| 预填与深链 | `YubaiApp.swift` 只接 sheet／URL 分发和 AppStore 单例，不改 TabView；`QuickEntryView.swift` 仅预填参数、携带截图进入导入及指定的还能花文案，不改日期与分段布局。`EntryFormComponents.swift` 给既有表头增加可隐藏尾部动作的默认参数，Apple Pay 确认在底部。 |

Core `QuickCapture.swift` 复用 EntryAmountParser、ManualBookkeeping 与 Finance；卡／商户偏好和可选来源字段向后兼容。Apple Pay 以原始卡、商户、金额身份和原付款时间做 120 秒去重，软删除后保留凭据；snippet 渲染不会再次记账。所有后台操作在 App 进程内复用同一 MainActor／AppStore／Repository、版本检查与 iCloud 待上传状态，账本锁下仅专用记账和撤销放行。App Group 快照在隐藏金额／启用账本锁时删除。

没有新增动效或包，界面沿用 YubaiMotion 与系统 sheet／导航。Siri／通知／WidgetKit 的外框交给系统，画板的手机背景、系统遮罩、外部字体不复制进应用。实现与原稿的映射不构成逐像素原生验证；390pt、大字号、深色、VoiceOver、减少动态效果、锁屏及系统自动化均待 Apple 设备按[清单](../docs/QUICK-CAPTURE.md#验证与限制)验证。Linux build 和 324 项完整 Core 测试结果见[验证报告](../docs/VALIDATION.md#第九轮快速记账2026-10-21)。Figma、历史原型及分发包未同步。

## 2026-10-21 · 第八轮「存储空间」

owner 明确确认 [storage-v8 三稿](mockups/storage-v8/README.md)并授权实现。原始 HTML 未改写，数字为样例，App 使用本机账本副本与实际文件长度。此轮补充第四轮「我」的维护入口，继续沿用 `DesignSystem.swift` 与 Motion v2；没有新增动效、依赖或独立样式体系。

| 选定稿 | 原生源码与采用范围 |
|---|---|
| `V8-Storage.dc.html` | `StorageView.swift / StorageView`：衬线两行占用标题、brand／series2／neutralStrong 分段条与三行图例、截图与原件卡、恢复历史卡、底部 amberInk／card 抹掉按钮。`SettingsView.swift` 在备份与恢复下一行加入存储空间和实际总大小。恢复历史仍打开现有 `RecoveryVersionsView`，清除使用系统 confirmationDialog。 |
| `V8-Storage-Photos.dc.html` | `StoragePhotosSheet`：3／6／12 个月单选，默认半年；截图数／主目录 payload 大小／账目都留着、原件说明、删除与取消。按附件 createdAt 判断；移除附件并清空账目与导入撤销快照中的截图引用，正常保存留下「删除旧截图」恢复版本，主目录 payload 删除后用既有 toast 显示张数。 |
| `V8-Storage-Erase.dc.html` | `StorageEraseSheet`：有效账目／账户／记忆／截图及原件／恢复历史数量，备份状态，先加密备份打开原 `BackupView`，精确输入「抹掉」才启用抹掉操作。`Preferences.lastBackupAt` 可选兼容字段只在导出成功后记录；之后笔数取 recordedAt／导入时间，不伪造旧记录时间。`AppStore.eraseAllDeviceData` 与 `LedgerSync.swift` 切回仅本机、清除待上传状态与本机目录、换空账本并回到 onboarding；云端账本及钥匙串密钥保留。 |

Core 统计、分类和删除在 `YubaiCore/Storage.swift`／`StorageManagement.swift`。恢复占用包含共享 Payloads 与旧 sidecar；截图以账目引用且不属于任何导入原件判定，撤销过的批次仍保留原件。清理使用 repository 锁／恢复锁，云端截图 payload 经过原有下载与协调；删除失败回滚账本、恢复历史和涉及的 payload。App 实际只操作本机副本，再沿原有上传链同步截图删除。

适配：返回、标题栏、拖拽条与呈现采用原生导航／sheet；sheet 按内容高度呈现并可拉到大高度，小屏与大字号滚动，单选在辅助字号改纵排。复用 Card、Primary／PressButtonStyle、Pill、Toast 与既有列表／sheet 行为；32pt 视觉单选包在至少44pt触控区中。分段条和每条统计有 VoiceOver 文本，按钮／输入框有可访问名称与测试标识。

验证与限制见 [本轮记录](../docs/VALIDATION.md#第八轮存储空间2026-10-21)与 [人工验收](../docs/V2-TEST-CHECKLIST.md#第八轮存储空间2026-10-21待-apple-设备验证)。Linux 可验证 Core；SwiftUI 只做语法与源码核对，Apple 编译、UI 测试及视觉／交互／无障碍验收尚未执行。工程已重新生成；Figma、旧原型和分发包未同步，未提交。

## 2026-10-21 · 五个界面概念

来源为 owner 本轮完整任务；这是明确采用的文案与局部结构调整，不是新增视觉定稿。术语权威见 [CONTEXT.md](../CONTEXT.md#界面用词)，决定与边界见[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-21--五个界面概念owner-明确要求)。本条取代 V3／V4 稿中对应旧文案、我页独立记忆入口和指南；原稿归档保持原样。

| 范围 | 权威源码与采用方式 |
|---|---|
| 我 | `SettingsView.swift`：我的消费观内加记忆总数与本周新增数；下方心愿单／每周来信合为一张卡；保留账户、账目、固定收付及底部导入记录／智能与隐私／备份与恢复；删除指南行和实现 |
| 我的消费观 | `ProfileView.swift`：末节展示最近更新的两条记忆，带日期与中文来源；「全部 N 条 ›」push 原 `MemoryView`，空列表仍可进入；沿用现有暖纸卡片、字体与导航 |
| 还能花 | `OverviewView.swift`／`DesignSystem.swift`：主数字、图例、预测、每周来信与购买判断统一用词；明细页仅列现金、信用卡要还、接下来要付、在存钱、始终留着、日常开销、没写用途的进账、= 还能花，保留付款列表和事实提示 |
| 详情与欢迎页 | `EntryDetailView.swift` 不展示性质行；编辑／版本摘要只展示支出、收入、转账，底层 Nature 不变；`WelcomeView` 保留品牌、先记下此刻的余额与原按钮 |
| 需要留意与每周来信 | `ButlerViews.swift`：空卡片区不显示占位话；标题、标签和明细链接按新词；保留 PR #18 的 V7 检测、合并、日期、证据与反馈逻辑及所有入口 |
| Core 与生成文案 | 仅更新可见模板、错误提示及模型措辞约束；记忆来源使用展示属性，旧分类占位用展示映射；不迁移存档、不改计算、字段、Codable 键、枚举原值或去重键 |

验证见[本轮记录](../docs/VALIDATION.md#五个界面概念2026-10-21)。Linux 不编译 SwiftUI；Apple 构建、两端布局、大字号、VoiceOver 与真机验收仍待做。未提交；Figma、历史原型、截图和分发包未同步。

## 2026-10-21 · 管家的话 V7 异常消费卡

owner 在本轮任务提供已批准的 `V7-Butler-Unusual` 文案与行为，[文字归档](mockups/butler-unusual-v7.md)是本轮来源；没有取得原画板文件，也未新绘制或改动历史稿。采用以下范围，其他卡片沿用现有设计。

| 范围 | 权威源码与采用方式 |
|---|---|
| 原因、用途与日期 | `Assistant/ButlerWording.swift / OffCharacter`：偏高／少见／想克制的模板、用途约 10 字与 Money.text 金额、单笔倍数四舍五入、合并最小倍数向下取整、实际消费日期范围。 |
| 合并与存档 | 同原因同分类／克制领域合并；所有 entry IDs 留在 evidence 和稳定键中。`CardCandidate`／`ButlerCard` 仅新增可选 meta，旧卡片缺字段仍用现有展示。反馈、静音、导入撤销与每周回看复用既有入口。 |
| 原生展示 | `ButlerViews.swift / ButlerCardView`：复用 serif cardTitle、muted 正文按钮及现有依据页；单笔「看这笔 ›／值得」、合并「看看这 N 笔 ›／都值得」，「有点后悔」保持。隐藏金额时仍只显示隐藏提示与依据链接。 |

合并偏高正文的「平时一笔约」取各笔历史的去重并集、排除本卡记录后的均值；标题最低倍数仍按每笔自己的检测均值计算。合并少见／克制标题与有界事实摘要为授权内实现选择，非 owner 提供的额外画板。运行结果见 [本轮验证](../docs/VALIDATION.md#管家的话-v7-异常消费卡2026-10-21)。已通读核对 SwiftUI，Apple 编译、布局、辅助功能与真机验收未执行；Figma、旧原型、截图及分发包未同步，不提交。

## 2026-10-21 · 第四轮「手动优先」

owner 已批准本轮 V4 与 DS，原样保存在 [manual-first-v4](mockups/manual-first-v4/README.md)。任何记账、改账、看账与添加固定收付均有手动入口；问余白继续辅助。以下取代同日 Motion v2 中问余白圆形 tab 及相关缺屏描述，其他既有动效／iOS 26 系统玻璃约定不变。

| 选定稿 | 原生源码与采用范围 |
|---|---|
| `V4-Home.dc.html` / `V4-Home-Saved.dc.html` | `OverviewView.swift`：左眼睛／现在／40pt 问余白；主数字构成条下的今天行、笔数／最近用途／净额，zoom 到 `EntriesView`；仍用 150／96／一行的 `ViewThatFits`。`YubaiApp.swift` 与 `DesignSystem.swift` 复用 pendingEntrySave、数字换位、水面、触感和撤销 toast。 |
| `V4-Add.dc.html` / `DS-Keypad.md` | `QuickEntryView.swift` / `EntryFormComponents.swift`：支出／收入／转账、只用自定义键盘的金额与加减结果、常用分类／更多、用途／账户余额／日期、保存后余白预览、连续记账；通过手动 ChangeSet 保存。导入仅切换到参数为空的 `ImportView()`。 |
| `V4-Entries.dc.html` | `EntriesView.swift`：系统返回胶囊、右侧记一笔、搜索、逐月净收支／逐日进出与懒加载 EntryRow；新行洗色与删除让位复用原动效，隐藏金额同步处理。今天、我均可进入。 |
| `V4-Entry-Edit.dc.html` | `EntryEditView.swift`：原性质、金额、分类／更多、用途、账户、日期与时间、备注、source／recordedAt、就事提问、确认软删除及撤销；保存保留 id／source／recordedAt。洞察与账户的普通记录点开编辑，助手／管家依据仍走 `EntryDetailView`。 |
| `V4-Ask-Empty.dc.html` / `V4-Ask-Typing.dc.html` / `DS-AskBar.md` | `AskYubaiView.swift`：只改空态标题与输入区域；52pt 最小高度、6pt 内距、40pt 加号／单一尾钮、20pt 字行与10pt上下内距、最多5行、底部对齐、三条建议直发。消息列表、草稿卡、发送与听写实现保持其原逻辑。 |
| `V4-Me.dc.html` | `SettingsView.swift` / `DesignSystem.swift`：左空／我／右助手圆钮，账户后新增账目／固定收付卡，保留其余维护入口，指南仍在底部；`InsightsView` 使用同一助手顶栏。 |
| `P-Plans.dc.html` / `P-Plan-Edit.dc.html` | `FixedFlowsView.swift`：标题固定收付，90天非还款安排的要付／要收、活动安排与房租行、结束安排；`FixedFlowEditor` 的要付／要收、金额、名字、周期／首次日期、可选账户、结束日期及90天副本预览。按任务省略 AI 预填、租金与目标卡、进出图及解释性页脚。 |
| 三根页／系统圆钮 | `YubaiApp.swift`：系统 `Tab(role: .search)` 变为 plus／记一笔（`addEntry`，source `add`），保留当前 tab；根页助手为 `askYubai`／source `ask`。Mac 浮钮同样记一笔，⌘N 新建、⌘K 问余白。 |

非 UI 逻辑在 `YubaiCore/ManualBookkeeping.swift`：整数分键盘、分类频次与 CategoryMemory／关键词建议、最近应用内账户、日期落点、保存副本资金预览、编辑保留来源、按天／月汇总与搜索、安排周期和未来发生项。`ChangeSet.EntryDraft` 增加向后兼容的可选转入账户，保留 recordedAt 锚点修复；月收支与 Finance 共用支出／退款口径。

适配边界：样例数据由本机账本替换；字体沿用已采用的系统 rounded／serif，sheet／返回／菜单／日期使用系统控件，不自行模拟玻璃。输入金额、分类芯片和键盘复用现有 token，分类选中内描边 1.5pt。没有新增 spring 或动效；大字号／较小 sheet 允许表单滚动。固定收付直接复用 Finance.occurrences 的90天口径，保留尚未付完的逾期义务，排除信用还款避免本金重复预留。

验证：Linux Swift 6.2.4 的 Core 测试通过（运行结果见 [检查清单](../docs/V2-TEST-CHECKLIST.md#第四轮手动优先2026-10-21待-apple-设备验证)）；SwiftUI 按 iOS 26／macOS 14 目标仅做语法解析与人工 diff 核对，不能代替 Apple API 类型检查。新增手动记账 UI 流程源码尚未运行；390×844 首屏、输入条单行基线、保存顺序、转账、深色／大字号／VoiceOver／减少动态效果与 Mac 仍待设备验收。工程已按生成器的 App 顶层 swift glob 重新生成；没有改 ImportView 内部、AskEntryDraftCard 或网络服务，也未提交。Figma、旧原型与分发包未同步。

## 2026-10-21 · Motion v2 与 Liquid Glass

owner 本轮明确批准 motion v2 与 iOS 26 Liquid Glass，按所附 README 的「玻璃／动效／SwiftUI 对照」、tokens 和交互样机接入。三份输入[原样长期保存](motion-v2/README.md)，本轮指令中的已批准状态优先于原文件遗留的「待确认」。本次取代下方 V3 的 iPhone 自绘导航与 iOS 18 部署描述；V3 其余页面结构继续沿用，不改财务规则或 Core。

- `DesignSystem.swift`：集中三种 spring、时长与曲线；数字用 numericText，隐藏金额／减少动态效果用 160ms 淡入淡出或终态。首现图表与水位按进程登记，离开时结束；预测线横向揭示，低点下落与单次外圈，环图逐段长出／角度变形、柱从基线生长。环图着色放在动画 mask 外，避免颜色渐变。
- `YubaiApp.swift`：iOS 系统 TabView 三页，search role 作为问余白动作，selection binding 保留原页；新根页方向偏移 12pt，首开无入场。保留 `tab_*` 标签标识，UI 测试按系统标签文字查找。Mac 侧栏与旧版安全留白保持；系统栏接管 iOS 底部安全区。
- 浮层：顶栏圆钮、提示条、助手输入条和 Mac 问余白圆钮用系统 glassEffect；顶栏组合使用 GlassEffectContainer。sheet 容器不再强盖 canvas，内卡／列表仍为暖纸；iOS 系统导航提供返回控件，内容详情用 matchedTransitionSource／zoom，设置列表继续 push。所有新增玻璃 API 均有 macOS 26 可用性分支。
- 保存：持久化成功后识别实际新增／删除记录；sheet 收起后英雄数字换位、水带 keyframe 单次晃动与成功触感，380ms 后提示条入场，名义时长至 680ms。撤销只换回数字与轻触感；整批撤销抑制删除触感。替换账本或锁屏会取消待播反馈。行插入／删除让位、首次新行洗色、管家收起、分段滑块、助手消息入场和 4 秒提示条下滑关闭已接线。
- 新增 `MotionState.swift` 的 Foundation 逻辑测试，直接与 App 共用源文件编入 UI 测试 bundle；新增问余白保留当前页的 UI 流程。工程生成器同步 iOS 26 与源文件引用；PackageDescription 升到 6.2 以使用 `.iOS(.v26)`，Swift 5 语言模式、macOS 14 与 Linux Core 排除 App 的规则保持。

缺屏：当前没有原型中的独立「记一笔」数字键盘／分类选中芯片、「今天 → 账目」总账页、独立「想一想」五道水位购买完成页；没有为本任务新造这些页面。现有问答补记、导入、分类／账户／依据记录列表已接入对应保存与行反馈。分类芯片的缩放 helper 已备好，但无该类选中芯片可接。

系统标签图标当前使用静态水位模板资产与 SF Symbols，原型的逐带／扇区／点头自定义图标动画未实现；标签栏的玻璃选择动作交给系统。问余白的 zoom 来源已绑到系统 Tab 标签，原生 Tab 标签提取是否保留来源几何、圆钮的 tint 效果仍需 Xcode 26 真机确认，不能当成已验收。

本轮只有[静态检查](../docs/VALIDATION.md#motion-v2--liquid-glass静态核对2026-10-21)，没有 Swift 类型检查、Apple 构建、Core／UI 测试运行或视觉、VoiceOver、减少动态效果设备验收。旧 Figma、历史 HTML、截图和发布包未同步；不提交、不推送。

## 2026-10-20 · 记忆与智能设置选定稿

owner 本轮明确确认八张记忆与智能设置画板，按当前 `feat/ai-memory-drift-fixes` 源码结构接入；批准设计稿不代表已经完成原生设备验收。[原样保存的画板](mockups/ai-memory-v3/README.md)补充并取代下方相应的「缺画板／界面待确认」历史状态。

| 用户确认的画板 | 对应权威源码与实现 |
|---|---|
| [V3-Ask-Remember](mockups/ai-memory-v3/V3-Ask-Remember.dc.html) | `AskYubaiView.swift` + `MemoryView.swift / RememberedRows`；一次 update 保存记忆及待确认提案，新增／更新各一行，撤销调用 Memory.undo，旧回答不会覆盖后来编辑过的记忆 |
| [V3-Memory](mockups/ai-memory-v3/V3-Memory.dc.html) | 新 `MemoryView.swift`；三组非空记忆、日期／中文来源／原话，原生列表支持左滑删除，点开编辑或删除；空状态沿用用户指定的唯一补充文案 |
| [V3-Me](mockups/ai-memory-v3/V3-Me.dc.html) | `SettingsView.swift`；消费观与心愿之间的记忆入口及本周新增计数，智能入口使用 brand-tint 已配好标签；Mac 的「我」复用同一页面 |
| [V3-Letter-Learned](mockups/ai-memory-v3/V3-Letter-Learned.dc.html) | `ButlerViews.swift / WeeklyLetterCard`；依据下方的 brand-tint 卡，每句“不对”调用 Memory.reject 后隐藏 |
| [V3-Letter-Review](mockups/ai-memory-v3/V3-Letter-Review.dc.html) | 同上，learned 后为 amber 回顾卡；保留刷新确认日期，修改进入消费观，删除经现有 ButlerProposalView 确认；过时问题不继续展示 |
| [V3-Ask-Judge](mockups/ai-memory-v3/V3-Ask-Judge.dc.html) | `AskYubaiView.swift / AskPurchaseCard`；本地引用读取带 confirmed_at 的原则／领域，显示“你 X 月写过”，未知时间和超过180天沿用 core 的提示约定 |
| [V3-AI](mockups/ai-memory-v3/V3-AI.dc.html) | `SettingsView.swift / IntelligencePrivacyView` + `CloudAssistantViews.swift`；云端与隐私两组、当前模型及编辑、钥匙串密钥输入、会话发送总数和原稿说明；原有来信提醒、设备锁与外观项继续保留在下方 |
| [V3-AI-ModelError](mockups/ai-memory-v3/V3-AI-ModelError.dc.html) | `CloudAssistantViews.swift / ModelUnavailableNote` + `IntelligenceRuntime.swift / CloudAIStatus`；按稿显示实际模型名，问答内提供设置入口；错误状态留本机，成功请求或保存模型后清除 |

只扩展 `DesignSystem.swift` 的小动作按钮与标签高度，继续使用现有语义颜色／字体／卡片。记忆列表使用原生分组 List 以提供两端删除能力，编辑器沿用原生 Form；原稿没有独立编辑画板。每周回看在管家刷新早退之前执行，成功原子保存并更新来信，失败静默。本轮重新生成 Xcode 工程，仅完成源码通读、Swift 语法解析和工程静态核对；编译、iPhone／Mac 布局、深色、大字号、VoiceOver、网络及 Keychain 验证待做，见 [验收清单](../docs/V2-TEST-CHECKLIST.md)。

**2026-10-20 第三轮选定稿**：本轮 owner 明确批准本地 `design-ref/mockups/V3-*.dc.html` 全 13 稿及 `design-ref/ds`（来源目录为 `/tmp/claude-0/-home-user-yubai/daae97b0-203d-51d2-aee2-e0a1c7360177/scratchpad/`）。`refactor/v2-design-alignment` 已以此对齐 SwiftUI：iPhone 三 tab 浮动同排导航，Mac 三项侧栏与根页问余白圆钮；现在只露一张管家卡、来信入口与可收缩图表，洞察复用 Finance 的净收支口径，其余稿沿用真实数据和已有目的地。图表仍展示现有引擎已扣预留的保守路径；无依据的示例内容不补造。仅语法与工程静态检查，编译、两端视觉、Dynamic Type、VoiceOver 与设备验收待做；下方候选／缺画板记载为对齐前历史，Figma、旧原型与分发包仍未同步。

更新：2026-10-20。当前为「余白 2.0 · 管家」，沿用暖纸设计系统与原生 SwiftUI 组件构建候选 UI；页面视觉尚未定稿，采用不等于用户已经完成个人体验验收。用户决定与 Agent 实现选择以[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-20--余白-20管家决策归档)为准。

## 2.0 设计资源与缺口（2026-10-20）

2026-10-19 的[390pt 页面稿](https://claude.ai/artifact/FD6H6cqc6qAjsfZqiP8F6p)早于 2.0；它与[暖纸设计系统](https://claude.ai/artifact/Pz2z4mQNoCqTNLGRafY9v5)提供既有风格依据，不覆盖 2.0 的全部页面。当前 UI 使用 [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift) 的 token、Card、Page、按钮、文字与图表组件直接构建，是实现候选，不能记为最终视觉。旧 Figma、HTML 原型、截图和发布包均未同步。本轮未绘图，页面稿 artifact 无法通过浏览工具读取，来源与日期沿用既有记录。

以下七类均**尚无对应的 2.0 画板**；源码存在只说明实现已写，不表示布局与交互已通过验证。

| 缺少的画板 | 当前候选实现 | 「同步设计稿」需覆盖的状态 |
|---|---|---|
| 消费观画像页 | `ProfileView.swift` | 愿意多花／想克制、软线、原则、底线、目标、空内容与待确认提案 |
| 冷启动对话 | `ProfileConversationView.swift` | 一次一问、跳过、等待／失败、整份画像提案确认与取消 |
| 心愿单 | `WishlistView.swift` | 考虑中／已买／放弃、交易匹配歧义、回访及反馈 |
| 每周来信 | `ButlerViews.swift` / `WeeklyLetter.swift` | 来信正文、七日曲线与数字、依据、数据不足与历史回算说明 |
| 导入问题 | `ImportView.swift` | 最多五题的分组、选项与自由补充、稍后处理、离线待整理与整批撤销 |
| 推送 | `WeeklyPush.swift` / `SettingsView.swift` | 默认关闭、主动开启、权限请求／拒绝、系统设置入口与每周提醒文案 |
| 问余白回答卡片 | `AskYubaiView.swift` | 数字与图表、依据详情、未核实金额、修改提案确认／拒绝、购买判断、心愿、语音与截图金额确认 |

下一次「同步设计稿」以 2.0 的现在／我／问余白和 owner 的规格为范围，补齐上述画板及两端、深色、大字号与异常状态，再记录候选反馈和采用情况。旧稿保留原位置与历史含义，不把实现截图反写为用户定稿。本轮只维护记录；owner 最后在 Mac 按[组合清单](../docs/V2-TEST-CHECKLIST.md)验收，当前仅有静态解析与工程引用检查，没有编译或运行证据。

下节为 2026-10-19 迁移及随后旧页面修复的历史，五项导航、本机模型、洞察页等描述已被当前 2.0 范围替代。

## 2026-10-19 · 设计系统迁移

- 本次采用的视觉依据是[暖纸设计系统](https://claude.ai/artifact/Pz2z4mQNoCqTNLGRafY9v5)与[390pt 页面设计稿](https://claude.ai/artifact/FD6H6cqc6qAjsfZqiP8F6p)；生产样式的长期权威仍是 [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift)。
- 已将 `Sources/YubaiApp` 的现有页面、编辑器与子页面迁移到 `YubaiColor` / `YubaiFont` / 间距与尺寸 token；移除兼容主题与图标方块。首页采用 `HeroCard`，分类占比改横条，现金预测采用台阶线，导入与购买结果使用水位记号，反馈使用 `Toast`。长列表用带分隔线的惰性列表卡；编辑器保留系统 Form。
- 已采用：按设计系统 SwiftUI 对照移除三套颜色主题，`Preferences.colorTheme` 仅为旧存储兼容保留，界面忽略其值；不打包字体，数字用系统 rounded 等宽数字、衬线用系统 serif、正文用系统字体。助手页面尚未实现，因此保留五项原生 `TabView` 与 Mac 侧栏；原有操作和数据流程不变，聊天、语音、自动备份不纳入本次迁移。
- Step 3 修复按钮样式作用域、购买水位映射、待明确记录元信息、金额精度与 Mac 底部留白；拆分图表表达式，洞察汇总每次渲染只计算一次。预计收入仍以虚线预测路径与直接文字标签显示。
- 已做 Swift 语法树解析、旧样式残留扫描，以及标识符、快捷键、store 更新动作与说明文案的静态对照。当前环境没有 Swift / Apple SDK；iOS 与 macOS 编译、390pt 真机布局、深色、大字号、辅助功能与长账本性能均未执行验证。
- 现有 Figma 画布、旧截图、历史原型和既有验证报告未同步，不代表这次迁移的视觉或运行验收。
- 合并 E10 / E14 / E18 修复时保留上述设计：资金偏好三项显示持久标签并保留相同的 accessibility label；导入历史的导出 / 撤销、本机模型的下载 / 删除使用独立按钮样式。保留退款分类跟随原支出的存储同步与跨统计区间查找；复核 AppStore 更新、撤销、恢复和示例切换均清空相关缓存，单次遍历资金计算保持原逻辑。此次仅完成差异与源码静态复核，未运行 Swift 构建或 UI / Core 测试；外部设计资源未同步。
- 2026-10-20 无障碍修复：洞察分类横条列表显式使用 `.accessibilityElement(children: .contain)`，容器标签为「分类消费分布」，各行继续独立朗读分类、笔数与金额；视觉样式不变。已静态检查应用中的其他 accessibility label，未发现其他同类容器覆盖子项标签的问题；未运行 Swift 构建或设备 AX 验证，外部设计资源未同步。

## 当前应用设计

2026-10-20 按用户批准的 2.0 范围采用「现在／我 + 问余白」。Agent 用两端共用 SwiftUI 导航容器底部 accessory 实现常驻入口（使用 safeAreaInset，不依赖 iOS 26 专属 accessory API，保持 iOS 18 / macOS 14 的部署范围）；Mac 侧栏仅有现在与我。现在保留来信、管家、保守可动用与计算依据、Finance 待付款列表、导入；移除原首页独立资金走势图与手工维护页面，图表继续用于来信和问余白回答，洞察 tab 已删除。记录详情从依据打开，删除只能通过撤销或恢复版本找回。目标编辑器仅由 ProfileView 使用，问余白直接展示自己的补记草稿，不需要旧记录编辑器。导入记录与恢复版本分开，后者在备份页面下。旧偏好和 isSample 不再控制运行界面，存档仍保留，SampleData 只在测试目标。数字默认看 90 天，底线只取消费观，日常生活自动估算；具体数值和算法属于 Agent 实现选择。现有 Figma、HTML 原型和历史截图均未同步；无 Swift / Apple SDK，布局、底部安全区、VoiceOver、类型检查与五条离线 UI 测试尚未运行验证。


「我」的备份入口现为「备份与同步」，两端共用 LedgerSyncSection / SyncVersionsView：默认仅本机，可用时才显示 iCloud；读取时显示「正在从 iCloud 读取…」。切换遇到不同账本或同步冲突时，展示各自更新时间、版本时间、设备名（如有）、有效记录数、附件数和最多三笔差异，用户明确选定一份；另一份留本机恢复历史。位置切换可取消；未解决的同步冲突保留入口并阻止继续修改。采用现有 Form、Picker、Section 与样式 token，没有新增主入口。当前仅静态核查，未执行两端编译、布局、VoiceOver 或真实 iCloud 冲突验证，外部画布和包未同步。

| 资源 | 权威位置与用途 |
|---|---|
| 颜色、字体、基础视图 | `Sources/YubaiApp/DesignSystem.swift`；暖纸浅/深色语义 token、衬线标题、系统中文正文与 rounded 等宽金额；品牌绿只强调动作和图表 |
| 应用信息架构 | `YubaiApp.swift`；iPhone 两个 tab、Mac 两项侧栏，问余白底部常驻按钮；根视图处理账本锁、文件打开和错误 |
| 现在 | `OverviewView.swift`；来信和管家、保守金额与计算依据、只读待付款及结束安排、导入账单，不展示无依据的「可放心花」承诺 |
| 依据与账户 | `EntryDetailView.swift` / `Editors.swift`；依据打开记录来源，账户编辑和核对保留；不再提供独立账本或关联页面 |
| 整理 | `ImportView.swift`；文件/截图入口 → 账户对应 → 自动归类与少量例外 → 保存结果 → 可直接离开；不强迫逐笔审核 |
| 消费观与问答 | `ProfileView.swift` / `AskYubaiView.swift` / `WishlistView.swift`；消费原则、领域、底线和目标，问答数字、依据、提案与心愿 |
| 我与维护 | `SettingsView.swift`；七个维护入口、导入批次整批撤销、加密备份、可选 iCloud 同步与版本选择、恢复版本、智能与隐私和指南 |
| 云端智能 | `IntelligenceRuntime` + `YubaiCore/Assistant/` 轻量 harness + DeepSeek，唯一模型路径；共用发送前后的快照保护，默认关闭；商户与备注可发送，敏感字段须脱敏，实际覆盖待验证，见 `docs/ASSISTANT.md` |
| 图标 | `Assets.xcassets/AppIcon.appiconset`；本项目生成的深青绿余白符号，不依赖远端素材 |

基础组件包括 `Page`、`Card` / `CardRows`、`AmountLabel`、`HeroCard`、`EntryRow`、`Pill`、`InlineNote`、`EmptyState`、`Toast`、`BrandMark`、`AssistantMark`、`WaterLevelView`、`ChartGrow` 和主次按钮；均有实际调用。使用 SwiftUI 原生表单、导航、选择器、sheet、文件选择、SF Symbols 和 Swift Charts；卡片无描边、阴影和渐变。

大字号下，金额与待付款行通过纵向排布保持可读；已移除旧筛选与示例提示。金额不只靠颜色说明；入/出、性质、未知和异常均有文字。输入错误留在当前编辑页，不丢弃表单。触控、VoiceOver、设备认证与所有尺寸并未穷尽验收，已执行范围见 [验证记录](../docs/VALIDATION.md)。

2026-10-02 按用户明确要求建立 [Figma 全动作派生稿](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=13-3367)。三页分别为全动作 UI/UX、组件与参考、Mac 与共用流程；包含 111 个手机状态、11 个 Mac 画板、42 个本地组件（含 28 个图标）、43 个变量和 8 个文字样式。这些数量属于 1.0，不包含上方七类 2.0 新画板。

原生源码仍是应用实现的权威来源；Figma 是可编辑实现映射与设计说明，没有自动双向同步，也没有因画布排版回写应用。Figma 使用 Noto 字体和 Lucide 图标替代，Apple UI Kit 已检索但无法导入；通用反馈及系统控件以明确标注的示意表达。详细来源、逐动作索引、截图验证和原型播放限制见 [Figma 交付说明](../docs/UI-UX-FIGMA.md)。本轮画图不代表用户已确认最终视觉，不替代当前业务或真机验收。历史 HTML 继续保留为早期行为候选。


2026-10-08 新增[当时版本的浏览基线](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=40-6983)：当时完整页面和状态映射，用于逐页讨论，没有因画图采用改版。保留旧 Figma 页面，尚未同步 2.0。字体、系统控件与交互表达边界见[交付说明](../docs/UI-UX-FIGMA.md)。用户当时确认喜欢风格，但认为信息密度过大；该反馈不等于 2.0 新页面已经视觉验收。

## 历史候选登记（2026-09-20）

以下保留原资料，描述当时阶段；当前采用状态以上文及第 13 票为准。

更新：2026-09-20。状态：基础约定已记录，视觉未定。产品事实以[决策地图](../.scratch/yubai-product/map.md)与子票为准；这里将其连接到设计任务，不替代未解决的业务决策。

## 证据和采用状态

- **已确认约束**：来自地图明确记载的用户决定，可直接约束方案。
- **候选行为/视觉**：Agent 建议或原型演示，可供比较，不等于用户已选定。
- **待决定**：影响资金、数据边界或产品范围的未决问题，回对应子票讨论。
- **已实现/已验证**：分别要求实际代码与对应运行证据，不能从设计稿推断。

目前没有用户选定的视觉方案，也没有委托 Agent 定稿的记录。

## 从真实任务开始

用户场景：每周集中整理多个渠道账单，日常可补充截图或手工记录，希望减少维护负担。朋友按月转来房租分摊、用户按季度付租，使账户余额不能直接代表可花金额。事实来源：[地图 Notes](../.scratch/yubai-product/map.md#notes)。

当前局部任务：**一批记录整理结束 → 用户看摘要，可直接离开，也可补充用途或批量纠正 → 系统显示结果并保留可恢复入口 → 用户不必逐笔审核即可结束这次整理。**

采用边界：自动分类、只询问特别不明的记录或放入其他，是已确认方向；具体摘要、分组补充、返回路径和撤销呈现属于[导入结果原型](../.scratch/yubai-product/issues/12-import-result-prototype.md)候选。导入解析、去重、资金核对与真实保存尚未实现，规则见[多入口记录](../.scratch/yubai-product/issues/04-import-and-reconciliation.md)。

原型输入是合成汇总：3,972 条明确记录、26 条其他支出、2 条用途未知，共 4,000 条，仅展开代表记录。不能据此推断 AI 准确率、耗时、真实数据分布或完整交易处理能力。

### 关键状态与缺口

| 情况 | 当前候选表达 | 需要继续的部分 |
|---|---|---|
| 导入结果可查看 | 摘要后提供返回总览与查看分类入口 | 用户反馈层级是否清楚；真实导入完成判定未定 |
| 普通消费用途不够细 | 留在“其他支出”，按需批量修改 | 初始分类集合与学习规则见[分类票](../.scratch/yubai-product/issues/11-automatic-categories.md) |
| 入账性质/用途不明 | 保留未知，可整组或分别补充，也可稍后再说 | 对可动用资金的影响见[资金票](../.scratch/yubai-product/issues/02-funds-and-obligations.md)，当前不展示推测金额 |
| 没有疑问 | 草稿有“全部明确”的演示切换 | 应用中的空状态文案和后续动作尚未选定 |
| 想纠正或反悔 | 批量改类、补充用途均留内存历史，可撤销 | 跨页面、持久保存和重新导入后的撤销边界未定；现有通用撤销文案待体验时审视 |
| 暂时离开后再回来 | 同一页面会话内可重新查看导入 | 刷新/关闭即重置，真实持久恢复尚未设计 |
| 正在等待、导入失败、部分成功、重复或余额冲突 | 当前原型未覆盖 | 在[完整整理体验票](../.scratch/yubai-product/issues/07-weekly-experience.md)及其依赖规则收敛后补充，不能把失败画成整理成功 |

### 能力范围的读取路线

本轮先整理上述导入结果任务及设计资料。它不等于首版唯一能力，也不自动把下面的能力变成开发清单。

| 用户要完成的事 | 已有依据 | 当前设计状态 |
|---|---|---|
| 了解资金与义务 | [账户、信用负债、基金](../.scratch/yubai-product/issues/02-funds-and-obligations.md) | 计算口径待决定 |
| 维护月收季付的房租 | [房租分摊](../.scratch/yubai-product/issues/03-shared-rent.md) | 分摊、预留与异常场景待决定 |
| 从现在安排未来资金 | [动态资金安排](../.scratch/yubai-product/issues/09-dynamic-money-plan.md) | 方向已确认，规划范围和自动调整边界待决定 |
| 导入、补记并纠正账本 | [多入口记录](../.scratch/yubai-product/issues/04-import-and-reconciliation.md)、[分类](../.scratch/yubai-product/issues/11-automatic-categories.md) | 局部原型候选；全流程未完成 |
| 犹豫购买时寻求建议 | [购买前咨询](../.scratch/yubai-product/issues/05-purchase-advice.md) | 用户主动发起已确认，依据与缺信息处理待决定 |
| 找到值得调整的消费 | [消费回顾](../.scratch/yubai-product/issues/06-spending-review.md) | 候选分析与反馈方式待决定 |

首版取舍由[首版边界票](../.scratch/yubai-product/issues/08-first-release-boundary.md)决定。用户已否定把固定周期、逐笔审核、人物编号维护作为产品前提；代用户执行真实转账和投资交易在现有产品范围之外。更完整的成熟产品能力全景留到参考调查阶段补齐。

## 指导取舍的原则

| 保护的体验 | 因此怎样设计 | 适用边界与来源 |
|---|---|---|
| 一次整理可以轻松结束 | 默认自动归类，普通细类未知允许归其他，纠正入口按需展开 | 不把性质不明当成确定收入；方向来自地图，具体分组与退出方案待反馈 |
| 理解钱实际能做什么 | 区分账面进出、用途与未来义务；待规则明确后展示依据 | 不自行编造可花金额公式；[资金票](../.scratch/yubai-product/issues/02-funds-and-obligations.md)未解决 |
| 资金安排跟着现实变化 | 从当前时间和已知付款日期推演，保留实际租金日期 | 固定账单导出区间仍可用于筛选；不因此固定资金管理周期 |
| 用户容易纠正系统 | 建议展示影响范围、支持批量修改和撤销，金额由用户修正 | 撤销持久性仍是候选；AI 不以“整理”名义改金额 |
| 补充的是钱的用途 | 用自然语言问这笔钱做什么，允许少量未知 | 必要字段见[云端边界票](../.scratch/yubai-product/issues/01-cloud-data-boundary.md)，姓名留本地的方向不代表具体外发字段已获批准 |

## 布局与视觉的当前依据

目标是个人自用的 iOS 应用，来源为已有产品地图；本轮未选择技术栈。现存 HTML 用左侧手机式页面展示结果，右侧展示演示状态和场景引导。右侧控制台帮助讨论，不属于正式应用的信息架构。

候选主任务依次呈现整理结果、分类摘要、少量未知用途、按需纠正与离开入口；原型还包含总览占位、分类概览、分组补充与批量修改。未决定底部导航、完整首页、深色模式、正式字号或品牌色。后续做移动端方案时，以实际设备尺寸和真实长度中文观察层级、触控与可读性。

现有 HTML 声明焦点样式、文本状态和 `aria-live`，只是源码证据；实际键盘、读屏、对比度与布局尚未验证。正式稿需要让未知、选中、成功与失败可由文字理解，并检查放大字体与关键动作是否可达。此为设计建议，不是已通过的无障碍验收。

## 样式与组件登记

唯一候选数值来源：[原型内嵌 CSS](../.scratch/yubai-product/prototypes/import-result.prototype.html)。本轮核对了源码，没有提取第二份 tokens.json；所有颜色、尺寸和字体仍为候选。原型之外尚无应用样式目录或生产组件库。

| 已有 CSS 名称/选择器 | 用途 | 来源与采用状态 |
|---|---|---|
| `--ink`、`--muted` | 主文字、次级说明 | 原型 `:root`；候选，正式数值未选 |
| `--green`、`--pale` | 主动作、选中及浅色提示底 | 同上；候选，尚未建立语义状态色体系 |
| `--line`、`--paper` | 分隔线、页面底 | 同上；候选 |
| `body`、`h1/h2/h3`、`.small` | 系统字体栈与文字层级 | 原型样式；未做 iOS 动态字体映射 |
| `.phone`、`.section`、`.choices` | 页面容器、分区、选项布局 | 原型样式；演示外框不能直接升级为应用组件 |

| 候选组件及源码入口 | 已出现的行为/状态 | 正式化前的缺口 |
|---|---|---|
| 摘要 `metrics()` / `.metrics` | 明确、其他、未知三组计数 | 标签是否易懂、窄屏与大字体表现 |
| 主动作 `button.primary` | 返回结果、返回总览等 | 明确页面主次与等待/失败状态 |
| 用途补充 `renderApp()` 的 `questions` 分支 | 整组选择、分别选择、稍后再说 | 分组依据、影响范围和未知对资金的含义 |
| 分类修改 `other` 分支 | 26 笔合成记录批量修改、撤销 | 真实筛选、个别排除、持久历史与反馈文案 |
| 反馈 `#status`、撤销历史 `ImportDemo` | 内存状态更新、文本提示 | 应用内反馈位置与持久恢复；控制台不可直接照搬 |

提取条件：视觉被用户选定或在明确委托范围内定稿，重复样式和组件已有实际用途。届时保留现成体系；若采用 CSS 则以工程样式为权威，若采用原生平台则登记实际样式文件。按用途命名，记录来源、派生画布及同步方向；无需求时不预建多主题或完整组件库。

## 下一轮设计与实现交接

继续可见设计时，先读取本文件、入口和原型记录，沿用本任务与合成数据边界，补足相关参考后制作或调整候选。按[启动协议](../产品设计启动协议.md)默认使用 Open Design，首次生成前落实模式与额度说明；已有选定模式时沿用。

只有选定方向后，才将其升级为正式视觉资源。交接须同时指向：本轮真实任务、选定画面、关键状态、样式来源、可复用组件和未决业务行为。现在能交接的是资料与局部候选，尚不能宣称资金计算、账单导入或正式 UI 已可直接实现。

本轮验证范围：文件存在、引用和来源一致、原有记录与原型保留。历史静态检查结论以原型票为准；本轮未运行原型或真实业务测试，也未设置使用成效指标。
