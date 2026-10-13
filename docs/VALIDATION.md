# 余白 1.0.0 · 交付与验证记录

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
