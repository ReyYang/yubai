余白是只服务本人的个人资金软件，iPhone 优先。它只回答一个问题：先留出要付的和该留的，还剩多少可以放心花。界面像一张暖色的纸：一屏只讲一件事，用一个大数字加一张图讲完，字越少越好。三条底线：数字永远由账本算；不确定的钱往少了算；绿色只留给“余白”和要你做的那一步。

2.0 起余白是一位克制的财务管家：代码算数，你来决定，AI 在旁边帮忙。**手动优先（2026-10-21 用户定）**：任何事都能自己点完，记账、改账、看账目不需要开口；问余白是辅助，不是唯一入口。应用有三个标签：**现在**（还剩多少、今天记了什么、管家想说的一件事、钱会怎么走）、**洞察**、**我**（消费观、心愿单、账户、账目、固定收付与维护）；标签栏右侧的主圆钮是**记一笔**，问余白在三个标签页顶栏右侧。管家只在两种时候开口：碰到你想克制的事，或者钱不够付接下来的付款。

## 语气与文案

- 对用户说“你”，句子短，像朋友提醒，不像报表。页面开头常用一句话把结论说完：“从 32,860 现金里，先把该留的都留出来。”“钱只是换了个地方，不算花掉。”“3 笔被移到这里”。
- 卡片标题写成一个问题，图回答它：“现金会怎么走”“每天花了多少”“花在哪”“照这样留，三月够不够”“哪个跑得动”。
- 主数字上方用 `hero-label` 说清它是什么：“还能自在支配”“十月已经花了”“接下来 90 天要付”。不写“总资产”“可用余额”这类行话。
- 金额用人民币，千分位，列表行保留两位小数（`−42.50`），主数字和图上取整（`¥12,480`、`605`）。入账带 `+`，出账带 `−`（U+2212，不是连字符）。日期写“10月16日”“今天”“昨天”，不写 2026-10-16。
- 不确定就直说：“待明确”“是估的”“可能记重了”，用 amber 一组颜色标出，并给下一步（“去确认”“去改”）。从不替用户猜性质或金额。
- 保守口径要写在旁边：“小林的钱到账前不算进余白”“工资到账前不算进来”“圆点是已知的大额付款”。
- 动作词朴素：“记一笔”“记下这笔”“说一句”“放回去”“回到这里”“关联这两笔”“先跳过，以后再导入”。确认按钮写结果，不写“确定”。
- 空状态先讲事实再给一步：“这一页，还没有记录”“还看不出水位”“先有生活的记录，再有洞察”，不写“暂无数据”。
- 页面里不写解释产品怎么运作的句子（如“余白按你说过的话来提醒你”“想买的先放这里”“急的排在前面”）：标题和内容本身说清楚了就不再加一句。只留带事实或数字的话（“86 笔，已经整理好了”），和会改变用户下一步的提醒（“没答的问题会留在「现在」”）。解释留给空状态和第一次进入。

## Token 怎么命名

名字说用途，不说颜色。同一组用同一个前缀，读名字就知道能放在哪：

| 前缀 | 管什么 | 例子 |
|---|---|---|
| 无前缀的底 | 三层底和选中底 | `canvas`、`card`、`raised`、`selected` |
| `label-*` | 文字三级 | `label`、`label-muted`、`label-secondary` |
| 线 | 分隔、拖动条、虚线框 | `separator`、`grabber`、`border-dashed` |
| `brand-*`、`on-brand` | 品牌绿和它的字、底、记号 | `brand`、`brand-ink`、`brand-tint`、`brand-mark` |
| `amber-*` | 需要留意 | `amber-tint`、`amber-ink`、`amber-dot`、`amber-mark` |
| `series-*`、`neutral-*`、`chart-*`、`outflow` | 只在图表里 | `series-soft`、`neutral-strong`、`chart-rule` |
| `toggle-on`、`icon-*` | 单个控件或应用图标专用 | `toggle-on`、`icon-tile`、`icon-ink` |
| `space-N`、`radius-*`、尺寸名 | 间距（N 就是像素）、圆角、固定尺寸 | `space-18`、`radius-card`、`button-height` |
| `duration-*`、`ease-*` | 动效 | `duration-quick`、`ease-out` |

