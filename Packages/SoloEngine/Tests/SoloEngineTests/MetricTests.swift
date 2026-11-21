import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// Port of the source `engine/test/metrics.test.ts` (commit c2fe3fd).

private func computer(_ pairs: [(String, MetricDefinition)]) throws -> MetricComputer {
    try MetricComputer(metrics: pairs.map { Metric(name: $0.0, definition: $0.1) })
}

private func lm(_ name: LandmarkName) -> LandmarkRef { .landmark(name) }
private func ref(_ raw: String) -> LandmarkRef { LandmarkRef(raw)! }

/// Overrides image coordinates of some landmarks on a copy of a frame.
private func withImage(_ base: Frame, _ points: [LandmarkName: (x: Double, y: Double)]) -> Frame {
    var f = base
    for (name, xy) in points {
        f.image[name.index].x = xy.x
        f.image[name.index].y = xy.y
    }
    return f
}

private func isClose(_ a: Double?, _ b: Double, digits: Int = 2) -> Bool {
    guard let a else { return false }
    return Swift.abs(a - b) < pow(10, Double(-digits)) / 2
}

private func pack(_ id: String) throws -> RulePack {
    try RulePackLoader.load(try Repo.read(Repo.sourceExercises.appendingPathComponent("\(id).json"))).get().pack
}

