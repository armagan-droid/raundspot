import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// Port of the source `engine/test/setup.test.ts` (commit c2fe3fd), plus the
// specs/12 "S1 hesapları" additions.

private func pack(_ id: String) -> RulePack { try! Repo.load(id).pack }

/// Scales image coordinates around (cx, cy) and moves them by (dx, dy).
private func transform(_ f: Frame, _ k: Double, _ dx: Double = 0, _ dy: Double = 0, cx: Double = 0.5, cy: Double = 0.55) -> Frame {
    var out = f
    for i in out.image.indices {
        out.image[i].x = cx + (out.image[i].x - cx) * k + dx
        out.image[i].y = cy + (out.image[i].y - cy) * k + dy
    }
    return out
}

private func setVisibility(_ f: Frame, _ names: [LandmarkName], _ v: Double) -> Frame {
    var out = f
    for n in names { out.image[n.index].visibility = v }
    return out
}

private func samples(_ frames: [Frame]) -> [SetupSample] { frames.map { SetupSample(frame: $0) } }
private func oneSecond(_ make: (Double) -> Frame) -> [Frame] { (0..<30).map { make(Double($0) * 1000 / 30) } }
private func standing(_ t: Double) -> Frame { squatFrame(SquatParams(kneeAngle: 172), FrameOptions(view: .front, t: t)) }

@Suite("selectPerson (ref 07)") struct SelectPersonTests {
    private let center = squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front))
    private var smallSide: Frame { transform(center, 0.6, 0.3) }

    @Test func aSinglePersonIsSelected() {
        let s = selectPerson([center])
        #expect(s.frame == center)
        #expect(!s.ambiguous)
        #expect(s.track != nil)
    }

    @Test func theLargerMoreCentralPersonWins() {
        #expect(selectPerson([smallSide, center]).frame == center)
    }

    @Test func twoSimilarCandidatesWithoutATrackAreAmbiguous() {
        let s = selectPerson([transform(center, 1, -0.05), transform(center, 1, 0.05)])
        #expect(s.ambiguous)
        #expect(s.frame == nil)
        #expect(s.track == nil)
    }

    @Test func anExistingTrackIsKeptEvenIfSomeoneMoreCentralAppears() {
        let first = selectPerson([smallSide])
        let next = selectPerson([center, transform(smallSide, 1, 0.02)], track: first.track)
        #expect(next.frame != center)
        #expect(!next.ambiguous)
    }

    @Test func whenTheTrackedPersonIsGoneSelectionStartsOver() {
        let first = selectPerson([smallSide])
        #expect(selectPerson([center], track: first.track).frame == center)
    }

    @Test func noCandidatesNoFrameTrackKept() {
        let first = selectPerson([center])
        let s = selectPerson([], track: first.track)
        #expect(s.frame == nil)
        #expect(s.track == first.track)
    }

    @Test func onlyTheFirstTwoCandidatesAreConsidered() {
        // numPoses = 2 (specs/03): a third, better candidate is dropped
        let s = selectPerson([smallSide, transform(center, 0.5, -0.3), center])
        #expect(s.frame == smallSide)
    }
}

