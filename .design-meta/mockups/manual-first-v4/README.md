# 第四轮 · 手动优先

2026-10-21 owner 明确批准并要求按稿实现；以下 HTML 与 DS 从本轮提供的 mockups 目录原样归档，没有改写原稿中的历史说明。它们取代 V3／Motion v2 中“独立圆钮是问余白、缺少手动记账与总账”的入口约定。Motion v2 的系统玻璃与既有动效继续使用。

- [现在](V4-Home.dc.html)、[保存后](V4-Home-Saved.dc.html)
- [记一笔](V4-Add.dc.html)、[账目](V4-Entries.dc.html)、[改一笔](V4-Entry-Edit.dc.html)
- [问余白空态](V4-Ask-Empty.dc.html)、[打字中](V4-Ask-Typing.dc.html)、[我](V4-Me.dc.html)
- [固定收付沿用的安排稿](P-Plans.dc.html)、[添加安排](P-Plan-Edit.dc.html)
- [设计系统](DS-README.md)、[助手输入条](DS-AskBar.md)、[数字键盘](DS-Keypad.md)

这是静态设计源文件归档。HTML 原有的 support.js、tokens.css 与在线字体引用保持原样，归档不声称可独立运行，也没有加载网络资源。实际运行实现与 token 权威为 `Sources/YubaiApp`；[逐稿映射与适配边界](../../DESIGN.md#2026-10-21--第四轮手动优先)。稿中金额、商户、时间和条数都是样例，App 使用真实账本计算。

Linux Core 测试已执行；Apple SwiftUI 编译、UI 测试、390×844 首屏、输入框基线、深色／大字号／减少动态效果及真机验收未执行。没有提交、推送或修改原有 Figma／历史原型／分发包。
