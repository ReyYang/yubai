# 任务：余白「快速记账入口」（第九轮设计稿，用户已确认）

仓库 /home/user/yubai，分支 feat/quick-capture-entries（基于 main）。用中文写注释/文案，代码风格和周围代码一致（紧凑、单行多语句的写法照旧）。

## 设计依据（必须照做）
- 画板：本目录 V9-Quick-*.html（Lock、Home-Widget、Control、Siri-Snippet、Pay-Auto、Screenshot、Add-Prefilled、Me-Quick）。
- 设计系统规则：DS-README.md 的「系统入口」一节和「动效」一节。只用 SwiftUI / Apple 原生框架（AppIntents、WidgetKit、UserNotifications、Vision），不加任何第三方包。
- 文案词汇：主数字一律叫「还能花」；分类没把握的自动记账标「没分类」。不要出现「自在支配」「可支配」「保守可动用」「待整理」等词（本次新代码里）。界面文案不解释余白怎么工作，只写事实/数字/下一步。
- 动效只用已有 YubaiMotion / 动效表里的，不新增。

## 要做的

### Core（Sources/YubaiCore，必须有 Linux 可跑的单元测试，放 Tests/YubaiCoreTests/QuickCaptureTests.swift）
1. QuickCapture：把一句话（如「午饭 32」「咖啡 18 和面包 12」「打车24」）在本机解析成 1..n 笔草稿（金额、用途、按 ManualBookkeeping.guessCategory 猜分类、默认账户）。复用现有本机金额解析（AskYubai 里 parsedEntries 那套），不要另写一套不一致的解析；不发云端。只有金额没有/解析不出时返回「需要追问」状态。
2. Apple Pay 交易记账：输入 商户名、金额字符串（快捷指令钱包触发器给的，如 "¥18.00"、"CN¥18.00"、"18.00"）、卡名、时间 → 一笔支出。卡名→账户映射、商户→分类规则存在账本偏好里（Codable，旧账本解码兼容，默认空）。没有规则且猜不出分类时放「其他支出」并带「没分类」标记（可用 classificationReason 或新字段，Codable 兼容）。source 记为「Apple Pay」，sourceIdentity/externalID 用于去重：同卡同商户同金额 2 分钟内重复触发只记一次。
3. 撤销：给出按 entry id 撤销（软删除，与现有删除一致）的操作；「以后『商户』都记到 分类」写规则的操作。
4. 截图多笔：把 ImportView 里 Vision OCR 后的单笔启发式抽到 Core 可测的纯函数（输入识别出的文字行，输出 0..n 笔草稿），支持支付成功页和账单列表多笔；Vision 调用本身留在 App 侧。
5. 记账后「还能花」金额用现有算法（QuickEntryView 里 previewAvailable 用的那套）提供给 snippet/通知/小组件快照。
6. 小组件快照：一个小的 Codable 结构（还能花、今天笔数、今天合计、常记的三项 用途+金额+分类），由 Core 从账本算出。

### App（Sources/YubaiApp + Xcode 工程）
1. App Intents（放在 App target，能在不打开 App 时运行并写账本；需要与 AppStore 同一套存储/锁逻辑，账本被面容锁锁住时仍可记，但 snippet 不显示金额以外的隐私信息——如果现有存储做不到后台写，就 openAppWhenRun 并说明原因）：
   - 记一笔（参数：一句话文本，可选）→ 直接写入，返回 Siri-Snippet 画板样式的 snippet（已记下、用途+金额、分类·账户·时间、还能花、改一下/撤销）；缺金额时追问「多少钱，花在什么上？」。
   - Apple Pay 记一笔（参数：商户、金额、卡名）→ 直接写入并发本地通知（Pay-Auto 画板：标题余白，正文「已记下 商户 ¥金额 · 分类 · 账户」，副行「还能花 ¥X · 轻点改一下」；通知动作「改一下」「撤销这笔」）。
   - 打开记一笔（可带分类+金额预填）、截图记（参数：图片文件；无参数时从最近截图/剪贴板取不到就打开导入）。
   - AppShortcutsProvider，中文短语如「用余白记一笔」「余白记一笔」「余白截图记」。
2. 通知点击/改一下 → 打开 Add-Prefilled 画板的「改一笔」：顶部来源胶囊「来自 Apple Pay · 卡名 · 时间」，底部「以后「商户」都记到 分类 · 好」，按钮「删除这笔」「好了」。基于现有 EntryEditView 改，不另起一个编辑页。
3. 截图记结果：Screenshot 画板（逐笔可勾掉，「记下 N 笔」「打开核对」→ 现有导入核对）。
4. 「我 › 快速记账」页（Me-Quick 画板），从 SettingsView 进入；含卡→账户、商户→分类两个列表页（简单的增删改）。近 7 天笔数与「没打开 App」笔数可由 source/记录方式统计。
5. 账目列表里「没分类」的那笔显示一个小标签，点进改一笔可归类。
6. Widget Extension 新 target（YubaiWidgets）：锁屏 accessoryCircular（记一笔、截图记）、accessoryRectangular（还能花+今天笔数）、主屏 systemSmall、systemMedium（常记三项+加号），以及 iOS 18+ ControlWidget（记一笔、截图记）。小组件点击全部是打开 App（OpenIntent 或 widgetURL 深链），不在扩展里写账本。显示数字依赖 App Group 共享快照：App Group 标识放 xcconfig 开关（类似 Config/iCloud.xcconfig 的做法），默认关闭；关闭时小组件只显示按钮、不显示数字。App 在账本变化时写快照并 WidgetCenter.reloadAllTimelines()。
7. 深链：yubai://add?category=&amount=&purpose=、yubai://capture；在 YubaiApp 的 onOpenURL 里处理（保留现有文件 URL 逻辑）。
8. Xcode 工程（Yubai.xcodeproj/project.pbxproj 是手写的）：正确加入新源文件、新 widget extension target（嵌入 App，bundle id app.yubai.personal.widgets，iOS 26），Info.plist 需要的键（NSExtension 等）。注意签名用 Automatic，不写 team。

## 约束
- 不要碰 RootView 的 TabView 结构；记一笔 sheet（QuickEntryView）的日期选择器和分段控件另一个分支在修，尽量不改 QuickEntryView 内部布局，只加预填入口。
- 不运行任何会产生费用的东西；不 git push。完成后在本地提交（作者已配置，提交信息中文、不加任何 Co-Authored-By/Claude 字样），可分 Core 和 App 两个提交。
- 验证：运行 `swift build` 和 `swift test`（Linux，Swift 已装在 PATH 中；若无，运行 scripts/install-linux-swift.sh）。App/Widget 代码在 Linux 编不了，请格外仔细地检查 API（iOS 26 SDK），用 #if os(iOS)/canImport 保护。
- 最后输出：改了哪些文件、测试结果、免费 Personal Team 下有风险的点。
