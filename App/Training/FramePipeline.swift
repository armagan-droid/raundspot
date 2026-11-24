import CoreMedia
import CoreVideo
import Foundation
import SoloCapture
import SoloEngine
import SoloPose

/// Camera queue work: Vision 2D on each frame, then the candidate `Frame`s to
/// the main actor (specs/02 "Akış": no image work on the main thread).
nonisolated final class FramePipeline: @unchecked Sendable {
    private let detector = PoseDetector()
    private let deliver: @Sendable (_ candidates: [Frame], _ t: Double) -> Void

    init(deliver: @escaping @Sendable (_ candidates: [Frame], _ t: Double) -> Void) {
        self.deliver = deliver
    }

    /// Recording mode (Beta, specs/09): the frame and what Vision saw, on the camera queue.
    var record: (@Sendable (_ pixelBuffer: CVPixelBuffer, _ pts: CMTime, _ poses: [DetectedPose]) -> Void)?

    func process(_ frame: CameraFrame) {
        let rotation = UprightRotation(degrees: frame.rotationDegrees)
        let aspect = rotation.uprightAspect(width: frame.width, height: frame.height)
        let poses = (try? detector.detect(frame.pixelBuffer, rotation: rotation)) ?? []
        record?(frame.pixelBuffer, frame.pts, poses)
        deliver(FrameMapper.candidates(poses, t: frame.hostTimeMs, imageAspect: aspect), frame.hostTimeMs)
    }
}
