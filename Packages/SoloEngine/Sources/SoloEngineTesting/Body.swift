import Foundation
import SoloEngine

// Minimal kinematic body model for synthetic fixtures, translated from the
// source `testing/body.ts` (commit c2fe3fd). Body space: f = forward (the
// direction the person faces), u = up from the floor, lat = lateral
// (positive = the person's left). Meters.

public struct BodyPoint: Sendable, Equatable {
    public var f: Double
    public var u: Double
    public var lat: Double

    public init(f: Double, u: Double, lat: Double) {
        self.f = f
        self.u = u
        self.lat = lat
    }

    func adding(f df: Double, u du: Double, lat dl: Double) -> BodyPoint {
        BodyPoint(f: f + df, u: u + du, lat: lat + dl)
    }
}

/// All 33 landmarks in body space.
public typealias Body = [LandmarkName: BodyPoint]

public enum Segment {
    public static let shin = 0.43
    public static let thigh = 0.45
    public static let torso = 0.52
    public static let upperArm = 0.3
    public static let forearm = 0.27
    public static let neck = 0.25
}

/// The joints exercise builders provide; the rest is derived by `completeBody`.
public enum CoreJoint {
    public static let names: [LandmarkName] = [
        .nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]
}

extension LandmarkName {
    /// The anatomical side in the name (`mouth_left` → left), or nil.
    public var side: PersonSide? {
        let parts = rawValue.split(separator: "_")
        if parts.contains("left") { return .left }
        if parts.contains("right") { return .right }
        return nil
    }

    /// The same landmark on the other side (`left_hip` ↔ `right_hip`, `mouth_left` ↔ `mouth_right`).
    public var mirrored: LandmarkName {
        guard let side else { return self }
        let raw = rawValue
        let from = side.rawValue, to = side.opposite.rawValue
        let range = raw.range(of: from)!
        return LandmarkName(rawValue: raw.replacingCharacters(in: range, with: to))!
    }
}

/// Fills face, hand and foot landmarks from the core joints.
public func completeBody(_ core: [LandmarkName: BodyPoint]) -> Body {
    let n = core[.nose]!
    var body = core
    for side in PersonSide.allCases {
        let g: Double = side == .left ? 1 : -1
        func j(_ joint: String) -> LandmarkName { LandmarkName(side: side, joint: joint)! }
        func hand(_ k: Double, _ dl: Double) -> BodyPoint {
            let w = core[j("wrist")]!, e = core[j("elbow")]!
            // continue a little along the forearm direction
            return BodyPoint(f: w.f + (w.f - e.f) * k, u: w.u + (w.u - e.u) * k, lat: w.lat + (w.lat - e.lat) * k + dl)
        }
        body[j("eye_inner")] = n.adding(f: -0.02, u: 0.03, lat: g * 0.015)
        body[j("eye")] = n.adding(f: -0.025, u: 0.03, lat: g * 0.03)
        body[j("eye_outer")] = n.adding(f: -0.03, u: 0.03, lat: g * 0.045)
        body[j("ear")] = n.adding(f: -0.1, u: 0.01, lat: g * 0.07)
        body[side == .left ? .mouthLeft : .mouthRight] = n.adding(f: -0.01, u: -0.04, lat: g * 0.025)
        body[j("pinky")] = hand(0.3, g * 0.02)
        body[j("index")] = hand(0.35, 0)
        body[j("thumb")] = hand(0.2, -g * 0.02)
        body[j("heel")] = core[j("ankle")]!.adding(f: -0.06, u: -0.06, lat: 0)
        body[j("foot_index")] = core[j("ankle")]!.adding(f: 0.15, u: -0.07, lat: 0)
    }
    return body
}

public struct FrameOptions {
    public enum Facing: Sendable { case left, right }

    public var view: CameraView
    /// Side view only: which way the person faces in the image.
    public var facing: Facing
    public var t: Double
    /// Image-space gaussian noise sigma (normalized units); world noise is scaled to meters.
    public var noise: Double
    public var rng: SeededRandom?
    public var nearVisibility: Double
    public var farSideVisibility: Double
    /// Meters covered by the full image width/height (orthographic camera).
    public var scale: Double

    public init(view: CameraView, facing: Facing = .right, t: Double = 0, noise: Double = 0, rng: SeededRandom? = nil,
                nearVisibility: Double = 0.95, farSideVisibility: Double = 0.4, scale: Double = 2.5) {
        self.view = view
        self.facing = facing
        self.t = t
        self.noise = noise
        self.rng = rng
        self.nearVisibility = nearVisibility
        self.farSideVisibility = farSideVisibility
        self.scale = scale
    }
}

/// Projects a body into a MediaPipe-like frame. World: hip-centered meters,
/// x right, y down, z away from the camera. Image: normalized [0, 1].
public func toFrame(_ body: Body, _ o: FrameOptions) -> Frame {
    let farSide: PersonSide? = o.view == .side ? (o.facing == .right ? .right : .left) : nil

    func toWorld(_ p: BodyPoint) -> (x: Double, y: Double, z: Double) {
        if o.view == .front { return (p.lat, -p.u, -p.f) }
        return o.facing == .right ? (p.f, -p.u, -p.lat) : (-p.f, -p.u, p.lat)
    }
    let raw = LandmarkName.allCases.map { toWorld(body[$0]!) }
    let lh = raw[LandmarkName.leftHip.index], rh = raw[LandmarkName.rightHip.index]
    let c = (x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2, z: (lh.z + rh.z) / 2)

    func jitter(_ sigma: Double) -> Double {
        guard sigma > 0, let rng = o.rng else { return 0 }
        return rng.gaussian(sigma)
    }
    var world: [Landmark] = []
    var image: [Landmark] = []
    for (i, p) in raw.enumerated() {
        let name = LandmarkName.allCases[i]
        let visibility = farSide != nil && name.side == farSide ? o.farSideVisibility : o.nearVisibility
        let w = (x: p.x - c.x, y: p.y - c.y, z: p.z - c.z)
        // Same draw order as the source: world x, y, z, then image x, y.
        let wx = w.x + jitter(o.noise * o.scale)
        let wy = w.y + jitter(o.noise * o.scale)
        let wz = w.z + jitter(o.noise * o.scale)
        world.append(Landmark(x: wx, y: wy, z: wz, visibility: visibility))
        let ix = 0.5 + w.x / o.scale + jitter(o.noise)
        let iy = 0.55 + w.y / o.scale + jitter(o.noise)
        image.append(Landmark(x: ix, y: iy, z: w.z / o.scale, visibility: visibility))
    }
    return Frame(t: o.t, image: image, world: world)
}

/// Horizontal mirror: left/right landmarks swap, image x → 1 − x, world x → −x.
public func mirrorFrame(_ frame: Frame) -> Frame {
    let mirror = LandmarkName.allCases.map { $0.mirrored.index }
    return Frame(
        t: frame.t,
        image: mirror.map { j in var p = frame.image[j]; p.x = 1 - p.x; return p },
        world: mirror.map { j in var p = frame.world[j]; p.x = -p.x; return p })
}
