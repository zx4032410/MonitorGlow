#!/bin/zsh
# 打包並安裝到 /Applications（固定位置，螢幕錄製權限與登入啟動才不會亂掉）
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x MonitorGlow 2>/dev/null || true
rm -rf "/Applications/螢幕背光.app"
cp -R "build/螢幕背光.app" /Applications/
open "/Applications/螢幕背光.app"