@Suite("Metric functions") struct MetricFunctionValueTests {
    @Test func angleUsesWorldCoordinates() throws {
        let c = try computer([("k", .angle(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle)))])
        for view in [CameraView.front, .side] {
            #expect(isClose(c.compute(squatFrame(SquatParams(kneeAngle: 105), FrameOptions(view: view)), near: .left)["k"], 105, digits: 1))
        }
    }

    @Test func nearFarFollowTheNearSide() throws {
        let c = try computer([("near", .angle(ref("near_hip"), ref("near_knee"), ref("near_ankle")))])
        let f = squatFrame(SquatParams(kneeAngle: 120), FrameOptions(view: .side))
        #expect(isClose(c.compute(f, near: .left)["near"], 120, digits: 1))
        #expect(isClose(c.compute(f, near: .right)["near"], 120, digits: 1))
    }

    @Test func avgAndAbsDiffCombineMetrics() throws {
        let c = try computer([
            ("l", .angle(lm(.leftShoulder), lm(.leftElbow), lm(.leftWrist))),
            ("r", .angle(lm(.rightShoulder), lm(.rightElbow), lm(.rightWrist))),
            ("mean", .avg("l", "r")),
            ("diff", .absDiff("l", "r")),
        ])
        let v = c.compute(pressFrame(PressParams(elbowAngle: 160, elbowAngleRight: 120), FrameOptions(view: .front)), near: .left)
        #expect(isClose(v["mean"], 140, digits: 1))
        #expect(isClose(v["diff"], 40, digits: 1))
    }

    @Test func maxTakesTheLargerOrTheComputableOne() throws {
        let f = squatFrame(SquatParams(kneeAngle: 120), FrameOptions(view: .front))
        let c = try computer([
            ("l", .angle(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle))),
            ("r", .angle(lm(.rightHip), lm(.rightKnee), lm(.rightAnkle))),
            ("m", .max("l", "straight")),
            ("straight", .angleFromVertical(lm(.leftHip), lm(.leftShoulder))),
            ("broken", .angleFromVertical(lm(.leftHip), lm(.leftHip))),  // NaN
            ("either", .max("broken", "l")),
            ("none", .max("broken", "broken")),
        ])
        let v = c.compute(f, near: .left)
        #expect(isClose(v["m"], Swift.max(v["l"]!, v["straight"]!), digits: 6))
        #expect(isClose(v["either"], v["l"]!, digits: 6))
        #expect(v["none"]!.isNaN)
    }

    @Test func metricsMayDependOnMetricsDefinedLater() throws {
        let c = try computer([
            ("mean", .avg("l", "r")),
            ("l", .angle(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle))),
            ("r", .angle(lm(.rightHip), lm(.rightKnee), lm(.rightAnkle))),
        ])
        #expect(c.order == ["l", "r", "mean"])
        #expect(isClose(c.compute(squatFrame(SquatParams(kneeAngle: 100), FrameOptions(view: .front)), near: .left)["mean"], 100, digits: 1))
    }

    @Test func cyclesAndUndefinedMetricsAreBuildErrors() {
        #expect(throws: MetricComputer.BuildError.cycle("a")) {
            try computer([("a", .avg("b", "b")), ("b", .avg("a", "a"))])
        }
        #expect(throws: MetricComputer.BuildError.undefinedMetric("x")) { try computer([("a", .avg("x", "x"))]) }
    }

    @Test func diffYIsHeightAboveNormalizedByTorsoLength() throws {
        let base = squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front))
        // shoulders at y=0.3, hips at y=0.5 -> torso length 0.2
        let f = withImage(base, [
            .leftShoulder: (0.45, 0.3), .rightShoulder: (0.55, 0.3),
            .leftHip: (0.47, 0.5), .rightHip: (0.53, 0.5), .leftWrist: (0.45, 0.25),
        ])
        let c = try computer([("up", .diffY(lm(.leftWrist), lm(.leftShoulder))), ("down", .diffY(lm(.leftShoulder), lm(.leftWrist)))])
        let v = c.compute(f, near: .left)
        #expect(isClose(v["up"], 0.05 / 0.2))
        #expect(isClose(v["down"], -0.05 / 0.2))
    }

    @Test func angleFromVerticalZeroUpNinetyHorizontal180Down() throws {
        let base = squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .side))
        let c = try computer([("lean", .angleFromVertical(lm(.leftHip), lm(.leftShoulder)))])
        func at(_ x: Double, _ y: Double) -> Double? {
            c.compute(withImage(base, [.leftHip: (0.5, 0.5), .leftShoulder: (x, y)]), near: .left)["lean"]
        }
        #expect(isClose(at(0.5, 0.3), 0))
        #expect(isClose(at(0.7, 0.5), 90))
        #expect(isClose(at(0.3, 0.5), 90))
        #expect(isClose(at(0.5, 0.7), 180))
        #expect(isClose(at(0.6, 0.4), 45))
    }

    @Test func angleFromVerticalReproducesSyntheticTorsoLean() throws {
        let c = try computer([("lean", .angleFromVertical(ref("near_hip"), ref("near_shoulder")))])
        let f = squatFrame(SquatParams(kneeAngle: 100, torsoLean: 40), FrameOptions(view: .side))
        #expect(isClose(c.compute(f, near: .left)["lean"], 40, digits: 1))
    }

    @Test func kneeInwardRatioSignsAndSymmetry() throws {
        let c = try computer([
            ("l", .kneeInwardRatio(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle))),
            ("r", .kneeInwardRatio(lm(.rightHip), lm(.rightKnee), lm(.rightAnkle))),
        ])
        let aligned = c.compute(squatFrame(SquatParams(kneeAngle: 120), FrameOptions(view: .front)), near: .left)
        #expect(isClose(aligned["l"], 0, digits: 3))
        #expect(isClose(aligned["r"], 0, digits: 3))
        let inward = c.compute(squatFrame(SquatParams(kneeAngle: 120, valgus: 0.1), FrameOptions(view: .front)), near: .left)
        #expect(inward["l"]! > 0.05)
        #expect(isClose(inward["r"], inward["l"]!, digits: 6))
        let outward = c.compute(squatFrame(SquatParams(kneeAngle: 120, valgus: -0.1), FrameOptions(view: .front)), near: .left)
        #expect(outward["l"]! < -0.05)
    }

    @Test func kneeInwardRatioEqualsValgusWhenStraight() throws {
        let c = try computer([("l", .kneeInwardRatio(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle)))])
        let f = squatFrame(SquatParams(kneeAngle: 180, valgus: 0.1), FrameOptions(view: .front))
        #expect(isClose(c.compute(f, near: .left)["l"], 0.1, digits: 2))
    }

    @Test func signedOffsetReproducesPushupHipOffset() throws {
        let c = try computer([("hip", .signedOffset(ref("near_shoulder"), ref("near_hip"), ref("near_ankle")))])
        for facing in [FrameOptions.Facing.left, .right] {
            let near: PersonSide = facing == .right ? .left : .right
            for hipOffset in [0, 0.08, -0.06] {
                let f = pushupFrame(PushupParams(elbowAngle: 150, hipOffset: hipOffset), FrameOptions(view: .side, facing: facing))
                #expect(isClose(c.compute(f, near: near)["hip"], hipOffset, digits: 3), "\(facing) \(hipOffset)")
            }
        }
    }

    @Test func degenerateGeometryYieldsNaN() throws {
        let base = squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front))
        let f = withImage(base, [.leftHip: (0.5, 0.5), .leftShoulder: (0.5, 0.5)])
        let c = try computer([("lean", .angleFromVertical(lm(.leftHip), lm(.leftShoulder)))])
        #expect(c.compute(f, near: .left)["lean"]!.isNaN)
    }

    /// `Math.max(-1, Math.min(1, NaN))` is NaN in JavaScript; `Swift.min(1, .nan)` is 1.
    @Test func missingLandmarkGivesNaNAngleNotZero() throws {
        var f = squatFrame(SquatParams(kneeAngle: 120), FrameOptions(view: .front))
        f.world[LandmarkName.leftKnee.index] = .missing
        f.image[LandmarkName.leftShoulder.index] = .missing
        let c = try computer([
            ("k", .angle(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle))),
            ("v", .angleFromVertical(lm(.leftHip), lm(.leftShoulder))),
            ("lean", .lateralLean(lm(.nose), lm(.leftHip))),
            ("chain", .chainHeight([lm(.nose), lm(.leftKnee)])),
        ])
        let v = c.compute(f, near: .left)
        #expect(v["k"]!.isNaN)
        #expect(v["v"]!.isNaN)
        #expect(v["chain"]!.isNaN)
    }

    @Test func lateralLeanAndChainHeightOnSyntheticFrames() throws {
        let c = try computer([
            ("lean", .lateralLean(lm(.leftShoulder), lm(.leftHip))),
            ("chain", .chainHeight([lm(.leftHip), lm(.leftKnee), lm(.leftAnkle)])),
            ("bent", .chainHeight([lm(.leftShoulder), lm(.leftHip), lm(.leftKnee), lm(.leftAnkle)])),
        ])
        let front = c.compute(squatFrame(SquatParams(kneeAngle: 180), FrameOptions(view: .front)), near: .left)
        // Synthetic shoulders sit 0.08 m outside the hips (0.19 vs 0.11), 0.52 m above them.
        #expect(isClose(front["lean"], 0.08 / (0.08 * 0.08 + 0.52 * 0.52).squareRoot(), digits: 9))
        #expect(isClose(front["chain"], 1, digits: 9))  // hip, knee, ankle stacked vertically
        #expect(isClose(front["bent"], 1.40 / ((0.08 * 0.08 + 0.52 * 0.52).squareRoot() + 0.88), digits: 9))
        // Turned sideways: shoulders overlap horizontally, so the lean is undefined.
        let side = c.compute(squatFrame(SquatParams(kneeAngle: 180), FrameOptions(view: .side)), near: .left)
        #expect(side["lean"]!.isNaN)
    }

    @Test func projectFunctionsAreUnknownUntilT27() throws {
        let c = try computer([("x", .lateralLean2d(lm(.nose), lm(.leftHip))), ("y", .min("x", "x"))])
        let v = c.compute(squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front)), near: .left)
        #expect(v["x"]!.isNaN && v["y"]!.isNaN)
    }
}

