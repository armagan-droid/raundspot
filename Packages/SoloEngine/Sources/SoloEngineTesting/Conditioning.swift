import Foundation
import SoloEngine

// Synthetic bodies for this project's conditioning templates (specs/04
// "Yeni şablonlar"): reverse lunge (side view) and jumping jack (front view).
// Same body space as `Body.swift`.

private func rad(_ deg: Double) -> Double { deg * Double.pi / 180 }
private func joint(_ side: PersonSide, _ name: String) -> LandmarkName { LandmarkName(side: side, joint: name)! }
private func mix(_ a: Double, _ b: Double, _ s: Double) -> Double { SoloEngineTesting.lerpValue(a, b, s) }

// MARK: - Reverse lunge

public struct LungeParams: SyntheticPose, Equatable {
    /// Hip–knee–ankle angle of both knees, 180 = standing.
    public var kneeAngle: Double
    /// Hip→shoulder lean from vertical, degrees forward.
    public var torsoLean: Double
    /// The leg that steps back.
    public var backLeg: PersonSide

    public init(kneeAngle: Double = 178, torsoLean: Double = 0, backLeg: PersonSide = .right) {
        self.kneeAngle = kneeAngle
        self.torsoLean = torsoLean
        self.backLeg = backLeg
    }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        Self(kneeAngle: mix(a.kneeAngle, b.kneeAngle, s), torsoLean: mix(a.torsoLean, b.torsoLean, s),
             backLeg: s > 0 ? b.backLeg : a.backLeg)
    }

    public var body: Body {
        let theta = rad(kneeAngle)
        var j: [LandmarkName: BodyPoint] = [:]
        // front leg: vertical shin, the thigh turns back by the knee angle
        let frontSide = backLeg.opposite
        let fg: Double = frontSide == .left ? 1 : -1
        let frontAnkle = BodyPoint(f: 0, u: 0, lat: fg * 0.11)
        let frontKnee = BodyPoint(f: 0, u: Segment.shin, lat: fg * 0.11)
        let hip = (f: frontKnee.f - Segment.thigh * sin(theta), u: frontKnee.u - Segment.thigh * cos(theta))
        // back leg: the thigh tilts back by half the bend, the shin closes the same knee angle
        let beta = (Double.pi - theta) / 2
        let bg = -fg
        let backKnee = BodyPoint(f: hip.f - Segment.thigh * sin(beta), u: hip.u - Segment.thigh * cos(beta), lat: bg * 0.11)
        let phi = Double.pi / 2 - beta + theta  // knee→ankle direction, from +f
        let backAnkle = BodyPoint(f: backKnee.f + Segment.shin * cos(phi), u: backKnee.u + Segment.shin * sin(phi), lat: bg * 0.11)
        j[joint(frontSide, "ankle")] = frontAnkle
        j[joint(frontSide, "knee")] = frontKnee
        j[joint(backLeg, "knee")] = backKnee
        j[joint(backLeg, "ankle")] = backAnkle
        let lean = rad(torsoLean)
        for (s, g) in [(PersonSide.left, 1.0), (.right, -1.0)] {
            let h = BodyPoint(f: hip.f, u: hip.u, lat: g * 0.11)
            let shoulder = BodyPoint(f: h.f + Segment.torso * sin(lean), u: h.u + Segment.torso * cos(lean), lat: g * 0.19)
            j[joint(s, "hip")] = h
            j[joint(s, "shoulder")] = shoulder
            j[joint(s, "elbow")] = shoulder.adding(f: 0, u: -Segment.upperArm, lat: 0)
            j[joint(s, "wrist")] = shoulder.adding(f: 0.02, u: -Segment.upperArm - Segment.forearm, lat: 0)
        }
        let sh = j[.leftShoulder]!
        j[.nose] = BodyPoint(f: sh.f + Segment.neck * sin(lean) + 0.05, u: sh.u + Segment.neck * cos(lean), lat: 0)
        // stand on the floor
        let floor = Swift.min(j[.leftAnkle]!.u, j[.rightAnkle]!.u) - 0.08
        for (k, p) in j { j[k] = p.adding(f: 0, u: -floor, lat: 0) }
        return completeBody(j)
    }
}

public func lungeFrame(_ p: LungeParams, _ o: FrameOptions) -> Frame { toFrame(p.body, o) }

public func lungeSequence(reps: [SyntheticRep<LungeParams>], start: LungeParams = LungeParams(),
                          options: SequenceOptions = .init()) -> LandmarkSequence {
    buildSequence(exerciseId: "reverse_lunge", view: .side, start: start, reps: reps, options: options)
}

// MARK: - Jumping jack

public struct JackParams: SyntheticPose, Equatable {
    /// Straight arms raised sideways from the body, degrees: 0 = down, 180 = overhead.
    public var armRaise: Double
    /// Each ankle's sideways shift from under the hip, meters.
    public var legSpread: Double

    public init(armRaise: Double = 5, legSpread: Double = 0) {
        self.armRaise = armRaise
        self.legSpread = legSpread
    }

    public static func lerp(_ a: Self, _ b: Self, _ s: Double) -> Self {
        Self(armRaise: mix(a.armRaise, b.armRaise, s), legSpread: mix(a.legSpread, b.legSpread, s))
    }

    public var body: Body {
        let leg = Segment.thigh + Segment.shin
        let hipU = 0.08 + (leg * leg - legSpread * legSpread).squareRoot()
        let a = rad(armRaise)
        var j: [LandmarkName: BodyPoint] = [:]
        for (s, g) in [(PersonSide.left, 1.0), (.right, -1.0)] {
            let hip = BodyPoint(f: 0, u: hipU, lat: g * 0.11)
            let ankle = BodyPoint(f: 0, u: 0.08, lat: g * (0.11 + legSpread))
            let k = Segment.thigh / leg
            let shoulder = BodyPoint(f: 0, u: hipU + Segment.torso, lat: g * 0.19)
            let dir = (lat: g * sin(a), u: -cos(a))
            let elbow = shoulder.adding(f: 0, u: dir.u * Segment.upperArm, lat: dir.lat * Segment.upperArm)
            j[joint(s, "hip")] = hip
            j[joint(s, "knee")] = BodyPoint(f: 0, u: mix(hip.u, ankle.u, k), lat: mix(hip.lat, ankle.lat, k))
            j[joint(s, "ankle")] = ankle
            j[joint(s, "shoulder")] = shoulder
            j[joint(s, "elbow")] = elbow
            j[joint(s, "wrist")] = elbow.adding(f: 0, u: dir.u * Segment.forearm, lat: dir.lat * Segment.forearm)
        }
        j[.nose] = BodyPoint(f: 0.05, u: hipU + Segment.torso + Segment.neck, lat: 0)
        return completeBody(j)
    }
}

public func jackFrame(_ p: JackParams, _ o: FrameOptions) -> Frame { toFrame(p.body, o) }

public func jackSequence(reps: [SyntheticRep<JackParams>], start: JackParams = JackParams(),
                         options: SequenceOptions = .init()) -> LandmarkSequence {
    buildSequence(exerciseId: "jumping_jack", view: .front, start: start, reps: reps, options: options)
}
