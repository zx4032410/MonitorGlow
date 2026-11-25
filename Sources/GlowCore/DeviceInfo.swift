/// `readInfo` 的回應。刻意不解析 uuid，用不到。
public struct DeviceInfo: Equatable, Sendable {
    public let model: String, inches: Int, ledCount: Int
    public let firmware: [Int]

    /// 序號與 action 都要對上，避免誤用舊回應。
    public init?(report b: [UInt8], sequence: UInt8) {
        guard b.count >= 24, b[0] == 0x52, b[1] == 0x42, b[3] == sequence, b[4] == 0x82 else { return nil }
        model = b[5...7].map { $0 < 16 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        inches = Int(b[8])
        ledCount = Int(b[11])
        firmware = b[21...23].map(Int.init)
    }

    /// 官方只在韌體大於 1.0.2 時用 SC 同步訊框
    public var supportsSyncFrame: Bool { [1, 0, 2].lexicographicallyPrecedes(firmware) }
}
