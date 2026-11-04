# PR #62 + #63 Mac 验证报告

- 提交：`55d66879d7d8ad762c42b7ed39657c54698ca319`（main）。
- Xcode 27.1，Build version 27A9275；指定现有 iPhone 17 Pro Max 模拟器 `37FDA39F-AF08-48EA-9E35-0AAB017AAFE0`。
- 2026-11-04，本轮不改产品代码、不读密钥、不调用 DeepSeek（0 次请求），不用 GitHub Actions，不新建 worktree/模拟器，不操作真机 App。
- 执行环境显式设置 `YUBAI_LIVE_EVAL=0 DEEPSEEK_API_KEY=`；live DeepSeek 用例跳过。

## 1. Core：总数 / 失败

`swift test` 退出 1。735 项，跳过 4 项，5 个失败断言，分布于 4 个失败用例。

| 用例 | 结果 |
|---|---|
| ImportOrganizerTests.testPartyCheckpointCancellationResumeAndRecordProgressNeverResendsGroups | 1 个 XCTAssertTrue 失败，1358 行 |
| StoragePolicyTests.testMissingPayloadDoesNotEvictTheLastCompleteRecovery | 1 个 XCTAssertTrue 失败，115 行 |
| StorageTests.testHistoryBudgetRemovesLegacySidecarsAndProtectsUnreadablePayloadReferences | 1 个 XCTAssertEqual 失败，239 行；输出可见 /private/var 与 /var 路径差异 |
| StorageTests.testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten | 2 个 XCTAssertEqual 失败，341 行；用户已说明为 Mac 既有 lazy-attachments 问题，本轮仍复现 |

其余失败的归因未通过基线对比证实，不宣称均为本轮回归。断言原文（包括前 3 条）：

```text
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/ImportOrganizerTests.swift:1358: error: -[YubaiCoreTests.ImportOrganizerTests testPartyCheckpointCancellationResumeAndRecordProgressNeverResendsGroups] : XCTAssertTrue failed
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StoragePolicyTests.swift:115: error: -[YubaiCoreTests.StoragePolicyTests testMissingPayloadDoesNotEvictTheLastCompleteRecovery] : XCTAssertTrue failed
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:239: error: -[YubaiCoreTests.StorageTests testHistoryBudgetRemovesLegacySidecarsAndProtectsUnreadablePayloadReferences] : XCTAssertEqual failed: ("[file:///private/var/folders/_s/6rwp6y017dd_xw9d3_q4g0940000gn/T/yubai-payloads-3853FDB4-FB9D-4C53-BDC8-0BF61B66205D/Recovery/2000-unreadable-%E5%8E%9F%E6%96%87%E4%BB%B6.json.gz, file:///private/var/folders/_s/6rwp6y017dd_xw9d3_q4g0940000gn/T/yubai-payloads-3853FDB4-FB9D-4C53-BDC8-0BF61B66205D/Recovery/1500-legacy-%E5%8F%AF%E8%AF%BB%E7%89%88%E6%9C%AC.json]") is not equal to ("[file:///var/folders/_s/6rwp6y017dd_xw9d3_q4g0940000gn/T/yubai-payloads-3853FDB4-FB9D-4C53-BDC8-0BF61B66205D/Recovery/2000-unreadable-%E5%8E%9F%E6%96%87%E4%BB%B6.json.gz, file:///var/folders/_s/6rwp6y017dd_xw9d3_q4g0940000gn/T/yubai-payloads-3853FDB4-FB9D-4C53-BDC8-0BF61B66205D/Recovery/1500-legacy-%E5%8F%AF%E8%AF%BB%E7%89%88%E6%9C%AC.json]")
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:341: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-11-04 06:08:04 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
/Users/yang/deepresearch/yubai/Tests/YubaiCoreTests/StorageTests.swift:341: error: -[YubaiCoreTests.StorageTests testSavedAndLoadedAttachmentsAreLazyAndImmutablePayloadsAreNotRewritten] : XCTAssertEqual failed: ("Optional(2026-11-04 06:08:04 +0000)") is not equal to ("Optional(1970-01-01 00:01:40 +0000)")
```

## 2. UI：总数 / 失败；四个重点用例逐条

请求全量测试，但构建阶段失败，实际执行 UI 用例 0 项；不是 UI 全部通过，也不是 UI 断言失败。

首次执行用户指定命令，增加 `-parallel-testing-enabled NO` 和独立 result bundle，退出 65。首个且唯一不同的 error：

