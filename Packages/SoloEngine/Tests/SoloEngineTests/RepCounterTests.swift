import Testing
@testable import SoloEngine
import SoloEngineTesting

// Port of the source `engine/test/rep-counter.test.ts` (commit c2fe3fd).

private let squat = try! Repo.load("squat")
private let press = try! Repo.load("shoulder_press")

/// Runs a scalar signal for the pack's rep metric through a fresh counter.
private func run(_ rep: RepDefinition, _ signal: [SignalPoint],
                 extra: ((Double) -> [String: Double])? = nil) -> [RepCounterEvent] {
    var c = RepCounter(rep)
    return signal.flatMap { p in
        var values = [rep.metric: p.value]
        extra?(p.t).forEach { values[$0] = $1 }
        return c.push(p.t, values)
    }
}

private func attempts(_ events: [RepCounterEvent]) -> [AttemptCompleted] {
    events.compactMap { if case .attemptCompleted(let a) = $0 { a } else { nil } }
}

private func starts(_ events: [RepCounterEvent]) -> [Double] {
    events.compactMap { if case .repStarted(let t) = $0 { t } else { nil } }
}

private func reps(_ targets: Double..., durationMs: Double = 2000) -> [SignalRep] {
    targets.map { SignalRep(to: $0, durationMs: durationMs) }
}

private func near(_ a: Double, _ b: Double, digits: Int = 2) -> Bool {
    // vitest toBeCloseTo: |a − b| < 10^−digits / 2
    Swift.abs(a - b) < 0.5 * pow10(-digits)
}

private func pow10(_ e: Int) -> Double { (0..<Swift.abs(e)).reduce(1.0) { a, _ in e < 0 ? a / 10 : a * 10 } }

@Suite("RepCounter — decreasing movement (squat)") struct RepCounterSquatTests {
    @Test func countsCleanRepsThatReachTheTarget() {
        let ev = run(squat.pack.rep, scalarSignal(fps: 30, from: 172, reps: reps(90, 90, 90)))
        #expect(starts(ev).count == 3)
        let a = attempts(ev)
        #expect(a.count == 3)
        #expect(a.allSatisfy { $0.reachedTarget })
    }

    @Test func repStartedPrecedesEachAttemptCompleted() {
        let ev = run(squat.pack.rep, scalarSignal(fps: 30, from: 172, reps: reps(90, 90)))
        let types = ev.map { if case .repStarted = $0 { "S" } else { "C" } }
        #expect(types == ["S", "C", "S", "C"])
    }

    @Test func nothingCountsUntilTheStartZoneHasBeenEntered() {
        // starts half-way down (120), comes up to 172, then does one rep
        var sig = scalarSignal(fps: 30, from: 172, reps: reps(90), leadInMs: 1000)
        for i in 0..<10 { sig[i].value = 120 }
        #expect(attempts(run(squat.pack.rep, sig)).count == 1)
    }

    @Test func aPartialRepIsAnAttemptThatDidNotReachTheTarget() {
        let a = attempts(run(squat.pack.rep, scalarSignal(fps: 30, from: 172, reps: reps(125))))
        #expect(a.count == 1)
        #expect(a[0].reachedTarget == false)
        #expect(near(a[0].turn.value, 125, digits: 0))
    }

    @Test func aWobbleSmallerThanAttemptMinExcursionIsNotAnAttempt() {
        // AC-4.4: start.exit 150, excursion 20 -> must go below 130 to count
        #expect(attempts(run(squat.pack.rep, scalarSignal(fps: 30, from: 172, reps: reps(135)))).isEmpty)
    }

    @Test func turnPointAndStartSnapshotsCarryAllMetricValuesFromThoseFrames() {
        let sig = scalarSignal(fps: 30, from: 172, reps: reps(90))
        let a = attempts(run(squat.pack.rep, sig) { ["torso_lean": $0 / 100] })[0]
        #expect(near(a.turn.value, 90))
        #expect(near(a.turn.values["torso_lean"]!, a.turn.t / 100))
        #expect(a.turn.values[squat.pack.rep.metric] == a.turn.value)
        #expect(near(a.start.values["torso_lean"]!, a.start.t / 100))
        #expect(a.start.values[squat.pack.rep.metric]! < 150)
    }

    @Test func durationRunsFromLeavingTheStartZoneToReEnteringIt() {
        let sig = scalarSignal(fps: 30, from: 172, reps: reps(90, durationMs: 2000))
        let a = attempts(run(squat.pack.rep, sig))[0]
        let left = sig.first { $0.value < 150 }!.t
        let back = sig.first { $0.t > left && $0.value >= 160 }!.t
        #expect(a.start.t == left)
        #expect(a.t == back)
        #expect(near(a.durationMs, back - left))
    }

    @Test func nanFramesAreIgnored() {
        var sig = scalarSignal(fps: 30, from: 172, reps: reps(90))
        for i in sig.indices where i % 7 == 3 { sig[i].value = .nan }
        let a = attempts(run(squat.pack.rep, sig))
        #expect(a.count == 1)
        #expect(a[0].reachedTarget)
    }

    @Test func resetReturnsToWaitingForTheStartZone() {
        var c = RepCounter(squat.pack.rep)
        _ = c.push(0, [squat.pack.rep.metric: 172])
        _ = c.push(33, [squat.pack.rep.metric: 140])
        #expect(c.state == .inRep)
        c.reset()
        #expect(c.state == .waiting)
    }
}

