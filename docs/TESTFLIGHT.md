# 用 TestFlight 安装余白测试版

**目前先不付费：继续用免费 Personal Team 在 Xcode 直接安装。** Mac 直接安装默认 `YUBAI_MAC_SANDBOX = NO`，保持非沙盒及原有账本位置。TestFlight 的归档、上传入口已经准备好；仓库没有选择开发团队，没有创建开发者资源或上传构建。不填写 `Config/Local.xcconfig` 的 `DEVELOPMENT_TEAM`，脚本就会用中文提示退出，连归档也不会开始。免费安装方法见 [iPhone 安装指南](INSTALL-iPhone.md)。

将来加入付费 Apple Developer Program 后，TestFlight 是推荐的测试版安装方式，iPhone 和 Mac 都可以从 TestFlight 更新。它需要有效的付费团队，免费 Personal Team 无法使用。准备使用时再按下面操作，不需要现在购买。[Apple 会员能力说明](https://developer.apple.com/support/compare-memberships/)

## 第一次启用

1. 本人加入 [Apple Developer Program](https://developer.apple.com/programs/enroll/)，等待会员生效，并在开发者网站和 App Store Connect 接受账户要求的协议。
2. 在 Mac 安装完整 **Xcode 26**，首次打开完成许可和 iOS / macOS 平台组件安装。在 Xcode → Settings → Accounts 登录自己的 Apple ID，确认列表里出现付费团队；Settings → Locations → Command Line Tools 选择这个 Xcode。打开 `Yubai.xcodeproj`，scheme 选 **Yubai**；在应用和两个测试 target 的 Signing & Capabilities 中确认所用团队，保持 **Automatically manage signing**。团队的长期配置放在下面的本机文件中，避免把 Xcode 写入工程的个人 Team ID 提交到仓库。
3. 在该团队登记明确的 App ID：`app.yubai.personal`，名称可填「余白」。Xcode 自动签名可以登记，也可在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) 手工创建。iOS 和原生 macOS 使用同一个 Bundle ID。如果提示标识已被其他团队占用，先核对原 Personal Team、付费团队和标识归属，不要随意换 ID，以免数据迁移到另一个应用。暂时保持 iCloud 关闭；要启用时再按 [开发说明](DEVELOPMENT.md#可选-icloud-账本)配置容器。
4. 打开 [App Store Connect](https://appstoreconnect.apple.com/) → Apps → ＋ → New App。填写：

   | 字段 | 内容 |
   |---|---|
   | 平台 | iOS；需要原生 Mac 测试时也选 macOS，或稍后在同一个 app record 添加 macOS 平台 |
   | 名称 | 余白；若被占用，尝试「余白个人账本」，仍被占用则选择另一个可用名称 |
   | 主要语言 | 简体中文 |
   | Bundle ID | `app.yubai.personal`，选择刚登记的标识 |
   | SKU | `yubai-personal-2`，作为自己账户内唯一的内部编号 |
   | 用户访问 | 自己能访问即可 |

   这是建立测试应用记录，不会自动公开上架。[Apple：添加应用记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)、[添加平台](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/)
5. 在余白 → **TestFlight → Internal Testing（内部测试）** 新建「本人」组，把自己的 App Store Connect 用户加入。本人通常是 Account Holder；内部测试者须是有此应用访问权的 App Store Connect 用户。可以开启自动分发新构建，也可以处理完成后手动添加。[Apple：添加内部测试者](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
6. 在仓库根目录复制配置：

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   编辑新文件，取消 `DEVELOPMENT_TEAM` 行的注释，并替换为付费团队 **10 位 Team ID**（在 Apple 开发者账户 Membership details 查看；不是 Apple ID 邮箱或证书名称）：

   ```xcconfig
   DEVELOPMENT_TEAM = XXXXXXXXXX
   YUBAI_ICLOUD = NO
   YUBAI_MAC_SANDBOX = NO
   ```

   `XXXXXXXXXX` 只是占位符，脚本会拒绝它。请用不带引号的单行直接赋值；上传脚本只读取此文件中的最后一个直接赋值，不执行文件，也不展开其中的变量、条件或其他 include。这个文件已被 Git 忽略，不放私钥；`.example` 是共享模板。应用和测试目标都可选包含它，缺少文件不影响免费团队本机开发。今后团队配置以此文件为准，不在 target 设置中增加相互覆盖的 Team 或 entitlement 路径。

## 归档、上传和安装

在 Mac 的终端进入仓库根目录，运行其中一条。命令会实际创建归档并上传到所配置团队的 App Store Connect：

```sh
scripts/testflight.sh       # 默认只上传 iPhone / iPad 构建
scripts/testflight.sh mac   # 只上传原生 Mac 构建
scripts/testflight.sh all   # 依次上传 iOS 和原生 macOS
```

脚本要求 Xcode 26 和本机配置中的 Team ID，保持自动签名，通过 `-allowProvisioningUpdates` 让 Xcode 使用已登录的 Apple ID 管理所需签名资源。若需要账号登录、钥匙串访问或协议处理，先在 Xcode / 网站完成后重试。脚本不能判断某个 Team ID 是否已付费；即使填入免费团队 ID，Apple 仍会拒绝 App Store 分发。不要用 `scripts/package-mac.sh` 的本地 DMG 上传 TestFlight。

Mac App Store / TestFlight 要求 App Sandbox，脚本在 Mac archive 命令行强制传入 `YUBAI_MAC_SANDBOX=YES`（`mac` 和 `all` 的 Mac 归档均如此），不改本机配置，日常直接安装仍默认非沙盒。iCloud 是否开启继续由独立的 `YUBAI_ICLOUD` 决定。

每次使用 **UTC 分钟时间 `YYYYMMDDHHMM`** 作为 `CURRENT_PROJECT_VERSION`，例如 `202610201430`；版本号为 **2.0.0**。项目里的日常 build 仍为 `1`，归档时用命令行覆盖，Info.plist 从构建设置取值，不用每次改工程。`all` 的两个平台共用本次构建号。归档、源码副本、导出选项和日志保存在 `build/testflight/<构建号>/`，整个 `build/` 已被 Git 忽略。每个平台有自己的 `Yubai.xcarchive`、`archive.log`、`upload.log` 和导出目录。

脚本用独占目录拒绝同一仓库同一分钟再次运行，避免重用构建号；失败后保留记录，等下一个 UTC 分钟再试。保持 Mac 时钟准确；多个仓库副本或不同机器不要在同一分钟上传同一平台，也不要回拨时间。重新上传使用新的一分钟，不删除旧目录来复用号码。导出模板的 `teamID` 只在该目录里的副本中替换，`manageAppVersionAndBuildNumber = false` 防止 Xcode 另改号码。

上传命令成功后，到 App Store Connect → 余白 → TestFlight 等待 Apple 处理。收到处理邮件或构建可用后，选择对应平台和 2.0.0 构建，填写「测试内容」并加入「本人」内部组；若未自动发邀请，手动邀请自己。遇到 Missing Compliance 时按下一节检查加密问题。处理耗时由 Apple 决定；命令成功不等于已经可以安装。[Apple：构建状态](https://developer.apple.com/help/app-store-connect/reference/app-build-statuses/)

在 iPhone 的 App Store 或 Mac App Store 安装 Apple 的 **TestFlight**，使用收到邀请的 Apple 账户接受邀请，再安装「余白」。余白要求 iOS 18 / macOS 14 或更新版本。内部测试不需要 Beta App Review；外部测试另有审核要求。每个测试构建可用 **90 天**，到期前上传新构建并更新。[Apple：TestFlight](https://developer.apple.com/testflight/)、[内部测试与邀请](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)

首次安装沙盒版 Mac 应用（TestFlight）时，新容器初始为空，会显示空账本；旧非沙盒账本不会自动迁入。**切换前，必须先在旧 Mac 应用的「我 → 备份与同步」导出加密的完整备份，再在 TestFlight 构建中选择该备份、输入密码并确认恢复。** 妥善保存密码，保留旧应用和文件。免费签名切换团队前也先备份，不要先卸载来解决安装问题。沙盒和旧 Mac 存储位置的区别见下文。

## 加密、隐私和 Mac 权限

当前代码使用系统加密，因此 Info.plist 设置 **`ITSAppUsesNonExemptEncryption = NO`**，意思是「没有非豁免加密」。若被问「是否使用加密」，不能回答完全没有：云端调用使用系统 URLSession 的标准 HTTPS；`Sources/YubaiCore/Storage.swift` 使用系统 CryptoKit 的 AES-GCM 加密本地备份、SHA-256 校验；`Sources/CArchive/Archive.c` 使用系统 CommonCrypto 的 PBKDF2-HMAC-SHA256 派生备份密钥。备份文件格式由应用包装，加密算法实现来自 Apple 系统，没有自带密码库或专有算法。按当前实现，对「是否仅使用 Apple 操作系统提供的加密」回答是，对「是否使用非豁免加密」回答否；Apple 对仅使用系统加密的应用不要求在 App Store Connect 上传加密文档。以后引入其他密码实现时重新核对。[Apple：加密出口声明及材料](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/)

隐私清单随应用打包，目前声明：

| API / 权限 | 代码依据与用途 |
|---|---|
| 文件时间 / 元数据 `C617.1` | Storage 读取应用私有恢复文件的修改时间，读取本机 / iCloud 账本与附件元数据 |
| 用户选择文件元数据 `3B52.1` | ImportView、AskYubaiView、SettingsView 读取用户选中文件大小，限制导入和备份容量 |
| UserDefaults `CA92.1` | 应用 LedgerSync 只读写自己的本机 / iCloud 位置偏好 |
| 语音、麦克风 | Info.plist 已有中文说明；AskCapture 在用户开始听写时请求授权；Mac 沙盒另有音频输入权限 |
| 照片 | 使用 PhotosPicker / `loadTransferable` 读取用户选中的截图，不直接枚举照片库；此路径不需要整库授权。现有照片用途说明保留，但不代表请求整库权限 |

源码未发现磁盘剩余空间、系统启动时间或键盘列表等其他 required-reason API 的直接使用。清单是源码核查结果，最终以 Xcode 归档和 Apple 处理结果为准。它不代替 App Store Connect 的应用隐私问卷，后者应按实际启用的云端功能填写。[Apple：Required Reason API 理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)、[PhotosPicker](https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app)

图标资源已有 iOS 通用 1024×1024，以及 Mac 16 / 32 / 128 / 256 / 512 点的 1×、2× 全套 PNG。仓库里的旧 iOS PNG 带 alpha 通道；上传脚本在 `build/testflight/<构建号>/source/` 的源码副本中调用现有 Swift 绘图脚本，重建无 alpha 的 RGB iOS 图标及完整 Mac 图标，再从副本归档，原仓库 PNG 不变。这里只沿用现有代码绘制的图标，不更换图案。Info.plist 补齐 iPad 多任务要求的四种方向，开发语言引用工程的简体中文设置；Mac 分类设为 `public.app-category.finance`，并补充版权字段。

Mac 使用 SDK 条件选择权限文件，iOS 不接收 Mac 权限：

| 平台 / 沙盒开关 | iCloud 关闭（默认） | iCloud 开启 |
|---|---|---|
| iOS | 无附加 entitlement 文件 | `Yubai-iCloud.entitlements` |
| macOS：`YUBAI_MAC_SANDBOX = NO`（默认，直接安装） | 无附加 entitlement 文件 | `Yubai-iCloud.entitlements`：仅 iCloud 权限，无沙盒 |
| macOS：`YUBAI_MAC_SANDBOX = YES`（TestFlight 归档强制开启） | `Yubai-macOS.entitlements`：沙盒、网络客户端、用户选中文件读写、麦克风输入 | `Yubai-macOS-iCloud.entitlements`：前述全部权限加上同一组 iCloud Documents / 容器权限 |

macOS 的选择由 `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = $(YUBAI_MAC_ENTITLEMENTS_$(YUBAI_MAC_SANDBOX)_$(YUBAI_ICLOUD))` 完成，两个开关独立组合。非沙盒 Mac 与 iOS 复用现有的 iCloud-only 文件；三个权限文件均已登记在工程和生成器中，无需新增文件。组合文件是两组权限的显式并集，修改任一基础权限时也要同步组合文件。测试目标只包含团队设置，不继承应用的 iCloud 或沙盒权限。只填写团队不会开启 iCloud 或沙盒。

正式账本路径通过 `FileManager` 的 Application Support API 获取，没有硬编码家目录。Mac 沙盒内通常为 `~/Library/Containers/app.yubai.personal/Data/Library/Application Support/app.yubai.personal/`，账本、附件、恢复版本都可写入；旧非沙盒包的 `~/Library/Application Support/app.yubai.personal/` 不会被代码自动读取或迁移，应通过完整备份交接。导入与备份恢复在安全作用域内读取所选文件，导出使用系统 `fileExporter`；没有长期保存外部文件 URL 的需求。开发用 `YUBAI_DATA_DIR` / `--data-directory` 指向容器外位置可能被沙盒拒绝，测试时使用容器内目录或系统文件选择器，不扩大全盘权限。

当前环境没有 Xcode；本次没有执行工程生成器、绘图脚本、shellcheck、构建、归档、上传或真机测试。权限组合已按文本核对，仍需在 Mac 验证首次启动、备份交接、系统文件导入 / 导出、麦克风和可选 iCloud；没有声称通过 Apple 处理。免费团队本机安装仍是当前测试路径。

## 可选：无人值守上传

平时使用 Xcode 登录的 Apple ID 即可，不需要 API key。只有准备在 CI 等环境运行时，才在 App Store Connect 的 Users and Access → Integrations 创建具备此应用和上传 / 签名资源访问权限的团队 API key；该运行环境也需要可用的签名身份及钥匙串权限。API key 不是替代付费会员的办法。[Apple：App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)

```sh
export ASC_KEY_ID='你的KeyID'
export ASC_ISSUER_ID='你的IssuerUUID'
export ASC_KEY_PATH='/私有目录/AuthKey_你的KeyID.p8'
scripts/testflight.sh all
```

三个变量必须同时设置；脚本将它们传给 archive 和 export 的 `-authenticationKeyPath`、`-authenticationKeyID`、`-authenticationKeyIssuerID`。私钥放在仓库外，不写入 xcconfig 或工程，不提交；`DEVELOPMENT_TEAM` 仍从本机配置读取。恢复 Apple ID 登录方式时，在终端取消这三个变量即可。
