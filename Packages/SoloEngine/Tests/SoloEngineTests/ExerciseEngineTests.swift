import Testing
@testable import SoloEngine
import SoloEngineTesting

// Port of the source `engine/test/exercise-engine.test.ts` (commit c2fe3fd),
// plus the Swift additions: timed events and the raw metric history.

private let squat = try! Repo.load("squat")
private let standing = SquatParams(kneeAngle: 172, torsoLean: 5, valgus: 0)

/// A rep target: unless given, knee 90 and torso lean 25.
private struct RepSpec {
    var kneeAngle = 90.0
    var torsoLean = 25.0
    var valgus = 0.0
}

/// Squat frames: each rep interpolates from standing to its own params.
private func squatFrames(_ view: CameraView, _ reps: [RepSpec], restMs: Double = 800, durationMs: Double = 2000,
                         leadInMs: Double = 2000, leadOutMs: Double = 1000, facing: FrameOptions.Facing = .right) -> [Frame] {
    let tl = repTimeline(fps: 30, repDurationsMs: reps.map { _ in durationMs }, leadInMs: leadInMs, restMs: restMs,
                         leadOutMs: leadOutMs)
    return tl.map { p in
        let target = p.repIndex.map { reps[$0] } ?? RepSpec(kneeAngle: standing.kneeAngle, torsoLean: standing.torsoLean,
                                                            valgus: standing.valgus)
        let s = p.progress
        let params = SquatParams(
            kneeAngle: standing.kneeAngle + (target.kneeAngle - standing.kneeAngle) * s,
            torsoLean: standing.torsoLean + (target.torsoLean - standing.torsoLean) * s,
            valgus: standing.valgus + (target.valgus - standing.valgus) * s)
        return squatFrame(params, FrameOptions(view: view, facing: facing, t: p.t))
    }
}

private func setVisibility(_ f: Frame, _ names: [LandmarkName], _ v: Double) -> Frame {
    var out = f
    for n in names { out.image[n.index].visibility = v }
    return out
}

private func shifted(_ f: Frame, by dt: Double) -> Frame {
    var out = f
    out.t += dt
    return out
}

private let front = ExerciseSetup(view: .front, nearSide: .left)
private let side = ExerciseSetup(view: .side, nearSide: .left)

private func run(_ frames: [Frame], _ setup: ExerciseSetup, _ engine: ExerciseEngine? = nil) -> [EngineEvent] {
    timed(frames, setup, engine).map(\.event)
}

private func timed(_ frames: [Frame], _ setup: ExerciseSetup, _ engine: ExerciseEngine? = nil) -> [TimedEvent] {
    let e = engine ?? ExerciseEngine(squat, setup: setup)
    return frames.flatMap { e.push($0) }
}

private struct Completed: Equatable {
    var outcome: RepOutcome
    var faults: [String]
    var durationMs: Int
}

private func completed(_ ev: [EngineEvent]) -> [Completed] {
    ev.compactMap {
        if case .repCompleted(let o, let f, let d) = $0 { Completed(outcome: o, faults: f, durationMs: d) } else { nil }
    }
}

private func cues(_ ev: [EngineEvent]) -> [String] {
    ev.compactMap { if case .faultDetected(let id) = $0 { id } else { nil } }
}

private func pauses(_ ev: [EngineEvent]) -> [String] {
    ev.compactMap { if case .safetyPause(let id) = $0 { id } else { nil } }
}

private func count(_ ev: [EngineEvent], _ e: EngineEvent) -> Int { ev.count { $0 == e } }

private func tracking(_ ev: [EngineEvent]) -> [EngineEvent] {
    ev.filter { $0 == .trackingLost || $0 == .trackingRestored }
}

private func modifiedSquat(_ change: (inout JSONValue) -> Void) throws -> LoadedRulePack {
    var json = try Repo.sourceJSON("squat")
    change(&json)
    return try Repo.load(json: json)
}

@Suite("ExerciseEngine — reps and outcomes") struct EngineRepTests {
    @Test func cleanRepsAreValidAndSilent() {
        let ev = run(squatFrames(.front, [RepSpec(), RepSpec(), RepSpec()]), front)
        #expect(count(ev, .repStarted) == 3)
        #expect(completed(ev).map(\.outcome) == [.valid, .valid, .valid])
        #expect(cues(ev).isEmpty)
    }

