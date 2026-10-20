# DeepSeek 云端 AI · 台架评测

仅保留 DeepSeek 云端路径。合成样例覆盖用途归类、购买价值短答、洞察叙述（金额原文保护）和搜索扩词，供后续云端评测继续使用。

## 夹具与运行器

- 权威 JSON：`Tests/YubaiCoreTests/Fixtures/ai-bench-samples.json`，随测试包复制；共 52 例（归类 16、购买 12、洞察 12、搜索 12）。
- `AIBenchRunner.run(fixture:backend:)` 接收 `CloudBackend`，输出各任务通过数及总通过率；请求失败计为该例失败。
- 评测针对带护栏的后端结果：洞察缺失受保护金额时会返回本机模板，因此洞察通过数不等于模型原始回答的通过数。
- 购买短答检查指定关键词并排除模型金额；搜索用扩词匹配标题、备注、分类，保持账本不变。当前关键词断言是初步检查，尚不能代表真实体验质量。

## 离线检查

在有 Swift / Apple SDK 的环境中，从仓库根目录执行：

```sh
swift test --filter AIBenchTests
swift test --filter DeepSeekCloudTests
swift test --filter StorageTests
```

默认不发送网络请求。测试专用 `CloudTestStub` 用 `URLProtocol` 截获请求，验证真实云端后端的请求字段、提示词边界、金额保护、搜索解析及台架计分；没有产品 mock 开关。实网测试缺少明确启用变量或密钥时跳过。

## 云端配置与实网检查

应用设置中的「使用云端智能（DeepSeek）」默认关闭。仅在开关开启且存在 DeepSeek 配置时创建后端。暂时从启动进程的环境读取密钥；应用内密钥输入留待后续步骤。Xcode 启动应用时在 Scheme → Run → Arguments → Environment Variables 设置：

```sh
export DEEPSEEK_API_KEY='your-key'
# 可选覆盖 API 根地址和模型；默认值见 DeepSeekConfiguration。
export DEEPSEEK_BASE_URL='https://api.deepseek.com'
export DEEPSEEK_MODEL='deepseek-flash'
```

密钥不写入账本或诊断摘要。运行测试时不需要打开应用偏好开关，以下显式启用变量表示允许对合成夹具发起云端请求。

只做一次搜索扩词冒烟：

```sh
YUBAI_RUN_DEEPSEEK_LIVE=1 swift test --filter DeepSeekCloudTests/testLiveDeepSeekSmokeWhenExplicitlyEnabled
```

运行全部 52 例（会产生多次 API 请求及相应费用）：

```sh
YUBAI_RUN_DEEPSEEK_EVAL=1 swift test --filter AIBenchTests/testLiveCloudFixtureWhenExplicitlyEnabled
```

摘要示例：`[DeepSeek(api.deepseek.com/deepseek-flash)] 通过 …/52（…%）· 归类 … · 购买 … · 洞察 … · 搜索 …`。实网测试打印分项结果，不把当前通过率当作已确定的产品验收阈值。

## 产品回退与边界

关闭云端或缺少配置时，运行时返回无 AI；离线或请求失败由调用方保留规则归类、洞察模板、普通子串搜索和购买资金判断，不附加模型反思。金额、账户和资金性质始终由本机逻辑处理；模型仅提供用途分类或文字与搜索词，洞察必须保留受保护金额。提示词明确把用户文字视为数据，忽略其中命令。

2026-10-20 本次修改环境没有 Swift 工具链，仅完成静态检查，未运行上述测试或实网请求。
