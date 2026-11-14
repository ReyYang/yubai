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

当前规划 **105 块稿（第四十六轮 88 块、第四十七轮 17 块）、49 条巡游、1,113 个截屏停点**，其中第四十七轮 A 批 88 个、B 批 128 个、C 批 80 个、D 批 76 个。数量是源码清单，不代表已经取得截图。

第四十七轮统一命名为 `V47-{light|dark|a11y|hidden}-{BoardOrState}`，已有巡游继续保留 V46 前缀并使用当前界面。四种状态分别为浅色、深色、最大辅助字号（Accessibility XXXL）、隐藏金额；每块稿在四种状态中各有一个同名停点。补充交互状态使用独立名称，避免同图多名。`scripts/round46-boards.txt` 与 `scripts/round47-boards.txt` 只保存稿名，不保存私有设计地址。

| 巡游方法 | 条数 | 每条停点 |
|---|---:|---:|
| testWalk47BatchA / Dark / Large / Hidden | 4 | 22 |
| testWalk47BatchB / Dark / Large / Hidden | 4 | 32 |
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

`Tests/YubaiUITests/ScreenGalleryTests.swift` 是停点的来源。`scripts/gallery_inventory.py` 从实际方法和共享巡游生成清单，检查重复名称、105 块稿的四种状态以及 CI 是否逐条排入。`scripts/gallery.sh` 使用同一清单生成 `expected.txt`；未执行的停点也会报缺失。CI 每个 part 只跑一条巡游，测试方法最多 30 分钟，作业上限 50 分钟。实际耗时仍需在 Mac 验证。

## 每个停点的检查

所有新旧停点在截屏前经过唯一的 `auditGallery()`：

- 检查当前可触达控件的 44pt 点击区、互相覆盖及固定主动作越界；排除系统键盘、菜单、滚轮与包裹子控件的容器。
- 调用 XCTest 的 `textClipped` 辅助功能审计。设计允许单行省略的名称标为 `truncatableName`，页头名称和回执正文允许省略，输入内容可随光标滚动；金额与按钮不豁免。
- 检查关键金额没有省略号；记账的支出／收入／转账保持同一行。

这些检查是运行时辅助检查，不能替代截图逐屏对稿、旁白和真机边缘返回验证。滚动内容允许暂时在视口外；固定主动作不允许。

## 输出与失败

`.shots/` 每次运行前清空且被 git 忽略。正常停点写 `<name>.png`，同时保存同名 `.keepAlways` XCTAttachment。失败写 `<name>-MISSING.png` 与层级文本，并继续后续停点，最终令 XCTest 和脚本失败。

`expected.txt` 是所选巡游的完整计划；`missing.txt` 合并运行报告和未产生正常 PNG 的停点；`index.txt` 记录数量、git SHA、xcodebuild 状态、结果包路径和文件列表。构建失败、缺图或任何审计失败均返回非零，即使已有部分 PNG。诊断图片不算完成对应停点。

DerivedData、xcresult 和构建日志在脚本打印的 `/tmp/yubai-gallery.*` 下。XCTest runner 使用 `TEST_RUNNER_YUBAI_GALLERY_DIR` 转发输出目录；宿主写图受限时从 xcresult 附件清单恢复名称。没有非空 `YUBAI_GALLERY_DIR` 的普通 UI 测试会跳过图库类；没有新增禁用的流程测试。

## 数据隔离与补充状态

所有夹具仅限 `DEBUG && targetEnvironment(simulator)`，还须 UUID 形式的 `--test-ledger`。每次启动都使用独立缓存目录，稳定领域 ID；助手使用离线 transport，不读取真实账本、不联系云服务。外观、字号、隐藏金额均随夹具设定，不改模拟器全局偏好。

`gallery`、`gallery-empty`、`gallery-locked`、`v46-*`、`v47-*` 和已有专用夹具覆盖超长中英文名称、零余额、0.01、大额、信用欠款、超支、隐藏账户／分类及撤销。有效交易仍由 Core 校验，不注入业务禁止的零金额交易。

第五批还覆盖实际重复分类校验、删分类并迁移记录、长文本输入、统一回执与撤销、账户金额键盘、AI 子页、通知和设备设置。加密恢复夹具通过真实 `Backup.export/restore` 生成并读取隔离目录内的临时文件；版本选择夹具使用本机文件版本源，不依赖 iCloud。两者仍走正式页面和校验逻辑。

系统文件选择器、相册／相机权限、设备解锁、真实后台任务及真实 iCloud 冲突受宿主和设备能力约束，不能由静态覆盖清单证明。已删除的旧图表、旧储蓄目标编辑器和无入口页面不再造路线展示。

Linux 可运行清单、脚本合约、UI lint、条件语法解析与 Core 单测；Apple SDK 构建、UI XCTest 与实际截图须在 Mac 上执行。

第四十七轮 A 批覆盖：三标签和居中记账宽钮、推入的存钱页、存钱卡四态、小票空态／正常／新增／滑出撤销／撤销后／超过六笔、首次「窗」场景与减弱动态效果、首笔后工资设置／延期／新收入触发／日期到期，以及超长名称与大额。小票新增态通过正式记账流程产生，不伪造页面状态。存钱页的存取操作由 B 批停点验证。

第四十七轮 C 批覆盖：十种空态、常用模板添加、首页建议、证据首四笔／全部／纠正、两周回看、设置开关与上次运行、零建议、长名称和大额。首页建议由脚本回复经过正式每周请求、Core 验算和队列产生；错误合计、未知记录、未知动作与损坏 JSON 另由流程测试验证。`V47-Butler-AI` 是 Core 合约板，画廊对应其设置入口；不新增一张解释机制的产品页面。

第四十七轮 B 批覆盖：单卡竖式及零扣项／负数／大额、每项去向、拿出和放回的预览／限额／保存／撤销、底线改清、普通存取流水、发薪日全部／部分／不补与队列轮转，以及短回执、截断、展开、撤销和关闭。

第四十七轮 D 批覆盖：补回与 AI 建议共用的首页／牌组／证据页、各自回答后状态、长名称与大额、多条建议、五种错误或空回复、关闭建议、空句纠正与回看答复。`V47-Changes` 是八项变更的总览合约板，其停点验证整合后的首页和共用队列，不把设计说明加入产品界面。
