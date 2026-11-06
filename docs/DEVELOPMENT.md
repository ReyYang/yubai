# 开发与验证

Xcode 26 / Apple SDK，Swift 5 语言模式；最低 iOS 18 / macOS 14。Linux 的 Core 构建与单元测试使用下方 SwiftPM 路径；Apple 应用与 UI 仍须在 Xcode 验证，历史 1.0 的验证报告不覆盖 2.0。

- `Sources/YubaiApp`：两项导航「现在／我」，底部常驻按钮「问余白」。首页复用 Finance 的待付款期次；依据打开精简记录详情。ProfileView 负责消费观、储蓄目标与「始终留着」目标。SettingsView 负责「我」的入口、导入记录、备份、恢复版本和指南。
- `Sources/YubaiCore`：schema 2（兼容 schema 1）、财务计算、导入解析与去重、ChangeSet、助手工具、管家与来信、加密备份和原子存储。默认资金观察期固定 90 天，「始终留着」目标取 `profile.floorAmount`，不扣减还能花或预测余额，日常预留自动估算。旧 horizonDays / emergencyReserve / dailyLiving / isSample 等字段保留解码与往返，不再控制 UI 或资金默认值。主动问答的指定日期预测通过函数参数传入范围。
- `Tests/YubaiCoreTests`：计算、兼容、整理、撤销、隐私和备份测试；SampleData.swift 仅属于测试目标。Fixtures 是合成资料；SPM 和 Xcode 原生测试目标使用同一份文件。
- `Tests/YubaiUITests`：五条离线流程：空账本开户、CSV 整理问答与整批撤销、克制卡片静音、数字问答到依据详情、消费原则持久化与备份入口。
- `scripts/generate-project.py`：生成 app、CoreTests 和 UITests 的工程引用与共享 scheme，包括签名配置和平台权限文件。源文件移动或删除后运行；生成结果纳入版本管理。
- `scripts/testflight.sh [ios|mac|all]`：付费团队配置完成后归档、上传 TestFlight；默认 ios。当前本人暂不加入付费计划，免费团队直接安装仍是测试路径。设置、构建号和安装见 [TESTFLIGHT.md](TESTFLIGHT.md)。

在 Apple 开发环境从仓库根目录运行：

