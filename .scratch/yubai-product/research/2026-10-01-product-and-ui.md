# 余白：产品闭环、原生 UI 与安装研究

查阅日期：2026-10-01。范围：官方公开文档与官网；没有安装或实测竞品，没有读取个人账单、凭据或调用外部 AI。下文“事实”指文档可核查的描述，不表示已在用户设备验证。工程建议为研究者判断，交付负责人负责实际采用与实现验收。当前任务的完整产品授权优先于旧地图建图阶段的范围说明。

## 结论与会阻塞交付的条件

**建议采用 SwiftUI + Swift Charts + 本机持久化，分别构建 iOS/macOS 入口，共享纯 Swift 账本、导入与预测逻辑。** 当前任务聚焦 iPhone、兼顾 Mac，原生方案减少跨运行时与原生桥接的维护面；这是一项针对本项目的判断，不是框架普遍优劣排名。Apple 官方支持 SwiftUI 横跨 Apple 平台并与 UIKit/AppKit 互操作；Swift Charts 提供原生图表与无障碍支持。[SwiftUI](https://developer.apple.com/swiftui/)、[Swift Charts](https://developer.apple.com/documentation/Charts?changes=_1)

必须将下面两件事分开报告：

- **能编译不等于能长期装在 iPhone。** Apple Personal Team 最多 10 个 App ID、3 台设备、每设备 3 个应用；profile 自发放起 7 天失效，需要重新构建安装。开发者账号、设备连接、签名能力及分发方式尚未核实。不要将模拟器构建写成真机交付。[Apple 开发者账户](https://developer.apple.com/help/account/basics/about-your-developer-account/)
- **本机大模型不能作为核心功能前提。** Foundation Models 要检查 `SystemLanguageModel.default.availability`，设备、地区、启用状态和模型下载影响可用性。Apple 支持页仍写明：中国大陆购买设备不可用；境外购买设备在大陆且 Apple Account 地区为大陆时也不可用。不推断用户设备是否符合条件，不改变其账号/地区。账本、规则分类、资金计算与购买情景比较必须独立可用。[Foundation Models 可用性](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)、[Apple Intelligence 地区条件](https://support.apple.com/en-us/121115)

## UI 与技术方案比较

这些都是当前有官方文档的方案；本研究未取得市场占有率，故“主流候选”不代表量化流行度排名。

| 候选 | 官方事实与直接来源 | 对余白的采用判断与维护边界 |
|---|---|---|
| SwiftUI / HIG / Swift Charts | SwiftUI 覆盖 Apple 平台，支持 UIKit/AppKit 混用；Charts 提供标记、坐标轴、图例、国际化和无障碍。[SwiftUI](https://developer.apple.com/swiftui/)、[Charts](https://developer.apple.com/documentation/Charts?changes=_1)、[HIG 入口](https://developer.apple.com/design/human-interface-guidelines) | 推荐。iPhone 用标准导航、表单、sheet 和系统文件选择；Mac 用侧栏、表格、键盘批量操作。HIG 页面正文受 JS 限制，本轮未逐条核查新版视觉细则；不要声称已经验证某种玻璃效果。图表只服务余额变化和现金最低点，不能取代可读数值与明细。 |
| SwiftData（持久化补充） | 官方提供 managed persistence，无外部依赖；可本地保存，跨设备同步是可选能力。[SwiftData](https://developer.apple.com/documentation/SwiftData?input=swiftdata) | 可用但不是 UI 框架强制选择。应优先让账本核心与持久化解耦；SwiftData、SQLite 或版本化本地存档须按事务、迁移、备份恢复的实际测试决定。默认不开云同步。 |
| React Native / Expo | React Native macOS 在官方文档中列为 partner 维护的 out-of-tree 平台。[平台说明](https://reactnative.dev/docs/out-of-tree-platforms)。Expo SQLite 文档现列 iOS/macOS/Web 等平台，数据库跨重启保留，Web 支持仍 alpha；SQLCipher 为可选配置。[Expo SQLite](https://docs.expo.dev/versions/latest/sdk/sqlite/) | 适合已有 React Native 团队或 Android 同期目标。本项目没有既有 JS 应用可复用，Mac 路径与 native module 兼容性需单独验收；不能把 Expo iOS 成功等同 macOS 整套可用。 |
| Flutter | 官方支持部署到 iOS 和 macOS。[支持平台](https://docs.flutter.dev/reference/supported-platforms)。官方 SQLite recipe 使用 `sqflite`，列出 iOS/macOS/Android 支持。[持久化](https://docs.flutter.dev/cookbook/persistence/sqlite) | 跨平台一致 UI 可行；本项目暂不需要额外 Dart 与插件维护面。文件、OCR、原生 AI 等能力仍需验证平台集成。支持平台页面会更新，不将该页最新 OS/API 自动当作当前 Xcode 已具备能力。 |
| React + shadcn/ui / Radix | shadcn/ui 交付可编辑组件源码，不是传统封装组件库；Radix Primitives 是 React 低层 UI 构件，强调无障碍与定制。[shadcn](https://ui.shadcn.com/docs)、[Radix](https://www.radix-ui.com/primitives/docs/overview/introduction) | 适合 Web 工作台与快速验证。组件库本身不解决 iOS 安装、文件持久化、OCR 与 Mac 应用打包；代码复制后升级与差异由项目维护。现有 HTML 草稿可借鉴任务结构，不应决定正式平台。 |
| Ionic / Capacitor | Capacitor 提供 Web UI 的原生容器与原生 SDK 访问，主要文档平台为 iOS/Android/Web。[运行时](https://capacitorjs.com/docs)。官方提醒 WebView LocalStorage/IndexedDB 可能被系统回收，Preferences 只适合少量键值，较大数据可采用 SQLite 插件。[存储](https://capacitorjs.com/docs/guides/storage) | 可复用 Web 实现，但需另外解决可靠数据库及 Mac 打包路径；不以 LocalStorage 保存唯一财务账本。插件生命周期、桥接和 Web UI 适配增加当前范围成本。 |

所有候选都仍需 Apple 的 iOS 签名/安装条件。框架本地运行不自动代表隐私合规、数据库已加密或备份可靠；应核查实际存储目录、系统备份行为、是否有网络请求和可恢复性。

## 成熟财务工具：可借鉴的真实能力

| 工具与证据 | 官方能力 | 借鉴与边界 |
|---|---|---|
| Actual Budget：[导入](https://github.com/actualbudget/actual/blob/master/packages/docs/docs/transactions/importing.md)、[API](https://actualbudget.org/docs/api/reference/) | 支持 CSV/QIF/OFX/QFX/CAMT。导入会跑规则并匹配重复；相同 imported_id 防重，其余按金额、近似日期及对方匹配，官方建议复核无 ID 情况。 | 主参考为本地规则、可解释去重和手动记录与导入匹配。不要仅用“同日同额”删除记录；重复与两个渠道描述同一资金事件须分开。官方文档不同页面对“重新导入已删记录”的默认值存在冲突，余白应自己明确定义并测试，不能沿抄默认值。 |
| Actual：[规则](https://actualbudget.org/docs/budgeting/rules/) | 可以自动积累对方改名与分类规则，支持阶段、匹配优先顺序、规则编辑和匹配结果的批量操作。 | 默认自动分类，低置信度归“其他”；批量纠正可以只改本次或形成以后规则。保留原文和用户手工覆盖；不能照搬 Actual 可改 amount 的动作，因为余白要求金额修正由用户完成。 |
| Actual：[转账](https://actualbudget.org/docs/transactions/transfers/)、[对账](https://actualbudget.org/docs/accounts/reconciliation/)、[备份](https://actualbudget.org/docs/backup-restore/backup/) | 转账两端关联，可不同入账日期；对账区分 cleared 与 reconciled，比较真实余额并锁定；可以导出与手工备份。 | 保留来源账号、两端证据、在途状态；对账应展示差额和数据日期，而非静默平账。备份要包含规则、关系、原始凭据与版本，不能只导出展示行。 |
| YNAB：[文件导入](https://support.ynab.com/en_us/file-based-import-a-guide-Bkj4Sszyo)、[对账](https://www.ynab.com/help-center) | 当前文件导入支持 Web/iPad，不支持 iPhone；CSV 为推荐格式，另有 OFX/QFX/QIF。上传文件在服务器解析、不保留原文件。对账用于让账本与银行一致。 | 借鉴导入预览和对账，但 iPhone 本机导入是余白需独立完成的体验；不得将其隐私路径照搬为“纯本地”。也不采用其固定预算周期作为余白资金安排基础。 |
| 钱迹：[导入](https://docs.qianjiapp.com/other/import_guide2.html)、[模板](https://docs.qianjiapp.com/other/import_templete.html) | 官方列微信、支付宝、京东账单等导入；明确导入定位为一次迁移，非日常记账。模板被称作 Excel 模板，但实际下载扩展名是 CSV。 | 中国交易词汇和导入步骤有参考价值；不能据“Excel 模板”宣称通用 XLSX 支持，也不能据一次迁移能力宣称适合每周重复导入。 |
| 钱迹：[FAQ](https://docs.qianjiapp.com/question_answer.html)、[Mac 更新日志](https://docs.qianjiapp.com/change-log/change_log_pc.html) | 文档列退款、报销、转账/还款、债务、分期与信用类账户；解释转账还款借还款不应计普通收支；当前 Mac 更新日志仍有维护。 | 借鉴负债和资金移动语义。FAQ 可能比版本日志旧，不据其旧条款推断当前全部离线/付费边界；未测试云同步、借还款或退款具体行为。 |
| MoneyWiz：[官网](https://www.wiz.money/) | 官网描述 iOS/macOS、导入、未来日期余额预测与多种报告。 | 将“按未来日期看余额”的任务用作候选；这是官网能力描述，未实测精度。项目旧退款帮助链接本轮返回 404，不能继续当当前能力证据。旧官方 MoneyWiz 3 手册只适合历史线索。 |
| Monarch：[预测](https://help.monarch.com/hc/en-us/articles/48344305092244-Forecasting-in-Monarch)、[周期账单](https://help.monarch.com/hc/en-us/articles/4890751141908-Tracking-Recurring-Expenses-and-Bills) | Forecasting 根据真实账户、历史支出与人生事件预测资产和现金流，文档指向 Monarch Plus，并强调不是精确预言；周期日历可覆盖账单、转账和工资。 | 余白先做可逐条解释的近期计划事件与购买情景，不将长期资产推演当当前可花现金。未证实中国账户联接或纯本地数据路径。 |
| Copilot：[交易类型](https://help.copilot.money/en/articles/3971267-transaction-types)、[交易页](https://help.copilot.money/en/articles/9554412-transactions-tab-overview) | 区分 Regular / Income / Internal Transfer，信用卡还款属于内部转账；交易页提供筛选、导出、拆分与 recurring 标记。 | 借鉴语义清晰的交易列表与细节编辑；未证实任意中国账单导入、本机模型或房租专用分摊。 |

## 中国账单与每周整理：实现所需边界

以下是依据产品场景和官方工具缺口形成的**工程建议**，不是“全部已支持”的报告：

1. 导入批次保留原文件、内容 hash、来源类型、账号映射、解析器版本和每行原始字段；原始文件复制在本机，账本交易引用来源行。先识别真实文件结构而非只看扩展名。
2. CSV 必须覆盖 BOM、UTF-8/常见中文编码、引号内逗号/换行、表前说明行、金额正负与独立收支列。XLSX 必须真正解析 ZIP/XML 工作簿、共享字符串、数字单元格和日期；只支持 CSV 不得把按钮写成已支持 Excel。
3. 微信/支付宝中银行卡付款可能与银行卡导入同时出现。支付渠道不一定是独立资金账户；需保留支付渠道、实际出资账户与可关联原单号，避免虚构钱包余额或重复记支出。
4. 强去重：来源与稳定交易 ID；同一文件 hash 可直接提示已导入。弱匹配只能成为候选，不能吞掉同额早餐等合法记录。手记/截图后导入应保留用户补充信息；退款不能与原支出互相“去重”。
5. 原金额解析不明确、币种未知或日期失败时保留问题行并说明原因，不猜测入账；类别不明确可归其他且允许退出。导入摘要应区分新增、匹配、跳过、失败、待补充，不把“解析成功”写成账目已对齐。
6. 截图 OCR 是提取入口，结果必须落入同一来源与去重流程。用户确认或修改金额；OCR 文本不是银行余额证明。

本轮未获取微信、支付宝、各银行的真实导出文件，没有证实所有版本字段和 Excel 方言。钱迹官方能力仅证实相应来源存在导入路径，不能代替源机构格式规范或真实 fixture 回归。

## 完整使用闭环建议

此部分是待实现/验证的产品方案，不冒充用户已确认业务规则。

- **开始使用**：空账本可以直接创建账号和余额基准；演示数据须显著区分且可安全退出。现金资产、信用负债、借入借出与基金估值分别表达。
- **补充与整理**：文件/截图/手动入口统一导入来源链；自动类别、少量异常提示、搜索筛选、批量纠正、撤销及重启后持久化。不能只有漂亮的导入结果页。
- **可信账本**：退款关联原支出、信用卡还款不再计消费、借贷本金与利息拆开、基金申购赎回与手续费/收益分开；资产估值不计可用现金。账户显示最近对账日期和差额；历史修正有追溯。
- **动态安排**：从“现在”累计已知收付款事件，未来计划与已发生交易分离；实际入账后消除对应计划的重复影响。展示可用现金、已安排资金、近期最低余额及具体形成原因，允许变更时间/金额/完成状态。
- **月收季付合租**：显式记录对房东的整季应付、本人承担份额、室友各月应付/实收和已预留。室友到账不能被误计工资，也不能把未到账应收当现有现金。欠付、提前付、金额变更和跨季余额需要可追溯。
- **购买前咨询**：输入金额、购买日期、用途，可比较“现在买/延后/不买”对现金最低点和确定到期支出的影响，列出数据截止日期与缺失计划；规则计算数值，本机可用模型只增强文本理解和解释。不展示规则模板为真实 AI 对话，不提供模型代算余额。
- **持续维护**：编辑账号、类别/规则、债务和计划；完整导出、备份、恢复预览与版本校验。恢复前保留当前账本。至少完成一次关闭重启、恢复到新目录并比较关键余额/记录数量/原文件校验和的独立验证。

## 仍需独立验收

未验证：真实微信/支付宝/银行 CSV/XLSX、真实截图 OCR 质量、4,000 条性能、所有金融边界、iPhone 真机安装、签名续期、用户设备 Foundation Models 可用性、两端账本转移/同步、备份恢复完整性、VoiceOver/大字体与真实 UI 交互。框架文档和竞品营销均不能替代这些结果。

资料访问限制：Apple HIG 及部分 SDK 页面正文依赖 JavaScript，已对 Charts/SwiftData 使用官方检索可读内容；MoneyWiz 旧帮助链接返回 404，降级为官网能力描述并明确未实测。上述来源以本次页面返回为准，不将最新文档中 SDK 功能自动视为本机 Xcode 26.4.1 已可使用；实际编译必须依据本机 SDK。
