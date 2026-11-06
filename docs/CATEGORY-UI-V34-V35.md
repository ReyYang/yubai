# 分类管理与共享两步选择器 · 第 34／35 轮

2026-11-06 记账入口续作：`feat/entry-more-category-picker` 已补齐此前留出的记一笔／改一笔「更多」。共享组件增加主类逐行、小项直接铺开的 sections 样式；点主类即确认主类，点小项确认完整路径，保存时沿用 CategoryModel.confirm 保护显式 nil；保留固定前五并追加范围外选中类。其余入口仍使用下文原 grid 展开样式。新增、收支方向、连续／重复记账、全部中文及最新验证见 [设计续作](../.design-meta/DESIGN.md#2026-11-06--第三十五轮记一笔改一笔更多owner-批准)。下文保留原轮次范围及验证记录。

2026-11-05，owner 在 `feat/category-defaults-expand`（前置 Core `e0789e3`）明确授权实现已批准稿，并要求提交、不推送。九份 HTML 只读；原文件、外部路径与链接均未写入仓库。以下区分用户决定与实现选择。

## 已采用行为与文件

| 文件 | 结果 |
|---|---|
| `Sources/YubaiApp/CategoriesView.swift` | 「我 › 分类」支出／收入、固定末位且不可编辑的其他分类、名字与小项数、拖动排序及前五个预览；新增大类后进入详情；改名、记账笔数、小项增改删、合并、隐藏／显示。 |
| `Sources/YubaiApp/SettingsView.swift` | 分类与固定收付放在同一卡片；独立值导航类型登记在我页，沿用根 NavigationPath，无需修改 AppStore／根导航文件。 |
| `Sources/YubaiApp/CategoryPicker.swift` | 新共享组件：固定 categoryOrder、三列主项、不压缩的整块换行、建议描边置首、展开行下跨列小项、其他主项变淡、同项再点收起、无小项立即选、只记大类；末格加一个。新增 sheet 仅有名字、放在、底部结果按钮，默认当前展开主类，三个主类及「更多…」展开全部。 |
| `Sources/YubaiApp/UnsortedViews.swift` | 一个个分、按对方分的选择 sheet、一组自己选共用组件；两步完成前不应用；即时入口选小项／只记大类立即应用并推进。一组页仍可先选子集和用途、再确认；新增并应用尊重当前勾选数，无勾选时只新增。 |
| `Sources/YubaiApp/ImportView.swift` | 分类对应和截图核对两处替换为共享选择器；来源名按账单首次出现顺序，目标按 categoryOrder；预览刷新及截图编辑保留显式小项／只记大类标记，切收支清空旧方向选择。 |
| `Sources/YubaiApp/AskYubaiView.swift` | 草稿编辑共享选择器，方向由草稿决定；卡片显示主类与小项，保存 finishing 阶段保留用户显式小项／只记大类。 |
| `Sources/YubaiApp/QuickCaptureSettingsView.swift` | 商户映射保存完整两级路径，支持同一个选择器切换收入／支出；长映射标签放不下时各占一行。 |
| `Sources/YubaiApp/IntelligenceRuntime.swift` | 创建主项／小项、应用既有 ChangeSet、显式确认小项与导入撤销记录同一次保存；保留快分／批量专用撤销及进度，失败整次回滚。 |
| `Sources/YubaiCore/CategoryModel.swift` | 新增有序投影、CategoryAddition 和显式 CategoryModel.confirm API；主类确认记录 nil 小项，防止自动猜测重新填入。其他分类管理沿用已有 API。 |
| `Sources/YubaiCore/ManualNoteMigration.swift`、`Models.swift` | 一次性用途备注迁移及口语关键词，详见下文。 |
| `Tests/YubaiCoreTests/CategoryUIContractsTests.swift` | 新增 10 项 Core 回归。 |
| `Tests/YubaiUITests/AppFlowTests.swift` | 原有 7 次单层点选补「只记」；新增 3 项回归源码，覆盖展开／收起／小项即时应用、新增默认归属与撤销、分类与小项维护及合并撤销。 |
| `Yubai.xcodeproj/project.pbxproj` | 仅登记两份新 App 源码及一份新 Core 测试；保留原工程设置。 |

排序保存到 preferences.categoryOrder；日常快选仍取按方向过滤后的固定前五，不按频率。隐藏只过滤记账候选，历史、金额与统计不变。删除小项用已有引用重写，仅保留大类；改名、合并继续更新记录、记忆、别名与保留的导入撤销快照。合并后使用现有全账本撤销提示。快分／多组选用原有按操作范围撤销：恢复仍与本次结果一致的记录与记忆，保留后续修改；新建的分类定义留存。这是复用既有撤销边界的实现选择。

## 用途与备注迁移、词表

用户明确决定：手写用途与备注合并一次；导入原文保留。实现以 `manualNotesMerged` 记录完成状态，新账本默认为已完成，旧账本首次 decode 时执行。只处理来源为手动／问余白、且没有 batchID、sourceRow、externalID、sourceIdentity 或 fingerprint 的记录。用途为空时取 note，否则拼接 `purpose + " · " + note`，按 Swift Character 截取前 4,000 字以符合 validate，随后 note 清空。截断是上限处理的实现选择；极端长备注超过上限的尾部不会进入新用途。原始磁盘文件仍走原存储／恢复机制，未改 Storage。

保留的导入 undo 内若有同类手写记录，也迁移，避免旧快照复活备注；导入、Apple Pay 与自动固定收付的备注保持。存档中的完成标记让以后新写的备注不再迁移。测试覆盖缺失标记、空用途、已有用途、来源／导入标记、Unicode 边界、undo 及真实仓库保存后第二次加载不重复追加。

理发新增「剪头发、剪头、洗头、洗剪吹、理发店、发廊」；复核新路径后补充修车／换机油／换轮胎、交保险／买保险／交保费／续保、交税／补税、做饭／买蔬菜、寄东西／寄包裹、请阿姨／打扫卫生、给爸妈／给父母／给妈妈／给爸爸、捐钱、提公积金／取公积金、卖闲置／卖二手及做指甲／做美甲。沿用加载时的增量词表更新，不复活已删除的小项。定向用例包括「剪头发 → 美容个护／理发」及收入方向隔离。

CategoryReguess 仅保留前置 Core API；本轮没有对应稿，不添加 UI 钩子。

## 可见中文字符串

以下是本次新增、改动或在新控件中复用的全部模板；分类名／小项名使用当前账本事实，不另造说明文字。

| 类别 | 字符串 |
|---|---|
| 标题／字段 | 分类、支出、收入、排序、名字、记过、小项、放在、藏起来的、记一笔先显示、X合并到 |
| 数字与事实 | N 个小项、N 笔、藏起来的 · N、主类 · 小项、1 至 N 的排序序号 |
| 控件 | 完成、取消、好、加一个大类、加小项、加一个、加上、新的大类、更多…、合并到…、记账时藏起来、显示、删掉这个小项、只记X、N 笔改成X、加上，这 N 笔记为Y、撤销 |
| 含小项的结果／状态模板 | N 笔记为 主类 · 小项、对方 · N 笔记为主类 · 小项、N 组 · M 笔记为主类 · 小项 |
| 保存状态 | 添加分类完成、修改分类完成、添加小项完成、修改小项完成、删除小项完成、合并分类完成（原 AppStore 保存提示拼接） |

删除原用途输入框的「可不填」占位，保留 accessibilityLabel。沿用原有「不是支出／不是收入」及性质／账户名，改用不截断的 chip；其措辞未改变。未新增四类之外的可见说明；错误复用已有 Core 原因。辅助功能的完整 label／hint／value 不作为可见文案。

## 验证与边界

- 指定 Linux Swift：Core build 成功；全量 **824 项，820 通过／4 项原有实网 opt-in 跳过／0 失败，122.802 秒**。相对前置 814 项增加 10 项，本轮没有新依赖或真实网络／模型请求。
- 实际 AppStore 新分类方法及原有缓存包装抽取到 Swift 6 Linux 平台替身，链接真实 Core／LedgerRepository：普通主类显式 nil、批量新增小项、部分新增大类、非法小项回滚四组通过；成功仅保存一次，落盘与内存一致，专用撤销恢复记录及记忆。平台替身不等同 Apple SDK 编译。
- 全部 43 份 App 与 1 份 UI 测试文件分别做 iOS 26 模拟器 Debug／设备 Debug、macOS 14 Debug 条件语法解析（132 次）；audit-swift-access.py 已运行，新增类型的访问级别与 AppStore 引用人工复核，无新增跨文件 private 越权。工程新引用及 diff whitespace 检查通过。
- 原主项测试标识 `quickSortCategory_*`、`unsortedCategory_*`、`unsortedSelectedCategory_*` 保留；新增 MainOnly、Subcategory、Add、管理／新增／合并控件标识。
- **仍待 Mac**：Apple SDK 类型检查、Xcode 构建、XCTest UI 实跑、390pt／深色／大字号／读屏与真机布局、拖动和 sheet 交互。没有把条件解析当成视觉验收。

原生适配与未覆盖：保留 DesignSystem 字体、20pt 页面 inset、48pt 行和至少 44pt 点击区，替代稿中部分 18pt inset／36pt 控件；排序用系统拖动手柄，sheet 用 yubaiSheetBackground。长按钮允许增高，chip 不缩字，主项按实际文字宽度整块换到下一行。第 35 轮「记一笔更多」整行铺开全部小项的专用画面留给该入口所属分支；本轮按要求不改 QuickEntryView，已提供独立共享组件供后续接入。其余指定禁改文件／方法均保持。外部设计资源未同步，原稿未归档入库。

## 提交环境限制

实现完成后，正常 git add 因该工作树的 Git 元数据挂载只读而失败，无法创建 index.lock。共用对象库与 refs 可写，因此使用 `/tmp` 临时索引生成两个 ReyYang 提交，并保存在本地 `review/category-ui-v34-v35` 引用中。该引用从本轮 e0789e3 基线延续；提交内容与当前文件逐项核对一致。原 `feat/category-defaults-expand` 引用和只读索引未修改，当前工作树仍显示本轮改动；未推送。需要在工作树元数据可写后，将当前分支与索引对齐到审阅分支末提交。
