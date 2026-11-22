import SoloEngine

/// Vision 2D body joints (specs/03 "2B — DetectHumanBodyPoseRequest").
public enum VisionJoint: String, CaseIterable, Sendable, Hashable {
    case nose, leftEye, rightEye, leftEar, rightEar, neck
    case leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

    /// The MediaPipe name templates use (specs/03 "Eşleme tablosu"); `neck`
    /// and `root` have none and are not used by templates.
    public var landmark: LandmarkName? {
        switch self {
        case .nose: .nose
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .leftEar: .leftEar
        case .rightEar: .rightEar
        case .neck, .root: nil
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftElbow: .leftElbow
        case .rightElbow: .rightElbow
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        }
    }
}

/// One detected joint in Vision's normalized coordinates: origin bottom-left,
/// in the upright image (the orientation was given to the request).
public struct DetectedJoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// One Vision body observation.
public struct DetectedPose: Sendable, Equatable {
    public var confidence: Double
    public var joints: [VisionJoint: DetectedJoint]

    public init(confidence: Double, joints: [VisionJoint: DetectedJoint]) {
        self.confidence = confidence
        self.joints = joints
    }
}

/// The clockwise rotation that makes a camera buffer upright, degrees.
public enum UprightRotation: Int, Sendable, CaseIterable {
    case r0 = 0, r90 = 90, r180 = 180, r270 = 270

    /// Nearest quarter turn of an `AVCaptureDevice.RotationCoordinator` angle.
    public init(degrees: Double) {
        let q = Int((degrees / 90).rounded()) % 4
        self = [.r0, .r90, .r180, .r270][(q + 4) % 4]
    }

    /// Upright width / height of a buffer of this size (specs/03 `imageAspect`).
    public func uprightAspect(width: Int, height: Int) -> Double {
        let w = Double(width), h = Double(height)
        return self == .r90 || self == .r270 ? h / w : w / h
    }
}

/// Vision observation → `Frame` (specs/03 "Koordinat dönüşümü").
public enum FrameMapper {
    /// - image: `x' = x`, `y' = 1 − y`; never mirrored (specs/02).
    /// - visibility: the Vision confidence; an undetected joint has visibility 0.
    /// - the 16 joints Vision lacks are missing (NaN, visibility 0), as in `vision19`.
    /// - world: all missing (H2, 2D only).
    public static func frame(_ pose: DetectedPose, t: Double, imageAspect: Double) -> Frame {
        var image = Array(repeating: Landmark.missing, count: LandmarkName.count)
        for joint in VisionJoint.allCases {
            guard let name = joint.landmark else { continue }
            if let j = pose.joints[joint], j.confidence > 0, j.x.isFinite, j.y.isFinite {
                image[name.index] = Landmark(x: j.x, y: 1 - j.y, z: 0, visibility: j.confidence)
            } else {
                image[name.index] = Landmark(x: 0, y: 0, z: 0, visibility: 0)
            }
        }
        return Frame(t: t, image: image, world: Array(repeating: .missing, count: LandmarkName.count), imageAspect: imageAspect)
    }

    /// Candidates for person selection (ref 07 "Seçim kuralları"): the most
    /// confident observations first, at most `PersonSelectionRules.maxCandidates`.
    public static func candidates(_ poses: [DetectedPose], t: Double, imageAspect: Double) -> [Frame] {
        poses.sorted { $0.confidence > $1.confidence }
            .prefix(PersonSelectionRules.maxCandidates)
            .map { frame($0, t: t, imageAspect: imageAspect) }
    }
}
