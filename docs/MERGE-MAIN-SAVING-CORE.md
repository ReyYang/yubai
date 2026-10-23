# main 与省钱分支合并核对

2026-10-23，`origin/main`／`9703831` → `feat/butler-saving-core`／`bb81a8c`，继续已有 merge。按 owner 明确要求保留两边功能与历史记录；未提交、未终止 merge、未联网调 API。

## 八个冲突的取舍

| 文件 | 合并结果 |
| --- | --- |
| `.design-meta/DESIGN.md` | 两边章节完整保留；新增本轮记录，明确 V14 停止 sheet 覆盖历史单按钮确认、小项页采用标准推入，历史验证仍属原轮次。 |
| `.design-meta/README.md` | 保留 V15／Core／V16／编译／显示／问余白记录及 main 的固定收付、取消侧滑返回记录；顶部登记当前合并与验证／暂存边界。 |
| `.scratch/yubai-product/issues/13-complete-personal-release.md` | 保留两边 owner 决定、实现选择和未验证项；追加此次明确合并任务，不将历史业务票或整票标成完成。 |
| `Sources/YubaiApp/FixedFlowsView.swift` | 采用 main 的状态与逾期显示、已停掉旧期处理、结算／跳过／取消 sheet；保留本分支 iOS HorizontalPan、停止按钮 identifier 与 macOS 手势分支。停止调用 FixedFlows.stop，仍进入本分支停订快照链。 |
| `Sources/YubaiApp/InsightsView.swift` | 保留本分支单一主项的小项目的页与当前期间／收支／标题，合并扇区保留 FlowRecordsView；使用 main 的 TabNavigationLink 值导航，删除分类入口成对 zoom，标准推入。 |
| `Sources/YubaiApp/UITestSupport.swift` | 白名单取两边并集：保留八个 V15 截图脚本、原夹具及 main 的 bills-clarity／bills-multiple 和准备数据；Debug＋模拟器＋UUID 隔离不变。 |
| `Sources/YubaiApp/YubaiApp.swift` | 同时保留 main 的四个独立 NavigationPath／tabBarHidden、路由与本分支 pagingPhase 停稳同步；新增 subcategoryInsights 路由，传完整小项页参数，sheet／macOS 使用原目的视图闭包。 |
| `Tests/YubaiUITests/AppFlowTests.swift` | 保留 HEAD 的 55 个与 main 的 54 个测试方法，并集 62 个，无重名；同名用例合并断言。已记状态断言改 main 灰勾，保留本分支 toast 等待、慢拖及 isHittable 查询；main 新增测试对齐小项标题、支出控件和云端关闭状态入口。 |

自动合并内容也已核对：记录详情仍是标准推入并保留 EntrySubcategoryRow；DesignSystem 移除浮栏出现回调，保留本分支手势判向、即时气泡与少写字；根页 push 使用 TabNavigationLink。Core 同时保留 skipOccurrence／旧期处理与 schema 3、停订快照、省钱、小项及购买能力。未修改本分支的 YubaiCore.Category、ToolbarItem 包装、拆分子视图、问余白纸色导航栏、追问移焦点／滚动修复或八项显示修复。

文档保留历史来源名称并去掉私有页面地址。sheet 隔离用例使用 manual 夹具：测试运行时已配置假 transport、云端智能关闭，因此从「云端智能没开 ›」进入设置。

## 本次新增或改动的可见中文

相对合并前 HEAD，新增／变化均来自 main 已采用的 V14 固定收付稿；没有另造说明文案。洞察路由变化不新增文字，原「X · 本月」及其他期间标题保留。下列 `{…}` 表示真实账本值；既有账户、自动、分期、大约等未变文字不重复列出。