    @Test func durationMsIsAnInteger() {
        let rep = completed(run(squatFrames(.front, [RepSpec()]), front))[0]
        #expect(rep.durationMs > 800)
    }

    @Test func partialSquatIsFaultyWithInsufficientDepthAndIsCued() {
        // AC-4.5
        let ev = run(squatFrames(.front, [RepSpec(), RepSpec(kneeAngle: 120)]), front)
        let reps = completed(ev)
        #expect(reps.map(\.outcome) == [.valid, .faulty])
        #expect(reps[1].faults == ["insufficient_depth"])
        #expect(cues(ev) == ["insufficient_depth"])
    }

    @Test func aNonValidityFaultIsRecordedButTheRepStaysValid() {
        let rep = completed(run(squatFrames(.front, [RepSpec(valgus: 0.25)]), front))[0]
        #expect(rep.outcome == .valid)
        #expect(rep.faults == ["knee_valgus"])
    }

    @Test func eventsInACompletingFrameAreOrderedFaultThenCompleted() {
        let ev = run(squatFrames(.front, [RepSpec(kneeAngle: 120)]), front).filter { $0 != .readyPoseHeld }
        #expect(ev.map(\.type) == ["REP_STARTED", "FAULT_DETECTED", "REP_COMPLETED"])
    }
}

@Suite("AC-4.6: view and visibility gating") struct EngineGatingTests {
    @Test func kneeValgusIsNotEvaluatedInSideView() {
        #expect(!completed(run(squatFrames(.side, [RepSpec(valgus: 0.25)]), side))[0].faults.contains("knee_valgus"))
    }

    @Test func excessiveForwardLeanIsOnlyEvaluatedInSideView() {
        let lean = [RepSpec(torsoLean: 70), RepSpec(torsoLean: 70)]
        #expect(!completed(run(squatFrames(.front, lean), front)).flatMap(\.faults).contains("excessive_forward_lean"))
        #expect(completed(run(squatFrames(.side, lean), side)).flatMap(\.faults).contains("excessive_forward_lean"))
    }

    @Test func sideViewDepthFaultAndReadyPoseWorkDespiteTheOccludedFarLeg() {
        // regression: a two-leg average metric is gated by the far side's low visibility
        let ev = run(squatFrames(.side, [RepSpec(), RepSpec(kneeAngle: 120)]), side)
        #expect(count(ev, .readyPoseHeld) > 0)
        #expect(completed(ev).map(\.outcome) == [.valid, .faulty])
        #expect(completed(ev)[1].faults == ["insufficient_depth"])
    }

    @Test func nearSideComesFromTheSetup() {
        // left-facing side view uses the right side
        let frames = squatFrames(.side, [RepSpec(torsoLean: 70), RepSpec(torsoLean: 70)], facing: .left)
        let right = run(frames, ExerciseSetup(view: .side, nearSide: .right))
        #expect(completed(right).flatMap(\.faults).contains("excessive_forward_lean"))
        // a wrong near side from the setup corrects itself before the first rep (the left side is barely seen)
        let engine = ExerciseEngine(squat, setup: side)
        let wrong = run(frames, side, engine)
        #expect(engine.nearSide == .right)
        #expect(completed(wrong).flatMap(\.faults).contains("excessive_forward_lean"))
    }

    @Test func inAnAmbiguousViewOnlyFaultsValidForBothViewsAreEvaluated() {
        let ev = run(squatFrames(.front, [RepSpec(kneeAngle: 120, valgus: 0.25)]), ExerciseSetup(view: .ambiguous, nearSide: .left))
        #expect(completed(ev)[0].faults == ["insufficient_depth"])
    }

    @Test func lowVisibilityOnAFaultsLandmarksSuppressesThatFault() {
        let frames = squatFrames(.front, [RepSpec(valgus: 0.25)]).map { setVisibility($0, [.rightKnee], 0.3) }
        let ev = run(frames, front)
        #expect(completed(ev)[0].faults.isEmpty)
        #expect(cues(ev).isEmpty)
    }
}

