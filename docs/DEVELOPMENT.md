# 开发与验证

Xcode 26 / Apple SDK，Swift 5 语言模式；最低 iOS 18 / macOS 14。当前环境没有 Swift 工具链，未运行编译或 XCTest；历史 1.0 的验证报告不覆盖 2.0。

- `Sources/YubaiApp`：两项导航「现在／我」，底部常驻按钮「问余白」。首页复用 Finance 的待付款期次；依据打开精简记录详情。ProfileView 负责消费观、目标与底线。SettingsView 负责「我」的入口、导入记录、备份、恢复版本和指南。
- `Sources/YubaiCore`：schema 2（兼容 schema 1）、财务计算、导入解析与去重、ChangeSet、助手工具、管家与来信、加密备份和原子存储。默认资金观察期固定 90 天，底线取 `profile.floorAmount ?? 0`，日常预留自动估算。旧 horizonDays / emergencyReserve / dailyLiving / isSample 等字段保留解码与往返，不再控制 UI 或资金默认值。主动问答的指定日期预测通过函数参数传入范围。
- `Tests/YubaiCoreTests`：计算、兼容、整理、撤销、隐私和备份测试；SampleData.swift 仅属于测试目标。Fixtures 是合成资料；SPM 和 Xcode 原生测试目标使用同一份文件。
- `Tests/YubaiUITests`：五条离线流程：空账本开户、CSV 整理问答与整批撤销、克制卡片静音、数字问答到依据详情、消费原则持久化与备份入口。
- `scripts/generate-project.py`：生成 app、CoreTests 和 UITests 的工程引用与共享 scheme。源文件移动或删除后运行；生成结果纳入版本管理。
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

每次写入先在副本验证，磁盘保存成功才更新内存。原文件、兼容字段和旧用户记录继续保留；删除界面不删除存档数据。`endPlan` 同时接受 plan / rent 的标识：开始后截断后续期次并保留到期欠款，开始前只停用。整批撤销恢复该批整理的差量；删除记录只能通过撤销或完整恢复版本找回。备份使用密码加密；旧未加密备份仍能读取。正式账本在 Application Support 的 `app.yubai.personal`，目录权限 700、文件 600；测试不得指向真实目录。


## 可选 iCloud 账本

Xcode app target 的 Debug / Release 共用 [Config/iCloud.xcconfig](../Config/iCloud.xcconfig)。默认 `YUBAI_ICLOUD = NO`，展开后 `CODE_SIGN_ENTITLEMENTS` 为空，Swift 不定义 `YUBAI_ICLOUD`，免费 Personal Team 的本机构建不增加 iCloud 签名要求。Swift Package 中的 app 默认也只使用本机；Core 的相同存储实现不依赖这个条件。

启用只改配置文件中的这一行：

```xcconfig
YUBAI_ICLOUD = YES
```

该行同时把 Swift 条件展开为 `YUBAI_ICLOUD`，把签名文件展开为 `Sources/YubaiApp/Yubai-iCloud.entitlements`。选择付费 Apple Developer Team，为 `app.yubai.personal` 在开发者门户或 Xcode 的 iCloud capability 中启用 iCloud Documents，并创建、关联 `iCloud.app.yubai.personal` 容器，刷新两端 provisioning profile。保持 entitlement 路径由 xcconfig 控制；不要在 target 的 Build Settings 另写一个非空覆盖值。Info.plist 仅登记容器元数据，不授予权限；容器文档不公开到文件浏览器。参考 [Apple 的 iCloud 配置](https://developer.apple.com/documentation/xcode/configuring-icloud-services)与[文档同步示例](https://developer.apple.com/documentation/uikit/synchronizing-documents-in-the-icloud-environment)。

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
