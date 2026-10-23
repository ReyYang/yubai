# 第十六轮两次截图修正合并

2026-10-23，继续当前未提交 merge：`origin/feat/no-explanatory-copy`／`205edde` → `feat/butler-saving-core`／`d9a3c56`。本分支已合入 `e50a73b` 与 main `9703831`，本轮仅带入 `65928a9` 和 `205edde` 两次截图修正。已逐项核对两次提交意图、当前源码与 V16 归档规则／选定稿；不提交、不终止 merge、不联网调 API。

## 八个冲突的取舍

| 文件 | 处理与保留 |
| --- | --- |
| `.design-meta/README.md` | 两边记录全部保留，截图复查记录与本分支 Core／V15／小项、编译、显示、问余白及 main 合并历史并存；顶部登记本次结果。历史测试与暂存结论仍属于原轮次。 |
| `.scratch/yubai-product/issues/13-complete-personal-release.md` | 两边 owner 决定、实现选择、原验证边界完整保留，追加本次明确任务与采用范围；整票保持原状态，不将合并等同于产品验收完成。 |
| `Sources/YubaiApp/AskYubaiView.swift` | 保留本分支拆分的 conversation／availabilityStatus、共用 ChatInputBar、焦点绑定、追问移焦点与滚到按钮行、纸色实底导航栏；在原 availabilityStatus 上补新 configureAskKey 标识，建议芯片采用新禁用灰色。没有恢复旧 HStack 输入条。 |
| `Sources/YubaiApp/FixedFlowsView.swift` | 卡片与左滑采用新 CardRows／SwipeActionRow／96pt 展开距离及已展开后右拖收回；保留本分支 HorizontalPan、macOS 手势与状态／金额／提前标记、已停掉唯一行、旧期结算／跳过／恢复／撤销。所有停止确认采用系统 alert，调用 FixedFlows.stop 继续处理全部未结算期与省钱停订快照。具体显示冲突见下节。 |
| `Sources/YubaiApp/OverviewView.swift` | 保留 paymentRow 子视图，内调用新行级 endButton／alert，避免恢复大段内联表达式；保留 main 值导航、现在页待保存快照／动画与近限额入口，带入 HeaderIconButton、大字号今天摘要换行及根页滚动标识。 |
| `Sources/YubaiApp/UITestSupport.swift` | 白名单取并集：八个 V15 截图脚本、原夹具、main bills-clarity／bills-multiple、新 wish-bought／overview-xl 共 24 个；全部准备数据与假 transport 保留。显式 configuredKeyOverride 与新密钥门槛只在 Debug 模拟器＋有效 UUID＋白名单脚本中生效。 |
| `Sources/YubaiApp/WishlistView.swift` | 保留 SavingsHeader、冷静到期卡、后悔入口、年龄／剩余天数／零天修复及买后问题去重；列表空态采用新「当前可展示项目」判断，同时计入 V15 后悔卡，历史入口保留。已买加状态胶囊、隐藏再问动作、保留全部日期及购买记录；标题沿用 V15 rowTitle，不退回旧 cardTitle。 |
| `Tests/YubaiUITests/AppFlowTests.swift` | 保留两边所有方法：HEAD 62、incoming 53，并集 68，零遗漏、零重名、无新增 skip。合并同名断言，保留慢拖与 isHittable 查询、主分支已停掉唯一行／灰勾／持久化和批量处理断言；停止确认全部改查 alert。自定义 sheet 的固定 50pt 高度／等宽断言，按新系统控件改为可点／启用／位于 alert 内；存储同时保留标识与「账单原件／不删」断言。 |

## 同处显示的实际取舍

