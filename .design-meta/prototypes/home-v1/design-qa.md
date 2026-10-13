# Design QA — 首页体验稿 v1

final result: passed

范围：用户授权的一版独立交互设计，保留现有风格、降低首屏密度；不是旧截图逐像素复刻，也不是原生产品验收。

Source visual truth: evidence/existing-home.png，1290×2796，源为当前应用合成账本截图；明确采用用户的密度调整意见。
Implementation: evidence/home-screen.jpg，393×852；evidence/home-context.jpg 包含预览设备环境。
Browser viewport: 1400×1200；实际 phone screen DOM 测量393×852 CSS px，scale1。源图归一化为393×852，比较图 evidence/comparison.jpg。结束时已恢复浏览器默认视口。
State: 首页、浅色、示例账本、隐藏金额关闭、未来30天。旧图金额9200/90天，新图7500/30天来自不同合成场景，是明确的内容差异。

Full-view comparison: evidence/comparison.jpg。保留灰白底、深青绿主金额区域、圆角、金额等宽和五项底部导航；有意收起现金/信用/预留三项指标、资金走势图及流水，主卡缩短，为一个近期安排和快捷操作留空间。标题、卡片、首屏动作没有裁切或导航遮挡。
Focused comparison: 金额和按钮在393宽截图中可直接辨识；修正后的详情面板见 evidence/calculation-after.jpg，购买咨询见 evidence/advice.jpg（该图摄于键盘返回修正前，主要记录结果内容）。

Required fidelity surfaces:
- Typography: 系统中文字体、标题32、金额40、正文14–15、辅助文字10–12；当前稿有意降低辅助信息层级，用户尚未确认最终字号。
- Spacing: 22px侧边距；主卡26px圆角，约230px高；一项近期安排，操作独立成组；导航保持固定且内容预留底部空间。
- Colors: 深青绿、灰白底与低饱和辅助色；核心色已读取实际DOM背景rgb(7,95,81)。浏览器设备外观/原生SF字体与图标的区别属于平台呈现差异。
- Assets: 无照片/插画需求；标准Radix图标代替SF Symbols用于网页体验，未用自制图形替代图片；设备框与键盘来自受保护模板。
- Copy: 示例标识明确；冲突保留原金额并暂不导入；导入和资金预览注明模拟；页面不声称真实交易已保存。

Comparison history:
1. P2: 关闭按钮用负top定位，受sheet内容区域裁切。改成面板内部可见按钮；实际点击关闭、截图确认可见，后续状态已回归。
2. P2: 输入后背景滚动位置可能被键盘运行时改变。关闭面板时重建滚动区域，验证输入后关闭回到可见首页标题，DOM top275.5，相对设备屏101.5。
3. Post-fix: evidence/calculation-after.jpg、home-screen.jpg；没有待处理P0/P1/P2。

Interactions actually tested via in-app browser:
- 金额依据打开/关闭、隐藏/显示、30→90天切换。
- 空记录提交报错；支出28.50保存后示例7500→7471.50；撤销回到7500。
- 导入选择门槛、账户对应门槛、120=112+6+2预览、冲突查看并返回、保存结果、返回首页。
- 第一笔用途补充后待处理数量2→1，第二笔仍保留；未冒充金额重算。
- 购买耳机800后示例余地6700，键盘关闭且结果可见。
- 账本搜索咖啡；安排与房租详情；洞察、我的、重置；输入后关闭回到首页。
- 浏览器error/warn日志为空。构建通过；28个模板受保护文件完整性通过。

Follow-up polish: 待用户实际体验后决定辅助字号、记一笔与整理的主次、是否保留首页问句、底部导航信息架构。Pixel、动态字体、深色及完整财务逻辑不在本轮已验证范围。
