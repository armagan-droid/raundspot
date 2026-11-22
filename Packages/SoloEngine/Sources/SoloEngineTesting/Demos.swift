import Foundation
import SoloEngine

// Demo animations (specs/04 "Gösterim animasyonu") from the synthetic bodies:
// one correct rep (two for two-sided drills), 10 frames a second.

public enum DemoGenerator {
    public static let frameMs = 100
    /// Valid reps one loop of each demo shows.
    public static let repsPerLoop: [String: Int] = [
        "slip_left": 1, "slip_right": 1, "slip": 2, "duck": 1, "bob_weave_left": 1, "bob_weave_right": 1,
        "lean_back": 1, "squat": 1, "pushup": 1, "reverse_lunge": 2, "jumping_jack": 1,
    ]

    private static var options: SequenceOptions {
        SequenceOptions(fps: 1000 / Double(frameMs), leadInMs: 600, restMs: 500, leadOutMs: 500, farSideVisibility: 1)
    }

    /// Templates whose movement is mostly in depth get a side view too (specs/04 `extra`).
    public static let extraSideView: Set<String> = ["duck", "bob_weave_left", "bob_weave_right"]

    public static func sequence(_ id: String, view: CameraView = .front) -> LandmarkSequence? {
        let o = options
        func evade(_ p: EvaderParams, _ ms: Double = 900) -> SyntheticRep<EvaderParams> { SyntheticRep(p, durationMs: ms) }
        let dip = EvaderParams(kneeAngle: 110, torsoLean: 25)
        switch id {
        case "slip_left": return evaderSequence(exerciseId: id, reps: [evade(EvaderParams(slip: 28))], options: o)
        case "slip_right": return evaderSequence(exerciseId: id, reps: [evade(EvaderParams(slip: -28))], options: o)
        case "slip": return evaderSequence(exerciseId: id, reps: [evade(EvaderParams(slip: 28)), evade(EvaderParams(slip: -28))], options: o)
        case "duck":
            // down, a short hold at the bottom, back up
            let rest = EvaderParams(), deep = EvaderParams(kneeAngle: 100, torsoLean: 30)
            return keyframes(id, view: view, [(rest, 700), (deep, 600), (deep, 400), (rest, 600), (rest, 300)])
        case "bob_weave_left", "bob_weave_right":
            // a U: dip first, move under to the side, come up there, back to the center
            // (weaving before the dip is a fault)
            let side: Double = id == "bob_weave_left" ? 20 : -20
            let rest = EvaderParams()
            return keyframes(id, view: view, [(rest, 700), (dip, 500), (EvaderParams(slip: side, kneeAngle: 110, torsoLean: 25), 500),
                                               (EvaderParams(slip: side), 500), (rest, 600), (rest, 300)])
        case "lean_back":
            return fighterSequence(exerciseId: id, reps: [SyntheticRep(FighterParams(torsoLean: 32), durationMs: 1200)],
                                   start: FighterParams(kneeAngle: 175), options: o)
        case "squat": return squatSequence(view: .side, reps: [squatRep(kneeAngle: 90, durationMs: 2000)], options: o)
        case "pushup": return pushupSequence(reps: [SyntheticRep(PushupParams(elbowAngle: 80), durationMs: 1800)], options: o)
        case "reverse_lunge":
            return lungeSequence(reps: [LungeParams(kneeAngle: 90, backLeg: .right), LungeParams(kneeAngle: 90, backLeg: .left)]
                .map { SyntheticRep($0, durationMs: 2000) }, options: o)
        case "jumping_jack":
            return jackSequence(reps: [SyntheticRep(JackParams(armRaise: 175, legSpread: 0.25), durationMs: 900)], options: o)
        default: return nil
        }
    }

    /// A path through poses: each pose is reached after its duration, eased, from the previous one.
    private static func keyframes<P: SyntheticPose>(_ id: String, view: CameraView, _ path: [(P, Double)]) -> LandmarkSequence {
        var frames: [Frame] = []
        var t = 0.0
        let step = Double(frameMs)
        var from = path[0].0
        for (to, ms) in path {
            let n = Int((ms / step).rounded())
            for i in 0..<n {
                let s = (1 - cos(Double.pi * Double(i + 1) / Double(n))) / 2
                frames.append(toFrame(P.lerp(from, to, s).body, FrameOptions(view: view, facing: .right, t: t, farSideVisibility: 1)))
                t += step
            }
            from = to
        }
        return LandmarkSequence(formatVersion: 1, skeleton: .mediapipe33, exerciseId: id, source: .synthetic,
                                view: view, fps: 1000 / step, labels: nil, frames: frames, hasWorld: true)
    }

    public static func demo(_ id: String) -> ExerciseDemo? {
        guard let seq = sequence(id) else { return nil }
        func points(_ seq: LandmarkSequence) -> [[LandmarkName: GuidePoint]] {
            seq.frames.map { f in
                Dictionary(uniqueKeysWithValues: ExerciseDemo.joints.map { n in (n, GuidePoint(x: f[image: n].x, y: f[image: n].y)) })
            }
        }
        let extra = extraSideView.contains(id) ? sequence(id, view: .side).map { ExerciseDemo.Extra(view: .side, frames: points($0)) } : nil
        // rounded as stored, so the file and the generator agree
        let demo = ExerciseDemo(exercise: id, view: seq.view ?? .front, aspect: 1, frameMs: frameMs, frames: points(seq), extra: extra)
        return try? ExerciseDemo.parse(JSONValue.parse(demo.json.serialized()))
    }
}
