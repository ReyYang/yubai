# PR #34 名单外 UI 失败修复（2026-10-23）

基于 `feat/butler-saving-core`／`4b7c0f7`。Mac 报告实际运行在 `a23e179`：Xcode 27.1、iPhone 17 Pro／iOS 26.4.1、`-parallel-testing-enabled NO`，68 项中 26 项失败。本轮按测试名对照旧提交的准确失败行及当前源码，不把旧行号用于当前文件，也不把失败截图当作初始夹具状态。没有在 Linux 实跑 XCUI。

## 逐个判断

| 测试 | 判断与处理 |
| --- | --- |
| `testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow` | 测试查询错误。共用 `openFixedBillStop` 先只按 `stopFixedFlow_` identifier 前缀查询，再用 `allElementsBoundByIndex.first { $0.isHittable }` 找可点按钮并 tap。方法体属于已知名单，保持原样。 |
| `testFixedBillStopAndResumeBothSupportUndo` | 同上；只通过共用 helper 修正非法查询，方法体保持原样。 |
| `testFixedBillStopHandlesEveryUnsettledPeriod` | 同一非法查询；修共用 helper，六期待处理、全部结算和撤销断言保持。 |
| `testFixedIncomeStopSkipCancelPersistenceAndUndo` | 同一非法查询；修共用 helper，收入取消／跳过／撤销／重启持久化／恢复断言保持。 |
| `testUpcomingPaymentStopUsesAlertAndSupportsCancelAndConfirm` | 与 Undo 版重复，合入下面一个测试。保留按名称查系统 alert、无 popover、取消／停掉以后的可点、取消不修改与确认后结束入口消失等覆盖；没有改 alert 设计或 destructive role。 |
| `testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo` | 测试呈现层级过时。旧报告第 443 行是直接在计算页 sheet 内找根页撤销；「还能花是怎么算的」正是预期入口，没有点错。当前 HEAD 已先关闭 sheet。本轮合并两版覆盖，限定计算页导航栏的 `closeSheet`，关闭后按 `undoLastChange` 和「结束安排」提示定位根页撤销，再打开计算页断言原结束入口恢复。 |
| `testCancelledInsightBackKeepsTabBarHiddenAndPagingLocked` | 测试手势落点过时。旧第 770 行发生在取消返回验证已通过、随后执行屏幕 40% 高度横拖之后；V15 在这里新增了可点击的「其他」小项行，截图是更深的记录页，浮栏仍隐藏。本轮增加非交互汇总区 `subcategoryInsightsSummary` 标识，在其高度横拖整屏 60% 宽，避免误入小项，并保留重复取消、左右横拖后页面／浮栏、完成返回和根分页断言。返回后查恢复滚动位置上的 `insightCategory_0`；根页翻页在固定 header 的非按钮区域起手。 |
| `testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop` | 真实布局缺陷，尚未到取消返回断言。旧第 806 行在点 `moreDueBills` 时失败，截图仍在根页，浮栏可见符合当时页面状态。普通字号的 `ViewThatFits` 最后一个候选仍是不可滚动的完整内容，所有候选都放不下时入口可能落在浮栏下或屏幕外；固定 header 还会占用独立高度。本轮保留三档原静态候选，并在全部放不下时复用大字号的滚动内容与底部 margin。测试先确认溢出入口完整位于浮栏上方，必要时在 `overviewScroll` 滚动，再运行原取消／完成返回验证；返回后查保留位置上的 `moreDueBills`。无法仅凭该报告断定此缺陷首次由哪次合并引入。 |
| `testFixedBillGroupedSwipesKeepCardAndContentGeometry` | 测试行数预期过时，当前 HEAD 已修，无本轮方法体改动。`bills-overdue` 的上月账单只进入首页待付款，不属于当月支出卡；卡内确实只有话费和房租两行。保留当前的至少两行与首／末行验证，以及卡片不动、原行宽、96pt 左移、78pt 动作、12±1pt 间距等全部几何断言。 |
| `testFixedBillsStateTextAndUpcomingHasOnlyContextAction` | 测试短暂提示的等待／点按方式不当。旧第 542 行失败在点「撤销」，已先成功结算房租、工资并提前标记话费；全部灰勾和要付／要收为零正是这些操作的结果，并非夹具把全部账单初始设成已付。提示寿命为 4 秒，原测试先等待已付图标，再经通用滚动 helper 找撤销。本轮改为一次等待对应「话费」提示和 `undoLastChange` 可点，立即撤销，再断言已付标志消失、原未到行恢复、没有直接付款按钮。初始日期／逾期、自动已付、未来只有长按入口等覆盖保持，夹具和业务代码不改。 |
| `testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet` | 测试系统元素假设过时，当前 HEAD 已修，无本轮方法体改动。旧第 627 行等的是 `app.statusBars`，尚未执行 tab 切换或“记一笔”，不能从该截图判定 addEntry 失效。当前测试已用 push 页原生导航栏测 safeTop，分别覆盖普通／XL 字号、四个固定 header、正文点击与滚动、打开／关闭记一笔和所选 tab 保持。 |

