import SoloEngine

// `toVision19` (specs/03 "`vision19` iskeleti ve şema"): reduces a MediaPipe
// frame to what Apple Vision provides, so that source sequences can drive the
// new behavior's tests and snapshots.

/// Landmarks Vision 2D has but Vision 3D does not (specs/03: nose, eyes, ears).
public let vision3DMissing: Set<LandmarkName> = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]

/// Drops the 16 joints Vision lacks (image and world). In world, the nose
/// becomes the `centerHead` estimate (midpoint of the ears, visibility from
/// the 2D nose) and the eyes and ears are missing. With `world: false` every
/// world point is missing (H2, no 3D).
public func toVision19(_ frame: Frame, world keepWorld: Bool = true) -> Frame {
    var out = frame
    for name in Skeleton.vision19Missing {
        out.image[name.index] = .missing
        out.world[name.index] = .missing
    }
    guard keepWorld else {
        out.world = Array(repeating: .missing, count: LandmarkName.count)
        return out
    }
    let le = frame[world: .leftEar], re = frame[world: .rightEar]
    let centerHead = Landmark(x: (le.x + re.x) / 2, y: (le.y + re.y) / 2, z: (le.z + re.z) / 2,
                              visibility: frame[image: .nose].visibility)
    for name in vision3DMissing { out.world[name.index] = .missing }
    out.world[LandmarkName.nose.index] = centerHead
    return out
}

/// A `formatVersion: 2` `vision19` copy of a sequence.
public func toVision19(_ seq: LandmarkSequence, world keepWorld: Bool = true) -> LandmarkSequence {
    var out = seq
    out.formatVersion = 2
    out.skeleton = .vision19
    out.hasWorld = keepWorld && seq.hasWorld
    out.frames = seq.frames.map { toVision19($0, world: out.hasWorld) }
    return out
}
