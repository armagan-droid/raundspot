import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// This project's templates under `exercises/` (specs/04 "Şablon seti", T2.8):
// they run on Vision 2D only (H2), follow the drawing rules, and behave as
// specified on synthetic `vision19` sequences without world landmarks.

private let projectIds = ["slip_left", "slip_right", "slip", "duck", "bob_weave_left", "bob_weave_right", "lean_back",
                          "squat", "pushup", "reverse_lunge", "jumping_jack"]

private func projectJSON(_ id: String) throws -> JSONValue {
    try Repo.read(Repo.exercises.appendingPathComponent("\(id).json"))
}

private let project: [String: LoadedRulePack] = Dictionary(uniqueKeysWithValues: projectIds.map {
    ($0, try! RulePackLoader.load(projectJSON($0), capabilities: .vision19TwoD).get())
})

/// The sequence as the app sees it under H2: Vision joints, no world.
private func vision(_ seq: LandmarkSequence) -> LandmarkSequence { toVision19(seq, world: false) }

private func run(_ loaded: LoadedRulePack, _ seq: LandmarkSequence, view: View? = nil) -> [EngineEvent] {
    let v = view ?? View(loaded.pack.camera.views[0])
    let near = v == .side ? chooseNearSide(seq.frames) : .left
    let engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: v, nearSide: near))
    return playSequence(seq) { engine.push($0) }.map(\.event)
}

private func run(_ id: String, _ seq: LandmarkSequence) -> [EngineEvent] { run(project[id]!, vision(seq)) }

private struct Completed: Equatable, CustomStringConvertible {
    var outcome: RepOutcome
    var faults: [String]
    var description: String { "\(outcome.rawValue)\(faults.isEmpty ? "" : " \(faults)")" }
}

private func completed(_ ev: [EngineEvent]) -> [Completed] {
    ev.compactMap { if case .repCompleted(let o, let f, _) = $0 { Completed(outcome: o, faults: f) } else { nil } }
}

private func outcomes(_ ev: [EngineEvent]) -> [RepOutcome] { completed(ev).map(\.outcome) }

private func cues(_ ev: [EngineEvent]) -> [String] {
    ev.compactMap { if case .faultDetected(let id) = $0 { id } else { nil } }
}

private func evade(_ p: EvaderParams, _ ms: Double = 900) -> SyntheticRep<EvaderParams> { SyntheticRep(p, durationMs: ms) }
private let deepDuck = EvaderParams(kneeAngle: 110, torsoLean: 25)

