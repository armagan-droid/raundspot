import Foundation
import Testing
@testable import SoloEngine

// Port of the source `shared/test/rule-pack.test.ts` (commit c2fe3fd), plus
// specs/04 additions. The base document is exercises/source/squat.json.

@Suite("AC-4.1: exercises conform to the rule pack schema") struct ExerciseFilesTests {
    static let files = Repo.jsonFiles(in: Repo.sourceExercises) + Repo.jsonFiles(in: Repo.exercises)

    @Test func ruleFilesExist() {
        #expect(Repo.jsonFiles(in: Repo.sourceExercises).count == 11)
    }

    @Test(arguments: files) func isValid(_ file: URL) throws {
        #expect(issuesOf(try Repo.read(file)) == [])
    }

    @Test(arguments: files) func fileNameMatchesId(_ file: URL) throws {
        let pack = try RulePackParser.parse(try Repo.read(file)).get()
        #expect(pack.id == file.deletingPathExtension().lastPathComponent)
    }
}

@Suite("Unknown fields are rejected") struct UnknownFieldTests {
    @Test func topLevel() throws {
        var p = try Repo.squat()
        p["hysteresis"] = ["upEnter": 160]
        #expect(hasIssue(p, "", "hysteresis"))
    }

    @Test func insideAFault() throws {
        var p = try Repo.squat()
        p["faults"]![0]!["priority"] = 1
        #expect(hasIssue(p, "faults.0"))
    }

    @Test func insideRepZones() throws {
        var p = try Repo.squat()
        p["rep"]!["start"]!["middle"] = 155
        #expect(hasIssue(p, "rep.start"))
    }
}

@Suite("Metric references") struct MetricReferenceTests {
    @Test func repMetricMustBeDefined() throws {
        var p = try Repo.squat()
        p["rep"]!["metric"] = "hip_angle"
        #expect(hasIssue(p, "rep.metric", "hip_angle"))
    }

    @Test func maxMustReferenceDefinedMetrics() throws {
        var p = try Repo.squat()
        p["metrics"]!["m"] = ["max": ["knee_angle_near", "nope"]]
        #expect(hasIssue(p, "metrics.m", "nope"))
        p["metrics"]!["m"] = ["max": ["knee_angle_near", "torso_lean"]]
        #expect(try RulePackParser.parse(p).get().metric(named: "m") == .max("knee_angle_near", "torso_lean"))
    }

    @Test func avgMustReferenceDefinedMetrics() throws {
        var p = try Repo.squat()
        p["metrics"]!["knee_angle_avg"] = ["avg": ["knee_angle_l", "knee_angle_x"]]
        #expect(hasIssue(p, "metrics.knee_angle_avg", "knee_angle_x"))
    }

    @Test func minMustReferenceDefinedMetrics() throws {
        var p = try Repo.squat()
        p["metrics"]!["m"] = ["min": ["knee_angle_near", "nope"]]
        #expect(hasIssue(p, "metrics.m", "nope"))
    }

    @Test func metricValuedFunctionRejectsLandmarkArguments() throws {
        var p = try Repo.squat()
        p["metrics"]!["knee_angle_avg"] = ["avg": ["left_knee", "right_knee"]]
        #expect(hasIssue(p, "metrics.knee_angle_avg"))
    }

    @Test func cyclicMetricsAreRejected() throws {
        var p = try Repo.squat()
        p["metrics"]!["a"] = ["avg": ["b", "knee_angle_l"]]
        p["metrics"]!["b"] = ["absDiff": ["a", "knee_angle_r"]]
        #expect(hasIssue(p, "metrics", "cycle"))
        #expect(issuesOf(p).contains("metrics.a: metric cycle: a -> b -> a"))
    }

    @Test func reservedWordsAreRejected() throws {
        var p = try Repo.squat()
        p["metrics"]!["and"] = ["angle": ["left_hip", "left_knee", "left_ankle"]]
        #expect(hasIssue(p, "metrics.and", "reserved"))
    }

    @Test func selfReferenceIsRejected() throws {
        var p = try Repo.squat()
        p["metrics"]!["a"] = ["avg": ["a", "knee_angle_l"]]
        #expect(hasIssue(p, "metrics", "cycle"))
    }

    @Test func metricOrderIsFileOrder() throws {
        let pack = try RulePackParser.parse(try Repo.squat()).get()
        let raw = try Repo.squat()["metrics"]!.objectValue!.keys
        #expect(pack.metricNames == raw)
    }
}

