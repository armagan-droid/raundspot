#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// One pose line of `poses.jsonl` (specs/09): the frame's PTS, then Vision's 2D joints or `skipped`.
public struct PoseLine: Sendable {
    /// Joint name → (x, y, confidence), Vision 2D.
    public var joints: [String: [Double]]?
    public var people: Int
    public var selected: Int?
    public var skipped: Bool
    /// Upright width / height of the processed picture (the export's `imageAspect`).
    public var aspect: Double

    public init(joints: [String: [Double]]?, people: Int, selected: Int?, skipped: Bool = false, aspect: Double = 16.0 / 9) {
        self.joints = joints
        self.people = people
        self.selected = selected
        self.skipped = skipped
        self.aspect = aspect
    }

    public static let skippedFrame = PoseLine(joints: nil, people: 0, selected: nil, skipped: true)
}

/// Writes one recording package `<id>.gsrec/` (specs/09): `video.mov` without audio, and `poses.jsonl`,
/// `engine.jsonl`, `app.jsonl`, `meta.json`. Every processed frame gets a pose line with its PTS, so every video
/// frame has its line (AC-9.3); a frame the video could not take is marked `inVideo: false`.
public final class RecordingWriter: @unchecked Sendable {
    public let dir: URL
    public private(set) var meta: RecordingMeta
    private let writer: AVAssetWriter
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let poses: FileHandle
    private let engine: FileHandle
    private let app: FileHandle
    private var started = false
    /// The first frame's PTS: the video's time zero.
    private var startPTS = CMTime.zero
    public private(set) var framesWritten = 0
    public private(set) var framesDropped = 0

    init(dir: URL, meta: RecordingMeta) throws {
        self.dir = dir
        self.meta = meta
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        try JSONEncoder.iso.encode(meta).write(to: dir.appendingPathComponent("meta.json"), options: [.atomic, .completeFileProtection])
        func handle(_ name: String) throws -> FileHandle {
            let url = dir.appendingPathComponent(name)
            fm.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
            return try FileHandle(forWritingTo: url)
        }
        poses = try handle("poses.jsonl")
        engine = try handle("engine.jsonl")
        app = try handle("app.jsonl")
        writer = try AVAssetWriter(outputURL: dir.appendingPathComponent("video.mov"), fileType: .mov)
    }

    /// One camera frame: into the video, then its pose line with the same PTS.
    public func frame(_ pixelBuffer: CVPixelBuffer, pts: CMTime, pose: PoseLine) {
        if !started { start(pixelBuffer, at: pts) }
        // every processed frame gets its line (the engine saw it, AC-9.5); one the video could not take is marked
        var inVideo = false
        if let input, let adaptor, input.isReadyForMoreMediaData, adaptor.append(pixelBuffer, withPresentationTime: pts) { inVideo = true }
        if inVideo { framesWritten += 1 } else { framesDropped += 1 }
        // host PTS, and the frame's time in the video (from its first frame), exact in the same timescale
        let v = CMTimeSubtract(pts, startPTS)
        var line: [String: Any] = ["ptsValue": pts.value, "ptsScale": pts.timescale, "t": CMTimeGetSeconds(pts) * 1000,
                                   "videoValue": v.value, "videoScale": v.timescale, "aspect": pose.aspect]
        if !inVideo { line["inVideo"] = false }
        if pose.skipped {
            line["skipped"] = true
        } else {
            line["people"] = pose.people
            if let s = pose.selected { line["selected"] = s }
            if let j = pose.joints { line["joints"] = j }
        }
        write(line, to: poses)
    }

    /// An engine line (metrics, rep state, events), already keyed by frame time.
    public func engineLine(_ line: [String: Any]) { write(line, to: engine) }
    /// An app line (cues, trials, user actions, degradations).
    public func appLine(_ line: [String: Any]) { write(line, to: app) }

    private func write(_ line: [String: Any], to h: FileHandle) {
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
        h.write(data)
        h.write(Data([0x0A]))
    }

    private func start(_ pb: CVPixelBuffer, at pts: CMTime) {
        started = true
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h]
        if !writer.canApply(outputSettings: settings, forMediaType: .video) { settings[AVVideoCodecKey] = AVVideoCodecType.h264 }
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        i.expectsMediaDataInRealTime = true
        // no rounding of frame times: the camera's timescale for the track and the movie
        i.mediaTimeScale = pts.timescale
        writer.movieTimeScale = pts.timescale
        startPTS = pts
        // video only: no audio input exists (AC-9.9)
        guard writer.canAdd(i) else { return }
        writer.add(i)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        input = i
        writer.startWriting()
        writer.startSession(atSourceTime: pts)
    }

    /// Closes the files; the video is complete when this returns.
    public func finish() async {
        try? poses.close()
        try? engine.close()
        try? app.close()
        guard started, writer.status == .writing else { return }
        input?.markAsFinished()
        await writer.finishWriting()
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                               ofItemAtPath: dir.appendingPathComponent("video.mov").path)
    }
}
#endif
