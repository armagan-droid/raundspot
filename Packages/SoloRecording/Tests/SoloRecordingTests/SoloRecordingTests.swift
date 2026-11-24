import AVFoundation
import Foundation
import Testing
@testable import SoloRecording

/// specs/09 T5.1: consent (AC-9.2), package writing (AC-9.3, AC-9.9), withdrawal (AC-9.7), storage (AC-9.8).
@Suite(.serialized) struct SoloRecordingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func library() throws -> RecordingLibrary {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        return try RecordingLibrary(root: dir)
    }

    func meta(_ lib: RecordingLibrary, _ code: String) throws -> RecordingMeta {
        let c = try #require(lib.activeConsent(code))
        return RecordingMeta(participant: code, consentId: c.id, createdAt: now, device: "test", osVersion: "26", appVersion: "t",
                             mode: "technique", stance: "orthodox", camera: "front", pose3D: false, templates: ["slip_left": "{}"])
    }

    @Test func consentRules() throws {
        let lib = try library()
        #expect(throws: RecordingError.invalidCode) { try lib.addParticipant("Ahmet", at: now) }
        try lib.addParticipant("P07", at: now)
        #expect(throws: RecordingError.duplicateCode) { try lib.addParticipant("P07", at: now) }
        #expect(!lib.canRecord("P07"))
        #expect(throws: RecordingError.adultNotConfirmed) { try lib.consent("P07", adultConfirmed: false, at: now) }
        #expect(throws: RecordingError.unknownParticipant) { try lib.consent("P08", adultConfirmed: true, at: now) }
        try lib.consent("P07", adultConfirmed: true, at: now)
        #expect(lib.canRecord("P07"))
        // reopened from disk: the same state
        let again = try RecordingLibrary(root: lib.root)
        #expect(again.canRecord("P07") && again.participants.map(\.code) == ["P07"])
        // no package without consent
        try lib.addParticipant("P08", at: now)
        var m = try meta(lib, "P07")
        m.participant = "P08"
        #expect(throws: RecordingError.noConsent) { try lib.newPackage(m, freeBytes: 10_000_000_000) }
    }

    func pixelBuffer(_ shade: UInt8) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        memset(CVPixelBufferGetBaseAddress(pb!), Int32(shade), CVPixelBufferGetDataSize(pb!))
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
    }

    /// AC-9.3: every frame of the video has a pose line with the same PTS (skipped frames included); AC-9.9: no audio.
    @Test func everyVideoFrameHasItsPoseLine() async throws {
        let lib = try library()
        try lib.addParticipant("P01", at: now)
        try lib.consent("P01", adultConfirmed: true, at: now)
        let w = try lib.newPackage(try meta(lib, "P01"), freeBytes: 10_000_000_000)
        for i in 0..<45 {
            let pts = CMTime(value: CMTimeValue(1000 + i * 33_333), timescale: 1_000_000)
            let pose = i % 7 == 3 ? PoseLine.skippedFrame : PoseLine(joints: ["nose": [0.5, 0.3, 0.9]], people: 1, selected: 0)
            w.frame(pixelBuffer(UInt8(i * 5)), pts: pts, pose: pose)
            try await Task.sleep(for: .milliseconds(5))
        }
        w.appLine(["type": "cue", "t": 1.0])
        await w.finish()

        let lines = try String(contentsOf: w.dir.appendingPathComponent("poses.jsonl"), encoding: .utf8).split(separator: "\n")
        let posePTS = try lines.map { l -> CMTime in
            let o = try #require(try JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any])
            return CMTime(value: (o["videoValue"] as! NSNumber).int64Value, timescale: (o["videoScale"] as! NSNumber).int32Value)
        }
        #expect(lines.contains { $0.contains("\"skipped\":true") })

        let asset = AVURLAsset(url: w.dir.appendingPathComponent("video.mov"))
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out)
        reader.startReading()
        var videoPTS: [CMTime] = []
        while let s = out.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(s) > 0 { videoPTS.append(CMSampleBufferGetPresentationTimeStamp(s)) }
        }
        #expect(videoPTS.count == w.framesWritten && videoPTS.count > 0)
        #expect(Set(videoPTS.map { CMTimeConvertScale($0, timescale: 1_000_000, method: .default).value })
            == Set(posePTS.map { CMTimeConvertScale($0, timescale: 1_000_000, method: .default).value }))
    }

    /// AC-9.7: withdrawal deletes every package of the participant and leaves nothing of them.
    @Test func withdrawalDeletesTheParticipantsPackages() async throws {
        let lib = try library()
        for code in ["P01", "P02"] {
            try lib.addParticipant(code, at: now)
            try lib.consent(code, adultConfirmed: true, at: now)
        }
        for code in ["P01", "P01", "P02"] {
            var m = try meta(lib, code)
            m.exports = code == "P01" ? ["p01-a.json.gz"] : []
            let w = try lib.newPackage(m, freeBytes: 10_000_000_000)
            await w.finish()
        }
        #expect(lib.packages().count == 3)
        let exports = try lib.withdraw("P01", at: now)
        #expect(exports == ["p01-a.json.gz", "p01-a.json.gz"])
        #expect(lib.packages().map(\.meta.participant) == ["P02"])
        #expect(!lib.canRecord("P01"))
        let left = try FileManager.default.subpathsOfDirectory(atPath: lib.packagesDir.path)
        #expect(left.allSatisfy { !$0.contains(lib.packages().first.map { _ in "P01" } ?? "P01") })
        #expect(try FileManager.default.contentsOfDirectory(atPath: lib.packagesDir.path).count == 1)
    }

    /// AC-9.8: excluded from backup, complete file protection.
    @Test func storageIsProtectedAndNotBackedUp() throws {
        let lib = try library()
        let values = try lib.root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        let attrs = try FileManager.default.attributesOfItem(atPath: lib.root.path)
        // the simulator has no data protection: the class is checked on a device
        #if os(iOS) && !targetEnvironment(simulator)
        #expect(attrs[.protectionKey] as? FileProtectionType == .complete)
        #else
        _ = attrs
        #endif
    }

    @Test func spaceAndRetention() async throws {
        #expect(StorageCheck.check(freeBytes: 3_000_000_000) == .ok)
        #expect(StorageCheck.check(freeBytes: 1_000_000_000) == .warn)
        #expect(StorageCheck.check(freeBytes: 400_000_000) == .refuse)
        let lib = try library()
        try lib.addParticipant("P01", at: now)
        try lib.consent("P01", adultConfirmed: true, at: now)
        #expect(throws: RecordingError.lowStorage) { try lib.newPackage(try meta(lib, "P01"), freeBytes: 100) }
        let w = try lib.newPackage(try meta(lib, "P01"), freeBytes: 10_000_000_000)
        await w.finish()
        let cal = Calendar(identifier: .gregorian)
        let r11 = lib.retention(now: cal.date(byAdding: .month, value: 11, to: now)!)
        #expect(r11.suggest.count == 1 && r11.delete.isEmpty)
        try lib.purgeExpired(now: cal.date(byAdding: .month, value: 11, to: now)!)
        #expect(lib.packages().count == 1)
        try lib.purgeExpired(now: cal.date(byAdding: .month, value: 12, to: now)!)
        #expect(lib.packages().isEmpty)
    }
}
