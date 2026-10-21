# 第八轮 · 存储空间

2026-10-21 owner 明确确认本目录三张画板并要求按稿实现，原始 HTML 保持不变：

- [存储空间主页](V8-Storage.dc.html)
- [删除旧截图 sheet](V8-Storage-Photos.dc.html)
- [抹掉全部数据 sheet](V8-Storage-Erase.dc.html)

这是静态设计源文件归档。原稿中的 support.js、tokens.css 与在线字体引用保持原样；本目录未附这些运行资源，不声称可以独立运行，本轮没有加载在线字体或调用设计服务。稿中的 MB、张数、份数、日期和备份天数均为样例，App 按真实账本与本机目录计算。第四轮「我」的备份分组新增存储空间入口，其余第四轮与 Motion v2 约定继续沿用。

原生实现为 `Sources/YubaiApp/StorageView.swift`、`SettingsView.swift`、`YubaiApp.swift`、`LedgerSync.swift`；Core 接口在 `Storage.swift`／`StorageManagement.swift`，配套测试为 `StorageManagementTests.swift`。逐稿映射、系统导航／sheet／动态字体适配见 [DESIGN.md](../../DESIGN.md#2026-10-21--第八轮存储空间)。颜色、字体、卡片、按钮、间距与既有动效继续以 `DesignSystem.swift` 为权威，没有新增动效或依赖。

Linux Core 新增测试已运行；完整运行证据见 [验证记录](../../../docs/VALIDATION.md#第八轮存储空间2026-10-21)。SwiftUI 与 UI 测试源码已做语法解析，尚未在 Apple SDK 下编译或运行；390×844、深色／大字号／VoiceOver、sheet 高度与键盘、真实 iCloud 协调和失败回滚待设备验证。没有提交、推送或同步旧 Figma／原型／分发包。
