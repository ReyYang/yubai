# 余白 · 交付与验证记录

## Linux Core 构建与单元测试（2026-10-21）

环境为 Ubuntu 24.04.5 LTS、x86_64、Swift 6.2.4（`swift-6.2.4-RELEASE`），Swift 5 语言模式。先执行 `export PATH=/opt/swift-rootfs/usr/bin:$PATH`；受限容器使用 [开发说明](DEVELOPMENT.md#linux-core-构建与测试) 中的可写模块缓存路径。

| 命令 | 实际结果 | 原始日志（本地保留，不纳入版本管理） |
|---|---|---|
| `swift build --target YubaiCore` | 退出 0，CArchive 与 YubaiCore 编译成功 | `.verification/linux-swift/core-build.log` |
| `swift build` | 退出 0；Linux 构建图只包含 Core 与依赖，未构建 YubaiApp | `.verification/linux-swift/build.log` |
| `swift test` | 退出 0；253 项 XCTest，249 通过、4 跳过、0 失败（0 unexpected），25.945 秒 | `.verification/linux-swift/test-final.log` |

四个跳过均为原有的实网 opt-in 评测，未启用 `YUBAI_LIVE_EVAL=1` 与配置密钥：

- `AIBenchTests.testLiveCloudFixtureWhenExplicitlyEnabled`
- `AssistantEvalTests.testLiveAssistantEvalOnlyWhenExplicitlyEnabled`
- `DeepSeekCloudTests.testLiveDeepSeekSmokeWhenExplicitlyEnabled`
- `ImportOrganizerTests.testLiveImportEvalOnlyWhenExplicitlyEnabled`

本轮新增 `XCTSkip` 为 0，既有测试未跳过、禁用或放宽断言。新增两项备份测试与一项 Linux 内存密钥生命周期测试：独立 hashlib／AESGCM 向量验证 100,000／210,000／1,000,000 轮 PBKDF2-HMAC-SHA256、含中文／NUL／emoji 的 UTF-8 密码、v1 nonce＋密文＋tag 与 AAD；另测 tag 篡改、导出参数与无效盐／轮数拒绝。原有 GB18030、XLSX、权限 700／600、附件、原子保存、恢复、云端 HTTP stub 等测试实际通过，无需改变金额或日期格式行为。首轮仅新增向量缺少必填偏好字段而失败，修正夹具后 StorageTests 17 项通过，再完成上述全量测试。

Linux 使用 swift-crypto 3.15.1（`Crypto`、`_CryptoExtras` 产品仅在 Linux 生效）；Apple 的 CryptoKit／CommonCrypto 路径保持。API 密钥在 Linux 仅驻内存，iCloud 系统服务显式不可用；本机文件版本与测试注入的冲突选择照常运行。另将一处嵌套字符计数表达式拆成相同求和，解决 Swift 6.2.4 的类型推导超时，计数规则不变。`git diff --check` 通过；未修改 Yubai.xcodeproj、工程生成器或 UI。

本记录仅证明 Linux Core 的编译与单元测试；未运行 Apple 构建、真实 Keychain／iCloud、SwiftUI／UI 测试、安装或实网 DeepSeek。下方 2026-10-20 的「无工具链／未执行」为当时历史状态，Apple 验收与设计资源边界继续有效。

## 记忆与智能设置界面静态检查（2026-10-20）

- 按用户确认的八张 HTML 源码实现记忆列表、问答撤销、来信 learned／review、智能与隐私及模型不可用状态，原稿原样保存在 `.design-meta/mockups/ai-memory-v3/`，映射见 [DESIGN.md](../.design-meta/DESIGN.md#2026-10-20--记忆与智能设置选定稿)。
- 新增／扩展 core 测试源码覆盖用户编辑、导入自由补充的原子保存与批次撤销／旧JSON、画像回顾近况与已解决状态、模型偏好优先级、真实 HTTP 错误分类及响应体不外泄、发送总计。UI 测试新增第六条脚本流程：问答记下 → 我 → 记忆编辑 → 重开 → 删除；脚本不受之前保存的模型错误状态影响。
- 已通读变更并使用 tree-sitter 解析 `Sources/`、`Tests/`、`Package.swift` 共85个 Swift 文件，零语法解析错误；已运行 `python3 scripts/generate-project.py` 更新工程，检查 App 源文件引用及重复生成一致性，`git diff --check` 通过。
- 当前没有 Swift／Xcode／Apple SDK，未进行 Swift 类型检查、编译、XCTest 或 UI 运行，也未请求 DeepSeek。SwiftUI 的分组 List／编辑器、嵌套提案 sheet、Observable 跨 actor 状态以及两端 SDK 可用性仍须实际构建确认。设计已获确认，原生视觉／触控／辅助功能尚未验收；旧 Figma／原型／截图／包未同步。本轮未创建 git commit。
- 本批全部手动验收项统一维护在 [组合清单的记忆与智能设置部分](V2-TEST-CHECKLIST.md#记忆与智能设置2026-10-20-用户确认稿尚未运行)，均未勾选，不视为已通过。


## 余白记忆层 core 静态检查（2026-10-20）

分支 `feat/ai-memory-drift-fixes` 本轮只改 YubaiCore、测试和文档，YubaiApp 无差异，未创建提交。新增记忆读写／撤销、每周回看、来信 learned 与画像过期回顾；接口与待接线事项见 [ASSISTANT.md](ASSISTANT.md#余白记得的记忆层-core2026-10-20)。

- 使用本机 tree-sitter Swift 解析 `Sources/`、`Tests/` 与 `Package.swift` 共82个文件，零语法解析错误；`git diff --check` 通过。新 core 文件由 SwiftPM 自动发现，无需改变 App 工程引用。
- 新增24个 XCTest 方法，覆盖记忆写入／替换／撤销、预算和 recall、使用标记及隐私、回访、反思结果与非法输出、来信 learned 与否认、合并防复活、旧 JSON、画像回顾及动作；调整冷启动工具契约测试。均为脚本化传输／合成数据，**尚未执行**。
- 本机没有 Swift／Xcode／Apple SDK，未做编译器类型检查、Codable／Sendable 合成验证、XCTest 编译或运行；未请求真实模型或验证 iCloud。语法解析通过不能认定可编译。界面管理、聊天结果保存、反思触发、导入自由补充和来信动作待设计确认后接入 App。

## 余白 2.0「管家」静态检查与待验收（2026-10-20）

分支 `feat/yubai-2-butler` 已落地步骤 1–9 及 TestFlight 准备；步骤 10 同步产品记录。当前状态为**仅静态检查，尚未编译或运行**。本容器没有 Swift、Xcode 或 Apple SDK，不能据此宣称 2.0 可安装、测试通过或产品已验收。

- tree-sitter：解析 `Sources/`、`Tests/` 与 `Package.swift` 共 75 个 Swift 文件，零解析错误；这不检查 Swift 类型、SDK 或链接。
- 工程引用：在临时目录运行工程生成器，与登记的 `project.pbxproj` 及共享 scheme 逐字节一致；核对 SampleData 只在测试目标、iCloud 与 Mac 沙盒默认 NO。工程引用一致不代表 Xcode 构建成功。
- 尚未执行：`swift test`、Core XCTest、`YubaiUITests` 五条流程、iPhone／Mac 构建或安装，以及真实 DeepSeek 请求、发送内容检查、Keychain、升级与旧备份恢复、导入撤销、OCR、语音、通知、离线补整理、iCloud 同步或冲突、TestFlight 归档上传。测试文件存在不计为测试通过。
- Figma、2026-10-19 页面稿、历史原型、截图和发布包均未同步 2.0。用户决定与实现差异见[第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md#2026-10-20--余白-20管家决策归档)，当前候选与设计缺口见 [DESIGN.md](../.design-meta/DESIGN.md#20-设计资源与缺口2026-10-20)。

owner 于 2026-10-20 决定暂不加入付费 Apple Developer Program：本轮免费团队 Xcode 直接安装，TestFlight 以后再用。最后由 owner 在自己的 Mac 一次验收，一个到 main 的 PR 附相同组合清单；本轮不提交或推送。以下全部待执行，与 [V2-TEST-CHECKLIST.md](V2-TEST-CHECKLIST.md)逐项一致，勾选须以真实结果为准。

## 安装与构建

- [ ] 安装：本轮用 Xcode 直接装到 iPhone 和 Mac（免费个人团队，签名 7 天有效）；TestFlight 脚本已备好，开通付费开发者账号后按 docs/TESTFLIGHT.md 使用。
- [ ] 构建：Xcode 26 打开 `Yubai.xcodeproj`，iPhone 模拟器与 My Mac 两个目标都能编译；`swift test` 全部通过；`YubaiUITests` 六条流程通过（新增问答记忆 → 我 → 编辑／重开／删除）。

## 升级与智能设置

- [ ] 升级：用一份真实账本的副本（或旧加密备份）启动，确认自动升级、恢复版本里出现「升级前版本」、余额与保守可动用和升级前一致（旧应急底线已迁入消费观）。
- [ ] 密钥：我 → 智能与隐私 填 DeepSeek 密钥、测试连接、查看「发给云端的内容」里没有人名、卡号、订单号。

## 主要使用流程

- [ ] 导入：导入一份真实账单，看整理结果、≤5 个问题、回答、整批撤销后账本恢复。
- [ ] 消费观：冷启动聊几句并确认；手动加一条想克制的领域和软线。
- [ ] 现在：制造一次超线，看到卡片；「以后别提」后消失；依据能打开记录详情。
- [ ] 来信与提醒：打开每周提醒开关，系统请求通知权限。
- [ ] 问余白：问一个数字问题（与 现在 的数字一致）；「把上周的美团都改成餐饮」出现确认；「把那笔 42 改成 24」被拒绝；买前问一件东西，加入心愿单；语音输入一句；截图记一笔并确认金额。

## 离线与 Mac 同步

- [ ] 离线：断网导入，联网后补整理。
- [ ] Mac：同样三处界面可用。iCloud 默认关闭；如有付费开发者账号，按 docs/DEVELOPMENT.md 改一行开启后两端同步与冲突选择。

## 1.0 历史验证（不覆盖 2.0）

> 历史 1.0 资料：下文保留当时的验证与画布证据。2.0 已采用「现在／我 + 问余白」，旧页面、示例模式与导出入口不再适用；当前结构见 [README](../README.md)。这些结果不代表 2.0 已编译或验收。

下表 `dist/` 安装包、源码包与校验和路径为历史产物记录，本容器未提供对应文件。

2026-10-08 vphone 实际执行结果：[完整结果与证据](IOS-E2E-VPHONE.md)。Core 2.4.0、唯一客体和余白 1.0.0 已安装运行，20 组流程已有结果：**14 组通过、4 组失败、OCR 环境不支持、认证成功路径受阻；完整验收未通过**。发现大账本新增/后台切换看门狗终止、原文件导出误触撤销、退款分类错位和偏好字段无标签。最终 4,032 笔账本摘要完整保留。以下旧验证不计入本轮通过数。

以下核心、模拟器与 Mac 包验证日期：2026-10-02，Asia/Shanghai。环境：Apple Silicon、Xcode 26.4.1、Swift 6.3.1；原生 UI 使用独立的 iPhone 16 Pro Max 模拟器，ID `A5A70CF9-6A86-41B1-9BE4-E59B5C4704B2`。所有测试数据均为合成资料，未读取用户真实账单。

## 当前交付状态

Mac 本地安装包已生成。2026-10-08 从当前源码新构建的 iPhone Release 应用已签名，并安装到「阿雨的 iPhone」（iPhone 16 Pro Max，iOS 27.0）；手机应用列表独立回读为 1.0.0 / build 1。本机签名、Team、Bundle ID、原有证书及目标设备匹配校验通过。首次远程启动被系统以 `Security` 拒绝；本人随后完成开发者信任，蜂窝网络下「验证 App」转圈后无结果，切换 Wi-Fi 后验证完成并确认余白已打开。**签名安装与本人首次打开已完成，业务实际使用尚未验收，完整产品验收仍未通过**。具体证据与签名有效期见 [iPhone 安装记录](INSTALL-iPhone.md)。

| 产物 | 位置与实际状态 |
|---|---|
| Mac 安装包 | [Yubai-1.0.0-macOS-arm64.dmg](../dist/Yubai-1.0.0-macOS-arm64.dmg)；Apple Silicon，最低 macOS 14，本机临时签名，无 Apple 公证 |
| iPhone 工程 | [Yubai.xcodeproj](../Yubai.xcodeproj)；scheme Yubai、Bundle ID `app.yubai.personal`、最低 iOS 18 |
| iPhone 归档 | `build/iPhone/Yubai-delivery.xcarchive`；arm64 Release，`CODE_SIGNING_ALLOWED=NO`，不能直接安装 |
| 本人手机安装包 | `build/PhoneInstall-20261008/Build/Products/Release-iphoneos/Yubai.app`；2026-10-08 签名安装成功，profile 有效至 2026-10-15 17:32:21（Asia/Shanghai）；本人完成信任与验证后已打开 |
| 完整源码与项目资料 | [Yubai-1.0.0-Source.zip](../dist/Yubai-1.0.0-Source.zip)；包含源码、测试、工程、指南、研究及长期产品记录，不含凭据或个人账单 |
| 校验和 | [SHA256SUMS.txt](../dist/SHA256SUMS.txt)；核心源码文件摘要另存 `.verification/source-sha256.json` |

## 已实际通过

| 层次 | 证据与范围 |
|---|---|
| 核心测试 | `test-core-07.log`：43 项 XCTest，0 失败，约 1.03 秒；含金额精度、余额核对前后、内部移动/本金、借还款、退款、房租分摊、计划月末递推、目标预留、批量修改及无效关联 |
| 导入与容量 | 同上；CSV 多行/引号/BOM、GB18030 支付宝、XLSX 共享字符串和 1900/1904 日期、收入/支出双列、付款账户映射、稳定 ID/同额多笔/退款去重、来源冲突、用户修改保留、删除不复活、整批撤销与资源上限 |
| AI 写入边界 | 同上；模型建议只能改变已知方向对应的类别，不能更改金额、账户、性质或覆盖强规则；分类规则不能把退款/本金/未知转账变成普通收入 |
| 数据保护与恢复 | 同上；加密备份完整往返、原附件逐字节一致、错误密码/校验和/版本拒绝、独立新目录恢复、损坏账本不得被空账本覆盖、恢复前版本可再次找回、目录 700/文件 600 |
| 规模样本 | 4,000 条合成记录解析 + 提交 + 再导入去重，Mac 本机测试约 0.83 秒；这不是 iPhone 耗时、真实账单质量或每周整理总时长的证明 |
| iPhone 原生全流程 | `test-ios-final-01.log` / `.verification/ios-final-01.xcresult`：7 项 UI 测试全部通过，约 211 秒，详情如下 |
| 最后总览修正回归 | `test-ios-overview-final-02.log`：计算依据展开/收起、主页面切换及超预算购买判断通过；修正了计算入口箭头对比度与整行触控范围，其他行为沿用上面的组合证据 |
| 两端 Release | `build-release-mac-delivery.log`、`build-release-ios-delivery.log`；分别成功构建 macOS arm64 app 和 iPhone arm64 归档，最低系统版本写入 Info.plist；未在所有最低版本系统上实测 |
| Mac 包回读 | DMG 只读挂载；内部 app 与打包源逐文件比较一致，`codesign --verify --deep --strict` 通过，随后卸载挂载卷。签名验证不能代替 Mac 交互验收 |

7 项 UI 测试覆盖：真实空白账本开户、记账及重启；示例账本多页导航和购买判断；非法金额错误后保留编辑页及示例隔离；系统 Files 选择账单、两组账户映射、保存及重复导入；实际 Vision OCR 识别合成图片的 28.50 元、确认保存；系统文件导出密码备份并恢复到新空账本；通过实际设置切换深色，在最大辅助字号下观察总览、账本和设置。

## 原生截图

下面均来自成功的原生测试，没有用静态网页或绘图替代界面。

- [欢迎页](screenshots/iPhone-01-welcome.png)、[当前总览](screenshots/iPhone-03-overview.png)、[账本](screenshots/iPhone-04-ledger.png)
- [资金安排](screenshots/iPhone-05-plans.png)、[房租](screenshots/iPhone-06-rent.png)、[洞察](screenshots/iPhone-07-insights.png)、[购买判断](screenshots/iPhone-08-purchase.png)
- [文件预览与账户对应](screenshots/iPhone-09-import-preview.png)、[导入结果](screenshots/iPhone-10-import-result.png)、[重复导入](screenshots/iPhone-11-import-repeat.png)、[OCR 确认](screenshots/iPhone-12-OCR-confirmation.png)
- [备份验证预览](screenshots/iPhone-14-verified-backup.png)、[恢复后的账户](screenshots/iPhone-15-restored-account.png)、[深色与辅助字号](screenshots/iPhone-18-dark-large-ledger.png)

已观察的常规页面可读；大字号下调整了固定示例提示、筛选方式、交易行和品牌区布局。原生 tab 在 iOS 26 使用系统浮动外观，内容可滚动。截图和自动化没有穷尽所有屏幕尺寸、VoiceOver 或真实使用情况。

## 剩余条件与未验证项

- **iPhone 首次启动与使用**：2026-10-08 已获精确批准、完成自动 provisioning 和签名安装，复用原有证书；profile 仅包含本人设备。首次远程启动返回系统 `Security`，本机签名/profile 校验通过；本人完成信任并切换 Wi-Fi 后验证成功，确认应用已打开。尚未由 Agent 核验真机页面或业务交互，Face ID、OCR 和设备模型仍未验证。
- **Mac 实际交互**：已尝试用正常界面工具读取应用，系统明确返回 Mac 已锁定。没有绕过锁屏；Release 包目前只验证构建、资源、签名和包完整性。
- **真实模型生成**：Foundation Models 路径已编译且有本地写入边界测试；模拟器显示 Apple Intelligence 未启用，用户设备生成质量与可用性未验证。不会把规则判断当成实际 AI 输出。
- **真实数据**：未取得用户微信、支付宝、银行卡和截图样本，不能保证所有机构/版本的导出格式均兼容；异常保留在预览，原文件可导出。没有验证每周集中整理能否在 10 分钟内完成。
- **产品边界**：人民币、本地账本、完整备份交接；无银行直连、自动云同步、外部模型、独立照片分享扩展或自动行情。设备解锁保护是 UI 保护，不声称本地账本文件另有密码加密。iPad 与 Intel Mac 未专门验收，交付的 Mac 包仅含 arm64。

## 修复与证据保留

本轮真实失败与修复包括：CRLF/Excel 日期解析、保留编辑页的错误提示、Files 的目录导航、备份结果在屏幕外、辅助字号挤压，以及总览按钮空白区域未命中。失败日志和 `.xcresult` 保留在本地；后续通过不覆盖原失败证据。没有使用真实账单、生产系统或远端发布作为测试环境。

产品采用决定在 [第 13 票](../.scratch/yubai-product/issues/13-complete-personal-release.md)，使用入口在 [README](../README.md)。