@Suite("assessSetup (ref 08 A3)") struct AssessSetupTests {
    @Test func frontViewSquatReadyWithFrontChecks() {
        let r = assessSetup(samples(oneSecond(standing)), pack: pack("squat"))
        #expect(r.ready && r.view == .front && r.hints.isEmpty)
        #expect(r.activeFaults["squat"] == ["insufficient_depth", "knee_valgus"])
    }

    @Test func sideViewSquatNearSideAndSideChecks() {
        let r = assessSetup(samples(oneSecond { squatFrame(SquatParams(kneeAngle: 172), FrameOptions(view: .side, facing: .left, t: $0)) }),
                            pack: pack("squat"))
        #expect(r.ready && r.view == .side && r.nearSide == .right)
        #expect(r.activeFaults["squat"] == ["insufficient_depth", "excessive_forward_lean"])
    }

    @Test func pushupSeenFromTheFrontAsksToTurnSideways() {
        // AC-8.5
        let r = assessSetup(samples(oneSecond { pushupFrame(PushupParams(elbowAngle: 165), FrameOptions(view: .front, t: $0)) }),
                            pack: pack("pushup"))
        #expect(!r.ready)
        #expect(r.hints.contains(.turnSide))
    }

    @Test func pushupFromTheSideIsReady() {
        // the horizontal body is not "too far"
        let r = assessSetup(samples(oneSecond { pushupFrame(PushupParams(elbowAngle: 165), FrameOptions(view: .side, t: $0)) }),
                            pack: pack("pushup"))
        #expect(r.ready && r.view == .side && r.hints.isEmpty)
    }

    @Test func aFrontOnlyExerciseSeenFromTheSideAsksToFaceTheCamera() throws {
        var json = try Repo.sourceJSON("shoulder_press")
        json["camera"]!["views"] = ["front"]
        for i in 0..<(json["faults"]!.arrayValue!.count) { json["faults"]![i]!["views"] = nil }
        let p = try Repo.load(json: json).pack
        let r = assessSetup(samples(oneSecond { pressFrame(PressParams(elbowAngle: 85), FrameOptions(view: .side, t: $0)) }), pack: p)
        #expect(!r.ready)
        #expect(r.hints.contains(.faceCamera))
    }

    @Test func anAmbiguousViewAsksToAdjustTheAngle() {
        let squeezed = { (t: Double) -> Frame in
            var f = standing(t)
            let li = LandmarkName.leftShoulder.index, ri = LandmarkName.rightShoulder.index
            let mid = (f.image[li].x + f.image[ri].x) / 2
            f.image[li].x = mid + (f.image[li].x - mid) * 0.45
            f.image[ri].x = mid + (f.image[ri].x - mid) * 0.45
            return f
        }
        let r = assessSetup(samples(oneSecond(squeezed)), pack: pack("squat"))
        #expect(!r.ready && r.view == .ambiguous)
        #expect(r.hints.contains(.adjustAngle))
    }

    @Test func tooFarAwayAsksToMoveCloser() {
        let r = assessSetup(samples(oneSecond { transform(standing($0), 0.4) }), pack: pack("squat"))
        #expect(!r.ready)
        #expect(r.hints.contains(.moveCloser))
    }

    @Test func feetOutsideTheFrameAsksToStepBack() {
        let r = assessSetup(samples(oneSecond { transform(standing($0), 1.6, 0, 0.1) }), pack: pack("squat"))
        #expect(!r.ready)
        #expect(r.hints.contains(.stepBack))
    }

    @Test func hiddenLegsAskToShowTheFullBody() {
        // both sides: hiding one leg just moves the near side to the other leg
        let r = assessSetup(samples(oneSecond { setVisibility(standing($0), [.leftKnee, .rightKnee], 0.2) }), pack: pack("squat"))
        #expect(!r.ready)
        #expect(r.hints.contains(.showFullBody))
    }

    @Test func ambiguousPersonSelectionInTwentyPercentOfFramesBlocksSetup() {
        let s = oneSecond(standing).enumerated().map { i, f in
            SetupSample(frame: i % 4 == 0 ? nil : f, ambiguous: i % 4 == 0)
        }
        let r = assessSetup(s, pack: pack("squat"))
        #expect(!r.ready)
        #expect(r.hints.contains(.multiplePeople))
    }

    @Test func readyWhenAtLeastEightyPercentOfFramesPass() {
        let s = oneSecond(standing).enumerated().map { i, f in
            SetupSample(frame: i % 7 == 0 ? setVisibility(f, [.leftKnee, .rightKnee], 0.1) : f)  // ~14% bad
        }
        #expect(assessSetup(s, pack: pack("squat")).ready)
    }

    @Test func noFramesNotReadyShowTheFullBody() {
        let r = assessSetup([], pack: pack("squat"))
        #expect(!r.ready && r.hints == [.showFullBody])
    }

    @Test func mixedFailuresBelowEachLimitStillNameTheMostFrequentOne() {
        let ok = squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front))
        let hidden = setVisibility(ok, [.leftAnkle, .rightAnkle], 0.1)  // show_full_body
        let edge = transform(ok, 1, 0, 0.5)  // pushed off the bottom: step_back
        // 30 samples: 21 pass (70 % < 80 %), 5 + 4 failures, each ≤ the 20 % limit (6)
        let frames = Array(repeating: ok, count: 21) + Array(repeating: hidden, count: 5) + Array(repeating: edge, count: 4)
        let a = assessSetup(samples(frames), pack: pack("squat"))
        #expect(!a.ready)
        #expect(a.hints.first == .showFullBody)
    }

    @Test func listsTheRequiredLandmarkIndicesForTheOverlay() {
        let a = assessSetup(samples(oneSecond { _ in squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front)) }),
                            pack: pack("squat"))
        #expect(a.requiredLandmarks.count == pack("squat").camera.minVisibleLandmarks.count)
        #expect(a.requiredLandmarks.allSatisfy { $0 >= 0 && $0 < LandmarkName.count })
    }
}