@Suite("during_rep holdMs") struct EngineHoldTests {
    @Test func aSpikeShorterThanHoldMsIsIgnoredASustainedOneIsDetected() {
        let base = squatFrames(.front, [RepSpec(), RepSpec()])
        // rep windows start at 2000 and 4800 ms; turn points at 3000 and 5800
        func spike(_ from: Double, _ to: Double) -> (Frame) -> Frame {
            { f in
                f.t >= from && f.t < to
                    ? squatFrame(SquatParams(kneeAngle: 100, torsoLean: 20, valgus: 0.3), FrameOptions(view: .front, t: f.t)) : f
            }
        }
        #expect(completed(run(base.map(spike(2950, 3050)), front))[0].faults.isEmpty)  // ~3 frames ≈ 67–100 ms
        #expect(completed(run(base.map(spike(2900, 3150)), front))[0].faults == ["knee_valgus"])  // ~8 frames ≈ 233 ms
    }
}

@Suite("Cue rules (ref 05, AC-5.1)") struct EngineCueTests {
    @Test func cooldownTheSameFaultIsNotRepeatedWithinCooldownMs() {
        // reps 2.8 s apart, cooldown 4 s -> cue on reps 1 and 3 only
        let ev = run(squatFrames(.front, [RepSpec(valgus: 0.25), RepSpec(valgus: 0.25), RepSpec(valgus: 0.25)]), front)
        #expect(completed(ev).allSatisfy { $0.faults.contains("knee_valgus") })
        #expect(cues(ev) == ["knee_valgus", "knee_valgus"])
    }

    @Test func minConsecutiveRepsCueOnlyOnceTheFaultRepeats() {
        // excessive_forward_lean needs 2 consecutive attempts
        let once = run(squatFrames(.side, [RepSpec(torsoLean: 70), RepSpec(), RepSpec(torsoLean: 70)]), side)
        #expect(!cues(once).contains("excessive_forward_lean"))
        let twice = run(squatFrames(.side, [RepSpec(torsoLean: 70), RepSpec(torsoLean: 70)]), side)
        #expect(cues(twice) == ["excessive_forward_lean"])
    }

    @Test func majorBeatsMinorInTheSameMoment() throws {
        // knee_valgus (major) now at_turn
        let pack = try modifiedSquat { $0["faults"]![1]!["check"] = "at_turn: knee_valgus_l > 0.15 or knee_valgus_r > 0.15" }
        let engine = ExerciseEngine(pack, setup: front)
        // (valgus also bends the 3D knee angle, so keep it moderate to stay short of the target)
        let ev = run(squatFrames(.front, [RepSpec(kneeAngle: 125, valgus: 0.2)]), front, engine)
        #expect(completed(ev)[0].faults == ["insufficient_depth", "knee_valgus"])
        #expect(cues(ev) == ["knee_valgus"])
    }

    @Test func equalSeverityGoesToRulePackOrder() throws {
        // excessive_forward_lean (minor, at_turn)
        let pack = try modifiedSquat { $0["faults"]![2]!["minConsecutiveReps"] = 1 }
        let engine = ExerciseEngine(pack, setup: side)
        let ev = run(squatFrames(.side, [RepSpec(kneeAngle: 120, torsoLean: 70)]), side, engine)
        #expect(completed(ev)[0].faults == ["insufficient_depth", "excessive_forward_lean"])
        #expect(cues(ev) == ["insufficient_depth"])
    }
}

@Suite("AC-5.2: cues can be switched off") struct EngineCueSwitchTests {
    @Test func noCuesWhileDisabledFaultsStillRecordedCooldownNotConsumed() {
        let engine = ExerciseEngine(squat, setup: front)
        let frames = squatFrames(.front, [RepSpec(valgus: 0.25), RepSpec(valgus: 0.25)])
        let split = frames.firstIndex { $0.t >= 4400 }!  // between rep 1 and rep 2
        engine.setCuesEnabled(false)
        let first = run(Array(frames[..<split]), front, engine)
        #expect(cues(first).isEmpty)
        #expect(completed(first)[0].faults == ["knee_valgus"])
        engine.setCuesEnabled(true)
        let second = run(Array(frames[split...]), front, engine)
        #expect(cues(second) == ["knee_valgus"])  // within 4 s of rep 1, but rep 1 was never cued
    }
}