```sh
python3 scripts/generate-project.py
swift test
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Release \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

模拟器名称按本机列表调整。UI 测试同时传入 `--test-ledger <UUID>` 与 `YUBAI_UI_TEST_SCRIPT=empty|import|restrain|ask|profile`，只读写缓存目录中的独立账本，脚本传输仍调用真实助手工具／整理器。导入测试以 `YUBAI_UI_STATEMENT` 的 base64 CSV 注入文件，经过与文件打开相同的预览和保存路径；这五条测试不覆盖系统文件选择器。两个条件缺一则不启用夹具。该入口仅编译进 Debug simulator，设备与 Release 不包含脚本传输，也不需要向 Keychain 写假密钥。

正常云端配置位于「我 → 智能与隐私」，密钥进入 Keychain，开发启动可回退 `DEEPSEEK_API_KEY`。`DEEPSEEK_BASE_URL` 和 `DEEPSEEK_MODEL` 可覆盖配置。测试默认为离线；实网评测须显式设置 `YUBAI_LIVE_EVAL=1`，见 [台架说明](ai-bench/README.md)。共享助手与外发边界见 [ASSISTANT.md](ASSISTANT.md)。

## 始终留着是目标（2026-10-27）

owner 明确「始终留着」属于消费观，是希望在资金观察期末留住的金额，未达到很正常。`Finance.funds()` 的口径为：

```text
available = cash - debt - committed - goals - living - uncertainInflow
baseline = cash - debt - goals - uncertainInflow
conservative = baseline - 截至预测日已知付款 - 此前日常开销
```

`Funds.emergency` 保留为 `profile.floorAmount ?? 0` 的目标值；`floorRoom` 在目标未设置时为 nil，否则为 `available - floorAmount`。正值是期末仍留住目标时还能多花的金额，负值是距目标的缺口；明确设为 0 与未设置区分。资金工具与购买工具的 affordability 返回可空的 `floor_target`／`floor_room`（当前购买前差额），替代 `emergency`／`floor_already_reserved`；消费观工具保留 `floor_amount`。

购买后 `after = available - amount`：小于 0 仅允许 skip；否则低于已设目标允许 wait／skip；达到目标时继续核对原有克制次数／金额规则。优先级为实际缺口、目标缺口、克制规则；目标与克制规则同为 wait／skip 时保留较早的目标理由。付款缺口卡只看保守路径小于 0，已设目标仅作背景事实；每周来信沿用不扣目标的 Finance 结果。AI 平静陈述目标与差额，不责备。

App 本轮只从首页 HeroCard 的 reserved 合计移除目标、删除计算页「始终留着」扣减行；不新增行或视图，首页目标新行等待设计稿。新增／改动可见中文模板为「在存钱与日常开销 X」「想始终留着 X，按现在能留住」「想始终留着 X，还差 Y」「买了以后离始终留着的 X 还差 Y。」；均为金额事实。原稿、Figma、截图与分发包未同步。

本轮使用 Swift 6.2.4，改动 Swift 文件的 19 项条件语法解析、夹具 JSON、新增链接与 `git diff --check` 通过。`swift test` 将缓存改至可写的 `/tmp` 后，因 `swift-crypto`／`swift-asn1` 未缓存、代理不可连接及 GitHub DNS 不可用，停在依赖下载；未构建／运行单测。Apple SDK 编译与 UI 实跑仍待 Mac。

## Linux Core 构建与测试

Ubuntu 24.04 / Swift 6.2.4，从仓库根目录运行。云端容器访问不了 swift.org 时，先用 `scripts/install-linux-swift.sh` 从 Docker Hub 官方 `swift:6.2-noble` 镜像取出工具链（约 1.2 GB，默认装到 `/opt/swift-rootfs`，已安装则跳过）：

```sh
scripts/install-linux-swift.sh
export PATH=/opt/swift-rootfs/usr/bin:$PATH
swift build --target YubaiCore
swift build
swift test
```

`CArchive`、`YubaiCore` 和 `YubaiCoreTests` 可在 Linux 构建；包清单在 Linux 排除 `YubaiApp` 与 `YubaiDesktop`，不编译 SwiftUI 源码。首次运行需从 GitHub 获取依赖，版本由 `Package.resolved` 固定。受限容器若无法写默认模块缓存，可在上述命令前设置：

```sh
export CLANG_MODULE_CACHE_PATH=/tmp/yubai-clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/yubai-swiftpm-module-cache
export XDG_CACHE_HOME=/tmp/yubai-swift-cache
```

Linux 的 SHA256、AES-GCM 与 PBKDF2 使用仅限 Linux 的 swift-crypto 产品；Apple 继续使用 CryptoKit 与 CommonCrypto。备份 v1 的 PBKDF2-HMAC-SHA256、32 字节密钥、16 字节盐、导出 210,000 轮（读取接受 100,000–1,000,000 轮）、nonce／密文／tag 布局与 `yubai-backup-v1` AAD 保持一致。兼容向量由独立的 Python hashlib／AESGCM 实现生成，覆盖含 NUL 的 UTF-8 密码与轮数边界。

Linux 的 `KeychainAPIKeyStorage` 只在进程内共享密钥，不写磁盘；iCloud 下载、协调与系统冲突版本不可用，显式请求 iCloud 仓库访问会报错。本机目录中的存储、附件、权限、恢复与版本选择逻辑仍运行真实测试。默认四个实网评测沿用原有 opt-in 跳过条件，离线测试仍使用真实 URLSession 与内存 HTTP stub。

## GitHub Actions

两个工作流都会消耗 GitHub 额度，所以只能在 Actions 页手动运行，不随 PR 或推送自动跑；运行前先确认要花这笔额度。日常验证免费做：YubaiCore 用 `scripts/install-linux-swift.sh` 在本地或 Claude 容器里跑 `swift test`，App 构建与 UI 测试在自己的 Mac 上跑。

- `Linux Core`（`.github/workflows/linux-core.yml`）：在 `swift:6.2-noble` 容器里确认 Xcode 工程与生成器一致、编译 YubaiCore 并跑 `swift test`。
- `iOS`（`.github/workflows/ios.yml`）：用 macOS 26 runner 上最新的 Xcode 26，在 iPhone 模拟器上编译并跑 Core 与 UI 测试；UI 测试在关键页面和失败时截图，作为 `ios-screenshots` 产物上传，测试日志为 `ios-test-logs`。手动运行时勾选 `release_builds` 可加做不签名的 iOS／macOS Release 构建。私有仓库的 macOS 分钟按 10 倍计入额度。

每次写入先在副本验证，磁盘保存成功才更新内存。原文件、兼容字段和旧用户记录继续保留；删除界面不删除存档数据。`endPlan` 同时接受 plan / rent 的标识：开始后截断后续期次并保留到期欠款，开始前只停用。整批撤销恢复该批整理的差量；删除记录只能通过撤销或完整恢复版本找回。备份使用密码加密；旧未加密备份仍能读取。正式账本通过系统 API 取得 Application Support 下的 `app.yubai.personal`，目录权限 700、文件 600；Mac 直接安装默认非沙盒，沿用原位置，沙盒构建才使用应用容器内的 Application Support。首次安装沙盒版 Mac 应用（TestFlight）时，新容器初始为空，会显示空账本，旧非沙盒目录不会自动迁入。切换前必须先在旧 Mac 应用的「我 → 备份与同步」导出加密的完整备份，再在 TestFlight 构建中选择备份、输入密码并确认恢复；测试不得指向真实目录。

## 本机签名与版本

应用 Debug / Release 使用 `Config/iCloud.xcconfig`，Widget 使用 `Config/Widgets.xcconfig`；两者均先包含 `AppGroup.xcconfig` 的共享默认，再由 `Signing.xcconfig → #include? "Local.xcconfig"` 加载本机覆盖，因此 Local 中的 `YUBAI_APP_GROUP = NO` 对两个 target 均生效。CoreTests / UITests 只以 Signing.xcconfig 为基础配置，获得同一团队而不继承应用 entitlement／编译条件。Local.xcconfig 已被 Git 忽略，缺失时不会设置团队；免费 Personal Team 在 Xcode 为 App 与 Widget 两 target 选择同一团队并保持自动签名。需要本机持久配置时，从 [模板](../Config/Local.xcconfig.example)复制；TestFlight 只能填付费团队的 10 位 `DEVELOPMENT_TEAM`。不要把自己的团队或签名材料写进工程、生成器或模板。

