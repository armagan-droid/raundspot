import Foundation
import Testing
@testable import SoloCapture

@Suite("Capture clock and frame rate (specs/02)") struct CaptureTests {
    @Test func hostClockIsMonotonicMs() {
        let a = HostClock.nowMs, b = HostClock.nowMs
        #expect(b >= a && a > 0)
        #expect(HostClock.ms(fromHostTicks: 0) == 0)
    }

    @Test func frameRateOverTheWindow() {
        var m = FrameRateMeter()
        #expect(m.fps == 0)
        for i in 0..<61 { m.record(Double(i) * 1000 / 30) }
        #expect(abs(m.fps - 30) < 0.01)
        for i in 0..<20 { m.record(2000 + Double(i) * 1000 / 15) }
        #expect(abs(m.fps - 15) < 0.01)
    }

    @Test func clocks() {
        let m = ManualClock(startMs: 500)
        #expect(m.nowMs == 500)
        m.advance(byMs: 33.5)
        #expect(m.nowMs == 533.5)
        let live = LiveClock.shared.nowMs
        #expect(abs(live - HostClock.nowMs) < 1000)
    }

    /// AC-2.2 (audio side): a cue's host time round-trips through the scheduling conversion.
    @Test func hostTimeConversionRoundTrips() {
        for ms in [0.0, 1.5, 12_345.678, HostClock.nowMs + 80] {
            #expect(abs(HostClock.ms(fromHostTicks: HostClock.hostTicks(fromMs: ms)) - ms) < 0.001)
        }
    }

    @Test func cueTiming() {
        let file = CueTiming.delay(onsetMs: 12, outputLatencyMs: 20, ioBufferMs: 5, bluetooth: false)
        #expect(file.ms == 37 && !file.approximate)
        #expect(CueTiming.delay(onsetMs: 12, outputLatencyMs: 150, ioBufferMs: 5, bluetooth: true).approximate)
        let tts = CueTiming.delay(onsetMs: nil, outputLatencyMs: 20, ioBufferMs: 5, bluetooth: false)
        #expect(tts.ms == 0 && tts.approximate)
    }

    @Test func cueManifest() throws {
        let ok = try CueManifest.parse(Data(#"{"formatVersion": 1, "cues": {"strike.jab": {"file": "jab.caf", "cueOnsetMs": 12}}}"#.utf8))
        #expect(ok.cues["strike.jab"] == CueManifest.Cue(file: "jab.caf", cueOnsetMs: 12))
        for bad in [#"{"formatVersion": 2, "cues": {}}"#, #"{"formatVersion": 1, "cues": {"a": {"file": "../x.caf", "cueOnsetMs": 1}}}"#,
                    #"{"formatVersion": 1, "cues": {"a": {"file": "x.caf"}}}"#, #"{"formatVersion": 1, "cues": {}, "x": 1}"#] {
            #expect(throws: CueManifest.ParseError.self) { try CueManifest.parse(Data(bad.utf8)) }
        }
    }
}
