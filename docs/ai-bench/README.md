# 本地优先 AI · 台架评测

合成 / 脱敏样例，覆盖一期四类任务：用途归类、购买价值短答、洞察叙述（数字一致性）、搜索扩词。

## 夹具位置

- 权威 JSON：`Tests/YubaiCoreTests/Fixtures/ai-bench-samples.json`（随 `YubaiCoreTests` 复制进测试包）
- 本目录仅说明如何跑；改样本请改上述 JSON。

## 怎么跑

在仓库根目录：

```sh
swift test --filter AIBenchTests
```

也会打印各后端摘要行，例如：

```text
[MockLocalBackend/localDownloaded] 通过 …/…（…%）· 归类 … · 购买 … · 洞察 … · 搜索 …
[RulesOnlyBackend/rulesOnly] …
[MockCloudBackend/cloudOptional] …
```

`swift test`（全量）同样会执行该用例。

## 后端说明

| 后端 | 用途 |
|---|---|
| `RulesOnlyBackend` | 规则 / 模板 / 无扩词；购买短答会失败（预期） |
| `MockLocalBackend` | 本机模型未链 llama.cpp 时的启发式 mock |
| `MockCloudBackend` | 可选云 mock（默认产品开关关闭） |

真机 `llama.cpp` + GGUF **尚未**接入；`LocalDownloadedBackend` 为 protocol 占位，可注入 mock delegate。真机后续：接 XCFramework、用本夹具对比 0.5B / 1.5B。

## 硬约束抽检

- 购买短答：不得出现 `¥` + 数字或 `x.xx元` 形态金额改写
- 洞察：输出必须保留夹具中的 `protectedAmountTexts`
- 搜索：只匹配标题 / 备注 / 分类名，不改库
