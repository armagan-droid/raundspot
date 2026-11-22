import Foundation
import SoloEngine

// Synthetic exercise bodies and sequences, translated from the source
// `testing/exercises.ts` and `testing/timeline.ts` (commit c2fe3fd). Martial
// arts bodies (evader, fighter) are in `Martial.swift`.

private func rad(_ deg: Double) -> Double { deg * Double.pi / 180 }
private func lerp(_ a: Double, _ b: Double, _ s: Double) -> Double { a + (b - a) * s }
private let sides: [(PersonSide, Double)] = [(.left, 1), (.right, -1)]

private func joint(_ side: PersonSide, _ name: String) -> LandmarkName { LandmarkName(side: side, joint: name)! }

/// Parameters that can be interpolated from the start pose toward a rep target.
public protocol SyntheticPose: Sendable {
    static func lerp(_ from: Self, _ to: Self, _ s: Double) -> Self
    var body: Body { get }
}

// MARK: - Squat

public struct SquatParams: SyntheticPose, Equatable {
    /// Hip–knee–ankle angle, 180 = straight.
    public var kneeAngle: Double
    /// Hip→shoulder lean from vertical, degrees forward.
    public var torsoLean: Double
    /// Knee shift toward the midline, as a fraction of leg length (kneeInwardRatio).
    public var valgus: Double

    public init(kneeAngle: Double, torsoLean: Double = 0, valgus: Double = 0) {
        self.kneeAngle = kneeAngle
        self.torsoLean = torsoLean
        self.valgus = valgus
    }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        Self(kneeAngle: SoloEngineTesting.lerpValue(a.kneeAngle, b.kneeAngle, s),
             torsoLean: SoloEngineTesting.lerpValue(a.torsoLean, b.torsoLean, s),
             valgus: SoloEngineTesting.lerpValue(a.valgus, b.valgus, s))
    }

    public var body: Body {
        let a = rad((180 - kneeAngle) / 2)
        let lean = rad(torsoLean)
        let legLat = 0.11
        var j: [LandmarkName: BodyPoint] = [:]
        for (s, g) in sides {
            let ankle = BodyPoint(f: 0, u: 0.08, lat: g * legLat)
            let knee = BodyPoint(f: ankle.f + Segment.shin * sin(a), u: ankle.u + Segment.shin * cos(a),
                                 lat: g * (legLat - valgus * (Segment.shin + Segment.thigh)))
            let hip = BodyPoint(f: knee.f - Segment.thigh * sin(a), u: knee.u + Segment.thigh * cos(a), lat: g * legLat)
            let shoulder = BodyPoint(f: hip.f + Segment.torso * sin(lean), u: hip.u + Segment.torso * cos(lean), lat: g * 0.19)
            var elbow = shoulder
            elbow.f += Segment.upperArm
            var wrist = elbow
            wrist.f += Segment.forearm
            j[joint(s, "ankle")] = ankle
            j[joint(s, "knee")] = knee
            j[joint(s, "hip")] = hip
            j[joint(s, "shoulder")] = shoulder
            j[joint(s, "elbow")] = elbow
            j[joint(s, "wrist")] = wrist
        }
        let sh = j[.leftShoulder]!
        j[.nose] = BodyPoint(f: sh.f + Segment.neck * sin(lean), u: sh.u + Segment.neck * cos(lean), lat: 0)
        return completeBody(j)
    }
}

public func squatFrame(_ p: SquatParams, _ o: FrameOptions) -> Frame { toFrame(p.body, o) }

// MARK: - Push-up

public struct PushupParams: SyntheticPose, Equatable {
    /// Shoulder–elbow–wrist angle.
    public var elbowAngle: Double
    /// Hip offset from the shoulder–ankle line as a fraction of that line (signedOffset), + = up.
    public var hipOffset: Double

