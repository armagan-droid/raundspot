import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// AC-4.3: the specs/04 metric functions — sign, mirroring (left↔right),
// undefined geometry → NaN, and the aspect correction.

private func computer(_ pairs: [(String, MetricDefinition)]) -> MetricComputer {
    try! MetricComputer(metrics: pairs.map { Metric(name: $0.0, definition: $0.1) })
}

private func lm(_ n: LandmarkName) -> LandmarkRef { .landmark(n) }

private func value(_ def: MetricDefinition, _ frame: Frame, near: PersonSide = .left) -> Double {
    computer([("m", def)]).compute(frame, near: near)["m"]!
}

private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { Swift.abs(a - b) < tol }

/// A frame with every landmark missing except the given image points (visibility 1).
private func imageFrame(_ points: [LandmarkName: (Double, Double)], aspect: Double = 1) -> Frame {
    var image = Array(repeating: Landmark.missing, count: LandmarkName.count)
    for (n, p) in points { image[n.index] = Landmark(x: p.0, y: p.1, z: 0, visibility: 1) }
    return Frame(t: 0, image: image, world: Array(repeating: .missing, count: LandmarkName.count), imageAspect: aspect)
}

/// The same picture flipped horizontally (front camera mirroring): x → 1 − x,
/// landmark names unchanged (unlike `mirrorFrame`, which also swaps sides).
private func flipX(_ f: Frame) -> Frame {
    var out = f
    for i in out.image.indices { out.image[i].x = 1 - out.image[i].x }
    for i in out.world.indices { out.world[i].x = -out.world[i].x }
    return out
}

private var evaderFront: FrameOptions { FrameOptions(view: .front) }
private var fighterSide: FrameOptions { FrameOptions(view: .side) }

@Suite("min (specs/04)") struct MinMetricTests {
    private let c = computer([
        ("a", .angle2d(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle))),
        ("b", .angle2d(lm(.rightHip), lm(.rightKnee), lm(.rightAnkle))),
        ("m", .min("a", "b")),
    ])

    @Test func smallerOfTwoAndNaNSideDoesNotCount() {
        let f = imageFrame([.leftHip: (0.4, 0.4), .leftKnee: (0.4, 0.6), .leftAnkle: (0.4, 0.8),   // 180°
                            .rightHip: (0.6, 0.4), .rightKnee: (0.6, 0.6), .rightAnkle: (0.8, 0.6)])  // 90°
        let v = c.compute(f, near: .left)
        #expect(close(v["m"]!, 90))
        var oneSide = f
        oneSide.image[LandmarkName.rightAnkle.index] = .missing
        #expect(close(c.compute(oneSide, near: .left)["m"]!, 180))
        #expect(computer([("m", .min("x", "y")), ("x", .angle2d(lm(.nose), lm(.nose), lm(.nose))),
                          ("y", .angle2d(lm(.nose), lm(.nose), lm(.nose)))]).compute(f, near: .left)["m"]!.isNaN)
    }

    @Test func mirroredFrameGivesTheSameMinimum() {
        let f = squatFrame(SquatParams(kneeAngle: 120, torsoLean: 20), FrameOptions(view: .side))
        #expect(close(c.compute(f, near: .left)["m"]!, c.compute(mirrorFrame(f), near: .left)["m"]!, 1e-9))
    }
}