@Suite("Project templates — packs (specs/04)") struct ProjectPackTests {
    /// The app bundle gets exactly `exercises/*.json` (specs/02): the build
    /// script copies the files named in `scripts/build/exercises.xcfilelist`.
    @Test func theAppBuildListNamesEveryTemplate() throws {
        let list = try String(contentsOf: Repo.root.appendingPathComponent("scripts/build/exercises.xcfilelist"), encoding: .utf8)
        let listed = list.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let files = try FileManager.default.contentsOfDirectory(atPath: Repo.root.appendingPathComponent("exercises").path)
            .filter { $0.hasSuffix(".json") }
        #expect(listed.sorted() == files.map { "$(SRCROOT)/exercises/\($0)" }.sorted())
    }

    @Test func everyTemplateRunsOnVision2DOnly() throws {
        let files = Repo.jsonFiles(in: Repo.exercises).map { $0.deletingPathExtension().lastPathComponent }
        #expect(files.sorted() == projectIds.sorted(), "templates not covered by these tests")
        for id in projectIds {
            #expect(throws: Never.self, "\(id)") { try RulePackLoader.load(projectJSON(id), capabilities: .vision19TwoD).get() }
        }
    }

    @Test func draftsWithHowToAndDerivedOrigin() {
        let derived = ["slip_left", "slip_right", "slip", "duck", "squat", "pushup"]
        for id in projectIds {
            let p = project[id]!.pack
            #expect(p.status == .draft, "\(id)")
            #expect(p.howTo.map { !$0.tr.isEmpty && !$0.en.isEmpty } == true, "\(id)")
            #expect(p.camera.minVisibility == 0.5, "\(id)")
            if derived.contains(id) {
                #expect(p.derivedFrom == DerivedFrom(id: id, version: 1, commit: "c2fe3fd"), "\(id)")
                #expect(p.version == 2, "\(id)")
            } else {
                #expect(p.derivedFrom == nil && p.version == 1, "\(id)")
            }
        }
    }

    @Test func viewsFollowTheTemplateTable() {
        for id in projectIds {
            let side = ["lean_back", "squat", "pushup", "reverse_lunge"].contains(id)
            #expect(project[id]!.pack.camera.views == [side ? .side : .front], "\(id)")
        }
    }

    /// ref 04 / specs/04: the drawn threshold is the counting threshold.
    @Test func headTargetsMatchTheCountingThreshold() throws {
        for id in ["slip_left", "slip_right", "slip", "duck", "bob_weave_left", "bob_weave_right", "lean_back"] {
            let p = project[id]!.pack
            let ht = try #require(p.overlay?.headTarget, "\(id)")
            let drawn = id.hasPrefix("bob_weave") || id == "duck" ? ht.height : id == "lean_back" ? ht.back : ht.lateral
            #expect(drawn == p.rep.target.enter, "\(id)")
        }
        #expect(project["bob_weave_left"]!.pack.overlay?.headTarget?.sides == [.left])
        #expect(project["bob_weave_right"]!.pack.overlay?.headTarget?.sides == [.right])
        #expect(project["bob_weave_left"]!.pack.overlay?.headTarget?.lateral == 0.15)  // the no_weave threshold
        #expect(project["slip_left"]!.pack.overlay?.headTarget?.sides == [.left])
        #expect(project["slip_right"]!.pack.overlay?.headTarget?.sides == [.right])
    }

    @Test func derivedEskivsKeepTheSourceMetricNamesAndFaultIds() throws {
        for id in ["slip_left", "slip_right", "slip", "duck"] {
            let source = try Repo.load(id).pack, p = project[id]!.pack
            #expect(p.metrics.map(\.name) == source.metrics.map(\.name), "\(id)")
            #expect(p.faults.map(\.id) == source.faults.map(\.id), "\(id)")
            #expect(p.rep.metric == source.rep.metric, "\(id)")
        }
    }
}

// MARK: - AC-4.4 equivalence (synthetic part; the golden part waits for T1.2)

@Suite("Project templates — AC-4.4 equivalence") struct EquivalenceTests {
    static let dir = Repo.root.appendingPathComponent("fixtures/equivalence", isDirectory: true)

    static func frozen(_ id: String) throws -> LoadedRulePack {
        try RulePackLoader.load(Repo.read(dir.appendingPathComponent("\(id).json")), capabilities: .vision19TwoD).get()
    }