- **停止 sheet 与 alert**：采用更晚截图要求的系统 alert，移除旧 FixedFlowStopSheet。没有待处理期时只显示「停掉以后的／取消」，不显示可恢复操作的后果说明。有待处理期时保留 main 的「付了／收到了，记一笔再停」「没付／没收到，这期也不要了」「取消」，并仅显示原期数／日期事实；不添加后果说明。结果按钮仍一次处理所有到期未结算期，然后停订，恢复及快照撤销均保留。
- **停止后的行**：采用 main 已停掉分区的唯一记录，保留最近一期已记／没要事实；不恢复 incoming 旧分支的活动区已记灰勾重复行。新 alert 的取消、确认、恢复、撤销及系统呈现要求均保留。
- **固定收付行层级**：采用新共享卡片／行 offset／独立按钮层，去掉原整组手写裁切和行内额外水平 padding，避免文字缩窄或二次内缩。保留 V14 状态文字、已记 0.7 淡化、占位对齐和未到长按提前标记，不恢复旧日期点阵。
- **心愿显示**：新已买状态／日期／无再问动作与 V15 冷静期、省钱、后悔卡同时保留。当前没有聚焦、买后追问、在想项目或后悔入口时才显示列表空态；已经买过的历史仍可进入。保留 V15 标题层级和到期不写零天的规则。

## 自动合并与保留范围

已核对自动合并的 14 个文件。DesignSystem 共用左滑、根页裁切／底部 margin、欢迎 safeAreaInset 与禁用底色、header／tab 图标缩放，EntriesView 删除行改用共享左滑而保留原单行展开与分页协调；记账／改账用途留空占位、导入按流向汇总、消费观全部记忆的行尾图标、我页右侧计数、快速记账字体／行宽、存储系统导航标题与金额单位样式全部带入。第一轮的中间方案以第二轮修正为准，历史记录不删。

相对 HEAD，YubaiCore、Core 测试、SavingViews、SavingPurchaseViews、SubcategoryViews、ProfileConversationView、EntryDetailView 无差异；YubaiCore.Category、ToolbarItem 包装、拆子视图、来信／消费观显示修复均保留。YubaiApp 仍用四个独立 NavigationPath、值路由与 pagingPhase 停稳同步；洞察只新增截图修正的滚动标识，main #35 标准推入／取消返回规则保持。工程／依赖与原始 HTML 不改。

