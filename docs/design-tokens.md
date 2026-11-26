# Design tokens

`design-tokens.json` 是颜色、字体、间距、圆角、尺寸、阴影和动效的唯一 token 真源。Python 标准库生成器保留 JSON 顺序，输出 `DSTheme.swift` 与 `DSMotion.swift`；网页预览也应读取这份 JSON，不再维护另一组数值。本次只实现原生生成物，没有把外部旧版网页生成器复制进仓库。

```bash
python3 scripts/generate-design-tokens.py
python3 scripts/generate-design-tokens.py --check
python3 scripts/generate-project.py
python3 scripts/ui_consistency.py --self-test
python3 -m unittest discover -s scripts/tests
```

`--check` 仅在内存中生成并逐字比较，过期输出给 unified diff、返回 1。lint 自动运行它。项目与 shared scheme 由 generate-project.py 生成，不手改。SnapshotTesting 精确固定 1.19.6，只链接 hosted `YubaiDesignSystemTests`；现有根 `Package.resolved` 不改，Xcode 可在首次解析时写自己的 workspace resolved 文件。

页面使用 `DS.Color/Font/Space/Radius/Stroke/Size/Shadow/Material/Icon` 与 `DSMotion`。`DSStyle.swift` 编码行盒、Dynamic Type、盒模型、按压、循环和 Reduce Motion。`DSComponents.swift` 提供 17 组组件及配套 DayHeader、AmberTile、AskBar、菜单。金额与日期由调用者提供，gallery 固定样本，不接业务页面。接口与 CSS 翻译规则见 [design-system skill](../.claude/skills/design-system/SKILL.md)。设计变更先进入设计系统与设计稿，再写代码。

审计规则覆盖全 App：continuous 圆角；禁用 cornerRadius modifier、自定义字体、衬线、easing 曲线；玻璃只用系统 material/glassEffect。DS 文件可以定义几何，但 hex 只准出现在生成的 DSTheme.swift。所有新动画由四组未经换算的物理弹簧驱动；减弱动态只留下 smooth opacity，位移、缩放和数字替换直接跳。阴影只有 color/radius/x/y。旧的竹影 penumbra（5pt）与透光边缘 feather（1.4pt）是装饰性深度模糊，材质会改变其光影含义，保留并逐行注明 `ds-allow-blur`。`DSInteraction` 只保留 0.7 按压透明度、85% 预算阈值与动效角色提供的 floatScale；组件几何直接引用专用 token，不用不相关 token 的算术凑尺寸。数量使用 `DSLayout` 的整数，gallery 柱高使用 `GallerySample` 的 `[CGFloat]` 样例数组。所有 Swift 文件都禁止 token 转 `Int` 和不相关 token 算术；同心内圆角与两处分隔线缩进是明确列出的例外，详见 design-system skill。

## 快照与动效

DEBUG 启动 `-YubaiDesignSystemGallery`，或环境变量 `YUBAI_DS_GALLERY=1`。Release 不编译 gallery。十节快照为 `colors`、`type`、`spacing`、`radius`、`shadow`、`components-skeleton`、`components-numbers`、`components-entry`、`components-overlay-controls`、`motion`；宽度为 393pt、3×，高度随内容测量，组件分区各不超过 1600pt。zh_CN、默认大号字体、固定样本，禁用 UIView/SwiftUI 动画，循环静止，Reduce Motion 关闭。明暗共 20 张，命名为 `gallery.<section>-<light|dark>.png`。完整 gallery 保留原来的组件顺序、全部样本和 accessibility identifiers，组件与动效跳转按钮继续可用；TabBar 快照保留系统玻璃并加实色底层。

```bash
# 在装有 Xcode 26 的 Mac 上；SIM_UDID 为已启动的 iPhone 模拟器。
xcodebuild build-for-testing -project Yubai.xcodeproj -scheme Yubai \
  -destination "id=$SIM_UDID" -derivedDataPath build/DSDerivedData \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
TEST_RUNNER_DS_SNAPSHOT_RECORD=1 TEST_RUNNER_DS_SNAPSHOT_EXPORT_DIR=/tmp/ds-png \
  xcodebuild test-without-building -project Yubai.xcodeproj -scheme Yubai \
  -destination "id=$SIM_UDID" -derivedDataPath build/DSDerivedData \
  -parallel-testing-enabled NO -only-testing:YubaiDesignSystemTests
```

