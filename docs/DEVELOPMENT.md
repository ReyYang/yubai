# 构建与维护

构建需要 Xcode / Apple SDK；此前验证工具链为 Xcode 26.4.1、Swift 6.3.1、Apple Silicon。项目最低 iOS 18 / macOS 14。2026-10-20 的修改环境没有 Swift 工具链，本次仅完成静态检查，未构建或运行测试。

## 结构

- `Sources/YubaiCore`：模型、整数金额、财务计算、来源导入、批量操作、加密备份和原子持久化。
- `Sources/YubaiApp`：SwiftUI 页面、Apple Vision OCR、云端智能调用入口、系统文件交互和设备认证。
- `Sources/CArchive`：系统 zlib 与 CommonCrypto 的小型桥接，不联网下载库。
- `Tests/YubaiCoreTests`：计算与存档 contract；Fixtures 为明确合成资料（含 `ai-bench-samples.json`）。
- `Tests/YubaiUITests`：iPhone 原生交互测试，使用独立 UUID 账本；测试夹具入口仅编译进 Debug simulator。
- `docs/ai-bench/`：DeepSeek 云端 AI 台架说明；跑 `swift test --filter AIBenchTests`。
- `scripts/generate-project.py`：从 app 源文件生成 Xcode 工程；增加 app 源文件后运行。
- `.design-meta` / `.scratch/yubai-product`：长期产品和设计资料。
- AI：`YubaiCore.CloudBackend` 调用 `DeepSeekClient`；`IntelligenceRuntime.backend(for:)` 返回可选后端。仅在用户开启云端且配置可用时调用 DeepSeek，其他情况使用本机已有结果。台架与测试说明见 `docs/ai-bench/README.md`。

## 本地验证

在项目根目录执行：

```sh
swift test
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test
```

测试只使用合成账本。具体 simulator 名称以本机列表为准；本轮测试 ID 记录于验证报告。模拟器运行结果不能代替真机签名、系统认证或真实网络验证。

Mac Release 与 iPhone 未签名归档：

```sh
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/ReleaseMac \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/ReleaseiOS \
  -archivePath build/iPhone/Yubai.xcarchive \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO archive
```

## DeepSeek 配置

设置中的「使用云端智能（DeepSeek）」是唯一 AI 开关，默认关闭。在应用内保存的密钥仅写入本机钥匙串（generic password，service `app.yubai.deepseek`），配置优先读取钥匙串，缺少时回退到启动进程环境的 `DEEPSEEK_API_KEY`；Xcode 开发时可在 Scheme → Run → Arguments → Environment Variables 添加。可选 `DEEPSEEK_BASE_URL` 指定 API 根地址，`DEEPSEEK_MODEL` 覆盖模型，默认值见 `DeepSeekConfiguration`。密钥不写入账本、备份或日志。设置内可保存/替换/删除密钥、测试连接、查看最近50条脱敏发送记录，以及打开临时问答页。连接测试是用户主动发起的无账本请求，不依赖云端开关；财务问答和既有AI功能需要开关开启。

未开启或没有配置时不创建后端。离线导入保留本机解析的金额、日期、账户与明确性质，分类留作「待整理」，批次持久标记待整理；下次应用活跃且云端可用时补整理，也可在结果页点「现在整理」。未知表头只发送表头和最多五行脱敏样本，模型返回列索引；代码校验后解析原始数值。整理每次发送最多 80 行及限量关联证据，返回分类、性质、用途、关联与周期证据；金额、主账户、原始日期不变，周期计划的数值也由证据计算。疑问最多五个，回答通过 ChangeSet 写入。购买、洞察、搜索继续保留本机计算和失败回退。

共享助手与只读工具接口见 [ASSISTANT.md](ASSISTANT.md)。默认测试用测试专用网络响应桩，不访问 DeepSeek。显式实网冒烟和合成夹具评测的环境变量见 [云端台架说明](ai-bench/README.md)。

## 数据与兼容性

当前写入 `schema = 2`，仍读取 schema 1。旧 `rules` 字段忽略，之后不再编码；导入待整理标记、结果、问题和撤销差量都是可选字段，旧文件缺失时为 nil。旧偏好的云端开关只有在原云端开关为真且原智能总开关没有关闭时才保留为真；缺少原云端开关按关闭、缺少原总开关按开启迁移。其他旧模型偏好被忽略，重新编码仅写当前偏好键。正式 Mac 数据位于用户 Application Support 中的 `app.yubai.personal/ledger.json`；iOS 位于 app 私有 Library/Application Support 下。账本目录权限 700、文件 600，iOS 文件使用系统数据保护；本机文件不单独密码加密。密码加密只作用于导出的备份。

每次事务先复制并验证账本，磁盘写入成功才替换内存；保存前保留最近 20 个完整版本。损坏文件不会变成空账本，恢复会保留被替换文件。目录位置可用 `--data-directory /absolute/path` 指定；测试和预览不得指向真实数据目录。

现有 ChangeSet 校验禁止修改金额、主账户和原始日期；分类仅接受账本分类和别名，关联仍须通过财务关系校验。无效整理项报告后跳过。新批次的撤销差量只保留被改变的旧记录及新增计划、卡片标识；没有嵌套保存完整账本。旧批次没有撤销差量时沿用移入回收站。

导入容量为单文件 50 MB、256 列、10 万行、100 万个单元格。工作簿解析会处理共享字符串、内联文本、1900/1904 日期系统，不执行公式或宏；公式单元格只读取文件内已有缓存值。旧二进制 `.xls`、PDF、多币种及任意银行私有格式未支持，应先转换或使用模板，不能通过改扩展名伪装格式。

模型和存档格式变更应先定义迁移与恢复方案。整个文件重写及 20 份完整历史适用于个人账本规模，接近 250 MB 编码容量时会拒绝继续写入并提示；无需通过删除原文件绕过。
