# 余白项目入口

<!-- product-design:start -->
## 产品与设计协作

- 新对话先读 [.design-meta/README.md](.design-meta/README.md)，了解当前目标、资源状态、未决项和下一步；按当前请求确定本轮范围。
- 涉及产品目标、功能范围或业务规则时，读取 [.scratch/yubai-product/map.md](.scratch/yubai-product/map.md) 及相关子票；术语读取 [CONTEXT.md](CONTEXT.md)。产品知识复用这些权威位置。
- 推进具体决策票时，先读 [tracker 约定](.scratch/yubai-product/README.md)，保留真实用户决策与候选的区别；框架资料维护不等于解决业务票。
- 页面、交互、组件或样式变化时，读取 [.design-meta/DESIGN.md](.design-meta/DESIGN.md)、入口登记的选定稿与实际源码。现有原型为候选，视觉尚未定稿。
- 启动或重整设计流程、选择参考或接入工具时，读取 [产品设计启动协议.md](产品设计启动协议.md) 的相关分支；工具使用前读取本机当前 Skill。
- 本轮允许写入且产生已采用决定或资源变化时，按设计入口的维护表更新对应权威位置及受影响资源；未同步、未验证和待决定事项明确保留。只读咨询只报告建议。
- `.design-meta/` 与 `.scratch/yubai-product/` 中的现有产品记录均为需长期保存的项目资料；保持现有位置，不作为临时缓存清理。
<!-- product-design:end -->

## 界面文案：少写字，让版式说话（owner 2026-10-23 定，所有 UI 改动必须遵守）

> Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.

写 SwiftUI 时：

- 界面上可见的字只有四种：标题、数字和事实、控件上的字（按钮写结果）、状态。副标题、说明句、口号、操作提示、步骤清单、安慰或邀请的话、「例如：…」占位、「（可选）」默认不写。
- 想加一行说明之前，按顺序换成：删掉 → 层级（位置、分组、字重、amber）→ 控件（›、勾框、禁用态、建议芯片、「去设置」按钮）→ 状态和数字 → 挪到发生那一刻（确认框、撤销提示条）。都不行才写一行，且只写事实或数字。
- 设计稿里没有的说明文字，代码里不加；发现设计稿不够清楚，先改设计稿，不用文字补洞。
- 例外：不可撤销操作的确认框写一句后果；出错写原因并给按钮；`accessibilityLabel` / `accessibilityHint` 照写完整；Info.plist 权限说明照写。
- 交付时列出本次新增或改动的可见中文字符串；不属于上面四种的，说明为什么前五步都不行。
