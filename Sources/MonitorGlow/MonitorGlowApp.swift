import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        let model = AppModel.shared
        if let dir = ProcessInfo.processInfo.environment["MONITORGLOW_SNAPSHOT"] { snapshot(model, to: dir) }
    }

    /// 開發用：把各模式的面板畫成 PNG 後結束
    @MainActor private func snapshot(_ model: AppModel, to dir: String) {
        func draw(_ name: String) {
            let v = NSHostingView(rootView: PanelView(model: model).background(Color(nsColor: .windowBackgroundColor)))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: v.fittingSize), styleMask: .borderless, backing: .buffered, defer: false)
            w.contentView = v
            v.layoutSubtreeIfNeeded()
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            model.isOn = true
            for m in [Mode.solid, .dynamic, .music] {
                model.mode = m
                try? await Task.sleep(for: .seconds(2))
                draw(m.rawValue)
            }
            model.isOn = false // 不觸發螢幕錄製授權
            model.mode = .screen
            try? await Task.sleep(for: .seconds(1))
            draw("screen")
            NSApp.terminate(nil)
        }
    }
    func applicationWillTerminate(_ n: Notification) { AppModel.shared.shutdown() }
}

@main
struct MonitorGlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(systemName: model.isOn ? "light.strip.2.fill" : "light.strip.2")
        }
        .menuBarExtraStyle(.window)
    }
}
