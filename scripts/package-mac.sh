#!/bin/bash
# Package a local build; preserve iCloud signing when present. Never publish.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_source="$task_root/build/ReleaseMac/Build/Products/Release/Yubai.app"
task_stage="$task_root/build/package-mac-$(date +%Y%m%d%H%M%S)"
task_output="$task_root/dist/Yubai-1.0.0-macOS-arm64.dmg"
test -d "$task_source"
if test -e "$task_output"; then
  echo "Output already exists. Preserve or rename that release before packaging again." >&2
  exit 1
fi
mkdir -p "$task_stage" "$task_root/dist"
ditto "$task_source" "$task_stage/余白.app"
task_entitlements="$(mktemp)"
trap 'rm -f "$task_entitlements"' EXIT
codesign --display --entitlements - "$task_stage/余白.app" > "$task_entitlements" 2>/dev/null || true
if /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers:0' "$task_entitlements" >/dev/null 2>&1; then
  # Re-signing ad hoc would discard the paid team's iCloud authorization.
  task_signing_note="保留构建时的签名与 iCloud 权限；iCloud 需要付费团队的有效签名及配置。"
else
  codesign --force --sign - --options runtime --timestamp=none "$task_stage/余白.app"
  task_signing_note="本地临时签名，账本默认仅本机。"
fi
codesign --verify --deep --strict --verbose=2 "$task_stage/余白.app"
ln -s /Applications "$task_stage/Applications"
cat > "$task_stage/安装与开始使用.txt" <<TEXT
余白 1.0.0 · Apple Silicon / macOS 14+

把「余白.app」拖到 Applications，然后从「应用程序」打开。
$task_signing_note
此脚本不执行 Apple 公证；如遇系统开发者确认，请核对来源后使用系统提供的批准入口。
不要关闭 Gatekeeper，不需要 sudo。

开始空白账本，添加实际账户与此刻余额，在「我的消费观」设置原则、目标与底线，再导入历史账单。
信用账户填写欠款，不填写可用额度；历史导入不会重复增加当前余额。

账户、账单、OCR、文件数值解析与资金计算均在本机。可选 DeepSeek 云端智能负责整理用途与关联；离线可先保存，联网后补整理。默认仅本机；启用并正确签名的 iCloud 构建可在「我 → 备份与同步」共享账本，冲突由你选择。
请在「我 → 备份与同步」保存加密完整备份，密码无法找回。
也可跨设备通过完整备份交接。不要先卸载应用再尝试迁移账本。

计算口径、使用说明及恢复入口都在应用内「我」。
TEXT
hdiutil create -volname '余白 1.0.0' -srcfolder "$task_stage" -format UDZO "$task_output"
printf '%s\n' "$task_output"