    /// The frozen copy is the initial version; while `exercises/` still has that version they are the same file.
    @Test(arguments: ["slip_left", "duck"]) func frozenCopyIsTheInitialVersion(_ id: String) throws {
        let copy = try Repo.read(Self.dir.appendingPathComponent("\(id).json"))
        #expect(copy["version"] == 2)
        let current = try projectJSON(id)
        if current["version"] == copy["version"] { #expect(current == copy) }
    }

    static var slipCases: [[SyntheticRep<EvaderParams>]] { [
        [evade(EvaderParams(slip: 25), 700), evade(EvaderParams(slip: -25), 700), evade(EvaderParams(slip: 25), 700)],
        [evade(EvaderParams(slip: 15), 700)],
        [evade(EvaderParams(slip: 4, neckTilt: 80), 700), evade(EvaderParams(slip: 4, neckTilt: 80), 700)],
        [evade(EvaderParams(slip: 25, guardDrop: 1), 1200), evade(EvaderParams(slip: 30), 700)],
        [evade(deepDuck), evade(EvaderParams(slip: 35), 700)],
    ] }

    static var duckCases: [[SyntheticRep<EvaderParams>]] { [
        [evade(deepDuck), evade(deepDuck), evade(EvaderParams(kneeAngle: 125, torsoLean: 15))],
        [evade(EvaderParams(kneeAngle: 110, torsoLean: 25, guardDrop: 1), 1200)],
        [evade(EvaderParams(slip: 20), 700), evade(deepDuck)],
        [evade(EvaderParams(kneeAngle: 100, torsoLean: 30)), evade(EvaderParams(kneeAngle: 130, torsoLean: 10))],
    ] }

    private func check(_ id: String, _ cases: [[SyntheticRep<EvaderParams>]]) throws {
        let source = try Repo.load(id), v2 = try Self.frozen(id)
        for (i, reps) in cases.enumerated() {
            for seed in [1, 2] {
                let seq = evaderSequence(exerciseId: id, reps: reps, start: EvaderParams(dropSide: .right),
                                         options: SequenceOptions(noise: 0.002, seed: seed))
                let expected = completed(run(source, seq, view: .front))
                let actual = completed(run(v2, vision(seq), view: .front))
                #expect(actual == expected, "\(id) case \(i) seed \(seed)")
            }
        }
    }

    @Test func slipLeft() throws { try check("slip_left", Self.slipCases) }
    @Test func duck() throws { try check("duck", Self.duckCases) }

    /// The source test uses noise 0.006; the 2D duck stands 0.003 only: shoulder
    /// width is a short baseline that multiplies landmark noise (specs/04 "Duck", risk).
    @Test(arguments: [("slip_left", 0.006), ("duck", 0.003)]) func standingWithJitterCountsNothing(_ id: String, _ noise: Double) throws {
        for seed in [7, 8, 9] {
            let still = evaderSequence(exerciseId: id, reps: [], options: SequenceOptions(noise: noise, seed: seed, leadInMs: 6000))
            #expect(!run(try Self.frozen(id), vision(still), view: .front).contains(.repStarted), "\(id) seed \(seed)")
        }
    }

    @Test func theDuckNoiseLimit() throws {
        // pinned so that a change of the metric or the thresholds is noticed (specs/04 "Duck", risk)
        let still = evaderSequence(exerciseId: "duck", reps: [], options: SequenceOptions(noise: 0.006, seed: 7, leadInMs: 6000))
        let ev = run(try Self.frozen("duck"), vision(still), view: .front)
        #expect(outcomes(ev).contains(.incomplete))
    }
}

// MARK: - Eskiv

@Suite("Project templates — slips and duck") struct ProjectEskivTests {
    @Test func slipsCountTheirSideOnly() {
        let seq = evaderSequence(exerciseId: "slip", reps: [EvaderParams(slip: 25), EvaderParams(slip: -25)].map { evade($0, 700) })
        #expect(outcomes(run("slip", seq)) == [.valid, .valid])
        #expect(outcomes(run("slip_left", seq)) == [.valid])
        #expect(outcomes(run("slip_right", seq)) == [.valid])
    }

    @Test func aSlipIsNotADuckAndADuckIsNotASlip() {
        #expect(!run("duck", evaderSequence(exerciseId: "duck", reps: [evade(EvaderParams(slip: 30), 700)])).contains(.repStarted))
        #expect(!run("slip", evaderSequence(exerciseId: "slip", reps: [evade(deepDuck)])).contains(.repStarted))
    }

