# 少写字与帮你省钱合并核对

2026-10-23，按 owner 本轮任务在 `feat/butler-saving-core` 的未完成 merge 中解决 `origin/feat/no-explanatory-copy` 冲突。两边功能与历史记录合并保留，说明文案采用第十六轮规则；不提交、不终止 merge、不联网调用 API。

## 八个冲突文件的取舍

| 文件 | 合并结果 |
|---|---|
| `.design-meta/DESIGN.md` | 同时保留 Simulator 27.1 toolbar 修复、第十五轮界面／Core／PR #34 记录和第十六轮规则、画板、源码映射；历史验证仍属于各自原日期。 |
| `.design-meta/README.md` | 保留省钱 Core、V15、编译排查及八个截图夹具入口，也保留 V16 交付入口；本轮核对单独登记。 |
| `.scratch/yubai-product/issues/13-complete-personal-release.md` | 保留两边 owner 决定、Agent 实现选择、授权降级和待验项；追加本次合并范围，整票状态保持。 |
| `AskYubaiView.swift` | 保留 `ChatInputBar`、购买追问／结论分派、拆开的消息／明细／核对／保护记录子视图。接入 V16 配置／网络／语音权限状态和设置入口；未核实金额改为琥珀金额＋核对控件。输入条用禁用态，删除听写说明和不可用占位；旧购买卡不恢复。 |
| `CloudAssistantViews.swift` | 删除模型说明函数及菜单副标题，保留菜单、自填模型、脚本模式不发请求的保护；默认与内置模型仍以本分支的 `deepseek-flash`／`deepseek-v4-pro` 为准。钥匙串、发送记录和不可用状态采用 V16 简写。 |
| `ProfileConversationView.swift` | 保留本分支整套拆分视图、冷启动三点／再聊无进度、起头芯片、记忆撤销、滚动、立即显示气泡、失败回填与重试替换。V16 的去三问说明／思考文字已被本分支的图形进度与水波覆盖，不恢复旧输入框或重复进度。最终内容与本分支 HEAD 一致。 |
| `ProfileView.swift` | 空领域采用虚线添加控件，习惯空态采用条形占位；保留本分支的 `areaRow`／`areaUsage`、次数／金额较高比例与 ≥80% 琥珀进度、小项匹配。合并自动产生的两个聊天入口为页底一处品牌浅底行；不可用时显示状态并进入智能与隐私。表单建议／关键词芯片和更多保留。 |
| `WishlistView.swift` | 同时保留省下的钱、冷静期卡、剩余天数、放弃日期与清理冷静期／旧卡、后悔再聊，以及 V16 空态占位＋该不该买按钮、买后日期＋日历图标。保留拆开的 `followUpCard`／`ageText`；可选补充收到更多。 |

`SubcategoryViews.swift`、`SavingPurchaseViews.swift`、`UITestSupport.swift` 均与本分支 HEAD 逐字节一致：拆开的分类芯片／明细视图、左右 `ToolbarItem`、`YubaiCore.Category` 和八个 Debug 模拟器脚本全部保留。Core 相对 HEAD 只有对方已采用的空账户显示字符串变化及其参考断言，没有改省钱计算、模型迁移或存档。

自动合并后的来信省钱格、订阅体检、三处上下文入口、近限额行、详情小项选择及洞察下钻均保留。UI 测试仍为 55 个方法，包含原有 47 个及全部 8 个截图流程；模型菜单断言同步为当前模型名。

## 可见中文变化