字样按用途起名（`amount-hero`、`card-title`、`meta`），不按字号。新加 token 先看这张表能不能放进已有的组；放不进再开新前缀。

## 视觉基础

**颜色。** 两个主题：`light`（浅色，默认）和 `dark`（深色），语义相同、各自取值，不是自动反色。

- 底只有三层：页面 `canvas`、卡片 `card`、浮在上面的浅层 `raised`（圆形按钮、返回胶囊、标签栏、输入条、卡里的小胶囊、下一笔这类提示行）。芯片选中用 `selected` 并加中等字重。
- 文字三级：`label`（正文、标题、金额）、`label-muted`（解释句）、`label-secondary`（日期、账户、轴标签、脚注）。不要再造灰色。
- `brand` 是唯一的品牌色，只用在：主按钮底、问余白圆钮、图表里被强调的那一个系列、进度、选中的勾。它在浅色卡片上只有 3.7:1，不拿它写小字；绿色文字一律用 `brand-ink`。
- 助手说的话、好消息放在 `brand-tint` 上，标题 `brand-tint-strong`，正文与胶囊字 `brand-ink`，水波记号 `brand-glyph`。
- 需要留意的一切用 amber 一组：底 `amber-tint`，字 `amber-ink`，标题 `amber-strong`，圆点 `amber-dot`，图里的那一段 `amber-mark`。amber 只表示“需要你看一眼”，不表示错误，也不用来装饰。
- 开关打开用 `toggle-on`（暖灰），不用品牌绿：它是设置，不是结果。
- 应用图标的方块和墨色 `icon-tile`、`icon-ink` 两种主题都不变。

**字体。** 三个家族，各管一件事：

- 数字一律 `num`（Geist，等宽数字），七级从大到小：`amount-hero` 只在首页出现一次；其他页面的主数字 `amount-display`；表单里正在输入的金额 `amount-input`；卡片里的结论 `amount-large`；列表金额 `amount`；卡片标题右侧的合计和进度分数 `amount-small`；图上数值 `chart-value`。
- 衬线 `serif`（Noto Serif SC）只给“说一句话”的地方：页面开头的 `lead`、用户和助手的话 `quote`、主数字标签 `hero-label`、卡片问题 `card-title`、欢迎页 `welcome`。账本月份用 `month`（Fraunces 落数字）。衬线不用于数据、按钮和列表。
- 其余都是 `sans`（Noto Sans SC）：顶栏 `nav-title`、助手回答和较长正文 `body`、行 `row-title` / `row`、说明 `callout`、图例 `caption`、元信息 `meta`、图表轴 `chart-label`、标签栏 `tab-label`、按钮 `button`。正文最小 `meta`（11px）；10px 只给图表轴和标签栏。

**间距与尺寸。** 页面左右 `space-18`；顶栏 `header-height`（48）下面隔 `space-20` 才开始内容；图表卡内边距 `space-18`，列表卡左右 `space-18`、上下 4，建议卡和提示卡 `space-16`；同组卡片间隔 `space-10`，图表卡之后 `space-12`。可点的东西不矮于 `tap-min`（44）。页底主按钮 `button-height`（52）满宽，两个并排各占一半、间隔 `space-10`。

**圆角。** 卡片 `radius-card`（22），单独一行的浅层块 `radius-row`（18），标签栏 `radius-tabbar`（24），分段格子 `radius-control`（14），胶囊、芯片、按钮、输入条一律 `radius-full`，柱和条的数据端 `radius-bar`（4）。“水位”图标方块用 `radius-tile`。

**层次。** 层次靠底色明度，不靠阴影和描边：卡片没有阴影也没有边框。阴影只有四处：标签栏和批量操作条 `shadow-float`，问余白圆钮 `shadow-ask`，问余白输入条 `shadow-input`，开关圆钮 `shadow-knob`。全应用没有渐变。