@Suite("AC-4.4: noisy signals are not double counted") struct RepCounterNoiseTests {
    @Test(arguments: [1, 2, 3, 4, 5])
    func fiveRepsWithNoiseCountExactlyFive(seed: Int) {
        let sig = scalarSignal(fps: 30, from: 172, reps: Array(repeating: SignalRep(to: 92), count: 5), noise: 3, seed: seed)
        let a = attempts(run(squat.pack.rep, sig))
        #expect(a.count == 5)
        #expect(a.allSatisfy { $0.reachedTarget })
    }

    @Test func standingStillNearTheStartThresholdsProducesNoEventsAtAll() {
        // 156 ± 4 keeps crossing start.exit (150) and start.enter (160)
        let sig = scalarSignal(fps: 30, from: 156, reps: [], leadInMs: 10_000, noise: 4, seed: 11)
        #expect(sig.contains { $0.value < 150 } && sig.contains { $0.value >= 160 })
        let lead = SignalPoint(t: -100, repIndex: nil, progress: 0, value: 170)
        #expect(run(squat.pack.rep, [lead] + sig).isEmpty)
    }

    @Test func repStartedFiresOnceTheExcursionIsConfirmed() {
        let sig = scalarSignal(fps: 30, from: 172, reps: reps(90))
        var c = RepCounter(squat.pack.rep)
        let first = sig.first { p in
            c.push(p.t, [squat.pack.rep.metric: p.value]).contains { if case .repStarted = $0 { true } else { false } }
        }!
        #expect(first.value <= 130)
        #expect(first.value > 120)
    }

    @Test func hoveringAroundTheTargetThresholdStillCountsOneRepPerRep() {
        let sig = scalarSignal(fps: 30, from: 172, reps: Array(repeating: SignalRep(to: 100, durationMs: 3000), count: 4),
                               noise: 3, seed: 21)
        #expect(attempts(run(squat.pack.rep, sig)).count == 4)
    }
}

@Suite("RepCounter — increasing movement (shoulder press)") struct RepCounterPressTests {
    @Test func countsPressesAndDetectsPartialLockouts() {
        let a = attempts(run(press.pack.rep, scalarSignal(fps: 30, from: 85, reps: reps(172, 140, 170))))
        #expect(a.map(\.reachedTarget) == [true, false, true])
        #expect(near(a[1].turn.value, 140, digits: 0))
    }
}

