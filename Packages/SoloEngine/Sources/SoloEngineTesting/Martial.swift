import Foundation
import SoloEngine

// Fighting stance and head-movement bodies, translated from the source
// `testing/martial.ts` and the `fighterSequence` / `evaderSequence` builders
// (commit c2fe3fd). Every limb moves in its own sagittal plane, so world
// angles are exact.

private func rad(_ deg: Double) -> Double { deg * Double.pi / 180 }
private func mix(_ a: Double, _ b: Double, _ s: Double) -> Double { a + (b - a) * s }
private func clamp01(_ x: Double) -> Double { Swift.max(0, Swift.min(1, x)) }
private let sides: [(PersonSide, Double)] = [(.left, 1), (.right, -1)]
private func joint(_ side: PersonSide, _ name: String) -> LandmarkName { LandmarkName(side: side, joint: name)! }

// MARK: - Fighter (side view)

public struct FighterParams: SyntheticPose, Equatable {
    /// Leg that kicks or strikes with the knee (fixed for a sequence).
    public var kickSide: PersonSide
    /// Thigh angle forward from straight down, degrees (0 = standing, 90 = thigh horizontal).
    public var hipFlex: Double
    /// Kicking leg hip–knee–ankle angle (180 = straight).
    public var kneeAngle: Double
    /// Arm that punches (fixed for a sequence).
    public var punchSide: PersonSide
    /// Punching arm shoulder–elbow–wrist angle: 35 = guard, 175 = fully extended.
    public var punchElbow: Double
    /// Non-punching hands: 0 = guard (hands at the chin), 1 = dropped to the sides.
    public var guardDrop: Double
    /// Backward lean of the torso from vertical, degrees.
    public var torsoLean: Double

    public init(kickSide: PersonSide = .right, hipFlex: Double = 0, kneeAngle: Double = 180, punchSide: PersonSide = .right,
                punchElbow: Double = 35, guardDrop: Double = 0, torsoLean: Double = 0) {
        self.kickSide = kickSide
        self.hipFlex = hipFlex
        self.kneeAngle = kneeAngle
        self.punchSide = punchSide
        self.punchElbow = punchElbow
        self.guardDrop = guardDrop
        self.torsoLean = torsoLean
    }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        Self(kickSide: a.kickSide, hipFlex: SoloEngineTesting.lerpValue(a.hipFlex, b.hipFlex, s),
             kneeAngle: SoloEngineTesting.lerpValue(a.kneeAngle, b.kneeAngle, s), punchSide: a.punchSide,
             punchElbow: SoloEngineTesting.lerpValue(a.punchElbow, b.punchElbow, s),
             guardDrop: SoloEngineTesting.lerpValue(a.guardDrop, b.guardDrop, s),
             torsoLean: SoloEngineTesting.lerpValue(a.torsoLean, b.torsoLean, s))
    }

    /// Guard: upper arm slightly forward, forearm up. Extension swings the upper arm to horizontal.
    private static func arm(_ shoulder: BodyPoint, elbowAngle: Double, shoulderFlex: Double) -> (BodyPoint, BodyPoint) {
        let a = rad(shoulderFlex)
        let elbow = BodyPoint(f: shoulder.f + Segment.upperArm * sin(a), u: shoulder.u - Segment.upperArm * cos(a), lat: shoulder.lat)
        let b = a + rad(180 - elbowAngle)
        let wrist = BodyPoint(f: elbow.f + Segment.forearm * sin(b), u: elbow.u - Segment.forearm * cos(b), lat: shoulder.lat)
        return (elbow, wrist)
    }

    public var body: Body {
        let lean = rad(torsoLean)
        var j: [LandmarkName: BodyPoint] = [:]
        for (s, g) in sides {
            let lat = g * 0.12
            let hip = BodyPoint(f: 0, u: 0.08 + Segment.shin + Segment.thigh, lat: lat)
            var knee = BodyPoint(f: 0, u: hip.u - Segment.thigh, lat: lat)
            var ankle = BodyPoint(f: 0, u: 0.08, lat: lat)
            if s == kickSide {
                let th = rad(hipFlex)
                knee = BodyPoint(f: hip.f + Segment.thigh * sin(th), u: hip.u - Segment.thigh * cos(th), lat: lat)
                let ph = th - rad(180 - kneeAngle)
                ankle = BodyPoint(f: knee.f + Segment.shin * sin(ph), u: knee.u - Segment.shin * cos(ph), lat: lat)
            }
            let shoulder = BodyPoint(f: -Segment.torso * sin(lean), u: hip.u + Segment.torso * cos(lean), lat: g * 0.19)
            let ext = clamp01((punchElbow - 35) / 140)
            let (elbow, wrist) = s == punchSide
                ? Self.arm(shoulder, elbowAngle: punchElbow, shoulderFlex: mix(25, 85, ext))
                : Self.arm(shoulder, elbowAngle: mix(35, 175, guardDrop), shoulderFlex: mix(25, 5, guardDrop))
            j[joint(s, "hip")] = hip
            j[joint(s, "knee")] = knee
            j[joint(s, "ankle")] = ankle
            j[joint(s, "shoulder")] = shoulder
            j[joint(s, "elbow")] = elbow
            j[joint(s, "wrist")] = wrist
        }
        let sh = j[.leftShoulder]!
        j[.nose] = BodyPoint(f: sh.f + 0.05 - Segment.neck * sin(lean), u: sh.u + Segment.neck * cos(lean), lat: 0)
        return completeBody(j)
    }
}

public func fighterFrame(_ p: FighterParams, _ o: FrameOptions) -> Frame { toFrame(p.body, o) }

