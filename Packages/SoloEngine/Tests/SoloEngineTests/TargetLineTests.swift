import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// specs/04 `overlay.targetLine` and AC-4.9.

private func projectJSON(_ id: String) throws -> JSONValue { try Repo.read(Repo.exercises.appendingPathComponent("\(id).json")) }

private func pack(_ id: String) throws -> LoadedRulePack {
    try RulePackLoader.load(projectJSON(id), capabilities: .vision19TwoD).get()
}

@Suite("Target line schema (specs/04)") struct TargetLineSchemaTests {
    @Test func defaultsToTheRepMetric() throws {
        let p = try RulePackParser.parse(projectJSON("squat")).get()
        #expect(p.overlay?.targetLine == TargetLine(metric: nil))
    }

    @Test func acceptsTheRepMetricOrOneOfItsArguments() throws {
        var p = try projectJSON("reverse_lunge")
        for m in ["knee", "knee_l", "knee_r"] {
            p["overlay"] = ["targetLine": ["metric": .string(m)]]
            #expect(!hasIssue(p, "overlay.targetLine"), "\(m)")
        }
        p["overlay"] = ["targetLine": ["metric": "knee_near"]]
        #expect(hasIssue(p, "overlay.targetLine.metric", "rep metric"))
        p["overlay"] = ["targetLine": ["metric": 3]]
        #expect(hasIssue(p, "overlay.targetLine.metric"))
        p["overlay"] = ["targetLine": ["extra": true]]
        #expect(hasIssue(p, "overlay.targetLine", "extra"))
    }

    @Test func needsAnAngle2dOrDiffYMetric() throws {
        var p = try projectJSON("lean_back")
        p["overlay"] = ["targetLine": [:]]
        #expect(hasIssue(p, "overlay.targetLine", "angle2d or diffY"))
        var j = try projectJSON("jumping_jack")
        j["overlay"] = ["targetLine": [:]]
        #expect(!hasIssue(j, "overlay.targetLine"))
    }

    @Test func conditioningTemplatesCarryOneAndEskivsDoNot() throws {
        for id in ["squat", "pushup", "reverse_lunge", "jumping_jack"] {
            #expect(try TargetLineTracker(pack(id).pack, nearSide: .left) != nil, "\(id)")
        }
        for id in ["slip_left", "slip", "duck", "bob_weave_left", "lean_back"] {
            #expect(try TargetLineTracker(pack(id).pack, nearSide: .left) == nil, "\(id)")
        }
    }
}

/// Raw (unsmoothed) metric values of one frame.
private func raw(_ loaded: LoadedRulePack, _ f: Frame, near: PersonSide) -> [String: Double] {
    try! MetricComputer(pack: loaded.pack).compute(f, near: near)
}

/// AC-4.9: the moving point is past the line exactly when the metric is past the threshold.
private func agreement(_ id: String, _ seq: LandmarkSequence, view: View, beyondIsBelow: Bool) throws -> (agree: Double, frames: Int, reached: Bool) {
    let loaded = try pack(id)
    let seq = toVision19(seq, world: false)
    let near: PersonSide = view == .side ? chooseNearSide(seq.frames) : .left
    var tracker = try #require(TargetLineTracker(loaded.pack, nearSide: near))
    let rep = loaded.pack.rep
    let decreasing = rep.target.enter < rep.start.enter
    var agree = 0, total = 0
    var reached = false
    for f in seq.frames {
        let m = raw(loaded, f, near: near)[rep.metric]!
        guard let g = tracker.update(f, repMetric: m, minVisibility: loaded.pack.camera.minVisibility), m.isFinite else { continue }
        let past = decreasing ? m <= rep.target.enter : m >= rep.target.enter
        reached = reached || g.mode == .back
        for line in g.lines {
            for mover in line.movers {
                total += 1
                let beyond = beyondIsBelow ? mover.y > line.y : mover.y < line.y
                if beyond == past { agree += 1 }
            }
        }
    }
    return (total == 0 ? 0 : Double(agree) / Double(total), total, reached)
}

@Suite("Target line geometry (AC-4.9)") struct TargetLineGeometryTests {
    @Test func squat() throws {
        let seq = squatSequence(view: .side, reps: [squatRep(kneeAngle: 90), squatRep(kneeAngle: 120)])
        let r = try agreement("squat", seq, view: .side, beyondIsBelow: true)
        #expect(r.frames > 100 && r.agree > 0.9 && r.reached, "\(r)")
    }

    @Test func pushup() throws {
        let seq = pushupSequence(reps: [PushupParams(elbowAngle: 80), PushupParams(elbowAngle: 120)].map { SyntheticRep($0, durationMs: 1500) })
        let r = try agreement("pushup", seq, view: .side, beyondIsBelow: true)
        #expect(r.frames > 100 && r.agree > 0.9 && r.reached, "\(r)")
    }

    @Test func reverseLungeBothLegsAndFacings() throws {
        for facing in [FrameOptions.Facing.left, .right] {
            let reps = [LungeParams(kneeAngle: 90, backLeg: .right), LungeParams(kneeAngle: 90, backLeg: .left)]
                .map { SyntheticRep($0, durationMs: 2000) }
            let seq = lungeSequence(reps: reps, options: SequenceOptions(facing: facing))
            let r = try agreement("reverse_lunge", seq, view: .side, beyondIsBelow: true)
            #expect(r.frames > 100 && r.agree > 0.9 && r.reached, "\(facing) \(r)")
        }
    }

    @Test func jumpingJackOneLineForBothWrists() throws {
        let reps = [175.0, 100].map { SyntheticRep(JackParams(armRaise: $0, legSpread: 0.25), durationMs: 900) }
        let seq = jackSequence(reps: reps)
        let r = try agreement("jumping_jack", seq, view: .front, beyondIsBelow: false)
        #expect(r.frames > 100 && r.agree > 0.9 && r.reached, "\(r)")
        let loaded = try pack("jumping_jack")
        var t = try #require(TargetLineTracker(loaded.pack, nearSide: .left))
        let g = t.update(toVision19(seq, world: false).frames[0], repMetric: nil, minVisibility: 0.5)
        #expect(g?.lines.count == 1 && g?.lines.first?.movers.count == 2)
    }

    @Test func modeGoesBackAtTheTargetAndReturnsAtTheStart() throws {
        let loaded = try pack("squat")
        let f = toVision19(squatSequence(view: .side, reps: [squatRep(kneeAngle: 90)]), world: false).frames[0]
        var t = try #require(TargetLineTracker(loaded.pack, nearSide: chooseNearSide([f])))
        #expect(t.update(f, repMetric: 170, minVisibility: 0.5)?.mode == .go)
        #expect(t.update(f, repMetric: 130, minVisibility: 0.5)?.mode == .go)
        #expect(t.update(f, repMetric: 99, minVisibility: 0.5)?.mode == .back)
        #expect(t.update(f, repMetric: 130, minVisibility: 0.5)?.mode == .back)
        #expect(t.update(f, repMetric: 161, minVisibility: 0.5)?.mode == .go)
    }
}
