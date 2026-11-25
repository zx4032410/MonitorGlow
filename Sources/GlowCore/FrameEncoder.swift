/// 把指令組成訊框，再切成 64 bytes 的 HID report（不含 report ID，不足補零）。
/// RB：'R' 'B' 總長u8 序號 action payload 加總
/// SC：'S' 'C' 總長u16BE 序號 action payload 加總（只給畫面同步）
public struct FrameEncoder: Sendable {
    public static let reportSize = 64
    public private(set) var sequence: UInt8 = 1

    public init() {}

    public mutating func frame(for command: LampCommand) -> [UInt8] {
        sequence = sequence >= 254 ? 1 : sequence + 1
        let payload = command.payload
        var frame: [UInt8]
        if command.usesSyncFrame {
            let total = payload.count + 7
            frame = [0x53, 0x43, UInt8(total >> 8), UInt8(total & 0xFF), sequence, command.action]
        } else {
            let total = payload.count + 6
            precondition(total <= Self.reportSize, "RB 訊框必須放得進一個 report")
            frame = [0x52, 0x42, UInt8(total), sequence, command.action]
        }
        frame += payload
        frame.append(frame.reduce(0, &+))
        return frame
    }

    public mutating func reports(for command: LampCommand) -> [[UInt8]] {
        let f = frame(for: command)
        return stride(from: 0, to: f.count, by: Self.reportSize).map {
            let chunk = Array(f[$0..<min($0 + Self.reportSize, f.count)])
            return chunk + [UInt8](repeating: 0, count: Self.reportSize - chunk.count)
        }
    }
}
