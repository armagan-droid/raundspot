import Foundation
import Testing
import SoloEngine
@testable import SoloPose

// AC-3.6 synthetic part: Vision → Frame keeps the y axis and left/right, and
// a slip to the person's left on an unmirrored front-camera frame gives a
// positive `lateralLean2d`.

/// A person facing the camera in Vision coordinates (origin bottom-left). On an
/// unmirrored front-camera image the person's left is on the image's right.
private func facingPose(headShift: Double = 0, confidence: Double = 0.9) -> DetectedPose {
    func j(_ x: Double, _ y: Double) -> DetectedJoint { DetectedJoint(x: x, y: y, confidence: confidence) }
    let joints: [VisionJoint: DetectedJoint] = [
        .nose: j(0.5 + headShift, 0.85), .leftEye: j(0.52 + headShift, 0.87), .rightEye: j(0.48 + headShift, 0.87),
        .leftEar: j(0.54 + headShift, 0.86), .rightEar: j(0.46 + headShift, 0.86), .neck: j(0.5, 0.78),
        .leftShoulder: j(0.58, 0.76), .rightShoulder: j(0.42, 0.76),
        .leftElbow: j(0.6, 0.66), .rightElbow: j(0.4, 0.66), .leftWrist: j(0.55, 0.78), .rightWrist: j(0.45, 0.78),
        .root: j(0.5, 0.5), .leftHip: j(0.55, 0.5), .rightHip: j(0.45, 0.5),
        .leftKnee: j(0.55, 0.3), .rightKnee: j(0.45, 0.3), .leftAnkle: j(0.55, 0.1), .rightAnkle: j(0.45, 0.1),
    ]
    return DetectedPose(confidence: 0.8, joints: joints)
}

private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardized

private func pack(_ id: String) throws -> LoadedRulePack {
    let data = try Data(contentsOf: repo.appendingPathComponent("exercises/\(id).json"))
    return try RulePackLoader.load(data: data, capabilities: .vision19TwoD).get()
}

@Suite("Vision → Frame (specs/03)") struct FrameMapperTests {
    @Test func flipsYAndKeepsSides() {
        let f = FrameMapper.frame(facingPose(), t: 40, imageAspect: 16.0 / 9)
        #expect(f.t == 40 && f.imageAspect == 16.0 / 9)
        #expect(f[image: .nose].y < f[image: .leftHip].y && f[image: .leftHip].y < f[image: .leftAnkle].y)
        #expect(abs(f[image: .nose].y - 0.15) < 1e-12)
        #expect(f[image: .leftShoulder].x == 0.58 && f[image: .rightShoulder].x == 0.42)
        #expect(f[image: .leftShoulder].visibility == 0.9)
    }

    @Test func missingAndUndetectedJoints() {
        var pose = facingPose()
        pose.joints[.leftKnee] = nil
        pose.joints[.rightKnee] = DetectedJoint(x: 0.4, y: 0.3, confidence: 0)
        let f = FrameMapper.frame(pose, t: 0, imageAspect: 1)
        #expect(f[image: .leftKnee].visibility == 0 && f[image: .rightKnee].visibility == 0)
        for name in Skeleton.vision19Missing { #expect(f[image: name] == .missing) }
        #expect(f.world.allSatisfy { $0 == .missing })
        let present = LandmarkName.allCases.filter { f[image: $0].visibility > 0 }
        #expect(Set(present) == Skeleton.vision19Landmarks.subtracting([.leftKnee, .rightKnee]))
    }

    @Test func candidatesAreTheTwoMostConfident() {
        var a = facingPose(), b = facingPose(), c = facingPose()
        a.confidence = 0.3; b.confidence = 0.9; c.confidence = 0.6
        b.joints[.nose]!.x = 0.1
        let frames = FrameMapper.candidates([a, b, c], t: 0, imageAspect: 1)
        #expect(frames.count == 2)
        #expect(frames[0][image: .nose].x == 0.1)
    }

    @Test func slipToThePersonsLeftIsPositiveOnTheFrontCamera() throws {
        let loaded = try pack("slip_left")
        func headLeft(_ shift: Double) -> Double {
            let engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: .front, nearSide: .left))
            _ = engine.push(FrameMapper.frame(facingPose(headShift: shift), t: 0, imageAspect: 1))
            return engine.metrics["head_left"]!
        }
        #expect(headLeft(0.08) > 0.2)
        #expect(headLeft(-0.08) < -0.2)
        #expect(abs(headLeft(0)) < 0.02)
    }

    @Test func rotationAndAspect() {
        #expect(UprightRotation(degrees: 90) == .r90)
        #expect(UprightRotation(degrees: 269) == .r270)
        #expect(UprightRotation(degrees: 360) == .r0)
        #expect(UprightRotation(degrees: -90) == .r270)
        #expect(UprightRotation.r0.uprightAspect(width: 1280, height: 720) == 1280.0 / 720)
        #expect(UprightRotation.r90.uprightAspect(width: 1280, height: 720) == 720.0 / 1280)
    }
}
