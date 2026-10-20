# 界面入口

当前 2.0 采用三个入口，暖纸样式沿用 [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift)。

| 入口 | 动作与下级内容 |
|---|---|
| 现在 | 每周来信、管家卡片；保守可动用 → 计算依据；待付款行 → 结束安排；导入账单 → 账户对应、预览、整理、少量问答 |
| 我 | 我的消费观（领域、原则、目标、底线）、心愿单、账户（编辑与核对）、导入记录（整批撤销）、智能与隐私、备份与恢复、使用指南 |
| 问余白 | 导航容器底部常驻；提问／截图／语音 → 数字回答与依据 → 记录详情；修改提案 → 用户确认；购买商量 → 心愿单 |

管家卡片可选「知道了」或「以后别提」。记录详情保留原始来源，删除后通过撤销或恢复版本找回。导入记录与恢复版本分开；恢复版本在备份页面下。

iPhone 使用两个原生 tab「现在／我」，Mac 使用对应侧栏；两端均保留底部问余白。当前代码入口为 [YubaiApp.swift](../Sources/YubaiApp/YubaiApp.swift)，新交互测试为 [AppFlowTests.swift](../Tests/YubaiUITests/AppFlowTests.swift)。当前无 Swift 工具链，尚未验证编译、底部安全区、辅助字号或 VoiceOver。

[历史 1.0 全动作 Figma](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=13-3367) 和 [2026-10-08 浏览基线](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=40-6983) 保留，尚未同步本次导航；历史画布状态见 [Figma 记录](UI-UX-FIGMA.md)。它们不作为 2.0 的操作指南。
