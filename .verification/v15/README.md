# 第十五轮截图 · 2026-10-23

feat/butler-saving-core（2a51c45），Debug，iOS 模拟器 iPhone 17 Pro / iOS 26.4（新建的独立模拟器，避开同时在跑的另一组测试），浅色、默认字号。全部用 UITestSupport 合成夹具与脚本化回复，没有联网、没有调用付费 API。

| 文件 | 内容 | 来源 |
|---|---|---|
| judge-ask | 问余白 · 徒步鞋 → 三道追问卡 | testJudgeAskScreenshotFixture |
| judge-wait | 结论：等等再说 | testJudgeWaitScreenshotFixture |
| judge-buy | 结论：买吧 | testJudgeBuyScreenshotFixture |
| judge-skip | 结论：先别买（降噪耳机，差 620） | testJudgeSkipScreenshotFixture |
| wishlist-cool | 心愿单：省下的、冷静期到期卡、冷静中 | testWishlistCoolScreenshotFixture |
| letter-saving | 每周来信：省下的、这些还在用吗 | testLetterSavingScreenshotFixture |
| profile-progress | 我的消费观（克制进度） | testProfileRevisitScreenshotFixture |
| profile-revisit-opening | 再聊页开场 | testProfileRevisitScreenshotFixture |
| profile-revisit-just-sent | 再聊页点发送后、回复到达前（YUBAI_UI_PROFILE_REPLY_DELAY=3） | testProfileRevisitScreenshotFixture |
| profile-revisit-reply | 再聊页收到回复后 | testProfileRevisitScreenshotFixture |
| now-restrain-near | 现在页「外卖 · 本周第 3 次」 | profile-revisit 夹具 simctl 启动后截屏 |
| subcategory-shopping | 洞察 › 购物 · 本月 小项页 | testSubcategoryScreenshotFixture |
| subcategory-outdoor-records | 运动户外 原账目 | testSubcategoryScreenshotFixture |
| entry-subcategory-row | 记录详情的分类行 | testSubcategoryScreenshotFixture |
| subcategory-picker | 小项选择 | testSubcategoryScreenshotFixture |

judge-ask 截于三道题出现时；该测试随后在点「就这样回答」时失败（见报告）。
