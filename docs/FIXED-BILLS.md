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

Core 接口未在 Apple SDK 或界面分支验证，设计稿、原型及分发包尚未同步。

## 改安排（2026-11-04）

```swift
ChangeItem.updatePlan(Plan)
FixedFlows.edit(planID: UUID, in ledger: Ledger,
                now: Date = Date()) -> FixedFlowEdit?
FixedFlows.update(planID: UUID, title: String, amount: Int64, frequency: Frequency,
                  date: Date, accountID: UUID?, category: String, installments: Int?,
                  autoPay: Bool, estimated: Bool, in ledger: Ledger,
                  now: Date = Date()) throws -> ChangeSet
FixedFlows.categories(inflow: Bool, in ledger: Ledger) -> [String]
```

`FixedFlowEdit` 提供 `title`、`amount`、`frequency`、`date`、`accountID`、`category`、`installments`、`autoPay`、`estimated`、`inflow`、`stopped`。金额取当前估额；日期取最早未结清且未跳过的一期，全部结束则取今天和已有末期之后的下一期（一次性安排保留原日期）。分类复用账本当前可选分类表并按收支方向筛选；添加的默认分类保持。

`update` 返回来源「用户操作」、只有一项 `.updatePlan` 的变更；未改动抛 `FixedFlowEditError.noChanges`。应用按 ID 整体替换，校验存在的安排／可空账户、有效日期、去空白后非空的名字、正金额、方向不变，自动记必须有账户。历史预览写「修改安排「标题」」及各字段前后值；撤销复用 AppStore 应用前完整快照。

名字、分类、账户和开关直接修改，所有关联流水保持。调价只改变未结清期，定额部分付款按新金额减已记金额；已结清期冻结状态。修改估额后先用所填金额，之后新记的实际金额继续更新估额。自动记从关变开以今天为起点，不补记历史；持续开启保留原 `autoPaySince`。修改停掉的安排保留 `active`／`endDate`／`stoppedAt`，不自动恢复。

日期或频率相对 `edit` 发生变化时，日程从所选日期重建，重设 `monthlyDay`；原日程没有关联记录的期不再保留，有关联记录的期按原日期保留（部分付款也保留余款），与新日程同日只算一期。跳过日期只留在新日程仍存在的期。

**`installments` 表示总期数，nil 表示一直**，与添加页「共几期」一致。保留的历史期也占期数，按日期排序编号；例如共 6 期已付 2 期，改新起点后还生成 4 期，首个新期标第 3／6 期。总数不能移除已记过的期。`Plan.previousOccurrences`／`settledOccurrences`／`estimatedAmountSince` 保存排期历史、已结清状态和估额修改时点；旧 JSON 缺键分别解码为 `[]`／`[]`／nil，不改 schema。SyncVersions 的整对象比较自动覆盖这些字段；MemoryReflection 无 ChangeItem 穷举，AI proposal tools 保持原能力。

本轮新增中文仅为历史事实字段「修改安排「…」」「名字：…」「金额：…」「日期/频率：…」「账户：…」「分类：…」「共几期：…」「自动记：开／关」「金额会变：开／关」（空账户「未指定」、无期限「一直」），以及错误状态「没有改动。」「找不到要修改的安排。」「安排名字不能为空。」「安排金额必须大于零且在有效范围内。」「资金安排的日期无效。」「共几期必须大于零。」「自动记需要选择账户。」「不能把要付改为要收，或把要收改为要付。」「资金安排的账户不存在。」「共几期不能少于已保留的期数。」「共几期不能移除已经记过的期。」；无新增页面说明。产品 tracker／设计入口不在本轮写入范围，尚未同步；SwiftUI／Apple SDK 接线未验证。

验证：Swift 6.2.4／Linux，`swift build --target YubaiCore` 通过；`swift test` 最终运行 767 项，763 通过／4 项原有实网 opt-in 跳过／0 失败（120.687 秒）。新增编辑回归 29 项全部通过，原固定收付 50 项保持通过；编译缓存因默认目录只读而放在 `/tmp`。未改 SwiftUI，未提交或推送。

### 第二十九轮 SwiftUI 接线（2026-11-04）

`AppSheet.editPlan(UUID)` 打开 `FixedFlowEditor(planID:)`；本月／以后／已停掉及首页现有 Plan 行主体可改，rent 不可改。编辑由 `FixedFlows.edit` 预填、隐藏方向切换，`FixedFlows.update` 可成功构造才启用「好」，保存走 `store.apply(..., label: "修改安排")` 后关闭。添加／编辑复用分类 Menu，默认分类保持，添加切换方向时重置不适用分类。预览复用 Core 发生项，保留月末锚点与总期数约束。

底部「停掉以后的」与列表共用 `FixedFlowStopConfirmation` 和原 `FixedFlows.stop`；无待处理期直接确认，有待处理期先记账或跳过，成功后关闭编辑，未保存改动不提交；已停掉隐藏按钮。新增可见中文仅「改」「分类」「停掉以后的」。原行内按钮、左滑、contextMenu、恢复、旧期处理及快照撤销保持。

Linux 构建通过；全量 767 项，763 通过／4 原有跳过／0 失败（125.513 秒）。新增 7 项 UI 回归源码；Apple SDK 类型检查、Xcode 编译与 UI 实跑待 Mac。产品 tracker／设计入口已同步，本节补充并更新上方 Core 阶段的「UI 尚未接线／资源尚未同步」状态；外部画布与分发资源仍未同步。
