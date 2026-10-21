# 余白 · 设计约定与资源登记


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
