/// 允許送給燈條的指令白名單。不在這裡的指令，程式沒有辦法送出。
/// 協定與驗證狀態見 docs/PROTOCOL.md。
public enum LampCommand: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        case dynamic(Int), music(Int) // 0...6，由燈條韌體執行
    }

    case readInfo
    case off
    /// 靜態色用的分段，最多 `Segment.maxPerRBFrame` 段
    case segments([Segment])
    /// 畫面同步用的分段，一幀一包
    case sync([Segment])
    case brightness(UInt8)
    case effect(Effect)
    /// 0...100，越大越快
    case speed(Int)
    /// 0...100
    case sensitivity(Int)

    var action: UInt8 {
        switch self {
        case .sync: 0x80
        case .readInfo: 0x82
        case .effect: 0x85
        case .segments: 0x86
        case .brightness: 0x87
        case .speed: 0x8A
        case .sensitivity: 0x8B
        case .off: 0x97
        }
    }

    var payload: [UInt8] {
        switch self {
        case .readInfo, .off: []
        case .segments(let s), .sync(let s): s.flatMap(\.bytes)
        case .brightness(let v): [max(5, v)]                       // 官方下限 5
        case .effect(.dynamic(let i)): [2, UInt8(min(max(i, 0), 6))]
        case .effect(.music(let i)): [3, UInt8(min(max(i, 0), 6))]
        case .speed(let v): [UInt8(100 - min(max(v, 0), 100))]      // 裝置端是反過來的
        case .sensitivity(let v): [UInt8(min(max(v, 0), 100))]
        }
    }

    var usesSyncFrame: Bool { if case .sync = self { true } else { false } }
}

/// 連續同色的燈珠，編號從 1 起算、含頭含尾。
public struct Segment: Equatable, Sendable {
    public static let maxPerRBFrame = 11 // 55 bytes，整包不超過一個 report
    public let first: UInt8, color: RGB, last: UInt8

    public init(first: UInt8, color: RGB, last: UInt8) {
        self.first = first; self.color = color; self.last = last
    }

    var bytes: [UInt8] { [first, color.r, color.g, color.b, last] }

    /// 合併相鄰同色；一律先限流，避免 USB 供電超載。
    public static func encode(_ colors: [RGB]) -> [Segment] {
        precondition(colors.count <= 254)
        let safe = colors.map(\.powerLimited)
        var out: [Segment] = []
        var start = 0
        while start < safe.count {
            var end = start
            while end + 1 < safe.count, safe[end + 1] == safe[start] { end += 1 }
            out.append(Segment(first: UInt8(start + 1), color: safe[start], last: UInt8(end + 1)))
            start = end + 1
        }
        return out
    }

    /// 整條單色：第 1～count 顆上色，其後全黑。
    public static func solid(_ color: RGB, count: Int) -> LampCommand {
        let c = color.powerLimited
        guard (1..<254).contains(count) else { return .segments([Segment(first: 1, color: c, last: 254)]) }
        return .segments([
            Segment(first: 1, color: c, last: UInt8(count)),
            Segment(first: UInt8(count + 1), color: .black, last: 254),
        ])
    }
}