记录全部用 `DS_SNAPSHOT_RECORD=1`；验证时去掉该变量（`.missing`）。缺失基线会记录并失败，已有基线不匹配也失败。`DS_SNAPSHOT_EXPORT_DIR` 每次导出用于比对的实际 PNG，即使完全匹配也导出。xcodebuild 转发变量用 `TEST_RUNNER_` 前缀。取回生成的 `Tests/YubaiDesignSystemTests/__Snapshots__`，审阅后再纳入版本控制。本 Linux 工作区没有 Apple SDK，因此本次不伪造 PNG 基线或 MP4。

手动工作流 `design-system.yml` 的 record 默认 false、video 默认 true，无 push/PR 触发。它编译后跑 hosted 快照，再用同一模拟器录制约 30 秒动效测试；只在 record 模式容忍成功记录引起的断言，崩溃、PNG 写入失败和其他断言仍失败。记录与验证模式均用 `scripts/check-ds-snapshot-result.py` 校验导出的 20 张 PNG，标准库 zlib 解码 8-bit、非交错的灰度、RGB、LA、RGBA，拒绝全透明或单一纯色图片。上传 PNG、基线、视频和 xcresult，保存 14 天。动效测试不靠截图：触发四种弹簧往返、play all、按住按钮、数字三次变化、原生 sheet 拖动关闭、Toggle、Accordion。动效测试用 `-only-testing:YubaiUITests/DesignSystemMotionTests` 显式选中。

## 本次可见中文字符串

以下仅出现在新组件的默认控件或 DEBUG 样本。旧页面没有新增可见文字。标题、事实/数字、控件或状态四类已覆盖全部，无说明句例外；accessibilityLabel / accessibilityValue 不算可见文案。

| 类别 | 字符串 |
|---|---|
| 标题与名称 | 颜色、字体、间距、圆角、阴影、组件、动效、昨天、本期入账、午饭、盒马、为了搬家以后和家人朋友一起使用的生活用品、电影票、打车、工资、娱乐、购物、买菜、吃饭、交通、居住、咖啡、午餐、早餐、晚餐、夜宵、衣服、数码配件、日用杂货、地铁、公交、房租、水电、维修、换手机、最多、其余 |
| 控件 | 记一笔、记下、完成、调整、添加小类、首页、全景、问余白 · 搜账单、今天、昨天、前天、日历、每月、更多、全部、支出、收入、编辑、改分类、再记一笔一样的、删除、打开弹窗、全部播放、按压 |
| 状态 | 待 AA、待报销、存入、不变、走机动余钱 |
| 固定事实与数据 | 信用卡、招行储蓄、招行信用卡、还能花、记下后还能花、吃饭剩 1,194.00、走机动余钱 · 还剩 1,421.00、购物 · 今天 14:20 · 招行信用卡、11.10 – 12.09 · 还剩 16 天、衣服比上期多 181%、上期留下、已转入机动余钱、移、腾、云 |
| 动态事实模板 | `已用 {百分比}`、`{数量} 个小类`、`每天 {金额}`、`还剩 {天数} 天`、`{日期} · 每月 {日} 日`、`/ {总额}`；纯金额、数字、色值与 token 名称照 JSON/固定样本展示 |

## 旧层映射

相同 light/dark（含 alpha）才允许别名，其他颜色标 `legacy: no DS v4 token`：

| YubaiColor | DS.Color |
|---|---|
| canvas / card / raised | bg / surface / raised |
| keypadTray / key / keyFn | tray / key / keyFn |
| selected / label / labelMuted / labelSecondary | selected / ink / ink2 / ink3 |
| separator / grabber | separator / grabber |
| brand / onBrand / brandInk / brandTint / toggleOn | accent / onAccent / accentInk / accentSoft / accent |
| amberTint / amberInk / amberDot | warnSoft / warnInk / warn |
| seriesSoft / neutralStrong / neutralSoft / chartRule | chart3 / chart4 / track / chevron |

| YubaiMotion | DSMotion |
|---|---|
| settle / layout / entrance / dismiss / chartGrowth / chart / progressFill / progress / stagger / toastOut / easeOut / easeIn | smooth |
| snappy / snappySpring / control | snappy |
| lively / livelySpring / ring / toastIn | bouncy |
| instant / quick / number / wash / easeInOut | standard |
| thinkCycle / think | Loop.breathe 的 smooth + hold |
| 减弱动态的非可选过渡 | smooth，仅 opacity；layout/ring/chart/progress/think 返回 nil |

公开兼容函数名保留；`easeOut/easeIn/easeInOut(duration:)` 的参数不再参与缓动计算。生命周期、停留、延迟常量保留。窗口摇影换成 PhaseAnimator + smooth spring；第一屏光线切换换成 smooth opacity；思考循环换成 token 的相位弹簧。所有旧 RoundedRectangle 补 continuous。
