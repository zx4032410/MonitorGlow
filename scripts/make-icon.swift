// 把 AI 生成的圖示原稿（中間是深色圓角方形、外圍是白底）
// 裁成 macOS 標準圖示：1024 畫布、824 方塊、圓角、透明背景、淡淡陰影
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let rep = NSBitmapImageRep(data: src.tiffRepresentation!) else {
    print("用法：swift make-icon.swift 原稿.png 輸出.png"); exit(1)
}

// 1. 找出深色方塊的範圍：背景是白色，方塊是深色
var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = 0, maxY = 0
for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
    for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        if lum < 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    }
}
let inset = 3  // 去掉邊緣的反鋸齒雜邊
// 底部的陰影也是深色，會讓範圍偏高；方塊本來就是正方形，所以以寬度為準、從上緣往下取
let side = maxX - minX - 2 * inset
let crop = NSRect(x: minX + inset, y: minY + inset, width: side, height: side)
print("方塊範圍：\(Int(crop.minX)),\(Int(crop.minY)) \(Int(crop.width))×\(Int(crop.height))")
guard let cg = rep.cgImage?.cropping(to: crop) else { print("裁切失敗"); exit(1) }

// 2. 畫到 Apple 圖示網格：1024 畫布中 824 的方塊，圓角半徑約 185
let size = 1024, tile: CGFloat = 824, radius: CGFloat = 185
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let origin = (CGFloat(size) - tile) / 2
let rect = CGRect(x: origin, y: origin + 6, width: tile, height: tile)  // 稍微上移，留空間給陰影
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor(white: 0.06, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.addPath(path)
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(cg, in: rect)

let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("完成：\(args[2])")
