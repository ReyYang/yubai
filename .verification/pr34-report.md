# PR #34 Mac 验证报告

- 结论: FAIL
- 分支提交: 619564faf2a74b78dd7d7b1e54961d7fee372cdc
- 时间: 2026-10-23T17:08:33+08:00
- Xcode: Xcode 27.1
  Build version 27A9275
- 模拟器: iPhone 17 Pro Max, iOS 26.4.1（23E254a）；经用户批准替代已删除的 iPhone 17 Pro。截图使用现有 vphone yubai-e2e-20261004，iOS 26.6.2（23G90），430×932pt。

## 编译
- 结果: 成功
- 错误（失败时逐行原样列出）: 无

## UI 测试
- 总数 / 通过 / 失败 / 跳过: 69 / 46 / 23 / 0
- 新测试（15 个）:
  - testJudgeAskScreenshotFixture: 通过
  - testJudgeWaitScreenshotFixture: 通过
  - testJudgeBuyScreenshotFixture: 通过
  - testJudgeSkipScreenshotFixture: 通过
  - testWishlistCoolScreenshotFixture: 通过
  - testLetterSavingScreenshotFixture: 通过
  - testProfileRevisitScreenshotFixture: 通过
  - testSubcategoryScreenshotFixture: 通过
  - testAskWithoutKeyDisablesComposerEvenWithScriptedReplies: 通过
  - testBoughtWishShowsStatusAndDateWithoutAskAgain: 通过
  - testFixedBillGroupedSwipesKeepCardAndContentGeometry: 失败
  - testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo: 失败
  - testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet: 失败
  - testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator: 失败
  - testOverviewAccessibilityXLScalesHeaderAndWrapsTodaySummary: 通过
- 已知失败（在 18 个名单里）:
  - testFixedBillCheckMarksPaidAndUndoRestoresIt | Tests/YubaiUITests/AppFlowTests.swift:300 | XCTAssertTrue failed
  - testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow | Tests/YubaiUITests/AppFlowTests.swift:351 | XCTAssertTrue failed
  - testFixedBillStopAndResumeBothSupportUndo | Tests/YubaiUITests/AppFlowTests.swift:381 | XCTAssertTrue failed
  - testDueCardIncludesPreviousMonthAndLinksOverflowToBills | Tests/YubaiUITests/AppFlowTests.swift:497 | XCTAssertTrue failed
  - testButlerSwipeDismissesWithoutSwitchingTabs | Tests/YubaiUITests/AppFlowTests.swift:1027 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
  - testButlerRightSwipeAtFirstPagePreservesCardAndPaging | Tests/YubaiUITests/AppFlowTests.swift:1070 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
  - testClosedLedgerRowPagesRightAndRevealedRowClosesFirst | Tests/YubaiUITests/AppFlowTests.swift:1091 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
  - testRevealedLedgerRowConsumesSwipesInBothDirections | Tests/YubaiUITests/AppFlowTests.swift:1117 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
  - testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt | Tests/YubaiUITests/AppFlowTests.swift:1135 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
  - testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab | Tests/YubaiUITests/AppFlowTests.swift:1161 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
  - testLedgerRevealClosesAfterTabSelectionAndPaging | Tests/YubaiUITests/AppFlowTests.swift:1175 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
  - testLedgerSwipeDeleteAndUndoRestoresRow | Tests/YubaiUITests/AppFlowTests.swift:1255 | XCTAssertTrue failed
  - testManualAndAskActionsPreserveTheSelectedPage | Tests/YubaiUITests/AppFlowTests.swift:1399 | XCTAssertTrue failed
  - testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible | Tests/YubaiUITests/AppFlowTests.swift:1437 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)")
- 名单里这次反而通过的:
  - testFixedBillEditorUsesInstallmentsAndAccountGatesAutomaticRecording
  - testRootSwipeSkipsAddTabAndPushedPageKeepsSystemBack
  - testDonutSwipeDoesNotSelectSlice
  - testLedgerRowsStillScrollVerticallyAndOpenWithTap
