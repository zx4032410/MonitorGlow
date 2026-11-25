import AppKit
import GlowCore
import GlowHID

func usage() -> Never {
    print("""
    用法：
      glow list                列出是否接上（不開啟裝置）
      glow info                讀型號、燈數、韌體
      glow color R G B         整條單色
      glow led N R G B         只亮第 N 顆（1 起算）
      glow ends                頭紅、中綠、尾藍（測線序與方向）
      glow syncends            同上但用同步封包，頭藍、中綠、尾紅，持續 60 秒
      glow brightness 5-255
      glow dynamic|music 0-6   燈條內建效果
      glow off
    """)
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { usage() }
if cmd == "list" { print(LampDevice.isPresent() ? "燈條已接上" : "找不到燈條"); exit(0) }

guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.robobloq.synclight").isEmpty else {
    print("SyncLight 正在執行，請先結束它（兩支程式會搶同一個裝置）。"); exit(1)
}

func byte(_ i: Int) -> UInt8 {
    guard args.count > i, let v = UInt8(args[i]) else { usage() }
    return v
}

do {
    let lamp = try LampDevice()
    switch cmd {
    case "info":
        let i = try lamp.readInfo()
        print("型號 \(i.model)　\(i.inches) 吋　\(i.ledCount) 顆燈　韌體 \(i.firmware.map(String.init).joined(separator: "."))")
    case "color":
        let n = try lamp.readInfo().ledCount
        try lamp.send(Segment.solid(RGB(byte(1), byte(2), byte(3)), count: n))
    case "led":
        let n = try lamp.readInfo().ledCount, k = Int(byte(1))
        guard (1...max(1, n)).contains(k) else { print("燈號要在 1～\(n)"); exit(2) }
        var colors = [RGB](repeating: .black, count: n)
        colors[k - 1] = RGB(byte(2), byte(3), byte(4))
        try lamp.send(.segments(Segment.encode(colors)))
    case "ends":
        // 頭 5 顆紅、中間 5 顆綠、尾 5 顆藍，一次看線序與方向
        let n = try lamp.readInfo().ledCount, mid = n / 2 - 2
        var colors = [RGB](repeating: .black, count: n)
        for k in 0..<5 {
            colors[k] = RGB(255, 0, 0)
            colors[mid + k] = RGB(0, 255, 0)
            colors[n - 1 - k] = RGB(0, 0, 255)
        }
        try lamp.send(.segments(Segment.encode(colors)))
    case "syncends":
        // 用同步專用封包：頭藍、中綠、尾紅，每秒 10 次持續 60 秒
        let n = try lamp.readInfo().ledCount, mid = n / 2 - 2
        var colors = [RGB](repeating: .black, count: n)
        for k in 0..<5 {
            colors[k] = RGB(0, 0, 255)
            colors[mid + k] = RGB(0, 255, 0)
            colors[n - 1 - k] = RGB(255, 0, 0)
        }
        let segments = Segment.encode(colors)
        for _ in 0..<600 {
            try lamp.send(.sync(segments))
            Thread.sleep(forTimeInterval: 0.1)
        }
    case "brightness": try lamp.send(.brightness(byte(1)))
    case "dynamic": try lamp.send(.effect(.dynamic(Int(byte(1)))))
    case "music": try lamp.send(.effect(.music(Int(byte(1)))))
    case "off": try lamp.send(.off)
    default: usage()
    }
    print("已送出")
} catch {
    print("失敗：\(error)"); exit(1)
}
