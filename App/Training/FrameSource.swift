import AVFoundation
import Foundation
import SoloCapture
import SoloEngine

/// Where the training screen's pose frames come from (specs/02 "Akış"): the
/// camera through Vision, or a landmark sequence file replayed on a clock (the
/// Debug fake camera, AC-2.2 tests). Candidates carry host times, ms.
protocol FrameSource: AnyObject {
    /// The live camera needs the user's permission first.
    var needsCameraAccess: Bool { get }
    var isFrontCamera: Bool { get }
    var dropped: Int { get }
    var horizontalFOVDegrees: Double? { get }
    /// The capture session, for the preview and its interruption notices.
    var captureSession: AVCaptureSession? { get }
    func start(deliver: @escaping @Sendable (_ candidates: [Frame], _ t: Double) -> Void) throws
    func stop()
    /// Degraded operation (specs/02 "Kademeli çalışma"): at most this many frames per second.
    func limitFrameRate(_ fps: Double)
}

/// The camera and Vision 2D (T3.1, T3.2).
final class CameraFrameSource: FrameSource {
    let camera: CameraSession
    private var pipeline: FramePipeline?

    init(position: AVCaptureDevice.Position = .front) { camera = CameraSession(position: position) }

    var needsCameraAccess: Bool { true }
    var isFrontCamera: Bool { camera.position == .front }
    var dropped: Int { camera.dropped }
    var horizontalFOVDegrees: Double? { camera.horizontalFOVDegrees }
    var captureSession: AVCaptureSession? { camera.session }

    func start(deliver: @escaping @Sendable ([Frame], Double) -> Void) throws {
        let pipeline = FramePipeline(deliver: deliver)
        self.pipeline = pipeline
        try camera.configure { frame in pipeline.process(frame) }
        camera.start()
    }

    func stop() { camera.stop() }

    func limitFrameRate(_ fps: Double) { camera.setFrameRate(Int32(fps)) }
}

/// A landmark sequence replayed on a clock, looping (specs/02 "Derleme
/// yapılandırmaları", Debug fake camera). A frame is due when the clock has
/// passed its time; `pump()` delivers the due ones. A sequence frame at `t`
/// is delivered at `start + loop × duration + t` on the clock.
final class SequenceFrameSource: FrameSource {
    let sequence: LandmarkSequence
    private let clock: SoloClock
    private let loop: Bool
    private var deliver: (@Sendable ([Frame], Double) -> Void)?
    private var startMs: Double?
    private var next = 0
    private var round = 0
    private var timer: Timer?
    /// Pump on a timer; tests pump by hand.
    private let autoPump: Bool
    /// Degraded rate: frames closer than this to the last delivered one are dropped.
    private var minGapMs: Double = 0
    private var lastDelivered = -Double.infinity
    private(set) var delivered = 0

    func limitFrameRate(_ fps: Double) { minGapMs = 1000 / fps - 1e-6 }

    init(sequence: LandmarkSequence, clock: SoloClock, loop: Bool = true, autoPump: Bool = false) {
        self.sequence = sequence
        self.clock = clock
        self.loop = loop
        self.autoPump = autoPump
    }

    var needsCameraAccess: Bool { false }
    var isFrontCamera: Bool { false }
    var dropped: Int { 0 }
    var horizontalFOVDegrees: Double? { nil }
    var captureSession: AVCaptureSession? { nil }

    /// One sequence pass: the last frame's time plus one frame interval.
    private var durationMs: Double { (sequence.frames.last?.t ?? 0) + 1000 / sequence.fps }

    func start(deliver: @escaping @Sendable ([Frame], Double) -> Void) throws {
        self.deliver = deliver
        startMs = clock.nowMs
        next = 0
        round = 0
        if autoPump {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / sequence.fps, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pump() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        deliver = nil
    }

    /// Delivers every frame that is due, one call per frame.
    func pump() {
        guard let deliver, let startMs, !sequence.frames.isEmpty else { return }
        let now = clock.nowMs
        while true {
            if next == sequence.frames.count {
                guard loop else { return }
                next = 0
                round += 1
            }
            var f = sequence.frames[next]
            let t = startMs + Double(round) * durationMs + f.t
            guard t <= now else { return }
            f.t = t
            next += 1
            if t - lastDelivered < minGapMs { continue }
            lastDelivered = t
            delivered += 1
            deliver([f], t)
        }
    }
}
