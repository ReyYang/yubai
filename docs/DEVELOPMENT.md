# 开发与验证

Xcode 26 / Apple SDK，Swift 5 语言模式；最低 iOS 18 / macOS 14。Linux 的 Core 构建与单元测试使用下方 SwiftPM 路径；Apple 应用与 UI 仍须在 Xcode 验证，历史 1.0 的验证报告不覆盖 2.0。

- `Sources/YubaiApp`：两项导航「现在／我」，底部常驻按钮「问余白」。首页复用 Finance 的待付款期次；依据打开精简记录详情。ProfileView 负责消费观、目标与底线。SettingsView 负责「我」的入口、导入记录、备份、恢复版本和指南。
- `Sources/YubaiCore`：schema 2（兼容 schema 1）、财务计算、导入解析与去重、ChangeSet、助手工具、管家与来信、加密备份和原子存储。默认资金观察期固定 90 天，底线取 `profile.floorAmount ?? 0`，日常预留自动估算。旧 horizonDays / emergencyReserve / dailyLiving / isSample 等字段保留解码与往返，不再控制 UI 或资金默认值。主动问答的指定日期预测通过函数参数传入范围。
- `Tests/YubaiCoreTests`：计算、兼容、整理、撤销、隐私和备份测试；SampleData.swift 仅属于测试目标。Fixtures 是合成资料；SPM 和 Xcode 原生测试目标使用同一份文件。
- `Tests/YubaiUITests`：五条离线流程：空账本开户、CSV 整理问答与整批撤销、克制卡片静音、数字问答到依据详情、消费原则持久化与备份入口。
- `scripts/generate-project.py`：生成 app、CoreTests 和 UITests 的工程引用与共享 scheme，包括签名配置和平台权限文件。源文件移动或删除后运行；生成结果纳入版本管理。
- `scripts/testflight.sh [ios|mac|all]`：付费团队配置完成后归档、上传 TestFlight；默认 ios。当前本人暂不加入付费计划，免费团队直接安装仍是测试路径。设置、构建号和安装见 [TESTFLIGHT.md](TESTFLIGHT.md)。
- `.design-meta/`、`.scratch/yubai-product/`：长期产品与设计资料。

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

