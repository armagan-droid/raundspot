import Foundation
import SoloCapture
import SoloEngine
import SwiftData
import Testing
@testable import GymSpotSolo

/// AC-2.6: a `serious` thermal state degrades (24 fps, recorded) without stopping the workout; `critical` pauses (E4).
@MainActor @Suite struct DegradationTests {
    func running() async throws -> (TrainingModel, SequenceFrameSource, ManualClock, ModelContainer, Double) {
        let container = try SoloStore.container(inMemory: true)
        let info = RecordContext(workoutVersion: nil, sport: "muay_thai", stance: "orthodox", appVersion: "t",
                                 blockKind: { _ in "technique" }, catalog: { _ in nil })
        let clock = ManualClock()
        let seq = try FakeCameraTests.slips()
        let source = SequenceFrameSource(sequence: seq, clock: clock)
        let model = TrainingModel(single: try #require(ExerciseCatalog.pack("slip_left")),
                                  recorder: SessionRecorder(context: container.mainContext, info: info), source: source, clock: clock)
        await model.confirmSpace()
        let step = 1000 / seq.fps
        for _ in 0..<900 where model.state != .active {
            clock.advance(byMs: step)
            source.pump()
            model.tick()
            if model.state == .ready { model.act(.start) }
        }
        return (model, source, clock, container, step)
    }

    @Test func seriousLowersTheFrameRateAndTheWorkoutGoesOn() async throws {
        let (model, source, clock, container, _) = try await running()
        defer { model.close() }
        #expect(model.state == .active)
        model.thermalChanged(.serious)
        #expect(model.state == .active && model.band == nil)
        // 30 fps frames, delivered at most 24 per second
        let before = source.delivered
        for _ in 0..<300 {
            clock.advance(byMs: 1000 / 30)
            source.pump()
            model.tick()
        }
        let perSecond = Double(source.delivered - before) / 10
        #expect(perSecond <= 24.5 && perSecond > 10, "\(perSecond)")
        #expect(model.degradations == ["fps24"])
        let s = try #require(try container.mainContext.fetch(FetchDescriptor<StoredSession>()).first)
        #expect(s.degradations == ["fps24"])
        #expect(!model.state.isTerminal)
    }

    @Test func criticalTakesABreak() async throws {
        let (model, _, _, container, _) = try await running()
        defer { model.close() }
        withExtendedLifetime(container) {
            model.thermalChanged(.critical)
            #expect(model.state == .paused)
            #expect(model.band == String(localized: "thermal.critical"))
        }
    }
}
