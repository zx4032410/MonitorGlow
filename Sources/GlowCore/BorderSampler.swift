/// 從縮小後的 BGRA 畫面算出每顆燈珠的顏色。
public struct BorderSampler: Sendable {
    public var layout: StripLayout
    /// 取樣邊框的厚度，佔寬或高的比例
    public var depth: Double

    public init(layout: StripLayout, depth: Double = 0.08) {
        self.layout = layout; self.depth = depth
    }

    /// inset：要略過的黑邊（像素），左右、上下對稱
    public func colors(bgra: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
                       inset: Inset = .none) -> [RGB] {
        precondition(width > 0 && height > 0 && bytesPerRow >= width * 4)
        precondition(bgra.count >= bytesPerRow * (height - 1) + width * 4)
        let ix = min(max(inset.x, 0), (width - 1) / 2), iy = min(max(inset.y, 0), (height - 1) / 2)
        let w = width - ix * 2, h = height - iy * 2
        let dx = max(1, Int(Double(w) * depth)), dy = max(1, Int(Double(h) * depth))

        func average(_ xs: Range<Int>, _ ys: Range<Int>) -> RGB {
            var r = 0, g = 0, b = 0
            for y in ys {
                for x in xs {
                    let o = (y + iy) * bytesPerRow + (x + ix) * 4
                    b += Int(bgra[o]); g += Int(bgra[o + 1]); r += Int(bgra[o + 2])
                }
            }
            let n = xs.count * ys.count
            return RGB(UInt8(r / n), UInt8(g / n), UInt8(b / n))
        }
        /// 把長度 total 均分成 n 格的第 i 格，至少一個像素
        func slice(_ i: Int, _ n: Int, _ total: Int) -> Range<Int> {
            let a = min(i * total / n, total - 1)
            return a..<min(max((i + 1) * total / n, a + 1), total)
        }

        // 先以「左下→左上→右上→右下」排好，需要時整條反轉
        let left = (0..<layout.left).map { average(0..<dx, slice(layout.left - 1 - $0, layout.left, h)) }
        let top = (0..<layout.top).map { average(slice($0, layout.top, w), 0..<dy) }
        let right = (0..<layout.right).map { average((w - dx)..<w, slice($0, layout.right, h)) }
        let all = left + top + right
        return layout.startsAtLeft ? all : all.reversed()
    }
}