- 新测试失败:
  - testFixedBillGroupedSwipesKeepCardAndContentGeometry | Tests/YubaiUITests/AppFlowTests.swift:434 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 失败截图中的固定收付卡片已回到未展开状态，房租、话费、工资可见；前一附件显示独立停掉按钮，失败在回滑后等待 action.hittable == false，之前的 12pt 几何断言已执行通过。 [失败截图](pr34-shots/failures/testFixedBillGroupedSwipesKeepCardAndContentGeometry-failure.png)
  - testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo | Tests/YubaiUITests/AppFlowTests.swift:462 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 失败截图已回到现在首页，还能花 700、房租待付 300；另一附件确认居中停掉「房租」？弹窗出现过，失败在撤销后等待 calculation 消失。 [失败截图](pr34-shots/failures/testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo-failure.png)
  - testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet | Tests/YubaiUITests/AppFlowTests.swift:670 | XCTAssertTrue failed | 屏幕处于横向分页中间，左半是现在、右半是洞察，但底部我为选中态；失败在 header.isHittable，记账面板未打开。 [失败截图](pr34-shots/failures/testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet-failure.png)
  - testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator | Tests/YubaiUITests/AppFlowTests.swift:724 | XCTAssertTrue failed | 记一笔面板已打开，合成账目 0/1/2 建议芯片和底部记下、再记一笔均可见；失败在 recent.isHittable，尚未执行底部几何断言。 [失败截图](pr34-shots/failures/testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator-failure.png)
- 新失败:
  - testCancelledInsightBackKeepsTabBarHiddenAndPagingLocked | Tests/YubaiUITests/AppFlowTests.swift:873 | XCTAssertTrue failed | 停在洞察根页，支出 32、餐饮 100%，底部 tab bar 可见；没有停留在预期的餐饮明细页。 [失败截图](pr34-shots/failures/testCancelledInsightBackKeepsTabBarHiddenAndPagingLocked-failure.png)
  - testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop | Tests/YubaiUITests/AppFlowTests.swift:912 | XCTAssertTrue failed | 停在现在首页，还能花 622，上月账单与房租待付卡及还有 1 笔可见；失败在查找 moreDueBills。 [失败截图](pr34-shots/failures/testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop-failure.png)
  - testFixedBillsStateTextAndUpcomingHasOnlyContextAction | Tests/YubaiUITests/AppFlowTests.swift:563 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 固定收付要付、要收均为 0，视频会员、房租、话费、工资均为灰色已记状态。 [失败截图](pr34-shots/failures/testFixedBillsStateTextAndUpcomingHasOnlyContextAction-failure.png)
  - testFixedBillStopHandlesEveryUnsettledPeriod | Tests/YubaiUITests/AppFlowTests.swift:612 | XCTAssertTrue failed | 居中的停掉「每周订阅」？弹窗显示还有 6 期没记。及三个按钮；失败在查找没付，这期也不要了按钮。 [失败截图](pr34-shots/failures/testFixedBillStopHandlesEveryUnsettledPeriod-failure.png)
  - testFixedIncomeStopSkipCancelPersistenceAndUndo | Tests/YubaiUITests/AppFlowTests.swift:579 | XCTAssertTrue failed | 固定收付房租已付，工资行左滑露出停掉，尚未出现确认弹窗。 [失败截图](pr34-shots/failures/testFixedIncomeStopSkipCancelPersistenceAndUndo-failure.png)

## 截图检查
- [01-welcome-keyboard.png](pr34-shots/01-welcome-keyboard.png) | 不符合 | 金额 1000、账户芯片与开始按钮完整；vphone 当前使用硬件键盘，软键盘未弹出，键盘遮挡场景未覆盖。
- [02-now-top.png](pr34-shots/02-now-top.png) / [02-now-mid.png](pr34-shots/02-now-mid.png) | 不符合 | 顶部标题与按钮完整；50 条合成账目、3 项固定收付下概览内容仍基本容纳于一屏，上滑后未形成有效中段，标题下滚动渐隐未覆盖。
- [03-insights-top.png](pr34-shots/03-insights-top.png) / [03-insights-mid.png](pr34-shots/03-insights-mid.png) | 符合 | 顶部和滚动后标题保持安全区内，右上圆形按钮完整，滚动内容在暖纸色区域渐隐。
- [04-entries-top.png](pr34-shots/04-entries-top.png) / [04-entries-mid.png](pr34-shots/04-entries-mid.png) | 符合 | 顶部月份条与筛选完整，滚动后账目在标题下渐隐，标题和问余白按钮未裁切。
- [05-me-top.png](pr34-shots/05-me-top.png) / [05-me-bottom.png](pr34-shots/05-me-bottom.png) | 符合 | 底部存储空间 25.6 KB 完整位于 tab bar 上方，滚动后顶部内容渐隐。
- [06-titles.json](pr34-shots/06-titles.json) | 符合 | 四页 rootHeaderTitle 顶部 y 均为 85.1667pt，中心 y 均为 95pt，高度均为 19.6667pt；切换后读取稳定状态。
- [07-entry-back.png](pr34-shots/07-entry-back.png) | 不符合 | 点击账目实际打开改一笔 sheet，没有系统导航返回按钮；从系统 sheet 控制柄下滑成功回到账目原滚动位置，所要求的系统导航返回路径未覆盖，附 07-entry-detail.png。
- [08-add-sheet.png](pr34-shots/08-add-sheet.png) | 符合 | 餐饮已选，3 个用途建议芯片可见，记下、再记一笔位于屏幕底部安全区域之上，未见重叠；vphone 未显示 home 指示条本体。
- [09-fixed-swiped.png](pr34-shots/09-fixed-swiped.png) | 符合 | 话费左滑后整组卡片完整，停掉为独立圆角按钮；AX 实测前一按钮右缘 298pt，停掉左缘 310pt，间隔 12pt；标题左移裁切符合预期。
- [10-stop-alert.png](pr34-shots/10-stop-alert.png) | 符合 | 还能花计算页的结束这个安排弹出居中停掉「房租」？alert，含取消和红色停掉以后的；取消后恢复，未执行停掉。固定收付已到期行走另一种居中处理弹窗，附 10-stop-due-alert.png。
- [11-now-xl.png](pr34-shots/11-now-xl.png) | 符合 | 辅助功能字体滑块第 10 档（9/11，82%，Accessibility XL）下，顶部两圆按钮均 48pt，图标完整；今天分行且无省略，tab bar 图标未溢出；恢复原设置关闭/67% 并回读一致。
- 多余的说明句或口号:
  - 编辑账目页（07-entry-detail.png）：「可不填」占位。
  - 计算页（10-stop-alert.png 背景）：「有固定收付已到期，请确认是否已付。」；「已到期，请核对」中的「请核对」属于操作提示。
  - 其余所查看的 vphone 页面未见额外说明句或口号；「记下后，还能花」与金额配对，按事实/数字标签记录；弹窗「10/23这期还没记。」为当前账单状态。

