import Foundation
import Testing
@testable import SoloHealth

/// A fake HealthKit store that records the calls (specs/08 tests).
final class FakeStore: HealthStore, @unchecked Sendable {
    var calls: [String] = []
    var energy: [(kcal: Double, start: Date, end: Date)] = []
    func begin(at: Date) { calls.append("begin") }
    func addActivity(_ type: HealthActivity, start: Date, end: Date) { calls.append("activity \(type.rawValue)") }
    func addEnergy(kcal: Double, start: Date, end: Date) { energy.append((kcal, start, end)); calls.append("energy") }
    func pause(at: Date) { calls.append("pause") }
    func resume(at: Date) { calls.append("resume") }
    func finish(at: Date, mainActivity: HealthActivity) -> Bool { calls.append("finish \(mainActivity.rawValue)"); return true }
    func discard() { calls.append("discard") }
}

@Suite("SoloHealth (specs/08)") struct HealthWorkoutTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ min: Double) -> Date { t0.addingTimeInterval(min * 60) }

    @Test func blockKindsMapToActivityTypes() {
        #expect(HealthActivity(blockKind: "technique", sport: "muay_thai") == .martialArts)
        #expect(HealthActivity(blockKind: "reflex", sport: "muay_thai") == .martialArts)
        #expect(HealthActivity(blockKind: "round", sport: "kickboxing") == .kickboxing)
        #expect(HealthActivity(blockKind: "technique", sport: "boxing") == .boxing)
        #expect(HealthActivity(blockKind: "conditioning", sport: "muay_thai") == .functionalStrengthTraining)
        #expect(HealthActivity(blockKind: "warmup", sport: "muay_thai") == .preparationAndRecovery)
        #expect(HealthActivity(blockKind: "guided", sport: "muay_thai") == .flexibility)
    }

    /// One workout, one activity per block, the longest block's type as the main one, an energy sample per block.
    @Test func aMixedSessionIsOneWorkout() {
        let store = FakeStore()
        let w = HealthWorkout(store: store, sport: "muay_thai")
        w.begin(at: at(0))
        w.block("warmup", start: at(0), end: at(3), kcal: 8)
        w.block("technique", start: at(3), end: at(13), kcal: 40)
        w.block("conditioning", start: at(13), end: at(18), kcal: 30)
        let saved = w.finish(at: at(18), aborted: false, activeMs: 18 * 60_000)
        #expect(saved)
        #expect(store.calls == ["begin", "activity preparationAndRecovery", "energy", "activity martialArts", "energy",
                                "activity functionalStrengthTraining", "energy", "finish martialArts"])
        #expect(store.energy.map(\.kcal) == [8, 40, 30])
    }

    /// AC-8.2: no weight → no energy sample, the workout is still written.
    @Test func noWeightNoEnergy() {
        let store = FakeStore()
        let w = HealthWorkout(store: store, sport: "muay_thai")
        w.begin(at: at(0))
        w.block("technique", start: at(0), end: at(10), kcal: nil)
        #expect(w.finish(at: at(10), aborted: false, activeMs: 600_000))
        #expect(store.energy.isEmpty && store.calls.last == "finish martialArts")
    }

    /// AC-8.5: an aborted session under 3 active minutes is discarded; from 3 minutes it is written.
    @Test func shortAbortedSessionsAreDiscarded() {
        let a = FakeStore(), wa = HealthWorkout(store: a, sport: "muay_thai")
        wa.begin(at: at(0))
        wa.block("technique", start: at(0), end: at(2), kcal: 5)
        #expect(!wa.finish(at: at(2), aborted: true, activeMs: 179_999))
        #expect(a.calls.last == "discard")
        let b = FakeStore(), wb = HealthWorkout(store: b, sport: "muay_thai")
        wb.begin(at: at(0))
        wb.block("technique", start: at(0), end: at(4), kcal: 5)
        #expect(wb.finish(at: at(4), aborted: true, activeMs: 180_000))
        #expect(b.calls.last == "finish martialArts")
    }

    @Test func pausesReachTheStore() {
        let s = FakeStore(), w = HealthWorkout(store: s, sport: "muay_thai")
        w.begin(at: at(0))
        w.pause(at: at(1))
        w.resume(at: at(2))
        #expect(s.calls == ["begin", "pause", "resume"])
    }
}
