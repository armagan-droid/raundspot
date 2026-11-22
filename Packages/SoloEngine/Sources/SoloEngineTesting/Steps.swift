import Foundation
import SoloEngine

// A small rig for the warm-up and cool-down step demos (specs/04 "Adım
// gösterimleri"): joint angles in degrees, lengths in meters, the same body
// space as `Body.swift` (f forward, u up, lat to the person's left).

private func rad(_ d: Double) -> Double { d * .pi / 180 }
private func j(_ side: PersonSide, _ name: String) -> LandmarkName { LandmarkName(side: side, joint: name)! }

public struct StepPose: SyntheticPose, Equatable {
    public struct Arm: Equatable, Sendable {
        /// Raise toward the front (sagittal plane): 0 down, 90 forward, 180 up, 270 back.
        public var flex: Double
        /// Raise to the side (frontal plane): 0 down, 90 out; negative = across the body.
        public var abduct: Double
        /// Elbow bend, 0 = straight.
        public var elbow: Double

        public init(flex: Double = 0, abduct: Double = 8, elbow: Double = 10) {
            self.flex = flex
            self.abduct = abduct
            self.elbow = elbow
        }
    }

    public var left = Arm()
    public var right = Arm()
    /// Both knees, degrees from straight.
    public var knees: Double = 4
    /// Right leg swing from the hip, sagittal: positive forward.
    public var legSwing: Double = 0
    /// Pelvis shift over the feet (hip circles), meters.
    public var hipLat: Double = 0
    public var hipF: Double = 0
    /// Torso lean: forward and to the person's left, degrees.
    public var torsoF: Double = 0
    public var torsoSide: Double = 0
    /// Whole-body lift (jumps), meters; applied after framing.
    public var bounce: Double = 0
    /// Hands on the hips (overrides the arms).
    public var handsOnHips = false

    public init(left: Arm = Arm(), right: Arm = Arm(), knees: Double = 4, legSwing: Double = 0, hipLat: Double = 0, hipF: Double = 0,
                torsoF: Double = 0, torsoSide: Double = 0, bounce: Double = 0, handsOnHips: Bool = false) {
        self.handsOnHips = handsOnHips
        self.left = left
        self.right = right
        self.knees = knees
        self.legSwing = legSwing
        self.hipLat = hipLat
        self.hipF = hipF
        self.torsoF = torsoF
        self.torsoSide = torsoSide
        self.bounce = bounce
    }

