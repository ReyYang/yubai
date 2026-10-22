# 固定收付 Core（2026-10-22）

本轮按 owner 提供的已批准规则实现 Core，供另一分支的 SwiftUI 调用；没有接入 App 启动或前台事件，也没有修改页面、工程或分发资源。产品 tracker 与设计入口因本轮写入范围限制尚未同步，本说明保留此次采用规则、API 与验证边界。

`Finance.nextPayday(in:now:) -> (date: Date, title: String)?` 从活跃、重复、收入性质且流入的安排中寻找未来 90 天最早的下一个发生日。今天不算，已收款不改变日程；结束日期和总期数照常生效。`Funds` 新增 `horizonEnd: Date`、`horizonDays: Int`、`payday: Date?`、`paydayTitle: String?`。还能花的已知付款含发薪当天与所有历史未付项，日常开销按距发薪日的自然日数预留。没有发薪安排时沿用 `days`（默认 90）；即使请求更短的预测图，发薪预留窗口也独立计算。

`Funds.occurrences`、`points` 和 `expectedIncome` 仍按传入 `days` 展开，缺口卡继续从完整预测路径取数。`get_funds` 的 `horizon_days` 使用实际预留窗口，有发薪日时附 `payday`（yyyy-MM-dd）和 `payday_title`。购买事实使用「发工资前已知付款」或具体截止日期。

`Plan` 新增 `autoPay: Bool = false`、`autoPaySince: Date?`、`installments: Int?`、`estimated: Bool = false`，旧账本缺键时正常解码。分期从 `dueDate` 算第一期；月末仍从原始日期推进。估额预留采用最近一笔活跃关联记录的金额，以记录日期排序，同日再按记下时刻排序；没有实际金额时用安排金额。估额本期有任意关联入账就结清，定额保留部分付款的差额。

```swift
FixedFlows.settle(planID: UUID, occurrence: Date, amount: Int64? = nil,
                  accountID: UUID? = nil, in ledger: Ledger, now: Date = Date()) throws -> ChangeSet
FixedFlows.suggestions(amount: Int64, nature: Nature, purpose: String, day: Date,
                       accountID: UUID?, in ledger: Ledger, now: Date = Date()) -> [Occurrence]
FixedFlows.autoSettle(in ledger: Ledger, now: Date = Date()) -> ChangeSet?
FixedFlows.month(containing now: Date, in ledger: Ledger) -> FixedFlowMonth
ManualBookkeeping.change(amount: Int64, nature: Nature, accountID: UUID,
                         otherAccountID: UUID? = nil, day: Date, purpose: String,
                         category: String, link: (planID: UUID, occurrence: Date)? = nil,
                         now: Date = Date()) throws -> ChangeSet
```

结清返回一项 `.addEntry`，金额默认本期剩余数，账户依次取显式账户、安排账户、默认账户；来源为「用户操作」。过去一期记录在到期日中午，今天和提前结清记录在当前时刻。无账户、已结清、无效期数或关联与性质／指定账户不符时报中文错误。`EntryDraft` 的 `planID`／`occurrence` 可同时传入构造器，旧草稿缺键仍正常解码；同一条记录不能再关联另一期。支持多笔部分付款。

建议仅返回计划的未结清发生项，不自动保存。日期差不超过三天，同额可直接匹配；相差不超过 10% 需要名称重叠，估额只需名称重叠。比较名称时忽略空白和大小写；指定账户不符的安排不候选。排序依次比较同额、名称重叠、日期接近程度，最多三项。

自动扣款要求安排已开启自动扣款且设置了有效账户，记录启用日起至今天的所有未付项，来源「自动扣款」。`autoPaySince == nil` 时从安排开始日计算。一次 ChangeSet 保存全部账目，应用后重跑返回 nil；没有调用就不会自动发生。撤销沿用 AppStore 应用 ChangeSet 前的完整账本快照，Core 无需新增独立撤销操作。

`FixedFlowMonth` 提供 `date`（月初）、`occurrences: [FixedFlowOccurrence]`、`remainingOutflow`、`remainingInflow`。每行包含 `id`、`title`、`date`、`state: FixedFlowState`（`paid`／`due`／`upcoming`）、`amount`、`planID`／`rentID`、`inflow`、`autoPay`、`installment: (index: Int, total: Int)?` 和 `estimated`。本期结清时状态为 `paid`，金额为关联记录合计；定额部分付款仍为 `due`／`upcoming`，金额显示剩余数；没有关联记录时今天及之前为 `due`，之后为 `upcoming`。定额部分付款的剩余差额仍计入剩余合计。房租付款和应收分摊分别列出，本轮只读。`FixedFlowArrangement` 新增 `paidCount: Int` 与 `total: Int?`；定额分期完全付清一期才计数。`canEnd` 及从今天结束安排的 `.endPlan` 规则保持。

验证结果见 [VALIDATION.md](VALIDATION.md)。Core 接口未在 Apple SDK 或界面分支验证，设计稿、原型及分发包尚未同步。
