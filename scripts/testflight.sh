#!/bin/bash
# Archive and upload only when explicitly invoked with a configured paid team.
set -euo pipefail

task_fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

task_platform="${1:-ios}"
if (( $# > 1 )); then
  task_fail '用法：scripts/testflight.sh [ios|mac|all]（默认 ios）。'
fi
case "$task_platform" in
  ios|mac|all) ;;
  *) task_fail '用法：scripts/testflight.sh [ios|mac|all]（默认 ios）。' ;;
esac

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
task_local="$task_root/Config/Local.xcconfig"
[[ -f "$task_local" ]] || task_fail \
  '尚未设置 DEVELOPMENT_TEAM。当前仍可用免费 Personal Team 在 Xcode 直接安装；TestFlight 需要付费 Apple Developer Program。决定启用后，将 Config/Local.xcconfig.example 复制为 Config/Local.xcconfig 并填写付费团队 ID。'

# Read a literal xcconfig assignment, never execute the file as shell code.
# The last assignment wins, as in xcconfig. Keep this setting on one line.
task_team="$(awk '
  {
    sub(/\/\/.*/, "")
    if ($0 ~ /^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/) {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/[[:space:]]*$/, "")
      team = $0
    }
  }
  END { print team }
' "$task_local")"
[[ "$task_team" =~ ^[A-Z0-9]{10}$ && "$task_team" != XXXXXXXXXX ]] || task_fail \
  '请在 Config/Local.xcconfig 写入 DEVELOPMENT_TEAM = 你的10位付费团队ID（不加引号）。免费 Personal Team 无法使用 TestFlight；未付费时继续在 Xcode 直接安装。'

[[ "$(uname -s)" == Darwin ]] || task_fail '归档上传需要装有完整 Xcode 26 的 Mac。'
command -v xcodebuild >/dev/null 2>&1 || task_fail '未找到 Xcode 26，请安装完整 Xcode 并在其 Settings → Locations 中选择 Command Line Tools。'
if ! task_xcode_version="$(xcodebuild -version 2>&1)"; then
  task_fail '无法使用 Xcode。请先打开完整 Xcode 26，接受许可、安装所需平台，并选择其 Command Line Tools。'
fi
task_xcode_number="$(awk 'NR == 1 && $1 == "Xcode" { print $2 }' <<< "$task_xcode_version")"
[[ "$task_xcode_number" =~ ^26([.][0-9]+)*$ ]] || task_fail \
  '此脚本要求 Xcode 26。请在 Xcode → Settings → Locations 选择 Xcode 26 的 Command Line Tools（也可用 DEVELOPER_DIR 指向它）。'

# Keep this array nonempty for macOS's Bash 3.2 with nounset.
task_signing_args=(-allowProvisioningUpdates)
if [[ -n "${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}${ASC_KEY_PATH:-}" ]]; then
  [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]] || task_fail \
    'API 密钥认证需同时设置 ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_PATH；使用 Xcode 登录的 Apple ID 时请全部取消设置。'
  [[ -f "$ASC_KEY_PATH" && -r "$ASC_KEY_PATH" ]] || task_fail 'ASC_KEY_PATH 必须指向可读取的 .p8 私钥文件；建议使用绝对路径。'
  task_signing_args+=(-authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

umask 077
task_build="$(date -u +%Y%m%d%H%M)"
task_run="$task_root/build/testflight/$task_build"
mkdir -p "$task_root/build/testflight"
# Reserve the minute atomically: never reuse an archive/build number in this checkout.
if ! mkdir "$task_run"; then
  task_fail "无法创建 $task_run；若本分钟已运行过，请等下一个 UTC 分钟再试，保留旧归档和日志。两端一起上传请使用 all。"
fi
task_finish() {
  local task_status=$?
  if (( task_status != 0 )); then
    printf '归档或上传未完成。请查看 %s 内的日志；再次上传使用下一分钟的新构建号。\n' "$task_run" >&2
  fi
}
trap task_finish EXIT

task_export_options="$task_run/ExportOptions-TestFlight.plist"
cp "$task_root/Config/ExportOptions-TestFlight.plist" "$task_export_options"
/usr/libexec/PlistBuddy -c "Set :teamID $task_team" "$task_export_options"
printf '余白 2.0.0 · build %s（UTC）\n归档与日志：%s\n' "$task_build" "$task_run"

# Archive an isolated source snapshot. Regenerate the existing code-drawn icons
# there so the legacy RGBA iOS PNG becomes RGB without changing tracked assets.
task_source="$task_run/source"
mkdir -p "$task_source"
for task_item in Sources Tests Config Yubai.xcodeproj Package.swift; do
  cp -R "$task_root/$task_item" "$task_source/"
done
xcrun swift "$task_root/scripts/make-icon.swift" "$task_source" 2>&1 | tee "$task_run/icons.log"

task_upload() {
  local task_name="$1"
  local task_destination="$2"
  local task_directory="$task_run/$task_name"
  local task_archive="$task_directory/Yubai.xcarchive"
  local task_archive_args=("CURRENT_PROJECT_VERSION=$task_build")
  if [[ "$task_name" == mac ]]; then
    # Mac App Store / TestFlight requires sandbox, regardless of local defaults.
    task_archive_args+=(YUBAI_MAC_SANDBOX=YES)
  fi
  mkdir -p "$task_directory"
  printf '\n正在归档 %s…\n' "$task_name"
  xcodebuild -project "$task_source/Yubai.xcodeproj" -scheme Yubai \
    -configuration Release -destination "$task_destination" \
    -archivePath "$task_archive" -derivedDataPath "$task_directory/DerivedData" \
    "${task_signing_args[@]}" "DEVELOPMENT_TEAM=$task_team" \
    "${task_archive_args[@]}" archive 2>&1 | tee "$task_directory/archive.log"
  printf '\n正在上传 %s 到 App Store Connect…\n' "$task_name"
  xcodebuild -exportArchive -archivePath "$task_archive" \
    -exportPath "$task_directory/export" -exportOptionsPlist "$task_export_options" \
    "${task_signing_args[@]}" 2>&1 | tee "$task_directory/upload.log"
}

case "$task_platform" in
  ios) task_upload ios 'generic/platform=iOS' ;;
  mac) task_upload mac 'generic/platform=macOS' ;;
  all)
    task_upload ios 'generic/platform=iOS'
    task_upload mac 'generic/platform=macOS'
    ;;
esac
printf '\n上传命令已完成。请到 App Store Connect → 余白 → TestFlight 等待审核，再把构建加入自己的内部测试组。\n'
