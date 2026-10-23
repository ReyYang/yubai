# 第十五轮「帮你省钱」界面交付

当前合并状态见 [少写字与帮你省钱合并核对](MERGE-NO-EXPLANATORY-COPY.md)：保留本页全部功能、拆分与夹具，采用 V16 文案；下列 V15 原始邀请句与“入口仅禁用”的历史描述由合并记录覆盖。

2026-10-23，`feat/butler-saving-core`。按 owner 指定的 12 张 V15 HTML、NOTE.txt、DS-README.md 实现；原稿位于 设计稿画布「第十五轮 · 帮你省钱」，保持原样。没有调用实网 API，没有 git commit／推送。

## 实现

| 设计稿 | 接线 |
| --- | --- |
| V15-Judge-Ask | 最多三题，每题单选；按题序拼接选项，发一条 user 消息；也可直接给结论。过往题卡不可重复提交；记忆继续用已记下／撤销。 |
| V15-Judge-Wait／Buy／Skip | 三种结论＋一句理由，钱的边界事实标签；原三项观察进入明细页。按金额加入 0／3／7 天心愿，按钮后带实际天数；0 天不加天数。买下和坚持购买均打开现有手动记一笔，预填用途、主项和金额，不再追问。采用天数按钮，没有另启发薪日按钮。 |
| V15-Wishlist | 累计省下、本月增量；到期卡调用 answerCooldown；未到期状态带剩余天数。手动放弃也保存 droppedAt、清冷静期和旧卡。 |
| V15-Letter | 来信正文之后显示成对省钱格，有累计或本周省下时才出现；订阅用来信中保存的候选，调用 SubscriptionCheck.answer；已答／停用／变更保留状态。原有图、三个数字、记忆和提醒开关保留，省钱数字不再混入原三个格；末行进入带来信正文上下文的再聊。 |
| V15-Profile | 页底始终有品牌浅底再聊行，未配云端时禁用；克制条使用 count／amount 的较高比例，≥80% 琥珀色。手动编辑领域保留已有小项匹配。 |
| V15-Revisit | 同一 ProfileConversationView 按已有消费观或入口上下文进入 revisit；三枚起头芯片直接发出；冷启动三圆点、再聊无进度；思考只画水波与三个点。共享 ChatInputBar，立即清空／显示用户气泡，失败回填，重试替换失败轮次。 |
| V15-Entries | 来信末行、心愿有点后悔后的邀请、克制超额的调额度，统一进入 ProfileConversationView，分别传 weeklyLetter／wishRegret／restrainExceeded。心愿邀请可在本次页面收起。 |
| V15-Restrain | 还能花下方、需要留意之前最多一条 near；点进消费观；原 near 管家卡在显示前过滤，over 保留原卡并添调额度。尊重该主题的静音／收起。 |
| V15-Entry-Sub | 主项 · 小项＋水波署名；只列当前主项小项，右上换主项。选择后原子保存主项与小项、记忆及 subcategoryUserEdited；关联退款编辑原支出并同步退款。记一笔不增加小项。 |
| V15-Insights-Sub | 主项进入两级明细：合计、实际支出／收入笔数、占比、和上月比、小项条形与克制标记；未归小项并入其他，能继续打开原账目。首页合并的其他扇区保留原明细入口。 |

主项详情沿用洞察选中的时间范围：当前月标题「X · 本月」，历史月显示月份，其余显示日期范围；比较基准为该范围起始月的完整上月。退款继续按 Core 净支出口径，笔数不把退款额外计成消费。

颜色、字体、间距均复用 DesignSystem。26px 宋体结论取最近的现有 `YubaiFont.lead`（22px）；40px 主金额取现有 `amountInput`（38px，取整显示）；没有添加颜色或字体 token。布局使用原有原生 sheet／导航、卡片、按钮和金额隐私行为。

另一个分支负责的句子均保留，只有被整体替换的旧 AskPurchaseCard 中消费观缺失说明随旧块移除；ProfileConversationView 的两个旧提示按 owner 明确例外替换。

接线发现独立退款的小项选择被 `nature.inflow` 当作收入，补一处 Core 校验：退款使用支出分类；补对应回归测试，不改其资金流向或计算。

## 本轮文件

新增 App 文件，均已登记到 Xcode App target（没有放进 Widget target）：

