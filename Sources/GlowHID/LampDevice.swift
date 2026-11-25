import Foundation
import GlowCore
import IOKit.hid

public enum LampError: Error, CustomStringConvertible {
    case notFound, open(IOReturn), write(IOReturn), noResponse
    public var description: String {
        switch self {
        case .notFound: "找不到燈條（1a86:fe07）"
        case .open(let r): "開啟燈條失敗：\(String(format: "0x%08x", UInt32(bitPattern: r)))"
        case .write(let r): "寫入失敗：\(String(format: "0x%08x", UInt32(bitPattern: r)))"
        case .noResponse: "燈條沒有回應"
        }
    }
}

/// 燈條連線。所有呼叫請在同一條執行緒上（輸入回呼掛在該執行緒的 run loop）。
public final class LampDevice {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var encoder = FrameEncoder()
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: FrameEncoder.reportSize)
    /// 拔線時呼叫（在建立連線的那條執行緒上）
    public var onRemoved: (() -> Void)?
    private var pending: (sequence: UInt8, info: DeviceInfo?)?

    /// 只比對廠商自訂介面（usage page 0xFF00），避開同一顆裝置上的鍵盤介面。
    private static func find() -> (IOHIDManager, IOHIDDevice)? {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(m, [
            kIOHIDVendorIDKey: 0x1a86, kIOHIDProductIDKey: 0xfe07,
            kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 1,
        ] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>,
              let d = set.first(where: {
                  IOHIDDeviceGetProperty($0, kIOHIDManufacturerKey as CFString) as? String == "ROBOBLOQ"
              }) else { return nil }
        return (m, d)
    }

    /// 只查系統登錄，不開啟裝置。
    public static func isPresent() -> Bool { find() != nil }

    public init() throws {
        guard let (m, d) = Self.find() else { throw LampError.notFound }
        manager = m; device = d
        let r = IOHIDDeviceOpen(d, 0)
        guard r == kIOReturnSuccess else { buffer.deallocate(); throw LampError.open(r) }
        IOHIDDeviceRegisterInputReportCallback(d, buffer, FrameEncoder.reportSize, { ctx, _, _, _, _, data, len in
            let me = Unmanaged<LampDevice>.fromOpaque(ctx!).takeUnretainedValue()
            me.received(Array(UnsafeBufferPointer(start: data, count: len)))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterRemovalCallback(d, { ctx, _, _ in
            Unmanaged<LampDevice>.fromOpaque(ctx!).takeUnretainedValue().onRemoved?()
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceRegisterInputReportCallback(device, buffer, FrameEncoder.reportSize, nil, nil)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, 0)
        buffer.deallocate()
    }

    private func received(_ bytes: [UInt8]) {
        guard let p = pending, p.info == nil else { return }
        if let info = DeviceInfo(report: bytes, sequence: p.sequence) { pending?.info = info }
    }

    public func send(_ command: LampCommand) throws {
        for report in encoder.reports(for: command) {
            let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, report, report.count)
            guard r == kIOReturnSuccess else { throw LampError.write(r) }
        }
    }

    public func readInfo(timeout: TimeInterval = 1) throws -> DeviceInfo {
        // 序號會在 send 內前進一格，先算好才不會漏接回應
        pending = (encoder.sequence >= 254 ? 1 : encoder.sequence + 1, nil)
        defer { pending = nil }
        try send(.readInfo)
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
            if let info = pending?.info { return info }
        }
        throw LampError.noResponse
    }
}