@Suite("faultLandmarks (T2 highlight)") struct FaultLandmarksTests {
    @Test func followsTheChecksMetricsDownToLandmarks() throws {
        let expected = [LandmarkName.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle].map(\.index).sorted()
        #expect(faultLandmarks(try Repo.load("squat"), faultId: "knee_valgus", nearSide: .left) == expected)
    }

    @Test func nearFarReferencesResolveWithTheNearSide() throws {
        let l = faultLandmarks(try Repo.load("pushup"), faultId: "hip_sag", nearSide: .right)
        #expect(l.contains(LandmarkName.rightHip.index))
        #expect(!l.contains(LandmarkName.leftHip.index))
    }

    @Test func anUnknownFaultHasNoLandmarks() throws {
        #expect(faultLandmarks(try Repo.load("squat"), faultId: "nope", nearSide: .left).isEmpty)
    }
}

@Suite("assessSetup: problem edges") struct ProblemEdgeTests {
    private let ok = squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front))

    @Test func feetBelowThePictureIsTheBottomEdge() {
        let a = assessSetup(samples(oneSecond { _ in transform(ok, 1, 0, 0.3) }), pack: pack("squat"))
        #expect(a.edges.contains(.bottom))
        #expect(!a.edges.contains(.top))
    }

    @Test func aWellPlacedPersonHasNoProblemEdges() {
        #expect(assessSetup(samples(oneSecond { _ in ok }), pack: pack("squat")).edges.isEmpty)
    }
}

// MARK: - specs/12 "S1 hesapları"

/// The vertical field of view at which `frame` reads as `meters` away.
private func fov(for frame: Frame, meters: Double, heightM: Double = 1.70) -> Double {
    let top = [LandmarkName.nose, .leftEye, .rightEye, .leftEar, .rightEar].map { frame[image: $0].y }.min()!
    let bottom = Swift.max(frame[image: .leftAnkle].y, frame[image: .rightAnkle].y)
    return 2 * atan(0.9 * heightM / (2 * meters * (bottom - top))) * 360 / (2 * .pi)
}

