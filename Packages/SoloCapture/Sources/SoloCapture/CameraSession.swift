#if canImport(AVFoundation) && os(iOS)
import AVFoundation
import CoreMedia

/// One camera frame, delivered on the camera queue (specs/02 "Akış").
public struct CameraFrame {
    public let pixelBuffer: CVPixelBuffer
    /// Presentation time on the host clock, ms (specs/02 "Saat tabanı").
    public let hostTimeMs: Double
    /// Clockwise turn that still makes the buffer upright, degrees (0, 90, 180, 270);
    /// 0 when the connection already rotates the buffers.
    public let rotationDegrees: Double
    public let width: Int
    public let height: Int
}

public enum CameraError: Error, Equatable {
    case noCamera, cannotAddInput, cannotAddOutput, notAuthorized
}

/// AVFoundation camera session (T3.1): 30 FPS, 1280×720, at most one frame
/// waiting (`alwaysDiscardsLateVideoFrames`), buffers never mirrored.
public final class CameraSession: NSObject, @unchecked Sendable {
    public let session = AVCaptureSession()
    public let position: AVCaptureDevice.Position
    private let queue = DispatchQueue(label: "solo.camera.frames", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private let lock = NSLock()
    private var captureAngle: Double = 0
    private var droppedCount = 0
    private var handler: ((CameraFrame) -> Void)?

    public init(position: AVCaptureDevice.Position = .front) {
        self.position = position
    }

    /// Asks for camera access when undetermined.
    public static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Frames dropped because the previous one was still being processed.
    public var dropped: Int { lock.withLock { droppedCount } }

    /// Horizontal field of view of the active format, degrees.
    public var horizontalFOVDegrees: Double? { device.map { Double($0.activeFormat.videoFieldOfView) } }

    /// `handler` runs on the camera queue, one frame at a time.
    public func configure(handler: @escaping (CameraFrame) -> Void) throws {
        self.handler = handler
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noCamera
        }
        self.device = device
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()
    }

    /// Follows the device orientation; `previewLayer` gets the preview angle.
    @MainActor public func attach(previewLayer: AVCaptureVideoPreviewLayer?) {
        guard let device else { return }
        let c = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        coordinator = c
        self.previewLayer = previewLayer
        refreshRotation()
        observations = [
            c.observe(\.videoRotationAngleForHorizonLevelCapture) { [weak self] _, _ in
                Task { @MainActor in self?.refreshRotation() }
            },
            c.observe(\.videoRotationAngleForHorizonLevelPreview) { [weak self] _, _ in
                Task { @MainActor in self?.refreshRotation() }
            },
        ]
    }

    private var observations: [NSKeyValueObservation] = []
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    @MainActor private func refreshRotation() {
        guard let c = coordinator else { return }
        // buffers are rotated upright on the output connection, so Vision gets `.up`
        // and nothing downstream has to know the sensor orientation
        let angle = c.videoRotationAngleForHorizonLevelCapture
        if let conn = output.connection(with: .video), conn.isVideoRotationAngleSupported(angle) {
            conn.videoRotationAngle = angle
            lock.withLock { captureAngle = 0 }
        } else {
            lock.withLock { captureAngle = angle }
        }
        let preview = c.videoRotationAngleForHorizonLevelPreview
        if let conn = previewLayer?.connection, conn.isVideoRotationAngleSupported(preview) {
            conn.videoRotationAngle = preview
        }
    }

    public func start() { queue.async { [session] in session.startRunning() } }
    public func stop() { queue.async { [session] in session.stopRunning() } }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let host = session.synchronizationClock.map { CMSyncConvertTime(pts, from: $0, to: CMClockGetHostTimeClock()) } ?? pts
        let angle = lock.withLock { captureAngle }
        handler?(CameraFrame(pixelBuffer: buffer, hostTimeMs: CMTimeGetSeconds(host) * 1000, rotationDegrees: angle,
                             width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
    }

    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.withLock { droppedCount += 1 }
    }
}
#endif
