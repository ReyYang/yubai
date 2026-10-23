# vphone 标签栏对比截图 · 2026-10-22

机器：yubai-e2e-20261004（iOS 26.6.2）。截图时客体为浅色模式、默认文字大小、粗体文本关闭，余白「外观」设为浅色；截完已恢复原设置（深色、文字大一档、粗体开、余白外观深色）。

- `fix-*`：fix/tabbar-gesture-regression（2be7adb）
- `main-*`：main（146e379）

| 文件 | 内容 |
|---|---|
| fix-01-now / main-01-now | 现在 |
| fix-02-insights / main-02-insights | 洞察 |
| fix-03-entries / main-03-entries | 账目（顶部） |
| fix-04-me / main-04-me | 我 |
| fix-05-entries-bottom | 账目滚到底 |
| fix-06-me-fixedflows | 我 → 固定收付 |
| fix-07-add-entry | 点 ＋ 打开记一笔 |
| fix-08-entries-row-swipe | 账目行左滑出现删除 |
| fix-09-entries-two-rows-open | 两行同时露出删除（展开后不自动收回） |

注：修复版测试中管家建议卡片被左滑收起（知道了），所以 main-01-now 里没有这张卡片。

## 复测 fix2：fix/tabbar-gesture-regression（0caf4e2）

| 文件 | 内容 |
|---|---|
| fix2-01-one-row-open | 账目行左滑露出删除（同一时间只有一行） |
| fix2-02-tap-row-edit | 点行打开「改一笔」 |
| fix2-03-butler-card | 为测试经 我的消费观 临时添加「想克制的」后出现的管家卡片（测完已删除这些领域） |

## 复测 fix3：fix/tabbar-gesture-regression（bd8b1b2，标签栏下移 14pt）

| 文件 | 内容 |
|---|---|
| fix3-01-now | 现在（标签栏下移后的位置） |
| fix3-02-entries-top | 账目顶部 |
| fix3-03-entries-bottom | 账目滚到底，最后一行仍在标签栏上方 |

## 左滑按钮外观：fix/row-delete-shape（ba977eb，深色、vphone 当前字号）

| 文件 | 内容 |
|---|---|
| del2-01-entries-first-row | 账目第一行左滑露出删除 |
| del2-02-entries-middle-row | 账目中间行左滑露出删除 |
| del2-03-fixedflow-stop | 固定收付左滑露出停掉 |

## 固定收付第十四轮：fix/fixed-bills-clarity（31cc440，浅色、默认字号）

测试用界面新增了「测试过期」「测试今天付」「测试还没到」三条安排，测完都已停掉。

| 文件 | 内容 |
|---|---|
| bills-01-list | 主列表（含过期、今天、还没到、已付、要收过期、已停掉） |
| bills-02-after-pay | 「测试过期」点付了之后 |
| bills-03-stop-dialog | 停掉「测试今天付」时的弹窗 |
| bills-04-after-stop | 停掉后进入已停掉区 |
| bills-05-all-stopped | 测试安排全部停掉后的列表 |

## 洞察分类与记录详情推入：fix/insights-push-inset（0838156，vphone 当前外观：深色、文字大一档、粗体）

文件名后缀为点击/手势开始后的毫秒数。

| 文件 | 内容 |
|---|---|
| push-01-category-* | 洞察点「其他支出」进入分类明细 |
| push-02-category-back-* | 点返回 |
| push-03-edge-cancel-* | 左边缘侧滑约一半后取消 |
| push-04-after-cancel-3s | 取消侧滑 3 秒后：标签栏仍留在分类明细页 |
| push-05-record-* | 分类明细里点记录：弹出「改一笔」表单（不是推入） |
| push-06-record-detail-* | 管家卡片明细里点记录推入「记录详情」 |
| push-07-record-edge-cancel-* | 记录详情左边缘侧滑一半后取消 |
| push-08-record-back-* | 记录详情点返回 |