@Suite("angle2d (specs/04)") struct Angle2DTests {
    private let knee = MetricDefinition.angle2d(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle))

    @Test func rightAngleAndStraightLine() {
        #expect(close(value(knee, imageFrame([.leftHip: (0.5, 0.2), .leftKnee: (0.5, 0.5), .leftAnkle: (0.8, 0.5)])), 90))
        #expect(close(value(knee, imageFrame([.leftHip: (0.5, 0.2), .leftKnee: (0.5, 0.5), .leftAnkle: (0.5, 0.8)])), 180))
    }

    @Test func aspectIsCorrected() {
        // 45° in a square image: dx = dy. In a 9:16 portrait image the same
        // normalized offsets are a narrower angle in pixels.
        let pts: [LandmarkName: (Double, Double)] = [.leftHip: (0.5, 0.2), .leftKnee: (0.5, 0.5), .leftAnkle: (0.8, 0.8)]
        #expect(close(value(knee, imageFrame(pts)), 135))
        let k = 9.0 / 16
        let expected = 180 - atan2(0.3 * k, 0.3) * 180 / .pi
        #expect(close(value(knee, imageFrame(pts, aspect: k)), expected))
    }

    @Test func matchesTheWorldAngleInAPureSideView() {
        // the side-view synthetic squat moves in the image plane
        let f = squatFrame(SquatParams(kneeAngle: 100, torsoLean: 30), FrameOptions(view: .side))
        let world = value(.angle(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle)), f)
        #expect(close(value(knee, f), world, 1e-6))
    }

    @Test func mirroringSwapsSides() {
        let f = squatFrame(SquatParams(kneeAngle: 110), FrameOptions(view: .front))
        let right = MetricDefinition.angle2d(lm(.rightHip), lm(.rightKnee), lm(.rightAnkle))
        #expect(close(value(knee, f), value(right, mirrorFrame(f)), 1e-9))
    }

    @Test func zeroLengthArmIsNaN() {
        #expect(value(knee, imageFrame([.leftHip: (0.5, 0.5), .leftKnee: (0.5, 0.5), .leftAnkle: (0.5, 0.8)])).isNaN)
        #expect(value(knee, imageFrame([:])).isNaN)
    }
}

@Suite("lateralLean2d (specs/04)") struct LateralLean2DTests {
    private let head = MetricDefinition.lateralLean2d(lm(.nose), lm(.leftHip))

    @Test func positiveTowardThePersonsLeft() {
        #expect(value(head, evaderFrame(EvaderParams(slip: 25), evaderFront)) > 0.2)
        #expect(value(head, evaderFrame(EvaderParams(slip: -25), evaderFront)) < -0.2)
    }

    @Test func frontCameraMirroringKeepsTheSign() {
        // AC-3.6 synthetic half: a horizontally flipped picture of a left slip is still a left slip
        let f = evaderFrame(EvaderParams(slip: 25), evaderFront)
        #expect(close(value(head, f), value(head, flipX(f)), 1e-9))
    }

    @Test func mirroringSwapsSides() {
        // a mirrored person (sides swapped) slipping left is a right slip of equal size
        let f = evaderFrame(EvaderParams(slip: 25), evaderFront)
        let rightHip = MetricDefinition.lateralLean2d(lm(.nose), lm(.rightHip))
        #expect(close(value(head, f), -value(rightHip, mirrorFrame(f)), 1e-9))
    }

    @Test func closeToTheWorldLeanForAFrontalSlip() {
        // the world version divides by the 3D length; without forward lean they nearly agree
        let f = evaderFrame(EvaderParams(slip: 20), evaderFront)
        let world = value(.lateralLean(lm(.nose), lm(.leftHip)), f)
        #expect(close(value(head, f), world, 0.005))
    }

    @Test func sidewaysIsNaN() {
        #expect(value(head, evaderFrame(EvaderParams(slip: 25), FrameOptions(view: .side))).isNaN)
    }

    @Test func narrowShouldersOnlyAfterAspectCorrectionAreNaN() {
        // spread 0.1 wide, torso 0.3 tall: ratio 0.33 square, 0.19 at 9:16
        let pts: [LandmarkName: (Double, Double)] = [
            .leftShoulder: (0.55, 0.3), .rightShoulder: (0.45, 0.3), .leftHip: (0.55, 0.6), .rightHip: (0.45, 0.6),
            .nose: (0.52, 0.2),
        ]
        #expect(!value(head, imageFrame(pts)).isNaN)
        #expect(value(head, imageFrame(pts, aspect: 9.0 / 16)).isNaN)
    }

    @Test func zeroLengthIsNaN() {
        let pts: [LandmarkName: (Double, Double)] = [
            .leftShoulder: (0.6, 0.3), .rightShoulder: (0.4, 0.3), .leftHip: (0.55, 0.6), .rightHip: (0.45, 0.6),
            .nose: (0.55, 0.6),
        ]
        #expect(value(head, imageFrame(pts)).isNaN)
    }
}