    @Test func aMirroredCameraGivesTheSameCount() {
        let seq = vision(evaderSequence(exerciseId: "slip_left", reps: [evade(EvaderParams(slip: 25), 700), evade(deepDuck)]))
        var flipped = seq
        flipped.frames = seq.frames.map { f in
            var g = f
            for i in g.image.indices where g.image[i].visibility > 0 { g.image[i].x = 1 - g.image[i].x }
            return g
        }
        for id in ["slip_left", "duck"] {
            #expect(completed(run(project[id]!, flipped)) == completed(run(project[id]!, seq)), "\(id)")
        }
    }
}

// MARK: - Bob & weave (AC-4.5)

@Suite("Project templates — bob & weave (AC-4.5)") struct BobWeaveTests {
    private func bw(_ slip: Double) -> SyntheticRep<EvaderParams> { evade(EvaderParams(slip: slip, kneeAngle: 110, torsoLean: 25), 1000) }

    @Test func aDipWithoutWeaveIsFaultyWeavingToTheSideIsValidTheOtherSideIsFaulty() {
        let seq = evaderSequence(exerciseId: "bob_weave_left", reps: [evade(deepDuck), bw(20), bw(-20)])
        #expect(completed(run("bob_weave_left", seq)) == [
            Completed(outcome: .faulty, faults: ["no_weave"]),
            Completed(outcome: .valid, faults: []),
            Completed(outcome: .faulty, faults: ["no_weave"]),
        ])
    }

    @Test func theRightPackIsTheMirror() {
        let seq = evaderSequence(exerciseId: "bob_weave_right", reps: [evade(deepDuck), bw(-20), bw(20)])
        #expect(outcomes(run("bob_weave_right", seq)) == [.faulty, .valid, .faulty])
    }

    @Test func aSlipWithoutDipIsNotAnAttempt() {
        let seq = evaderSequence(exerciseId: "bob_weave_left", reps: [evade(EvaderParams(slip: 30), 700)])
        #expect(!run("bob_weave_left", seq).contains(.repStarted))
    }

    @Test func weavingBeforeTheDipIsCued() {
        // the head is already to the side (but still high enough to be in the start zone) when the dip starts
        let early = SyntheticRep(EvaderParams(slip: 30, kneeAngle: 110, torsoLean: 25), durationMs: 1000)
        let seq = evaderSequence(exerciseId: "bob_weave_left", reps: [early], start: EvaderParams(slip: 14))
        #expect(cues(run("bob_weave_left", seq)).contains("weave_before_dip"))
        let clean = evaderSequence(exerciseId: "bob_weave_left", reps: [bw(20), bw(20)])
        #expect(!cues(run("bob_weave_left", clean)).contains("weave_before_dip"))
    }
}

// MARK: - Lean back (side)

@Suite("Project templates — lean back") struct LeanBackTests {
    private func lean(_ deg: Double, guardDrop: Double = 0) -> SyntheticRep<FighterParams> {
        SyntheticRep(FighterParams(guardDrop: guardDrop, torsoLean: deg), durationMs: 1200)
    }
    private func seq(_ reps: [SyntheticRep<FighterParams>], facing: FrameOptions.Facing = .right,
                     start: FighterParams = FighterParams(kneeAngle: 175)) -> LandmarkSequence {
        fighterSequence(exerciseId: "lean_back", reps: reps, start: start, options: SequenceOptions(facing: facing, noise: 0.002, seed: 4))
    }

    @Test(arguments: [FrameOptions.Facing.left, .right]) func deepLeansCountAShallowOneDoesNot(_ facing: FrameOptions.Facing) {
        #expect(outcomes(run("lean_back", seq([lean(30), lean(15), lean(35)], facing: facing))) == [.valid, .incomplete, .valid])
    }

    @Test func leaningTooFarIsAMajorFaultAndPausesTheSecondTime() {
        let ev = run("lean_back", seq([lean(70), lean(70)]))
        #expect(completed(ev).first?.faults == ["too_far"])
        #expect(ev.contains(.safetyPause(faultId: "too_far")))
    }

    @Test func droppingTheHandsIsCued() {
        #expect(cues(run("lean_back", seq([lean(30, guardDrop: 1)]))).contains("guard_dropped"))
    }

    /// `forward_lean_start` was dropped (specs/04): the ready pose asks for an upright start instead.
    @Test func theReadyPoseNeedsAnUprightTorso() {
        func ready(_ lean: Double) -> Bool {
            run("lean_back", seq([], start: FighterParams(kneeAngle: 175, torsoLean: lean))).contains(.readyPoseHeld)
        }
        #expect(ready(0))
        #expect(!ready(-12))
    }
}

// MARK: - Conditioning

