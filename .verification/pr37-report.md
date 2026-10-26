# PR #37 Mac 验证报告

- 结论: FAIL
- 提交: 1821b9b5cc22544a4906d11e8503a235dac21278
- 时间: 2026-10-26T10:12:24+08:00
- Xcode: Xcode 27.1；Build version 27A9275
- 模拟器: iPhone 17 Pro Max, iOS 26.4.1 (23E254a), id 6719E69E-FD49-4E6A-93C7-857012B57B3B

## 编译
- 结果: 成功
- 错误（失败时逐行原样列出）: 无编译失败。

## UI 测试
- 总数 / 第一次通过 / 时好时坏 / 稳定失败 / 跳过: 70 / 48 / 2 / 20 / 0
- 耗时: 两轮测试合计 115.83 分钟（第 1 轮 57.13 分钟，第 2 轮 58.71 分钟；不含编译和证据导出）。
- 统计口径: 合并两轮、按唯一测试计数；“第一次通过”表示两轮都首次通过；“时好时坏”包含 1 个跨轮中断后通过，不能据此断定是应用自身的随机缺陷。
- 第 1 轮: 70 个，49 首次通过 / 0 时好时坏 / 20 稳定失败 / 0 跳过，另 1 个中断；共 110 次执行，xcodebuild 退出码 65。
- 第 2 轮: 70 个，49 首次通过 / 1 时好时坏 / 20 稳定失败 / 0 跳过；共 111 次执行，xcodebuild 退出码 65。
- 执行时间: 第 1 轮 2026-10-26T08:15:15+08:00 至 2026-10-26T09:12:23+08:00；第 2 轮 2026-10-26T09:13:42+08:00 至 2026-10-26T10:12:24+08:00。
- 证据: 以下 20 个稳定失败均为两轮各 3/3 失败、合计 6/6；截图和层级取第 1 轮第一次失败。另 1 个断言型时好时坏取第 2 轮第一次失败。21 张失败截图均已逐张打开检查。[逐次结果](pr37/test-attempts.json)；[附件来源](pr37/evidence-index.json)。
- 稳定失败:
  - testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop | Tests/YubaiUITests/AppFlowTests.swift:1075 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 仍在现在根页，待付卡片显示上月账单、房租和“还有 1 笔”，底部栏可见。 | [截图](pr37/testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop.png) | [层级](pr37/testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop.txt)
  - testClosedLedgerRowPagesRightAndRevealedRowClosesFirst | Tests/YubaiUITests/AppFlowTests.swift:1251 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 账目页显示一笔合成咖啡 −32.00，行未展开，屏幕没有删除按钮。 | [截图](pr37/testClosedLedgerRowPagesRightAndRevealedRowClosesFirst.png) | [层级](pr37/testClosedLedgerRowPagesRightAndRevealedRowClosesFirst.txt)
  - testDueCardIncludesPreviousMonthAndLinksOverflowToBills | Tests/YubaiUITests/AppFlowTests.swift:637 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 现在页待付卡片显示上月账单 10、房租 300 和“还有 1 笔”，未进入固定收付页。 | [截图](pr37/testDueCardIncludesPreviousMonthAndLinksOverflowToBills.png) | [层级](pr37/testDueCardIncludesPreviousMonthAndLinksOverflowToBills.txt)
  - testFixedBillCheckMarksPaidAndUndoRestoresIt | Tests/YubaiUITests/AppFlowTests.swift:411 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 固定收付页房租已显示勾选和“已付”，本月还要付为 0，屏幕未见撤销提示。 | [截图](pr37/testFixedBillCheckMarksPaidAndUndoRestoresIt.png) | [层级](pr37/testFixedBillCheckMarksPaidAndUndoRestoresIt.txt)
  - testFixedBillGroupedSwipesKeepCardAndContentGeometry | Tests/YubaiUITests/AppFlowTests.swift:565 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 固定收付页房租与话费同组且均显示“付了”，各行未展开，未见停掉操作。 | [截图](pr37/testFixedBillGroupedSwipesKeepCardAndContentGeometry.png) | [层级](pr37/testFixedBillGroupedSwipesKeepCardAndContentGeometry.txt)
  - testFixedBillsStateTextAndUpcomingHasOnlyContextAction | Tests/YubaiUITests/AppFlowTests.swift:709 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 固定收付页视频会员、房租、话费均显示已付，工资显示已收到，全部带勾选。 | [截图](pr37/testFixedBillsStateTextAndUpcomingHasOnlyContextAction.png) | [层级](pr37/testFixedBillsStateTextAndUpcomingHasOnlyContextAction.txt)
  - testFixedBillStopAndResumeBothSupportUndo | Tests/YubaiUITests/AppFlowTests.swift:512 | Failed to get matching snapshot: Find single matching element. Multiple matching elements found for <XCUIElementQuery: 0x115c04c30>. | 屏幕停在“停掉「工资」？”确认框，包含记一笔再停、没收到和取消三个按钮。 | [截图](pr37/testFixedBillStopAndResumeBothSupportUndo.png) | [层级](pr37/testFixedBillStopAndResumeBothSupportUndo.txt)
  - testFixedBillStopHandlesEveryUnsettledPeriod | Tests/YubaiUITests/AppFlowTests.swift:763 | Failed to get matching snapshot: Find single matching element. Multiple matching elements found for <XCUIElementQuery: 0x115c05860>. | 屏幕停在“停掉「每周订阅」？”确认框，显示还有 6 期没记及三个操作按钮。 | [截图](pr37/testFixedBillStopHandlesEveryUnsettledPeriod.png) | [层级](pr37/testFixedBillStopHandlesEveryUnsettledPeriod.txt)
  - testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow | Tests/YubaiUITests/AppFlowTests.swift:481 | XCTAssertTrue failed | 工资行已收到并带勾选，前方显示“停掉「工资」？”确认框和取消、停掉以后的两个按钮。 | [截图](pr37/testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow.png) | [层级](pr37/testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow.txt)
  - testFixedIncomeStopSkipCancelPersistenceAndUndo | Tests/YubaiUITests/AppFlowTests.swift:730 | Failed to get matching snapshot: Find single matching element. Multiple matching elements found for <XCUIElementQuery: 0x115c06f30>. | 屏幕停在未记工资的停止确认框，显示记一笔再停、没收到和取消三个按钮。 | [截图](pr37/testFixedIncomeStopSkipCancelPersistenceAndUndo.png) | [层级](pr37/testFixedIncomeStopSkipCancelPersistenceAndUndo.txt)
  - testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible | Tests/YubaiUITests/AppFlowTests.swift:1621 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 账目搜索框为空，中文候选键盘仍覆盖屏幕下部，浮动底栏不可见。 | [截图](pr37/testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible.png) | [层级](pr37/testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible.txt)
  - testLedgerRevealClosesAfterTabSelectionAndPaging | Tests/YubaiUITests/AppFlowTests.swift:1351 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 账目页仍显示合成咖啡 −32.00，行未展开，底栏选中账目。 | [截图](pr37/testLedgerRevealClosesAfterTabSelectionAndPaging.png) | [层级](pr37/testLedgerRevealClosesAfterTabSelectionAndPaging.txt)
  - testLedgerSwipeDeleteAndUndoRestoresRow | Tests/YubaiUITests/AppFlowTests.swift:1438 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 账目页本月支出已为 0，显示“这个月还没有账目”，未见撤销提示。 | [截图](pr37/testLedgerSwipeDeleteAndUndoRestoresRow.png) | [层级](pr37/testLedgerSwipeDeleteAndUndoRestoresRow.txt)
  - testManualAndAskActionsPreserveTheSelectedPage | Tests/YubaiUITests/AppFlowTests.swift:1605 | Failed to swipe right NavigationBar (First Match): No matches found for first query match sequence: `Descendants matching type NavigationBar`, given input App element pid: 59152 | 记一笔面板仍打开，金额为 0，顶部有取消和导入，底部数字键盘可见。 | [截图](pr37/testManualAndAskActionsPreserveTheSelectedPage.png) | [层级](pr37/testManualAndAskActionsPreserveTheSelectedPage.txt)
  - testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt | Tests/YubaiUITests/AppFlowTests.swift:1303 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 账目页显示多笔合成账目，本月支出 1,600，各行保持关闭，未见删除按钮。 | [截图](pr37/testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt.png) | [层级](pr37/testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt.txt)
  - testRevealedLedgerRowConsumesSwipesInBothDirections | Tests/YubaiUITests/AppFlowTests.swift:1273 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 账目页显示合成咖啡 −32.00，行处于关闭状态，未见删除按钮。 | [截图](pr37/testRevealedLedgerRowConsumesSwipesInBothDirections.png) | [层级](pr37/testRevealedLedgerRowConsumesSwipesInBothDirections.txt)
  - testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab | Tests/YubaiUITests/AppFlowTests.swift:1327 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 账目页显示合成咖啡 −32.00，行未展开，底栏仍选中账目。 | [截图](pr37/testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab.png) | [层级](pr37/testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab.txt)
  - testTabTapReturnsToLedgerAfterRightSwipe | Tests/YubaiUITests/AppFlowTests.swift:1136 | XCTAssertEqual failed: ("XCTWaiterResult(rawValue: 2)") is not equal to ("XCTWaiterResult(rawValue: 1)") | 屏幕已显示账目页和合成咖啡 −32.00，底栏账目标签呈选中样式。 | [截图](pr37/testTabTapReturnsToLedgerAfterRightSwipe.png) | [层级](pr37/testTabTapReturnsToLedgerAfterRightSwipe.txt)
  - testUndoReceiptDismissesAfterProductionLifetime | Tests/YubaiUITests/AppFlowTests.swift:428 | XCTAssertTrue failed | 固定收付页房租已付并带勾选，本月还要付为 0，屏幕未见撤销提示。 | [截图](pr37/testUndoReceiptDismissesAfterProductionLifetime.png) | [层级](pr37/testUndoReceiptDismissesAfterProductionLifetime.txt)
  - testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo | Tests/YubaiUITests/AppFlowTests.swift:582 | XCTAssertTrue failed | 还能花计算面板上弹出“停掉「房租」？”确认框，取消和停掉以后的按钮均可见。 | [截图](pr37/testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo.png) | [层级](pr37/testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo.txt)