@Suite("AC-5.6: safety pause") struct EngineSafetyTests {
    @Test func aMajorFaultInTwoConsecutiveAttemptsPausesTheSet() {
        let ev = run(squatFrames(.front, [RepSpec(valgus: 0.25), RepSpec(valgus: 0.25)]), front)
        #expect(pauses(ev) == ["knee_valgus"])
        // fires during the second attempt, before it completes
        let idx = ev.firstIndex { if case .safetyPause = $0 { true } else { false } }!
        #expect(completed(Array(ev[..<idx])).count == 1)
    }

    @Test func nonConsecutiveMajorFaultsDoNotPause() {
        #expect(pauses(run(squatFrames(.front, [RepSpec(valgus: 0.25), RepSpec(), RepSpec(valgus: 0.25)]), front)).isEmpty)
    }

    @Test func canBeDisabledByTheGymSetting() {
        let engine = ExerciseEngine(squat, setup: front, options: ExerciseEngineOptions(safetyPause: false))
        #expect(pauses(run(squatFrames(.front, [RepSpec(valgus: 0.25), RepSpec(valgus: 0.25)]), front, engine)).isEmpty)
    }

    @Test func resetStartsANewSetStreaksAreCleared() {
        let engine = ExerciseEngine(squat, setup: front)
        _ = run(squatFrames(.front, [RepSpec(valgus: 0.25)]), front, engine)
        engine.reset()
        let ev = run(squatFrames(.front, [RepSpec(valgus: 0.25)]).map { shifted($0, by: 100_000) }, front, engine)
        #expect(pauses(ev).isEmpty)
    }
}

@Suite("Tracking and ready pose") struct EngineTrackingTests {
    private let allLegs: [LandmarkName] = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
    private let leftSide: [LandmarkName] = [.leftHip, .leftKnee, .leftAnkle, .leftShoulder]
    private let rightSide: [LandmarkName] = [.rightHip, .rightKnee, .rightAnkle, .rightShoulder]

    @Test func trackingLostAfterOneSecondAndRestoredWhenBack() {
        let frames = squatFrames(.front, [], leadInMs: 4000).map {
            $0.t >= 1000 && $0.t < 2500 ? setVisibility($0, allLegs, 0.1) : $0
        }
        #expect(tracking(run(frames, front)) == [.trackingLost, .trackingRestored])
    }

    @Test func flickerJustUnderMinVisibilityIsNotALoss() {
        // motion blur on a phone camera: ankles hover around 0.4–0.5 for seconds
        let frames = squatFrames(.front, [RepSpec(), RepSpec()], leadInMs: 4000).map {
            $0.t >= 1000 ? setVisibility($0, allLegs, 0.4) : $0
        }
        let ev = run(frames, front)
        #expect(tracking(ev).isEmpty)
        #expect(completed(ev).count == 2)
    }

    @Test func turningAroundIsNotALoss() {
        // set up facing right (left side near), then turned: the left side hides behind the body
        let frames = squatFrames(.side, [], leadInMs: 4000).map { setVisibility(setVisibility($0, leftSide, 0.05), rightSide, 0.95) }
        let engine = ExerciseEngine(squat, setup: side)
        #expect(tracking(run(frames, side, engine)).isEmpty)
        #expect(engine.missingLandmarks.isEmpty)
    }

    @Test func sideViewFollowsATurnAfterOneSecond() {
        let turned = { (f: Frame) in setVisibility(setVisibility(f, leftSide, 0.2), rightSide, 0.95) }
        let engine = ExerciseEngine(squat, setup: side)
        _ = run(squatFrames(.side, [], leadInMs: 2000).filter { $0.t < 800 }.map(turned), side, engine)
        #expect(engine.nearSide == .left)  // not long enough
        let ev = run(squatFrames(.side, [RepSpec(), RepSpec()], leadInMs: 2000).map { turned(shifted($0, by: 10_000)) },
                     side, engine)
        #expect(engine.nearSide == .right)
        #expect(completed(ev).count == 2)
    }

    @Test func aFrontViewNeverSwitchesSides() {
        let engine = ExerciseEngine(squat, setup: front)
        _ = run(squatFrames(.front, [], leadInMs: 3000).map { setVisibility($0, leftSide, 0.1) }, front, engine)
        #expect(engine.nearSide == .left)
    }