/// Kicks, knees and punches, side view. The source start pose: knee 175, guard.
public func fighterSequence(exerciseId: String, reps: [SyntheticRep<FighterParams>],
                            start: FighterParams = FighterParams(kneeAngle: 175),
                            options: SequenceOptions = .init()) -> LandmarkSequence {
    buildSequence(exerciseId: exerciseId, view: .side, start: start, reps: reps, options: options)
}

// MARK: - Evader (front view)

public struct EvaderParams: SyntheticPose, Equatable {
    public enum DropSide: Sendable, Equatable { case left, right, both }

    /// Sideways lean of the torso and head from the hips, degrees; positive = toward the person's left.
    public var slip: Double
    /// Hip–knee–ankle angle of both legs (180 = straight); lower = deeper duck.
    public var kneeAngle: Double
    /// Forward lean of the torso, degrees (ducks bend at the waist too).
    public var torsoLean: Double
    /// Shoulders stay square while only the neck tilts, degrees toward the left.
    public var neckTilt: Double
    /// 0 = guard (hands at the chin), 1 = hands dropped.
    public var guardDrop: Double
    /// Which hand drops with guardDrop (fixed for a sequence).
    public var dropSide: DropSide

    public init(slip: Double = 0, kneeAngle: Double = 165, torsoLean: Double = 0, neckTilt: Double = 0,
                guardDrop: Double = 0, dropSide: DropSide = .both) {
        self.slip = slip
        self.kneeAngle = kneeAngle
        self.torsoLean = torsoLean
        self.neckTilt = neckTilt
        self.guardDrop = guardDrop
        self.dropSide = dropSide
    }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        Self(slip: SoloEngineTesting.lerpValue(a.slip, b.slip, s),
             kneeAngle: SoloEngineTesting.lerpValue(a.kneeAngle, b.kneeAngle, s),
             torsoLean: SoloEngineTesting.lerpValue(a.torsoLean, b.torsoLean, s),
             neckTilt: SoloEngineTesting.lerpValue(a.neckTilt, b.neckTilt, s),
             guardDrop: SoloEngineTesting.lerpValue(a.guardDrop, b.guardDrop, s), dropSide: a.dropSide)
    }

    /// Front-facing boxer in a square stance for head-movement drills (ref 04 "Eskiv").
    public var body: Body {
        let a = rad((180 - kneeAngle) / 2)
        let s = rad(slip)
        let lean = rad(torsoLean)
        var j: [LandmarkName: BodyPoint] = [:]
        var hipMid = BodyPoint(f: 0, u: 0, lat: 0)
        for (side, g) in sides {
            let ankle = BodyPoint(f: 0, u: 0.08, lat: g * 0.2)
            let knee = BodyPoint(f: Segment.shin * sin(a), u: ankle.u + Segment.shin * cos(a), lat: g * 0.18)
            let hip = BodyPoint(f: knee.f - Segment.thigh * sin(a), u: knee.u + Segment.thigh * cos(a), lat: g * 0.12)
            hipMid.f = hip.f
            hipMid.u = hip.u
            j[joint(side, "ankle")] = ankle
            j[joint(side, "knee")] = knee
            j[joint(side, "hip")] = hip
        }
        // torso: rotate the upright shoulder line about the hip midpoint (lateral tilt, then forward lean)
        let up = BodyPoint(f: sin(lean) * cos(s), u: cos(lean) * cos(s), lat: sin(s))
        let across = BodyPoint(f: 0, u: -sin(s), lat: cos(s))  // toward the person's left
        let shMid = BodyPoint(f: hipMid.f + Segment.torso * up.f, u: hipMid.u + Segment.torso * up.u, lat: Segment.torso * up.lat)
        for (side, g) in sides {
            let shoulder = BodyPoint(f: shMid.f + g * 0.19 * across.f, u: shMid.u + g * 0.19 * across.u,
                                     lat: shMid.lat + g * 0.19 * across.lat)
            let drops = dropSide == .both || (dropSide == .left && side == .left) || (dropSide == .right && side == .right)
            let dropped = drops ? guardDrop : 0
            let elbow = BodyPoint(f: shoulder.f + mix(0.15, 0, dropped), u: shoulder.u - Segment.upperArm * mix(0.85, 1, dropped),
                                  lat: shoulder.lat - g * 0.04)
            let wrist = BodyPoint(f: elbow.f + mix(0.08, 0, dropped), u: elbow.u + Segment.forearm * mix(0.95, -1, dropped),
                                  lat: shoulder.lat - g * 0.12)
            j[joint(side, "shoulder")] = shoulder
            j[joint(side, "elbow")] = elbow
            j[joint(side, "wrist")] = wrist
        }
        let n = rad(neckTilt)
        let neckUp = BodyPoint(f: up.f, u: up.u, lat: up.lat + sin(n))
        let len = (neckUp.f * neckUp.f + neckUp.u * neckUp.u + neckUp.lat * neckUp.lat).squareRoot()
        j[.nose] = BodyPoint(f: shMid.f + Segment.neck * (neckUp.f / len) + 0.05, u: shMid.u + Segment.neck * (neckUp.u / len),
                             lat: shMid.lat + Segment.neck * (neckUp.lat / len))
        return completeBody(j)
    }
}

public func evaderFrame(_ p: EvaderParams, _ o: FrameOptions) -> Frame { toFrame(p.body, o) }

/// Head-movement drills, front view; the hand that drops with guardDrop is fixed for the sequence.
public func evaderSequence(exerciseId: String, reps: [SyntheticRep<EvaderParams>], start: EvaderParams = EvaderParams(),
                           options: SequenceOptions = .init()) -> LandmarkSequence {
    buildSequence(exerciseId: exerciseId, view: .front, start: start, reps: reps, options: options)
}
