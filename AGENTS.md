# 余白项目入口

<!-- product-design:start -->
## 产品与设计协作

- 术语与界面用词读取 [CONTEXT.md](CONTEXT.md)。
- 设计系统与设计稿是仓库外的私有页面，链接不进仓库，由 owner 或 Claude 在任务里提供。涉及界面、交互、视觉、动效的改动，先改设计稿、经 owner 确认，再按稿写代码。
- 历次改动记录见 [docs/HISTORY.md](docs/HISTORY.md)；更早的设计稿、产品决策票和验证记录已从工作区移除，需要时从 git 历史查看。
<!-- product-design:end -->

## 界面文案：少写字，让版式说话（owner 2026-10-23 定，所有 UI 改动必须遵守）

> Avoid unnecessary secondary labels and descriptions. Let the layout do the explaining.

写 SwiftUI 时：

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
2. **画布**（页面原型与交互）是给 owner 看的呈现，用来提前看清 iPhone 上的真实样子。必须模拟真机：标准 iPhone 视口、状态栏与灵动岛、底部安全区与 Home Indicator、按压弹簧反馈；导航栏、半屏、底栏等控件按设计框架自绘。只画 SwiftUI 能 1:1 实现的效果；颜色、字号、圆角、组件全部引用设计框架，不另起炉灶。

### 三、冲突仲裁

1. 新旧 API：Apple 官方 Skill 优先于社区 Skill，无条件。
2. Web 示例 vs 原生：`apple-design` 只吸收物理原则（弹簧、1:1 跟手、松手继承速度、动画中途可打断）。落到 SwiftUI 100% 用原生：`.clipShape(.rect(cornerRadius:style: .continuous))`、`Animation.spring` / `KeyframeTimeline`、`.sensoryFeedback`。忽略其中的 CSS 毫秒 transition、`backdrop-filter` 示例和「Initial Response」开场白；弹簧参数只用 `design-tokens.json` 的 snappy / smooth / standard / bouncy。
3. 品牌视觉 vs 系统默认：外观服从设计框架（定制色板、定制悬浮栏、Switch 等）；底层几何（连续圆角）、弹簧手感、触觉、无障碍服从 Apple 与 `apple-design`。设计框架或画布里出现 SwiftUI 无法 1:1 复现的效果（如 `spread` 扩散阴影、任意 blur），先向 owner 指出差异并给 2 个原生替代方案，由 owner 拍板，不私自改设计。
4. 社区规范之间：取当前最低 iOS 版本下更简洁、零多余抽象的写法。控件外观全部自绘（见下节），不用系统 Liquid Glass 外观；其中建议安装 RocketSim 等第三方工具时，先问 owner。

### 四、每轮交付闭环

1. 先画布后代码：新页面或改版先按下节「设计稿交付标准」交稿，并标明引用了设计框架的哪些组件与 token。
2. owner 确认画布后，再产出严格对齐的 SwiftUI 与 `#Preview`，保证画布、设计框架、SwiftUI 三者一致；实现中发现画布不合理，先回头改画布。
<!-- ios-agent-skills:end -->

## 设计稿交付标准（owner 2026-11-27 定，取代「画布给出贴近真机的完整呈现」这一笔带过的要求）

做设计的 agent 按专业 UI/UX 与动效设计师的标准交稿。样板：画布「余白 · 设计规格 v2」（2026-11-27，链接由 owner 或 Claude 在任务里提供）。

1. 可点原型：一部能从头点到尾的 iPhone 原型，带状态栏、灵动岛、Home 条；颜色、字号、间距、圆角、弹簧全部引用设计框架 token。
2. 状态板：每页的默认、按下、选中、禁用、空、加载、出错、极端内容（长名字、9 位数金额、0 笔）、深色、最大字号逐张画出；不值得单独画的，写进状态清单。
3. 规格页至少有这几块：
   - 问题对照：看到的 → 根因（查到代码行）→ 设计决定 → 对应画板。
   - 手势：起手阈值、跟手方式、松手怎么判、触感、冲突与无障碍。
   - 动效：只用四种弹簧；每个状态变化写清什么在动、交代了什么、减弱动态效果时怎么办。
   - 标注：关键页面的尺寸、间距、token。
   - 状态清单：每种状态要么链到画板，要么写一句规则，实现时照着做、不猜。
   - 大字号与无障碍：字号放大后怎么排、VoiceOver 怎么读。
   - 涉及算法或数据口径的，单列一块写清规则和测试用例。
