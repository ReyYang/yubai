# 快速记账 · 第九轮

2026-10-21，分支 `feat/quick-capture-entries`。选定稿与用户任务原文保存在 [.design-meta/mockups/quick-capture-v9](../.design-meta/mockups/quick-capture-v9/README.md)。本轮不改 TabView 结构；记一笔 sheet 只加预填参数和截图导入载荷，日期选择器及分段布局沿用原实现。

Core 的 `QuickCapture` 共用 `EntryAmountParser`、`ManualBookkeeping.guessCategory/defaultAccount` 和 `Finance.funds`。没有云端解析或新增包。`Preferences.quickCapture` 保存卡名到账户、商户到分类的映射，旧账本缺失时为空。`Entry.quickCapture` 是可选的来源资料；旧记录仍能解码。Apple Pay 记录保留 source、卡、商户、外部身份及原始时间；同卡／商户／金额在 120 秒内重复触发不重复入账，撤销后的记录也保留去重依据。没有分类规则或本机猜测时为「其他支出」，`classificationReason` 为「没分类」。

`ReceiptTextParser` 是共用的纯文字 OCR 启发式：支付成功页、金额与用途分行、账单多行、相同金额的多笔记录、正负号、日期与时间、收入和合计／余额过滤。Vision 留在 App。它不能保证所有机构截图都识别正确，截图记提供逐笔勾选及现有「打开核对」入口；首次截图原件和导入原件继续保存在账本附件中。

## 入口与存储

- Siri／快捷指令：「用余白记一笔」「余白记一笔」「余白截图记」。缺金额时系统追问「多少钱，花在什么上？」；结果使用 iOS 26 `SnippetIntent`，渲染只读，按钮按 entry id 改或软删除，不重复执行记账。
- Apple Pay：先在「我 › 快速记账」设置卡和账户，按说明在系统快捷指令建立钱包「交易」自动化，添加「Apple Pay 记一笔」，绑定商户、金额和卡，付款时间可选。没有启用 Apple Pay 商户收单能力，也不访问钱包历史。
- 通知：在快速记账设置主动开启本地通知权限；自动化执行时不弹权限框。点击／「改一下」进入既有 EntryEditView 的来源状态；「撤销这笔」按 id 软删除并移除通知。拒绝通知权限时仍可保存账目。
- 截图记：接受快捷指令图片文件；没有文件时先取剪贴板图片，再尝试已经获准访问的最近截图（不下载 iCloud 图片、不主动申请相册权限），否则进入导入。轻点背面可绑定系统快捷指令「截屏 → 余白截图记」，把当前截图作为文件传入，避免读到旧图。
- 深链：`yubai://add?category=餐饮&amount=32&purpose=午饭`、`yubai://capture`；通知编辑另有 `yubai://entry?id=UUID`。保留原有文件 URL 导入与备份恢复。锁账本时先保留目的地，解锁后展示。

App Intents 只编入 App target，没有账本写入扩展；`openAppWhenRun = false` 的两个记账动作和撤销在 App 进程里使用同一 `AppStore.shared`、MainActor、`LedgerRepository`、文件保护、恢复历史和 iCloud 待上传标记。没有另外创建账本副本；本机保存也启用最后读取版本检查。同步忙或版本待选择时明确失败，保留原账本；设备重启后的首次解锁之前可能无法访问受保护文件。Face ID 账本锁只对这些专用记账／撤销操作放行，普通编辑仍需解锁。后台操作会清除整本账本的旧撤销快照，避免之后的普通撤销覆盖新账。

启用账本锁时 snippet 和通知只显示金额与操作；隐藏金额时金额也遮住。不把用途、商户、卡名、分类或账户渲染到受保护的结果中。小组件从来不读取完整账本。

## 可选 App Group

`Config/AppGroup.xcconfig` 默认 `YUBAI_APP_GROUP = NO`，iCloud 仍独立默认关闭。此时小组件、锁屏和控制中心仅提供打开 App 的入口，不显示数字或常记用途。

获得可签 App Groups 的团队后，可在不入库的 `Config/Local.xcconfig` 写：

```xcconfig
YUBAI_APP_GROUP = YES
YUBAI_APP_GROUP_IDENTIFIER = group.app.yubai.personal
```

在 App 与 `app.yubai.personal.widgets` 两个标识都关联同一 App Group，并选择本机团队。仓库保持 Automatic，不写 DEVELOPMENT_TEAM。iOS entitlement 按 iCloud／App Group 四组合选择；macOS 沿用原组合，不启用本轮 iOS 小组件权限。

