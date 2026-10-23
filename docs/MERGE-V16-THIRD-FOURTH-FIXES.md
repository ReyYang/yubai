# 第十六轮第三、第四次截图修正合并

2026-10-23，处理当前未提交 merge：`origin/feat/no-explanatory-copy`／`86524fd` → `feat/butler-saving-core`／`a23e179`。`git log 205edde..origin/feat/no-explanatory-copy` 只有 `0acb32b`、`86524fd`；已逐个阅读提交意图及差异。此前已合入的 `205edde`、main `9703831` 及本分支功能继续保留。本次不提交、不终止 merge、不联网调 API。

## 五个冲突的取舍

| 文件 | 处理与保留 |
| --- | --- |
| `.design-meta/README.md` | 两边完整保留：此前 V15／Core／main／两次 V16 合并的历史，以及对方第三、第四次截图复查记录；顶部追加本次实际结果。历史暂存和验收结论仍属于原轮次。 |
| `.scratch/yubai-product/issues/13-complete-personal-release.md` | 两边 owner 要求、实现选择及验证边界完整保留，追加本次明确任务与适配；不将合并标为整票完成。 |
| `Sources/YubaiApp/EntriesView.swift` | 采用对方固定 `rootPageHeader { TabRootHeader(title: "账目") }`、隐藏 iOS 系统导航栏及删除正文重复顶部留白。保留月份／搜索／筛选／原宽行、共享左滑、单行展开与分页协调。保留本分支 `yubaiNavigation()` 签名：对方的 `hidesTabBar: false` 参数在本分支已被导航路径方案取代，不能直接复制该调用。 |
| `Sources/YubaiApp/FixedFlowsView.swift` | 继续共用 `CardRows`／`SwipeActionRow`，96pt 原宽左移、标题裁切、78pt 动作与 12pt `gapAction` 均采用对方方案。控件保留 main #32 的描边「付了／收到了」、已记灰勾及未到无按钮，不恢复更早的实心勾样式；把本次靠右对齐意图应用到描边按钮的 `yubaiHitTarget(alignment: .trailing)`，点击区仍至少 44pt。原状态／逾期、长按改金额／提前标记、停止系统 alert、全部旧期结算／跳过、唯一已停掉行、恢复和快照撤销保持；静态结算 helper 保留。 |
| `Sources/YubaiApp/SettingsView.swift` | 采用对方无重复顶部 padding 的正文和固定 header；保留本分支 `.profile` 值路由及其他全部 `TabNavigationLink`，延续 main #35 的 push／返回／浮栏规则。消费观计数、心愿、存储用量异步读取、智能设置和测试标识保持。 |

## 自动合并及保护范围

