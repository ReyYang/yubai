# 收支分类与自动整理：四款记账产品的官方资料核查

核查日期：2026-09-15。范围：Actual Budget、YNAB、MoneyWiz、钱迹的官方帮助文档。此文提供决策证据，不代表余白已经采用这些方案，也没有对真实账单或 AI 模型进行准确率测试。

## 结论

少量稳定分类、自动分类、记住纠正、批量修改都有现成产品依据。钱迹明确已有基于大模型的 iOS 自动记账匹配；其他三款的所查文档主要描述规则、商户历史和银行分类。它们的输入路径不同，不能据此断言大模型能在首次文件导入的 4,000 笔记录上达到某个准确率。

余白可以把“默认自动完成，用户无需逐笔审批”作为产品行为；无法细分的普通消费可以归入其他。另一个需要保留的区分是：账户入账不一定是收入、账户出账不一定是消费。退款、自己的账户转移、还款等需保留各自含义，避免汇总重复。下方列出事实与候选设计，二者分开。

## 1. Actual Budget

### 官方事实

- **默认分类及层次**：官方入门页把 Food、Bills、Bills (Flexible)、Savings、General 称为初始基础支出 categories；本次未安装核实默认制品，不把这五项当成完整叶子分类清单。该页明确举出的组内具体支出分类有 Groceries（买菜食品）、Eating Out（外出就餐）、Household Items（日用品）、Rent（房租）、Gifts（礼物）；收入可按来源建类，也可有利息、股息类别。类别可组织成组。这些是官方例子，不是必须采用的统一列表。[Starting Fresh](https://actualbudget.org/docs/getting-started/starting-fresh/)
- **自动分类**：导入或同步后应用规则；条件可含原始商户文字、账户、日期、备注、金额等。程序从用户分类行为生成、更新商户分类规则；规则可以编辑，也可以应用到已有匹配交易。这是公开描述的规则学习机制，文档没有把它表述为大模型识别。[Rules](https://actualbudget.org/docs/budgeting/rules/)
- **账户转账**：双边记录关联。两个预算内账户之间不需要支出类别；预算内外之间的转账规则不同，需要预算内一侧的分类。[Transfers](https://actualbudget.org/docs/transactions/transfers/)
- **批量修改**：筛选交易后可批量修改分类、备注、账户等；官方提醒该操作对拆分交易可能出现非预期行为。[Bulk Actions](https://actualbudget.org/docs/transactions/bulk-editing/)

### 可借鉴与限制

可借鉴“少量初始分类”和“纠正一次，之后复用”。不必照搬其把储蓄分配、债务和日常消费放在预算类别中的结构。本次未核实低置信度阈值、自动归其他策略，以及退款、借款全流程；不能补成其已有功能。

## 2. YNAB

### 官方事实

- **分类层次**：Category Group 包含 Categories；类别不能再嵌套类别。信用卡还款组由信用卡账户带出，具有特殊规则。[Adding, Removing, and Customizing Categories](https://support.ynab.com/en_us/adding-removing-and-customizing-categories-a-guide-HJFO5j909)
- **收入与用途**：一般收入进入 Ready to Assign；来源可以用工资、利息、礼金等概括称呼区分。若入账是在抵消已记录支出，如退款或朋友补偿，应回到原支出类别。它并非给每种收入建立一个普通消费类别。[How to Add Income and Other Inflows](https://support.ynab.com/en_us/how-to-add-income-and-other-inflows-H1ZNjfZJi)
- **自动分类与未分类**：首次遇到收付款方通常需要设置类别，支票账户的导入入账有默认例外；后续使用商户默认类别，最近三笔中两笔改成另一类别时更新默认。支持批量分类。允许暂时无类别，但会持续提醒补齐；这与余白“非关键未知可以留在其他”的期望不同。[Categorizing Transactions](https://support.ynab.com/en_us/categorizing-transactions-a-guide-HyRl60sks)
- **信用卡还款**：作为付款账户流出、信用卡账户流入的一笔转账处理；双边是预期记录，并非重复消费。首次识别可能需要纠正，之后会记住。[Credit Card Payments](https://support.ynab.com/en_us/credit-card-payments-a-guide-r1_506Q1j)
- **信用额度负债**：官方有 Line of Credit 专门账户说明，部分按信用卡账户运作；不能直接据此声称支持中国花呗、白条文件格式。[Line of Credit Accounts](https://support.ynab.com/en_us/line-of-credit-accounts-a-guide-S10LHsqkl)

### 可借鉴与限制

可借鉴收入、消费、还款的分离，以及分类纠正后的后续复用。首次新商户仍需人工分类和未分类提醒，不适合直接照搬为余白的大批导入体验。未找到本次分类指南给出通用大模型推断、置信度机制或中国平台适配证据。

## 3. MoneyWiz

### 官方事实

- **分类层次**：收入、支出分别有类别表；支持父类别和子类别，首次提供默认类别。官方举例：在不同超市购物，收款方不同但都可属于 groceries。本次没有获取完整默认分类清单。[How to manage transaction categories?](https://help.wiz.money/en/articles/4810637-how-to-manage-transaction-categories)
- **银行同步自动分类**：可开启自动分类和自动创建类别；关闭自动建类后，无法适配现有类别的交易保持未分类。[Automatic transaction categorization](https://help.wiz.money/en/articles/4476399-how-to-configure-online-banking-automatic-transaction-categorization)
- **文件导入是另一条路径**：若文件已有类别，映射到本地类别；若没有，可按收付款方映射类别，也可保持 Not Linked。映射会保存供下次复用。不能把银行同步自动分类直接推断为任何文件首次导入都能智能分类。[Import a CSV, QIF, OFX, QFX or MT940 file](https://help.wiz.money/en/articles/4440666-how-to-import-a-csv-qif-ofx-qfx-or-mt940-file-from-bank-or-other-application)
- **批量纠正与学习**：银行同步交易修改分类时，可选择将相同收付款方和原分类组合一起修改；下次导入时记住该选择。通用批量编辑只允许相同交易类型，排除转账、余额调整及退款等特殊类型。[Change a category in multiple transactions](https://help.wiz.money/en/articles/4440631-how-to-change-a-category-in-multiple-online-banking-transactions)、[Bulk edit](https://help.wiz.money/en/articles/4455735-how-to-bulk-edit-transactions)
- **退款和报销**：退款针对某一原支出，报销可针对一个类别的多笔支出；支持将已导入的收入转换为退款并关联原消费。[Refund or reimburse transactions](https://help.wiz.money/en/articles/4440659-how-to-refund-or-reimburse-transactions)
- **转账报表**：报表同时纳入转账双边账户时，普通转账不会作为该报表的收支出现；跨币种及贷款账户存在特例，不能一概视为普通消费。[Show transfers in reports](https://help.wiz.money/en/articles/5646118-how-to-show-transfers-in-reports)

### 可借鉴与限制

可借鉴收入/支出类别分开、允许不自动扩增类别、批量纠正后记住选择。文件导入映射仍有人工配置，不能把该流程当作余白低参与导入的完成方案。未核实它使用何种 AI 模型，也没有低置信度量化证据。

## 4. 钱迹

### 官方事实

- **明确的用途与类型分离**：模板给出“三餐”“交通”作为分类例子，支持一、二级分类，空分类默认为“其它”；账单类型另列收入、支出、报销、转账、信用卡还款。转账和还款使用第二账户字段。这些是模板规则和例子，并非完整默认类别表。[模板导入](https://docs.qianjiapp.com/other/import_templete.html)
- **已有大模型自动匹配**：使用金额、商户、时间等账单文本，以及用户分类列表、资产列表、账单类型进行匹配；网络或超时失败时退回本地逻辑。文档明确限制为 iOS/iPad 快捷指令自动记账，新建时匹配，不修改已保存历史账单。因此可以作为“AI 把文本对应到已有类别”的直接先例，不能用作批量文件归类已经验证的证据。[自动记账 AI](https://docs.qianjiapp.com/auto/qianji_auto_ai.html)
- **批量分类修正**：支持多选账单后修改分类；官方提醒批量操作不能撤销、不会自动更新资产余额。该限制不应照搬为余白的目标行为。[批量操作](https://docs.qianjiapp.com/batch_operation.html)

### 可借鉴与限制

钱迹是本次最直接的中文分类和 AI 匹配先例。其 AI 文档给出的准确率宣称没有提供样本与评估方法，本研究不将其当作独立验证。本次没有获得完整默认收支分类表，也未验证日常多文件增量导入是否调用该 AI 功能。

## 5. 对余白的候选设计推断

以下是结合用户需求与上述资料提出的候选，不是竞品事实，也不是已确认决策：

1. **少量稳定用途分类**：支出可从餐饮、居住、交通、购物与日用、健康、学习与工具、娱乐旅行、人情家庭、利息与费用、其他开始；收入可从工资劳务、礼金与补助、利息分红、其他开始。具体名字和数量可继续收敛。
2. **在内部区分交易性质与用途**：转账、还款、退款、借入借出、投资买卖等先记录其性质，再按需要关联用途。不给用户再增加一套必须逐笔填写的表单。基金赎回不能把全部回款都视为收益；贷款到账也不能直接当作工资类可消费收入。这是拟议的记账语义，尚需结合余白账户模型明确。
3. **默认完成整批归类**：优先复用账单已有的有效信息及已确认规则，再由 AI 处理需要理解语义的记录。用户看到汇总，可以直接结束导入；不设置逐笔批准的必经流程。金额保留来源值，修正仍由用户完成。
4. **其他作为可用结果**：普通消费无法细分时进入其他；如果连“收入、借款、退款、自己账户转移”都分不清，可以先保留待识别性质，并只在会影响重要判断时集中询问。不因无法细分消费用途阻断导入，也不把未知性质误说成确定收入。
5. **以组为单位补充**：相似描述的多笔记录一起提问、一起改分类；一次反馈尽量解决一组，不让 4,000 笔导入变成 4,000 个问题。用户仍能修正个别例外。
6. **隐私不要求真实姓名**：分类依赖用途、商品/商户线索及必要上下文；个人姓名留本地。有用的用途备注若包含姓名，应先去除身份信息再使用。缺少交易用途时，AI 能力不能凭空恢复账单中不存在的事实。

## 6. 证据边界与待验证项

- 已实际检索/打开官方网页；YNAB 的部分页面 open 返回空正文，采用同一官方 URL 的搜索索引正文。MoneyWiz 分类管理与文件导入页面搜索可读，但直接打开一度返回 404，相关事实来自官方域名的索引正文，应在实施前再检查页面可达性与版本。
- 本次是功能文档核查，没有安装软件、导入文件、上传用户数据或评测模型。
- 没有验证首次 4,000 笔归类的正确率、运行时间、成本、需要提问数量，也没有验证微信/支付宝/银行卡文件的现有字段完整度。
- “默认不逐笔复核”是余白可以采用的交互决定；“AI 可以识别多少、误判主要在哪”仍需以后用实际样本观察，两者不冲突。