- [SavingPurchaseViews.swift](../Sources/YubaiApp/SavingPurchaseViews.swift)：追问、购买结论及三项观察明细。
- [SavingViews.swift](../Sources/YubaiApp/SavingViews.swift)：统一再聊入口、省钱、冷静期、订阅、克制条与卡片显示适配。
- [SubcategoryViews.swift](../Sources/YubaiApp/SubcategoryViews.swift)：分类行、小项选择、小项洞察及原始账目。

修改 App 文件：

- [AskYubaiView.swift](../Sources/YubaiApp/AskYubaiView.swift)：分派追问／结论，移除旧购买卡。
- [WishlistView.swift](../Sources/YubaiApp/WishlistView.swift)：省下／到期／剩余天数／放弃日期／后悔邀请。
- [ButlerViews.swift](../Sources/YubaiApp/ButlerViews.swift)：来信与超额入口，近限额卡显示适配。
- [ProfileView.swift](../Sources/YubaiApp/ProfileView.swift)：常驻入口、克制条及保存小项匹配。
- [ProfileConversationView.swift](../Sources/YubaiApp/ProfileConversationView.swift)：再聊、起头芯片、圆点与滚动、记忆撤销、共享输入条。
- [OverviewView.swift](../Sources/YubaiApp/OverviewView.swift)：近限额一行。
- [EntryDetailView.swift](../Sources/YubaiApp/EntryDetailView.swift)：两级分类行。
- [InsightsView.swift](../Sources/YubaiApp/InsightsView.swift)：主项进入小项页。

其他：