- 时好时坏:
  - testCancelledNestedBackKeepsTabBarHiddenUntilSettingsRoot | 1/3（第 1 轮 0/1；第 2 轮 1/2，重试通过） | Tests/YubaiUITests/AppFlowTests.swift:1062 | XCTAssertTrue failed | 屏幕已返回我根页，消费观 0 条、心愿 0、账户 1,000、固定收付 0 项，底栏我标签选中。 | [截图](pr37/testCancelledNestedBackKeepsTabBarHiddenUntilSettingsRoot.png) | [层级](pr37/testCancelledNestedBackKeepsTabBarHiddenUntilSettingsRoot.txt)
  - testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet | 1/2（第 1 轮中断；第 2 轮首次通过） | 无源码位置（进程中断） | Test crashed with signal term. | 失败瞬间状态未知，未产生 failure 截图及 failure-hierarchy。 | 截图缺失 | [层级缺失说明](pr37/testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet-evidence-gap.txt)
- 失败位置: 20 个稳定失败在两轮的全部 6 次失败位置均一致，如上逐项列出；nested 测试唯一失败位于 1062 行；中断测试无源码行号。
- 原来失败的 23 个:
  - testFixedBillCheckMarksPaidAndUndoRestoresIt | 稳定失败
  - testFixedBillSwipeStopsFutureOccurrencesAndKeepsPaidRow | 稳定失败
  - testFixedBillStopAndResumeBothSupportUndo | 稳定失败
  - testDueCardIncludesPreviousMonthAndLinksOverflowToBills | 稳定失败
  - testButlerSwipeDismissesWithoutSwitchingTabs | 第一次通过（两轮均首次通过）
  - testButlerRightSwipeAtFirstPagePreservesCardAndPaging | 第一次通过（两轮均首次通过）
  - testClosedLedgerRowPagesRightAndRevealedRowClosesFirst | 稳定失败
  - testRevealedLedgerRowConsumesSwipesInBothDirections | 稳定失败
  - testOnlyOneLedgerRowRevealsDeleteAndOutsideTapClosesIt | 稳定失败
  - testRevealedLedgerRowSlowLeftSwipeKeepsCurrentTab | 稳定失败
  - testLedgerRevealClosesAfterTabSelectionAndPaging | 稳定失败
  - testLedgerSwipeDeleteAndUndoRestoresRow | 稳定失败
  - testManualAndAskActionsPreserveTheSelectedPage | 稳定失败
  - testFloatingNavigationHidesForKeyboardAndLeavesLastLedgerRowVisible | 稳定失败
  - testFixedBillGroupedSwipesKeepCardAndContentGeometry | 稳定失败
  - testUpcomingPaymentStopUsesAlertAndSupportsCancelAndUndo | 稳定失败
  - testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet | 时好时坏（第 1 轮中断，第 2 轮首次通过）
  - testEntrySheetWithPurposeSuggestionsKeepsActionsAboveHomeIndicator | 第一次通过（两轮均首次通过）
  - testCancelledInsightBackKeepsTabBarHiddenAndPagingLocked | 第一次通过（两轮均首次通过）
  - testCancelledOverviewBackRestoresTabBarOnlyAfterCompletedPop | 稳定失败
  - testFixedBillsStateTextAndUpcomingHasOnlyContextAction | 稳定失败
  - testFixedBillStopHandlesEveryUnsettledPeriod | 稳定失败
  - testFixedIncomeStopSkipCancelPersistenceAndUndo | 稳定失败