@Suite("Metric functions (closed list)") struct MetricFunctionTests {
    @Test func unknownFunctionIsRejected() throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = ["distance": ["left_hip", "left_knee"]]
        #expect(hasIssue(p, "metrics.x"))
    }

    @Test func exactlyOneFunctionPerMetric() throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = ["angle": ["left_hip", "left_knee", "left_ankle"], "diffY": ["left_hip", "left_knee"]]
        #expect(hasIssue(p, "metrics.x"))
    }

    @Test func arityIsEnforced() throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = ["angle": ["left_hip", "left_knee"]]
        #expect(hasIssue(p, "metrics.x"))
    }

    @Test func unknownLandmarkIsRejected() throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = ["diffY": ["left_hip", "left_kneecap"]]
        #expect(hasIssue(p, "metrics.x"))
    }

    @Test func nearFarOnlyExistForBilateralLandmarks() throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = ["diffY": ["near_nose", "near_hip"]]
        #expect(hasIssue(p, "metrics.x"))
    }

    @Test func nearFarOfBilateralLandmarksAreAccepted() throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = ["signedOffset": ["near_shoulder", "far_hip", "near_foot_index"]]
        #expect(issuesOf(p) == [])
    }

    @Test func leadRearAreNotAcceptedInMVP() throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = ["diffY": ["lead_knee", "lead_hip"]]
        #expect(hasIssue(p, "metrics.x"))
    }

    @Test func minVisibleLandmarksMustBeLandmarks() throws {
        var p = try Repo.squat()
        p["camera"]!["minVisibleLandmarks"]!.append("knee_angle_l")
        #expect(hasIssue(p, "camera.minVisibleLandmarks"))
    }

    /// specs/04 "Yeni metrik fonksiyonları".
    @Test(arguments: [
        ("min", ["knee_angle_near", "torso_lean"] as [JSONValue]),
        ("angle2d", ["left_hip", "left_knee", "left_ankle"]),
        ("lateralLean2d", ["nose", "left_hip"]),
        ("chainHeight2d", ["nose", "left_shoulder", "left_hip", "left_knee", "left_ankle"]),
        ("sagittalLean", ["nose", "left_hip"]),
        ("sagittalLean2d", ["nose", "near_hip"]),
        ("heightOverShoulders2d", ["nose", "left_ankle"]),
    ])
    func projectFunctionsAreAccepted(_ fn: String, _ args: [JSONValue]) throws {
        var p = try Repo.squat()
        p["metrics"]!["x"] = .object(JSONObject([(fn, .array(args))]))
        #expect(issuesOf(p) == [])
    }

    @Test func projectFunctionArityIsEnforced() throws {
        for (fn, args) in [("angle2d", ["left_hip", "left_knee"]), ("lateralLean2d", ["nose"]),
                           ("chainHeight2d", ["nose"]), ("sagittalLean2d", ["nose", "left_hip", "left_knee"]),
                           ("heightOverShoulders2d", ["nose"])] {
            var p = try Repo.squat()
            p["metrics"]!["x"] = .object(JSONObject([(fn, .array(args.map { .string($0) }))]))
            #expect(hasIssue(p, "metrics.x"), "\(fn)")
        }
    }

    @Test func worldFunctionsAreMarked() {
        let world = MetricDefinition.functions.map(\.name).filter { name in
            switch name {
            case "angle", "lateralLean", "chainHeight", "sagittalLean": true
            default: false
            }
        }
        #expect(world == ["angle", "lateralLean", "chainHeight", "sagittalLean"])
        #expect(MetricDefinition.angle(.landmark(.leftHip), .landmark(.leftKnee), .landmark(.leftAnkle)).usesWorld)
        #expect(!MetricDefinition.angle2d(.landmark(.leftHip), .landmark(.leftKnee), .landmark(.leftAnkle)).usesWorld)
        #expect(MetricDefinition.sagittalLean(.landmark(.nose), .landmark(.leftHip)).usesWorld)
        #expect(!MetricDefinition.sagittalLean2d(.landmark(.nose), .landmark(.leftHip)).usesWorld)
    }
}

