import Foundation
import SoloCapture
import SoloEngine
import Testing
@testable import GymSpotSolo

/// AC-2.2: frames, the session machine and its records run on one host clock;
/// end to end with the fake camera (a landmark sequence file) on a manual clock.
@MainActor @Suite struct FakeCameraTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    static func slips() throws -> LandmarkSequence {
        let url = repo.appendingPathComponent("fixtures/snapshots/sequences/project_slips.json")
        return try LandmarkSequence.parse(data: Data(contentsOf: url)).get()
    }

    @Test func aSetRunsOnTheFakeCameraAndOneClock() async throws {
        let seq = try Self.slips()
        let pack = try #require(ExerciseCatalog.pack("slip_left"))
        let clock = ManualClock(startMs: 5_000_000)
        let source = SequenceFrameSource(sequence: seq, clock: clock)
        let model = TrainingModel(single: pack, source: source, clock: clock)
        defer { model.close() }
        let start = clock.nowMs
        await model.confirmSpace()
        #expect(model.state == .setup)

        let step = 1000 / seq.fps
        func run(until done: () -> Bool, maxMs: Double) {
            var elapsed = 0.0
            while !done(), elapsed < maxMs {
                clock.advance(byMs: step)
                elapsed += step
                source.pump()
                model.tick()
            }
        }

        run(until: { model.state == .ready }, maxMs: 30_000)
        #expect(model.state == .ready)
        // the frame the screen shows is stamped on the clock the frames are delivered on
        let shown = try #require(model.frame)
        #expect(shown.t > start && shown.t <= clock.nowMs)
        #expect(model.latencyMs >= 0 && model.latencyMs < step)

        model.act(.start)
        let countdownAt = clock.nowMs
        run(until: { model.snapshot.counted >= 2 }, maxMs: 60_000)
        #expect(model.snapshot.counted >= 2)
        // the machine's set start is clock time: the countdown (3 s) after START
        let setStart = model.snapshot.setStartedAt
        #expect(abs(setStart - (countdownAt + SessionTiming.countdownMs)) <= step)
        #expect(model.records.contains { if case .rep = $0 { true } else { false } })
    }

    @Test func theSequenceLoopsOnTheClock() throws {
        let seq = try Self.slips()
        let clock = ManualClock(startMs: 100)
        let source = SequenceFrameSource(sequence: seq, clock: clock)
        nonisolated(unsafe) var times: [Double] = []
        try source.start { _, t in times.append(t) }
        source.pump()
        #expect(times == [100])
        let pass = seq.frames.last!.t + 1000 / seq.fps
        clock.advance(byMs: pass)
        source.pump()
        #expect(times.count == seq.frames.count + 1)
        #expect(times.last == 100 + pass)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
    }
}