    @Test func missingLandmarksNamesWhatIsOutOfView() {
        let frames = squatFrames(.front, [], leadInMs: 2000).map { setVisibility($0, [.leftAnkle, .rightAnkle], 0.05) }
        let engine = ExerciseEngine(squat, setup: front)
        #expect(run(frames, front, engine).contains(.trackingLost))
        #expect(engine.missingLandmarks.map { LandmarkName.allCases[$0] } == [.leftAnkle])
    }

    @Test func aDipShorterThanOneSecondIsIgnored() {
        let frames = squatFrames(.front, [], leadInMs: 4000).map {
            $0.t >= 1000 && $0.t < 1600 ? setVisibility($0, allLegs, 0.1) : $0
        }
        #expect(tracking(run(frames, front)).isEmpty)
    }

    @Test func readyPoseHeldFiresOnceAndReArmsAfterLeavingIt() {
        let ev = run(squatFrames(.front, [RepSpec()], leadInMs: 2000, leadOutMs: 3000), front)
        #expect(count(ev, .readyPoseHeld) == 2)  // before the rep and after returning
        #expect(ev.firstIndex(of: .readyPoseHeld)! < ev.firstIndex(of: .repStarted)!)
    }

    @Test func readyPoseRequiresVisibilityOfItsLandmarks() {
        let frames = squatFrames(.front, [], leadInMs: 3000).map { setVisibility($0, [.leftKnee], 0.2) }
        #expect(count(run(frames, front), .readyPoseHeld) == 0)
    }
}

@Suite("AC-5.4: set summary") struct SetSummaryTests {
    private func reps(_ list: [(RepOutcome, [String])]) -> [RepLabel] {
        list.map { RepLabel(outcome: $0.0, faults: $0.1) }
    }

    @Test func countsAndMostFrequentFault() {
        let s = summarizeSet(reps([(.valid, []), (.valid, ["knee_valgus"]), (.faulty, ["insufficient_depth"]),
                                   (.valid, ["knee_valgus"]), (.incomplete, [])]),
                             faults: squat.pack.faults, mode: .strict)
        #expect(s == SetSummary(counted: 3, valid: 3, faulty: 1, incomplete: 1, mostFrequentFault: "knee_valgus", frequentFaults: []))
    }

    @Test func lenientModeCountsFaultyReps() {
        let s = summarizeSet(reps([(.valid, []), (.faulty, ["insufficient_depth"])]), faults: squat.pack.faults, mode: .lenient)
        #expect(s.counted == 2)
    }

    @Test func tiesGoToSeverityThenRulePackOrder() {
        let s = summarizeSet(reps([(.faulty, ["insufficient_depth"]), (.valid, ["knee_valgus"])]),
                             faults: squat.pack.faults, mode: .strict)
        #expect(s.mostFrequentFault == "knee_valgus")  // major
        let t = summarizeSet(reps([(.valid, ["excessive_forward_lean"]), (.faulty, ["insufficient_depth"])]),
                             faults: squat.pack.faults, mode: .strict)
        #expect(t.mostFrequentFault == "insufficient_depth")  // both minor, earlier in pack
    }

    @Test func aFaultInThreeConsecutiveAttemptsIsMarkedFrequent() {
        let s = summarizeSet(reps([(.valid, ["knee_valgus"]), (.valid, ["knee_valgus"]), (.valid, []),
                                   (.valid, ["excessive_forward_lean"]), (.valid, ["excessive_forward_lean"]),
                                   (.valid, ["excessive_forward_lean"])]),
                             faults: squat.pack.faults, mode: .strict)
        #expect(s.frequentFaults == ["excessive_forward_lean"])
    }

    @Test func emptySet() {
        #expect(summarizeSet([], faults: squat.pack.faults, mode: .strict)
            == SetSummary(counted: 0, valid: 0, faulty: 0, incomplete: 0, mostFrequentFault: nil, frequentFaults: []))
    }
}

// MARK: - Swift additions (specs/03 "Zaman damgalı olaylar", specs/05 "Tepki süresi")

