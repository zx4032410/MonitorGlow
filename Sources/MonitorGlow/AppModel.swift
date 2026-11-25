import AppKit
import GlowCore
import GlowHID
import ServiceManagement
import SwiftUI

enum Mode: String, CaseIterable, Identifiable {
    case screen, solid, dynamic, music
    var id: String { rawValue }
    var title: String {
        switch self {
        case .screen: "螢幕同步"
        case .solid: "單色"
        case .dynamic: "燈效"
        case .music: "音樂"
        }
    }
    var symbol: String {
        switch self {
        case .screen: "display"
        case .solid: "circle.fill"
        case .dynamic: "sparkles"
        case .music: "music.note"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private let store = UserDefaults.standard
    private let lamp = LampController()
    private var sampler: ScreenSampler?
    private var generation = 0
    private var asleep = false

    @Published var link: LinkState = .searching
    @Published var screenMessage: String?

    @Published var isOn: Bool { didSet { save("isOn", isOn); apply() } }
    @Published var mode: Mode { didSet { save("mode", mode.rawValue); apply() } }
    @Published var brightness: Double { didSet { save("brightness", brightness); sendBrightness() } }
    @Published var hue: Double { didSet { save("hue", hue); if mode == .solid { apply() } } }
    @Published var saturation: Double { didSet { save("saturation", saturation); if mode == .solid { apply() } } }
    @Published var dynamicIndex: Int { didSet { save("dynamicIndex", dynamicIndex); apply() } }
    @Published var musicIndex: Int { didSet { save("musicIndex", musicIndex); apply() } }
    @Published var speed: Double { didSet { save("speed", speed); lamp.adjust(.speed(Int(speed))) } }
    @Published var sensitivity: Double { didSet { save("sensitivity", sensitivity); lamp.adjust(.sensitivity(Int(sensitivity))) } }
    /// 0 柔和 … 1 即時
    @Published var response: Double { didSet { save("response", response); lamp.setSmoothing(smoothing) } }
    @Published var vividness: Double { didSet { save("vividness", vividness) } }
    @Published var skipBars: Bool { didSet { save("skipBars", skipBars); if mode == .screen { apply() } } }
    @Published var startsAtLeft: Bool { didSet { save("startsAtLeft", startsAtLeft); if mode == .screen { apply() } } }

    private var smoothing: Double { 0.08 + response * 0.82 }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "isOn": true, "mode": Mode.solid.rawValue, "brightness": 0.6, "hue": 0.6, "saturation": 0.8,
            "dynamicIndex": 0, "musicIndex": 0, "speed": 50.0, "sensitivity": 50.0,
            "response": 0.5, "vividness": 1.3, "skipBars": true, "startsAtLeft": false,
        ])
        isOn = d.bool(forKey: "isOn")
        mode = Mode(rawValue: d.string(forKey: "mode") ?? "") ?? .solid
        brightness = d.double(forKey: "brightness")
        hue = d.double(forKey: "hue")
        saturation = d.double(forKey: "saturation")
        dynamicIndex = d.integer(forKey: "dynamicIndex")
        musicIndex = d.integer(forKey: "musicIndex")
        speed = d.double(forKey: "speed")
        sensitivity = d.double(forKey: "sensitivity")
        response = d.double(forKey: "response")
        vividness = d.double(forKey: "vividness")
        skipBars = d.bool(forKey: "skipBars")
        startsAtLeft = d.bool(forKey: "startsAtLeft")

        lamp.onState = { state in
            MainActor.assumeIsolated { AppModel.shared.linkChanged(state) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { body() } }
        }
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observe(ws, n) { AppModel.shared.setAsleep(true) }
        }
        for n in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observe(ws, n) { AppModel.shared.setAsleep(false) }
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) {
            let m = AppModel.shared
            if m.mode == .screen { m.apply() }
        }
        lamp.start()
    }

    private func save(_ key: String, _ value: Any) { store.set(value, forKey: key) }

    private func linkChanged(_ new: LinkState) {
        guard new != link else { return }
        link = new
        guard case .connected = new else { stopScreen(); return }
        sendBrightness()
        lamp.adjust(.speed(Int(speed)))
        lamp.adjust(.sensitivity(Int(sensitivity)))
        apply()
    }

    private func setAsleep(_ v: Bool) {
        guard asleep != v else { return }
        asleep = v
        apply()
    }

    private func sendBrightness() { lamp.adjust(.brightness(UInt8(min(max(brightness, 0), 1) * 255))) }

    var solidColor: RGB {
        let c = NSColor(colorSpace: .sRGB, hue: hue, saturation: saturation, brightness: 1, alpha: 1)
        return RGB(UInt8(c.redComponent * 255), UInt8(c.greenComponent * 255), UInt8(c.blueComponent * 255))
    }

    /// 把目前設定套用到燈條
    func apply() {
        stopScreen()
        guard case .connected(let info) = link else { return }
        guard isOn, !asleep else { lamp.send(.off); return }
        switch mode {
        case .solid: lamp.send(Segment.solid(solidColor, count: info.ledCount))
        case .dynamic: lamp.send(.effect(.dynamic(dynamicIndex)))
        case .music: lamp.send(.effect(.music(musicIndex)))
        case .screen: startScreen(info)
        }
    }

    private func stopScreen() {
        generation += 1
        sampler?.stop()
        sampler = nil
        lamp.endStream()
    }

    private func startScreen(_ info: DeviceInfo) {
        screenMessage = nil
        guard info.supportsSyncFrame else { screenMessage = "這個韌體不支援螢幕同步"; return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            screenMessage = "需要「螢幕錄製」權限；授權後請重開本 App"
            return
        }
        let size = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 9)
        let layout = StripLayout(ledCount: info.ledCount, aspect: size.width / size.height, startsAtLeft: startsAtLeft)
        let mine = generation
        let lamp = lamp
        lamp.beginStream(smoothing: smoothing)
        let s = ScreenSampler(layout: layout, vividness: vividness, skipBars: skipBars,
                              onColors: { lamp.stream($0) },
                              onStop: { Task { @MainActor in AppModel.shared.retryScreen(mine) } })
        sampler = s
        Task {
            do {
                try await s.start()
                if mine != generation { s.stop() }
            } catch {
                guard mine == generation else { return }
                screenMessage = "無法擷取畫面：\(error.localizedDescription)"
                retryScreen(mine)
            }
        }
    }

    /// 擷取中斷（換螢幕、解鎖等）2 秒後重來；期間若已切換模式就放棄
    private func retryScreen(_ gen: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated { if gen == self.generation { self.apply() } }
        }
    }

    func vividnessEdited() { if mode == .screen { apply() } }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { screenMessage = "設定開機啟動失敗：\(error.localizedDescription)" }
        }
    }

    func shutdown() {
        stopScreen()
        lamp.shutdown()
    }
}