@Suite("chainHeight2d (specs/04)") struct ChainHeight2DTests {
    private let chain = MetricDefinition.chainHeight2d([.nose, .leftShoulder, .leftHip, .leftKnee, .leftAnkle].map(lm))

    @Test func aboutOneStandingSmallerWhenBentInTheImagePlane() {
        let stand = value(chain, evaderFrame(EvaderParams(kneeAngle: 180), evaderFront))
        #expect(stand > 0.94)
        #expect(value(chain, evaderFrame(EvaderParams(slip: 30), evaderFront)) < stand - 0.02)
        // side view: a squat bends the chain in the image plane
        let squat = squatFrame(SquatParams(kneeAngle: 100, torsoLean: 30), FrameOptions(view: .side))
        #expect(value(chain, squat) < 0.85)
    }

    /// Known limit (specs/04 "Açık sorular"): seen from the front, a duck bends
    /// forward, out of the image plane; the projected segments shorten with the
    /// height, so the ratio barely moves (the world version drops to ~0.81).
    @Test func frontViewDuckBarelyMovesTheRatio() {
        let stand = value(chain, evaderFrame(EvaderParams(), evaderFront))
        let duck = value(chain, evaderFrame(EvaderParams(kneeAngle: 110, torsoLean: 25), evaderFront))
        #expect(stand - duck < 0.02)
        let world = MetricDefinition.chainHeight([.nose, .leftShoulder, .leftHip, .leftKnee, .leftAnkle].map(lm))
        #expect(value(world, evaderFrame(EvaderParams(), evaderFront)) - value(world, evaderFrame(EvaderParams(kneeAngle: 110, torsoLean: 25), evaderFront)) > 0.1)
    }

    @Test func straightVerticalChainIsOneAndUpsideDownIsMinusOne() {
        let up = imageFrame([.nose: (0.5, 0.1), .leftShoulder: (0.5, 0.2), .leftHip: (0.5, 0.5), .leftKnee: (0.5, 0.7), .leftAnkle: (0.5, 0.9)])
        #expect(close(value(chain, up), 1))
        let down = imageFrame([.nose: (0.5, 0.9), .leftShoulder: (0.5, 0.7), .leftHip: (0.5, 0.5), .leftKnee: (0.5, 0.2), .leftAnkle: (0.5, 0.1)])
        #expect(close(value(chain, down), -1))
    }

    @Test func aspectIsCorrected() {
        // a horizontal segment counts less in a portrait image
        let pts: [LandmarkName: (Double, Double)] = [.nose: (0.2, 0.2), .leftShoulder: (0.5, 0.2), .leftHip: (0.5, 0.5),
                                                     .leftKnee: (0.5, 0.5), .leftAnkle: (0.5, 0.5)]
        #expect(close(value(chain, imageFrame(pts)), 0.5))
        #expect(close(value(chain, imageFrame(pts, aspect: 0.5)), 0.3 / (0.15 + 0.3)))
    }

    @Test func mirroringSwapsSides() {
        let f = evaderFrame(EvaderParams(slip: 10, kneeAngle: 130, torsoLean: 15), evaderFront)
        let right = MetricDefinition.chainHeight2d([.nose, .rightShoulder, .rightHip, .rightKnee, .rightAnkle].map(lm))
        #expect(close(value(chain, f), value(right, mirrorFrame(f)), 1e-9))
    }

    @Test func zeroLengthChainIsNaN() {
        #expect(value(chain, imageFrame([.nose: (0.5, 0.5), .leftShoulder: (0.5, 0.5), .leftHip: (0.5, 0.5),
                                         .leftKnee: (0.5, 0.5), .leftAnkle: (0.5, 0.5)])).isNaN)
    }
}

