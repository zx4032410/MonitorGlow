import Foundation

/// 專用執行緒：HID 連線的建立、收發、關閉都在這裡，避免一幀的封包被別的指令插隊。
final class LampThread: Thread {
    private var loop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "lamp"
        qualityOfService = .userInitiated
        start()
        ready.wait()
    }

    override func main() {
        loop = CFRunLoopGetCurrent()
        // 沒有來源的 run loop 會立刻結束，放一個很久才響的計時器撐著
        RunLoop.current.add(Timer(timeInterval: 1e9, repeats: true) { _ in }, forMode: .default)
        ready.signal()
        while !isCancelled { CFRunLoopRunInMode(.defaultMode, 1e9, false) }
    }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    /// 等指令做完，最多等 timeout 秒（結束程式前收尾用）
    func performAndWait(timeout: TimeInterval, _ block: @escaping () -> Void) {
        let done = DispatchSemaphore(value: 0)
        perform { block(); done.signal() }
        _ = done.wait(timeout: .now() + timeout)
    }

    func every(_ seconds: TimeInterval, _ block: @escaping () -> Void) {
        perform {
            let t = Timer(timeInterval: seconds, repeats: true) { _ in block() }
            t.tolerance = seconds / 10
            RunLoop.current.add(t, forMode: .default)
        }
    }
}
