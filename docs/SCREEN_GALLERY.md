# Screen gallery

在 Apple Silicon Mac、Xcode 26 与 iOS 26 模拟器上，从仓库根目录运行：

```sh
scripts/gallery.sh <simulator-UDID>
```

也可用 `SIM` 指定模拟器。只跑某条巡游时设置 `GALLERY_ONLY`，多个 XCTest 方法名以空格分隔，例如：

```sh
GALLERY_ONLY='testWalk47BatchA testWalk47BatchALarge' scripts/gallery.sh <simulator-UDID>
python3 scripts/gallery_inventory.py --check
bash scripts/check-ui-consistency.sh --self-test
```

## 覆盖与命名

当前规划 **110 块稿（第四十六轮 87 块、第四十七轮 23 块）、61 条巡游、1,293 个截屏停点**。数量是源码清单，不代表已经取得截图。

第四十七轮统一命名为 `V47-{light|dark|a11y|hidden}-{BoardOrState}`，已有巡游继续保留 V46 前缀并使用当前界面。四种状态分别为浅色、深色、最大辅助字号（Accessibility XXXL）、隐藏金额；每块稿在四种状态中各有一个同名停点。补充交互状态使用独立名称，避免同图多名。`scripts/round46-boards.txt` 与 `scripts/round47-boards.txt` 只保存稿名，不保存私有设计地址。

| 巡游方法 | 条数 | 每条停点 |
|---|---:|---:|
| testWalk47BatchA / Dark / Large / Hidden | 4 | 22 |
| testWalk47BatchB / Dark / Large / Hidden | 4 | 20 |
| testWalk47BatchB2 / Dark / Large / Hidden | 4 | 20 |
| testWalk47BatchB3 / Dark / Large / Hidden | 4 | 20 |
| testWalk47BatchB4 / Dark / Large / Hidden | 4 | 17 |
| testWalk47BatchC / Dark / Large / Hidden | 4 | 20 |
| testWalk47BatchD / Dark / Large / Hidden | 4 | 19 |
| testWalk46Batch1 / Dark / Large / Hidden | 4 | 25 |
| testWalk46Batch2 / Dark / Large / Hidden | 4 | 28 |
| testWalk46Batch3 / Dark / Large / Hidden | 4 | 27 |
| testWalk46Batch4 / Dark / Large / Hidden | 4 | 14 |
| testWalk46Batch5 / Dark / Large / Hidden | 4 | 24 |
| testWalk01RootsAndLedger | 1 | 34 |
| testWalk02FormulaAndAccounts | 1 | 18 |
| testWalk03Bills | 1 | 18 |
| testWalk04Saving | 1 | 18 |
| testWalk05EntrySheets | 1 | 24 |
| testWalk06Categories | 1 | 13 |
| testWalk07Yubai | 1 | 22 |
| testWalk08Settings | 1 | 26 |
| testWalk09Imports | 1 | 17 |
| testWalk10States | 1 | 22 |
| testWalk11Empty | 1 | 15 |
| testAccessibilityWalk | 1 | 21 |
| testDarkWalk | 1 | 21 |

`Tests/YubaiUITests/ScreenGalleryTests.swift` 是停点的来源。`scripts/gallery_inventory.py` 从实际方法和共享巡游生成清单，检查重复名称、110 块稿的四种状态以及 CI 是否逐条排入。`scripts/gallery.sh` 使用同一清单生成 `expected.txt`；未执行的停点也会报缺失。CI 每个 part 只跑一条巡游，测试方法最多 30 分钟，作业上限 50 分钟。B 的 77 个停点保留在四段中，每段最多 20 个，lint 校验四种状态共 308 个停点。实际耗时仍需在 Mac 验证。

## 每个停点的检查

所有新旧停点在截屏前经过唯一的 `auditGallery()`：

- 截图前后确认应用仍在前台运行；进程停止只能产生失败图。每次启动保留所属停点，迟到的 XCTest 崩溃通知归回死亡进程的停点，不归给后来启动的夹具。
- 检查当前可触达控件的 44pt 点击区、互相覆盖及固定主动作越界；排除系统键盘、菜单、滚轮与包裹子控件的容器。
- 调用 XCTest 的 `textClipped` 辅助功能审计。设计允许单行省略的名称标为 `truncatableName`，页头名称和回执正文允许省略，输入内容可随光标滚动；金额与按钮不豁免。
- 检查关键金额没有省略号；记账的支出／收入／转账保持同一行。

这些检查是运行时辅助检查，不能替代截图逐屏对稿、旁白和真机边缘返回验证。滚动内容允许暂时在视口外；固定主动作不允许。

