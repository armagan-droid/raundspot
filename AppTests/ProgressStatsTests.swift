import Foundation
import SoloEngine
import SwiftData
import Testing
@testable import GymSpotSolo

/// specs/12 G1 and G3 figures from stored records.
@MainActor @Suite struct ProgressStatsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // a Friday

    /// One finished session at `at`: a technique set of `reps`, or a reflex set of `trials` at `level`.
    func session(_ c: ModelContainer, at: Date, technique: (String, [(RepOutcome, [String])])? = nil,
                 reflex: (Int, [(ReflexResult, Double?)])? = nil, done: Bool = true) throws {
        let kind = reflex == nil ? "technique" : "reflex"
        let info = RecordContext(workoutVersion: nil, sport: "muay_thai", stance: "orthodox", appVersion: "t", blockKind: { _ in kind },
                                 catalog: { _ in reflex.map { ("muay_thai", 1, $0.0) } })
        let r = SessionRecorder(context: c.mainContext, info: info)
        let sid = UUID().uuidString, bid = UUID().uuidString, setId = UUID().uuidString
        try r.write(.session(id: sid, workoutId: "w", status: .active, warmupSkipped: false), now: at, view: "front", activeMs: 0)
        if let (ex, reps) = technique {
            for (o, f) in reps {
                try r.write(.rep(id: UUID().uuidString, setId: setId, outcome: o, faults: f, durationMs: 700, counted: true), now: at, view: "front", activeMs: 0)
            }
            try r.write(.set(id: setId, blockId: bid, index: 0, validReps: 0, faultyReps: 0, attempts: reps.count, target: 10, belowTarget: true, mode: .lenient),
                        now: at, view: "front", activeMs: 0)
            try r.write(.block(id: bid, sessionId: sid, index: 0, exerciseId: ex, exerciseVersion: 2, status: .done), now: at, view: "front", activeMs: 0)
        }
        if let (_, trials) = reflex {
            for (i, (res, rt)) in trials.enumerated() {
                r.writeReflexTrial(ReflexTrialRecord(index: i, comboId: nil, comboIndex: nil, strikeId: "jab", isFeint: false, cueAt: 0, result: res,
                                                     responseExerciseId: nil, preferred: nil, reactionMs: rt, rtApproximate: false, faults: []),
                                   setId: setId, at: at)
            }
            try r.write(.set(id: setId, blockId: bid, index: 0, validReps: 0, faultyReps: 0, attempts: trials.count, target: trials.count,
                             belowTarget: false, mode: nil), now: at, view: "front", activeMs: 0)
            try r.write(.block(id: bid, sessionId: sid, index: 0, exerciseId: nil, exerciseVersion: nil, status: .done), now: at, view: "front", activeMs: 0)
        }
        try r.write(.session(id: sid, workoutId: "w", status: done ? .done : .aborted, warmupSkipped: false), now: at, view: "front", activeMs: 0)
    }

    @Test func weeklyCountsReactionTimesAndHits() throws {
        let c = try SoloStore.container(inMemory: true)
        let day = 86_400.0
        try session(c, at: now, reflex: (1, [(.correct, 400), (.wrong, 600), (.missed, nil), (.feintOk, nil)]))
        try session(c, at: now.addingTimeInterval(-day), reflex: (1, [(.correct, 300)]))
        try session(c, at: now.addingTimeInterval(-7 * day), technique: ("duck", [(.valid, [])]))
        try session(c, at: now.addingTimeInterval(-2 * day), technique: ("duck", [(.valid, [])]), done: false)  // aborted: not counted
        try session(c, at: now.addingTimeInterval(-70 * day), technique: ("duck", [(.valid, [])]))  // older than 8 weeks
        let all = try c.mainContext.fetch(FetchDescriptor<StoredSession>())
        let w = ProgressStats.weeks(all, now: now)
        #expect(w.count == 8)
        #expect(w.map(\.workouts).reduce(0, +) == 3)
        #expect(w.last?.workouts == 2 && w[6].workouts == 1)
        #expect(w.last?.medianRtByLevel == [1: 400])
        #expect(w.last?.hitRate == 3.0 / 5)
        #expect(w[6].hitRate == nil)
    }

    @Test func eskivCleanRateAndTopFaults() throws {
        let c = try SoloStore.container(inMemory: true)
        try session(c, at: now, technique: ("slip_left", [(.valid, []), (.valid, ["guard_dropped"]), (.faulty, ["neck_only"]), (.faulty, ["neck_only", "guard_dropped"])]))
        try session(c, at: now, technique: ("slip_left", [(.valid, []), (.incomplete, ["neck_only"])]))
        try session(c, at: now, technique: ("squat", [(.valid, [])]))
        try session(c, at: now.addingTimeInterval(-40 * 86_400), technique: ("slip_left", [(.faulty, ["x"])]))
        let all = try c.mainContext.fetch(FetchDescriptor<StoredSession>())
        let d = ProgressStats.eskivs(all, now: now, eskivIds: ["slip_left", "duck"])
        #expect(d.count == 1)
        #expect(d[0].exerciseId == "slip_left" && d[0].attempts == 6)
        #expect(d[0].cleanRate == 2.0 / 6)
        #expect(d[0].topFaults.map(\.id) == ["neck_only", "guard_dropped"] && d[0].topFaults.map(\.count) == [3, 2])
    }
}

/// H1's MVP suggestion (specs/12): the last workout again, else Eskiv temeli.
@MainActor @Suite struct HomeSuggestionTests {
    @Test func suggestion() throws {
        let packs = Dictionary(uniqueKeysWithValues: ExerciseCatalog.load().map { ($0.pack.id, $0) })
        let workouts = ExerciseCatalog.workouts(Array(packs.values))
        #expect(HomeSuggestion.pick(last: nil, workouts: workouts, packs: packs)?.title == Lang.text(workouts.first { $0.id == "eskiv_temeli" }!.name))
        #expect(HomeSuggestion.pick(last: "kondisyon", workouts: workouts, packs: packs)?.title == Lang.text(workouts.first { $0.id == "kondisyon" }!.name))
        #expect(HomeSuggestion.pick(last: "single_duck", workouts: workouts, packs: packs)?.title == Lang.text(packs["duck"]!.pack.name))
    }
}
