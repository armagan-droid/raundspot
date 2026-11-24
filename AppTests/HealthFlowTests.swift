import Foundation
import SoloCapture
import SoloEngine
import SoloHealth
import Testing
@testable import GymSpotSolo

final class RecordingHealthStore: HealthStore, @unchecked Sendable {
    var calls: [String] = []
    var energy: [Double] = []
    func begin(at: Date) { calls.append("begin") }
    func addActivity(_ type: HealthActivity, start: Date, end: Date) { calls.append("activity \(type.rawValue)") }
    func addEnergy(kcal: Double, start: Date, end: Date) { energy.append(kcal); calls.append("energy") }
    func pause(at: Date) { calls.append("pause") }
    func resume(at: Date) { calls.append("resume") }
    func finish(at: Date, mainActivity: HealthActivity) -> Bool { calls.append("finish \(mainActivity.rawValue)"); return true }
    func discard() { calls.append("discard") }
}

/// specs/08 through the app: a workout on the fake camera reaches Apple Health as one workout with its block
/// and energy (AC-8.2 with and without a weight); Y1 has the estimate.
@MainActor @Suite struct HealthFlowTests {
    func run(weight: Double?, minutes: Double) async throws -> (TrainingModel, RecordingHealthStore) {
        let store = RecordingHealthStore()
        let clock = ManualClock()
        let seq = try FakeCameraTests.slips()
        let source = SequenceFrameSource(sequence: seq, clock: clock)
        let model = TrainingModel(single: try #require(ExerciseCatalog.pack("slip_left")), source: source, clock: clock,
                                  settings: TrainingSettings(weightKg: weight), health: store)
        await model.confirmSpace()
        var activeSince: Double?
        for _ in 0..<20_000 where !model.state.isTerminal {
            clock.advance(byMs: 1000 / seq.fps)
            source.pump()
            model.tick()
            if model.state == .ready { model.act(.start) }
            if model.state == .active { activeSince = activeSince ?? clock.nowMs }
            if model.state == .confirm { model.act(.continueSet) }
            if let a = activeSince, clock.nowMs - a > minutes * 60_000 { model.act(.endSet) }
        }
        model.close()
        return (model, store)
    }

    @Test func aWorkoutReachesAppleHealthWithItsEnergy() async throws {
        let (model, store) = try await run(weight: 70, minutes: 4)
        #expect(model.state == .sessionDone)
        #expect(store.calls.first == "begin" && store.calls.last == "finish martialArts")
        #expect(store.calls.contains("activity martialArts") && store.energy.count == 1)
        let kcal = try #require(model.sessionKcal)
        #expect(kcal > 0 && abs(store.energy[0] - kcal) < 1)
    }

    @Test func withoutAWeightNoEnergyIsWritten() async throws {
        let (model, store) = try await run(weight: nil, minutes: 1)
        #expect(model.sessionKcal == nil)
        #expect(store.energy.isEmpty && store.calls.last == "finish martialArts")
    }
}
