import AppKit
import GlowCore
import GlowHID

enum LinkState: Equatable { case searching, blockedBySyncLight, connected(DeviceInfo) }

/// 連線與送指令。公開方法可從任何執行緒呼叫，實際動作都排到 LampThread。
final class LampController {
    private let thread = LampThread()
    private var device: LampDevice?
    private var target: [RGB] = []
    private var shown: [RGB] = []
    private var smoothing = 0.5
    private var streaming = false

    /// 在主執行緒呼叫
    var onState: ((LinkState) -> Void)?

    func start() {
        thread.perform { self.checkLink() }
        thread.every(2) { self.checkLink() }
        thread.every(1.0 / 30) { self.tick() }
    }

    private func report(_ s: LinkState) { DispatchQueue.main.async { self.onState?(s) } }

    private func checkLink() {
        let syncLight = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.robobloq.synclight").isEmpty
        if syncLight {
            device = nil
            report(.blockedBySyncLight)
            return
        }
        guard device == nil else { return }
        do {
            let d = try LampDevice()
            let info = try d.readInfo()
            d.onRemoved = { [weak self] in self?.lost() }
            device = d
            report(.connected(info))
        } catch {
            report(.searching)
        }
    }

    private func lost() {
        // 不能在 device 自己的回呼裡釋放它，排到下一輪
        thread.perform { self.device = nil; self.report(.searching) }
    }

    private func write(_ commands: [LampCommand]) {
        guard let device else { return }
        do {
            for c in commands {
                try device.send(c)
                // 設定類指令之間留一點空檔給韌體；同步幀不能等
                if case .sync = c {} else { Thread.sleep(forTimeInterval: 0.005) }
            }
        } catch { lost() }
    }

    func send(_ commands: LampCommand...) {
        thread.perform { self.streaming = false; self.write(commands) }
    }

    /// 亮度、速度這類不影響目前模式的設定
    func adjust(_ command: LampCommand) { thread.perform { self.write([command]) } }

    func beginStream(smoothing: Double) {
        thread.perform { self.streaming = true; self.smoothing = smoothing; self.target = []; self.shown = [] }
    }

    func endStream() { thread.perform { self.streaming = false } }

    func setSmoothing(_ v: Double) { thread.perform { self.smoothing = v } }

    func stream(_ colors: [RGB]) { thread.perform { self.target = colors } }

    /// 每 1/30 秒往目標色靠近一步；畫面靜止且已到位就不送，省 CPU 與 USB。
    private func tick() {
        guard streaming, device != nil, !target.isEmpty else { return }
        if shown.count != target.count { shown = [RGB](repeating: .black, count: target.count) }
        else if shown == target { return }
        shown = zip(shown, target).map { old, new in
            let m = old.mixed(to: new, smoothing)
            // 四捨五入可能讓顏色停在目標旁邊一格，直接對齊
            return m == old ? new : m
        }
        write([.sync(Segment.encode(shown))])
    }

    func shutdown() {
        thread.performAndWait(timeout: 1) {
            self.streaming = false
            self.write([.off])
            self.device = nil
        }
    }
}
