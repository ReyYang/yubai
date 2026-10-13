# 构建与维护

本轮工具链：Xcode 26.4.1、Swift 6.3.1、Apple Silicon。项目最低 iOS 18 / macOS 14。Apple Foundation Models 调用受运行时系统版本与模型可用性检查保护。

## 结构

- `Sources/YubaiCore`：模型、整数金额、财务计算、来源导入、批量操作、加密备份和原子持久化。
- `Sources/YubaiApp`：SwiftUI 页面、Apple Vision OCR、Foundation Models、系统文件交互和设备认证。
- `Sources/CArchive`：系统 zlib 与 CommonCrypto 的小型桥接，不联网下载库。
- `Tests/YubaiCoreTests`：计算与存档 contract；Fixtures 为明确合成资料。
- `Tests/YubaiUITests`：iPhone 原生交互测试，使用独立 UUID 账本；测试夹具入口仅编译进 Debug simulator。
- `scripts/generate-project.py`：从 app 源文件生成 Xcode 工程；增加 app 源文件后运行。
- `.design-meta` / `.scratch/yubai-product`：长期产品和设计资料。

## 本地验证

在项目根目录执行：

```sh
swift test
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test
```

测试只使用合成账本。具体 simulator 名称以本机列表为准；本轮测试 ID 记录于验证报告。模拟器运行结果不能代替真机签名、系统认证或设备模型实测。

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

## 数据与兼容性

`schema = 1`。正式 Mac 数据位于用户 Application Support 中的 `app.yubai.personal/ledger.json`；iOS 位于 app 私有 Library/Application Support 下。账本目录权限 700、文件 600，iOS 文件使用系统数据保护；本机文件不单独密码加密。密码加密只作用于导出的备份。

每次事务先复制并验证账本，磁盘写入成功才替换内存；保存前保留最近 20 个完整版本。损坏文件不会变成空账本，恢复会保留被替换文件。目录位置可用 `--data-directory /absolute/path` 指定；测试和预览不得指向真实数据目录。

金额、关系和来源 ID 不能由模型修改。模型只收到未匹配用途、方向和可选分类；返回结构化类别后由本地白名单及方向校验。模型不可用或出错时保留规则结果，并显示原因。不要未获授权接入新 Provider 或发送真实账单。

导入容量为单文件 50 MB、256 列、10 万行、100 万个单元格。工作簿解析会处理共享字符串、内联文本、1900/1904 日期系统，不执行公式或宏；公式单元格只读取文件内已有缓存值。旧二进制 `.xls`、PDF、多币种及任意银行私有格式未支持，应先转换或使用模板，不能通过改扩展名伪装格式。

模型和存档格式变更应先定义迁移与恢复方案。整个文件重写及 20 份完整历史适用于个人账本规模，接近 250 MB 编码容量时会拒绝继续写入并提示；无需通过删除原文件绕过。
