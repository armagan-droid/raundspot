import Foundation
import Testing
@testable import SoloEngine

// Port of the source `shared/test/sequence.test.ts` and `frame.test.ts`
// (commit c2fe3fd), plus formatVersion 2 (specs/03 AC-3.4).

private let point: JSONValue = ["x": 0.5, "y": 0.5, "z": 0, "visibility": 0.9]

private func landmarks(_ skeleton: Skeleton = .mediapipe33) -> JSONValue {
    .array(LandmarkName.allCases.map { skeleton.landmarks.contains($0) ? point : .null })
}

private func frame(_ t: Double, _ skeleton: Skeleton = .mediapipe33, world: JSONValue? = nil) -> JSONValue {
    ["t": .number(t), "image": landmarks(skeleton), "world": world ?? landmarks(skeleton)]
}

private func v1() -> JSONValue {
    [
        "formatVersion": 1, "exerciseId": "squat", "source": "synthetic", "view": "front", "fps": 30,
        "labels": ["reps": [["outcome": "valid", "faults": []]]],
        "frames": [frame(0), frame(33)],
    ]
}

private func v2(_ skeleton: Skeleton) -> JSONValue {
    var s = v1()
    s["formatVersion"] = 2
    s["skeleton"] = .string(skeleton.rawValue)
    s["imageAspect"] = 0.5625
    s["source"] = "team"
    s["frames"] = [frame(0, skeleton), frame(33, skeleton)]
    return s
}

private func isValid(_ json: JSONValue) -> Bool {
    if case .success = LandmarkSequence.parse(json) { return true }
    return false
}

@Suite("LandmarkSequence v1 (ref 04 fixture format)") struct SequenceV1Tests {
    @Test func validSequenceParses() throws {
        let seq = try LandmarkSequence.parse(v1()).get()
        #expect(seq.skeleton == .mediapipe33)
        #expect(seq.frames.count == 2)
        #expect(seq.labels == [RepLabel(outcome: .valid, faults: [])])
        #expect(seq.hasWorld)
    }

    @Test func labelsAreOptional() {
        var s = v1()
        s["labels"] = nil
        #expect(isValid(s))
    }

    @Test func frameTimestampsMustBeStrictlyIncreasing() {
        var s = v1()
        s["frames"] = [frame(33), frame(0)]
        #expect(!isValid(s))
        s["frames"] = [frame(0), frame(0)]
        #expect(!isValid(s))
    }

    @Test func viewCannotBeAmbiguousAndSourceMustBeKnown() {
        var s = v1()
        s["view"] = "ambiguous"
        #expect(!isValid(s))
        s = v1()
        s["source"] = "video"
        #expect(!isValid(s))
    }

    @Test func unknownFieldsAreRejected() {
        var s = v1()
        s["video"] = "data:..."
        #expect(!isValid(s))
    }

    @Test func v1CannotDeclareSkeletonOrNulls() {
        var s = v1()
        s["skeleton"] = "mediapipe33"
        #expect(!isValid(s))
        s = v1()
        s["frames"] = [frame(0, .vision19)]
        #expect(!isValid(s))
    }

    @Test func frameNeeds33Landmarks() {
        var s = v1()
        var f = frame(0)
        f["image"] = .array(Array(repeating: point, count: 32))
        s["frames"] = [f]
        #expect(!isValid(s))
    }

    @Test func visibilityMustBeWithin0And1() {
        var s = v1()
        var f = frame(0)
        f["image"]![0] = ["x": 0.5, "y": 0.5, "z": 0, "visibility": 1.5]
        s["frames"] = [f]
        #expect(!isValid(s))
    }

    @Test func frameRejectsExtraFields() {
        var s = v1()
        var f = frame(0)
        f["pixels"] = []
        s["frames"] = [f]
        #expect(!isValid(s))
    }
}

@Suite("AC-3.4: LandmarkSequence v2") struct SequenceV2Tests {
    @Test func bothSkeletonsLoad() throws {
        #expect(try LandmarkSequence.parse(v2(.mediapipe33)).get().skeleton == .mediapipe33)
        let seq = try LandmarkSequence.parse(v2(.vision19)).get()
        #expect(seq.skeleton == .vision19)
        #expect(seq.formatVersion == 2)
    }

