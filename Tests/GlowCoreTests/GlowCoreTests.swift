import Testing
@testable import GlowCore

private func hex(_ s: String) -> [UInt8] { s.split(whereSeparator: \.isWhitespace).map { UInt8($0, radix: 16)! } }

/// 依協定格式推導的範例，序號從 2 起算
@Test func framesMatchDocument() {
    func frame(_ c: LampCommand, seq: UInt8) -> [UInt8] {
        var e = FrameEncoder()
        for _ in 2..<seq { _ = e.frame(for: .off) }
        return e.frame(for: c)
    }
    #expect(frame(.readInfo, seq: 2) == hex("52 42 06 02 82 1E"))
    #expect(frame(.brightness(127), seq: 4) == hex("52 42 07 04 87 7F A5"))
    #expect(frame(.speed(50), seq: 5) == hex("52 42 07 05 8A 32 5C"))
    #expect(frame(.sensitivity(50), seq: 6) == hex("52 42 07 06 8B 32 5E"))
    #expect(frame(.off, seq: 7) == hex("52 42 06 07 97 38"))
    #expect(frame(Segment.solid(RGB(255, 0, 0), count: 65), seq: 8) == hex("52 42 10 08 86 01 FF 00 00 41 42 00 00 00 FE B3"))
    #expect(frame(.effect(.dynamic(0)), seq: 10) == hex("52 42 08 0A 85 02 00 2D"))
    #expect(frame(.effect(.dynamic(6)), seq: 11) == hex("52 42 08 0B 85 02 06 34"))
    #expect(frame(.effect(.music(0)), seq: 12) == hex("52 42 08 0C 85 03 00 30"))
    #expect(frame(Segment.solid(RGB(255, 0, 0), count: 0), seq: 13) == hex("52 42 0B 0D 86 01 FF 00 00 FE 30"))
}

@Test func syncFrameSplitsInto64ByteReports() {
    let segs = (1...34).map { Segment(first: UInt8($0), color: RGB(1, 2, 3), last: UInt8($0)) }
    var e = FrameEncoder(); let f = e.frame(for: .sync(segs))
    #expect(f.count == 177)
    #expect(Array(f.prefix(6)) == [0x53, 0x43, 0x00, 0xB1, 0x02, 0x80])
    #expect(f.last == f.dropLast().reduce(0, &+))
    var e2 = FrameEncoder(); let r = e2.reports(for: .sync(segs))
    #expect(r.count == 3 && r.allSatisfy { $0.count == 64 })
    #expect(Array(r.joined().prefix(177)) == f)
}

@Test func sequenceStaysIn1To254() {
    var e = FrameEncoder(); var seqs: [UInt8] = []
    for _ in 0..<300 { seqs.append(e.frame(for: .off)[3]) }
    #expect(seqs[0] == 2 && seqs.max() == 254 && seqs.min() == 1)
}

@Test func powerLimitKeepsSumUnder255() {
    let c = RGB(255, 255, 255).powerLimited
    #expect(c == RGB(85, 85, 85))
    #expect(RGB(255, 0, 0).powerLimited == RGB(255, 0, 0))
    #expect(Segment.encode([RGB(255, 255, 255)])[0].color == c)
}

@Test func brightnessHasFloor() {
    #expect(LampCommand.brightness(0).payload == [5])
}

@Test func infoParsingRejectsStaleReplies() {
    var b = [UInt8](repeating: 0, count: 64)
    b.replaceSubrange(0..<5, with: [0x52, 0x42, 24, 9, 0x82])
    b.replaceSubrange(5..<9, with: [0x00, 0x1c, 0x0a, 27])
    b[11] = 65; b[21] = 1; b[22] = 8; b[23] = 2
    let i = DeviceInfo(report: b, sequence: 9)
    #expect(i?.model == "001c0a" && i?.inches == 27 && i?.ledCount == 65)
    #expect(i?.firmware == [1, 8, 2] && i?.supportsSyncFrame == true)
    #expect(DeviceInfo(report: b, sequence: 8) == nil)
    b[4] = 0x87
    #expect(DeviceInfo(report: b, sequence: 9) == nil)
}

