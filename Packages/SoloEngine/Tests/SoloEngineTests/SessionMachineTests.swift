import Foundation
import Testing
@testable import SoloEngine

// specs/06 Bölüm 1 (AC-6.1–AC-6.4), ref 03 rules kept by this project.

final class Ids: @unchecked Sendable {
    private var n = 0
    func next() -> String { n += 1; return "id\(n)" }
}

/// Feeds inputs and keeps every command; time advances only with `at`.
struct Driver {
    var m: SessionMachine
    var log: [SessionCommand] = []
    var now = 0.0

    init(_ w: Workout, versions: [String: Int] = [:]) {
        let ids = Ids()
        m = SessionMachine(workout: w, exerciseVersions: versions, makeId: ids.next)
    }

    @discardableResult mutating func send(_ i: SessionInput) -> [SessionCommand] {
        let c = m.handle(i)
        log += c
        return c
    }

    @discardableResult mutating func user(_ a: UserAction) -> [SessionCommand] { send(.user(a)) }
    @discardableResult mutating func engine(_ e: EngineEvent) -> [SessionCommand] { send(.engine(e)) }

    /// Ticks every 100 ms up to `ms` after the current time.
    @discardableResult mutating func wait(_ ms: Double) -> [SessionCommand] {
        var out: [SessionCommand] = []
        let end = now + ms
        while now < end - 1e-9 {
            now = min(now + 100, end)
            out += send(.tick(now: now))
        }
        return out
    }

    var state: SessionState { m.state }

    /// Through S2 and S1 to the first block.
    mutating func begin() {
        user(.start)
        user(.confirmSpace)
        if m.workout.usesCamera { send(.setupReady) }
    }

    mutating func countdown() { user(.start); wait(3000) }

    mutating func rep(_ o: RepOutcome = .valid, faults: [String] = []) {
        engine(.repStarted)
        wait(300)
        engine(.repCompleted(outcome: o, faults: faults, durationMs: 300))
    }

    var records: [SessionRecord] { log.compactMap { if case .persist(let r) = $0 { r } else { nil } } }
    var spoken: [String] { log.compactMap { if case .speak(let k) = $0 { k } else { nil } } }
    var shown: [String] { log.compactMap { if case .show(let k) = $0 { k } else { nil } } }
}

private let warm = Block.warmup(steps: [GuidedStep(textKey: "warmup.a", durationSec: 2), GuidedStep(textKey: "warmup.b", durationSec: 1)])
private let cool = Block.guided(steps: [GuidedStep(textKey: "cooldown.a", durationSec: 1)])
private func tech(_ id: String = "slip_left", sets: Int = 2, reps: Int = 3, rest: Int = 5, mode: SetMode = .lenient) -> Block {
    .technique(exerciseId: id, sets: sets, reps: reps, restSec: rest, mode: mode)
}
private func workout(_ blocks: [Block]) -> Workout { Workout(id: "w", name: LocalizedText(tr: "w", en: "w"), estimatedMinutes: 5, blocks: blocks) }

private func setRecords(_ d: Driver) -> [(valid: Int, faulty: Int, attempts: Int, below: Bool)] {
    d.records.compactMap { if case .set(_, _, _, let v, let f, let a, _, let b, _) = $0 { (v, f, a, b) } else { nil } }
}
private func blockStatuses(_ d: Driver) -> [BlockStatus] {
    d.records.compactMap { if case .block(_, _, _, _, _, let s) = $0 { s } else { nil } }
}
private func sessionStatuses(_ d: Driver) -> [SessionStatus] {
    d.records.compactMap { if case .session(_, _, let s, _) = $0 { s } else { nil } }
}