| 文字或模板 | 类别／出现位置 |
| --- | --- |
| 要付 | 标题，支出分区 |
| 其中／已过期／过期没收到 | 状态，金额与两种逾期流向同一行 |
| {日}日 · 今天到期／今天该收到 | 日期事实＋状态 |
| {日}日 · 过了 {N} 天还没记／还没收到 | 日期事实＋状态 |
| {日}日 · 还没到／已付／已收到 | 日期事实＋状态 |
| {月日}记 | 事实，实际手动记下日期 |
| 付了／收到了 | 控件，到期未处理行的描边按钮 |
| 停掉「{名称}」？ | 标题，停止 sheet，沿用已有确认标题 |
| 还有 {N} 期没记。 | 数字和状态，仅在停止 sheet 出现 |
| {月日}这期还没记。 | 日期事实和状态，仅在停止 sheet 出现 |
| 只停以后的，付过的记录保留。 | 事实，仅在没有待处理期的停止 sheet 出现 |
| 付了，记一笔再停／收到了，记一笔再停 | 控件，写执行结果 |
| 没付，这期也不要了／没收到，这期也不要了 | 控件，写执行结果 |
| 停掉／取消 | 控件，无待处理期的停止按钮和关闭按钮 |
| {月}月{日}日停掉 · 还有 {N} 期没记 | 日期事实和状态，唯一的已停掉行 |
| {月}月{日}日停掉 · {日}日那期还没记／还没收到／已记／没要 | 日期事实和状态，唯一的已停掉行 |
| 不要了 | 控件，处理已停掉旧期 |
| 已记下／已不要了 | 状态，处理结果提示条 |

「停掉以后的」单按钮由 V14 的按状态结果按钮替换；原日期点阵删除，不补说明。上述文字均属于标题、事实／数字、控件或状态，无需规则外说明例外。读屏文字仍完整保留。

## 验证

- `export PATH=/opt/swift-rootfs/usr/bin:$PATH && swift test` 退出 0：464 项，460 通过、4 原有实网 opt-in 跳过、0 失败。运行环境显式设 YUBAI_LIVE_EVAL=0；日志 `/tmp/yubai-main-merge-swift-test.log`。
- 全部 38 个 App 文件逐个通过 swiftc -frontend -parse：arm64-apple-ios26.0-simulator、arm64-apple-ios27.1-simulator、arm64-apple-ios26.0、arm64-apple-macosx14.0。模拟器 Debug 开启 YUBAI_APP_GROUP／YUBAI_ICLOUD／AppIntents 条件，macOS Debug 开启 YUBAI_ICLOUD，设备覆盖 Release。
- UI 测试文件通过 iOS 26／27.1 模拟器 Debug 条件解析；测试名集合等于两边并集，62 个方法且无重复、无删除／新增跳过。
- 从当前 UITestSupport 提取同一源码，仅移除最外层模拟器编译条件，与本轮编译后的真实 Core 链接；八个截图脚本的账本、假 transport 购买／追问／消费观工具链执行通过，main 两个夹具通过 UUID 白名单、prepare／load／validate，并核对已付状态与六个待处理期。临时检查文件仅在 `/tmp/yubai-main-merge-fixture-check/`。
- git diff --check 通过；全部版本管理文本无冲突标记、无私有页面链接。三份冲突文档两边历史内容保留。

Linux 无 Apple SDK，以上不代表 SwiftUI／XCTest 类型检查或 UI 实跑通过；标准推入首帧、侧滑取消、分页、键盘与视觉仍待 Mac 复验。原稿、Figma 与分发包未同步。

## 暂存边界

工作树已解决。执行 git add 退出 128：无法创建 `.git/index.lock`，当前沙盒将 `.git` 挂载为只读。未尝试更改权限或退出 merge；索引仍保留八个未合并文件。请在 `.git` 可写环境中运行以下命令，只暂存，不提交：

```sh
git add \
  .design-meta/DESIGN.md \
  .design-meta/README.md \
  .scratch/yubai-product/issues/13-complete-personal-release.md \
  .scratch/yubai-product/map.md \
  Sources/YubaiApp/FixedFlowsView.swift \
  Sources/YubaiApp/InsightsView.swift \
  Sources/YubaiApp/UITestSupport.swift \
  Sources/YubaiApp/YubaiApp.swift \
  Tests/YubaiUITests/AppFlowTests.swift \
  docs/MERGE-MAIN-SAVING-CORE.md
```
