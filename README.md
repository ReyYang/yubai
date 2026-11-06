<div align="center">

<img src="docs/brand-kit/vector/yubai-lockup-horizontal.svg" alt="余白 Yubai" width="420">

### 花之前，告诉你还能不能花。

一个住在 iPhone 里的财务管家。账本留在本机，不用注册；<br>
AI 负责理解和整理，数字永远由代码来算。

![iOS 26+](https://img.shields.io/badge/iOS-26%2B-2f6f5e)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-2f6f5e)
![Swift](https://img.shields.io/badge/Swift-6.2%20toolchain%20·%20v5%20mode-f05138)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0a84ff)
![Local first](https://img.shields.io/badge/data-local--first-6b5b3e)
![License](https://img.shields.io/badge/license-Apache--2.0-blue)

</div>

---

## 为什么是余白

大多数记账 App 是一张换了皮的 Excel：你填格子，它画饼图，判断还是得自己做。

余白想做的是**管家**，不是表格。它看着你的账户、会回来的账单和下一次发薪日，在你掏钱之前算清楚「还能花多少」；它记得你写下的消费观，在你犹豫要不要买的时候，按你自己的标准帮你想一想。

同时它首先是一个好用的记账 App：手动记一笔、改一笔永远是最快的路，和 AI 说话只是多一条路。

> 余白 2.0 · 管家 —— AI 做事，代码算数。

## 核心体验

| | |
|---|---|
| **还能花** | 从现在到下一次发薪日（没有固定收入时看 90 天），扣掉会回来的账单、在存的钱和日常开销后，还剩多少可以自在地花。点开金额，每一项扣除都看得到。 |
| **该不该买** | 想买一样东西时问余白。它用本机算出的数字，对照你的消费观，给出买、等等或算了的建议，并说清依据。 |
| **心愿单** | 还在想的东西先放进来。买了一个月后，余白会问一句「用得怎么样？」，你的回答会慢慢让判断更准。 |
| **每周来信** | 每周一份回顾：上周的数字、图表和变化，以及余白这周对你多了解的一点。 |
| **我的消费观** | 写下原则、想克制的、愿意多花的，以及想始终留着的钱。余白从聊天里记下的生活背景也在这里，随时可看、可改、可删。 |

### 其他你会用到的

- **四个入口**：现在 · 洞察 · 账目 · 我，右下角常驻「问余白」。
- **记一笔 / 改一笔**：两位小数的金额、分类与子分类、用途、转账；最近删掉的记录可以找回。
- **会回来的账单**：房租、订阅、分期、工资都按期出现，每一期只问一句「付了吗」。
- **洞察**：按时间窗口看支出和收入的分类分布；现在页上还有接下来几周的现金走势。
- **快速记账**：锁屏 / 主屏小组件、控制中心按钮和快捷指令；截图或一句话也能补记。
- **导入账单**：支持 CSV、TSV、XLSX。先按「对方」把重复往来归组，再交给云端整理，问题集中一次回答；可后台继续，可整批撤销。
- **对一下余额**、多账户、心愿单回访、整理剩下没分类的记录。
- **备份与恢复**：密码加密的完整备份；本机自动保留最近的恢复版本；可选 iCloud 同步（需付费开发者账号）。

## 隐私与 AI 边界

余白默认**完全离线**。云端智能（DeepSeek）需要你在「我 → 智能与隐私」里自己填入密钥后才会开启。

- **数字只来自本机。** 金额、余额、还能花都由 `YubaiCore` 计算，AI 只能通过只读工具查询，不能改已有记录的金额。
- **修改需要你确认。** AI 想改账本时，会以「余白想这样改」的形式提出，由你点头。
- **外发内容最小化。** 只发送任务需要的脱敏摘要（日期、金额、商户等）；原始图片、账单文件、交易单号不会离开手机。「发给云端的内容」页面可以查看最近每一次发送。
- **密钥只在 Keychain。** 不进入账本，也不进入备份。

完整的外发边界见 [docs/ASSISTANT.md](docs/ASSISTANT.md)。

## 技术栈

| 层 | 说明 |
|---|---|
| `Sources/YubaiApp` | SwiftUI App，iPhone 优先，同一份代码也能在 Mac 上运行。最低 iOS 26（Liquid Glass 只用于浮层）。 |
| `Sources/YubaiCore` | 纯 Swift 业务核心：账本模型与迁移、财务计算、导入解析与去重、整理与助手工具、管家卡片、每周来信、加密备份、原子存储与恢复版本。**不依赖 UI，可在 Linux 上编译和测试。** |
| `Sources/YubaiWidgets` | 小组件与控制中心按钮，通过 App Group 共享快照。 |
| `Sources/CArchive` | 读取 XLSX 用的极小 C 解压层。 |
| 云端智能 | DeepSeek Chat API（`deepseek-flash` / `deepseek-v4-pro`），无联网搜索。 |
| 依赖 | 只有 [swift-crypto](https://github.com/apple/swift-crypto)，且仅在 Linux 上使用；Apple 平台走 CryptoKit / CommonCrypto。 |

```
Sources/
├── YubaiApp/        SwiftUI 界面、设计系统、App Intents
├── YubaiCore/       业务核心（含 Assistant/ 助手与整理）
├── YubaiWidgets/    小组件
└── CArchive/        XLSX 解压
Tests/
├── YubaiCoreTests/  600+ 项单元测试，夹具均为合成数据
└── YubaiUITests/    离线 UI 流程测试
```

## 本地构建

### 环境

- macOS + Xcode 26（Apple SDK），Swift 5 语言模式
- 免费 Apple ID 的 **Personal Team** 就够用，不需要付费开发者账号

### 在 iPhone / 模拟器上运行

1. 打开 `Yubai.xcodeproj`，scheme 选 **Yubai**。
2. 在 **Yubai** 和 **YubaiWidgets** 两个 target 的 *Signing & Capabilities* 里选同一个 Personal Team，保持自动签名。
3. （可选）需要本机覆盖配置时：

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig   # 已被 git 忽略
   ```

   - `YUBAI_ICLOUD = NO`：免费团队保持关闭。
   - App Group 默认开启；如果签名注册失败，设 `YUBAI_APP_GROUP = NO`，小组件会退回为纯入口按钮。

4. 选择设备，Run。真机日常使用请装 **Release** 构建，Debug 会慢很多。

命令行编译（Apple Silicon 上务必带上架构参数，否则小组件的 x86_64 链接会失败）：

```sh
xcodebuild -project Yubai.xcodeproj -scheme Yubai -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

> 免费 Personal Team 的签名大约 7 天过期，到期重新构建安装即可。**不要为了续签先卸载**，卸载会删除本机账本；更新前先在「我 → 备份与同步」导出一份加密备份。

更完整的真机步骤见 [docs/INSTALL-iPhone.md](docs/INSTALL-iPhone.md)。

### 在 Linux 上测试 Core

`YubaiCore` 不依赖 SwiftUI，可以在任何 Linux 机器或容器里免费跑完整的单元测试：

```sh
scripts/install-linux-swift.sh             # 取出 Swift 6.2 工具链到 /opt/swift-rootfs（已装则跳过）
export PATH=/opt/swift-rootfs/usr/bin:$PATH
swift test
```

包清单在 Linux 上会自动排除 App 目标。默认测试全部离线；需要连真实 DeepSeek 的评测必须显式设置 `YUBAI_LIVE_EVAL=1`，见 [docs/ai-bench](docs/ai-bench/README.md)。

### 关于 CI

仓库里的两个 GitHub Actions 工作流（Linux Core、iOS）都设为**只能手动运行**，不会随 PR 自动触发，以免消耗 Actions 额度。日常验证请在本地跑。

## 文档

| 文档 | 内容 |
|---|---|
| [DEVELOPMENT.md](docs/DEVELOPMENT.md) | 开发说明：目录职责、签名配置、iCloud、存储与恢复、测试 |
| [ASSISTANT.md](docs/ASSISTANT.md) | 助手工具、外发内容与隐私边界 |
| [FIXED-BILLS.md](docs/FIXED-BILLS.md) | 会回来的账单的模型与 API |
| [QUICK-CAPTURE.md](docs/QUICK-CAPTURE.md) | 快速记账与 App Group |
| [INSTALL-iPhone.md](docs/INSTALL-iPhone.md) | 免费团队真机安装 |
| [TESTFLIGHT.md](docs/TESTFLIGHT.md) | 将来有付费账号后的 TestFlight 流程 |
| [CONTEXT.md](CONTEXT.md) | 界面用词与领域词汇 |
| [HISTORY.md](docs/HISTORY.md) | 历次改动的详细记录 |

## 参与

余白目前由作者一个人自用打磨。欢迎提 Issue 讨论想法或报告问题。贡献代码前请先看两条约定：

- **界面改动设计先行。** 涉及界面、交互、视觉的改动，先有设计稿再写代码。
- **少写字，让版式说话。** 界面上只出现标题、数字与事实、控件上的字和状态，不加解释性的副标题。详见 [AGENTS.md](AGENTS.md)。

## 许可证

[Apache License 2.0](LICENSE) © 2026 ReyYang