    @Test func skeletonIsRequired() {
        var s = v2(.vision19)
        s["skeleton"] = nil
        #expect(!isValid(s))
    }

    @Test func missingVision19JointMustBeNull() {
        var s = v2(.vision19)
        var f = frame(0, .vision19)
        f["image"]![LandmarkName.leftHeel.index] = point
        s["frames"] = [f]
        #expect(!isValid(s))
    }

    @Test func presentVision19JointCannotBeNull() {
        var s = v2(.vision19)
        var f = frame(0, .vision19)
        f["image"]![LandmarkName.nose.index] = .null
        s["frames"] = [f]
        #expect(!isValid(s))
    }

    @Test func mediapipe33HasNoNulls() {
        var s = v2(.mediapipe33)
        var f = frame(0)
        f["world"]![LandmarkName.leftHeel.index] = .null
        s["frames"] = [f]
        #expect(!isValid(s))
    }

    @Test func nullPointIsVisibilityZeroAndNaN() throws {
        let seq = try LandmarkSequence.parse(v2(.vision19)).get()
        let heel = seq.frames[0][image: .leftHeel]
        #expect(heel.visibility == 0)
        #expect(heel.x.isNaN && heel.y.isNaN && heel.z.isNaN)
        #expect(heel == .missing)
        #expect(seq.frames[0][image: .nose] == Landmark(x: 0.5, y: 0.5, z: 0, visibility: 0.9))
    }

    @Test func worldNullMeansNo3DInEveryFrame() throws {
        var s = v2(.vision19)
        s["frames"] = [frame(0, .vision19, world: .null), frame(33, .vision19, world: .null)]
        let seq = try LandmarkSequence.parse(s).get()
        #expect(!seq.hasWorld)
        #expect(seq.frames.allSatisfy { $0.world.allSatisfy(\.isMissing) })

        s["frames"] = [frame(0, .vision19, world: .null), frame(33, .vision19)]
        #expect(!isValid(s))
        s["frames"] = [frame(0, .vision19), frame(33, .vision19, world: .null)]
        #expect(!isValid(s))
    }

    @Test func v1WorldCannotBeNull() {
        var s = v1()
        s["frames"] = [frame(0, world: .null)]
        #expect(!isValid(s))
    }

    @Test func unknownVersionIsRejected() {
        var s = v1()
        s["formatVersion"] = 3
        #expect(!isValid(s))
    }

