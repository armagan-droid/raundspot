import AVFoundation
import Foundation
import Testing
@testable import SoloRecording
import SoloEngine

/// specs/09 T5.1: consent (AC-9.2), package writing (AC-9.3, AC-9.9), withdrawal (AC-9.7), storage (AC-9.8).
@Suite(.serialized) struct SoloRecordingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func library() throws -> RecordingLibrary {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        let lib = try RecordingLibrary(root: dir)
        try lib.setEnabled(true)
        return lib
    }

    func meta(_ lib: RecordingLibrary, _ code: String) throws -> RecordingMeta {
        let c = try #require(lib.activeConsent(code))
        return RecordingMeta(participant: code, consentId: c.id, createdAt: now, device: "test", osVersion: "26", appVersion: "t",
                             mode: "technique", stance: "orthodox", camera: "front", pose3D: false, templates: ["slip_left": "{}"])
    }

    /// AC-9.1 (Beta side): no recording until the mode is turned on.
    @Test func offUntilTurnedOn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)", isDirectory: true)
        let lib = try RecordingLibrary(root: dir)
        #expect(!lib.isEnabled)
        try lib.addParticipant("P01", at: now)
        try lib.consent("P01", adultConfirmed: true, at: now)
        #expect(throws: RecordingError.disabled) { try lib.newPackage(try meta(lib, "P01"), freeBytes: 10_000_000_000) }
        try lib.setEnabled(true)
        #expect(try RecordingLibrary(root: dir).isEnabled)
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
        let posePTS = try lines.filter { !$0.contains("\"inVideo\":false") }.map { l -> CMTime in
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

    /// AC-9.6: the export is a v2 vision19 team sequence with meta, read back by the strict schema; no picture.
    @Test func exportIsAStrictLandmarkSequence() async throws {
        let lib = try library()
        try lib.addParticipant("P03", at: now)
        try lib.consent("P03", adultConfirmed: true, at: now)
        let w = try lib.newPackage(try meta(lib, "P03"), freeBytes: 10_000_000_000)
        // a standing pose (Vision coordinates: y up), every 5th frame skipped by Vision
        let joints: [String: [Double]] = ["nose": [0.5, 0.8, 0.9], "leftShoulder": [0.55, 0.65, 0.9], "rightShoulder": [0.45, 0.65, 0.9],
                                          "leftHip": [0.53, 0.45, 0.9], "rightHip": [0.47, 0.45, 0.9]]
        for i in 0..<30 {
            let pts = CMTime(value: CMTimeValue(500_000 + i * 33_333), timescale: 1_000_000)
            w.frame(pixelBuffer(10), pts: pts, pose: i % 5 == 4 ? .skippedFrame : PoseLine(joints: joints, people: 1, selected: 0, aspect: 0.75))
            try await Task.sleep(for: .milliseconds(5))
        }
        await w.finish()
        let out = FileManager.default.temporaryDirectory
        let url = try RecordingExport.export(package: w.dir, consentVersion: 1, templateVersions: ["slip_left": 2], to: out)
        #expect(url.lastPathComponent.hasPrefix("slip_left-P03-") && url.pathExtension == "gz")

        // gunzip: 10-byte header, raw deflate, CRC32 and size
        let gz = try Data(contentsOf: url)
        #expect(gz.prefix(2) == Data([0x1F, 0x8B]))
        let json = try (gz.dropFirst(10).dropLast(8) as NSData).decompressed(using: .zlib) as Data
        let crc = gz.suffix(8).prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(crc == RecordingExport.crc32(json))
        let text = String(decoding: json, as: UTF8.self)
        for word in ["video", "pixel", "jpeg", "png"] { #expect(!text.contains(word)) }

        let seq = try LandmarkSequence.parse(data: json).get()
        #expect(seq.formatVersion == 2 && seq.skeleton == .vision19 && seq.source == .team && !seq.hasWorld)
        #expect(seq.meta?.participant == "P03" && seq.meta?.templates == [.init(id: "slip_left", version: 2)])
        #expect(seq.frames.count == 30 && seq.imageAspect == 0.75)
        #expect(seq.frames[4].image[LandmarkName.nose.index].visibility == 0)  // skipped by Vision
        #expect(abs(seq.frames[0].image[LandmarkName.nose.index].y - 0.2) < 1e-9)  // y flipped to image coordinates
        // the export is listed in the package's meta (shown on withdrawal)
        #expect(lib.packages().first?.meta.exports == [url.lastPathComponent])
        try? FileManager.default.copyItem(at: url, to: out.appendingPathComponent("export-sample.json.gz"))
        try? json.write(to: out.appendingPathComponent("export-sample.json"))
        print("EXPORT_SAMPLE", out.appendingPathComponent("export-sample.json").path)
    }

    /// specs/09 "Refleks kaydı" (T5.2): trials are `app.jsonl`'s trial lines, a note labels the right response,
    /// and the export carries the cue and trial lines as `reflex` (specs/03).
    @Test func reflexRecordingExportsItsTrialsWithTheCoachsLabels() async throws {
        let lib = try library()
        try lib.addParticipant("P04", at: now)
        try lib.consent("P04", adultConfirmed: true, at: now)
        var m = try meta(lib, "P04")
        m.mode = "reflex"
        m.reflexCatalog = "muay_thai"
        m.reflexLevel = 2
        m.templates = ["slip_left": "{}", "slip_right": "{}"]
        let w = try lib.newPackage(m, freeBytes: 10_000_000_000)
        let joints: [String: [Double]] = ["nose": [0.5, 0.8, 0.9], "leftHip": [0.53, 0.45, 0.9], "rightHip": [0.47, 0.45, 0.9]]
        for i in 0..<10 {
            w.frame(pixelBuffer(10), pts: CMTime(value: CMTimeValue(1_000 + i * 500), timescale: 1_000), pose: PoseLine(joints: joints, people: 1, selected: 0))
        }
        w.appLine(["t": 1200.0, "type": "cue", "key": "strike.jab", "plannedAt": 1195.0])
        w.appLine(["t": 2100.0, "type": "trial", "strike": "jab", "feint": false, "cueAt": 1200.0, "result": "correct", "response": "slip_left",
                   "reactionMs": 310.0, "approximate": false])
        w.appLine(["t": 3000.0, "type": "cue", "key": "strike.jab", "plannedAt": 3000.0])
        w.appLine(["t": 3900.0, "type": "trial", "strike": "jab", "feint": true, "cueAt": 3000.0, "result": "feint_bitten", "response": "slip_right",
                   "reactionMs": NSNull(), "approximate": false])
        w.appLine(["t": 4000.0, "type": "degradation", "step": "fps24"])
        await w.finish()

        let trials = RecordingNotes.trials(package: w.dir)
        #expect(trials == [RecordedAttempt(start: 1200, end: 2100, outcome: "correct"), RecordedAttempt(start: 3000, end: 3900, outcome: "feint_bitten")])
        // the coach: the first was right, the second needed no response (a feint)
        var notes = [RecordingNote(t: 1500, text: "iyi", author: .coach, label: .init(response: "slip_left", faults: [])),
                     RecordingNote(t: 3500, text: "çalım", author: .coach, label: .init(response: RecordingNote.Label.noResponse, faults: []))]
        try RecordingNotes.save(notes, w.dir)

        let seq = try RecordingExport.sequence(package: w.dir, consentVersion: 1, templateVersions: ["slip_left": 2, "slip_right": 2])
        #expect(seq.exerciseId == "muay_thai" && seq.labels == nil)
        let r = try #require(seq.reflex)
        #expect(r.catalogId == "muay_thai" && r.level == 2 && r.stance == .orthodox)
        #expect(r.cues.map(\.t) == [1200, 3000])
        #expect(r.trials.map(\.result) == [.correct, .feintBitten] && r.trials[1].reactionMs == nil)
        #expect(r.trials.map(\.expected) == [.some("slip_left"), .some(nil)])
        // the export reads back strictly, and its name is the catalog's
        #expect(try LandmarkSequence.parse(JSONValue.parse(seq.json.serialized())).get().reflex == r)
        let url = try RecordingExport.export(package: w.dir, consentVersion: 1, templateVersions: [:], to: FileManager.default.temporaryDirectory)
        #expect(url.lastPathComponent.hasPrefix("muay_thai-P04-"))

        // an edited note keeps its time; an unlabelled trial has no `expected`
        notes[1] = RecordingNotes.edited(notes[1], text: "yok", author: .developer, label: nil)
        #expect(notes[1].t == 3500 && notes[1].text == "yok" && notes[1].author == .developer && notes[1].label == nil)
        try RecordingNotes.save(notes, w.dir)
        let again = try RecordingExport.sequence(package: w.dir, consentVersion: 1, templateVersions: [:])
        #expect(again.reflex?.trials.map(\.expected) == [.some("slip_left"), nil])
    }

    /// specs/09 "Deneme işaretleme": the coach marks attempts; marks never overlap, and when there are any the export's
    /// labels come from them, with their spans (specs/03).
    @Test func markedAttemptsBecomeTheExportsLabels() async throws {
        let lib = try library()
        try lib.addParticipant("P06", at: now)
        try lib.consent("P06", adultConfirmed: true, at: now)
        let w = try lib.newPackage(try meta(lib, "P06"), freeBytes: 10_000_000_000)
        let joints: [String: [Double]] = ["nose": [0.5, 0.8, 0.9], "leftHip": [0.53, 0.45, 0.9], "rightHip": [0.47, 0.45, 0.9]]
        for i in 0..<20 {
            w.frame(pixelBuffer(10), pts: CMTime(value: CMTimeValue(1_000 + i * 250), timescale: 1_000), pose: PoseLine(joints: joints, people: 1, selected: 0))
        }
        await w.finish()

        var marks: [AttemptMark] = []
        let valid = RecordingNote.Label(outcome: "valid", faults: [])
        marks = try RecordingMarks.adding(AttemptMark(start: 3000, end: 3800, label: .init(outcome: "faulty", faults: ["neck_only"])), to: marks)
        marks = try RecordingMarks.adding(AttemptMark(start: 1500, end: 2500, label: valid), to: marks)
        #expect(marks.map(\.start) == [1500, 3000])  // kept in time order
        #expect(throws: RecordingMarks.MarkError.overlap) { try RecordingMarks.adding(AttemptMark(start: 2400, end: 3100, label: valid), to: marks) }
        #expect(throws: RecordingMarks.MarkError.reversed) { try RecordingMarks.adding(AttemptMark(start: 4000, end: 3900, label: valid), to: marks) }
        // editing a mark's label keeps its range and does not count as an overlap with itself
        marks[0].label = .init(outcome: "incomplete", faults: [])
        try RecordingMarks.save(marks, w.dir)
        #expect(RecordingMarks.load(w.dir) == marks)

        // a note label exists too, but the marks win
        try RecordingNotes.save([RecordingNote(t: 1600, text: "x", author: .coach, label: valid)], w.dir)
        let seq = try RecordingExport.sequence(package: w.dir, consentVersion: 1, templateVersions: ["slip_left": 2])
        #expect(seq.labels == [RepLabel(outcome: .incomplete, faults: [], span: [1500, 2500]),
                               RepLabel(outcome: .faulty, faults: ["neck_only"], span: [3000, 3800])])
        #expect(try LandmarkSequence.parse(JSONValue.parse(seq.json.serialized())).get().labels == seq.labels)
    }
}