@Suite("Rep zones (hysteresis)") struct RepZoneTests {
    @Test func decreasingStartExitMustBeBelowEnter() throws {
        var p = try Repo.squat()
        p["rep"]!["start"] = ["enter": 160, "exit": 170]
        #expect(hasIssue(p, "rep.start"))
    }

    @Test func decreasingTargetExitMustBeAboveEnter() throws {
        var p = try Repo.squat()
        p["rep"]!["target"] = ["enter": 100, "exit": 90]
        #expect(hasIssue(p, "rep.target"))
    }

    @Test func zonesMustNotOverlap() throws {
        var p = try Repo.squat()
        p["rep"]!["target"] = ["enter": 100, "exit": 155]
        #expect(hasIssue(p, "rep", "overlap"))
    }

    @Test func increasingMovementIsAcceptedWhenMirrored() throws {
        var p = try Repo.squat()
        p["rep"]!["start"] = ["enter": 95, "exit": 105]
        p["rep"]!["target"] = ["enter": 160, "exit": 150]
        p["readyPose"] = "knee_angle_avg < 100 for 1500ms"
        #expect(issuesOf(p) == [])
    }

    @Test func increasingStartExitMustBeAboveEnter() throws {
        var p = try Repo.squat()
        p["rep"]!["start"] = ["enter": 95, "exit": 90]
        p["rep"]!["target"] = ["enter": 160, "exit": 150]
        #expect(hasIssue(p, "rep.start"))
    }

    @Test func startEnterMustDifferFromTargetEnter() throws {
        var p = try Repo.squat()
        p["rep"]!["target"] = ["enter": 160, "exit": 165]
        #expect(hasIssue(p, "rep", "must differ"))
    }

    @Test func minDurationMustBeBelowMax() throws {
        var p = try Repo.squat()
        p["rep"]!["minDurationMs"] = 9000
        #expect(hasIssue(p, "rep", "maxDurationMs"))
    }

    @Test func durationsMustBeIntegers() throws {
        var p = try Repo.squat()
        p["rep"]!["minDurationMs"] = 250.5
        #expect(hasIssue(p, "rep.minDurationMs"))
    }
}

@Suite("Faults") struct FaultTests {
    @Test func defaultsAreApplied() throws {
        var p = try Repo.squat()
        let count = p["faults"]!.arrayValue!.count
        for i in 0..<count {
            p["faults"]![i]!["cooldownMs"] = nil
            p["faults"]![i]!["minConsecutiveReps"] = nil
        }
        p["camera"]!["minVisibility"] = nil
        p["camera"]!["posture"] = nil
        let parsed = try RulePackParser.parse(p).get()
        #expect(parsed.camera.minVisibility == 0.6)
        #expect(parsed.camera.posture == .standing)
        for f in parsed.faults {
            #expect(f.cooldownMs == 4000)
            #expect(f.minConsecutiveReps == 1)
        }
    }

    @Test func postureAcceptsStandingOrHorizontalOnly() throws {
        var p = try Repo.squat()
        p["camera"]!["posture"] = "horizontal"
        #expect(try RulePackParser.parse(p).get().camera.posture == .horizontal)
        p["camera"]!["posture"] = "sitting"
        #expect(hasIssue(p, "camera.posture"))
    }

    @Test func holdMsDefaultsTo150ForDuringRepOnly() throws {
        let parsed = try RulePackParser.parse(try Repo.squat()).get()
        #expect(parsed.faults.first { $0.id == "knee_valgus" }?.holdMs == 150)
        #expect(parsed.faults.first { $0.id == "insufficient_depth" }?.holdMs == nil)
    }

    @Test func holdMsIsRejectedOnNonDuringRepFaults() throws {
        var p = try Repo.squat()
        p["faults"]![0]!["holdMs"] = 200
        #expect(hasIssue(p, "faults.0.holdMs", "during_rep"))
    }

    @Test func checkMustStartWithAKnownPosition() throws {
        var p = try Repo.squat()
        p["faults"]![0]!["check"] = "at_phase_bottom: knee_angle_avg > 100"
        #expect(hasIssue(p, "faults.0.check"))
        p["faults"]![0]!["check"] = "at_turn:   "
        #expect(hasIssue(p, "faults.0.check"))
    }

    @Test func faultViewsMustBeASubsetOfCameraViews() throws {
        var p = try Repo.squat()
        p["camera"]!["views"] = ["front"]
        #expect(hasIssue(p, "faults.2.views", "side"))
    }

    @Test func faultIdsMustBeUnique() throws {
        var p = try Repo.squat()
        p["faults"]![1]!["id"] = p["faults"]![0]!["id"]
        #expect(hasIssue(p, "faults.1.id", "duplicate"))
    }

    @Test func faultsNeedALocalizedName() throws {
        var p = try Repo.squat()
        p["faults"]![0]!["name"] = nil
        #expect(hasIssue(p, "faults.0.name"))
    }

    @Test func cueNeedsBothTrAndEn() throws {
        var p = try Repo.squat()
        p["faults"]![0]!["cue"]!["en"] = nil
        #expect(hasIssue(p, "faults.0.cue"))
    }
}

@Suite("Top-level constraints") struct TopLevelTests {
    @Test func holdTypeIsRejectedInMVP() throws {
        var p = try Repo.squat()
        p["type"] = "hold"
        #expect(hasIssue(p, "type", "MVP"))
    }

