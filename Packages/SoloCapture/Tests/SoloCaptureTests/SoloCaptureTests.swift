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
}
