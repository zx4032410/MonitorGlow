/// 燈條在螢幕三邊的燈珠數（從正面看）。
public struct StripLayout: Equatable, Sendable {
    public var left: Int, top: Int, right: Int
    /// true：第 1 顆在左下（左→上→右）；false：第 1 顆在右下（右→上→左）
    public var startsAtLeft: Bool

    public init(left: Int, top: Int, right: Int, startsAtLeft: Bool) {
        self.left = left; self.top = top; self.right = right; self.startsAtLeft = startsAtLeft
    }

    /// 依總燈數與螢幕長寬比推算三邊配置；27 吋 65 顆會得到 17/31/17。
    public init(ledCount: Int, aspect: Double, startsAtLeft: Bool) {
        let top = Int(Double(ledCount) * aspect / (aspect + 2))
        let side = max(0, (ledCount - top) / 2)
        self.init(left: side, top: ledCount - side * 2, right: side, startsAtLeft: startsAtLeft)
    }

    public var count: Int { left + top + right }
}
