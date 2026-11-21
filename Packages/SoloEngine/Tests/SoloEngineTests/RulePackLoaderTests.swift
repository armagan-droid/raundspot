import Foundation
import Testing
@testable import SoloEngine

// Port of the source `engine/test/load-rule-pack.test.ts` (commit c2fe3fd),
// plus skeleton capability checks (specs/03 AC-3.5).

@Suite("AC-4.1 (expression part): every exercise loads") struct ExerciseLoadTests {
    static let files = Repo.jsonFiles(in: Repo.sourceExercises) + Repo.jsonFiles(in: Repo.exercises)

    @Test(arguments: files) func loads(_ file: URL) throws {
        #expect(loadIssues(try Repo.read(file)).map(\.description) == [])
    }
}

@Suite("RulePackLoader") struct RulePackLoaderTests {
    @Test func compilesFaultChecksAndReadyPose() throws {
        let loaded = try RulePackLoader.load(try Repo.squat()).get()
        #expect(loaded.readyPose.durationMs == 1500)
        let depth = loaded.faults.first { $0.fault.id == "insufficient_depth" }
        #expect(depth?.position == .atTurn)
        guard case .compare(.greater, _, _) = depth?.expr else {
            Issue.record("expected a '>' comparison"); return
        }
        #expect(loaded.pack.id == "squat")
    }

    @Test func undefinedMetricInAFaultCheckIsRejectedWithItsPath() throws {
        var p = try Repo.squat()
        p["faults"]![1]!["check"] = "during_rep: knee_valgus > 0.15"
        let issues = loadIssues(p)
        #expect(issues.contains { $0.path == "faults.1.check" && $0.message.contains("knee_valgus") && $0.code == .expression })
    }

    @Test func undefinedMetricInReadyPoseIsRejected() throws {
        var p = try Repo.squat()
        p["readyPose"] = "knee_angle > 165 for 1500ms"
        #expect(loadIssues(p).contains { $0.path == "readyPose" && $0.message.contains("knee_angle") })
    }

    @Test func chainHeightTakes2To6Landmarks() throws {
        let cases: [([JSONValue], Bool)] = [
            (["nose"], false),
            (["nose", "left_ankle"], true),
            (["nose", "left_shoulder", "left_hip", "left_knee", "left_ankle", "left_heel", "left_foot_index"], false),
        ]
        for (chain, ok) in cases {
            var p = try Repo.squat()
            p["metrics"]!["h"] = ["chainHeight": .array(chain)]
            #expect(loadIssues(p).isEmpty == ok, "\(chain)")
        }
    }

    @Test func schemaIssuesAreReportedBeforeExpressionParsing() throws {
        var p = try Repo.squat()
        p["hysteresis"] = [:]
        p["readyPose"] = "nope > 1 for 1ms"
        let issues = loadIssues(p)
        #expect(issues.contains { $0.description.contains("hysteresis") })
        #expect(!issues.contains { $0.code == .expression })
    }

    @Test func allExpressionIssuesAreListed() throws {
        var p = try Repo.squat()
        p["faults"]![0]!["check"] = "at_turn: nope > 1"
        p["faults"]![1]!["check"] = "during_rep: eval(1) > 1"
        guard case .failure(let error) = RulePackLoader.load(p) else {
            Issue.record("expected failure"); return
        }
        #expect(error.issues.count == 2)
        #expect(error.description.hasPrefix("invalid rule pack:\n"))
    }

    @Test func invalidJSONDataIsAnIssue() {
        guard case .failure(let error) = RulePackLoader.load(data: Data("{".utf8)) else {
            Issue.record("expected failure"); return
        }
        #expect(error.issues.count == 1)
    }
}

@Suite("AC-3.5: skeleton capabilities") struct CapabilityTests {
    @Test func mediapipe33AcceptsEverySourceTemplate() throws {
        for file in Repo.jsonFiles(in: Repo.sourceExercises) {
            #expect(loadIssues(try Repo.read(file), capabilities: .mediapipe33).isEmpty, "\(file.lastPathComponent)")
        }
    }

    @Test func missingLandmarkIsUnsupportedLandmark() throws {
        var p = try Repo.squat()
        p["metrics"]!["toe"] = ["diffY": ["left_foot_index", "left_ankle"]]
        let issues = loadIssues(p, capabilities: PoseCapabilities(skeleton: .vision19, worldAvailable: true))
        #expect(issues.contains { $0.code == .unsupportedLandmark && $0.path == "metrics.toe" && $0.message.contains("left_foot_index") })
        #expect(loadIssues(p, capabilities: .mediapipe33).isEmpty)
    }

    @Test func nearFarNeedBothSidesInTheSkeleton() throws {
        var p = try Repo.squat()
        p["metrics"]!["heel"] = ["diffY": ["near_heel", "near_ankle"]]
        let issues = loadIssues(p, capabilities: PoseCapabilities(skeleton: .vision19, worldAvailable: true))
        let issue = issues.first { $0.path == "metrics.heel" }
        #expect(issue?.code == .unsupportedLandmark)
        #expect(issue?.message.contains("left_heel, right_heel") == true)
    }

    @Test func minVisibleLandmarksAreChecked() throws {
        var p = try Repo.squat()
        p["camera"]!["minVisibleLandmarks"]!.append("right_thumb")
        let issues = loadIssues(p, capabilities: PoseCapabilities(skeleton: .vision19, worldAvailable: true))
        #expect(issues.contains { $0.path == "camera.minVisibleLandmarks" && $0.code == .unsupportedLandmark })
    }

    @Test func worldMetricsAreRejectedWithout3D() throws {
        // The source squat uses `angle` (world).
        let issues = loadIssues(try Repo.squat(), capabilities: .vision19TwoD)
        #expect(!issues.isEmpty)
        #expect(issues.allSatisfy { $0.code == .worldUnavailable })
        #expect(loadIssues(try Repo.squat(), capabilities: PoseCapabilities(skeleton: .vision19, worldAvailable: true)).isEmpty)
    }

    @Test func imageOnlyTemplateLoadsInH2() throws {
        // Source teep uses 2D functions only (specs/03 "Etkilenen şablonlar").
        let teep = try Repo.read(Repo.sourceExercises.appendingPathComponent("teep.json"))
        #expect(loadIssues(teep, capabilities: .vision19TwoD).isEmpty)
    }

    @Test func vision19HasSeventeenMediaPipeLandmarks() {
        #expect(Skeleton.vision19Landmarks.count == 17)
        #expect(Skeleton.vision19Missing.count == 16)
        #expect(Skeleton.mediapipe33.landmarks.count == 33)
    }
}

@Suite("Landmarks") struct LandmarkTests {
    @Test func mediaPipeOrder() {
        #expect(LandmarkName.allCases.count == 33)
        #expect(LandmarkName.nose.index == 0)
        #expect(LandmarkName.leftShoulder.index == 11)
        #expect(LandmarkName.leftHip.index == 23)
        #expect(LandmarkName.rightFootIndex.index == 32)
    }

    @Test func nearFarResolution() {
        #expect(LandmarkRef("near_hip")?.resolve(near: .left) == .leftHip)
        #expect(LandmarkRef("far_hip")?.resolve(near: .left) == .rightHip)
        #expect(LandmarkRef("near_foot_index")?.resolve(near: .right) == .rightFootIndex)
        #expect(LandmarkRef("near_nose") == nil)
        #expect(LandmarkRef("near_eye_inner")?.resolve(near: .right) == .rightEyeInner)
        #expect(LandmarkRef.bilateralJoints.count == 15)  // mouth_left/right do not follow the left_/right_ pattern
    }
}