4. 只画做得出来的：每个按钮都要点出真实结果；系统不给 App 的信息（例如小组件加没加）不画成状态；SwiftUI 有原生做法的（如 `.swipeActions`）写明用原生。
5. 要 owner 拍板的产品决定用选择卡单独问，给建议项；不藏在稿子里。
6. 真机问题先分类：界面类进稿子；纯算法、数据类直接改代码并补测试，不等设计。
7. 评审在画布上进行：owner 留评论，agent 逐条在评论里回复并改稿，全部解决、owner 说「没问题」后才进入写代码。

## 界面框架与做法（owner 2026-11-25 定，取代「原生组件优先」「底栏用系统玻璃」「仅浮层用玻璃」）

依据：记一笔一屏用 SwiftUI 自绘和 UIKit 各做一遍的对比试验（分支 `feat/entry-framework-bakeoff`，仅作试验，不合并）：静态画面差 0.3%，真机 40 圈自动演示两边都几乎无卡顿。

1. 新界面留在 SwiftUI，从零重写。只有量出来 SwiftUI 做不到的地方才用 UIKit 补，并写明量到的数据。
2. 控件外观全部按设计框架自绘（底栏、开关、分段、按钮、半屏等）；手势、触觉、无障碍、键盘等行为用系统的。
3. 数字规格：每批页面先从高保真画布把尺寸、间距、字号、圆角、颜色抄成一份数字规格（有 token 用 token，没有的集中在一个规格文件并注明画布来源），代码只照规格画。
4. 写界面的 agent 在 owner 的 Mac 上边看边改：每改一处就编译、启动、截图、对照规格，修到对为止；交付包含截图、录屏、日志、报告。
5. 动效在真机上量：App 内自动演示 + 系统 Animation Hitches 录制，不用模拟器录屏判断流畅度。当前 Xcode 27.1 对 iOS 27.2.1 的真机自动测试连不上，不要在真机上用 XCTest 驱动手势。
6. 拖动和动画进行中不重新生成整屏或整块内容，逐帧变化的状态放在最小范围里；验收时报告动画期间内容的重算次数。
7. 不知道怎么做的功能或动画，先看 Telegram 的做法（项目共享文件夹 `reference/telegram-ios/`，源码不进仓库），只学思路不复制（GPL）。

## 过程不欠债（owner 2026-11-25 定）

谁开发谁收尾：每个开发任务（Claude、Codex、Mac 上的 agent 都一样）做完就删掉自己产生的临时东西，并在交付报告里列出删了什么。Claude 交接开发任务时，prompt 末尾固定写上这一步。

1. 任务结束时删：临时 worktree、stash、临时分支、`build/<批次>/` 里的中间产物、Instruments 原始 trace（只留摘要和录屏）。PR 合并后删它的分支和这批的 `build/<批次>/` 文件夹。
2. 每批在 Mac 上只用一个 `build/<批次>/` 文件夹，重做就覆盖，不开 `-2`、`-3`。
3. 规则只有一个家：给所有 agent 的写本文件，只管 Claude 的写项目说明，记忆只记事实和链接。新规则写明「取代 xx」，同一次改动删掉旧条。
4. 测试按功能命名，不按轮次。界面改版时，旧界面的测试、截图工具和旧界面在同一个 PR 里删。
5. 验证结果写进 PR 描述，不另开验证分支或验证文档。
6. 不是本任务产生的东西（共享文件夹、owner 的旧文件）不顺手删，列给 owner 确认。