@Suite("Session — setup and warm-up (AC-6.3)") struct SessionSetupTests {
    @Test func nothingStartsBeforeTheSpaceIsConfirmedAndTheCameraIsReady() {
        var d = Driver(workout([warm, tech()]))
        d.user(.start)
        #expect(d.state == .setup && sessionStatuses(d) == [.active])
        d.send(.setupReady)  // before S2: ignored
        d.wait(5000)
        #expect(d.state == .setup)
        d.user(.confirmSpace)
        #expect(d.state == .setup)  // camera workout: waits for S1
        d.send(.setupReady)
        #expect(d.state == .warmup && d.spoken.last == "warmup.a")
    }

    @Test func aCameralessWorkoutSkipsS1ButNotS2() {
        var d = Driver(workout([cool]))
        d.user(.start)
        d.wait(2000)
        #expect(d.state == .setup)
        d.user(.confirmSpace)
        #expect(d.state == .cooldown)
    }

    @Test func warmUpStepsAdvanceWithTime() {
        var d = Driver(workout([warm, tech()]))
        d.begin()
        d.wait(1900)
        #expect(d.spoken.last == "warmup.a")
        d.wait(200)
        #expect(d.spoken.last == "warmup.b" && d.state == .warmup)
        d.wait(1000)
        #expect(d.state == .ready && blockStatuses(d) == [.done])
    }

    @Test func skippingTheWarmUpWarnsOnceAndIsRecorded() {
        var d = Driver(workout([warm, tech(sets: 1, reps: 1), cool]))
        d.begin()
        d.user(.skipWarmup)
        d.user(.skipWarmup)
        #expect(d.state == .ready)
        #expect(d.shown.filter { $0 == "safety.warmup_skipped" }.count == 1)
        d.countdown()
        d.rep()
        d.user(.skipBlock)  // cool-down is skippable
        #expect(d.state == .sessionDone)
        #expect(d.records.last == .session(id: "id1", workoutId: "w", status: .done, warmupSkipped: true))
        #expect(blockStatuses(d) == [.skipped, .done, .skipped])
    }
}

@Suite("Session — sets (ref 03 rules 2–6)") struct SessionSetTests {
    @Test func countdownSpeaksThreeTwoOneGoAndIgnoresReps() {
        var d = Driver(workout([tech()]))
        d.begin()
        d.user(.start)
        #expect(d.state == .countdown && d.spoken.last == "countdown.3")
        d.wait(1000)
        #expect(d.spoken.last == "countdown.2")
        d.engine(.repCompleted(outcome: .valid, faults: [], durationMs: 300))
        d.engine(.faultDetected(faultId: "neck_only"))
        d.wait(1000)
        #expect(d.spoken.last == "countdown.1")
        d.wait(1000)
        #expect(d.spoken.last == "set.go" && d.state == .active)
        #expect(!d.records.contains { if case .rep = $0 { true } else { false } })
    }

    @Test func readyPoseStartsTheCountdown() {
        var d = Driver(workout([tech()]))
        d.begin()
        d.engine(.readyPoseHeld)
        #expect(d.state == .countdown)
    }

    @Test func strictCountsOnlyValidLenientAlsoFaultyIncompleteNever() {
        for (mode, expected) in [(SetMode.strict, 1), (.lenient, 2)] {
            var d = Driver(workout([tech(sets: 1, reps: 5, mode: mode)]))
            d.begin()
            d.countdown()
            d.rep(.valid)
            d.rep(.faulty, faults: ["neck_only"])
            d.rep(.incomplete)
            d.user(.endSet)
            let reps = d.records.compactMap { if case .rep(_, _, let o, _, _, let c) = $0 { (o, c) } else { nil } }
            #expect(reps.map(\.0) == [.valid, .faulty, .incomplete])
            #expect(reps.filter(\.1).count == expected, "\(mode)")
            #expect(setRecords(d).first.map { $0.valid == 1 && $0.faulty == 1 && $0.attempts == 3 && $0.below } == true)
        }
    }

    @Test func faultCuesOnlyWhileActive() {
        var d = Driver(workout([tech()]))
        d.begin()
        d.engine(.faultDetected(faultId: "neck_only"))
        d.countdown()
        d.engine(.faultDetected(faultId: "neck_only"))
        #expect(d.spoken.filter { $0 == "cue.slip_left.neck_only" }.count == 1)
    }

    @Test func targetEndsTheSetThenRestThenReady() {
        var d = Driver(workout([tech(sets: 2, reps: 2, rest: 5)]))
        d.begin()
        d.countdown()
        d.rep()
        d.rep()
        #expect(d.state == .rest && setRecords(d).map(\.below) == [false])
        d.wait(4900)
        #expect(d.state == .rest)
        d.wait(200)
        #expect(d.state == .ready && d.spoken.last == "rest.done")
        d.countdown()
        d.rep()
        d.rep()
        #expect(d.state == .sessionDone && blockStatuses(d) == [.done] && sessionStatuses(d) == [.active, .done])
    }

    @Test func readyEndsTheRestEarly() {
        var d = Driver(workout([tech(sets: 2, reps: 1, rest: 60)]))
        d.begin()
        d.countdown()
        d.rep()
        d.user(.ready)
        #expect(d.state == .ready)
    }

    @Test func inactivityAsksThenEndsTheSet() {
        var d = Driver(workout([tech(sets: 2, reps: 5)]))
        d.begin()
        d.countdown()
        d.rep()
        d.wait(9900)
        #expect(d.state == .active)
        d.wait(200)
        #expect(d.state == .confirm && d.shown.last == "prompt.set_confirm")
        d.user(.continueSet)
        #expect(d.state == .active)
        d.wait(10_100)
        #expect(d.state == .confirm)
        d.rep()  // a rep in CONFIRM is handled and the set goes on
        #expect(d.state == .active && setRecords(d).isEmpty)
        d.wait(20_100)
        #expect(d.state == .rest)
        #expect(setRecords(d).map { $0.valid } == [2] && setRecords(d).map(\.below) == [true])
    }

    @Test func timedConditioningSetEndsOnTime() {
        var d = Driver(workout([.conditioning(exerciseId: "jumping_jack", sets: 1, reps: nil, durationSec: 30, restSec: 0, mode: .lenient)]))
        d.begin()
        d.countdown()
        d.wait(29_900)
        #expect(d.state == .active)  // no inactivity prompt in a timed set
        d.wait(200)
        #expect(d.state == .sessionDone && setRecords(d).map(\.below) == [false])
    }
}

