#if canImport(Vision)
import CoreVideo
import ImageIO
import Vision

/// Runs Vision 2D body pose on one camera buffer (specs/02 "Akış"; H2).
/// Synchronous: call it on the camera queue, never on the main thread.
public final class PoseDetector {
    private let request = VNDetectHumanBodyPoseRequest()

    public init() {}

    public func detect(_ buffer: CVPixelBuffer, rotation: UprightRotation) throws -> [DetectedPose] {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: rotation.imageOrientation)
        try handler.perform([request])
        return (request.results ?? []).map { obs in
            var joints: [VisionJoint: DetectedJoint] = [:]
            let points = (try? obs.recognizedPoints(.all)) ?? [:]
            for joint in VisionJoint.allCases {
                guard let p = points[joint.visionName] else { continue }
                joints[joint] = DetectedJoint(x: Double(p.location.x), y: Double(p.location.y), confidence: Double(p.confidence))
            }
            return DetectedPose(confidence: Double(obs.confidence), joints: joints)
        }
    }
}

extension UprightRotation {
    /// The EXIF orientation of a buffer that needs this clockwise turn; never mirrored.
    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .r0: .up
        case .r90: .right
        case .r180: .down
        case .r270: .left
        }
    }
}

extension VisionJoint {
    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose: .nose
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .leftEar: .leftEar
        case .rightEar: .rightEar
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftElbow: .leftElbow
        case .rightElbow: .rightElbow
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        case .root: .root
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        }
    }
}
#endif