@Suite("Timed events") struct TimedEventTests {
    @Test func everyEventCarriesTheTimeOfItsFrame() {
        let frames = squatFrames(.front, [RepSpec(kneeAngle: 120)])
        let engine = ExerciseEngine(squat, setup: front)
        var all: [TimedEvent] = []
        for f in frames {
            let out = engine.push(f)
            #expect(out.allSatisfy { $0.t == f.t })
            all += out
        }
        let reps = all.filter { $0.event != .readyPoseHeld }
        #expect(reps.map(\.event.type) == ["REP_STARTED", "FAULT_DETECTED", "REP_COMPLETED"])
        // FAULT_DETECTED and REP_COMPLETED come from the same (completing) frame
        #expect(reps[1].t == reps[2].t)
        #expect(reps[0].t < reps[1].t)
    }

    @Test func eventTypesMatchTheSourceNames() {
        let names: [EngineEvent: String] = [
            .repStarted: "REP_STARTED", .faultDetected(faultId: "x"): "FAULT_DETECTED",
            .safetyPause(faultId: "x"): "SAFETY_PAUSE", .trackingLost: "TRACKING_LOST",
            .trackingRestored: "TRACKING_RESTORED", .readyPoseHeld: "READY_POSE_HELD",
            .repCompleted(outcome: .valid, faults: [], durationMs: 1): "REP_COMPLETED",
        ]
        for (event, name) in names { #expect(event.type == name) }
    }

    @Test func jsRoundRoundsHalvesUp() {
        #expect(jsRound(2.5) == 3)
        #expect(jsRound(-2.5) == -2)
        #expect(jsRound(2.4999) == 2)
        #expect(jsRound(0.49999999999999994) == 0)
        #expect(jsRound(1666.6666666666667) == 1667)
    }
}

@Suite("Raw metric history") struct RawMetricHistoryTests {
    @Test func keepsUnsmoothedValuesOfEveryFrame() throws {
        let frames = squatFrames(.front, [RepSpec()])
        let engine = ExerciseEngine(squat, setup: front)
        let computer = try MetricComputer(pack: squat.pack)
        for f in frames { _ = engine.push(f) }
        let last = engine.rawHistory.frames.last!
        #expect(last.t == frames.last!.t)
        let expected = computer.compute(frames.last!, near: .left)
        for (name, value) in expected {
            #expect(last.values[name] == value || (last.values[name]!.isNaN && value.isNaN), "\(name)")
        }
    }

    @Test func rawNeverLagsTheSmoothedMetricDuringTheDescent() {
        // the raw metric crosses the confirmation threshold no later than the smoothed one
        let frames = squatFrames(.front, [RepSpec()])
        let engine = ExerciseEngine(squat, setup: front)
        let rep = squat.pack.rep
        let confirmAt = rep.start.exit - rep.attemptMinExcursion
        var startedAt: Double?
        var attemptStart: Double?
        for f in frames {
            let out = engine.push(f)
            if out.contains(where: { $0.event == .repStarted }) {
                startedAt = f.t
                attemptStart = engine.attemptStart?.t
                break
            }
        }
        let started = try! #require(startedAt)
        let from = try! #require(attemptStart)
        #expect(from < started)
        let window = engine.rawHistory.frames(since: from)
        #expect(window.first!.t == from)
        // at 30 fps both may cross in the same frame; the raw one is never later
        let rawCross = window.first { $0.values[rep.metric]! <= confirmAt }!.t
        #expect(rawCross <= started)
        #expect(window.last!.t == started)
    }

    @Test func retentionDropsOldFramesAndKeepsAtLeastTheWindow() {
        var h = RawMetricHistory(retentionMs: 100)
        for i in 0..<1000 { h.append(Snapshot(t: Double(i) * 10, values: ["m": Double(i)])) }
        #expect(h.frames.first!.t == 9890)
        #expect(h.frames.last!.t == 9990)
        #expect(h.frames.count == 11)
        #expect(h.frames(since: 9950).map(\.t) == [9950, 9960, 9970, 9980, 9990])
        #expect(h.frames(since: 20_000).isEmpty)
    }

    @Test func retentionCoversTheLongestRep() {
        let engine = ExerciseEngine(squat, setup: front)
        #expect(engine.rawHistory.retentionMs >= Double(squat.pack.rep.maxDurationMs))
    }
}