**玻璃（Liquid Glass，2026-10-21 用户决定）。** 应用最低系统升到 iOS 26，浮在内容上的那一层改用系统 Liquid Glass：标签栏、记一笔圆钮（品牌色着色玻璃）、顶栏圆钮、返回胶囊、提示条、问余白输入条和 sheet。卡片、数字、图表和列表永远是不透明的暖纸底，玻璃上不叠玻璃。玻璃一律用系统的 `.glassEffect` 和系统控件，不自己画模糊和高光；浮层原来的 `raised` 底和 `shadow-float`、`shadow-ask` 在 iOS 26 上由玻璃取代。样机：[余白 · 动效样机](https://claude.ai/artifact/SDsMQU5KWfrnZRhL6NJQui)。

**密度。** 一屏一个主角：要么首页的那个数，要么一张图。一屏最多三张卡；能用图说的不用表格，能用一句话说的不放图例。次要的东西收进“下一笔”这种一行提示，或者点进去再看。首页只显示今天；完整的账在“账目”：按天分组的长列表，能搜、能改、能删，是唯一允许长列表的页面。

**记一笔。** 一个 sheet：顶部分段 支出 / 收入 / 转账，下面大金额、常用分类芯片、用途 / 账户 / 日期三行，一行“记下后，还能自在支配 ¥…”，底部数字键盘（`Keypad`）。主键写结果“记下 32 元”，旁边一行“记下，再记一笔”。只有用途会弹系统键盘。默认值：上次用的账户、今天、按用途猜的分类（猜的分类可直接点掉）。改一笔用同一张表，多一个备注和“删除这笔”。

**导入。** 从记一笔 sheet 右上角“导入”进入，截图和账单文件都可以一次选多份，排成队一份一份核对（“核对 1/3”）。核对页先给来源、日期范围、笔数和收支合计，然后只把要你决定的事放在上面（没有的分类、没写账户记到哪、可能重复），最后按天列出每一笔；主键写结果“导入 42 笔”。常见导出在本机读，页面写一行“在本机读完，没有发给云端”。

**“现在”一屏看完。** 在 390×844 上不滚动就能看完，从上到下只有六样：顶栏（左隐藏金额、右问余白）、主数字和构成条、“今天”一行（今天记了几笔、合计，点进账目）、最多一张管家卡（`ButlerCard`）、“现金会怎么走”图、“下一笔”一行。记一笔之后主数字按这笔的金额逐位换成新值（见“动效”的落笔），提示条给撤销。其余都收起来：另外几张管家卡收进卡片右上角的“还有 2 件 ›”，来信是一行入口，完整计算依据点主数字进去，导入在记一笔 sheet 右上角。新东西想放进“现在”，先决定替换掉哪一样。大字号或小屏放不下时，先缩图（图高可从 150 缩到 96），再把图收成一行“现金会怎么走 ›”，不把主数字和管家卡挤出首屏。

**洞察：收支按类型。** 想看一段时间钱花在哪、从哪来，去第二个标签“洞察”：顶部选时间窗（本周 / 本月 / 近 3 个月 / 自定，左右切上一段下一段），下面三格收入、支出、结余，再是一张卡：卡里先用分段切换“支出 · 按类型 / 收入 · 按类型”，下面一个环形饼图（直径 180、环宽 26、段间留 2.5 的缝，中间写合计），再下面逐类图例行（色块、类型、金额、占比、›）。饼图配色按“着色靠强调”：从大到小 `brand` → `series-2` → `series-3` → `neutral-strong` → `neutral-soft`，消费观里想克制的类型用 `amber-dot` 并在行里标“想克制”；最多 6 段，其余合成“其他 N 类”。环上不写字，数值全部写在图例行里。点一行推入这段时间该类型的每一笔。转账、还信用卡和退款对冲不算收支，写在列表最后一行脚注。这一页可以滚动（只有“现在”要求一屏看完），内容底部同样让出 106。

**页面骨架。** 顶栏三种：标签页根（左圆钮、中间标题、右圆钮）、推入页（左返回胶囊写上一页名字、中间标题、右侧可选文字按钮）、sheet（顶部 `grabber` 拖动条，左“取消/关闭”、右“保存”主色胶囊）。有标签栏的页面，内容底部给标签栏留出 106 的空间：标签栏和问余白圆钮在同一行，浮在内容之上，内容的最后一行滚到底时必须完整露在标签栏上方，任何浮层都不能盖住它。sheet 和推入页没有标签栏，也不显示问余白圆钮。

**状态。** 按下降到 75% 不透明。选中从不改颜色，只换底色并加中等字重：芯片用 `selected`，分段控件的选中格用 `raised`，标签栏的当前标签用 `card`。动效见下一节。

**深色。** 同一结构、各自取值：底变成 `#1f1b14` 的深咖，`brand` 提亮到 `#86a884`，`on-brand` 变成深色字。应用图标方块不变色。深色首页见设计稿“现在 · 深色”。

## 动效

动效的性格是水：有分量，会落定，不喧哗。它做三件事：让你看清“刚才变了什么”、让你知道“从哪来回哪去”、让“水位”这个记号在关键时刻活一下。可点的样机见 [余白 · 动效样机](https://claude.ai/artifact/SDsMQU5KWfrnZRhL6NJQui)（2026-10-21，待用户确认），代码以它为准；演示卡见 `Motion`。

**边界（九条）**

1. 一次只有一个主角：每次操作只让一样东西带性格地动，其余只淡入淡出或跟着让位；几件事要发生时排先后，不同时抢。
2. 三档时长封顶：反馈 ≤ 160ms；过渡 ≤ 450ms；品牌时刻整段 ≤ 700ms。
3. 随时能打断：动画中手指照样能点、能滑，新动作从当前位置接上；不用延迟链锁住输入。
4. 只有三条弹簧：`spring-settle`（大面：页面、sheet、卡片让位，不回弹）、`spring-snappy`（小控件：标签底块、分段滑块、芯片、提示条、数字逐位，微回弹）、`spring-lively`（只给记一笔圆钮松手和“记下”后水面一晃）。不再加别的弹簧。
5. 位移有限：控件和内容位移 ≤ 24pt，缩放只在 0.92–1.04；页面和 sheet 除外。除了水波，什么都不旋转。
6. 只有一处循环：助手思考时的水波，拿到回答立刻停。
7. 玻璃只在浮层：标签栏、圆钮、胶囊、提示条、输入条、sheet 是玻璃；内容永远是暖纸底。标签栏的选中块是一滴更亮的玻璃，切换时被拉长流到新标签再收圆；按住标签栏整块像透镜一样微微放大。
8. 落定才给触感：记下、删除、撤销、到达底线提醒各一次系统触感；切标签、滚动、输入数字不给。
9. 减少动态效果：位移、缩放、弹簧全部换成 `duration-quick` 的交叉淡入；水位和图表直接显示终点；按压和触感照旧。

**每一处怎么动**

| 场合 | 怎么动 | token |
|---|---|---|
| 按压 | 按下 75% 不透明并缩到 0.97，松手回来。记一笔圆钮按下 0.92，松手用 lively 弹回 | `duration-instant`；圆钮 `spring-lively` |
| 标签切换 | 玻璃选中块被拉长流到新标签再收圆（系统 TabView 自带）；新页面从切换方向偏 12 淡入，旧页面原地淡出（120ms）；新标签图标动一下：现在的三道水位依次升起，洞察的扇区转进来，我的头像轻点一下 | `spring-snappy`；页面 `duration-standard`；图标错开 `duration-stagger` |
| 从卡片放大进入 | 今天 → 账目、洞察的类型行 → 这类的每一笔、我 → 账目、主数字 → 计算依据：下一页从点的那块长出来，返回缩回原处，可下拉或边缘滑回。只给“从一块内容进它的详情”；设置类列表仍用系统推入 | `spring-settle` |
| 其他推入页、返回手势、键盘 | 系统默认 | — |
| sheet | 系统 sheet 升起，后面的页面缩小后退；问余白的 sheet 从右上角圆钮长出来 | 系统；问余白 `spring-settle` |
| 数字变化（余白、合计、结论、正在输入的金额） | 只换变了的那几位：变大时新数字从下方升起，变小时从上方落下，略带模糊；不滚过中间值 | `spring-snappy` |
| 落笔（品牌时刻，点“记下”） | sheet 落下 → 余白逐位换成新值，同时水位记号水面一晃并给成功触感 → “今天”一行换成这笔 → 提示条升起给撤销；整段 700ms 内。撤销只换回数字，不晃水面 | `spring-lively`（水面）、`spring-snappy` |
| 图表第一次出现 | 台阶线从左往右画完，低于底线的点落下后外圈扩一次；环图从 12 点顺时针一段段长出；柱从 0 基线长出。冷启动后第一次看到时长，之后直接是终点 | `duration-draw`、`duration-stagger`、`ease-out` |
| 环图切换支出/收入、切换周期 | 各段角度直接变形到新比例，不重新生长；合计和每行金额逐位变化 | `spring-settle` |
| 新的一行（账目） | 刚记的那笔撑开插到最上面，底色从 `brand-tint` 褪掉（1.2s）；删除时整行收走，下面补上 | `spring-settle` |
| 管家卡“知道了” | 卡片缩到 0.96 并淡出，下面的内容往上补位 | 200ms `ease-in`，补位 `spring-settle` |
| 分段控件、芯片选中 | 选中底块滑过去；芯片按下后 0.94 弹回 | `spring-snappy` |
| 提示条 | 从下方 12 升起；4 秒后只淡出；可下滑关掉 | `spring-snappy` / `duration-quick` + `ease-in` |
| 隐藏金额 | 所有金额交叉淡成 ••••，不模糊、不翻转 | `duration-quick` |
| 助手 | 你的话升起；水波记号起伏表示在想，回答一到立刻停；回答整段淡入上浮 8，不打字机 | `duration-think`、`duration-standard` |
| 水位升起（品牌时刻） | 横带一道道从下往上升到位：冷启动算出余白时升到余白占现金的比例；导入读取中一格格涨满；“想一想”买完升到五道。同一时刻一次会话只播一次 | `duration-water`、`duration-stagger`、`ease-out` |

- 不做：滚动计数、视差和陀螺仪、卡片逐张入场、骨架屏闪烁、彩带与庆祝动画、3D 翻转、整页模糊转场、颜色渐变过渡（新行底色褪去除外）、自动播放的提示动画。
- 动效从不改变数字的含义：动画开始时读屏已经念新值；动画没跑完就离开页面，下次进入直接是终点。
- 选型：每件事只用一样。动效只用 SwiftUI 自带的 API，收在一个 `YubaiMotion` 里，不引入 Lottie 或其他动画包；图标用 SF Symbols 加本系统的自有记号；图表只用 Swift Charts。

## 图表

图是主要的说话方式，规则如下：

- 先选形：随时间的余额用台阶线（`ForecastChart`），每天或每周的量用柱（`ColumnChart`），类别占比用横条（`BarList`），一个整体的构成用构成条（`Meter`），两段时间对比用累计线（`TrendChart`），从总数一路扣减用瀑布（`Waterfall`），日期上的事件用时间轴（`Timeline`）。一个数就够的，不画图，用 `amount-large`。
- 着色靠“强调”而不是分类色：要说的那一个用 `brand`，其余用 `series-soft` 或中性色。整体构成用同色系由深到浅（`brand` → `series-2` → `series-3`）或 brand + 中性。不要用一排不同色相区分类别：这套暖色在色盲下分不开。
- 需要留意的那一段用 `amber-mark`，待收、估算、未来用虚线。
- 柱宽不超过 `bar-max`，数据端 `radius-bar`；折线 `line-width`（2）；圆点 `marker` 外加 2px 卡片色描边；分段之间留 `space-2` 缝。
- 网格和基线克制：0 基线 `neutral-soft`，网格 `separator`，参考线 `chart-rule` 配一行 `chart-label` 文字，均值和阈值用 `chart-guide` 虚线。
- 直接标数，不放坐标轴刻度：只标最高、最新、被强调的那一两个值，`chart-value`、`label` 色。文字永远是文字色，不用系列色。
- 只有一个系列不放图例；两个系列在卡片标题右侧放小图例，同时在线端直接标。
- 每张图有 `role="img"` 和把数据念完整的 `aria-label`；金额隐藏时图一起收起。

## 余白助手

助手的原则写在设置页上：“帮你读、找、说；改账先给你看，金额永远不改。”

- 入口：三个标签页顶栏右侧的圆钮（`raised` 底、`brand-ink` 水波记号）；另外在记录、管家卡、心愿单里有就事论事的“问余白：这笔合理吗 ›”一行。标签栏右侧的主圆钮留给记一笔。别处出现助手时，用 `brand-tint` 底加“余白助手”署名，或一行带水波记号的小字（“按金额和日期排好了，越上面越像”）。
- 助手说出的每个数字都由账本算出，旁边放“依据：18 笔记录 ›”芯片，能点回原始记录。估算要写“是估算，不会改账本”。
- 助手能做的，手动都能做：记账、改分类、加安排、改消费观都有自己的页面；助手只是更快的一条路。
- 助手提议、用户决定：改分类、配对转账、加安排、改消费观都先出一张提议卡（`ProposalCard`），逐行写清会改哪几笔，两个按钮“改好这 6 笔 / 不用了”，主动作写结果。一句话说了几笔，就出一张多笔草稿卡（`ProposalCard` 的多笔形态）：每笔一行（勾选、用途、分类、金额），同额两笔列两行，下面一行合计，主键“记下 4 笔”；点一行进改一笔。改金额、账户、原始日期的请求直接说明做不到，不出提议卡。
- 买前判断按三行写：付得起吗、和你平时比、和你在乎的比；第三行逐字引用消费观原话，没有消费观就只写前两行并说缺什么。不打分，不下“建议买/不买”的结论，最后给“放进心愿单”。
- 只用云端 DeepSeek：开关一个（`Toggle`），密钥存钥匙串；“发给云端的内容”先按用途汇总次数和“发之前换掉了”哪些信息，再逐次列出；点开一次看经过（`SendTrace`）：编号的步骤，发出的用 `brand` 圆点、云端回的用 `card` 圆点，每步一句白话（你说的、云端想看什么、余白给了什么、云端回了什么），规则说明折叠，原文可看可拷贝；没成功的用琥珀色写原因。没配好或离线时，页面照常显示本机算出的数字，助手处只写一行“联网并配好密钥后，余白才能回答”。

## 管家开口

管家的话就是一张卡（`ButlerCard`），不是通知中心。

- 只在这些时候出卡：碰到你想克制的领域（快到软线或超了）；钱不够付接下来的付款；以及必要的小维护（待明确的钱、太久没核对的账户、导入时没答完的问题）。“无所谓”的领域花多少都不出卡，不夸奖，不提醒“记得记账”。
- 一张卡只讲一件事：一行 `meta` 说类别，一句 `card-title` 说结论，一行 `callout` 说依据，最多一个主动作。钱不够、需要你确认的用 amber 一组；只是观察的（快到线了、不像你）用 `card` 底，不用 amber。
- “现在”上同时只露一张，按“钱不够 > 超线 > 快到线 > 待明确 > 没核对 > 待答问题”取第一张；其余收进卡片右上角“还有 2 件 ›”，点开是“管家的话”sheet。同时存在最多 5 张。
- 每张卡右上角“…”里有“以后别提”，选了就不再出同一类话；“知道了”只收起这一张。
- 每周来信：一段话 + 一张余白一周变化的台阶线 + 三个小数字，周一出现在“现在”顶栏下方的一行入口（“周一来信 · 这周余白多了 320 ›”），点开读全文；读过就只在“我 › 来信”里。推送一周一次，可关，锁屏上不出现金额。

## 图标

- **应用图标“水位”**：一圈 `icon-ink` 圆环，下半部三道等宽横带，上半留白（`BrandMark`；文件在 assets/Logos：`yubai-icon-1024.png`、`yubai-icon.svg`、`yubai-icon-rounded.svg`）。方块 `icon-tile`，深浅色都不变。32px 及以下减为两道横带、16px 一道，线条加粗。水位越高表示越紧：在“想一想”里买完后横带升到五道，导入进度里横带一格格涨满。
- **标签栏里的“现在”**：同一个圆环加三道横带的单色记号，没有方块（`yubai-mark.svg`）。
- **助手的水波**：圆环里一道水波线（`AssistantMark`、`yubai-assistant.svg`），只代表余白助手。
- 其他图标是 24×24、1.8–2.2 描边、圆角端点的单线图标，用 `currentColor` 着色（返回、加号、眼睛、搜索、话筒、上传、垃圾桶、勾）。原型里可以用 assets/Icons 的 Lucide 替身；落到代码用 SF Symbols。不用表情，不用彩色图标，列表行不再放图标方块。

## 可读性

关键组合的对比度（WCAG 2）。文字要求 4.5:1，图形记号 3:1；⚠ 表示不足。

| 组合 | 浅色 | 深色 |
|---|---|---|
| `label` 在 `canvas` 上 | 11.7 | 12.8 |
| `label` 在 `card` 上 | 10.6 | 11.4 |
| `label` 在 `raised` 上 | 12.7 | 9.8 |
| `label` 在 `selected` 上 | 13.2 | 7.2 |
| `label-muted` 在 `card` 上 | 6.3 | 7.7 |
| `label-secondary` 在 `card` 上 | 5.0 | 5.7 |
| `label-secondary` 在 `raised` 上 | 5.9 | 4.9 |
| `label-secondary` 在 `selected` 上 | 6.2 | 3.6 ⚠ |
| `on-brand` 在 `brand` 上 | 4.6 | 6.5 |
| `brand-ink` 在 `brand-tint` 上 | 4.7 | 7.7 |
| `brand-ink` 在 `card` 上 | 5.1 | 10.9 |
| `brand-tint-strong` 在 `brand-tint` 上 | 7.3 | 8.6 |
| `amber-ink` 在 `amber-tint` 上 | 5.3 | 7.1 |
| `amber-strong` 在 `amber-tint` 上 | 7.5 | 8.1 |
| `brand`（图形）在 `card` 上 | 3.7 | 5.8 |
| `brand-mark`（图形）在 `card` 上 | 2.8 ⚠ | 5.8 |
| `series-soft`（图形）在 `card` 上 | 1.6 ⚠ | 3.2 |
| `amber-mark`（图形）在 `card` 上 | 1.8 ⚠ | 6.3 |
| `amber-dot`（图形）在 `card` 上 | 2.6 ⚠ | 6.9 |
| `chart-rule`（图形）在 `card` 上 | 1.8 ⚠ | 2.5 ⚠ |

- 这套暖纸配色的浅色图形对比天生偏低。所以：被强调的系列永远用 `brand`；`series-soft`、`amber-mark` 画的柱和段必须直接标数值或在旁边逐项写文字；`brand-mark`、`amber-dot` 圆点永远跟着文字；参考线永远配一行说明。
- 绿色小字只用 `brand-ink`，不用 `brand`。设计稿里胶囊字的 `#4a6b48` 在 `brand-tint` 上是 4.48:1，这里定为 `#476846`（4.7:1），落地时以此为准。
- 选中芯片的 `selected` 和 `raised` 在浅色下差别很小，选中必须同时加中等字重，必要时加 1.5px `brand` 内描边。`selected` 上只写 `label`：深色下 `label-secondary` 在它上面只有 3.6:1。
- 动态字体放大时，主数字可以缩到 `amount-large`，行改竖排，金额不截断；读屏念完整数值，隐藏金额念“金额已隐藏”。

## SwiftUI 对照

代码（`DesignSystem.swift`）目前还是上一版的三套青绿主题。落地这一版时建议这样改：

| 本系统 | SwiftUI 落地 |
|---|---|
| 颜色 token | Asset Catalog 里每个 token 一个 Color Set（Any / Dark 两个值），`Color("canvas")` 或在 `YubaiTheme` 里收成静态属性；删掉三主题切换 |
| 旧 `jade` / `deep-jade` | `brand`；旧 `accent-text` → `brand-ink`；旧 `amber` → `amber-ink`（字）/ `amber-dot`（点）；旧 `card` 白 → `card` 暖纸色 |
| `num` 家族 | 打包 Geist（OFL），`.font(.custom("Geist-SemiBold", size: 48)).monospacedDigit()`；不打包时退回 `.system(design: .rounded).monospacedDigit()` |
| `serif` 家族 | 打包 Noto Serif SC 子集，或退回 `.system(design: .serif)` |
| `sans` 家族 | 系统字体（PingFang SC），设计稿里的 Noto Sans SC 是它的替身 |
| `Card` | `.background(Color("card"), in: RoundedRectangle(cornerRadius: 22))`，去掉旧版的 `card-stroke` 描边 |
| 图表 | Swift Charts：`LineMark(...).interpolationMethod(.stepEnd)` 画台阶线，`BarMark` 加 `.clipShape(UnevenRoundedRectangle(topLeading: 4, topTrailing: 4))` 画柱 |
| `TabBar` + 记一笔圆钮 | iOS 26 起用系统 `TabView`：三个 `Tab`（现在、洞察、我）加一个 `Tab(role: .search)` 位的分开圆钮当记一笔（选中它时不切页，改为弹出记一笔 sheet）；玻璃标签栏、流动选中块、按压透镜都由系统给，不自绘。圆钮用品牌色着色：`.tint(Color("brand"))`。每个标签页的滚动内容照旧让出底部空间，保证最后一行露在标签栏上方。推入页和 sheet 里隐藏标签栏 |
| “现在”一屏 | 根用 `VStack` 而不是长 `ScrollView`；图表高度用 `ViewThatFits` 在 150 / 96 / 收成一行之间选；只有动态字体超过 `.xxLarge` 才允许滚动 |
| `ButlerCard` | `card` 或 `amber-tint` 底的 `RoundedRectangle(cornerRadius: 22)`；右上角 `Menu("…")` 放“以后别提”“知道了”；“还有 N 件”是 `Button` 打开 sheet |
| `Toggle` | `Toggle(...).tint(Color("toggle-on"))` |
| 动效 token | 收成 `YubaiMotion`：`settle = .smooth(duration: 0.42)`、`snappy = .snappy(duration: 0.3)`、`lively = .spring(duration: 0.45, bounce: 0.25)`，时长曲线如 `.timingCurve(0.2, 0, 0, 1, duration: 0.24)`；`@Environment(\.accessibilityReduceMotion)` 为真时统一换成 `.easeInOut(duration: 0.16)` 并去掉位移和缩放 |
| 标签切换 | 自绘标签栏，底块 `matchedGeometryEffect`；页面 `.transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: ±12)), removal: .opacity))`；图标用 `KeyframeAnimator` |
| 从卡片放大进入 | iOS 18：来源加 `.matchedTransitionSource(id:in:)`，目标加 `.navigationTransition(.zoom(sourceID:in:))`；问余白 sheet 同样用 zoom |
| 数字逐位 | `.contentTransition(.numericText(value:))` 配 `withAnimation(YubaiMotion.snappy)` |
| 落笔与触感 | 水面一晃用 `KeyframeAnimator` 驱动横带 `offset(y:)`；触感 `.sensoryFeedback(.success, trigger:)`，撤销 `.impact(weight: .light)` |
| 图表生长 | Swift Charts 里用 `@State` 进度 0→1 乘到值上，`.onAppear` 只触发一次；环图切换保持 `SectorMark` 的数据身份，`withAnimation(YubaiMotion.settle)` |
| 新的一行、卡片收起 | `List` 插入动画；新行背景 `.animation(.easeOut(duration: 1.2))` 褪色；管家卡 `.transition(.scale(0.96).combined(with: .opacity))` |
| 助手思考 | `PhaseAnimator` 做水波上下起伏，拿到回答时移除 |

## 组件

- 骨架：`Page`、`NavigationBar`、`TabBar`、`Sheet`、`Card`、`SectionHeading`。
- 数字：`AmountLabel`、`HeroCard`、`Progress`。
- 图表：`ForecastChart`、`ColumnChart`、`BarList`、`Meter`、`TrendChart`、`Waterfall`、`Timeline`（怎么选见上面“图表”一节）。
- 内容：`EntryRow`、`Pill`、`InlineNote`、`EmptyState`、`Toast`、`DemoBanner`。
- 操作：`PrimaryButton`、`Segmented`、`Toggle`、`Stepper`、`EditorForm`、`Keypad`。
- 助手：`AssistantMark`、`AssistantCard`、`AskBar`、`ProposalCard`、`SendTrace`。
- 管家：`ButlerCard`。
- 品牌：`BrandMark`。
- 动效：`Motion`（演示卡，不是一个组件）。

分组和组件页里的分组一一对应。每张组件卡都按同一个顺序写：一句话说它是什么、使用者要提供什么、规则、不要做的事、源码状态；预览是按设计稿画的静态示意，可切换深浅色。

## 与代码的差距

- 组件没有可运行的 bundle，预览都是静态 HTML；SwiftUI 里还没有这一版的颜色、字体和自定义组件。
- 设计只画了 iPhone。Mac 侧栏、Mac 布局还没重做，旧版 `Sidebar` 和 `IconTile` 卡已移到 `archived/`。
- 字体是 Google Fonts 托管的 Geist、Noto Serif SC、Noto Sans SC、Fraunces，系统里没有字体文件。
- 应用图标：新的 `yubai-icon-1024.png` 还没放进仓库的 `AppIcon.appiconset`；assets/Logos 里的 `Icon-1024.png` 是现在装在手机上的旧图标。
