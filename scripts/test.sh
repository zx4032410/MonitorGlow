#!/bin/zsh
# 只裝 Command Line Tools 時，SwiftPM 有時找不到 swift-testing 的巨集外掛，所以明確指定路徑
set -euo pipefail
cd "$(dirname "$0")/.."
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" "$@"