Linux 的 `KeychainAPIKeyStorage` 只在进程内共享密钥，不写磁盘；iCloud 下载、协调与系统冲突版本不可用，显式请求 iCloud 仓库访问会报错。本机目录中的存储、附件、权限、恢复与版本选择逻辑仍运行真实测试。默认四个实网评测沿用原有 opt-in 跳过条件，离线测试仍使用真实 URLSession 与内存 HTTP stub。Linux 结果不代表 Keychain、iCloud、SwiftUI 或 Apple SDK 已验收；实际结果见 [验证记录](VALIDATION.md#linux-core-构建与单元测试2026-10-21)。

## GitHub Actions

两个工作流都会消耗 GitHub 额度，所以只能在 Actions 页手动运行，不随 PR 或推送自动跑；运行前先确认要花这笔额度。日常验证免费做：YubaiCore 用 `scripts/install-linux-swift.sh` 在本地或 Claude 容器里跑 `swift test`，App 构建与 UI 测试在自己的 Mac 上跑。

- `Linux Core`（`.github/workflows/linux-core.yml`）：在 `swift:6.2-noble` 容器里确认 Xcode 工程与生成器一致、编译 YubaiCore 并跑 `swift test`。
- `iOS`（`.github/workflows/ios.yml`）：用 macOS 26 runner 上最新的 Xcode 26，在 iPhone 模拟器上编译并跑 Core 与 UI 测试；UI 测试在关键页面和失败时截图，作为 `ios-screenshots` 产物上传，测试日志为 `ios-test-logs`。手动运行时勾选 `release_builds` 可加做不签名的 iOS／macOS Release 构建。私有仓库的 macOS 分钟按 10 倍计入额度。

每次写入先在副本验证，磁盘保存成功才更新内存。原文件、兼容字段和旧用户记录继续保留；删除界面不删除存档数据。`endPlan` 同时接受 plan / rent 的标识：开始后截断后续期次并保留到期欠款，开始前只停用。整批撤销恢复该批整理的差量；删除记录只能通过撤销或完整恢复版本找回。备份使用密码加密；旧未加密备份仍能读取。正式账本通过系统 API 取得 Application Support 下的 `app.yubai.personal`，目录权限 700、文件 600；Mac 直接安装默认非沙盒，沿用原位置，沙盒构建才使用应用容器内的 Application Support。首次安装沙盒版 Mac 应用（TestFlight）时，新容器初始为空，会显示空账本，旧非沙盒目录不会自动迁入。切换前必须先在旧 Mac 应用的「我 → 备份与同步」导出加密的完整备份，再在 TestFlight 构建中选择备份、输入密码并确认恢复；测试不得指向真实目录。

## 本机签名与版本

应用 Debug / Release 使用 `Config/iCloud.xcconfig → Config/Signing.xcconfig → #include? "Local.xcconfig"`；CoreTests / UITests 只以 Signing.xcconfig 为基础配置，获得同一团队而不继承应用 entitlement。Local.xcconfig 已被 Git 忽略，缺失时不会设置团队或影响免费 Personal Team 自动签名。需要本机持久配置时，从 [模板](../Config/Local.xcconfig.example)复制，保持自动签名；TestFlight 只能填付费团队的 10 位 `DEVELOPMENT_TEAM`。不要把自己的团队或签名材料写进工程、生成器或模板。

应用 `MARKETING_VERSION = 2.0.0`，日常 `CURRENT_PROJECT_VERSION = 1`；Info.plist 引用两项构建设置。上传脚本只在 archive 命令行以 UTC `YYYYMMDDHHMM` 覆盖 build number，导出时不让 Xcode 改号码。归档、源码副本及日志保留在已忽略的 `build/testflight/<构建号>/`；同一仓库同一分钟不重复运行，失败后下一分钟用新号码重试。跨机器上传也要错开分钟并保持时钟准确。没有配置付费团队前，不会开始归档或上传。

Mac Xcode 应用默认 `YUBAI_MAC_SANDBOX = NO`，免费 Personal Team 直接安装保持非沙盒。在 `Config/Local.xcconfig` 设为 `YES` 才增加 App Sandbox、网络客户端、用户选中文件读写和麦克风输入 entitlement。Mac App Store / TestFlight 要求沙盒，`scripts/testflight.sh` 对 `mac` 和 `all` 的 Mac archive 命令行强制传入 `YUBAI_MAC_SANDBOX=YES`，不改日常安装的本机配置。系统文件导入 / 恢复已有安全作用域，备份和原件导出使用系统 fileExporter，不保存长期外部 URL；沙盒构建可能拒绝容器外的自定义开发数据目录。`scripts/package-mac.sh` 从已构建的 Info.plist 读取版本，临时签名时显式保留已有沙盒 entitlement，有 iCloud 权限时仍保留原构建签名。它仅打包本地 DMG，不用于 TestFlight。

图标目录包含 iOS 通用 1024 图标和完整 Mac 尺寸。旧 iOS PNG 为 RGBA；`scripts/make-icon.swift` 已改为输出不含 alpha 的 RGB iOS PNG。TestFlight 脚本将 Sources、Tests、Config、工程和 Package.swift 复制到构建目录，在副本中重建图标并归档；既不运行工程生成器，也不改工作区的图标。开发者以后手工运行绘图脚本时，也会得到无 alpha 的 iOS 图标。当前无 Xcode，未运行上述脚本、工程生成器、shellcheck 或归档上传验证。


## 可选 iCloud 账本

Xcode app target 的 Debug / Release 共用 [Config/iCloud.xcconfig](../Config/iCloud.xcconfig)，默认 `YUBAI_ICLOUD = NO`、`YUBAI_MAC_SANDBOX = NO`；由上述 Signing.xcconfig 可选包含本机覆盖。默认 iOS 和 Mac 的 `CODE_SIGN_ENTITLEMENTS` 均为空，Swift 不定义 `YUBAI_ICLOUD`，免费 Personal Team 的本机构建不增加 iCloud 签名要求，Mac 也不会因更新切入沙盒。Swift Package 中的 app 默认也只使用本机；Core 的相同存储实现不依赖这个条件。

启用只改 **Config/Local.xcconfig** 中的这一行，不改共享默认值：

```xcconfig
YUBAI_ICLOUD = YES
```

该行同时把 Swift 条件展开为 `YUBAI_ICLOUD`。iOS 签名文件展开为 `Sources/YubaiApp/Yubai-iCloud.entitlements`。macOS 使用 `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = $(YUBAI_MAC_ENTITLEMENTS_$(YUBAI_MAC_SANDBOX)_$(YUBAI_ICLOUD))`，两个开关独立组合：

| `YUBAI_MAC_SANDBOX` | `YUBAI_ICLOUD` | macOS 权限文件（位于 `Sources/YubaiApp/`） |
|---|---|---|
| NO | NO | 无 |
| NO | YES | `Yubai-iCloud.entitlements`（仅 iCloud，无沙盒） |
| YES | NO | `Yubai-macOS.entitlements` |
| YES | YES | `Yubai-macOS-iCloud.entitlements` |

非沙盒 Mac 与 iOS 复用现有 iCloud-only 文件，工程和 `generate-project.py` 已引用全部三个权限文件。组合文件是两个基础文件的显式并集，任一权限变动须同步更新组合文件；测试目标不使用这些文件。

选择付费 Apple Developer Team，为 `app.yubai.personal` 在开发者门户或 Xcode 的 iCloud capability 中启用 iCloud Documents，并创建、关联 `iCloud.app.yubai.personal` 容器，刷新两端 provisioning profile。保持 entitlement 路径由 xcconfig 控制；不要在 target 的 Build Settings 另写一个非空覆盖值。Info.plist 仅登记容器元数据，不授予权限；容器文档不公开到文件浏览器。参考 [Apple 的 iCloud 配置](https://developer.apple.com/documentation/xcode/configuring-icloud-services)与[文档同步示例](https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment)。

安装后仍默认「仅本机」，在「我 → 备份与同步」主动选择 iCloud。容器探测在后台；关闭编译条件、未登录或容器不可用时继续使用 Application Support 中的本机副本。自定义数据目录和 UI 测试目录不连接 iCloud。启用两端使用同一个容器、Apple ID 和三入口界面：现在／我／问余白。`scripts/package-mac.sh` 对本机构建保持临时签名；检测到 iCloud entitlement 时保留构建签名，不以临时签名覆盖它。

存储与恢复：

- 旧布局：Application Support/app.yubai.personal/ledger.json，附件以 base64 内嵌。
- 新布局：本机同目录或容器内 `Documents/Yubai/ledger.json` 只含附件 id、名称、时间、字节数和 SHA-256；字节在旁边 `Attachments/<UUID>`。schema 仍为 2，载入兼容旧内嵌形状并自动拆分；先验证、保留原始文件字节，再替换元数据文件。
- 账本元数据上限 250 MiB，当前账本所引用的附件总量另限 250 MiB。附件 UUID 对应不可变字节，删除引用后暂保留文件，以免破坏尚未到达的冲突版本。未实现孤立附件清理；总磁盘占用因此可能超过当前附件上限。
- `Recovery/*.json` 与同名 `*.attachments/` 始终在本机 Application Support，保留最近 20 份完整版本；旧内嵌恢复记录继续能读。设备解锁设置、位置选择及待上传标记也留在本机；`.icloud-pending` 在保存修改前原子写入 Application Support，避免重启时丢失待上传状态。iCloud 账本中的设备解锁字段固定为关闭，接收同步时保留本机设置。
- 加密备份继续使用 v1 envelope，把附件字节一并打包，旧备份仍可恢复。JSON/base64 的包装读取上限单独放宽（由 `LedgerCodec.backupCapacity` 统一控制），不放宽账本或附件的逻辑上限。恢复附件缺失、校验失败时不替换现有账本。
- iCloud 文件列表先经 NSMetadataQuery 完成发现，避免把尚未下载的账本误判为空。读取前请求下载，显示「正在从 iCloud 读取…」；等待 30 秒后保留本机内容并允许重试。账本与附件分别使用 NSFileCoordinator。
- 每次修改先存本机，后台上传；待上传状态跨重启保留。没有待上传修改时接收远端账本；有修改、上传前指纹已变或存在 NSFileVersion 未解决版本时，显示更新时间、版本时间、设备名（如有）、有效记录数与最多三笔差异。用户选定后，先把未选中版本保存为「同步冲突时的另一版本」，再替换和标记这些已展示的冲突已解决。选择期间再更新会要求重新选择。
- 切到 iCloud 时若两处不同先选择，未选中版本记为「切换存储时的另一版本」。切回仅本机复制当前账本，包括未上传修改；不删除云端账本。退出 iCloud 后保留本机副本并回到仅本机，再次使用 iCloud 需要主动选择。恢复版本只在产生它的设备上可用。

`LedgerSyncTests` 使用两个临时目录和假的 `LedgerVersionSource`，覆盖附件迁移、校验／容量、独立恢复附件、完整加密备份往返、两种冲突选择及恢复顺序、失效选择与位置切换。现有 repository 初始化和 load/save/recover/Backup API 继续可用；原始文件断言按新的元数据布局调整。当前只执行静态语法、配置与工程生成核查，没有 Swift 工具链，未执行这些 XCTest。

在 Xcode 验证默认 NO 的 iOS / Mac 构建与测试后，再用上方单行启用 YES，重复两端构建。真实同步需两端有效签名、同一 Apple ID、iCloud Drive；核对首次空云端、已有不同账本、下载占位、离线待上传、前台远端更新、同时编辑冲突、选择期间再次更新、切回本机及退出登录。静态检查与临时目录测试不能代替这些系统行为的设备验证。
