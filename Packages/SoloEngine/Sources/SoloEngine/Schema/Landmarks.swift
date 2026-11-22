/// MediaPipe Pose landmark names in model index order (0–32). Templates keep
/// writing MediaPipe names; the Swift engine resolves them for Vision (specs/03).
public enum LandmarkName: String, CaseIterable, Sendable, Hashable, Comparable {
    case nose
    case leftEyeInner = "left_eye_inner"
    case leftEye = "left_eye"
    case leftEyeOuter = "left_eye_outer"
    case rightEyeInner = "right_eye_inner"
    case rightEye = "right_eye"
    case rightEyeOuter = "right_eye_outer"
    case leftEar = "left_ear"
    case rightEar = "right_ear"
    case mouthLeft = "mouth_left"
    case mouthRight = "mouth_right"
    case leftShoulder = "left_shoulder"
    case rightShoulder = "right_shoulder"
    case leftElbow = "left_elbow"
    case rightElbow = "right_elbow"
    case leftWrist = "left_wrist"
    case rightWrist = "right_wrist"
    case leftPinky = "left_pinky"
    case rightPinky = "right_pinky"
    case leftIndex = "left_index"
    case rightIndex = "right_index"
    case leftThumb = "left_thumb"
    case rightThumb = "right_thumb"
    case leftHip = "left_hip"
    case rightHip = "right_hip"
    case leftKnee = "left_knee"
    case rightKnee = "right_knee"
    case leftAnkle = "left_ankle"
    case rightAnkle = "right_ankle"
    case leftHeel = "left_heel"
    case rightHeel = "right_heel"
    case leftFootIndex = "left_foot_index"
    case rightFootIndex = "right_foot_index"

    public static let count = 33

    /// Index in a 33-element frame array.
    public var index: Int { Self.indexByName[self]! }

    private static let indexByName: [LandmarkName: Int] =
        Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })

    public static func < (lhs: LandmarkName, rhs: LandmarkName) -> Bool { lhs.index < rhs.index }

    /// The landmark for a side and bilateral joint, e.g. `.left` + `"hip"` → `left_hip`.
    public init?(side: PersonSide, joint: String) {
        self.init(rawValue: "\(side.rawValue)_\(joint)")
    }
}

/// The person's anatomical side (ref 04 "Kişinin solu").
public enum PersonSide: String, CaseIterable, Sendable, Hashable {
    case left, right

    public var opposite: PersonSide { self == .left ? .right : .left }
}

/// A landmark name or a virtual `near_`/`far_` landmark (ref 04 "Sanal noktalar").
/// `lead_`/`rear_` are v1.0 (specs/04) and not accepted yet.
public enum LandmarkRef: Sendable, Hashable, CustomStringConvertible {
    case landmark(LandmarkName)
    case near(joint: String)
    case far(joint: String)

    /// Joints that exist on both sides, e.g. `"hip"` for `left_hip`/`right_hip`.
    public static let bilateralJoints: [String] = LandmarkName.allCases.compactMap { name in
        let raw = name.rawValue
        guard raw.hasPrefix("left_") else { return nil }
        let joint = String(raw.dropFirst(5))
        return LandmarkName(rawValue: "right_\(joint)") == nil ? nil : joint
    }

    public init?(_ raw: String) {
        if let name = LandmarkName(rawValue: raw) {
            self = .landmark(name)
        } else if raw.hasPrefix("near_"), Self.bilateralJoints.contains(String(raw.dropFirst(5))) {
            self = .near(joint: String(raw.dropFirst(5)))
        } else if raw.hasPrefix("far_"), Self.bilateralJoints.contains(String(raw.dropFirst(4))) {
            self = .far(joint: String(raw.dropFirst(4)))
        } else {
            return nil
        }
    }

    public var description: String {
        switch self {
        case .landmark(let name): name.rawValue
        case .near(let joint): "near_\(joint)"
        case .far(let joint): "far_\(joint)"
        }
    }

    /// Resolves against the near side of the current setup (ref 04, source `resolveLandmark`).
    public func resolve(near: PersonSide) -> LandmarkName {
        switch self {
        case .landmark(let name): name
        case .near(let joint): LandmarkName(side: near, joint: joint)!
        case .far(let joint): LandmarkName(side: near.opposite, joint: joint)!
        }
    }

    /// Every concrete landmark this reference can resolve to (both sides for near_/far_).
    public var possibleLandmarks: [LandmarkName] {
        switch self {
        case .landmark(let name): [name]
        case .near(let joint), .far(let joint):
            [LandmarkName(side: .left, joint: joint)!, LandmarkName(side: .right, joint: joint)!]
        }
    }
}

/// Pose model joint sets (specs/03 "Apple Vision eklem setleri").
public enum Skeleton: String, CaseIterable, Sendable, Hashable {
    case mediapipe33
    case vision19

    /// MediaPipe-named landmarks the skeleton provides in image (2D) coordinates.
    public var landmarks: Set<LandmarkName> {
        switch self {
        case .mediapipe33: Set(LandmarkName.allCases)
        case .vision19: Self.vision19Landmarks
        }
    }

    /// Vision 2D joints expressed with MediaPipe names. Vision's own `neck` and
    /// `root` have no MediaPipe name and are not used by templates.
    public static let vision19Landmarks: Set<LandmarkName> = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]

    /// MediaPipe landmarks Vision does not provide (16, specs/03 "Eksik eklemler").
    public static var vision19Missing: Set<LandmarkName> {
        Set(LandmarkName.allCases).subtracting(vision19Landmarks)
    }
}