@Suite("Project templates — squat and push-up (side, 2D)") struct SideConditioningTests {
    @Test func squatCountsFullDepthFlagsShallow() {
        let seq = squatSequence(view: .side, reps: [squatRep(kneeAngle: 90), squatRep(kneeAngle: 120), squatRep(kneeAngle: 92)],
                                options: SequenceOptions(noise: 0.002, seed: 2))
        #expect(completed(run("squat", seq)) == [
            Completed(outcome: .valid, faults: []),
            Completed(outcome: .faulty, faults: ["insufficient_depth"]),
            Completed(outcome: .valid, faults: []),
        ])
    }

    @Test func squatWithTheSourceTemplateOnTheSameRepsAgrees() throws {
        let seq = squatSequence(view: .side, reps: [squatRep(kneeAngle: 90), squatRep(kneeAngle: 120), squatRep(kneeAngle: 90, torsoLean: 60)],
                                options: SequenceOptions(noise: 0.002, seed: 5))
        let source = completed(run(try Repo.load("squat"), seq, view: .side))
        #expect(completed(run("squat", seq)) == source)
    }

    @Test func pushupCountsFullRangeFlagsPartialAndSag() {
        let seq = pushupSequence(reps: [PushupParams(elbowAngle: 80), PushupParams(elbowAngle: 120),
                                        PushupParams(elbowAngle: 80, hipOffset: -0.1), PushupParams(elbowAngle: 80, hipOffset: -0.1)]
            .map { SyntheticRep($0, durationMs: 1500) }, options: SequenceOptions(noise: 0.002, seed: 2))
        let c = completed(run("pushup", seq))
        #expect(c.map(\.outcome) == [.valid, .faulty, .valid, .valid])
        #expect(c[1].faults == ["partial_range"])
        #expect(c[3].faults.contains("hip_sag"))
    }
}

@Suite("Project templates — reverse lunge and jumping jack") struct NewConditioningTests {
    private func lunge(_ knee: Double, back: PersonSide, lean: Double = 5) -> SyntheticRep<LungeParams> {
        SyntheticRep(LungeParams(kneeAngle: knee, torsoLean: lean, backLeg: back), durationMs: 2000)
    }

    @Test(arguments: [FrameOptions.Facing.left, .right]) func alternatingLegsCountBoth(_ facing: FrameOptions.Facing) {
        let seq = lungeSequence(reps: [lunge(90, back: .right), lunge(90, back: .left), lunge(92, back: .right)],
                                options: SequenceOptions(facing: facing, noise: 0.002, seed: 3))
        #expect(outcomes(run("reverse_lunge", seq)) == [.valid, .valid, .valid])
    }

    @Test func shallowIsFaultyLeaningForwardIsCued() {
        let seq = lungeSequence(reps: [lunge(120, back: .right), lunge(90, back: .left, lean: 40), lunge(90, back: .right, lean: 40)],
                                options: SequenceOptions(noise: 0.002, seed: 3))
        let ev = run("reverse_lunge", seq)
        let c = completed(ev)
        #expect(c.map(\.outcome) == [.faulty, .valid, .valid])
        #expect(c[0].faults == ["insufficient_depth"])
        #expect(c[2].faults.contains("torso_forward"))
        #expect(cues(ev).contains("torso_forward"))
    }

    @Test func jumpingJacksCountArmsOverheadOnly() {
        let full = SyntheticRep(JackParams(armRaise: 175, legSpread: 0.25), durationMs: 700)
        let half = SyntheticRep(JackParams(armRaise: 100, legSpread: 0.25), durationMs: 700)
        let seq = jackSequence(reps: [full, full, half, full], options: SequenceOptions(noise: 0.002, seed: 6, restMs: 200))
        #expect(outcomes(run("jumping_jack", seq)) == [.valid, .valid, .incomplete, .valid])
    }

    @Test func armsDownIsTheReadyPose() {
        let seq = jackSequence(reps: [], options: SequenceOptions(leadInMs: 1500))
        #expect(run("jumping_jack", seq).contains(.readyPoseHeld))
    }
}
