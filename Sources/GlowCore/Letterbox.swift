public struct Inset: Equatable, Sendable {
    public var x: Int, y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
    public static let none = Inset(x: 0, y: 0)
}

/// 找影片上下或左右的對稱黑邊。同一個結果連續出現多次才採用，避免暗場閃動。
public struct Letterbox: Sendable {
    public private(set) var current = Inset.none
    private var candidate = Inset.none
    private var hits = 0
    private let needed: Int
    private let threshold: UInt8 = 8

    public init(needed: Int = 15) { self.needed = needed }

    public mutating func update(bgra: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int) -> Inset {
        let found = detect(bgra, width, height, bytesPerRow)
        if found == candidate { hits += 1 } else { candidate = found; hits = 1 }
        if hits >= needed { current = candidate }
        return current
    }

    private func detect(_ p: UnsafeRawBufferPointer, _ w: Int, _ h: Int, _ stride: Int) -> Inset {
        func dark(_ x: Int, _ y: Int) -> Bool {
            let o = y * stride + x * 4
            return p[o] <= threshold && p[o + 1] <= threshold && p[o + 2] <= threshold
        }
        func row(_ y: Int) -> Bool { (0..<w).allSatisfy { dark($0, y) } }
        func column(_ x: Int) -> Bool { (0..<h).allSatisfy { dark(x, $0) } }
        /// 兩側都是黑的才算；超過 1/4 多半是整片暗場，不算黑邊
        func bars(_ n: Int, _ isDark: (Int) -> Bool) -> Int {
            let limit = n / 4
            var k = 0
            while k <= limit, isDark(k), isDark(n - 1 - k) { k += 1 }
            return k > limit ? 0 : k
        }
        return Inset(x: bars(w, column), y: bars(h, row))
    }
}
