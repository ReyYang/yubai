# 2026-11-02 vphone 构建报告

- 总结论：打包成功；本轮仅完成第一段，vphone 安装、真实 DeepSeek 整理及后台运行由 owner 执行，尚未验收。
- 分支与提交：`feat/organize-by-party-groups` @ `47d7f03e44bb00a01a0f38ee7ff15e1a3e10abb2`（#53 + #54）
- 环境：macOS / Xcode 27.1（27A9275）；iPhoneOS SDK 27.1；Debug / iphoneos / arm64；最低 iOS 26.0。
- 编译开始：2026-11-02T14:18:45.228817+08:00；构建及产物检查完成：2026-11-02T14:19:27.674122+08:00。

## 编译：成功

`xcodebuild` 退出 0，`** BUILD SUCCEEDED **`，日志无 `error:` 行。使用现有仓库，未创建 worktree；应用、测试及工程源码未修改。

```sh
xcodebuild build -project Yubai.xcodeproj -scheme Yubai -configuration Debug \
  -destination 'generic/platform=iOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath "$PWD/.dd-vphone"
```

SSH fetch 返回 `Connection closed by 30.100.5.158 port 443`；随后用单次 HTTPS fetch 拉取同一远端分支并核对完整 SHA。未更改 origin URL 或全局 Git 配置。

## 签名方式、身份与 entitlements

沿用仓库已有 [vphone 未签名包方式](../docs/IOS-E2E-VPHONE.md#测试对象与隔离)，本轮将配置按请求改为 Debug，使用命令行 `CODE_SIGNING_ALLOWED=NO`；没有修改项目签名设置，没有使用或申请 Personal Team 证书。

- 签名身份：无（未签名）。
- Team：无。
- 已签名 entitlements：无，不能从未签名对象导出。
- `embedded.mobileprovision`：不存在。

按要求执行 `codesign -dv --entitlements - "$APP" 2>&1`，退出 1，原文如下；这是本次未签名方式的实际结果，不是编译失败：

```text
/Users/yang/deepresearch/yubai/.dd-vphone/Build/Products/Debug-iphoneos/Yubai.app: code object is not signed at all
```

未向包内追加签名或 entitlements。安装后的处理与运行权限需要在 owner 的第二段操作中确认；本报告不将 Info.plist 声明等同于系统已接受后台任务。

## 包内 Info.plist 与架构

应用：`app.yubai.personal` / 余白 / 2.0.0（1）。实际产物包含两项预期值：

```text
  "BGTaskSchedulerPermittedIdentifiers" => [
    0 => "app.yubai.personal.organizeImports.*"
  ]
  "BuildMachineOSBuild" => "26A434"
  "UIBackgroundModes" => [
    0 => "processing"
  ]
  "UIDeviceFamily" => [
```

`lipo -archs`：`arm64`；`vtool -show-build` 原文：

```text
/Users/yang/deepresearch/yubai/.dd-vphone/Build/Products/Debug-iphoneos/Yubai.app/Yubai:
Load command 11
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform IOS
    minos 26.0
      sdk 27.1
   ntools 1
     tool LD
  version 27037.1
```

## IPA

- 路径：`/Users/yang/Desktop/Yubai-47d7f03-vphone.ipa`
- 大小：12,200,310 字节（11.64 MiB）
- SHA-256：`8f34ec8e8501572bb92fb0ac245c1e4bdadef98b281605f4da19169c76c7d15f`
- ZIP 完整性检查通过；共 25 个 ZIP 条目，所有普通文件与原始 Debug-iphoneos/Yubai.app 逐字节一致，路径为 `Payload/Yubai.app/`。
- 未使用命令行或其他方式向 vphone 安装、启动应用，未操作 vphone 客体。

## 收尾

- Git 恢复一致：**是**；已于 2026-11-02T14:19:58.840326+08:00 核对原分支、HEAD、完整 status、binary diff、index、原有文件 SHA-256 及 stash 哈希/顺序/名称均一致。
- 已回到 `main` @ `2fa6b470f0aa4c83d2849d9ba152b5f88d03a0d2`，main 未修改。
- 开始时工作区不干净，创建了 `before vphone build 2026-11-02`（`a422bfcf18a264f1197fb78ccfb40d60d5af245c`），收尾只 pop/drop 这一项，无冲突。原有三项 stash 均未改变。
- 已删除本轮 `.dd-vphone`、`build-vphone.log`、`/tmp/yubai-ipa` 及临时 `test/vphone` 分支；构建生成的 Package.resolved 先清除，再从本轮 stash 恢复原始内容。
- 原始和恢复后的 `git status --short --untracked-files=all`：

```text
 M Yubai.xcodeproj/project.pbxproj
?? Yubai.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

- 报告提交使用独立临时 Git index，以目标提交为 parent 创建报告分支；仅加入本报告，不影响用户工作区、正常 index、原有修改或 main。
- 不修代码、不 merge、不调用 DeepSeek、不运行 GitHub Actions；未读取或打印密钥。
- 可见中文字符串改动：无。
