import Foundation
import Testing
@testable import SoloEngine

/// specs/08: AC-8.1 (segment kcal, pauses not counted), AC-8.3 (heart rate method choice), weight, display.
@Suite("Energy") struct EnergyTests {
    static func table() throws -> METTable { try METTable.parse(Repo.read(Repo.exercises.appendingPathComponent("energy/met.json"))) }
    static func keytel() throws -> KeytelEquations { try KeytelEquations.parse(Repo.read(Repo.exercises.appendingPathComponent("energy/keytel.json"))) }

    @Test func theTableFollowsSpecs08() throws {
        let t = try Self.table()
        #expect(t.met("technique") == 5.3 && t.met("conditioning") == 7.5 && t.met("cooldown") == 2.3 && t.met("warmup") == 2.8)
        #expect(t.met("rest") == 1.5 && t.met("reflex") == 7.8 && t.met("round") == 10.3)
        #expect(t.met("nope") == nil)
    }

    /// AC-8.1: net kcal = Σ (MET − 1) × kg × h over the timeline; a pause adds nothing.
    @Test func netKcalOverATimelineWithAPause() throws {
        var line = EnergyTimeline()
        let min = 60_000.0
        line.enter("warmup", at: 0)                // 3 min warm-up
        line.enter("technique", at: 3 * min)       // 2 min set
        line.pause(at: 5 * min)                    // 4 min paused
        line.resume(at: 9 * min)                   // 1 more min of the set
        line.enter("rest", at: 10 * min)           // 1 min rest
        line.enter("conditioning", at: 11 * min)   // 2 min
        line.finish(at: 13 * min)
        let segs = line.segments
        #expect(segs.map(\.kind) == ["warmup", "technique", "technique", "rest", "conditioning"])
        #expect(segs.map(\.durationMs).reduce(0, +) == 9 * min)
        let kcal = try Energy.netKcal(segs, weightKg: 70, table: Self.table())
        // (1.8×3 + 4.3×3 + 0.5×1 + 6.5×2) × 70 / 60
        let expected = (1.8 * 3 + 4.3 * 3 + 0.5 * 1 + 6.5 * 2) * 70 / 60
        #expect(abs(try #require(kcal) - expected) <= 0.5)
        #expect(try Energy.netKcal(segs, weightKg: nil, table: Self.table()) == nil)
    }

    /// AC-8.3: 69 % of the active minutes with a sample → MET; 70 % → heart rate; no age or sex → MET; unverified → MET.
    @Test func heartRateMethodChoice() {
        let active = [0.0...(100 * 60_000)]
        func samples(_ minutes: Int) -> [Double] { (0..<minutes).map { Double($0) * 60_000 + 30_000 } }
        #expect(HeartRateCoverage.fraction(samples(69), active: active) == 0.69)
        #expect(Energy.method(coverage: 0.69, ageAndSexKnown: true, equationsVerified: true) == .met)
        #expect(Energy.method(coverage: 0.70, ageAndSexKnown: true, equationsVerified: true) == .heartRate)
        #expect(Energy.method(coverage: 0.95, ageAndSexKnown: false, equationsVerified: true) == .met)
        #expect(Energy.method(coverage: 0.95, ageAndSexKnown: true, equationsVerified: false) == .met)
        // pauses split the active time: samples in a pause do not count
        let split = [0.0...(60_000), (120_000.0)...(180_000)]
        #expect(HeartRateCoverage.fraction([90_000], active: split) == 0)
        #expect(HeartRateCoverage.fraction([30_000, 150_000], active: split) == 1)
    }

    @Test func keytelIsDataAndNotYetVerified() throws {
        let k = try Self.keytel()
        #expect(!k.verified)
        // the form: (a + b HR + c kg + d age) kJ/min → kcal
        let male = k.kcalPerMinute(sex: .male, heartRate: 150, weightKg: 70, age: 30)
        #expect(abs(male - (-55.0969 + 0.6309 * 150 + 0.1988 * 70 + 0.2017 * 30) / 4.184) < 1e-9)
    }

    @Test func weightAndDisplay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Energy.weight(healthKit: (72, now.addingTimeInterval(-10 * 86_400)), profile: 70, now: now) == 72)
        #expect(Energy.weight(healthKit: (72, now.addingTimeInterval(-91 * 86_400)), profile: 70, now: now) == 70)
        #expect(Energy.weight(healthKit: nil, profile: nil, now: now) == nil)
        #expect(Energy.display(133) == 135 && Energy.display(132.4) == 130 && Energy.display(2) == 0)
    }
}