@Suite("heightOverShoulders2d (specs/04)") struct HeightOverShoulders2DTests {
    private let height = MetricDefinition.heightOverShoulders2d(lm(.nose), lm(.leftAnkle))
    private let duckParams = EvaderParams(kneeAngle: 110, torsoLean: 25)

    /// The open question 6 case: a front-view duck lowers it about as much as the world `chainHeight`.
    @Test func frontViewDuckLowersIt() {
        let stand = value(height, evaderFrame(EvaderParams(), evaderFront))
        let duck = value(height, evaderFrame(duckParams, evaderFront))
        #expect(stand > 4 && stand < 4.6)
        #expect(duck < stand * 0.9)
        // a slip barely changes it, so a slip is not a duck
        #expect(value(height, evaderFrame(EvaderParams(slip: 25), evaderFront)) > stand * 0.94)
    }

    @Test func positiveWhenAAboveBAndAspectCorrected() {
        let pts: [LandmarkName: (Double, Double)] = [.leftShoulder: (0.6, 0.3), .rightShoulder: (0.4, 0.3),
                                                     .leftHip: (0.58, 0.6), .rightHip: (0.42, 0.6),
                                                     .nose: (0.5, 0.2), .leftAnkle: (0.55, 0.9)]
        #expect(close(value(height, imageFrame(pts)), 0.7 / 0.2))
        #expect(close(value(height, imageFrame(pts, aspect: 0.75)), 0.7 / 0.15))
        let below = MetricDefinition.heightOverShoulders2d(lm(.leftAnkle), lm(.nose))
        #expect(close(value(below, imageFrame(pts)), -0.7 / 0.2))
    }

    @Test func mirroringAndFrontCameraFlip() {
        let f = evaderFrame(EvaderParams(slip: 10, kneeAngle: 130, torsoLean: 15), evaderFront)
        let right = MetricDefinition.heightOverShoulders2d(lm(.nose), lm(.rightAnkle))
        #expect(close(value(height, f), value(right, mirrorFrame(f)), 1e-9))
        #expect(close(value(height, f), value(height, flipX(f)), 1e-9))
    }

    @Test func sidewaysOrZeroShoulderWidthIsNaN() {
        #expect(value(height, fighterFrame(FighterParams(), fighterSide)).isNaN)
        let pts: [LandmarkName: (Double, Double)] = [.leftShoulder: (0.5, 0.3), .rightShoulder: (0.5, 0.3),
                                                     .leftHip: (0.5, 0.6), .rightHip: (0.5, 0.6),
                                                     .nose: (0.5, 0.2), .leftAnkle: (0.5, 0.9)]
        #expect(value(height, imageFrame(pts)).isNaN)
    }
}

