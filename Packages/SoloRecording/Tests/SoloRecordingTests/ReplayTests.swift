import AVFoundation
import Foundation
import SoloEngine
import SoloEngineTesting
import SoloPose
import Testing
@testable import SoloRecording

/// AC-9.5: replaying a recording with unchanged thresholds gives the recorded events; a changed threshold
/// shows its difference.
@Suite(.serialized) struct ReplayTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Vision's raw joints (y up) for a synthetic vision19 frame, as the camera pipeline would have seen them.
    static func visionJoints(_ f: Frame) -> [String: [Double]] {
        var out: [String: [Double]] = [:]
        for j in VisionJoint.allCases {
            guard let name = j.landmark else { continue }
            let l = f.image[name.index]
            if l.isMissing { continue }
            out[j.rawValue] = [l.x, 1 - l.y, l.visibility]
        }
        return out
    }

    func pixelBuffer() -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        return pb!
    }

    @Test func unchangedThresholdsReplayTheRecordedEvents() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        let lib = try RecordingLibrary(root: dir)
        try lib.setEnabled(true)
        try lib.addParticipant("P05", at: now)
        let consent = try lib.consent("P05", adultConfirmed: true, at: now)
        let packJSON = try JSONValue.parse(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("exercises/slip_left.json"))
        let pack = try RulePackLoader.load(packJSON, capabilities: .vision19TwoD).get()
        let w = try lib.newPackage(RecordingMeta(participant: "P05", consentId: consent.id, createdAt: now, device: "t", osVersion: "26",
                                                 appVersion: "t", mode: "front", stance: "orthodox", camera: "front", pose3D: false,
                                                 templates: ["slip_left": "{}"]), freeBytes: 10_000_000_000)

        // "live": a slipping boxer through the same mapping the camera pipeline uses, the engine writing its lines
        let synth = toVision19(evaderSequence(exerciseId: "slip_left", reps: [SyntheticRep(EvaderParams(slip: 25), durationMs: 700),
                                                                               SyntheticRep(EvaderParams(slip: 15), durationMs: 700),
                                                                               SyntheticRep(EvaderParams(slip: 27), durationMs: 700)],
                                              options: SequenceOptions(fps: 30, noise: 0.002, seed: 4)), world: false)
        let live = ExerciseEngine(pack, setup: ExerciseSetup(view: .front, nearSide: .left))
        for (i, f) in synth.frames.enumerated() {
            let joints = Self.visionJoints(f)
            let pts = CMTime(value: CMTimeValue(1_000_000 + i * 33_333), timescale: 1_000_000)
            w.frame(pixelBuffer(), pts: pts, pose: PoseLine(joints: joints, people: 1, selected: 0, aspect: 1))
            // the frame the app would have built from those joints
            let pose = DetectedPose(confidence: 1, joints: Dictionary(uniqueKeysWithValues: joints.compactMap { k, v in
                VisionJoint(rawValue: k).map { ($0, DetectedJoint(x: v[0], y: v[1], confidence: v[2])) } }))
            let t = CMTimeGetSeconds(pts) * 1000  // as the camera session stamps frames
            let frame = FrameMapper.candidates([pose], t: t, imageAspect: 1)[0]
            let events = live.push(frame)
            if !events.isEmpty {
                w.engineLine(["t": t, "template": "slip_left",
                              "events": events.map { try! JSONSerialization.jsonObject(with: Data($0.event.jsonObject.serialized().utf8)) }])
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        await w.finish()
        #expect(w.framesWritten + w.framesDropped == synth.frames.count)

        let recorded = RecordingReplay.recorded(package: w.dir, template: "slip_left")
        #expect(recorded.contains { $0.json.contains("REP_COMPLETED") })
        let seq = try RecordingExport.sequence(package: w.dir, consentVersion: 1, templateVersions: ["slip_left": 2])
        let setup = ExerciseSetup(view: .front, nearSide: .left)
        let replay = RecordingReplay.run(seq, pack: pack, setup: setup)
        #expect(replay == recorded)

        // a stricter target: the shallow slip no longer counts, and the replay says so
        let stricter = try RecordingReplay.run(seq, rulePack: packJSON, path: "rep.target.enter", value: 0.9, setup: setup)
        let d = RecordingReplay.diff(old: replay, new: stricter)
        #expect(!d.added.isEmpty || !d.removed.isEmpty)
    }
}