- [Subcategories.swift](../Sources/YubaiCore/Subcategories.swift)：退款的小项有效性修正。
- [SubcategorySavingTests.swift](../Tests/YubaiCoreTests/SubcategorySavingTests.swift)：新增独立退款的小项、手改保护和记忆回归。
- [project.pbxproj](../Yubai.xcodeproj/project.pbxproj)：按现有生成器登记三个 App 文件。
- 本文、[设计入口](../.design-meta/README.md)、[设计采用记录](../.design-meta/DESIGN.md#2026-10-23--第十五轮帮你省钱界面)、[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-23--第十五轮帮你省钱界面owner-指定稿)、[地图](../.scratch/yubai-product/map.md)：同步本轮已采用范围与验证边界。

## 新增可见文字逐条清单

`{…}` 是来自账本／当前选择的实际内容，不是界面上的占位文字。下列包括新视图中复用的既有文字；完整复用的记一笔、错误弹层及消费观确认卡内部既有文案没有新增。

| 可见文字或模板 | 类别 |
| --- | --- |
| 余白 · 该不该买 | 标题 |
| 余白 · {物品名称} | 标题＋事实 |
| 买吧 | 标题（结论） |
| 等等再说 | 标题（结论） |
| 先别买 | 标题（结论） |
| {结论的一句理由} | 数字和事实，submit_verdict 的已校验理由 |
| {bound_reason} | 数字和事实，仅钱的边界标签 |
| {问题序号} | 数字 |
| {购买问题题目} | 控件（单选题题目） |
| {购买问题选项} | 控件（芯片） |
| 就这样回答 | 控件 |
| 直接给结论 | 控件 |
| 放进心愿单 | 控件 |
| 放进心愿单 · {N} 天后再问我 | 控件 |
| 先放进心愿单 | 控件 |
| 我还是要买 | 控件 |
| 买了，记一笔 | 控件 |
| 已放进心愿单 | 状态 |
| 明细 | 标题／控件 |
| 明细 · 买了以后还能花 {金额} | 控件＋事实 |
| 明细 · {N} 笔 | 控件＋数字 |
| 付得起吗 | 标题（明细分组） |
| 和你平时比 | 标题（明细分组） |
| 和你在乎的比 | 标题（明细分组） |
| 买了以后还能花 {金额} | 数字和事实 |
| 过去 90 天，同类消费平均一次 {金额} | 数字和事实 |
| 你写过「{原话}」 | 事实 |
| 没有记录 | 状态 |
| 已记下：{记忆内容} | 状态，复用 RememberedRows |
| 撤销 | 控件，复用 RememberedRows |
| 没买，省下的 | 标题 |
| {累计省下金额} | 数字 |
| 这个月 +{省下金额} | 数字和事实 |
| 冷静了 {N} 天 | 状态＋数字 |
| {物品名称} {金额}，还想要吗？ | 标题＋事实；隐藏金额时省略金额 |
| 当时说「{心愿用途}」 | 事实 |
| 还想要 | 控件 |
| 不要了 | 控件 |
| 冷静中 · 还有 {N} 天 | 状态＋数字 |
| 放了 {N} 天 | 数字和事实 |
| 买了 {N} 件 · 划掉 {M} 件 | 控件＋数字 |
| {心愿名称} {金额} · 有点后悔 | 事实／状态 |
| 要把这次的感受写进消费观吗？ | 标题，设计稿指定 |
| 和余白说说 | 控件 |
| 不用了 | 控件 |
| 这周省下 | 标题 |
| 一共省下 | 标题 |
| {本周／累计省下金额} | 数字 |
| 这些还在用吗？ | 标题 |
| {订阅名称} | 事实 |
| {订阅金额} | 数字 |
| 每月 {D} 日 | 事实 |
| 每周{星期} | 事实 |
| {周期} · {月日} | 事实（每季／每年等） |
| {周期} | 事实（没有日期时） |
| 还在用 | 控件／回答后状态 |
| 停掉 | 控件 |
| 已停掉 | 状态 |
| 已回答 | 状态 |
| 已变更 | 状态 |
| 想聊聊这周吗？ | 控件 |
| 和余白聊聊 | 标题／控件 |
| 最近花钱的感觉变了 | 控件（起头芯片） |
| 加一条想克制的 | 控件（起头芯片） |
| 看看这个月我做得怎么样 | 控件（起头芯片） |
| 还没配密钥 | 状态（对话配置失效） |
| 调一下额度 | 控件 |
| {领域名称} · 本周第 {N} 次 | 数字和事实 |
| {领域名称} · 本月 {金额} | 数字和事实 |
| 你写的最多 {N} 次 | 数字和事实 |
| 你写的最多 {金额} | 数字和事实 |
| 分类 | 控件（分类行） |
| {主项} · {小项} | 控件／事实；未归小项时只显示主项 |
| {主项}里的哪一类 | 标题 |
| 换主项 | 控件 |
| {主项名称} | 控件（换主项菜单） |
| {小项名称} | 控件（选择芯片、条形行）／原账目页标题 |
| 其他 | 标题／控件（未归小项与既有其他合并） |
| {主项} · 本月 | 标题 |
| {主项} · {N}月 | 标题（历史月） |
| {主项} · {日期范围} | 标题（其他时间范围） |
| {起始月日} – {结束月日} · {N} 笔 | 数字和事实 |
| {分类合计金额} | 数字 |
| 占支出 {N}% | 数字和事实 |
| 占收入 {N}% | 数字和事实 |
| 和上月相同 | 事实 |
| 比上月多 {金额} | 数字和事实 |
| 比上月少 {金额} | 数字和事实 |
| 按小项 | 标题 |
| 想克制 | 状态 |
| {小项金额} | 数字 |
| {小项占比}% | 数字 |
| — | 状态（无有效占比） |
| 金额已隐藏 | 状态 |
| •••• | 状态（金额隐藏） |

复用对话的「余白」、输入条占位、用户与助手真实消息；没有新增固定开场说明句。思考三个点、冷启动三个圆点和小项水波均是图形；「余白归的」只用于 accessibilityLabel，不是可见副标签。动态问题、理由、记忆、原话和错误原因直接来自现有 Core 返回，不填入设计稿的示例事实。

## 验证

```sh
export PATH=/opt/swift-rootfs/usr/bin:$PATH
export XDG_CACHE_HOME=/tmp/yubai-swift-cache
export CLANG_MODULE_CACHE_PATH=/tmp/yubai-clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/yubai-swift-module-cache
export YUBAI_LIVE_EVAL=0
swift build --target YubaiCore && swift test
```

构建通过；449 项测试，445 通过、4 项原有实网 opt-in 跳过、0 失败。新增 1 项退款回归，已有 448 项保留。

全部 App Swift 文件通过以下两个目标的语法解析；这是解析，不是 SwiftUI 类型检查：

```sh
swiftc -frontend -parse -target arm64-apple-ios26.0 Sources/YubaiApp/*.swift
swiftc -frontend -parse -target arm64-apple-macosx14.0 Sources/YubaiApp/*.swift
```

工程三文件引用、现有 token 与分支保护文案静态检查、`git diff --check` 通过。没有运行实网 API，也没有创建提交。

只能在 Mac／Xcode 继续验证：Apple SDK 下的完整 iOS／macOS 类型检查与构建；sheet／导航与输入焦点；多行、键盘、发送后即时气泡、失败回填和编辑后重试；三种再聊上下文的开场；选择后单次提交；购买记账预填；冷静期／停订／撤销的实际联动；大字号、浅深色、VoiceOver、Reduce Motion 和与 390pt 原稿的设备视觉比对。原稿／Figma／截图／分发包未更新，不把 Linux 结果当作设备验收。

## 2026-10-23 · PR #34 编译修复与截图夹具

owner 在 iPhone 17 Pro 模拟器／iOS 26 SDK 真编译发现的小项页错误：补齐 `.setCategory(entry:category:)` 标签，把网格选择项拆为 `SubcategoryChoiceChip`，将选择状态、主项与小项列表的类型写明。逐个通读本轮三个新 App 文件及八个接线文件，核对 Core 的 public 访问、参数标签、可选输入；将购买问题／选项／明细、小项汇总／行、冷静期卡、订阅行、近限额筛选、聊天气泡、领域行、来信数字、洞察分类导航／扇区和现在页账单等拆为独立视图或计算属性。保留原文案、token、布局、状态与交互；没有新增产品说明文字。

按 owner 提供的 2026-10-23 官方原文修正默认模型和内置列表：`deepseek-flash`、`deepseek-v4-pro`；`deepseek-chat`／`deepseek-v4-flash` 映射到 `deepseek-flash`，`deepseek-reasoner` 映射到 `deepseek-v4-pro`，未知名保留。模型菜单的说明键与测试同步；本轮没有重新联网抓取或调用 API。

本次修改文件：

- App：`SavingPurchaseViews.swift`、`SavingViews.swift`、`SubcategoryViews.swift`、`AskYubaiView.swift`、`ButlerViews.swift`、`EntryDetailView.swift`、`InsightsView.swift`、`OverviewView.swift`、`ProfileConversationView.swift`、`ProfileView.swift`、`WishlistView.swift`、`CloudAssistantViews.swift`、`UITestSupport.swift`（均位于 `Sources/YubaiApp/`）。
- Core：`Sources/YubaiCore/DeepSeekClient.swift`。
- 测试：`Tests/YubaiCoreTests/DeepSeekCloudTests.swift`、`Tests/YubaiCoreTests/SavingConversationTests.swift`、`Tests/YubaiUITests/AppFlowTests.swift`。
- 记录：本文、`.design-meta/README.md`、`.design-meta/DESIGN.md`、`.scratch/yubai-product/issues/13-complete-personal-release.md`。

### 模拟器启动

只在 **Debug + iOS 模拟器** 启用，必须同时提供启动参数 `--test-ledger <UUID>` 和环境变量 `YUBAI_UI_TEST_SCRIPT=<脚本名>`；缺一、UUID 无效或脚本不在白名单时不启用。所有数据均为合成数据／设计示例，云端请求走现有 `UITestTransport`，不需要密钥。

Xcode Scheme › Run › Arguments：加入 `--test-ledger`、一个新 UUID，Environment Variables 加入对应的 `YUBAI_UI_TEST_SCRIPT`。合入 V16 截图复查修正后，还须设 `YUBAI_UI_TEST_CONFIGURED_KEY=1` 显式模拟已配密钥；设为 `0` 可验无密钥禁用态，未设置时沿用真实钥匙串状态。此覆盖只对通过上述隔离门槛的 Debug 模拟器脚本生效，不写入钥匙串。可附加 `-AppleLanguages (zh-Hans) -AppleLocale zh_CN` 固定中文。每次要重置截图数据就换 UUID；同一 UUID 重启保留修改，不覆盖已有测试账本。

已安装 Debug App、模拟器已启动时也可运行（Bundle ID 如有本机配置覆盖，替换成实际值）：

```bash
SIMCTL_CHILD_YUBAI_UI_TEST_SCRIPT=judge-ask \
SIMCTL_CHILD_YUBAI_UI_TEST_CONFIGURED_KEY=1 \
SIMCTL_CHILD_DEEPSEEK_API_KEY= \
xcrun simctl launch --terminate-running-process booted app.yubai.personal \
  --test-ledger "$(uuidgen)" -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
```

只替换上例中的脚本名；新脚本及入口如下：

| 脚本名 | 打开路径／内容 | 截图测试方法（`AppFlowTests`） |
| --- | --- | --- |
| `judge-ask` | 顶栏问余白，发送「想买双徒步鞋 899，该不该买？」；真实执行 `judge_purchase` 后执行 `ask_purchase_questions`，三题与选项逐字采用 V15-Judge-Ask；选完发送或直接给结论可继续得到 wait | `testJudgeAskScreenshotFixture` |
| `judge-wait` | 同上发送鞋的问题；真实执行 `judge_purchase` → `submit_verdict(wait)` | `testJudgeWaitScreenshotFixture` |
| `judge-buy` | 同上；`submit_verdict(buy)`，带运动装备消费观与旧鞋磨脚的合成记忆 | `testJudgeBuyScreenshotFixture` |
| `judge-skip` | 问余白发送「想买个 1,899 的降噪耳机，该不该买？」；账户 3,029、下月 1 日房租 1,750，还能花 1,279，小于购买金额；本机只允许 skip，缺口 620 | `testJudgeSkipScreenshotFixture` |
| `wishlist-cool` | 我 › 心愿单；降噪耳机 1,899 已冷静 7 天到期，徒步鞋 899 剩 2 天，咖啡机 2,480 放了 12 天；合成投影仪已划掉、省下 1,299，合成机械键盘买了 31 天待回访 | `testWishlistCoolScreenshotFixture` |
| `letter-saving` | 我 › 每周来信 › 当期来信；周一至周三也可从现在页来信胶囊打开。通过真实 `WeeklyLetter.candidate` 生成本月第一封；本周和上一完整周均有划掉的心愿，视频会员 25、网盘 12、健身 App 30 为月度支出，带三项「这些还在用吗？」；不静音来信 | `testLetterSavingScreenshotFixture` |
| `profile-revisit` | 现在页 near 行，或我 › 我的消费观；外卖每周最多 3 次且已 3 次，数码电器每月 800 已花 420；另有愿意多花的、原则和三条记忆。页底「和余白聊聊」可打开再聊，开场及发送后的回复均先走真实 `get_profile` | `testProfileRevisitScreenshotFixture` |
| `subcategory` | 洞察 › 购物 › 运动户外可看购物小项和原账目；部分已有余白小项、部分没有。记录详情走现有入口：我 › 心愿单 › 买了 1 件 › 购买记录；「徒步鞋 · 京东」899 位于购物 · 运动户外，可打开分类选择 | `testSubcategoryScreenshotFixture` |

购买理由采用设计稿的句子或原句片段：wait 取第一句，buy 取「旧跑鞋你也说磨脚了。」；skip 取第一句，按模拟器当前月更新房租日期，并为金额补「元」，满足现有单句／60 字／金额校验。没有放宽 Core 边界，也没有绕过工具直接塞结论。夹具已注明／引用真实存在的合成记忆 ID。

可在 Xcode Test Navigator 单独运行上述方法，或使用 `xcodebuild test -project Yubai.xcodeproj -scheme Yubai -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:YubaiUITests/AppFlowTests/testJudgeAskScreenshotFixture`（其余方法替换末段）。测试自动设置 UUID、脚本和中文，并把截图附件保留到 xcresult；本机 scheme／模拟器名称按实际配置选择。

### 本次验证

- 指定 Linux `swift build --target YubaiCore && swift test` 退出 0：449 项，445 通过、4 项原有实网 opt-in 跳过、0 失败；运行时明确关闭 `YUBAI_LIVE_EVAL`，没有访问真实服务。
- 全部 App 文件通过 `swiftc -frontend -parse` 的 iOS 26 模拟器 Debug、iOS 26 设备 Debug／Release、macOS 14 条件语法检查；UI 测试通过 iOS 26 模拟器语法检查。
- 临时 Linux 检查程序只在 `/tmp` 去除夹具外层编译条件，以实际 YubaiCore 模块对夹具做类型检查，并离线运行全部 8 个脚本：三题及续答、wait／buy／skip 工具链、钱不够边界、首封来信三项订阅／省钱、near 与再聊两轮、冷静期和小项数据均通过。源码中的 Debug＋模拟器限制保留。
- 保留原 47 个 UI 测试方法，新增 8 个截图流程；没有 Xcode／Apple SDK，尚未执行 SwiftUI 类型检查或 UI 测试，仍需 Mac 真编译及截图验收。`git diff --check` 通过，无提交／推送。设计原稿、Figma、分发包保持原状。