@Suite("sagittalLean2d (specs/04)") struct SagittalLean2DTests {
    private let lean = MetricDefinition.sagittalLean2d(lm(.nose), .near(joint: "hip"))

    @Test func positiveWhenTheHeadGoesBehindTheHips() {
        let back = value(lean, fighterFrame(FighterParams(torsoLean: 25), fighterSide))
        let upright = value(lean, fighterFrame(FighterParams(torsoLean: 0), fighterSide))
        #expect(back > 0.2)
        #expect(back > upright + 0.2)
        #expect(value(lean, fighterFrame(FighterParams(torsoLean: -20), fighterSide)) < upright)
    }

    @Test func facingEitherWayGivesTheSameValue() {
        let right = fighterFrame(FighterParams(torsoLean: 25), FrameOptions(view: .side, facing: .right))
        let left = fighterFrame(FighterParams(torsoLean: 25), FrameOptions(view: .side, facing: .left))
        let nearRight = chooseNearSide([right]), nearLeft = chooseNearSide([left])
        #expect(nearRight != nearLeft)
        #expect(close(value(lean, right, near: nearRight), value(lean, left, near: nearLeft), 1e-9))
        #expect(close(value(lean, right, near: nearRight), value(lean, mirrorFrame(right), near: nearRight.opposite), 1e-9))
    }

    @Test func frontViewIsNaN() {
        #expect(value(lean, evaderFrame(EvaderParams(), evaderFront)).isNaN)
    }

    @Test func undefinedFrontOrLengthIsNaN() {
        var f = fighterFrame(FighterParams(torsoLean: 25), fighterSide)
        f.image[LandmarkName.leftEar.index].x = f.image[LandmarkName.nose.index].x  // no "front"
        #expect(value(lean, f).isNaN)
        var g = fighterFrame(FighterParams(torsoLean: 25), fighterSide)
        g.image[LandmarkName.nose.index] = g.image[LandmarkName.leftHip.index]
        #expect(value(lean, g).isNaN)
    }

    @Test func aspectIsCorrected() {
        let pts: [LandmarkName: (Double, Double)] = [
            .leftShoulder: (0.5, 0.3), .rightShoulder: (0.5, 0.3), .leftHip: (0.5, 0.6), .rightHip: (0.5, 0.6),
            .nose: (0.4, 0.2), .leftEar: (0.45, 0.2),  // facing left (nose left of ear), head 0.1 behind? no: ahead
        ]
        // front = sign(0.4 − 0.45) = −1; a.x − b.x = −0.1 → value = −(−1)(−0.1·k)/len < 0 (head forward)
        let sq = value(lean, imageFrame(pts))
        #expect(close(sq, -0.1 / (0.1 * 0.1 + 0.4 * 0.4).squareRoot()))
        let k = 0.5
        #expect(close(value(lean, imageFrame(pts, aspect: k)), -0.1 * k / ((0.1 * k) * (0.1 * k) + 0.4 * 0.4).squareRoot()))
    }
}

@Suite("sagittalLean (specs/04, world)") struct SagittalLeanTests {
    private let lean = MetricDefinition.sagittalLean(lm(.nose), lm(.leftHip))

    @Test func frontViewPositiveWhenTheHeadGoesBackAwayFromTheCamera() {
        // an evader leaning forward (toward the camera) is negative
        let forward = value(lean, evaderFrame(EvaderParams(kneeAngle: 180, torsoLean: 20), evaderFront))
        let upright = value(lean, evaderFrame(EvaderParams(kneeAngle: 180), evaderFront))
        #expect(forward < upright - 0.1)
        // move the head straight back (away from the camera, +z)
        var f = evaderFrame(EvaderParams(kneeAngle: 180), evaderFront)
        f.world[LandmarkName.nose.index].z += 0.3
        #expect(value(lean, f) > upright + 0.1)
    }

    @Test func sideViewUsesTheNoseSideAsFront() {
        let back = fighterFrame(FighterParams(torsoLean: 25), fighterSide)
        let upright = fighterFrame(FighterParams(), fighterSide)
        let side = MetricDefinition.sagittalLean(lm(.nose), .near(joint: "hip"))
        let near = chooseNearSide([back])
        #expect(value(side, back, near: near) > value(side, upright, near: near) + 0.2)
        // same sign as the image version in a side view (lengths differ: 3D vs image)
        let image = value(.sagittalLean2d(lm(.nose), .near(joint: "hip")), back, near: near)
        #expect(value(side, back, near: near) > 0 && image > 0)
    }

    @Test func mirroringSwapsSides() {
        let f = evaderFrame(EvaderParams(kneeAngle: 170, torsoLean: 15), evaderFront)
        let right = MetricDefinition.sagittalLean(lm(.nose), lm(.rightHip))
        #expect(close(value(lean, f), value(right, mirrorFrame(f)), 1e-9))
    }

    @Test func noWorldOrNoShoulderLineIsNaN() {
        let f = toVision19(evaderFrame(EvaderParams(), evaderFront), world: false)
        #expect(value(lean, f).isNaN)
        var g = evaderFrame(EvaderParams(), evaderFront)
        g.world[LandmarkName.rightShoulder.index] = g.world[LandmarkName.leftShoulder.index]
        #expect(value(lean, g).isNaN)
    }
}

