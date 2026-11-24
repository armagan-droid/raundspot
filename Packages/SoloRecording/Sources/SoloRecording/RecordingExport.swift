import Compression
import Foundation
import SoloEngine
import SoloPose

/// Landmark-only export of a recording (specs/09 "Dışa aktarma", AC-9.6): a `LandmarkSequence` v2,
/// `vision19`, `source: team`, with `meta`; no video, no picture. Gzipped for sharing.
public enum RecordingExport {
    public enum ExportError: Error, Equatable { case empty, unreadable }

    /// The sequence from `poses.jsonl` and `meta.json`.
    public static func sequence(package dir: URL, consentVersion: Int, templateVersions: [String: Int]) throws -> LandmarkSequence {
        guard let metaData = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
              let meta = try? JSONDecoder.iso.decode(RecordingMeta.self, from: metaData),
              let text = try? String(contentsOf: dir.appendingPathComponent("poses.jsonl"), encoding: .utf8) else { throw ExportError.unreadable }
        var frames: [Frame] = []
        var aspect = 16.0 / 9
        for line in text.split(separator: "\n") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let t = o["t"] as? Double else { continue }
            var pose: [DetectedPose] = []
            let skipped = (o["skipped"] as? Bool) == true
            if !skipped { aspect = (o["aspect"] as? Double) ?? aspect }  // a skipped frame says nothing about the picture
            if !skipped, let joints = o["joints"] as? [String: [Double]] {
                var j: [VisionJoint: DetectedJoint] = [:]
                for (name, v) in joints where v.count == 3 {
                    if let vj = VisionJoint(rawValue: name) { j[vj] = DetectedJoint(x: v[0], y: v[1], confidence: v[2]) }
                }
                pose = [DetectedPose(confidence: 1, joints: j)]
            }
            // the selected person; an unseen frame keeps its time with every joint at visibility 0
            let frame = FrameMapper.candidates(pose, t: t, imageAspect: aspect).first ?? unseen(t, aspect)
            if let last = frames.last, frame.t <= last.t { continue }
            frames.append(frame)
        }
        guard frames.count > 1 else { throw ExportError.empty }
        let fps = Double(frames.count - 1) / ((frames.last!.t - frames.first!.t) / 1000)
        let exercise = meta.templates.keys.sorted().first ?? "free"
        // the labels of the notes, when every attempt has one (specs/09)
        let labels = RecordingNotes.labels(RecordingNotes.load(dir), attempts: RecordingNotes.attempts(package: dir, template: exercise))
        var seq = LandmarkSequence(formatVersion: 2, skeleton: .vision19, exerciseId: exercise, source: .team,
                                   view: meta.mode == "side" ? .side : .front, fps: (fps * 100).rounded() / 100, labels: labels,
                                   frames: frames, hasWorld: false, imageAspect: aspect)
        seq.meta = ExportMeta(recordingId: meta.recordingId.uuidString, participant: meta.participant, consentVersion: consentVersion,
                              device: meta.device, osVersion: meta.osVersion, appVersion: meta.appVersion,
                              templates: meta.templates.keys.sorted().map { .init(id: $0, version: templateVersions[$0] ?? 1) })
        return seq
    }

    private static func unseen(_ t: Double, _ aspect: Double) -> Frame {
        let present = Skeleton.vision19.landmarks
        let image = LandmarkName.allCases.map { present.contains($0) ? Landmark(x: 0, y: 0, z: 0, visibility: 0) : .missing }
        return Frame(t: t, image: image, world: Array(repeating: .missing, count: LandmarkName.count), imageAspect: aspect)
    }

    /// The file to share: gzip of the sequence JSON, named `<template>-<participant>-<id8>.json.gz`; recorded in the meta.
    public static func export(package dir: URL, consentVersion: Int, templateVersions: [String: Int], to outDir: URL) throws -> URL {
        let seq = try sequence(package: dir, consentVersion: consentVersion, templateVersions: templateVersions)
        let json = Data((seq.json.serialized() + "\n").utf8)
        let name = "\(seq.exerciseId)-\(seq.meta!.participant)-\(seq.meta!.recordingId.prefix(8).lowercased()).json.gz"
        let url = outDir.appendingPathComponent(name)
        try gzip(json).write(to: url, options: .atomic)
        // the export list in the meta (specs/09): shown when consent is withdrawn
        let metaURL = dir.appendingPathComponent("meta.json")
        if var meta = try? JSONDecoder.iso.decode(RecordingMeta.self, from: Data(contentsOf: metaURL)) {
            meta.exports.append(name)
            try JSONEncoder.iso.encode(meta).write(to: metaURL, options: [.atomic, .completeFileProtection])
        }
        return url
    }

    /// RFC 1952 gzip around raw deflate.
    static func gzip(_ data: Data) throws -> Data {
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF])
        let deflated = try (data as NSData).compressed(using: .zlib) as Data  // raw deflate (no zlib header)
        out.append(deflated)
        var crc = crc32(data), size = UInt32(truncatingIfNeeded: data.count)
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }

    static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return (crc ^ 0xFFFF_FFFF).littleEndian
    }
}
