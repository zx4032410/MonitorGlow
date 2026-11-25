#!/bin/zsh
# 從 Resources/icon-source.png（gpt-image 生成的原稿）重新產生 Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swift scripts/make-icon.swift Resources/icon-source.png "$TMP/icon.png"
cp "$TMP/icon.png" docs/icon-preview.png

# iconutil 需要的各種尺寸：16、32、128、256、512 各一份 1x 和 2x
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for px in 16 32 128 256 512; do
    sips -z $px $px "$TMP/icon.png" --out "$SET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) "$TMP/icon.png" --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "完成：Resources/AppIcon.icns"