    public init(elbowAngle: Double, hipOffset: Double = 0) {
        self.elbowAngle = elbowAngle
        self.hipOffset = hipOffset
    }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        Self(elbowAngle: SoloEngineTesting.lerpValue(a.elbowAngle, b.elbowAngle, s),
             hipOffset: SoloEngineTesting.lerpValue(a.hipOffset, b.hipOffset, s))
    }

    public var body: Body {
        let a = Segment.upperArm, b = Segment.forearm
        let d = (a * a + b * b - 2 * a * b * cos(rad(elbowAngle))).squareRoot()
        // elbow: circle intersection, bending toward the feet (−f)
        let y0 = (b * b - a * a + d * d) / (2 * d)
        let h = Swift.max(0, b * b - y0 * y0).squareRoot()
        let length = Segment.torso + Segment.thigh + Segment.shin
        let ankleF = -(length * length - (d - 0.08) * (d - 0.08)).squareRoot()
        let e = (f: ankleF / length, u: (0.08 - d) / length)  // shoulder → ankle unit vector
        let n = (f: e.u, u: -e.f)  // perpendicular, pointing up
        let lat = 0.17  // equal widths keep each side planar so angles stay exact
        var j: [LandmarkName: BodyPoint] = [:]
        for (s, g) in sides {
            let shoulder = BodyPoint(f: 0, u: d, lat: g * lat)
            let hip = BodyPoint(f: e.f * Segment.torso + n.f * hipOffset * length,
                                u: d + e.u * Segment.torso + n.u * hipOffset * length, lat: g * lat)
            let ankle = BodyPoint(f: ankleF, u: 0.08, lat: g * lat)
            let k = Segment.thigh / (Segment.thigh + Segment.shin)
            j[joint(s, "shoulder")] = shoulder
            j[joint(s, "elbow")] = BodyPoint(f: -h, u: y0, lat: g * lat)
            j[joint(s, "wrist")] = BodyPoint(f: 0, u: 0, lat: g * lat)
            j[joint(s, "hip")] = hip
            j[joint(s, "knee")] = BodyPoint(f: SoloEngineTesting.lerpValue(hip.f, ankle.f, k),
                                            u: SoloEngineTesting.lerpValue(hip.u, ankle.u, k), lat: g * lat)
            j[joint(s, "ankle")] = ankle
        }
        j[.nose] = BodyPoint(f: Segment.neck, u: d + 0.02, lat: 0)
        return completeBody(j)
    }
}

public func pushupFrame(_ p: PushupParams, _ o: FrameOptions) -> Frame { toFrame(p.body, o) }

// MARK: - Shoulder press

public struct PressParams: SyntheticPose, Equatable {
    /// Left (or both) shoulder–elbow–wrist angle.
    public var elbowAngle: Double
    public var elbowAngleRight: Double
    /// Backward lean of the torso from vertical, degrees.
    public var torsoLean: Double

    public init(elbowAngle: Double, elbowAngleRight: Double? = nil, torsoLean: Double = 0) {
        self.elbowAngle = elbowAngle
        self.elbowAngleRight = elbowAngleRight ?? elbowAngle
        self.torsoLean = torsoLean
    }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        Self(elbowAngle: SoloEngineTesting.lerpValue(a.elbowAngle, b.elbowAngle, s),
             elbowAngleRight: SoloEngineTesting.lerpValue(a.elbowAngleRight, b.elbowAngleRight, s),
             torsoLean: SoloEngineTesting.lerpValue(a.torsoLean, b.torsoLean, s))
    }

    public var body: Body {
        let lean = rad(torsoLean)
        var j: [LandmarkName: BodyPoint] = [:]
        for (s, g) in sides {
            let theta = rad(s == .left ? elbowAngle : elbowAngleRight)
            let hip = BodyPoint(f: 0, u: 0.95, lat: g * 0.11)
            let shoulder = BodyPoint(f: -Segment.torso * sin(lean), u: hip.u + Segment.torso * cos(lean), lat: g * 0.19)
            // forearm vertical; upper arm sets the elbow angle in the frontal plane
            let elbow = BodyPoint(f: shoulder.f, u: shoulder.u - Segment.upperArm * cos(theta),
                                  lat: shoulder.lat + g * Segment.upperArm * sin(theta))
            var wrist = elbow
            wrist.u += Segment.forearm
            j[joint(s, "hip")] = hip
            j[joint(s, "knee")] = BodyPoint(f: 0, u: 0.52, lat: g * 0.11)
            j[joint(s, "ankle")] = BodyPoint(f: 0, u: 0.08, lat: g * 0.11)
            j[joint(s, "shoulder")] = shoulder
            j[joint(s, "elbow")] = elbow
            j[joint(s, "wrist")] = wrist
        }
        let sh = j[.leftShoulder]!
        j[.nose] = BodyPoint(f: sh.f - Segment.neck * sin(lean), u: sh.u + Segment.neck * cos(lean), lat: 0)
        return completeBody(j)
    }
}

public func pressFrame(_ p: PressParams, _ o: FrameOptions) -> Frame { toFrame(p.body, o) }

// MARK: - Timeline

public struct TimelinePoint: Sendable, Equatable {
    public var t: Double
    /// Index of the rep in progress, or nil while resting.
    public var repIndex: Int?
    /// 0 at the start position, 1 at the turn point (mid-rep), back to 0.
    public var progress: Double
}