对方全应用清理的完整可见中文清单沿用 [V16 交付清单](../.design-meta/no-explanatory-copy-v16.md#本次新增改动的全部可见中文)，保留的省钱文字沿用 [V15 清单](SAVING-UI-V15.md#新增可见文字逐条清单)。本次合并补充和覆盖如下；没有新增说明句或规则例外。

| 文字／模板 | 处理与类别 |
|---|---|
| 还没配密钥 ›；没联网；云端智能没开 ›；模型不可用 › | 问余白采用 V16，状态／配置入口控件。 |
| 没开语音权限；去设置 | 问余白采用 V16，状态／控件。 |
| 问点什么…；接着问… | 共享输入条采用 V16 控件占位，禁用态由控件表达。 |
| 核对 ›；{未核实金额}；•••• | 拆分后的核对子视图采用 V16，控件／数字／金额隐藏状态。 |
| 和余白聊聊；还没配密钥；云端智能没开；模型不可用 | 消费观只留一处页底入口，控件／状态；最后一项也覆盖本分支模型不可用时的保护。 |
| 添加；愿意多花的；你常花的；近 90 天；名称；关键词；添加关键词；更多；说明；相关分类；上限；每周次数；每月金额 | 消费观采用 V16 标题／控件／事实；名称、关键词建议芯片保持 V16 清单。 |
| 心愿单还是空的；该不该买 | 心愿空态采用 V16，标题／主动作。 |
| {日期}＋日历图标 | 买后等待仅显示日期事实；不加入内部回访术语，读屏仍说明“问你用得怎么样”。 |
| 写进消费观 | 替换“要把这次的感受写进消费观吗？”与“和余白说说”；按钮写结果，仍传 `wishRegret` 上下文。 |
| 收起 | 替换“不用了”；控件，仍只收起本次心愿页面的入口卡。 |
| 聊聊这周 | 替换“想聊聊这周吗？”；控件，仍传 `weeklyLetter` 上下文。 |
| 没有匹配的支出 | 替换“还没有匹配的支出，先记一笔。”；状态，原记账入口保留。 |
| 更多；补充 | 替换“想补充的话（可选）”；折叠控件／输入控件，输入与保存逻辑保留。 |

删除而不新增替代句：听写操作说明、不可用输入占位、未核实金额说明、消费观导语／空态邀请／设置路径／来源副标题、心愿空态邀请、选择已记支出的操作说明、两条模型能力说明。相关动作由原控件或 V16 状态入口承接；必要的完整读屏文案保留。

已检查省钱新增视图、原接线页面及全部 App Swift 字符串，`InterfaceVocabularyTests` 全部通过；没有用户可见的禁用词。内部字段与代码标识符不因文案改名。仓库工作树未检出私有设计页面链接，原始画板、历史记录、Figma／分发资源保持原位置；外部资源未同步。

## 验证

- Linux `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test`：449 项，445 通过、4 项原有实网 opt-in 跳过、0 失败；明确设置 `YUBAI_LIVE_EVAL=0`，未访问真实模型服务。包含 `InterfaceVocabularyTests` 的 3 项。
- 最终 App 源码通过全部 38 个 Swift 文件的 `swiftc -frontend -parse`：iOS 26／27.1 模拟器 Debug、iOS 26 设备 Debug／Release、macOS 14 Debug；UI 测试文件通过 iOS 26 模拟器 Debug 语法解析。
- 全部 55 个 UI 测试方法名、8 个截图流程保留，夹具实现与 HEAD 一致；本轮没有 Apple SDK 类型检查、UI 实跑或设备视觉验收。
- `git diff --check` 与暂存差异空白检查通过，工作树没有冲突标记。

运行原始输出保存在本机 `/tmp/yubai-merge-review/`，不进入仓库。

## 暂存受环境阻止

验证完成后已执行 `git add`，退出 128：`Unable to create '/home/user/yubai/.git/index.lock': Read-only file system`。当前环境将 `.git` 挂为只读，无法写入索引；源文件已无冲突标记，索引仍有原来的 8 个未合并文件。没有提交、终止 merge 或修改 Git 元数据。需在 `.git` 可写的环境执行：

```sh
git add -- \
  .design-meta/DESIGN.md .design-meta/README.md \
  .scratch/yubai-product/issues/13-complete-personal-release.md \
  Sources/YubaiApp/AskYubaiView.swift Sources/YubaiApp/CloudAssistantViews.swift \
  Sources/YubaiApp/ProfileConversationView.swift Sources/YubaiApp/ProfileView.swift \
  Sources/YubaiApp/WishlistView.swift Sources/YubaiApp/SavingViews.swift \
  Sources/YubaiApp/ButlerViews.swift Tests/YubaiUITests/AppFlowTests.swift \
  docs/SAVING-UI-V15.md docs/MERGE-NO-EXPLANATORY-COPY.md
```