    @Test func statusMustBeDraftOrCalibrated() throws {
        var p = try Repo.squat()
        p["status"] = "draft-thresholds-need-calibration"
        #expect(hasIssue(p, "status"))
    }

    @Test func readyPoseMustEndWithADuration() throws {
        var p = try Repo.squat()
        p["readyPose"] = "knee_angle_avg > 165"
        #expect(hasIssue(p, "readyPose"))
    }

    @Test func cameraViewsCannotBeEmptyOrAmbiguous() throws {
        var empty = try Repo.squat()
        empty["camera"]!["views"] = []
        #expect(hasIssue(empty, "camera.views"))
        var ambiguous = try Repo.squat()
        ambiguous["camera"]!["views"] = ["front", "ambiguous"]
        #expect(hasIssue(ambiguous, "camera.views"))
    }

    @Test func versionMustBeAPositiveInteger() throws {
        var p = try Repo.squat()
        p["version"] = 0
        #expect(hasIssue(p, "version"))
    }

    @Test func nullIsNotAnOmittedOptional() throws {
        var p = try Repo.squat()
        p["howTo"] = nil
        p["howTo"] = .null
        #expect(hasIssue(p, "howTo"))
    }
}

@Suite("specs/04 schema additions") struct ProjectSchemaTests {
    @Test func derivedFromIsAccepted() throws {
        var p = try Repo.squat()
        p["derivedFrom"] = ["id": "squat", "version": 1, "commit": "c2fe3fd"]
        #expect(try RulePackParser.parse(p).get().derivedFrom == DerivedFrom(id: "squat", version: 1, commit: "c2fe3fd"))
        p["derivedFrom"] = ["id": "squat", "version": 1]
        #expect(hasIssue(p, "derivedFrom.commit"))
        p["derivedFrom"] = ["id": "squat", "version": 1, "commit": "c2fe3fd", "extra": true]
        #expect(hasIssue(p, "derivedFrom", "extra"))
    }

    @Test func headTargetBackIsAccepted() throws {
        var p = try Repo.squat()
        p["overlay"] = ["headTarget": ["back": 0.3]]
        #expect(try RulePackParser.parse(p).get().overlay?.headTarget?.back == 0.3)
        p["overlay"] = ["headTarget": ["back": -0.3]]
        #expect(hasIssue(p, "overlay.headTarget.back"))
    }
}

/// Port of the A5 overlay cases in the source `load-rule-pack.test.ts`.
@Suite("Overlay head target") struct OverlayTests {
    @Test func emptyHeadTargetIsRejected() throws {
        var p = try Repo.squat()
        p["overlay"] = ["headTarget": [:]]
        #expect(!issuesOf(p).isEmpty)
        p["overlay"] = ["headTarget": ["height": 0.86]]
        #expect(issuesOf(p) == [])
        p["overlay"] = ["headTarget": ["lateral": 0.3, "sides": ["left"]]]
        #expect(issuesOf(p) == [])
    }

    @Test(arguments: [[] as [JSONValue], ["up"], ["left", "left"]])
    func badSidesAreRejected(_ sides: [JSONValue]) throws {
        var p = try Repo.squat()
        p["overlay"] = ["headTarget": ["lateral": 0.3, "sides": .array(sides)]]
        #expect(!issuesOf(p).isEmpty)
    }

    @Test func sidesOnlySteerALateralTarget() throws {
        var p = try Repo.squat()
        p["overlay"] = ["headTarget": ["height": 0.86, "sides": ["left"]]]
        #expect(!issuesOf(p).isEmpty)
    }
}

@Suite("JavaScript pattern semantics") struct JSRegexTests {
    @Test func readyPosePattern() {
        let ok = ["a > 1 for 1500ms", "x > 1 for  20ms", "(a > 1)\tfor\t5ms", "a for 1ms", "a\nfor 1ms"]
        let bad = ["a > 1 for 1500", "a > 1 for ms", "a > 1for 15ms", " a > 1 for 15ms", "a > 1 for 15ms ",
                   "for 1ms", "a\n> 1 for 1ms", "a > 1 for 1٣ms", "a > 1 for1ms"]
        for s in ok { #expect(JSRegex.matchesReadyPose(s), "\(s)") }
        for s in bad { #expect(!JSRegex.matchesReadyPose(s), "\(s)") }
    }

    @Test func checkPattern() {
        for s in ["at_turn: x > 1", "during_rep:x", "at_start:\u{00A0}\u{00A0}x"] { #expect(JSRegex.matchesCheck(s), "\(s)") }
        for s in ["at_turn:", "at_turn:  ", "at_turn : x", "turn: x", "x at_turn: x"] { #expect(!JSRegex.matchesCheck(s), "\(s)") }
    }
}
