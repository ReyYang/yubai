# 余白 · 产品与设计入口

**当前选定稿（2026-10-20）**：owner 已批准第三轮 `V3-*.dc.html` 与配套 DS；已在 `refactor/v2-design-alignment` 按稿实现（现在／洞察／我、根页浮动导航与问余白、相关子页），仅静态核查，未编译、未验证真机。以下两 tab 与候选视觉描述保留为本次对齐前的历史状态。

更新：**2026-10-20**。当前目标为「余白 2.0 · 管家」：AI 做事，代码算数，用户决定。`feat/yubai-2-butler` 的步骤 1–9 与 TestFlight 准备已落地源码，步骤 10 同步长期记录；2.0 **仅做静态检查，未编译或运行**。决定来源为 owner 的[产品评审](https://claude.ai/code/artifact/21365038-7478-4933-9c2c-0358b054f5a4)与[规格](https://claude.ai/code/artifact/9e7ad27e-85a3-478d-911e-aa58843ec4d3)，本轮使用 owner 提供的决定摘录，artifact 正文无法读取。用户决定、Agent 实现选择和差异见[第 13 票归档](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-20--余白-20管家决策归档)。

2026-10-20 后续按 owner 明确任务改进[AI 记忆与画像](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-20--ai-记忆与画像改进owner-明确决定)：去掉AI次数上限，增加重复调用复用、字符预算压缩、画像时间、对称反馈、分类记忆和同步记忆合并。只改core、测试、文档及App的时间戳／合并调用，未改视觉、布局或交互，设计资源状态保持。实现与验证边界见[助手文档](../docs/ASSISTANT.md)；无Swift工具链，未编译、运行或提交。

2026-10-20 本轮[记忆层 core](../docs/ASSISTANT.md#余白记得的记忆层-core2026-10-20)已写：生活背景直接保存、读取与撤销、每周回看及画像过期回顾，含测试源码；只改 YubaiCore、测试、文档，未改 YubaiApp。界面与触发接线待设计稿确认；仅静态解析，未编译、运行或提交，设计资源状态保持。

当前入口为 iPhone 两个 tab「现在／我」和 iPhone／Mac 底部常驻「问余白」；Mac 侧栏同样只保留现在与我。云端智能仅用 DeepSeek 轻量 harness，本机模型已移除；旧账本、安排、洞察等独立维护页和应用内示例已删除，示例数据只留测试夹具，旧用户存档字段保持兼容。图表保留在来信与问答中。使用说明见 [README](../README.md)。

当前 UI 由 [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift) 组件构建，属于**候选视觉，并非最终定稿**。2026-10-19 的[390pt 页面稿](https://claude.ai/artifact/FD6H6cqc6qAjsfZqiP8F6p)早于 2.0，需要「同步设计稿」；现有 Figma、HTML 原型、截图与发布包也未同步。消费观画像页、冷启动对话、心愿单、每周来信、导入问题、推送、问余白回答卡片均**尚无对应 2.0 画板**，缺口和源码入口见 [DESIGN.md](DESIGN.md#20-设计资源与缺口2026-10-20)。下一步先补齐这些页面与状态的设计映射，保留候选与最终验收的区别；本轮仅登记缺口，未绘制新稿。

iCloud 已实现，构建默认 `YUBAI_ICLOUD = NO`；付费团队配置好容器后可在本机配置改一行启用，应用内仍需在「我 → 备份与同步」主动选择。账本附件使用同目录文件，冲突保留各版本并由用户选择，恢复历史与设备锁留本机。采用边界见[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#icloud-账本的采用边界)，开关见 [DEVELOPMENT.md](../docs/DEVELOPMENT.md#可选-icloud-账本)。

owner 于 2026-10-20 决定暂不加入付费 Apple Developer Program：先用免费 Personal Team 经 Xcode 直接安装 iPhone 和 Mac，TestFlight 以后再用。[TestFlight 脚本与说明](../docs/TESTFLIGHT.md)、本机配置模板、2.0.0 版本与隐私配置均已准备，未运行归档或上传。Mac 直接安装默认 `YUBAI_MAC_SANDBOX = NO`，沿用原账本位置，与 iCloud 独立；TestFlight Mac archive 强制沙盒，首次为空容器，旧账本须从旧应用导出完整加密备份再恢复。

最后只做一个到 main 的 PR，由 owner 在 Mac 按[组合清单](../docs/V2-TEST-CHECKLIST.md)一次验收；本轮不提交、不推送。静态解析和工程引用结果见 [VALIDATION.md](../docs/VALIDATION.md#余白-20管家静态检查与待验收2026-10-20)，五条 UI 测试等运行检查全部待执行。以下旧日期记录保留历史含义，不作为 2.0 验收证据。

## 历史迁移与安装节点

2026-10-19 续作：按用户指定的[暖纸设计系统](https://claude.ai/artifact/Pz2z4mQNoCqTNLGRafY9v5)与[390pt 页面设计稿](https://claude.ai/artifact/FD6H6cqc6qAjsfZqiP8F6p)迁移已有页面，并完成 Step 3 评审修复。已采用移除三套颜色主题（`Preferences.colorTheme` 仅保留旧存储兼容、界面忽略）、不打包字体而用系统 rounded / serif 回退，以及因暂无助手页面保留原生 `TabView`。本次仅有静态验证；没有 Swift 工具链，未验证 iOS / Mac 编译与真机效果。采用范围与未同步资源见 [DESIGN.md 的迁移记录](DESIGN.md#2026-10-19--设计系统迁移)。下方安装和测试结果保留原日期，不适用于本次迁移。

2026-10-08 当时阶段：**原生 iPhone / Mac 应用已实现；余白 1.0.0 已签名安装到本人 iPhone，本人完成信任并在 Wi-Fi 下验证后已打开应用，业务实际使用核验尚未完成。** 该记录不覆盖 2.0。

## 当前采用的产品与设计

用户于 2026-10-01 委托自主主导完整个人产品，随后确认「iPhone 优先，Mac 也能用」，2026-10-20 明确采用 2.0 管家方向。[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md)区分 owner 的决定与委托下的 Agent 实现选择；候选视觉尚未经用户最终验收。

- 当前实现源：`Sources/YubaiApp` 的原生 SwiftUI 界面；入口为现在、我，以及底部常驻的问余白。共同财务引擎在 `Sources/YubaiCore`。
- 当前候选设计：系统导航与表单、暖纸浅/深色 token、衬线标题与等宽金额、无描边卡片，iPhone 两项原生底部导航、Mac 两项侧栏，问余白使用底部常驻按钮。实现样式以 [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift)为准，详见 [DESIGN.md](DESIGN.md)；组件已使用不等于页面已定稿。
- 交付入口：[安装与使用](../README.md)、[真实验证结果](../docs/VALIDATION.md)、[iPhone 安装前提](../docs/INSTALL-iPhone.md)。未签名归档不能当作可安装 IPA，Mac 编译不代替完整人工体验。
- 当前 2.0 验证只有静态检查；测试使用独立合成夹具，尚未运行。原生导入、账户映射、OCR、持久化、深色与大字号的旧执行证据仅属于 1.0，没有读取用户真实财务资料。
- 历史研究：[2026-10-01 UI/组件与竞品研究](../.scratch/yubai-product/research/2026-10-01-product-and-ui.md)。当前继续使用 SwiftUI、Charts 与系统 Vision；该研究中的 Foundation Models／无外部模型方案已被 2.0 的 DeepSeek 云端单一路径替代。
- 2026-10-02 用户要求在 Codex 的 Figma 绘制所有动作，已建立 [余白全动作 UI / UX](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=13-3367)：111 个 iPhone 界面与状态、11 个 Mac 布局与弹窗，以及组件、变量和参考来源。详见 [交付说明](../docs/UI-UX-FIGMA.md)、[逐动作索引](../docs/UI-UX-ACTIONS.md) 和 [第 14 票](../.scratch/yubai-product/issues/14-figma-action-atlas.md)。
- Figma 依据当时的 1.0 原生源码派生，已做代表截图和结构读回；原型逐路径点击受内嵌播放控件遮挡，未完成。部分系统控件、字体和图标为注明来源的替代示意，不能称逐像素原生还原或用户已验收定稿。它与历史 HTML 原型均保留，尚未同步 2.0。
- 2026-10-04 用户要求 vphone-cli 完整 iOS 测试；2026-10-08 Core 2.4.0、唯一客体和余白 1.0.0 已运行，20 组实际流程结果为 14 通过、4 失败，另有 OCR 与认证环境边界。发现大账本看门狗终止、原文件导出误触撤销、退款分类错位和资金偏好无标签；最终账本数据完整。详见[实际结果](../docs/IOS-E2E-VPHONE.md)。这些问题后来已有修复提交，当前分支未重新运行，不能改写历史结果或宣称 2.0 完整验收通过。

本人曾完成 1.0 的手机开发者信任、验证与首次打开，该次 profile 有效至 2026-10-15 17:32（Asia/Shanghai），现已过期，详情见 [iPhone 安装记录](../docs/INSTALL-iPhone.md)。2.0 须按组合清单重新安装与核对真实来源样本；每周 10 分钟仍是目标，不能由合成夹具推定达成。

## 交互设计探索（2026-10-08）

用户反馈当前信息密度过高，但喜欢现有风格；明确要求先在设计中体验、逐步找问题，不改产品。已创建独立[首页体验稿 v1](prototypes/home-v1/README.md)，预览 http://127.0.0.1:8796/ 。保留深青绿与五项导航，首页减少并列信息，细节点击展开。仅合成内存数据，应用源码和工程44个文件哈希回读均未变化。

这份原型是待反馈的设计候选，尚未取代当前应用与Figma稿。次级编辑、备份和特殊交易等保留范围，部分仅展示入口。已验证范围与未展开边界见[设计QA](prototypes/home-v1/design-qa.md)。此前三组生成图片被用户否定，不作为采用方向。

## 历史记录（2026-09-20，已被上方当前状态更新）

以下保留当时的原始盘点与候选，避免丢失长期项目资料。下面的「本轮」「未实现」「待选择」均指 2026-09-20 的历史阶段。

当时阶段：基础框架已接入；视觉方向待选；正式应用未实现。

余白先服务用户本人：整理分散在微信、支付宝和银行卡的资金，理解房租分摊等已有用途与未来付款，并在购买犹豫时提供有依据的建议。产品事实与未决规则以[产品决策地图](../.scratch/yubai-product/map.md)及其子票为准，术语以 [CONTEXT.md](../CONTEXT.md) 为准；这里负责导航与设计状态。

## 当时建议的下一步（2026-09-20 历史）

- 当前可见候选：[导入结果交互草稿](../.scratch/yubai-product/prototypes/import-result.prototype.html)。用户曾授权制作，尚无选定视觉或完成体验反馈的记录。
- 当前选定稿：无。草稿的绿色、卡片、手机外框和演示控制台均未成为正式视觉约定。
- 建议下一步：继续这份草稿，先观察“整理完能否直接离开，之后能否轻松补充或纠正”；通过具体画面收集反馈，再定正式布局。此为 Agent 建议，不新增产品决策。
- 真正影响后续的未决项：资金计算口径、房租预留规则、云端最少字段、首版范围，以及视觉方向。它们分别保留在原决策票中，不阻塞本次框架交付。

## 资源盘点（2026-10-20 当前状态）

| 资源 | 实际位置与已有内容 | 状态、缺口与后续动作 |
|---|---|---|
| 产品知识 | [决策地图](../.scratch/yubai-product/map.md)、[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md) | 已对齐 2.0 目的地、owner 决定和 Agent 实现选择；额外发言触发、脱敏覆盖与升级数值仍有待对齐／验证项 |
| 领域词汇 | [CONTEXT.md](../CONTEXT.md) | 已补齐管家、消费观、来信、心愿与提案等；旧规则、洞察 tab、应用内示例、本机模型标为历史 |
| 设计约定 | [DESIGN.md](DESIGN.md) | 2.0 组件实现为候选视觉，七类新增页面／状态尚无画板；需要「同步设计稿」 |
| 参考与页面稿 | [2026-10-19 页面稿](https://claude.ai/artifact/FD6H6cqc6qAjsfZqiP8F6p)、上方暖纸设计系统；历史[分类调研](../.scratch/yubai-product/research/transaction-categorization.md) | 页面稿早于 2.0，不能充当新增页面定稿；本轮 artifact 无法读取，未绘制或导出 |
| 历史候选 | [导入结果原型](../.scratch/yubai-product/prototypes/import-result.prototype.html)、[首页 v1](prototypes/home-v1/README.md) | 合成内存交互，保留原位置；行为、导航与视觉均未同步 2.0 |
| 样式与组件 | [DesignSystem.swift](../Sources/YubaiApp/DesignSystem.swift)、[源码登记](DESIGN.md#当前应用设计) | 已有原生 token 与共用组件，2.0 新页面据此构建；编译、视觉、大字号与辅助功能待 Mac 验证 |
| 工具与画布 | [Figma 全动作稿](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=13-3367)、[浏览基线](https://www.figma.com/design/vIJH4tq6ZMNOJeRzUsI2Z7?node-id=40-6983) | 1.0 派生资源已登记，未同步 2.0；本轮未调用绘图工具，也未切换设计面 |
| 验证与分发 | [VALIDATION.md](../docs/VALIDATION.md)、[组合清单](../docs/V2-TEST-CHECKLIST.md)、[TESTFLIGHT.md](../docs/TESTFLIGHT.md) | 仅静态检查；先免费直接安装，TestFlight 准备但未启用，旧截图与包只作历史 |
| 维护入口 | [AGENTS.md](../AGENTS.md)、[项目协议副本](../产品设计启动协议.md) | 沿用下方维护表；tracker 继续区分真实决定、实现选择与候选，长期资料不清理或迁移 |

上述资料均为长期项目资料，包括仍在 `.scratch/yubai-product/` 的权威记录。保留原位置；未来初始化版本管理时一并纳入，不能因目录名而当作缓存清理。2026-10-13 已初始化本地 Git 版本管理，代码、测试、设计资料（含原型与设计证据）和文档纳入首次提交。构建产物、依赖缓存、日志及 `.verification/` 原始运行输出由 `.gitignore` 排除，文件仍保留本地；整理后的验证报告与文档截图纳入版本管理。未配置远端或推送。

## 参考记录

本轮复核了本地研究内容，未重新访问以下官网；事实核查日期沿用 **2026-09-15**，不能据此宣称当前版本已验证。详细来源、访问限制与事实/建议区分见[原调研](../.scratch/yubai-product/research/transaction-categorization.md)。

| 类型与采用状态 | 可打开的来源 | 借鉴意图、适配与证据缺口 |
|---|---|---|
| 同类行为主参考候选：Actual Budget | [分类规则](https://actualbudget.org/docs/budgeting/rules/)、[批量编辑](https://actualbudget.org/docs/transactions/bulk-editing/) | 借鉴稳定分类、纠正后复用及批量整理。余白仍希望首次大批导入少参与；未验证完整操作及 AI 批量效果 |
| 同类补充：钱迹 | [模板导入](https://docs.qianjiapp.com/other/import_templete.html)、[自动记账 AI](https://docs.qianjiapp.com/auto/qianji_auto_ai.html) | 中文交易类型与分类的参考。研究所查 AI 文档针对快捷指令新建账单，不能推广为文件批量能力；不照搬其批量不可撤销限制 |
| 特殊交易补充：YNAB、MoneyWiz | [YNAB 入账语义](https://support.ynab.com/en_us/how-to-add-income-and-other-inflows-H1ZNjfZJi)、[MoneyWiz 退款关联](https://help.wiz.money/en/articles/4440659-how-to-refund-or-reimburse-transactions) | 为收入、退款、还款等区别提供线索；具体计算口径仍需余白决策，不照搬预算周期 |
| 相邻交互参考：待调查 | 尚无已采用来源 | 后续如处理长时间导入与失败恢复，针对这些问题补充真实流程参考；本轮不填产品名称凑数 |
| 视觉主参考：待选择 | 现有原型只作为自己的候选 | 需要观察适合移动端的结果层级、批量纠正和退出路径；未看过的界面不写成已借鉴 |

## 工具与资源关系

2026-09-20 能力快照：

- **Open Design**：本机 Skill 0.5.2 可读，当前会话暴露需求收集、项目、生成及查询工具。仅证实工具可见；运行服务、登录、额度和实际生成未调用验证。框架接入不需要建立生成工作流。
- **执行模式**：项目尚无已确认选择。该版本 Skill 默认 OpenDesign Cloud，使用其账户与额度；Local Codex 需用户明确选择。下一次首次生成前说明实际模式及额度归属，按届时 Skill 处理已有选择；本轮没有费用授权、登录或模式切换。
- **Product Design**：本轮参考其上下文与来源管理规则；未执行图像探索或构建流程。插件全局上下文预检未发现保存内容，本项目资料只写入当前项目。
- **Figma**：相关 Skill 在宿主可见，未选择为本项目画布；文件权限和实际工具调用未验证。本轮无需安装或接入。
- **原型**：本地 HTML 是现存候选的唯一源码；尚无 Open Design/Figma 派生稿。以后选定画布时登记工具真实返回的位置、导出状态与同步差异。

产品决定以地图和子票为准，词义以 CONTEXT.md 为准，设计意图以 DESIGN.md 和明确选定稿为准，候选数值以原型 CSS 为准。没有自动双向同步；相关修改由当前 Agent 更新并记录尚未同步的资源。

## 范围与连续维护

2026-09-20 的授权是创建产品设计基础框架：盘点、补齐资料、建立项目入口，当时未实现应用或新建可见方案。当前 2026-10-20 步骤 10 只同步产品与设计记录、验证清单，不改 Swift、不提交或推送；步骤 1–9 的源码采用与尚未验证项见上方。每轮范围按用户当次请求确定。

长期产品约束从[地图 Notes](../.scratch/yubai-product/map.md#notes)读取：先服务本人、动态安排资金、少打扰自动分类、金额由用户修正、原始账单本地保留，以及按实际使用反馈迭代。10 分钟是已有体验目标，4,000 条是规模示例，都不是实测成绩或本轮新增验收标准。

后续有变化时，在本轮允许写入的范围内维护：

| 变化 | 更新权威位置 | 连带检查 |
|---|---|---|
| 产品目标、范围或规则确定/改变 | 对应决策票；地图只加链接与摘要 | 受影响流程和原型；未知继续标注未知 |
| 领域词义澄清 | CONTEXT.md | 子票与界面文案一致 |
| 页面或交互调整 | 当前稿与 DESIGN.md | 空内容、异常、返回和撤销；记录未验证部分 |
| 视觉方向选定 | 本文选定稿登记与 DESIGN.md | 旧稿被替代关系、样式与组件来源 |
| 公共样式、组件或工具变化 | 当前权威源码、本文工具记录 | 派生画布/导出是否同步，缺口写明 |
| 只讨论尚未采用的想法 | 对应票 Comments 或本文未决项 | 保留当前决定；只读任务只报告建议 |

结束相关任务前核对链接、来源、采用状态与未决项。资料可读不代表 UI 或业务行为已经通过验证；无变化时无需重写。

本协议副本来自用户指定的 [Vellum 源文件](/Users/yang/Documents/Vellum/vault/outputs/产品设计启动协议.md)，2026-09-20 复制。副本用于本项目续作，源文件更新后按差异人工合并，不承诺自动同步。