@Suite("Session — pauses (ref 03 rules 10–12, E2, E4)") struct SessionPauseTests {
    @Test func trackingLostForFiveSecondsPausesAndComesBackWithACountdown() {
        var d = Driver(workout([tech(sets: 1, reps: 3)]))
        d.begin()
        d.countdown()
        d.rep()
        d.engine(.trackingLost)
        d.wait(4000)
        d.engine(.trackingRestored)
        d.wait(3000)
        #expect(d.state == .active)
        d.rep()  // movement, so the inactivity prompt does not come first
        d.engine(.trackingLost)
        d.wait(5000)
        #expect(d.state == .paused && d.spoken.last == "tracking.lost")
        d.engine(.trackingRestored)
        #expect(d.state == .countdown)
        d.wait(3000)
        d.rep()
        #expect(d.state == .sessionDone && setRecords(d).map(\.valid) == [3])  // counter kept
    }

    @Test func trackingLossPausesInReadyButNotInConfirm() {
        var d = Driver(workout([tech(sets: 1, reps: 3)]))
        d.begin()
        d.engine(.trackingLost)
        d.wait(5000)
        #expect(d.state == .paused)
        d.send(.setupReady)  // S1 checks met again
        #expect(d.state == .ready)
        d.countdown()
        d.wait(10_100)
        #expect(d.state == .confirm)
        d.engine(.trackingLost)
        d.wait(6000)
        #expect(d.state == .confirm)
    }

    @Test func safetyPauseResumesWhenTheFormIsRightAgain() {
        var d = Driver(workout([tech(sets: 1, reps: 3)]))
        d.begin()
        d.countdown()
        d.rep()
        d.engine(.safetyPause(faultId: "too_far"))
        #expect(d.state == .paused && d.spoken.last == "safety.stop")
        d.engine(.readyPoseHeld)
        #expect(d.state == .countdown && d.spoken.last == "safety.resumed")
        d.wait(1000)
        #expect(d.spoken.last == "countdown.2")
        d.wait(2000)
        d.rep()
        d.rep()
        #expect(setRecords(d).map(\.valid) == [3])
    }

    @Test func safetyPauseIsIgnoredOutsideTheSet() {
        var d = Driver(workout([tech()]))
        d.begin()
        d.engine(.safetyPause(faultId: "too_far"))
        #expect(d.state == .ready)
    }

    @Test func manualPauseNeedsResumeAndKeepsTheRestLeft() {
        var d = Driver(workout([tech(sets: 2, reps: 1, rest: 10)]))
        d.begin()
        d.countdown()
        d.rep()
        d.wait(4000)
        d.user(.pause)
        d.wait(60_000)
        d.engine(.trackingRestored)
        #expect(d.state == .paused && d.shown.last == "prompt.resume")
        d.user(.resume)
        #expect(d.state == .rest)
        d.wait(5900)
        #expect(d.state == .rest)
        d.wait(200)
        #expect(d.state == .ready)
    }

    @Test func pauseFromEveryStateReturnsThere() {
        // AC-3.6: ACTIVE/CONFIRM come back through COUNTDOWN with the counter kept
        var d = Driver(workout([warm, tech(sets: 2, reps: 3), cool]))
        d.begin()
        d.user(.pause); #expect(d.state == .paused); d.user(.resume); #expect(d.state == .warmup)
        d.user(.skipWarmup)
        d.user(.pause); d.user(.resume); #expect(d.state == .ready)
        d.user(.start)
        d.user(.pause); d.user(.resume); #expect(d.state == .countdown)
        d.wait(3000)
        d.rep()
        d.user(.pause); d.user(.resume); #expect(d.state == .countdown)
        d.wait(3000)
        d.wait(10_100)
        #expect(d.state == .confirm)
        d.user(.pause); d.user(.resume); #expect(d.state == .countdown)
        d.wait(3000)
        d.rep(); d.rep()
        #expect(d.state == .rest && setRecords(d).map(\.valid) == [3])
    }

    @Test func interruptionsPauseUntilResume() {
        for kind in [Interruption.background, .call, .camera] {
            var d = Driver(workout([tech()]))
            d.begin()
            d.countdown()
            d.send(.interrupted(kind))
            #expect(d.state == .paused)
            d.engine(.trackingRestored)
            #expect(d.state == .paused)
            d.user(.resume)
            #expect(d.state == .countdown)
        }
    }

    @Test func audioInterruptionPausesAReflexSetButOnlySilencesTechnique() {
        var d = Driver(workout([tech()]))
        d.begin()
        d.countdown()
        d.send(.audioInterrupted)
        #expect(d.state == .active)
        d.engine(.faultDetected(faultId: "neck_only"))
        #expect(!d.spoken.contains("cue.slip_left.neck_only"))
        d.send(.audioResumed)
        d.engine(.faultDetected(faultId: "neck_only"))
        #expect(d.spoken.contains("cue.slip_left.neck_only"))

        var r = Driver(workout([.reflex(catalogId: "muay_thai", level: .fixed(1), cues: 3, restSec: 0, sets: 1)]))
        r.begin()
        r.countdown()
        r.send(.audioInterrupted)
        #expect(r.state == .paused)
    }

    @Test func abortWritesThePartialSet() {
        var d = Driver(workout([tech(sets: 2, reps: 3), tech("duck")]))
        d.begin()
        d.countdown()
        d.rep()
        d.user(.abort)
        #expect(d.state == .aborted)
        #expect(setRecords(d).map { $0.below } == [true] && blockStatuses(d) == [.partial] && sessionStatuses(d) == [.active, .aborted])
        d.user(.resume)
        #expect(d.state == .aborted && d.m.handle(.tick(now: 1e9)).isEmpty)
    }

    @Test func abortBeforeAnyAttemptWritesNoSet() {
        var d = Driver(workout([tech()]))
        d.begin()
        d.countdown()
        d.user(.abort)
        #expect(setRecords(d).isEmpty && blockStatuses(d).isEmpty && sessionStatuses(d) == [.active, .aborted])
    }
}