@Suite("S1: distance (specs/12)") struct SetupDistanceTests {
    @Test func estimateFromTheHeadToAnkleSpan() {
        var image = Array(repeating: Landmark.missing, count: LandmarkName.count)
        image[LandmarkName.nose.index] = Landmark(x: 0.5, y: 0.2, z: 0, visibility: 1)
        image[LandmarkName.leftAnkle.index] = Landmark(x: 0.5, y: 0.8, z: 0, visibility: 1)
        let f = Frame(t: 0, image: image, world: image)
        let d = estimateDistance(f, minVisibility: 0.6, verticalFOVDegrees: 60, heightM: 1.70)!
        #expect(Swift.abs(d - 0.9 * 1.7 / (2 * tan(Double.pi / 6) * 0.6)) < 1e-12)
        // a taller person at the same size in the picture is further away
        #expect(estimateDistance(f, minVisibility: 0.6, verticalFOVDegrees: 60, heightM: 1.90)! > d)
        var noHead = f
        noHead.image[LandmarkName.nose.index].visibility = 0.1
        #expect(estimateDistance(noHead, minVisibility: 0.6, verticalFOVDegrees: 60, heightM: 1.70) == nil)
    }

    @Test(arguments: [(1.6, SetupHint.stepBack), (3.6, SetupHint.moveCloser)])
    func outOfRangeDistanceIsAHint(meters: Double, hint: SetupHint) {
        let frames = oneSecond(standing)
        let context = SetupContext(verticalFOVDegrees: fov(for: frames[0], meters: meters))
        let r = assessSetup(samples(frames), pack: pack("squat"), context: context)
        #expect(!r.ready)
        #expect(r.hints == [hint])
        #expect(Swift.abs(r.distanceM! - meters) < 1e-9)
    }

    @Test func inRangeIsReady() {
        let frames = oneSecond(standing)
        let r = assessSetup(samples(frames), pack: pack("squat"), context: SetupContext(verticalFOVDegrees: fov(for: frames[0], meters: 2.5)))
        #expect(r.ready && r.hints.isEmpty)
    }

    @Test func theDistanceRuleReplacesTheBoxSizeRule() {
        // 40 % of the picture would be "too far" by the box rule, but at 2.5 m it is fine
        let frames = oneSecond { transform(standing($0), 0.4) }
        let context = SetupContext(verticalFOVDegrees: fov(for: frames[0], meters: 2.5))
        #expect(assessSetup(samples(frames), pack: pack("squat"), context: context).ready)
        #expect(!assessSetup(samples(frames), pack: pack("squat")).ready)  // unknown FOV: box rule
    }

    @Test func profileHeightIsUsed() {
        let frames = oneSecond(standing)
        let fov = fov(for: frames[0], meters: 2.9, heightM: 1.70)
        #expect(assessSetup(samples(frames), pack: pack("squat"), context: SetupContext(verticalFOVDegrees: fov)).ready)
        let tall = SetupContext(verticalFOVDegrees: fov, heightM: 1.95)  // reads as 3.3 m
        #expect(assessSetup(samples(frames), pack: pack("squat"), context: tall).hints == [.moveCloser])
    }

    @Test func horizontalPostureHasNoDistanceCheck() {
        let frames = oneSecond { pushupFrame(PushupParams(elbowAngle: 165), FrameOptions(view: .side, t: $0)) }
        let r = assessSetup(samples(frames), pack: pack("pushup"), context: SetupContext(verticalFOVDegrees: 5))
        #expect(r.ready && r.distanceM == nil)
    }
}

@Suite("S1: phone tilt and rotation (specs/12)") struct SetupPhoneTests {
    @Test func aTiltedPhoneIsTheFirstHintAndBlocksSetup() {
        let r = assessSetup(samples(oneSecond(standing)), pack: pack("squat"), context: SetupContext(deviceTiltDegrees: -15))
        #expect(!r.ready && r.hints == [.phoneUpright])
        #expect(assessSetup(samples(oneSecond(standing)), pack: pack("squat"), context: SetupContext(deviceTiltDegrees: 8)).ready)
    }

    @Test func aHorizontalExerciseInAPortraitPictureAsksToRotateThePhone() {
        let portrait = oneSecond { t -> Frame in
            var f = pushupFrame(PushupParams(elbowAngle: 165), FrameOptions(view: .side, t: t))
            f.imageAspect = 9.0 / 16
            return f
        }
        let r = assessSetup(samples(portrait), pack: pack("pushup"), context: SetupContext(deviceTiltDegrees: 20))
        #expect(!r.ready)
        #expect(r.hints.prefix(2) == [.rotatePhone, .phoneUpright])
        // standing exercises do not care about the picture's orientation
        let squat = oneSecond { t -> Frame in
            var f = standing(t)
            f.imageAspect = 9.0 / 16
            return f
        }
        #expect(assessSetup(samples(squat), pack: pack("squat")).ready)
    }
}

@Suite("S1: several rule packs (specs/12, reflex mode)") struct SetupMultiPackTests {
    @Test func landmarkUnionAndActiveFaultsPerPack() {
        let packs = [pack("slip_left"), pack("duck")]
        let r = assessSetup(samples(oneSecond { evaderFrame(EvaderParams(), FrameOptions(view: .front, t: $0)) }), packs: packs)
        #expect(r.ready, "\(r.hints)")
        let union = Set(packs.flatMap { $0.camera.minVisibleLandmarks.map { $0.resolve(near: r.nearSide).index } })
        #expect(Set(r.requiredLandmarks) == union)
        #expect(r.requiredLandmarks.count == union.count)
        #expect(Set(r.activeFaults.keys) == ["slip_left", "duck"])
    }

    @Test func viewsAreIntersected() {
        // squat (front, side) + push-up (side): only side is accepted
        let packs = [pack("squat"), pack("pushup")]
        let r = assessSetup(samples(oneSecond(standing)), packs: packs)
        #expect(!r.ready)
        #expect(r.hints.contains(.turnSide))
    }
}
