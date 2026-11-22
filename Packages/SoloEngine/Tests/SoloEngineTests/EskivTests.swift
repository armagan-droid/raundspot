import Testing
@testable import SoloEngine
import SoloEngineTesting

// Port of the source `engine/test/eskiv.test.ts` (commit c2fe3fd): head
// movement drills on a synthetic front-facing boxer (ref 04 "Eskiv").

private let ids = ["slip", "slip_left", "slip_right", "duck"]
private let packs: [String: LoadedRulePack] = Dictionary(uniqueKeysWithValues: ids.map { ($0, try! Repo.load($0)) })

private func run(_ id: String, _ seq: LandmarkSequence) -> [EngineEvent] {
    let engine = ExerciseEngine(packs[id]!, setup: ExerciseSetup(view: .front, nearSide: .left))
    return playSequence(seq) { engine.push($0) }.map(\.event)
}

private func outcomes(_ ev: [EngineEvent]) -> [RepOutcome] {
    ev.compactMap { if case .repCompleted(let o, _, _) = $0 { o } else { nil } }
}

private func cues(_ ev: [EngineEvent]) -> [String] {
    ev.compactMap { if case .faultDetected(let id) = $0 { id } else { nil } }
}

private func slipTo(_ slip: Double) -> SyntheticRep<EvaderParams> { SyntheticRep(EvaderParams(slip: slip), durationMs: 700) }
private var front: FrameOptions { FrameOptions(view: .front) }

private func near(_ a: Double?, _ b: Double?, digits: Int = 6) -> Bool {
    guard let a, let b else { return false }
    var tol = 0.5
    for _ in 0..<digits { tol /= 10 }
    return Swift.abs(a - b) < tol
}

@Suite("Eskiv — metric functions") struct EskivMetricTests {
    private let c = try! MetricComputer(metrics: [
        Metric(name: "lean", definition: .lateralLean(.landmark(.nose), .landmark(.leftHip))),
        Metric(name: "height", definition: .chainHeight([.nose, .leftShoulder, .leftHip, .leftKnee, .leftAnkle].map { .landmark($0) })),
    ])

    @Test func lateralLeanIsSignedTowardThePersonsAnatomicalLeft() {
        #expect(c.compute(evaderFrame(EvaderParams(slip: 25), front), near: .left)["lean"]! > 0.2)
        #expect(c.compute(evaderFrame(EvaderParams(slip: -25), front), near: .left)["lean"]! < -0.2)
    }

    @Test func aMirroredLeftSlipReadsAsAnEqualRightSlip() throws {
        let m = try MetricComputer(pack: packs["slip"]!.pack)
        let frame = evaderFrame(EvaderParams(slip: 25), front)
        let v = m.compute(frame, near: .left)
        let mv = m.compute(mirrorFrame(frame), near: .left)
        #expect(near(mv["head_right"], v["head_left"]))
        #expect(near(mv["head_slip"], v["head_slip"]))
    }

    @Test func lateralLeanIsUnknownWhenThePersonStandsSideways() {
        #expect(c.compute(evaderFrame(EvaderParams(slip: 25), FrameOptions(view: .side)), near: .left)["lean"]!.isNaN)
    }

    @Test func chainHeightIsAboutOneStandingSmallerInADuckAndScaleFree() {
        let stand = c.compute(evaderFrame(EvaderParams(kneeAngle: 180), front), near: .left)["height"]!
        let duck = c.compute(evaderFrame(EvaderParams(kneeAngle: 110, torsoLean: 25), front), near: .left)["height"]!
        #expect(stand > 0.94)
        #expect(duck < 0.85)
        var big = evaderFrame(EvaderParams(kneeAngle: 110, torsoLean: 25), front)
        big.world = big.world.map { Landmark(x: $0.x * 1.2, y: $0.y * 1.2, z: $0.z * 1.2, visibility: $0.visibility) }
        #expect(near(c.compute(big, near: .left)["height"], duck))
    }
}

@Suite("Eskiv — packs") struct EskivPackTests {
    @Test func frontViewOnlyHowToAndHeadTargetMatchesTheCountingThreshold() {
        for id in ids {
            let pack = packs[id]!.pack
            #expect(pack.camera.views == [.front], "\(id)")
            #expect(pack.howTo.map { !$0.tr.isEmpty && !$0.en.isEmpty } == true, "\(id)")
            let ht = try! #require(pack.overlay?.headTarget, "\(id)")
            #expect((ht.lateral ?? ht.height) == pack.rep.target.enter, "\(id)")
        }
    }

    @Test func guideSidesMatchTheSideEachSlipPackCounts() {
        #expect(packs["slip"]!.pack.overlay?.headTarget?.sides ?? [.left, .right] == [.left, .right])
        #expect(packs["slip_left"]!.pack.overlay?.headTarget?.sides == [.left])
        #expect(packs["slip_right"]!.pack.overlay?.headTarget?.sides == [.right])
        #expect(packs["duck"]!.pack.overlay?.headTarget?.sides == nil)
    }
}

