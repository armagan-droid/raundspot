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
}