    private static func mix(_ a: Double, _ b: Double, _ s: Double) -> Double { a + (b - a) * s }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        func arm(_ x: Arm, _ y: Arm) -> Arm {
            Arm(flex: mix(x.flex, y.flex, s), abduct: mix(x.abduct, y.abduct, s), elbow: mix(x.elbow, y.elbow, s))
        }
        return Self(left: arm(a.left, b.left), right: arm(a.right, b.right), knees: mix(a.knees, b.knees, s),
                    legSwing: mix(a.legSwing, b.legSwing, s), hipLat: mix(a.hipLat, b.hipLat, s), hipF: mix(a.hipF, b.hipF, s),
                    torsoF: mix(a.torsoF, b.torsoF, s), torsoSide: mix(a.torsoSide, b.torsoSide, s), bounce: mix(a.bounce, b.bounce, s),
                    handsOnHips: s < 0.5 ? a.handsOnHips : b.handsOnHips)
    }

    public var body: Body {
        var p: [LandmarkName: BodyPoint] = [:]
        let half = rad(knees) / 2
        for (side, g) in [(PersonSide.left, 1.0), (.right, -1.0)] {
            let ankle = BodyPoint(f: 0, u: 0.08, lat: g * 0.12)
            var knee = ankle.adding(f: Segment.shin * sin(half), u: Segment.shin * cos(half), lat: hipLat / 2)
            var hip = knee.adding(f: -Segment.thigh * sin(half) + hipF, u: Segment.thigh * cos(half), lat: hipLat / 2)
            var a = ankle
            if side == .right, legSwing != 0 {
                // standing on the left leg; the right one swings from the hip
                hip = p[.leftHip].map { BodyPoint(f: $0.f, u: $0.u, lat: $0.lat - 0.22) } ?? hip
                let sw = rad(legSwing)
                knee = hip.adding(f: Segment.thigh * sin(sw), u: -Segment.thigh * cos(sw), lat: 0)
                a = knee.adding(f: Segment.shin * sin(sw), u: -Segment.shin * cos(sw), lat: 0)
            }
            p[j(side, "ankle")] = a
            p[j(side, "knee")] = knee
            p[j(side, "hip")] = hip
        }
        let hipMid = BodyPoint(f: (p[.leftHip]!.f + p[.rightHip]!.f) / 2, u: (p[.leftHip]!.u + p[.rightHip]!.u) / 2,
                               lat: (p[.leftHip]!.lat + p[.rightHip]!.lat) / 2)
        let tf = rad(torsoF), ts = rad(torsoSide)
        let up = (f: sin(tf), u: cos(tf) * cos(ts), lat: sin(ts))
        let neckBase = hipMid.adding(f: Segment.torso * up.f, u: Segment.torso * up.u, lat: Segment.torso * up.lat)
        for (side, g, arm) in [(PersonSide.left, 1.0, left), (.right, -1.0, right)] {
            let shoulder = neckBase.adding(f: 0, u: 0, lat: g * 0.19)
            let ab = rad(arm.abduct), fl = rad(arm.flex)
            // abduction in the frontal plane, then flexion about the lateral axis
            let v = (f: cos(ab) * sin(fl), u: -cos(ab) * cos(fl), lat: g * sin(ab))
            let elbow = shoulder.adding(f: v.f * Segment.upperArm, u: v.u * Segment.upperArm, lat: v.lat * Segment.upperArm)
            // the forearm turns from the upper arm toward front-up by the elbow angle
            var w = (f: 0.45 - v.f * (0.45 * v.f + 0.9 * v.u), u: 0.9 - v.u * (0.45 * v.f + 0.9 * v.u), lat: -v.lat * (0.45 * v.f + 0.9 * v.u))
            let n = (w.f * w.f + w.u * w.u + w.lat * w.lat).squareRoot()
            if n < 1e-6 { w = (1, 0, 0) } else { w = (w.f / n, w.u / n, w.lat / n) }
            let e = rad(arm.elbow)
            let d = (f: v.f * cos(e) + w.f * sin(e), u: v.u * cos(e) + w.u * sin(e), lat: v.lat * cos(e) + w.lat * sin(e))
            p[j(side, "shoulder")] = shoulder
            if handsOnHips {
                // elbows out to the side, hands resting on the hips
                let hip = p[j(side, "hip")]!
                p[j(side, "elbow")] = BodyPoint(f: (shoulder.f + hip.f) / 2 - 0.03, u: (shoulder.u + hip.u) / 2 + 0.04, lat: shoulder.lat + g * 0.12)
                p[j(side, "wrist")] = hip.adding(f: 0.02, u: 0.05, lat: g * 0.05)
                continue
            }
            p[j(side, "elbow")] = elbow
            p[j(side, "wrist")] = elbow.adding(f: d.f * Segment.forearm, u: d.u * Segment.forearm, lat: d.lat * Segment.forearm)
        }
        p[.nose] = neckBase.adding(f: Segment.neck * up.f + 0.05, u: Segment.neck * up.u, lat: Segment.neck * up.lat)
        return completeBody(p)
    }
}

public enum StepDemos {
    public static let frameMs = DemoGenerator.frameMs

    private typealias A = StepPose.Arm

