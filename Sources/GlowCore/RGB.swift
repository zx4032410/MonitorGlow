public struct RGB: Equatable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    public static let black = RGB(0, 0, 0)

    /// 三色總和超過 255 時等比縮小（官方預設開啟的 USB 供電保護）。
    public var powerLimited: RGB {
        let sum = Int(r) + Int(g) + Int(b)
        guard sum > 255 else { return self }
        func scale(_ v: UInt8) -> UInt8 { UInt8(Int(v) * 255 / sum) }
        return RGB(scale(r), scale(g), scale(b))
    }

    /// 拉開與灰階的距離讓顏色更鮮豔；1 = 不變。接近黑的顏色直接當黑，避免暗場泛光。
    public func vivid(_ amount: Double) -> RGB {
        if max(r, g, b) <= 12 { return .black }
        let gray = (Double(r) + Double(g) + Double(b)) / 3
        func push(_ v: UInt8) -> UInt8 { UInt8(min(max(gray + (Double(v) - gray) * amount, 0), 255)) }
        return RGB(push(r), push(g), push(b))
    }

    /// 指數平滑：t = 1 直接採用新色，越小越柔和。
    public func mixed(to new: RGB, _ t: Double) -> RGB {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            let k = min(max(t, 0), 1)
            return UInt8((Double(a) + (Double(b) - Double(a)) * k).rounded())
        }
        return RGB(mix(r, new.r), mix(g, new.g), mix(b, new.b))
    }
}