应用 `MARKETING_VERSION = 2.0.0`，日常 `CURRENT_PROJECT_VERSION = 1`；Info.plist 引用两项构建设置。上传脚本只在 archive 命令行以 UTC `YYYYMMDDHHMM` 覆盖 build number，导出时不让 Xcode 改号码。归档、源码副本及日志保留在已忽略的 `build/testflight/<构建号>/`；同一仓库同一分钟不重复运行，失败后下一分钟用新号码重试。跨机器上传也要错开分钟并保持时钟准确。没有配置付费团队前，不会开始归档或上传。

Mac Xcode 应用默认 `YUBAI_MAC_SANDBOX = NO`，免费 Personal Team 直接安装保持非沙盒。在 `Config/Local.xcconfig` 设为 `YES` 才增加 App Sandbox、网络客户端、用户选中文件读写和麦克风输入 entitlement。Mac App Store / TestFlight 要求沙盒，`scripts/testflight.sh` 对 `mac` 和 `all` 的 Mac archive 命令行强制传入 `YUBAI_MAC_SANDBOX=YES`，不改日常安装的本机配置。系统文件导入 / 恢复已有安全作用域，备份和原件导出使用系统 fileExporter，不保存长期外部 URL；沙盒构建可能拒绝容器外的自定义开发数据目录。`scripts/package-mac.sh` 从已构建的 Info.plist 读取版本，临时签名时显式保留已有沙盒 entitlement，有 iCloud 权限时仍保留原构建签名。它仅打包本地 DMG，不用于 TestFlight。