@Test func segmentsMergeSameColors() {
    let red = RGB(255, 0, 0), blue = RGB(0, 0, 255)
    #expect(Segment.encode([red, red, blue]) == [
        Segment(first: 1, color: red, last: 2), Segment(first: 3, color: blue, last: 3),
    ])
    #expect(Segment.encode([]).isEmpty)
}

/// 左半紅、右半藍，最上面一列綠
private func sample(_ layout: StripLayout) -> [RGB] {
    let w = 40, h = 20
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let c = y == 0 ? RGB(0, 255, 0) : (x < w / 2 ? RGB(255, 0, 0) : RGB(0, 0, 255))
        let o = (y * w + x) * 4
        px[o] = c.b; px[o + 1] = c.g; px[o + 2] = c.r
    } }
    return px.withUnsafeBytes {
        BorderSampler(layout: layout, depth: 0.05).colors(bgra: $0, width: w, height: h, bytesPerRow: w * 4)
    }
}

@Test func samplerOrderAndFlip() {
    let l = sample(StripLayout(left: 2, top: 4, right: 2, startsAtLeft: true))
    #expect(l.count == 8)
    #expect(l[0] == RGB(255, 0, 0))                              // 左下
    #expect(l[2...5].allSatisfy { $0 == RGB(0, 255, 0) })        // 上緣
    #expect(l[7] == RGB(0, 0, 255))                              // 右下
    let r = sample(StripLayout(left: 2, top: 4, right: 2, startsAtLeft: false))
    #expect(r == l.reversed())
}

@Test func moreLedsThanPixelsDoesNotCrash() {
    #expect(sample(StripLayout(left: 50, top: 100, right: 50, startsAtLeft: true)).count == 200)
}

@Test func smoothingEndpoints() {
    let a = RGB(0, 0, 0), b = RGB(200, 100, 50)
    #expect(a.mixed(to: b, 1) == b)
    #expect(a.mixed(to: b, 0) == a)
    #expect(a.mixed(to: b, 0.5) == RGB(100, 50, 25))
}

@Test func layoutMatchesKnownStrips() {
    let l = StripLayout(ledCount: 65, aspect: 16.0 / 9, startsAtLeft: false)
    #expect(l == StripLayout(left: 17, top: 31, right: 17, startsAtLeft: false))
    #expect(StripLayout(ledCount: 54, aspect: 16.0 / 9, startsAtLeft: false).top == 26) // 24 吋
    #expect(StripLayout(ledCount: 77, aspect: 16.0 / 9, startsAtLeft: false).top == 37) // 32 吋
}

@Test func vividKeepsGrayAndCutsNearBlack() {
    #expect(RGB(100, 100, 100).vivid(2) == RGB(100, 100, 100))
    #expect(RGB(12, 3, 0).vivid(1) == .black)
    #expect(RGB(200, 100, 100).vivid(1.5).r > 200)
}

/// 上下各 bar 列黑、中間白
private func letterboxed(_ bar: Int, _ use: (UnsafeRawBufferPointer, Int, Int) -> Void) {
    let w = 32, h = 20
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h where y < bar || y >= h - bar { for i in 0..<(w * 4) { px[y * w * 4 + i] = 0 } }
    px.withUnsafeBytes { use($0, w, h) }
}

@Test func letterboxNeedsRepeatedFrames() {
    var box = Letterbox(needed: 3)
    letterboxed(3) { p, w, h in
        #expect(box.update(bgra: p, width: w, height: h, bytesPerRow: w * 4) == .none)
        #expect(box.update(bgra: p, width: w, height: h, bytesPerRow: w * 4) == .none)
        let inset = box.update(bgra: p, width: w, height: h, bytesPerRow: w * 4)
        #expect(inset == Inset(x: 0, y: 3))
        let c = BorderSampler(layout: StripLayout(left: 2, top: 4, right: 2, startsAtLeft: true), depth: 0.05)
            .colors(bgra: p, width: w, height: h, bytesPerRow: w * 4, inset: inset)
        #expect(c.allSatisfy { $0 == RGB(255, 255, 255) })
    }
}

@Test func allBlackIsNotLetterbox() {
    var box = Letterbox(needed: 1)
    letterboxed(10) { p, w, h in
        #expect(box.update(bgra: p, width: w, height: h, bytesPerRow: w * 4) == .none)
    }
}
