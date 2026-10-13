# 在自己的 iPhone 安装余白

余白的最低版本为 iOS 18。Xcode 工程已包含图标、隐私说明、文件类型、原生界面和本地账本。2026-10-08 已从当前源码重新构建 Release 真机应用、完成开发签名并安装到「阿雨的 iPhone」。历史 `build/iPhone/` 归档仍未签名，不是可直接安装的 IPA。

## 本人手机的当前状态（2026-10-08）

- 手机：iPhone 16 Pro Max，iOS 27.0，已配对、有线连接、开发者模式开启。
- 安装：手机应用列表独立回读为「余白」`app.yubai.personal`，版本 `1.0.0`、build `1`；安装前不存在该应用。
- 签名：Personal Team `7KKK56MULJ`，复用现有 Apple Development 证书；新 profile 为 `cd521254-43a3-4afa-8eda-4618658c9045`，只包含本人这台设备。`codesign --verify --deep --strict`、Team/Bundle ID/证书/设备校验通过。
- 有效期：2026-10-15 17:32:21（Asia/Shanghai）。到期需续签安装；更新时保留同一 Bundle ID，先备份，不要先卸载。
- 首次启动与本人确认：首次远程启动返回 `Security`。本机签名及 profile 匹配通过后，由本人在手机「设置 → 通用 → VPN 与设备管理」信任开发者 App `1270730209@qq.com`。本人报告蜂窝网络下「验证 App」转圈后无结果；切换到 Mac 使用的 Wi-Fi 后验证完成，并明确确认「余白已打开」。随后 `devicectl device info processes` 在同一设备独立读回余白进程 PID `74990`，可执行文件位于本次安装的应用容器。本次没有第二次安装或远程启动；不把首次运行写成完整业务验收。
- 证据：`build/phone-install-20261008-signature.json`、`build/phone-install-20261008-install.json`、`build/phone-install-20261008-readback.json`、`build/phone-install-20261008-launch.json`。当前签名应用在 `build/PhoneInstall-20261008/Build/Products/Release-iphoneos/Yubai.app`。

本次签名和安装依据用户在本对话的精确批准。首次证书指纹写法被 Xcode 本地参数检查拒绝；确认 profile 仍为空、签名身份未变化后，改用自动签名要求的 `Apple Development`，实际构建仍使用原证书。两次准备日志均保留，没有改变应用源码。

当前准备好的入口：项目根目录的 `Yubai.xcodeproj`，共享 scheme 为 `Yubai`，Bundle ID 为 `app.yubai.personal`。无远程 Swift Package 或 CocoaPods 依赖。

## 安装步骤

1. 解锁 Mac 和 iPhone，用数据线连接，在 iPhone 上确认信任这台 Mac。若系统要求开发者模式，在手机「设置 → 隐私与安全 → 开发者模式」按系统流程启用；这一步可能要求重启，需本人操作。
2. 在 Xcode 打开 `Yubai.xcodeproj`，选择 **Yubai target → Signing & Capabilities**。选择你自己的现有 Team，保留 Automatically manage signing。
3. 在工具栏选择已连接的 iPhone，scheme 选 Yubai，再按 Run。首次签名可能由 Xcode 向 Apple 登记 App ID、设备并创建 provisioning profile；账号登录、证书或权限确认由本人完成。
4. 若手机提示不受信任开发者，按系统提示在「设置 → 通用 → VPN 与设备管理」确认自己的开发者身份。回到余白，确认欢迎页出现，再建立账本。
5. 新建一个明确的测试账户、补记一笔、关闭重开后核对，再删除测试记录或恢复自己的完整备份。正式开始前可先体验独立示例。

历史状态（2026-10-02）：本机有 Apple Development 身份，Team 为 `7KKK56MULJ`，证书有效期至 2027-04-28；当时未发现现成 provisioning profile，已配对设备「阿雨的 iPhone」显示 unavailable。该次检查没有创建开发者资源或安装到真机；2026-10-08 状态以上方记录为准。

## 签名有效期

免费 Personal Team 的 profile 有效期通常为 7 天，需重新构建安装；Apple Developer Program 的分发与有效期取决于实际账户和 profile。现有开发证书不证明账号属于哪一类，也不代表应用可永久安装。[Apple 官方账户说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)

同一 Bundle ID 更新通常保留应用数据；**不要为了续签先卸载应用**。卸载会删除本地账本，应先导出完整备份。若需要长期分发或 TestFlight，应另行确认开发者账户、提交内容和发布权限；当前版本未公开发布。

如果希望由 Agent 继续签名与安装，先连接并解锁设备。Agent 需刷新 Team、profile、设备和构建状态，再展示本次具体签名/安装动作；未经确认不能创建或改动开发者资源。