/// Frame times with a smooth (raised cosine) 0→1→0 progress per rep.
public func repTimeline(fps: Double, repDurationsMs: [Double], leadInMs: Double, restMs: Double, leadOutMs: Double) -> [TimelinePoint] {
    var windows: [(start: Double, end: Double)] = []
    var cursor = leadInMs
    for (i, duration) in repDurationsMs.enumerated() {
        if i > 0 { cursor += restMs }
        windows.append((cursor, cursor + duration))
        cursor += duration
    }
    let total = cursor + leadOutMs
    let step = 1000 / fps
    var points: [TimelinePoint] = []
    var i = 0
    while Double(i) * step <= total + 1e-9 {
        let t = Double(i) * step
        if let index = windows.firstIndex(where: { t >= $0.start && t < $0.end }) {
            let w = windows[index]
            let p = (t - w.start) / (w.end - w.start)
            points.append(TimelinePoint(t: t, repIndex: index, progress: (1 - cos(2 * Double.pi * p)) / 2))
        } else {
            points.append(TimelinePoint(t: t, repIndex: nil, progress: 0))
        }
        i += 1
    }
    return points
}

// MARK: - Sequences

public struct SyntheticRep<P: SyntheticPose> {
    public var target: P
    public var durationMs: Double
    public var label: RepLabel?

    public init(_ target: P, durationMs: Double = 2000, label: RepLabel? = nil) {
        self.target = target
        self.durationMs = durationMs
        self.label = label
    }
}

public struct SequenceOptions {
    public var facing: FrameOptions.Facing = .right
    public var fps: Double = 30
    public var noise: Double = 0
    public var seed: Int = 1
    public var leadInMs: Double = 2000
    public var restMs: Double = 800
    public var leadOutMs: Double = 1000
    public var farSideVisibility: Double = 0.4

    public init(facing: FrameOptions.Facing = .right, fps: Double = 30, noise: Double = 0, seed: Int = 1,
                leadInMs: Double = 2000, restMs: Double = 800, leadOutMs: Double = 1000, farSideVisibility: Double = 0.4) {
        self.facing = facing
        self.fps = fps
        self.noise = noise
        self.seed = seed
        self.leadInMs = leadInMs
        self.restMs = restMs
        self.leadOutMs = leadOutMs
        self.farSideVisibility = farSideVisibility
    }
}

public func buildSequence<P: SyntheticPose>(
    exerciseId: String, view: CameraView, start: P, reps: [SyntheticRep<P>], options o: SequenceOptions = .init()
) -> LandmarkSequence {
    let rng = SeededRandom(seed: o.seed)
    let timeline = repTimeline(fps: o.fps, repDurationsMs: reps.map(\.durationMs), leadInMs: o.leadInMs,
                               restMs: o.restMs, leadOutMs: o.leadOutMs)
    let frames = timeline.map { pt -> Frame in
        let params = pt.repIndex.map { P.lerp(start, reps[$0].target, pt.progress) } ?? start
        return toFrame(params.body, FrameOptions(view: view, facing: o.facing, t: pt.t, noise: o.noise, rng: rng,
                                                 farSideVisibility: o.farSideVisibility))
    }
    let labels = reps.allSatisfy { $0.label != nil } ? reps.map { $0.label! } : nil
    return LandmarkSequence(formatVersion: 1, skeleton: .mediapipe33, exerciseId: exerciseId, source: .synthetic,
                            view: view, fps: o.fps, labels: labels, frames: frames, hasWorld: true)
}

/// Unless a rep says otherwise, the torso leans further (30°) as the squat
/// deepens; pass the full target to override.
public func squatSequence(view: CameraView, reps: [SyntheticRep<SquatParams>],
                          start: SquatParams = SquatParams(kneeAngle: 172, torsoLean: 5),
                          options: SequenceOptions = .init()) -> LandmarkSequence {
    buildSequence(exerciseId: "squat", view: view, start: start, reps: reps, options: options)
}

/// A squat rep target with the source defaults: torsoLean 30 unless given, valgus from the start pose.
public func squatRep(kneeAngle: Double, torsoLean: Double = 30, valgus: Double = 0, durationMs: Double = 2000,
                     label: RepLabel? = nil) -> SyntheticRep<SquatParams> {
    SyntheticRep(SquatParams(kneeAngle: kneeAngle, torsoLean: torsoLean, valgus: valgus), durationMs: durationMs, label: label)
}

public func pushupSequence(reps: [SyntheticRep<PushupParams>], start: PushupParams = PushupParams(elbowAngle: 168),
                           options: SequenceOptions = .init()) -> LandmarkSequence {
    buildSequence(exerciseId: "pushup", view: .side, start: start, reps: reps, options: options)
}

public func pressSequence(view: CameraView, reps: [SyntheticRep<PressParams>],
                          start: PressParams = PressParams(elbowAngle: 85), options: SequenceOptions = .init()) -> LandmarkSequence {
    buildSequence(exerciseId: "shoulder_press", view: view, start: start, reps: reps, options: options)
}

public enum SoloEngineTesting {
    public static func lerpValue(_ a: Double, _ b: Double, _ s: Double) -> Double { lerp(a, b, s) }
}