V16 不再把脚本存在视为已配密钥，因此同步 [V15 夹具启动说明](SAVING-UI-V15.md#模拟器启动)：手动截图须显式设置 YUBAI_UI_TEST_CONFIGURED_KEY=1；UI application 助手已设置。密钥状态覆盖不写钥匙串，传输仍为本机假 transport。

## 本次新增或改动的可见中文

相对合并前 HEAD，下表涵盖新增、改写、删除与因条件变化重新展示的文字。均沿用两边已经采用的文案；没有四类以外的新正文。布局／字体变化复用的既有文字一并列出，动态值来自原数据。两次修正的原始完整清单仍在 [V16 交付](../.design-meta/no-explanatory-copy-v16.md#截图复查修正)与其第二次复查章节。

| 位置 | 文字／模板及变化 | 类型 |
| --- | --- | --- |
| 固定收付／计算页 | 停掉；停掉「{名称}」？；停掉以后的；取消；结束这个安排 | 标题／控件字；采用系统 alert，无待处理期的「停掉」确认按钮改为「停掉以后的」 |
| 固定收付待处理期 | 付了，记一笔再停；收到了，记一笔再停；没付，这期也不要了；没收到，这期也不要了 | 结果控件字，原 main 文案移至 alert |
| 固定收付待处理期 | 还有 {N} 期没记。；{月日}这期还没记。 | 数字、日期事实及状态，原文移至 alert |
| 固定收付 | 删除可见的「只停以后的，付过的记录保留。」 | 可恢复操作不显示后果说明；完整读屏 hint 保留 |
| 心愿 | 已买（新增）；心愿单还是空的；该不该买（当前列表空时重新显示） | 状态／标题／控件字 |
| 心愿 | 已买卡不显示「再问一次」；{日期}无新增中文后缀；加入 {N} 天 · {日期}保留 | 控件删除／日期事实；读屏追问日期完整保留 |
| 消费观 | 全部 {N} 条（从文字移除 ›，改行尾图标） | 控件字、数字 |
| 我 | {N} 条（右侧值）；删除可见「余白记得的 · {N} 条 · 这周新记了 {M} 条」「还没写消费观。」 | 数字；原信息保留给读屏 |
| 记一笔／改一笔 | 输入框删除重复「用途」占位，行名「用途」保留 | 控件字 |
| 导入核对 | 流出 {N} 笔；流入 {N} 笔（替换支出／收入）；{来源} · {日期范围} · {N} 笔（字体） | 数字和事实／标题 |
| 问余白 | 还没配密钥 ›；这周外卖花了多少？；11月1日的房租够吗？；想买一双 899 的鞋，该不该买？ | 状态／控件字，仅改缺密钥时外观、标识与禁用检查 |
| 欢迎 | 余白；现在手里有；微信零钱；支付宝；招行储蓄卡；＋ 别的；名称；开始；恢复备份 | 标题／控件字，仅位置与样式变化 |
| 根页／tab／今天行 | 现在；洞察；我；记一笔；今天；还没记；{N} 笔 · {用途}；账目 | 标题／状态／控件字／数字和事实，仅缩放、换行或裁切变化 |
| 存储／快速记账 | 存储空间；Apple Pay 付完就记 | 标题，仅字体或系统导航呈现变化 |
| 仅 Debug 模拟器 | 合成水壶；合成测试的午饭和日用品以及下周旅行准备 | 合成账目／心愿用途事实，供新夹具验证 |

不增加说明句，期数 message 属于数字和状态；不需要四类之外的正文例外。accessibilityLabel／Hint 保持完整，未作为可见说明重新引入。

## 验证

- 指定 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0；同时显式设置 YUBAI_LIVE_EVAL=0。464 项，460 通过、4 原有实网 opt-in 跳过、0 失败；包含 InterfaceVocabularyTests 3 项。日志 `/tmp/yubai-v16-review-merge-swift-test.log`。
- 全部 38 个 App 文件逐个通过 swiftc -frontend -parse：iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug；UI 测试通过两组模拟器 Debug 条件解析。日志 `/tmp/yubai-v16-review-merge-parse.log`。保留既有条件编译分支，没有用简化文件代替 App 源文件。
- UI 方法名严格等于两边并集，68 个，无遗漏／重名／新增 skip；只做语法与静态合并检查，未执行 UI 测试。
- 从合并后 UITestSupport 提取同一源码，仅移除最外层模拟器条件，与本轮真实 Core 编译产物离线类型检查／链接并执行。24 个脚本的白名单、prepare／load／validate 通过；8 个截图／购买追问／消费观假 transport 流程通过；新增已买心愿／长用途、main 状态夹具／六期结算和跳过、密钥 0／1／未设置、无 UUID／非法 UUID／未知脚本拒绝门槛全部通过。临时源码、日志与二进制仅在 `/tmp/yubai-v16-review-fixture-check/`。
- git diff --check 通过；当前版本管理及未忽略文本无冲突标记、无私有页面链接；两边产品历史记录保留。

Linux 没有 Apple SDK，不能执行 SwiftUI／XCTest 类型检查或 UI 实跑；系统 alert 按钮、首中末行左滑、键盘、根页安全区、无障碍字号、VoiceOver／深色与取消侧滑返回仍待 Mac 复验。原始选定稿、Figma、旧原型及分发包未同步；没有将历史截图验收当作本轮验收。

## 暂存状态

工作树冲突已解决，验证已完成。执行 git add 退出 128：无法创建 `.git/index.lock`，当前环境将 `.git` 挂载为只读；索引仍有八个未合并文件。未更改权限、未尝试绕过挂载限制，未提交、未终止 merge。后续在 `.git` 可写环境执行以下命令，只暂存，不提交：

```sh
git add -- \
  .design-meta/DESIGN.md \
  .design-meta/README.md \
  .scratch/yubai-product/issues/13-complete-personal-release.md \
  .scratch/yubai-product/map.md \
  Sources/YubaiApp/AskYubaiView.swift \
  Sources/YubaiApp/FixedFlowsView.swift \
  Sources/YubaiApp/OverviewView.swift \
  Sources/YubaiApp/UITestSupport.swift \
  Sources/YubaiApp/WishlistView.swift \
  Tests/YubaiUITests/AppFlowTests.swift \
  docs/MERGE-V16-SCREENSHOT-FIXES.md \
  docs/SAVING-UI-V15.md
```