App 在账本变化时原子写 `quick-capture.json`，随后 reloadAllTimelines；快照仅含还能花、今日统计和最多三项常记用途／金额／分类。账本锁或隐藏金额时移除快照。扩展读不到共享容器、读取失败或跨日时只显示入口；时间线在午夜去掉过期数字。刷新频率最终由 WidgetKit 控制，不能视作实时余额。

`YubaiWidgets` target（iOS 26）包含记一笔 accessoryCircular、截图记 accessoryCircular、还能花 accessoryRectangular、systemSmall／systemMedium，以及两个 ControlWidget。普通组件使用深链；控制使用 App 与扩展共用声明的 OpenIntent，在 App target 处理目的地。扩展没有写账、读账或云端操作。App 的 Mac 构建通过平台过滤跳过扩展依赖与嵌入。工程生成器已同步，重新生成不会丢失 target。

## 验证与限制

Linux Swift 6.2.4：`swift build` 与 `swift test`；实际最终数字见 [VALIDATION.md](VALIDATION.md#第九轮快速记账2026-10-21)。默认 `/root` 缓存只读，运行时使用可写缓存：

```bash
CLANG_MODULE_CACHE_PATH=/tmp/yubai-swift-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/yubai-swift-cache \
XDG_CACHE_HOME=/tmp/yubai-cache \
swift test --cache-path /tmp/yubai-swiftpm-cache \
  --config-path /tmp/yubai-swiftpm-config --security-path /tmp/yubai-swiftpm-security
```

`swift build` 使用相同缓存参数。不启用 `YUBAI_LIVE_EVAL`，不运行实网模型测试。App／Widget 只做 Swift 语法、plist、工程引用、条件编译和 API 文档核对，**没有 Apple SDK 类型检查、签名或设备运行证据**。

Mac／iPhone 待执行：

- Xcode 26 构建 iOS App＋Widget、macOS App；确认 Mac 不构建／嵌入 Widget，iOS 两个 target 均用 Automatic＋同一团队；默认无 App Group entitlement。
- 冷启动、App 已在前台、App 在后台、系统锁屏和 Face ID 账本锁下，执行单笔／多笔短句；缺金额追问；Siri snippet 的编辑、逐笔撤销和刷新；重启首次解锁前失败不得覆盖原文件。
- 钱包自动化参数实际类型、通知同意／拒绝、点按／长按编辑与撤销；跨两分钟边界的重复付款、软删除后重触发、卡映射和商户分类编辑。
- 当前截屏文件、剪贴板、已授权／受限相册、无权限、无可读截图；逐笔勾选、原图附件和导入核对；模糊图返回记一笔后仍能在导入入口找到原图。
- 深链中文编码、预填字段、锁定期间保留目的地；账目标签和 Apple Pay 改账首屏；通知权限、拒绝权限后的保存。
- 默认关闭的所有小组件和控制按钮仅打开 App；可签团队启用 App Group 后确认数字、三项预填、保存／编辑／撤销／同步刷新、跨日、锁账本／隐藏金额清理。
- 390×844、小屏、深色、大字号、VoiceOver、减少动态效果；沿用现有 YubaiMotion，没有新增动画。

免费 Personal Team 的 provisioning profile 有效 7 天，过期需要重新构建安装；最多 10 个 App ID、3 台设备、每台设备 3 个 App。新增 Widget 另用一个 bundle id，实际签名安装仍需 Xcode 核对。App Groups 需要对应团队能力，故默认关闭数字共享；本地通知不使用 APNs entitlement，本次钱包交易是用户的系统自动化输入，不需要商户 Apple Pay entitlement。来源：[Apple 账户说明](https://developer.apple.com/help/account/basics/about-your-developer-account)、[App Groups 配置](https://developer.apple.com/documentation/xcode/configuring-app-groups)、[交互式 snippet](https://developer.apple.com/documentation/appintents/displaying-static-and-interactive-snippets)、[OpenIntent](https://developer.apple.com/documentation/appintents/openintent)、[ControlWidget](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)。


## 本轮本地提交位置

执行环境将原仓库 `/home/user/yubai/.git` 以只读挂载，`git add` 无法创建 index.lock；没有修改挂载或尝试提权。为完成本地提交，建立 `/tmp/yubai-quick-capture.git` 的本地 Git 副本，沿用原分支基线和已配置作者，工作树仍指向 `/home/user/yubai`，提交分 Core 与 App／Widget 两次。原仓库 HEAD 无法前移，其工作区改动保持原位；没有 push。

可移交文件为 `/tmp/yubai-quick-capture-patches/` 内两份 format-patch，以及 `/tmp/yubai-quick-capture.bundle`（含此分支相对原基线的两次提交，原基线为前置条件）。补丁可在可写环境的干净基线分支中应用；当前已有源码改动的工作区须先妥善保留，避免重复应用。