    /// The steps of the ready-made workouts (specs/06), each a short loop.
    public static let all: [String: (view: CameraView, path: [(StepPose, Double)])] = {
        let stand = StepPose()
        var out: [String: (view: CameraView, path: [(StepPose, Double)])] = [:]
        // light jumps in place, arms loose
        let dip = StepPose(left: A(abduct: 14, elbow: 25), right: A(abduct: 14, elbow: 25), knees: 30)
        let air = StepPose(left: A(abduct: 22, elbow: 15), right: A(abduct: 22, elbow: 15), knees: 6, bounce: 0.14)
        out["warmup.light_jumps"] = (.front, [(stand, 300), (dip, 250), (air, 250), (dip, 250), (air, 250), (dip, 250), (stand, 300)])
        // big arm circles, side view: forward, up, back, down
        func arms(_ a: Double) -> StepPose { StepPose(left: A(flex: a, abduct: 0, elbow: 5), right: A(flex: a, abduct: 0, elbow: 5)) }
        out["warmup.arm_circles"] = (.side, [(arms(0), 200), (arms(90), 400), (arms(180), 400), (arms(270), 400), (arms(359), 400), (arms(0), 100)])
        // hip circles, hands on the hips
        func hips(_ lat: Double, _ f: Double) -> StepPose {
            StepPose(knees: 10, hipLat: lat, hipF: f, handsOnHips: true)
        }
        out["warmup.hip_circles"] = (.front, [(hips(0, 0), 200), (hips(0.09, 0), 400), (hips(0, 0.06), 400), (hips(-0.09, 0), 400),
                                              (hips(0, -0.06), 400), (hips(0.09, 0), 400), (hips(0, 0), 300)])
        // light shadowboxing, side view: guard, jab, guard, cross, guard
        let guardArm = A(flex: 40, abduct: 10, elbow: 130)
        let guardPose = StepPose(left: guardArm, right: guardArm, knees: 14)
        var jab = guardPose; jab.left = A(flex: 88, abduct: 5, elbow: 5)
        var cross = guardPose; cross.right = A(flex: 88, abduct: -5, elbow: 5); cross.torsoSide = -6
        out["warmup.shadow"] = (.side, [(guardPose, 300), (jab, 200), (guardPose, 250), (cross, 220), (guardPose, 300), (jab, 200), (guardPose, 400)])
        // leg swings, side view
        func swing(_ s: Double) -> StepPose { StepPose(left: A(abduct: 30, elbow: 20), right: A(abduct: 30, elbow: 20), legSwing: s) }
        out["warmup.dynamic_stretch"] = (.side, [(swing(0.01), 200), (swing(55), 450), (swing(-25), 500), (swing(55), 500), (swing(0.01), 450)])
        // slow breathing: arms rise to the sides and come down
        let breathe = StepPose(left: A(abduct: 165, elbow: 5), right: A(abduct: 165, elbow: 5))
        out["cooldown.breathing"] = (.front, [(stand, 300), (breathe, 1800), (breathe, 400), (stand, 1800), (stand, 300)])
        // hip stretch: a deep lunge held, side view
        var lunge = StepPose(left: A(abduct: 20, elbow: 20), right: A(abduct: 20, elbow: 20), knees: 70, hipF: -0.12, torsoF: 4)
        lunge.legSwing = -35
        out["cooldown.hip_stretch"] = (.side, [(stand, 300), (lunge, 900), (lunge, 1400), (stand, 900)])
        // shoulder stretch: right arm across the chest, held by the left
        let across = StepPose(left: A(flex: 60, abduct: -20, elbow: 100), right: A(flex: 85, abduct: -70, elbow: 5))
        out["cooldown.shoulder_stretch"] = (.front, [(stand, 300), (across, 800), (across, 1600), (stand, 800)])
        return out
    }()

    public static func demo(_ key: String) -> ExerciseDemo? {
        guard let (view, path) = all[key] else { return nil }
        var frames: [[LandmarkName: GuidePoint]] = []
        let o = FrameOptions(view: view, facing: .right, farSideVisibility: 1)
        var from = path[0].0
        for (to, ms) in path {
            let n = max(1, Int((ms / Double(frameMs)).rounded()))
            for i in 0..<n {
                let s = (1 - cos(Double.pi * Double(i + 1) / Double(n))) / 2
                let pose = StepPose.lerp(from, to, s)
                let f = toFrame(pose.body, o)
                let lift = pose.bounce / o.scale
                frames.append(Dictionary(uniqueKeysWithValues: ExerciseDemo.joints.map { n in
                    (n, GuidePoint(x: f[image: n].x, y: f[image: n].y - lift))
                }))
            }
            from = to
        }
        let demo = ExerciseDemo(exercise: nil, step: key, view: view, aspect: 1, frameMs: frameMs, frames: frames)
        return try? ExerciseDemo.parse(JSONValue.parse(demo.json.serialized()))
    }
}
