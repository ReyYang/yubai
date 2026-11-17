#!/usr/bin/env bash
# Prepare the selected device before xcodebuild launches it or clones it.
set -euo pipefail
simulator="${1:?Usage: prepare-simulator-keyboard.sh simulator-UDID}"
# boot returns an error for an already booted device; bootstatus verifies either case.
xcrun simctl boot "$simulator" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$simulator" -b
domain=com.apple.keyboard.ContinuousPathIntroduction
key=DidShowContinuousPathIntroduction
xcrun simctl spawn "$simulator" defaults write "$domain" "$key" -bool true
test "$(xcrun simctl spawn "$simulator" defaults read "$domain" "$key")" = 1