@Suite("imageAspect in landmark sequences (specs/03)") struct ImageAspectSequenceTests {
    private func v2(_ extra: [String: JSONValue]) -> JSONValue {
        let point: JSONValue = ["x": 0.5, "y": 0.5, "z": 0, "visibility": 1]
        let landmarks = JSONValue.array(Array(repeating: point, count: 33))
        var o: JSONValue = ["formatVersion": 2, "skeleton": "mediapipe33", "exerciseId": "squat", "source": "synthetic",
                            "view": "side", "fps": 30, "frames": [["t": 0, "image": landmarks, "world": landmarks]]]
        for (k, v) in extra { o[k] = v }
        return o
    }

    @Test func requiredInV2AndCopiedIntoFrames() throws {
        let seq = try LandmarkSequence.parse(v2(["imageAspect": 0.5625])).get()
        #expect(seq.imageAspect == 0.5625)
        #expect(seq.frames[0].imageAspect == 0.5625)
        guard case .failure(let e) = LandmarkSequence.parse(v2([:])) else { Issue.record("accepted"); return }
        #expect(e.issues.map(\.description).contains("imageAspect: imageAspect is required in formatVersion 2"))
        guard case .failure(let z) = LandmarkSequence.parse(v2(["imageAspect": 0])) else { Issue.record("accepted"); return }
        #expect(z.issues.map(\.description).contains("imageAspect: must be positive"))
    }

    @Test func notAllowedInV1() {
        var json = v2(["imageAspect": 1])
        json["formatVersion"] = 1
        json["skeleton"] = nil
        guard case .failure = LandmarkSequence.parse(json) else { Issue.record("accepted"); return }
    }
}

@Suite("toVision19 (specs/03)") struct ToVision19Tests {
    @Test func dropsMissingJointsAndProxiesTheWorldNose() {
        let f = evaderFrame(EvaderParams(slip: 10), evaderFront)
        let v = toVision19(f)
        for n in Skeleton.vision19Missing {
            #expect(v[image: n].isMissing && v[world: n].isMissing, "\(n)")
        }
        for n in Skeleton.vision19Landmarks {
            #expect(!v[image: n].isMissing, "\(n)")
        }
        #expect(v[world: .leftEar].isMissing && v[world: .rightEye].isMissing)
        let le = f[world: .leftEar], re = f[world: .rightEar]
        #expect(close(v[world: .nose].x, (le.x + re.x) / 2) && close(v[world: .nose].z, (le.z + re.z) / 2))
        #expect(v[world: .nose].visibility == f[image: .nose].visibility)
        #expect(v[world: .leftHip] == f[world: .leftHip])
    }

    @Test func withoutWorldEveryWorldPointIsMissing() {
        let v = toVision19(evaderFrame(EvaderParams(), evaderFront), world: false)
        #expect(v.world.allSatisfy { $0.isMissing })
    }

    @Test func sequenceBecomesV2Vision19AndLoadsTheVisionTemplates() {
        let seq = toVision19(squatSequence(view: .front, reps: [squatRep(kneeAngle: 90)]), world: false)
        #expect(seq.formatVersion == 2 && seq.skeleton == .vision19 && !seq.hasWorld)
        // 2D-only metrics still work on the reduced frames
        let knee = MetricDefinition.angle2d(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle))
        #expect(!value(knee, seq.frames[0]).isNaN)
        #expect(value(.angle(lm(.leftHip), lm(.leftKnee), lm(.leftAnkle)), seq.frames[0]).isNaN)
    }
}