@Suite("Session — skip and undo (ref 03 rule 9)") struct SessionSkipTests {
    @Test func undoneSkipWritesNothing() {
        var d = Driver(workout([tech("slip_left"), tech("duck")]))
        d.begin()
        d.user(.skipBlock)
        #expect(d.m.block?.exerciseId == "duck")
        d.user(.undoSkip)
        #expect(d.m.block?.exerciseId == "slip_left" && d.state == .ready)
        #expect(blockStatuses(d).isEmpty)
    }

    @Test func theRecordIsWrittenOnceWhenTheUndoWindowCloses() {
        var d = Driver(workout([tech("slip_left", sets: 2, reps: 1), tech("duck")]))
        d.begin()
        d.countdown()
        d.rep()
        d.user(.skipBlock)  // from REST, one set done → partial
        #expect(blockStatuses(d).isEmpty)
        d.countdown()
        #expect(blockStatuses(d) == [.partial])
        d.user(.undoSkip)  // too late: a set started
        #expect(d.m.block?.exerciseId == "duck" && blockStatuses(d) == [.partial])
    }

    @Test func skipIsOnlyValidInReadyRest() {
        var d = Driver(workout([tech(), tech("duck")]))
        d.begin()
        d.countdown()
        d.user(.skipBlock)
        #expect(d.state == .active && d.m.block?.exerciseId == "slip_left")
        d.user(.undoSkip)
        #expect(d.state == .active)
    }

    @Test func skippingTheLastBlockEndsTheSessionAndWritesTheRecord() {
        var d = Driver(workout([tech()]))
        d.begin()
        d.user(.skipBlock)
        #expect(d.state == .sessionDone && blockStatuses(d) == [.skipped])
    }
}