图标目录包含 iOS 通用 1024 图标和完整 Mac 尺寸。旧 iOS PNG 为 RGBA；`scripts/make-icon.swift` 已改为输出不含 alpha 的 RGB iOS PNG。TestFlight 脚本将 Sources、Tests、Config、工程和 Package.swift 复制到构建目录，在副本中重建图标并归档；既不运行工程生成器，也不改工作区的图标。开发者以后手工运行绘图脚本时，也会得到无 alpha 的 iOS 图标。当前无 Xcode，未运行上述脚本、工程生成器、shellcheck 或归档上传验证。


## 可选 iCloud 账本

Xcode app target 的 Debug / Release 共用 [Config/iCloud.xcconfig](../Config/iCloud.xcconfig)，默认 `YUBAI_ICLOUD = NO`、`YUBAI_MAC_SANDBOX = NO`，App Group 独立默认 YES；由上述 Signing.xcconfig 可选包含本机覆盖。默认 iOS 使用 `Sources/YubaiApp/Yubai-AppGroup.entitlements`，Mac 的 `CODE_SIGN_ENTITLEMENTS` 仍为空；Swift 不定义 `YUBAI_ICLOUD`，本机构建不增加 iCloud 签名要求，Mac 也不会因更新切入沙盒或启用 App Group。Swift Package 中的 app 默认也只使用本机；Core 的相同存储实现不依赖这个条件。

启用只改 **Config/Local.xcconfig** 中的这一行，不改共享默认值：

```xcconfig
YUBAI_ICLOUD = YES
```

该行同时把 Swift 条件展开为 `YUBAI_ICLOUD`。App Group 保持默认 YES 时，iOS 签名文件为 `Sources/YubaiApp/Yubai-iCloud-AppGroup.entitlements`；App Group 改回 NO 时为 `Yubai-iCloud.entitlements`。macOS 使用 `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = $(YUBAI_MAC_ENTITLEMENTS_$(YUBAI_MAC_SANDBOX)_$(YUBAI_ICLOUD))`，两个开关独立组合：

| `YUBAI_MAC_SANDBOX` | `YUBAI_ICLOUD` | macOS 权限文件（位于 `Sources/YubaiApp/`） |
|---|---|---|
| NO | NO | 无 |
| NO | YES | `Yubai-iCloud.entitlements`（仅 iCloud，无沙盒） |
| YES | NO | `Yubai-macOS.entitlements` |
| YES | YES | `Yubai-macOS-iCloud.entitlements` |

非沙盒 Mac 与关闭 App Group 的 iOS 复用现有 iCloud-only 文件，工程和 `generate-project.py` 已引用全部权限文件。组合文件是对应基础文件的显式并集，任一权限变动须同步更新组合文件；测试目标不使用这些文件。

