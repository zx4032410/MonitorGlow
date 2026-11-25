import GlowHID
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel

    private var connected: Bool { if case .connected = model.link { true } else { false } }

    private var status: String {
        switch model.link {
        case .searching: "找不到燈條，請檢查 USB"
        case .blockedBySyncLight: "SyncLight 正在執行，請先結束它"
        case .connected(let i): "已連線・\(i.inches) 吋・\(i.ledCount) 顆燈"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("螢幕背光").font(.headline)
                    Text(status).font(.caption).foregroundStyle(connected ? Color.secondary : Color.orange)
                }
                Spacer()
                Toggle("電源", isOn: $model.isOn).toggleStyle(.switch).labelsHidden()
            }

            Group {
                HStack(spacing: 8) {
                    ForEach(Mode.allCases) { m in modeButton(m) }
                }
                slider("亮度", $model.brightness, 0.02...1)
                options
            }
            .disabled(!connected || !model.isOn)

            if let msg = model.screenMessage {
                Text(msg).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Toggle("登入時啟動", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("結束") { NSApp.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func modeButton(_ m: Mode) -> some View {
        let selected = model.mode == m
        return Button { model.mode = m } label: {
            VStack(spacing: 5) {
                Image(systemName: m.symbol).font(.system(size: 16)).frame(height: 20)
                Text(m.title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? Color.accentColor : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var options: some View {
        switch model.mode {
        case .screen:
            slider("反應", $model.response, 0...1)
            slider("鮮豔", $model.vividness, 1...2) { model.vividnessEdited() }
            Toggle("略過影片黑邊", isOn: $model.skipBars)
            Toggle("左右對調", isOn: $model.startsAtLeft)
        case .solid:
            HStack(spacing: 6) {
                ForEach([0.0, 0.07, 0.13, 0.33, 0.5, 0.62, 0.77, 0.9], id: \.self) { h in
                    Button { model.hue = h; if model.saturation < 0.5 { model.saturation = 1 } } label: {
                        Circle().fill(Color(hue: h, saturation: 1, brightness: 1)).frame(width: 24, height: 24)
                    }.buttonStyle(.plain)
                }
                Button { model.saturation = 0 } label: {
                    Circle().fill(.white).overlay(Circle().stroke(.secondary)).frame(width: 24, height: 24)
                }.buttonStyle(.plain)
            }
            slider("色相", $model.hue, 0...1)
            slider("濃淡", $model.saturation, 0...1)
        case .dynamic:
            numbers($model.dynamicIndex)
            slider("速度", $model.speed, 0...100)
        case .music:
            numbers($model.musicIndex)
            slider("靈敏度", $model.sensitivity, 0...100)
            Text("用線控器上的麥克風收音，播放音樂時燈會跟著跳").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func numbers(_ value: Binding<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(0..<7, id: \.self) { Text("\($0 + 1)").tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        onEnd: @escaping () -> Void = {}) -> some View {
        HStack {
            Text(title).frame(width: 48, alignment: .leading)
            Slider(value: value, in: range) { editing in if !editing { onEnd() } }
        }
    }
}