@Suite("classifyAttempt (ref 04 outcome table)") struct ClassifyAttemptTests {
    private func classify(reachedTarget: Bool = true, durationMs: Double = 2000, hasValidityFault: Bool = false) -> RepOutcome {
        classifyAttempt(reachedTarget: reachedTarget, durationMs: durationMs, hasValidityFault: hasValidityFault,
                        minDurationMs: 800, maxDurationMs: 8000)
    }

    @Test func outcomeTable() {
        #expect(classify(reachedTarget: true, hasValidityFault: false) == .valid)
        #expect(classify(reachedTarget: true, hasValidityFault: true) == .faulty)
        #expect(classify(reachedTarget: false, hasValidityFault: true) == .faulty)
        #expect(classify(reachedTarget: false, hasValidityFault: false) == .incomplete)
    }

    @Test func tooFastOrTooSlowIsIncompleteRegardlessOfTheRest() {
        #expect(classify(durationMs: 500) == .incomplete)
        #expect(classify(durationMs: 9000) == .incomplete)
        #expect(classify(durationMs: 500, hasValidityFault: true) == .incomplete)
        #expect(classify(durationMs: 800) == .valid)
        #expect(classify(durationMs: 8000) == .valid)
    }
}

@Suite("AC-4.5: partial reps trigger the depth fault at the turn point") struct DepthFaultTests {
    @Test func insufficientDepthIsTrueForAPartialSquatAndFalseForAFullOne() {
        let depth = squat.faults.first { $0.fault.id == "insufficient_depth" }!
        let a = attempts(run(squat.pack.rep, scalarSignal(fps: 30, from: 172, reps: reps(90, 120))))
        #expect(depth.position == .atTurn)
        #expect(depth.expr.evaluate(a[0].turn.values) == false)
        #expect(depth.expr.evaluate(a[1].turn.values) == true)
        let outcomes = a.map {
            classifyAttempt(reachedTarget: $0.reachedTarget, durationMs: $0.durationMs,
                            hasValidityFault: depth.expr.evaluate($0.turn.values) == true,
                            minDurationMs: squat.pack.rep.minDurationMs, maxDurationMs: squat.pack.rep.maxDurationMs)
        }
        #expect(outcomes == [.valid, .faulty])
    }
}

@Suite("AC-4.7: near_ landmarks give the same result for left, right and mirrored side views")
struct NearSideEquivalenceTests {
    private let pushup = try! Repo.load("pushup")

    private func attemptsOf(_ seq: LandmarkSequence) -> [AttemptCompleted] {
        let computer = try! MetricComputer(pack: pushup.pack)
        let near = chooseNearSide(Array(seq.frames.prefix(30)))
        var smoother = MetricSmoother(names: computer.order, params: OneEuroParams(pushup.pack.smoothing))
        var counter = RepCounter(pushup.pack.rep)
        return attempts(playSequence(seq) { f in counter.push(f.t, smoother.smooth(computer.compute(f, near: near), tMs: f.t)) })
    }

    @Test func sameAttemptsAndTurnValues() {
        let targets = [PushupParams(elbowAngle: 85), PushupParams(elbowAngle: 110), PushupParams(elbowAngle: 88, hipOffset: -0.08)]
        let reps = targets.map { SyntheticRep($0) }
        let right = pushupSequence(reps: reps, options: SequenceOptions(facing: .right))
        let left = pushupSequence(reps: reps, options: SequenceOptions(facing: .left))
        var mirrored = right
        mirrored.frames = right.frames.map(mirrorFrame)

        let r = attemptsOf(right)
        #expect(r.map(\.reachedTarget) == [true, false, true])
        for other in [attemptsOf(left), attemptsOf(mirrored)] {
            #expect(other.map(\.reachedTarget) == r.map(\.reachedTarget))
            for (i, a) in other.enumerated() {
                #expect(near(a.turn.value, r[i].turn.value, digits: 6))
                #expect(near(a.turn.values["hip_offset"]!, r[i].turn.values["hip_offset"]!, digits: 6))
            }
        }
    }
}
