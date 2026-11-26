#!/bin/zsh
# 編譯並打包成 build/螢幕背光.app（只要 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product MonitorGlow
BIN="$(swift build -c release --show-bin-path)/MonitorGlow"
APP="build/螢幕背光.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MonitorGlow"
# SwiftPM 用 Command Line Tools 連結時，執行檔的 SDK 版本會被記成 14.0，
# 系統就把 App 當舊版、套相容外觀（選單列面板變成方框，不是 Liquid Glass）。改記成實際 SDK 版本。
vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
  -output "$APP/Contents/MacOS/MonitorGlow" "$APP/Contents/MacOS/MonitorGlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" # 由 scripts/make-icon.sh 產生
# 預設 ad-hoc 簽章；scripts/local.env 可設 CODESIGN_IDENTITY，讓螢幕錄製權限不因重新打包而失效
[ -f scripts/local.env ] && source scripts/local.env
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "完成：$APP"