@Suite("Eskiv — slip") struct EskivSlipTests {
    @Test func slipsToBothSidesCountEachOneSidedPackCountsOnlyItsOwnSide() {
        let seq = evaderSequence(exerciseId: "slip", reps: [slipTo(25), slipTo(-25), slipTo(25), slipTo(-25)])
        #expect(outcomes(run("slip", seq)) == [.valid, .valid, .valid, .valid])
        #expect(outcomes(run("slip_left", seq)) == [.valid, .valid])
        #expect(outcomes(run("slip_right", seq)) == [.valid, .valid])
    }

    @Test func aSmallLeanIsAnAttemptThatDoesNotCount() {
        #expect(outcomes(run("slip", evaderSequence(exerciseId: "slip", reps: [slipTo(15)]))) == [.incomplete])
    }

    @Test func noNewSlipStartsBeforeTheHeadComesBackToTheCenter() {
        // left, then held there without passing the center zone's exit
        let seq = evaderSequence(exerciseId: "slip", reps: [slipTo(25)], options: SequenceOptions(restMs: 0, leadOutMs: 0))
        let held = evaderSequence(exerciseId: "slip", reps: [], start: EvaderParams(slip: 25),
                                  options: SequenceOptions(leadInMs: 1500, leadOutMs: 0))
        let half = seq.frames.count / 2
        let t0 = seq.frames[half].t
        var frames = Array(seq.frames[..<half])
        for (i, f) in held.frames.enumerated() {
            var g = f
            g.t = t0 + Double(i) * 33
            frames.append(g)
        }
        var combined = seq
        combined.frames = frames
        #expect(outcomes(run("slip", combined)).isEmpty)
    }

    @Test func aDuckingHeadIsNotASlipASlipIsNotADuck() {
        let duck = evaderSequence(exerciseId: "slip", reps: [SyntheticRep(EvaderParams(kneeAngle: 110, torsoLean: 25), durationMs: 900)])
        #expect(!run("slip", duck).contains(.repStarted))
        let slip = evaderSequence(exerciseId: "duck", reps: [slipTo(30)])
        #expect(!run("duck", slip).contains(.repStarted))
    }

    @Test func slippingWithTheNeckOnlyIsCuedABodySlipIsNot() {
        let neck = SyntheticRep(EvaderParams(slip: 8, neckTilt: 60), durationMs: 700)
        #expect(cues(run("slip", evaderSequence(exerciseId: "slip", reps: [neck, neck]))).contains("neck_only"))
        #expect(!cues(run("slip", evaderSequence(exerciseId: "slip", reps: [slipTo(25), slipTo(-25)]))).contains("neck_only"))
    }

    @Test func droppingOneHandDuringTheSlipIsCued() {
        let seq = evaderSequence(exerciseId: "slip", reps: [SyntheticRep(EvaderParams(slip: 25, guardDrop: 1), durationMs: 1200)],
                                 start: EvaderParams(dropSide: .right))
        #expect(cues(run("slip", seq)).contains("guard_dropped"))
    }
}

@Suite("Eskiv — duck") struct EskivDuckTests {
    @Test func deepDucksCountAShallowKneeBendDoesNot() {
        let deep = SyntheticRep(EvaderParams(kneeAngle: 110, torsoLean: 25), durationMs: 900)
        let shallow = SyntheticRep(EvaderParams(kneeAngle: 125, torsoLean: 15), durationMs: 900)
        #expect(outcomes(run("duck", evaderSequence(exerciseId: "duck", reps: [deep, deep, shallow]))) == [.valid, .valid, .incomplete])
    }
}

@Suite("Eskiv — ready pose and noise") struct EskivReadyTests {
    @Test(arguments: [(EvaderParams(), 1), (EvaderParams(guardDrop: 1), 0), (EvaderParams(slip: 15), 0)])
    func guardWithTheHeadCenteredIsTheReadyPose(params: EvaderParams, expected: Int) {
        let engine = ExerciseEngine(packs["slip"]!, setup: ExerciseSetup(view: .front, nearSide: .left))
        var ev: [EngineEvent] = []
        var t = 0.0
        while t <= 1500 {
            ev += engine.push(evaderFrame(params, FrameOptions(view: .front, t: t))).map(\.event)
            t += 33
        }
        #expect(ev.count { $0 == .readyPoseHeld } == expected)
    }

    @Test func standingInGuardWithJitterCountsNothingSlipsStillCount() {
        for id in ids {
            let still = evaderSequence(exerciseId: id, reps: [], options: SequenceOptions(noise: 0.006, seed: 7, leadInMs: 6000))
            #expect(!run(id, still).contains(.repStarted), "\(id)")
        }
        let seq = evaderSequence(exerciseId: "slip", reps: [slipTo(25), slipTo(-25), slipTo(25)],
                                 options: SequenceOptions(noise: 0.006, seed: 3))
        #expect(outcomes(run("slip", seq)) == [.valid, .valid, .valid])
    }
}