    /// specs/03 `meta` (T5.4): strict, team recordings only, a participant code and no free text.
    @Test func exportMeta() throws {
        let frame: JSONValue = ["t": 0, "image": .array((0..<33).map { _ in ["x": 0.5, "y": 0.5, "z": 0, "visibility": 1] }), "world": .null]
        var j: JSONValue = ["formatVersion": 2, "skeleton": "mediapipe33", "imageAspect": 1, "exerciseId": "slip_left", "source": "team",
                            "view": "front", "fps": 30, "frames": [frame]]
        j["meta"] = ["recordingId": "6F1B2C3D-0000-4000-8000-000000000001", "participant": "P07", "consentVersion": 1, "device": "iPhone",
                     "osVersion": "26.1", "appVersion": "1.0", "templates": [["id": "slip_left", "version": 2]]]
        let seq = try LandmarkSequence.parse(j).get()
        #expect(seq.meta?.participant == "P07" && seq.meta?.templates == [.init(id: "slip_left", version: 2)])
        // written and read back
        #expect(try LandmarkSequence.parse(JSONValue.parse(seq.json.serialized())).get().meta == seq.meta)
        var named = j; named["meta"]!["participant"] = "Ahmet"
        var extra = j; extra["meta"]!["note"] = "hoca"
        var synthetic = j; synthetic["source"] = "synthetic"
        for bad in [named, extra, synthetic] { #expect(throws: SequenceIssues.self) { try LandmarkSequence.parse(bad).get() } }
    }

    /// specs/03 `reflex` (T5.2): a reflex recording's cue and trial lines, strict, team only; `expected` is the coach's label.
    @Test func reflexLines() throws {
        let frame: JSONValue = ["t": 0, "image": .array((0..<33).map { _ in ["x": 0.5, "y": 0.5, "z": 0, "visibility": 1] }), "world": .null]
        var j: JSONValue = ["formatVersion": 2, "skeleton": "mediapipe33", "imageAspect": 1, "exerciseId": "muay_thai", "source": "team",
                            "view": "front", "fps": 30, "frames": [frame]]
        j["reflex"] = ["catalogId": "muay_thai", "level": 2, "stance": "orthodox",
                       "cues": [["t": 1200, "key": "strike.jab", "plannedAt": 1195]],
                       "trials": [["t": 2100, "strike": "jab", "feint": false, "cueAt": 1200, "result": "correct", "response": "slip_left",
                                   "reactionMs": 310, "approximate": false, "expected": "slip_left"],
                                  ["t": 3900, "strike": "jab", "feint": true, "cueAt": 3000, "result": "feint_ok", "response": .null,
                                   "reactionMs": .null, "approximate": false, "expected": .null],
                                  ["t": 5900, "strike": "hook", "feint": false, "cueAt": 5000, "result": "missed", "response": .null,
                                   "reactionMs": .null, "approximate": false]]]
        let seq = try LandmarkSequence.parse(j).get()
        let r = try #require(seq.reflex)
        #expect(r.level == 2 && r.cues == [.init(t: 1200, key: "strike.jab", plannedAt: 1195)])
        #expect(r.trials.map(\.expected) == [.some("slip_left"), .some(nil), nil])
        #expect(r.trials[1].response == nil && r.trials[0].reactionMs == 310 && r.trials[1].result == .feintOk)
        // written and read back
        #expect(try LandmarkSequence.parse(JSONValue.parse(seq.json.serialized())).get().reflex == r)
        var extra = j; extra["reflex"]!["note"] = "hoca"
        var badResult = j; badResult["reflex"]!["trials"] = [["t": 1, "strike": "jab", "feint": false, "cueAt": 0, "result": "great",
                                                              "response": .null, "reactionMs": .null, "approximate": false]]
        var synthetic = j; synthetic["source"] = "synthetic"
        var v1 = j; v1["formatVersion"] = 1; v1["skeleton"] = nil; v1["imageAspect"] = nil
        for bad in [extra, badResult, synthetic, v1] { #expect(throws: SequenceIssues.self) { try LandmarkSequence.parse(bad).get() } }
    }

    /// specs/03 `labels.reps[].span` (T5.2): a marked attempt's time range; all or none, ordered, inside the frames.
    @Test func labelSpans() throws {
        let frames: [JSONValue] = (0..<5).map { i in
            ["t": .number(Double(i) * 1000), "image": .array((0..<33).map { _ in ["x": 0.5, "y": 0.5, "z": 0, "visibility": 1] }), "world": .null]
        }
        var j: JSONValue = ["formatVersion": 2, "skeleton": "mediapipe33", "imageAspect": 1, "exerciseId": "slip_left", "source": "team",
                            "view": "front", "fps": 1, "frames": .array(frames)]
        j["labels"] = ["reps": [["outcome": "valid", "faults": [], "span": [500, 1500]], ["outcome": "incomplete", "faults": [], "span": [2000, 3000]]]]
        let seq = try LandmarkSequence.parse(j).get()
        #expect(seq.labels?.map(\.span) == [[500, 1500], [2000, 3000]])
        #expect(try LandmarkSequence.parse(JSONValue.parse(seq.json.serialized())).get().labels == seq.labels)
        func with(_ reps: JSONValue) -> JSONValue { var c = j; c["labels"] = ["reps": reps]; return c }
        let bad: [JSONValue] = [
            with([["outcome": "valid", "faults": [], "span": [500, 1500]], ["outcome": "valid", "faults": []]]),  // not all
            with([["outcome": "valid", "faults": [], "span": [1500, 500]]]),  // reversed
            with([["outcome": "valid", "faults": [], "span": [500, 9000]]]),  // past the last frame
            with([["outcome": "valid", "faults": [], "span": [500, 2500]], ["outcome": "valid", "faults": [], "span": [2000, 3000]]]),  // overlap
            with([["outcome": "valid", "faults": [], "span": [500]]]),  // one number
        ]
        for b in bad { #expect(throws: SequenceIssues.self) { try LandmarkSequence.parse(b).get() } }
        #expect(throws: Never.self) { try LandmarkSequence.parse(with([["outcome": "valid", "faults": []]])).get() }
    }
}
