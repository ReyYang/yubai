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

相关 filter（无权重 CI 默认可绿）：

| Filter | 说明 |
|---|---|
| `AIBenchTests` | 规则 / mock 本地 / mock 云台架；权重占位拦截；`LocalDownloaded` 降级与 stub 推理 |
| `LocalGGUFTests` | 金额守卫、洞察护栏；**不含**实机 Metal（默认） |
| `LocalGGUFTests/testLiveLocalGGUFSmokeWhenExplicitlyEnabled` | 真 GGUF 冒烟；需环境变量 + 已下载权重 |
| `DeepSeekCloudTests` | 云端 mock / 守卫；实网另见下 |

## 后端说明

| 后端 | 用途 |
|---|---|
| `RulesOnlyBackend` | 规则 / 模板 / 无扩词；购买短答会失败（预期） |
| `MockLocalBackend` | 无权重时的启发式 mock（设置里「实验性 mock」） |
| `LocalDownloadedBackend` + `YubaiLocalLLM` | **主路径**：`mattt/llama.swift` → 官方 `llama.xcframework`（Metal）+ 本机 Qwen GGUF |
| `MockCloudBackend` | 可选云 mock（默认产品开关关闭） |
| `CloudOptionalBackend` + DeepSeek | 真实云端：读 `DEEPSEEK_API_KEY`；仅当 `cloudAIEnabled`；无密钥降级 |

### 默认模型选型

| 档 | Spec ID | 文件 | 来源 |
|---|---|---|---|
| **推荐（≈8 GB RAM）** | `qwen25-15b-q4` | `qwen2.5-1.5b-instruct-q4_k_m.gguf` | Hugging Face `Qwen/Qwen2.5-1.5B-Instruct-GGUF` |
| 覆盖（≈6 GB） | `qwen25-05b-q4` | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | Hugging Face `Qwen/Qwen2.5-0.5B-Instruct-GGUF` |

URL 与 SHA-256 写在 `ModelWeightCatalog`；**勿把 GGUF 提交进 git**。设置 →「本机模型权重」下载 / 校验 / 删除。

路由仍：本地已下载权重 → 可选云 → 可选 Apple FM → 规则。未下载或加载失败 → `RulesOnly` 降级。金额永不交模型修改。

## 可选：本机 GGUF 实网冒烟

1. 在 App 设置下载 0.5B（冒烟）或 1.5B（推荐档），或把文件放到 `ModelWeightStore` 目录并保证文件名与 catalog 一致。
2. 跑：

```sh
export YUBAI_RUN_LOCAL_GGUF_LIVE=1
swift test --filter LocalGGUFTests/testLiveLocalGGUFSmokeWhenExplicitlyEnabled
```

未设环境变量时该用例 `XCTSkip`，不失败。

**模拟器 / vphone：** 仅冒烟（能否加载与出字）；延迟、发热、jetsam **以真机为准**。

## 可选：DeepSeek 实网冒烟

默认 CI / 无密钥环境**不要**开实网用例。本机或 Secrets 已配密钥时：

```sh
export YUBAI_RUN_DEEPSEEK_LIVE=1
swift test --filter DeepSeekCloudTests/testLiveDeepSeekSmokeWhenExplicitlyEnabled
```

离线 / mock：

```sh
swift test --filter AIBenchTests
swift test --filter LocalGGUFTests
swift test --filter DeepSeekCloudTests
```

## SPM / XCFramework 取舍

- **采用：** `mattt/llama.swift`（exact `2.10549.0`）再导出官方 `llama-b10549-xcframework.zip`（Metal，iOS/macOS）。
- **原因：** 上游每次 release 出 XCFramework；该包提供可钉版本的 SPM 产品名，避免手搓 binaryTarget checksum。
- **备选：** 直接在 `Package.swift` 写 `.binaryTarget` 指向 ggml-org release（官方 docs/xcframework.md）；若 SPM 解析失败可改回该路径。
- App 目标经 `scripts/generate-project.py` 链接本地包产品 `YubaiCore` + `YubaiLocalLLM`。

## 硬约束抽检

- 购买短答：不得出现 `¥` + 数字或 `x.xx元` 形态金额改写（本机 / 云端都会剥离 / 拒绝）
- 洞察：输出必须保留夹具中的 `protectedAmountTexts`
- 搜索：只匹配标题 / 备注 / 分类名，不改库
