import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// Target circle and guide marks (ref 08 A5, specs/12 T2) on synthetic
// vision19 2D sequences, with the engine running beside the tracker.

private func pack(_ id: String) throws -> LoadedRulePack {
    try RulePackLoader.load(Repo.read(Repo.exercises.appendingPathComponent("\(id).json")), capabilities: .vision19TwoD).get()
}

/// Runs the engine and the tracker; returns the guide of every frame.
private func guides(_ id: String, _ seq: LandmarkSequence, view: View = .front) throws -> [(Frame, HeadGuide?, [String: Double])] {
    let loaded = try pack(id)
    let seq = toVision19(seq, world: false)
    let near: PersonSide = view == .side ? chooseNearSide(seq.frames) : .left
    let engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: view, nearSide: near))
    var tracker = try #require(HeadGuideTracker(loaded.pack, nearSide: near))
    return seq.frames.map { f in
        _ = engine.push(f)
        let g = tracker.update(f, repMetric: engine.metrics[loaded.pack.rep.metric], inRep: engine.repState == .inRep,
                               minVisibility: loaded.pack.camera.minVisibility)
        return (f, g, engine.metrics)
    }
}

private func dist(_ a: GuidePoint, _ b: GuidePoint, _ k: Double) -> Double { hypot((a.x - b.x) * k, a.y - b.y) }

private func slipRep(_ s: Double) -> SyntheticRep<EvaderParams> { SyntheticRep(EvaderParams(slip: s), durationMs: 800) }

@Suite("Head target guide (ref 08 A5)") struct HeadGuideTests {
    @Test func onlyEskivTemplatesHaveOne() throws {
        for id in ["squat", "pushup", "reverse_lunge", "jumping_jack"] {
            #expect(HeadGuideTracker(try pack(id).pack, nearSide: .left) == nil)
        }
        for id in ["slip_left", "slip_right", "slip", "duck", "bob_weave_left", "bob_weave_right", "lean_back"] {
            #expect(HeadGuideTracker(try pack(id).pack, nearSide: .left) != nil)
        }
    }

    @Test func slipLeftBalloonSitsAtTheThresholdOnThePersonsLeft() throws {
        let all = try guides("slip_left", evaderSequence(exerciseId: "slip_left", reps: [slipRep(25)]))
        let (f0, g0, _) = all[0]
        let g = try #require(g0)
        #expect(g.mode == .go && g.balloons.count == 1)
        // the person's left is where the left shoulder is in the image
        let leftIsRight = f0[image: .leftShoulder].x > f0[image: .rightShoulder].x
        #expect((g.balloons[0].point.x > g.center.x) == leftIsRight)
        #expect(g.arrowTo == g.balloons[0].point)
        // at the frame where the rep metric first reaches the target, the head is near the balloon
        let firstHit = all.first { $0.2["head_left"]! >= 0.3 }
        let hit = try #require(firstHit)
        let hg = try #require(hit.1)
        #expect(hg.mode == .back && hg.arrowTo == hg.center)
        #expect(dist(GuidePoint(x: hit.0[image: .nose].x, y: hit.0[image: .nose].y), hg.balloons[0].point, 1) < 0.25 * hg.radius / 0.3)
        // back to the start zone → go again
        #expect(all.last!.1!.mode == .go)
    }

    @Test func twoSidedSlipAlternatesStartingLeft() throws {
        let all = try guides("slip", evaderSequence(exerciseId: "slip", reps: [slipRep(25), slipRep(-25)]))
        func nextIsLeft(_ g: HeadGuide, _ f: Frame) -> Bool {
            let next = g.balloons.first { $0.next }!.point
            return (next.x > g.center.x) == (f[image: .leftShoulder].x > f[image: .rightShoulder].x)
        }
        #expect(all[0].1!.balloons.count == 2)
        #expect(nextIsLeft(all[0].1!, all[0].0))
        let backAt = all.firstIndex { $0.1?.mode == .back }
        let firstBack = try #require(backAt)
        let goAt = all[firstBack...].firstIndex { $0.1?.mode == .go }
        let againGo = try #require(goAt)
        #expect(!nextIsLeft(all[againGo].1!, all[againGo].0))
    }

    @Test func duckLineSitsBetweenStandingAndDeep() throws {
        let deep = SyntheticRep(EvaderParams(kneeAngle: 110, torsoLean: 25), durationMs: 1000)
        let all = try guides("duck", evaderSequence(exerciseId: "duck", reps: [deep]))
        let g0 = try #require(all[0].1)
        let line = try #require(g0.duckLineY)
        #expect(all[0].0[image: .nose].y < line)
        #expect(g0.balloons.count == 1 && g0.balloons[0].point.y > line)
        let deepest = all.max { $0.0[image: .nose].y < $1.0[image: .nose].y }!
        #expect(deepest.0[image: .nose].y > deepest.1!.duckLineY!)
        #expect(deepest.1!.mode == .back)
        // the head is below the line exactly when the metric is past the threshold (smoothing aside)
        let agree = all.filter { $0.1 != nil }.filter { f, g, m in
            (f[image: .nose].y > g!.duckLineY!) == (m["head_height"]! < 3.94)
        }
        #expect(Double(agree.count) / Double(all.count) > 0.9)
    }

    @Test func bobWeaveBalloonIsBelowTheLineOnItsSide() throws {
        let f = toVision19(evaderSequence(exerciseId: "bob_weave_right", reps: [slipRep(0)]), world: false).frames[0]
        var t = try #require(HeadGuideTracker(try pack("bob_weave_right").pack, nearSide: .left))
        let updated = t.update(f, repMetric: nil, inRep: false, minVisibility: 0.5)
        let g = try #require(updated)
        let rightIsRight = f[image: .rightShoulder].x > f[image: .leftShoulder].x
        #expect(g.balloons.count == 1 && g.balloons[0].point.y > g.duckLineY!)
        #expect((g.balloons[0].point.x > g.center.x) == rightIsRight)
    }

    @Test func leanBackLineIsBehindTheHead() throws {
        for facing in [FrameOptions.Facing.left, .right] {
            let reps = [SyntheticRep(FighterParams(torsoLean: 35), durationMs: 1200)]
            let seq = fighterSequence(exerciseId: "lean_back", reps: reps, start: FighterParams(kneeAngle: 175),
                                      options: SequenceOptions(facing: facing))
            let all = try guides("lean_back", seq, view: .side)
            let (f0, g0, _) = all[0]
            let g = try #require(g0)
            let line = try #require(g.backLineX)
            let near = chooseNearSide([f0])
            let ear = f0[image: LandmarkName(side: near, joint: "ear")!]
            let nose = f0[image: .nose]
            // behind = the opposite side of where the nose points
            #expect((line - nose.x) * (nose.x - ear.x) < 0, "facing \(facing)")
            #expect(all.contains { $0.1?.mode == .back }, "facing \(facing)")
        }
    }
}