@Suite("landmarksOf") struct LandmarksOfTests {
    @Test func resolvedLandmarksTransitively() throws {
        let c = try computer([
            ("l", .angle(ref("near_hip"), ref("near_knee"), ref("near_ankle"))),
            ("r", .angle(ref("far_hip"), ref("far_knee"), ref("far_ankle"))),
            ("mean", .avg("l", "r")),
        ])
        #expect(c.landmarks(of: "l", near: .left) == [.leftAnkle, .leftHip, .leftKnee])
        #expect(c.landmarks(of: "mean", near: .right) == [.leftAnkle, .leftHip, .leftKnee, .rightAnkle, .rightHip, .rightKnee])
    }
}

@Suite("Real rule packs on synthetic frames") struct RulePackMetricTests {
    @Test func squatPackMetricsMatchThePose() throws {
        let c = try MetricComputer(pack: try pack("squat"))
        let v = c.compute(squatFrame(SquatParams(kneeAngle: 95, torsoLean: 35), FrameOptions(view: .side)), near: .left)
        #expect(isClose(v["knee_angle_near"], 95, digits: 1))
        #expect(isClose(v["torso_lean"], 35, digits: 1))
    }

    @Test func pushupAndPressPacksProduceFiniteValues() throws {
        let cases: [(String, Frame)] = [
            ("pushup", pushupFrame(PushupParams(elbowAngle: 100, hipOffset: -0.05), FrameOptions(view: .side))),
            ("shoulder_press", pressFrame(PressParams(elbowAngle: 150), FrameOptions(view: .front))),
        ]
        for (id, frame) in cases {
            let p = try pack(id)
            let v = try MetricComputer(pack: p).compute(frame, near: .left)
            #expect(Set(v.keys) == Set(p.metricNames))
            for (k, x) in v { #expect(x.isFinite, "\(id).\(k)") }
        }
    }
}

@Suite("chooseNearSide") struct NearSideTests {
    @Test func picksTheMoreVisibleSide() {
        let reps = [squatRep(kneeAngle: 90)]
        #expect(chooseNearSide(squatSequence(view: .side, reps: reps, options: SequenceOptions(facing: .right)).frames) == .left)
        #expect(chooseNearSide(squatSequence(view: .side, reps: reps, options: SequenceOptions(facing: .left)).frames) == .right)
    }

    @Test func tiesGoToTheLeftSide() {
        #expect(chooseNearSide([squatFrame(SquatParams(kneeAngle: 170), FrameOptions(view: .front))]) == .left)
    }
}
