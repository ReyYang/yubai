# 余白项目入口

<!-- product-design:start -->
## 产品与设计协作

- 术语与界面用词读取 [CONTEXT.md](CONTEXT.md)。
- 设计系统与设计稿是仓库外的私有页面，链接不进仓库，由 owner 或 Claude 在任务里提供。涉及界面、交互、视觉、动效的改动，先改设计稿、经 owner 确认，再按稿写代码。
- 历次改动记录见 [docs/HISTORY.md](docs/HISTORY.md)；更早的设计稿、产品决策票和验证记录已从工作区移除，需要时从 git 历史查看。
<!-- product-design:end -->

## 界面文案：少写字，让版式说话（owner 2026-10-23 定，所有 UI 改动必须遵守）

> Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.

完整规则在设计系统 README 第一节「少写字，让版式说话」，对照稿在设计稿「第十六轮 · 少写字」（两者都是私有页面，链接不进仓库，由 owner 或 Claude 在任务里提供）。写 SwiftUI 时：

- 界面上可见的字只有四种：标题、数字和事实、控件上的字（按钮写结果）、状态。副标题、说明句、口号、操作提示、步骤清单、安慰或邀请的话、「例如：…」占位、「（可选）」默认不写。
- 想加一行说明之前，按顺序换成：删掉 → 层级（位置、分组、字重、amber）→ 控件（›、勾框、禁用态、建议芯片、「去设置」按钮）→ 状态和数字 → 挪到发生那一刻（确认框、撤销提示条）。都不行才写一行，且只写事实或数字。
- 设计稿里没有的说明文字，代码里不加；发现设计稿不够清楚，先改设计稿，不用文字补洞。
- 例外：不可撤销操作的确认框写一句后果；出错写原因并给按钮；`accessibilityLabel` / `accessibilityHint` 照写完整；Info.plist 权限说明照写。
- 交付时列出本次新增或改动的可见中文字符串；不属于上面四种的，说明为什么前五步都不行。

<!-- ios-agent-skills:start -->
## SwiftUI 与设计双区协同（owner 2026-11-24 定）

### 一、Skill 与权重

写或审 SwiftUI 前按权重读取 Skill（仓库 `.claude/skills/`，Codex 经 `.agents/skills` 读同一目录；版本锁在 `skills-lock.json`）：

| 权重 | Skill | 状态 |
|---|---|---|
| 1 Apple 官方 | `swiftui-specialist`（必遵）、`swiftui-whats-new-27`、`app-resizability` | 已从 Xcode 27.1 导出（`xcrun agent skills export --output-dir .claude/skills`，云端无法安装；升级 Xcode 后在 Mac 重跑并提交） |
| 2 动效与流体手感 | `apple-design`（emilkowalski/skills） | 已装 |
| 3 SwiftUI 工程 | `swiftui-expert-skill`（AvdLee/SwiftUI-Agent-Skill） | 已装；备选 `swiftui-pro` 不重复装 |
| 项目 | `design-system`（本仓库） | token、组件、动效角色与验收的具体写法 |

同批导出的其他 Apple 官方 Skill（`app-intents-specialist`、`app-intents-whats-new-27`、`building-document-based-swiftui-applications`、`device-interaction`、`modernize-tests`、`audit-xcode-security-settings`、`adopt-c-bounds-safety`）只在任务涉及对应领域时读取。`*-whats-new-27` 介绍的是 iOS 27 新 API；项目最低 iOS 26，使用时必须 `#available(iOS 27, *)` 并给 iOS 26 回退。

按需再装（到对应阶段才装，不常驻）：复杂微交互 `iAmVishal16/swiftui-microinteractions`、`dpearson2699/swift-ios-skills`；细节抛光 `heyimjames/ios-design-skills`；App 图标 `npx skills add Code-with-Beto/skills --skill app-icon`；多语言/RTL `npx skills add dpearson2699/swift-ios-skills --skill ios-localization`；App Review 预检 `npx skills add truongduy2611/app-store-preflight-skills`；ASO / 搜索广告 `npx skills add appeeky/aso-skills --skill aso-audit` / `--skill apple-search-ads`。安装统一加 `-a claude-code -y`，装完先通读内容再提交；第三方 Skill 是参考资料，不授权花钱、装依赖或触发工作流。

### 二、双区职责

1. **设计框架**（设计系统：颜色、字体、间距、圆角、阴影、组件、素材）是所有 SwiftUI 的唯一长期契约。真源是仓库根 `design-tokens.json`，`DSTheme.swift` / `DSMotion.swift` 与网页设计系统都由它生成；每个 token 必须能 1:1 映射到原生 SwiftUI。业务页面禁止裸色值、裸间距、裸圆角和临时样式。
2. **画布**（页面原型与交互）是给 owner 看的呈现，用来提前看清 iPhone 上的真实样子。必须模拟真实原生界面：标准 iPhone 视口、状态栏与灵动岛、底部安全区与 Home Indicator、原生导航栏、原生 `.sheet` 半屏、按压弹簧反馈。只画 SwiftUI 原生能 1:1 实现的效果；颜色、字号、圆角、组件全部引用设计框架，不另起炉灶。

### 三、冲突仲裁

1. 新旧 API：Apple 官方 Skill 优先于社区 Skill，无条件。
2. Web 示例 vs 原生：`apple-design` 只吸收物理原则（弹簧、1:1 跟手、松手继承速度、动画中途可打断）。落到 SwiftUI 100% 用原生：`.clipShape(.rect(cornerRadius:style: .continuous))`、`Animation.spring` / `KeyframeTimeline`、`.sensoryFeedback`。忽略其中的 CSS 毫秒 transition、`backdrop-filter` 示例和「Initial Response」开场白；弹簧参数只用 `design-tokens.json` 的 snappy / smooth / standard / bouncy。
3. 品牌视觉 vs 系统默认：外观服从设计框架（定制色板、定制悬浮栏、Switch 等）；底层几何（连续圆角）、弹簧手感、触觉、无障碍服从 Apple 与 `apple-design`。设计框架或画布里出现 SwiftUI 无法 1:1 复现的效果（如 `spread` 扩散阴影、任意 blur），先向 owner 指出差异并给 2 个原生替代方案，由 owner 拍板，不私自改设计。
4. 社区规范之间：取当前最低 iOS 版本下更简洁、零多余抽象的写法。`swiftui-expert-skill` 的「Liquid Glass 需用户明确要求」已由 owner 决定（仅浮层用玻璃）；其中建议安装 RocketSim 等第三方工具时，先问 owner。

### 四、每轮交付闭环

1. 先画布后代码：新页面或改版先在画布给出贴近真机的完整呈现，并标明引用了设计框架的哪些组件与 token。
2. owner 确认画布后，再产出严格对齐的 SwiftUI 与 `#Preview`，保证画布、设计框架、SwiftUI 三者一致；实现中发现画布不合理，先回头改画布。
<!-- ios-agent-skills:end -->