## 输出与失败

`.shots/` 每次运行前清空且被 git 忽略。正常停点写 `<name>.png`，同时保存同名 `.keepAlways` XCTAttachment。失败写 `<name>-MISSING.png` 与层级文本，并继续后续停点，最终令 XCTest 和脚本失败。

`expected.txt` 是所选巡游的完整计划；`missing.txt` 合并运行报告和未产生正常 PNG 的停点；`index.txt` 记录数量、git SHA、xcodebuild 状态、结果包路径和文件列表。构建失败、缺图或任何审计失败均返回非零，即使已有部分 PNG。诊断图片不算完成对应停点。

DerivedData、xcresult 和构建日志在脚本打印的 `/tmp/yubai-gallery.*` 下。XCTest runner 使用 `TEST_RUNNER_YUBAI_GALLERY_DIR` 转发输出目录；宿主写图受限时从 xcresult 附件清单恢复名称。没有非空 `YUBAI_GALLERY_DIR` 的普通 UI 测试会跳过图库类；没有新增禁用的流程测试。

`crashes/` 与 `stalls/` 一起上传。`scripts/export-crash-reports.py` 按本次开始时间收集宿主 DiagnosticReports 和模拟器自身 CrashReporter / DiagnosticReports 中的余白报告，包含 XCTest 的已关闭克隆设备；保留原始 `.ips`、来源清单和采集状态。脚本退出时与 CI 的 `always()` 步骤都采集，采集失败不改变测试结论。没有报告不代表没有崩溃。`GALLERY-PROCESS` 日志记录启动、停点和死亡的对应关系。

## 数据隔离与补充状态

所有夹具仅限 `DEBUG && targetEnvironment(simulator)`，还须 UUID 形式的 `--test-ledger`。每次启动都使用独立缓存目录，稳定领域 ID；助手使用离线 transport，不读取真实账本、不联系云服务。外观、字号、隐藏金额均随夹具设定，不改模拟器全局偏好。

`gallery`、`gallery-empty`、`gallery-locked`、`v46-*`、`v47-*` 和已有专用夹具覆盖超长中英文名称、零余额、0.01、大额、信用欠款、超支、隐藏账户／分类及撤销。有效交易仍由 Core 校验，不注入业务禁止的零金额交易。

第五批还覆盖实际重复分类校验、删分类并迁移记录、长文本输入、统一回执与撤销、账户金额键盘、AI 子页、通知和设备设置。加密恢复夹具通过真实 `Backup.export/restore` 生成并读取隔离目录内的临时文件；版本选择夹具使用本机文件版本源，不依赖 iCloud。两者仍走正式页面和校验逻辑。

系统文件选择器、相册／相机权限、设备解锁、真实后台任务及真实 iCloud 冲突受宿主和设备能力约束，不能由静态覆盖清单证明。已删除的旧图表、旧储蓄目标编辑器和无入口页面不再造路线展示。

Linux 可运行清单、脚本合约、UI lint、条件语法解析与 Core 单测；Apple SDK 构建、UI XCTest 与实际截图须在 Mac 上执行。

第四十七轮 A 批返修覆盖账本首页、月份、搜索、最底账目、三标签回顶、洞察与余白、首次「窗」场景和工资设置／延期；删除独立现在页、小票和存钱大卡片。存钱页的存取操作由 B 批停点验证。

第四十七轮 C 批覆盖：十种空态、常用模板添加、首页建议、证据首四笔／全部／纠正、两周回看、设置开关与上次运行、零建议、长名称和大额。首页建议由脚本回复经过正式每周请求、Core 验算和队列产生；错误合计、未知记录、未知动作与损坏 JSON 另由流程测试验证。`V47-Butler-AI` 是 Core 合约板，画廊对应其设置入口；不新增一张解释机制的产品页面。

第四十七轮 B 批覆盖：单卡竖式及零扣项／少攒／缺口／大额、每项去向、拿出和放回的预览／限额／保存／撤销、底线改清、普通存取流水、发薪日全部／部分／不补与队列轮转，以及短回执、截断、展开、撤销和关闭。

第四十七轮 D 批覆盖：补回与 AI 建议共用的首页单卡队列／证据页、各自回答后状态、长名称与大额、多条建议、五种错误或空回复、关闭建议、空句纠正与回看答复。`V47-Changes` 是八项变更的总览合约板，其停点验证整合后的首页和共用队列，不把设计说明加入产品界面。


