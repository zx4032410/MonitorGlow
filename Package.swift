// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MonitorGlow",
    platforms: [.macOS(.v14)],
    targets: [
        // 純邏輯：封包組裝、邊框取色、平滑，不碰硬體，可單獨測試
        .target(name: "GlowCore"),
        // USB HID 連線
        .target(name: "GlowHID", dependencies: ["GlowCore"]),
        // 實機測試用命令列工具
        .executableTarget(name: "glow", dependencies: ["GlowCore", "GlowHID"]),
        // 選單列 App
        .executableTarget(name: "MonitorGlow", dependencies: ["GlowCore", "GlowHID"]),
        .testTarget(name: "GlowCoreTests", dependencies: ["GlowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