@Suite("Session — reflex blocks (E1)") struct SessionReflexTests {
    @Test func theSetEndsAfterItsCues() {
        var d = Driver(workout([.reflex(catalogId: "muay_thai", level: .fixed(1), cues: 3, restSec: 10, sets: 2)]))
        d.begin()
        d.countdown()
        d.engine(.repCompleted(outcome: .valid, faults: [], durationMs: 300))  // reflex attempts come from the loop
        d.send(.reflexAttemptDone); d.send(.reflexAttemptDone)
        d.wait(30_000)
        #expect(d.state == .active)  // no inactivity rule in reflex sets
        d.send(.reflexAttemptDone)
        #expect(d.state == .rest)
        d.user(.ready)
        d.countdown()
        d.send(.reflexAttemptDone)
        d.user(.endSet)
        #expect(d.state == .sessionDone)
        #expect(setRecords(d).map(\.below) == [false, true])
        #expect(!d.records.contains { if case .rep = $0 { true } else { false } })
    }
}

@Suite("Session — serialize and restore (E4, AC-6.4)") struct SessionRestoreTests {
    @Test func aRestoredMachineGoesOnTheSameWay() throws {
        let w = workout([tech(sets: 2, reps: 3)])
        var a = Driver(w)
        a.begin()
        a.countdown()
        a.rep()
        let data = a.m.serialize()
        var b = a
        b.m = try SessionMachine.deserialize(data, workout: w, exerciseVersions: [:], makeId: { "x" })
        #expect(b.m.s == a.m.s)
        a.rep(); b.rep()
        #expect(a.m.s.counted == b.m.s.counted && a.state == b.state)
    }

    @Test func withinThirtyMinutesItOffersToResumeThenAborts() throws {
        let w = workout([tech(sets: 1, reps: 3)])
        var d = Driver(w)
        d.begin()
        d.countdown()
        d.rep()
        let saved = d.m.serialize()
        let t0 = d.now

        var soon = d
        soon.m = try SessionMachine.deserialize(saved, workout: w, exerciseVersions: [:], makeId: { "x" })
        soon.send(.restored(now: t0 + 10 * 60_000))
        #expect(soon.state == .paused && soon.shown.last == "session.resume_offer")
        soon.now = t0 + 10 * 60_000
        soon.user(.resume)
        #expect(soon.state == .countdown)

        var idle = d
        idle.m = try SessionMachine.deserialize(saved, workout: w, exerciseVersions: [:], makeId: { "x" })
        idle.send(.restored(now: t0 + 10 * 60_000))
        idle.now = t0 + 10 * 60_000
        idle.wait(20 * 60_000 + 200)
        #expect(idle.state == .aborted)

        var late = d
        late.m = try SessionMachine.deserialize(saved, workout: w, exerciseVersions: [:], makeId: { "x" })
        late.send(.restored(now: t0 + 31 * 60_000))
        #expect(late.state == .aborted && sessionStatuses(late).last == .aborted)
    }
}