选择付费 Apple Developer Team，为 `app.yubai.personal` 在开发者门户或 Xcode 的 iCloud capability 中启用 iCloud Documents，并创建、关联 `iCloud.app.yubai.personal` 容器，刷新两端 provisioning profile。保持 entitlement 路径由 xcconfig 控制；不要在 target 的 Build Settings 另写一个非空覆盖值。Info.plist 仅登记容器元数据，不授予权限；容器文档不公开到文件浏览器。参考 [Apple 的 iCloud 配置](https://developer.apple.com/documentation/xcode/configuring-icloud-services)与[文档同步示例](https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment)。

安装后仍默认「仅本机」，在「我 → 备份与同步」主动选择 iCloud。容器探测在后台；关闭编译条件、未登录或容器不可用时继续使用 Application Support 中的本机副本。自定义数据目录和 UI 测试目录不连接 iCloud。启用两端使用同一个容器、Apple ID 和三入口界面：现在／我／问余白。`scripts/package-mac.sh` 对本机构建保持临时签名；检测到 iCloud entitlement 时保留构建签名，不以临时签名覆盖它。

存储与恢复：

- 旧布局：Application Support/app.yubai.personal/ledger.json，附件以 base64 内嵌。
- 新布局：本机同目录或容器内 `Documents/Yubai/ledger.json` 只含附件 id、名称、时间、字节数和 SHA-256；字节在旁边 `Attachments/<UUID>`。schema 仍为 2，载入兼容旧内嵌形状并自动拆分。Ledger 只驻留附件元数据；需要字节时由 `LedgerRepository.attachmentData(id)` 读取并检查大小／SHA-256。`save`／`restoreBackup` 返回已释放附件字节的账本，App 采用该返回值。
- 账本元数据及单个附件仍限 250 MiB，取消附件总量 250 MiB 限制。附件 UUID 对应不可变字节；已有文件先比大小，复用已知校验信息，必要时流式计算 SHA-256，保存不重读所有 payload。保存清理未被任何账目（包括软删除）、导入批次（含撤销快照）或待确认修改所涉及账目引用的附件；选定冲突版本之前先保留另一版本的 payload。Apple 写入前检查可用卷空间，写满错误转为「手机空间不足，本次修改未保存。」；临时文件原子安装，沿用 0600／0700 与文件保护。
- 新版本为本机 `Recovery/*.json.gz`，只含账本元数据，附件共享一份 `Recovery/Payloads/<UUID>`。整个目录最多 4 MiB／8 份；同类自动操作以第一份为锚，10 分钟内合并，启动也修剪旧历史。预算内优先保留首尾，中间按时间均匀选；最新版本、最后完整可读回退与当前／保留版本必需附件优先于预算，引用无法读取或删除失败时允许超额。手动导入、恢复前、删除批次等各留一份后再参与预算修剪；剪除后仅清理所有剩余恢复版本及当前账本均不引用的共享 payload。旧 `.json`、同名 `.attachments/` 和内嵌恢复记录兼容读取，旧 sidecar 随版本删除。schema 1 无内嵌附件的原始 JSON 仍按原字节压缩保留；有内嵌附件时先拆分为元数据。Apple 排除 Recovery 的整机备份。设备解锁设置、位置选择及待上传标记也留在本机；`.icloud-pending` 在保存修改前原子写入 Application Support，避免重启时丢失待上传状态。iCloud 账本中的设备解锁字段固定为关闭，接收同步时保留本机设置。云端会话禁用 URLCache，启动只清本 App 命名空间的旧 `Cache.db*`／`fsCachedData`；[存储测量与边界](STORAGE-RECOVERY-CACHE.md)。
- 加密备份继续使用 v1 envelope，把附件字节一并打包，旧备份仍可恢复。JSON/base64 包装上限按最大附件个数与单个附件上限推导（`LedgerCodec.backupCapacity`），不再用旧总量限制阻止大账本导出。导出时临时读取全部字节，完成后不写回驻留 Ledger；完整备份的内存峰值仍随附件总量增长。恢复附件缺失、校验失败时不替换现有账本。
- iCloud 文件列表先经 NSMetadataQuery 完成发现，避免把尚未下载的账本误判为空。读取前请求下载，显示「正在从 iCloud 读取…」；等待 30 秒后保留本机内容并允许重试。账本与附件分别使用 NSFileCoordinator。
- 每次修改先存本机，后台上传；待上传状态跨重启保留。没有待上传修改时接收远端账本；有修改、上传前指纹已变或存在 NSFileVersion 未解决版本时，显示更新时间、版本时间、设备名（如有）、有效记录数与最多三笔差异。用户选定后，先把未选中版本保存为「同步冲突时的另一版本」，再替换和标记这些已展示的冲突已解决。选择期间再更新会要求重新选择。
- 切到 iCloud 时若两处不同先选择，未选中版本记为「切换存储时的另一版本」。切回仅本机复制当前账本，包括未上传修改；不删除云端账本。退出 iCloud 后保留本机副本并回到仅本机，再次使用 iCloud 需要主动选择。恢复版本只在产生它的设备上可用。

`LedgerSyncTests` 使用两个临时目录和假的 `LedgerVersionSource`，覆盖附件迁移、校验／容量、独立恢复附件、完整加密备份往返、两种冲突选择及恢复顺序、失效选择与位置切换。现有 repository 初始化和 load/save/recover/Backup API 继续可用；测试改为显式按需读取附件、解压恢复 JSON 后断言，容量与损坏断言遵循新语义。问余白截图保存前经 `ImageCompression`：ImageIO 缩长边至 2048、HEIC／JPEG 质量 0.8，仅更小时替换；Linux 或失败保留原件。

在 Xcode 验证默认 NO 的 iOS / Mac 构建与测试后，再用上方单行启用 YES，重复两端构建。真实同步需两端有效签名、同一 Apple ID、iCloud Drive；核对首次空云端、已有不同账本、下载占位、离线待上传、前台远端更新、同时编辑冲突、选择期间再次更新、切回本机及退出登录。静态检查与临时目录测试不能代替这些系统行为的设备验证。


## 快速记账与 App Group

第九轮新增 YubaiWidgets（iOS 26）并在 App 的 iOS 构建嵌入；Mac 通过平台条件排除。共享快照使用独立的 `Config/AppGroup.xcconfig`，默认 `YUBAI_APP_GROUP = YES`；[Apple 官方 iOS 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios)列出免费 Apple Developer 也支持 App Groups，iCloud 开关保持独立。首次在 Xcode 为 Yubai／YubaiWidgets 都选同一 Personal Team，核对 Signing & Capabilities 自动注册并关联 `group.app.yubai.personal`；失败时在 `Config/Local.xcconfig` 设 `YUBAI_APP_GROUP = NO` 后重新构建，仅显示入口。配置组合、容器不可用时的按钮回退与设备验证见[快速记账说明](QUICK-CAPTURE.md#app-group默认开启)。工程生成器同步包含源文件和扩展 target，没有另外写入 App Group 默认值；不要只手动修改生成结果。

## 第八轮存储空间（2026-10-21）

从「我 → 备份与恢复」下一行进入「存储空间」。入口在 `SettingsView.swift`，主页与两个 sheet 在 `StorageView.swift`，复用现有 DesignSystem、系统导航／sheet、恢复版本页和加密备份页，无新增动效或依赖。

`LedgerRepository.storageUsage()` 返回三类实际文件字节数、恢复份数与最早时间：账本目录其余文件为账本，`Attachments` 为截图和账单原件，`Recovery`（含共享 `Payloads`、旧 sidecar）为恢复历史。App 查询本机副本，后台只读文件长度，不载入所有附件；显示按十进制 KB／MB／GB，一位小数。

`StorageAttachments.classify`／`oldScreenshots`／`removeOldScreenshots` 是纯函数，截图以账目引用且非任何导入原件判定，包括软删除记录的引用，撤销批次仍保留原件；日期按 Calendar 的3／6／12个月回退，早于边界才删除。`deleteOldScreenshots` 走正常 save，留一份「删除旧截图」恢复版本，主目录 payload 删除失败则回滚元数据、历史与相关附件；账目及金额保持，账目和批次撤销快照中的已删截图引用置空。云端 payload 沿原有下载／协调规则；App 先改本机并按既有 pending／上传链同步。

`clearRecoveryHistory` 在账本锁与恢复锁下清空恢复目录，包括共享 payload；不触发另一次账本保存。`eraseAllLocalData` 仅清空 `localDirectory`，即使从 cloud repository 调用也不触碰云端目录。破坏性操作先建私有回滚快照，同卷文件用硬链接，失败则复制；清理失败恢复快照，回滚本身失败会保留副本并给出中文路径。App 等待同步操作结束，先改回本机位置，成功后清除位置／pending状态和内存撤销，换全新 Ledger 回 onboarding；钥匙串密钥不删。

可选 `Preferences.lastBackupAt` 兼容旧存档 nil，只在系统文件导出回调成功后保存，取消／加密失败不写入。抹掉 sheet 的「之后记了」按手动 recordedAt 或导入批次 importedAt 计算，不给旧记录补造时间；没有备份记录显示「还没备份过」。

新增11项 `StorageManagementTests`；UI 增加 `openStorage`／`storagePage`／`storageHeadline` 等标识与 `testStorageEntryAndOverviewOpenFromMe`。在 Mac 重新生成工程后执行 iOS／Mac 编译与 UITests；当前 AppFlowTests 共9条，另有3条 MotionStateTests。