```text
Sources/YubaiWidgets/YubaiWidgets.swift:5:8: error: Unable to resolve module dependency: 'YubaiCore' (in target 'YubaiWidgets' from project 'Yubai' at path '/Users/yang/deepresearch/yubai/Yubai.xcodeproj')
```

日志显示 x86_64 构建路径。保留原结果后，以相同模拟器和 derivedData 指定 `arch=arm64 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` 再试，退出 65。首个且唯一不同的 error（另一行是同一诊断的重复显示，没有 3 个不同 error）：

```text
/Users/yang/deepresearch/yubai/Sources/YubaiApp/CashTimelineCard.swift:184:14: error: instance method 'simultaneousGesture(_:including:)' requires that 'CashTimelinePress' conform to 'Gesture'
```

`CashTimelinePress` 在同文件 280 行声明为 `UIGestureRecognizerRepresentable`。本轮仅验证，未修改该实现。

| 重点用例 | 实际结果 |
|---|---|
| testCashTimelineHoldAndDragKeepsTheCurrentTab | 未运行：编译阻塞 |
| testCashTimelineIsBelowFundsAndPansWithinBoundsThenReturnsToToday | 未运行：编译阻塞 |
| testCashTimelineLowFloorUsesTwoDecimalsAndAmountPrivacyHidesThePlot | 未运行：编译阻塞 |
| testStorageEntryAndOverviewOpenFromMe | 未运行：编译阻塞 |

尚未进入 App/UI 测试，因此没有失败 UI 截图可导出。原始本地日志：`/tmp/yubai-verify6263-ui.log`、`/tmp/yubai-verify6263-arm64.log`、`/tmp/yubai-verify6263/core.log`；result bundles：`/tmp/yubai-verify6263-full.xcresult`、`/tmp/yubai-verify6263-arm64.xcresult`。

## 3. 截图对照：4 张逐项一致/不一致；拖动边界和「今天 ›」

已用 Chrome headless 按 390×844 CSS px、2 倍像素比渲染四张仓库 HTML，保存在 `pr62-63/`。这些仅为设计原稿截图，不能冒充模拟器截图或对照拼图。设计 README 声明缺少部分相对依赖，因此渲染结果也不等同完整原设计环境。

| 状态 / 设计截图 | 卡片位置 | 标题行 | 实线/虚线/浅色带 | 今天竖线 | 最低点 | 滚动条 | 今天 › |
|---|---|---|---|---|---|---|---|
| [默认](pr62-63/V28-Home-Cashflow.dc.png) | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |
| [按住工资日](pr62-63/V28-Home-Cashflow-Scrub.dc.png) | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |
| [低于始终留着](pr62-63/V28-Home-Cashflow-Low.dc.png) | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |
| [最早窗口](pr62-63/V28-Home-Cashflow-Earlier.dc.png) | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 |

编译阻塞，未取得同夹具 App 的四个状态截图，无法制作真实并排对照，也无法判定一致/不一致。继续向前拖的边界和点「今天 ›」返回默认均未验证；没有拿旧安装包代替本次提交。

## 4. 存储：Recovery 份数和大小、Cache.db 有无、恢复页小标题

编译阻塞，未执行模拟器假数据导入/整理，因此本轮 Recovery 份数、总大小、`Library/Caches` 中 `Cache.db*` 是否存在均未取得；不以旧容器状态冒充本次运行结果。

静态源码 `Sources/YubaiApp/SettingsView.swift:369` 确有 `Text("最近 8 份账本")`，仅证明源码文字存在，恢复页实际小标题及截图未验证。

## 5. 收尾：stash 情况

本轮创建 `before verify pr62-63` stash（含原有未跟踪 Package.resolved）。构建再生成的同路径文件经 blob hash 比较与原 stash 完全相同，仅移除再生成副本后执行本轮 stash pop，成功且无冲突；原有未跟踪文件已恢复。本轮之前的 stash 保留。

报告和四张设计截图提交到 `chore/verify-pr62-63-2026-11-04`，完成推送后切回 main；产品代码、测试文件均未修改，可见中文字符串无新增或修改。

## 结论：FAIL

Core 有 5 个失败断言（4 个失败用例，含已知 lazy-attachments）；App arm64 编译失败。全量 UI、四组 App/设计并排对照、拖动交互和模拟器存储验收均未完成。报告和设计截图只能交付已取得的证据，不能视为 PR #62/#63 验收通过。