@Suite("Session — ready-made workouts (AC-6.2, AC-6.5)") struct WorkoutFileTests {
    private func load(_ id: String) throws -> Workout {
        try Workout.parse(Repo.read(Repo.exercises.appendingPathComponent("workouts/\(id).json")))
    }

    @Test func filesParseAndUseExistingTemplates() throws {
        for id in ["eskiv_temeli", "refleks", "kondisyon", "hizli_karma"] {
            let w = try load(id)
            #expect(w.id == id)
            for b in w.blocks {
                if let ex = b.exerciseId {
                    #expect(FileManager.default.fileExists(atPath: Repo.exercises.appendingPathComponent("\(ex).json").path), "\(id): \(ex)")
                }
            }
        }
    }

    @Test func eskivTemeliRunsToTheEnd() throws {
        let w = try load("eskiv_temeli")
        var d = Driver(w, versions: ["slip_left": 2, "slip_right": 2, "duck": 2, "bob_weave_left": 1, "bob_weave_right": 1])
        d.begin()
        #expect(d.state == .warmup)
        d.wait(Double(w.blocks[0].steps.map(\.durationSec).reduce(0, +)) * 1000)
        var sets = 0
        while d.state != .sessionDone {
            switch d.state {
            case .ready: d.countdown()
            case .active:
                if case .reflex? = d.m.block { d.send(.reflexAttemptDone) } else { d.rep() }
            case .rest: d.user(.ready)
            case .cooldown: d.wait(1000)
            default: Issue.record("unexpected state \(d.state)"); return
            }
            if case .rest = d.state { sets += 1 }
            if d.log.count > 10_000 { Issue.record("runaway"); return }
        }
        // 2+2+2+1+1 technique sets, 1 reflex set
        #expect(setRecords(d).count == 9)
        #expect(blockStatuses(d) == Array(repeating: .done, count: 8))
        let versions = d.records.compactMap { if case .block(_, _, _, let ex?, let v, _) = $0 { "\(ex)@\(v ?? 0)" } else { nil } }
        #expect(versions == ["slip_left@2", "slip_right@2", "duck@2", "bob_weave_left@1", "bob_weave_right@1"])
        #expect(d.spoken.first == "warmup.light_jumps" && d.spoken.last == "session.done")
        #expect(sessionStatuses(d) == [.active, .done])
        // the command order of one set
        let firstSet = d.spoken.drop { $0 != "countdown.3" }.prefix(6)
        #expect(Array(firstSet) == ["countdown.3", "countdown.2", "countdown.1", "set.go"] + Array(firstSet.suffix(2)))
    }

    private func circuitWorkout(_ circuit: JSONValue) throws -> Workout {
        try Workout.parse(["formatVersion": 1, "id": "c", "name": ["tr": "c", "en": "c"], "sport": "muay_thai",
                           "estimatedMinutes": 5, "blocks": [circuit]])
    }

    /// specs/06 "Devre": the loader opens a circuit into one-set blocks; rest only between rounds.
    @Test func aCircuitOpensIntoOneSetBlocks() throws {
        let w = try circuitWorkout(["type": "circuit", "rounds": 2, "restSec": 60, "blocks": [
            ["type": "conditioning", "exerciseId": "jumping_jack", "reps": 20],
            ["type": "conditioning", "exerciseId": "squat", "durationSec": 30, "mode": "strict"],
        ]])
        let jj = { (rest: Int) in Block.conditioning(exerciseId: "jumping_jack", sets: 1, reps: 20, durationSec: nil, restSec: rest, mode: .lenient) }
        let sq = { (rest: Int) in Block.conditioning(exerciseId: "squat", sets: 1, reps: nil, durationSec: 30, restSec: rest, mode: .strict) }
        #expect(w.blocks == [jj(0), sq(0), jj(0), sq(0)])
        #expect(w.restAfterBlock == [1: 60])
    }

    @Test func malformedCircuitsAreRejected() throws {
        let item: JSONValue = ["type": "conditioning", "exerciseId": "squat", "reps": 12]
        for bad: JSONValue in [
            ["type": "circuit", "rounds": 0, "restSec": 60, "blocks": [item]],
            ["type": "circuit", "rounds": 2, "blocks": [item]],
            ["type": "circuit", "rounds": 2, "restSec": 60, "blocks": []],
            ["type": "circuit", "rounds": 2, "restSec": 60, "blocks": [["type": "conditioning", "exerciseId": "squat", "reps": 12, "sets": 3]]],
            ["type": "circuit", "rounds": 2, "restSec": 60, "blocks": [["type": "conditioning", "exerciseId": "squat", "reps": 12, "restSec": 5]]],
            ["type": "circuit", "rounds": 2, "restSec": 60, "blocks": [["type": "technique", "exerciseId": "slip_left", "reps": 8]]],
            ["type": "circuit", "rounds": 2, "restSec": 60, "blocks": [["type": "circuit", "rounds": 2, "restSec": 0, "blocks": [item]]]],
            ["type": "circuit", "rounds": 2, "restSec": 60, "blocks": [["type": "conditioning", "exerciseId": "squat"]]],
        ] {
            #expect(throws: Workout.ParseError.self, "\(bad)") { try circuitWorkout(bad) }
        }
    }

    /// specs/06 "Seçim": a technique block with `choose` is kept apart and filled at the start.
    @Test func aChoiceIsResolvedAtTheStart() throws {
        let w = try Workout.parse(["formatVersion": 1, "id": "c", "name": ["tr": "c", "en": "c"], "sport": "muay_thai", "estimatedMinutes": 5,
            "blocks": [
                ["type": "warmup", "steps": [["textKey": "warmup.arm_circles", "durationSec": 30]]],
                ["type": "technique", "choose": ["from": ["slip_left", "slip_right", "duck"], "count": 2], "sets": 2, "reps": 8, "restSec": 45],
                ["type": "circuit", "rounds": 2, "restSec": 60, "blocks": [["type": "conditioning", "exerciseId": "squat", "reps": 12]]],
            ]])
        #expect(w.blocks.count == 3)  // warm-up and the two circuit rounds; the choice is apart
        #expect(w.choices == [Workout.Choice(position: 1, from: ["slip_left", "slip_right", "duck"], count: 2, sets: 2, reps: 8,
                                              restSec: 45, mode: .lenient)])
        #expect(w.restAfterBlock == [1: 60])
        let r = try w.resolving(picks: [["duck", "slip_left"]])
        #expect(r.choices.isEmpty)
        #expect(r.blocks.compactMap(\.exerciseId) == ["duck", "slip_left", "squat", "squat"])
        #expect(r.blocks[1] == .technique(exerciseId: "duck", sets: 2, reps: 8, restSec: 45, mode: .lenient))
        #expect(r.restAfterBlock == [3: 60])
        #expect(throws: Workout.ParseError.self) { try w.resolving(picks: [["duck"]]) }
        #expect(throws: Workout.ParseError.self) { try w.resolving(picks: [["duck", "lean_back"]]) }
        #expect(throws: Workout.ParseError.self) { try w.resolving(picks: [["duck", "duck"]]) }
        #expect(throws: Workout.ParseError.self) { try w.resolving(picks: []) }
    }

    @Test func malformedChoicesAreRejected() throws {
        let base: JSONValue = ["type": "technique", "choose": ["from": ["slip_left", "duck"], "count": 2], "sets": 1, "reps": 5, "restSec": 0]
        var both = base; both["exerciseId"] = "duck"
        var none = base; none["choose"] = nil
        var many = base; many["choose"]!["count"] = 3
        var zero = base; zero["choose"]!["count"] = 0
        var twice = base; twice["choose"]!["from"] = ["duck", "duck"]
        var extra = base; extra["choose"]!["pick"] = 1
        for bad in [both, none, many, zero, twice, extra] {
            #expect(throws: Workout.ParseError.self, "\(bad)") {
                try Workout.parse(["formatVersion": 1, "id": "c", "name": ["tr": "c", "en": "c"], "sport": "muay_thai", "estimatedMinutes": 5,
                                   "blocks": [bad]])
            }
        }
    }

    @Test func hizliKarmaFollowsTheTable() throws {
        let w = try load("hizli_karma")
        #expect(w.choices.count == 1 && w.choices[0].count == 2)
        #expect(Set(w.choices[0].from) == ["slip_left", "slip_right", "duck", "bob_weave_left", "bob_weave_right"])
        #expect(w.blocks.contains { if case .reflex(_, .chosen, _, 60, 2) = $0 { true } else { false } })
        #expect(w.blocks.filter { $0.exerciseId != nil }.count == 8)  // the circuit ×2 of four moves
        #expect(w.blocks.last?.steps.isEmpty == false)
    }

    /// Kondisyon (specs/06 table): circuit ×3 of four moves, 60 s rest between rounds.
    @Test func kondisyonRunsThreeRounds() throws {
        let w = try load("kondisyon")
        let moves = w.blocks.compactMap(\.exerciseId)
        #expect(moves == Array(repeating: ["jumping_jack", "squat", "pushup", "reverse_lunge"], count: 3).flatMap { $0 })
        #expect(w.blocks.allSatisfy { $0.restSec == 0 } && w.restAfterBlock == [4: 60, 8: 60])
        var d = Driver(w, versions: ["jumping_jack": 1, "squat": 1, "pushup": 1, "reverse_lunge": 1])
        d.begin()
        d.wait(Double(w.blocks[0].steps.map(\.durationSec).reduce(0, +)) * 1000)
        var rests = 0
        while d.state != .sessionDone {
            switch d.state {
            case .ready: d.countdown()
            case .active: d.rep()
            case .rest: rests += 1; d.user(.ready)
            case .cooldown: d.wait(1000)
            default: Issue.record("unexpected state \(d.state)"); return
            }
            if d.log.count > 20_000 { Issue.record("runaway"); return }
        }
        #expect(setRecords(d).count == 12)
        #expect(rests == 2)
        #expect(sessionStatuses(d) == [.active, .done])
    }

    @Test func malformedWorkoutsAreRejected() throws {
        var j = try Repo.read(Repo.exercises.appendingPathComponent("workouts/kondisyon.json"))
        j["blocks"]![1]!["durationSec"] = 30
        #expect(throws: Workout.ParseError.self) { try Workout.parse(j) }
        var k = try Repo.read(Repo.exercises.appendingPathComponent("workouts/kondisyon.json"))
        k["blocks"]![1]!["type"] = "plank"
        #expect(throws: Workout.ParseError.self) { try Workout.parse(k) }
        var r = try Repo.read(Repo.exercises.appendingPathComponent("workouts/refleks.json"))
        #expect(try Workout.parse(r).blocks[1] == .reflex(catalogId: "muay_thai", level: .chosen, cues: nil, restSec: 60, sets: 3))
        r["blocks"]![1]!["level"] = "hard"
        #expect(throws: Workout.ParseError.self) { try Workout.parse(r) }
    }
}