- `DesignSystem.swift`：完整采用固定 header 的 canvas 暖纸底、8pt 不接收点击／读屏的渐隐、共享 `TabRootHeader`（现在页显示金额眼睛）、`gapAction` 展开几何，以及欢迎页 FocusState／ScrollViewReader／账户卡片自动滚动；保留本分支既有导航和编译适配。
- `OverviewView.swift`、`InsightsView.swift`：固定 header 移出正文，沿用本分支资金与保存反馈、近限额、paymentRow 拆分、小项及标准值导航；四根页统一同一组件。
- `QuickEntryView.swift`：采用对方底部键盘／保存操作 `safeAreaInset` 与独立表单滚动；原保存、继续记账、用途芯片和固定收付匹配保留。
- `Tests/YubaiUITests/AppFlowTests.swift`：采用对方两行夹具、欢迎聚焦自动滚动、根页标题安全区／可点击性和记一笔底部操作断言；原 12±1pt 左滑断言、慢拖、可点击查询、main 固定收付／导航和 V15 截图流程保持。自动合并将旧 `testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo` 替换成对方改名后的 `…CancelAndConfirm`，本次分别保留两个方法；旧方法先关闭计算页 sheet，再点根页撤销并重开计算页验证恢复，不要求 sheet 内访问根页提示条。
- 方法集合严格等于 HEAD 68 个与 incoming 54 个的并集，共 70 个，零遗漏／零重名，无新增 skip。所有原有及新增方法只做条件语法解析，本轮未执行 UI 测试。
- `UITestSupport.swift` 与 HEAD 完全一致，incoming 此文件也与此前已合入的 `205edde` 完全一致；24 个白名单脚本、8 个 V15 截图夹具、全部准备与假 transport 保留。两边 UI 方法直接引用的脚本均仍存在；本轮未重跑夹具流程，历史离线执行证据见[上一轮报告](MERGE-V16-SCREENSHOT-FIXES.md#验证)。
- YubaiCore、Core 测试、SavingViews、SavingPurchaseViews、SubcategoryViews、ProfileConversationView、EntryDetailView、AskYubaiView、YubaiApp、工程、Package 与锁文件相对 HEAD 无差异：V15 Core／界面、小项、`YubaiCore.Category`、ToolbarItem 包装、拆分子视图、问余白纸色导航与追问收键盘、显示修复、main #32／#35 导航路径及分页停稳同步全部保留。

## 可见中文

没有新增、删除或改写正式界面的可见中文措辞；仅沿用已有文字的位置与控件样式。以下为本次布局变化涉及的文字，完整原复查清单见[第三次](../.design-meta/no-explanatory-copy-v16.md#第三次截图复查修正)与[第四次](../.design-meta/no-explanatory-copy-v16.md#第四次截图复查修正)记录。

| 位置 | 复用的可见中文 | 类型 |
| --- | --- | --- |
| 固定 header | 现在；洞察；账目；我 | 标题；账目由系统标题改为自定义标题 |
| 欢迎 | 余白；现在手里有；微信零钱；支付宝；招行储蓄卡；＋ 别的；名称；开始；恢复备份 | 标题／控件字，只改键盘下滚动布局 |
| 记一笔 | 记一笔；导入；支出；收入；转账；记下后，还能花；记下 {金额} 元；记下，再记一笔 | 标题／控件字／数字事实；底部操作改用安全区 inset |
| 固定收付 | 付了；收到了 | 结果控件字，仅改透明点击区内的靠右对齐；已记、未到、旧期处理和停止确认文案保持 |

问余白图标入口及显示／隐藏金额、账户、日期等完整 accessibilityLabel／Hint 保留。不增加说明句，不需要四类以外的例外。

## 验证及边界

- 运行 `export PATH=/opt/swift-rootfs/usr/bin:$PATH && YUBAI_LIVE_EVAL=0 swift test`：464 项、460 通过／4 原有实网 opt-in 跳过／0 失败，包含禁用词检查 3 项。日志 `/tmp/yubai-v16-fourth-merge-swift-test.log`；未调用实网 API。
- 全部 38 个 App 文件逐个通过 `swiftc -frontend -parse`：iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug；UI 测试通过两组模拟器 Debug 条件解析。共 154 次文件解析，日志 `/tmp/yubai-v16-fourth-merge-parse.log`。Linux 无 Apple SDK，不能据此宣称 SwiftUI／XCTest 类型检查通过。
- 方法名并集、两边夹具引用、保护文件相对 HEAD 无差异检查通过；版本管理及未忽略文本无冲突标记、无私有页面链接。`git diff --check` 与 `git diff --cached --check` 通过。
- Apple 类型检查、70 项 UI 实跑、固定 header／安全区／键盘／左滑实际几何、VoiceOver／深色／大字号仍待 Mac 复验。原始选定稿、Figma、旧原型及分发包未同步；本次仅按既有采用意图合并，没有新增业务决定或设计稿。

## 暂存状态

工作树的五处冲突已解决。执行 `git add` 退出 128：当前环境将 `.git` 挂载为只读，无法创建 `.git/index.lock`；索引仍有五个未合并文件。本轮没有修改权限或绕过挂载限制，没有提交或终止 merge。在 `.git` 可写环境执行以下命令即可暂存全部合并结果（不提交）：

```sh
git add -- \
  .design-meta/DESIGN.md \
  .design-meta/README.md \
  .design-meta/no-explanatory-copy-v16.md \
  .scratch/yubai-product/issues/13-complete-personal-release.md \
  .scratch/yubai-product/map.md \
  Sources/YubaiApp/DesignSystem.swift \
  Sources/YubaiApp/EntriesView.swift \
  Sources/YubaiApp/FixedFlowsView.swift \
  Sources/YubaiApp/InsightsView.swift \
  Sources/YubaiApp/OverviewView.swift \
  Sources/YubaiApp/QuickEntryView.swift \
  Sources/YubaiApp/SettingsView.swift \
  Tests/YubaiUITests/AppFlowTests.swift \
  docs/MERGE-V16-THIRD-FOURTH-FIXES.md
```
