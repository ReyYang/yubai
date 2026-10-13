#!/bin/bash
# Package a locally built, unsigned app without using credentials or publishing.
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
codesign --force --sign - --options runtime --timestamp=none "$task_stage/余白.app"
codesign --verify --deep --strict --verbose=2 "$task_stage/余白.app"
ln -s /Applications "$task_stage/Applications"
cat > "$task_stage/安装与开始使用.txt" <<'TEXT'
余白 1.0.0 · Apple Silicon / macOS 14+

把「余白.app」拖到 Applications，然后从「应用程序」打开。
本地临时签名，没有 Apple 公证；如遇系统开发者确认，请核对来源后使用系统提供的批准入口。
不要关闭 Gatekeeper，不需要 sudo。

先看看独立示例，或开始空白账本。添加实际账户与此刻余额，设置房租、还款、应急和生活预留，再导入历史账单。
信用账户填写欠款，不填写可用额度；历史导入不会重复增加当前余额。

账户、账单、OCR、分类规则与资金计算均在本机。设备端 AI 依赖 Apple Intelligence 可用性；没有云端模型或自动同步。
请在「我的 → 备份、恢复与导出」保存加密完整备份，密码无法找回。
跨设备通过完整备份交接，一次只在一台设备编辑。不要先卸载应用再尝试迁移账本。

计算口径、使用说明及恢复入口都在应用内「我的」。
TEXT
hdiutil create -volname '余白 1.0.0' -srcfolder "$task_stage" -format UDZO "$task_output"
printf '%s\n' "$task_output"