## 导航与实现边界

`RootView` 未修改。当前四个 tab 的独立 `NavigationPath` 仍同时决定浮栏隐藏和根分页锁定；首层值导航、深层目的视图导航、sheet 隔离和 `pagingPhase` 停稳同步保持。没有恢复基于出现回调的浮栏状态。两项取消返回失败的准确位置分别是小项行上的额外横拖和根页入口点按，不是路径更新或取消返回后浮栏出现的证据。

App 改动只有三处：`OverviewView` 补滚动兜底；`SubcategoryViews` 的既有汇总区增加无障碍容器标识；`DesignSystem.Toast` 的既有撤销按钮增加 identifier。没有改 `.toolbar` 内容、Core、夹具、工程或依赖。

完整扫描 `AppFlowTests.swift` 后，查询谓词中已无 `hittable`／`isHittable`。`XCTNSPredicateExpectation` 对单个 element 使用的合法 `hittable == true/false` 保持。18 个已知失败测试方法体与本轮起点逐字一致，只有共用停止查询 helper 的修正会影响其中两项。两份重复停止测试合为一项，UI 方法数由 70 变为 69，没有新增 skip，也没有删除独有覆盖。

## 可见中文

本次新增或改动的可见中文字符串：无。没有添加说明句，也没有改写确认框、按钮或提示文案；新增 identifier 只用于稳定定位。

## 验证

- `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0：464 项，460 通过、4 项原有实网 opt-in 跳过、0 失败。日志 `/tmp/yubai-pr34-swift-test.log`；没有联网调 API。
- 38 个 App 文件逐个通过 `swiftc -frontend -parse`：iOS 26／27.1 模拟器 Debug、iOS 26 设备 Release、macOS 14 Debug；UI 测试通过两组模拟器 Debug 条件解析，共 154 次。日志 `/tmp/yubai-pr34-newfailures-parse.log`。
- 对比当前 HEAD 的 18 个已知方法体、UI 方法集合及查询谓词扫描通过；`git diff --check` 通过。
- 从当前 `UITestSupport.swift` 仅移除最外层模拟器条件，与本轮真实 Core 产物离线类型检查、链接和执行通过：`bills-overdue` 当月支出 2 行、到期待付 3 笔、还能花 622；`bills-clarity` 初始要付 358／要收 500、仅视频会员已付，显式结算后复现全部已付与两个余额为零，恢复快照后话费状态正确；`bills` 停掉未来仍保留已到期付款、恢复快照重新开放结束入口。源码／日志在 `/tmp/yubai-pr34-newfailures-fixtures/`；不执行 UI 或传输 API。

Apple SDK 类型检查、69 项 UI 实跑、4 秒提示时序、根页滚动兜底与实际手势几何仍待 Mac 复验。原始选定稿、外部设计系统、Figma、旧原型及分发包未同步；不改写原 Mac 失败报告，也不宣称 UI 已通过。未提交、未推送。