## 其他
- 运行中断、重跑、模拟器异常等情况: 本轮完整运行一次，退出码 65；无宿主中断、无重跑，xcresult runtimeWarnings 为空。自动测试耗时约 28 分 31 秒。测试使用 -parallel-testing-enabled NO，复用 6719E69E-FD49-4E6A-93C7-857012B57B3B；未创建模拟器或 worktree。
- 统计以本轮 xcresult 为准：14 项已知失败、4 项新测试失败、5 项新失败；8 个第十五轮截图夹具全部通过。分类以用户名单为准，不单独证明名单外失败由 PR 引入；本轮未额外跑 main 基线。9 项非已知失败的截图均逐张打开查看，断言为原文。
- 按用户确认的混合方案，自动测试用 Pro Max，人工截图用 vphone，未新建临时截图测试文件，未修改应用或已有测试。vphone 使用同一提交的设备 Debug 构建；为保留原应用数据，仅在安装包副本中改为 app.yubai.verifypr34 / 余白验证并移除 PlugIns，故不覆盖原包签名、安装门槛或 Widget 验收。通过 vphone 安装包入口安装，原 app.yubai.personal 未被覆盖。
- vphone 截图数据是本次独立账本：50 条合成账目、3 项固定收付；cloudAIEnabled=false。首次写入合成文件后遇到文件 owner 导致不可读，已只对该测试文件修正为 501:501 后正常启动，此为测试准备问题。软键盘因现有硬件键盘设置未显示；需重启 VM 的更改对话框已取消，未改硬件键盘配置。
- vphone 原字号为辅助功能字体关闭、滑块 67%，原粗体文本已开启；本轮仅临时调整字号，XL 后恢复关闭/67%，并独立回读一致。vphone 时间栏与 Mac 时间不一致，截图保留原样。
- 11 组截图检查中，01、02、07 因条件或路径未覆盖按不符合记录，并非直接判定应用缺陷；10 的指定 alert 来自与自动测试相同的计算页结束安排入口，固定收付已到期行的弹窗另附。vphone 外观检查不替代 Pro Max 自动测试失败。
- 全程未运行 GitHub Actions、未调用 DeepSeek 或付费 API、未登录或购买；未 merge、未修改 main 提交。无新增或改动的应用可见中文字符串。报告及截图为唯一提交内容。
- 收尾: 已切回 main；本轮 "before pr34 verify" stash 已恢复并仅删除该 stash；"xcode signing before v16 check" stash 仍在，原有三条 stash 的 hash、顺序和说明与开始前一致。git status 与开始前一致，project.pbxproj、Package.resolved 的原始 SHA-256 均一致；UserInterfaceState.xcuserstate 恢复时一致，但 Xcode 随后再次自动更新该被忽略的窗口状态文件，保留当前状态与原始备份，不声明整个 workspace 字节一致；main 仍为 97038316d3db79cbdcfc9e876ce2545a2db04afd。根目录 build.log、test.log、ui.xcresult 已移出；报告推送核对后移出本轮 .verification。原始证据及编译生成 workspace 保留在 /tmp/yubai-pr34-verify-20261023-r2/，此前 .verification 已保留在该目录的 previous-verification/，未删除长期项目资料。模拟器和 vphone 保留。