- 原 23 个汇总: 4 个第一次通过、1 个时好时坏（中断后通过）、18 个稳定失败。
- 新测试 testUndoReceiptDismissesAfterProductionLifetime: 稳定失败，两轮各 3/3 失败，均位于 AppFlowTests.swift:428，XCTAssertTrue failed。

## 其他
- 运行中断: 第 1 轮 testScrolledRootHeadersStayInsideSafeAreaWhenOpeningEntrySheet 执行约 173.405 秒后被记录为 “Test crashed with signal term.”；runner 重启后继续执行其余测试，但该测试没有得到 3 次尝试。未发现另一 xcodebuild test 占用该模拟器，未主动终止进程，具体终止原因未查明。日志未出现字面量 “Termination requested by simulator host”。按请求在同一模拟器、同一提交、不变更参数的情况下完整重跑一次，第 2 轮无此中断，该测试首次通过。未进行第三轮测试。
- 环境诊断: 日志出现 invalidDigitCount / 找不到可附加调试器 URL 等工具诊断；编译仍成功，未据此认定测试失败根因。simctl runtime 名称为 iOS 26.4，以上系统版本使用 xcresult 的实际设备记录 26.4.1。
- 证据缺口: 中断测试没有导出首次失败截图或界面层级，已明确保留缺失，未用重跑成功截图或普通步骤截图替代。稳定失败、时好时坏及证据缺口均不满足 PASS 规则。
- 范围: 只运行现有本地编译及全部 YubaiUITests，使用测试夹具和脚本回复；未调用 DeepSeek 或付费 API，未运行 GitHub Actions，未登录、购买、合并或修改应用/测试代码。新增或改动的可见中文字符串: 无。
- 收尾: 已切回 main；"before pr37 verify" stash 已恢复且仅移除此条；"xcode signing before v16 check" stash 仍在，全部 3 条既有 stash 的 hash 与顺序均与开始前一致；git status --short -uall 与开始前完全一致。main HEAD 仍为 cfe155c51c43c2f98dcf79e4aa91bcf1987743e0，原 project.pbxproj、Package.resolved 和 Xcode 界面状态均已逐字节恢复核对。
- 编译生成的 workspace 已先移出仓库保存，未与 stash 覆盖；测试日志、xcresult 和报告副本移出仓库留作失败证据，仓库中的 build.log、test.log、ui.xcresult、.verification 已收走；现有模拟器保留。报告通过独立临时 Git index 提交到 chore/verify-pr37，避免再次切换已恢复的脏工作区。
