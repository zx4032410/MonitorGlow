import CoreMedia
import GlowCore
import ScreenCaptureKit

/// 擷取縮小後的主螢幕畫面，換算成每顆燈珠的顏色。
final class ScreenSampler: NSObject, SCStreamOutput, SCStreamDelegate {
    private let queue = DispatchQueue(label: "capture", qos: .userInitiated)
    private var stream: SCStream?
    private var sampler: BorderSampler
    private var letterbox = Letterbox()
    private let skipBars: Bool
    private let vividness: Double
    private let onColors: ([RGB]) -> Void
    private let onStop: () -> Void

    init(layout: StripLayout, vividness: Double, skipBars: Bool,
         onColors: @escaping ([RGB]) -> Void, onStop: @escaping () -> Void) {
        sampler = BorderSampler(layout: layout)
        self.vividness = vividness
        self.skipBars = skipBars
        self.onColors = onColors
        self.onStop = onStop
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let main = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == main }) ?? content.displays.first else {
            throw CocoaError(.featureUnsupported)
        }
        let config = SCStreamConfiguration()
        config.width = 192
        config.height = max(1, 192 * display.height / max(1, display.width))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = false
        let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() {
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let px = CMSampleBufferGetImageBuffer(buffer) else { return }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px), row = CVPixelBufferGetBytesPerRow(px)
        let bytes = UnsafeRawBufferPointer(start: base, count: row * h)
        let inset = skipBars ? letterbox.update(bgra: bytes, width: w, height: h, bytesPerRow: row) : .none
        let colors = sampler.colors(bgra: bytes, width: w, height: h, bytesPerRow: row, inset: inset)
        onColors(colors.map { $0.vivid(vividness) })
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop() }
}