2026-11-16 第四十七轮返修：`testWalk47BatchA` 及 Dark / Large / Hidden 四个走查从账本首页开始，覆盖 `Ledger-Home`、`Ledger-Find`、`Ledger-Modes`、`Insights-Two`、`Yubai`、`First-A`、`First-After`。`Ledger-Find-End` 验收最早账目完整位于记账宽钮上方，`Ledger-Return-To-Top` 验收重选账本后清搜索、筛选并回顶。设置走「余白 → 设置」；搜索先点 `openLedgerSearch`，在顶栏展开。已删除独立现在页、首页小票和存钱大卡片的截图要求；存钱页从「已存」胶囊进入。

2026-11-16 rB 整合：B 批四种模式补齐六种 hero 状态、少攒／缺口补救与撤销、上期自动存好与留这月花、发薪补回、每周 AI、设线建议与纠正、余额偏差、下一期年季付账单、竖式的结转／取用／余额差额、金额和次数提醒、记账实时剩余与超出、对账覆盖和底线两态、洞察设线／改数／按次数。深色账本带 carry 卡；账本底部实测留白、末笔可点可左滑及回顶验收保持。上述停点仍需 Apple SDK 构建和模拟器执行。

看门狗的 `source=app` 标记实际应用工作；`source=xctest-audit` 和 `source=xctest-snapshot` 标记 XCTest 审计与查询，系统工作和未完整捕获的堆栈分别为 `system` / `unknown`。全部保留。每个界面只暴露一个定长诊断摘要，完整堆栈由 stderr 与 Documents/tmp 文件导出到 `stalls/`；模拟器已关闭时使用 xcodebuild 日志和本次构建的符号文件。

图库与流程审计共用应用控件清单，排除系统键盘及其首次使用提示；仍验证键盘存在、焦点字段完整露出、Return 后键盘收起。图库和普通 UI 分片在 xcodebuild 启动前写入所选模拟器的滑行输入介绍已读偏好，并核对回读；不支持该偏好时保留按系统容器关闭提示的回退。纠正弹窗打开及重开均自动聚焦。控件 reveal 按实际页头、底部固定操作区和导航栏的无遮挡区域滚动，避免只在最后检查可点时才发现被挡住。

fixC4c：顶栏控件从实际 `rootHeaderRegion` 子树取得层级，不再为月份和搜索逐次遍历整张账本及键盘；仍检查原生命中和原时限，超时与真实遮挡分别记录。新增流程覆盖启动后与滚动后的全部顶栏控件、五种外观／字号组合下的紧凑浮动入口和实测底部留白。`Home-AI-Many-Next` 在截图前将两个答案一起滚到渐隐及浮层上方；最大字号的管家标题直接全文显示。`Butler-Cards-Long` 在已有中文句子后复用已有超长英文夹具，验证普通字号仍能展开；无障碍字号无折叠钮。新增流程还逐一审计 AI、设线、结转、余额偏差、年付提醒、缺口、发薪补回和两周回看卡的标题与动作，包含深色和隐藏金额。标签的系统大字号查看器及实际像素仍需 Apple 环境验证；记账宽钮的长按口径见 fixC6。

fixC5：纠正和记忆编辑的自动聚焦弹层，分别在键盘显示、输入前后运行原生 `dynamicType` 与 `textClipped` 审计，检查进程、焦点和输入内容；纠正覆盖浅色、深色及最大字号下隐藏金额。缺口补救流程同时检查两颗按钮滚到渐隐、记一笔和标签栏上方，并验证执行及撤销。滚动 helper 在手势完成后等待实际位移再判断停滞，保留原截止时间及原生命中要求。以上原生 UI 回归需要 Apple 环境执行。

fixC6：记账宽钮在所有字号下保留 0.4 秒长按打开常用，系统大内容查看器只用于标签。画廊与流程共用长按 helper，在手势前保存标识，手势后必须验证常用菜单出现并稳定；空账本另验单击记账与长按整理、添加常用。纠正的首次焦点请求由同一原生输入控件持有到布局、弹层完成并确认取得焦点，直接入口和「依据 → 说得不对」都覆盖普通／最大字号的自动聚焦、输入、取消重开、保存及原生字号／裁切审计。金额弹层先验证预览稳定再按键；按键通过实际 `fixedBottomBar` 子树验证完整几何、启用和原生命中，有系统键盘或找不到该子树时保留整树检查。`GALLERY-PHASE` 在原始日志记录启动、按键完成和 walk 完成时的剩余停点预算；原时限、审计和所有停点不变。深色放回限额及隐藏金额长名称的设置行另有流程回归，后者继续使用 fixC5 的实际位移等待。上述原生验证仍须在 Apple 环境执行。
