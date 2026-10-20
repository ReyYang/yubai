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
