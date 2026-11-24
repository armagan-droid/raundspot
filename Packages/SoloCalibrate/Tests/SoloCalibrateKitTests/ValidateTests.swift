import Foundation
import Testing
@testable import SoloCalibrateKit

@Suite struct ValidateTests {
    static let repoExercises = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("exercises")

    static var squat: String {
        get throws { try String(contentsOf: repoExercises.appendingPathComponent("source/squat.json"), encoding: .utf8) }
    }

    private func makeDirectory(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("solo-calibrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (name, content) in files {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    @Test func repositoryExercisesAreValid() throws {
        let report = try Validator.validate(directory: Self.repoExercises)
        #expect(report.errors == [])
        #expect(report.checkedFiles.contains("source/squat.json"))
    }

    @Test func sourceTemplateMayOmitHowTo() throws {
        let dir = try makeDirectory(["source/squat.json": try Self.squat])
        #expect(try Validator.validate(directory: dir).isValid)
    }

    @Test func projectTemplateNeedsHowTo() throws {
        let dir = try makeDirectory(["squat.json": try Self.squat])
        let report = try Validator.validate(directory: dir)
        #expect(report.errors.count == 1)
        #expect(report.errors[0].contains("howTo"))
    }

    @Test func fileNameMustMatchId() throws {
        let dir = try makeDirectory(["source/lunge.json": try Self.squat])
        let report = try Validator.validate(directory: dir)
        #expect(report.errors == ["source/lunge.json: id 'squat' does not match the file name"])
    }

    @Test func schemaAndExpressionIssuesAreReported() throws {
        let broken = try Self.squat.replacingOccurrences(of: "\"readyPose\": \"", with: "\"readyPose\": \"nope > 1 and ")
        let dir = try makeDirectory(["source/squat.json": broken, "source/bad.json": "{\"id\": "])
        let report = try Validator.validate(directory: dir)
        #expect(report.errors.contains { $0.hasPrefix("source/squat.json: readyPose: unknown metric 'nope'") })
        #expect(report.errors.contains { $0.hasPrefix("source/bad.json: ") })
    }

    @Test func demosAreChecked() throws {
        let demo = try String(contentsOf: Self.repoExercises.appendingPathComponent("demos/squat.json"), encoding: .utf8)
        let ok = try makeDirectory(["source/squat.json": try Self.squat, "demos/squat.json": demo])
        #expect(try Validator.validate(directory: ok).errors == ["demos/squat.json: no template 'squat' in exercises/"])
        let renamed = try makeDirectory(["demos/lunge.json": demo])
        #expect(try Validator.validate(directory: renamed).errors.contains("demos/lunge.json: exercise 'squat' does not match the file name"))
        let broken = try makeDirectory(["demos/squat.json": "{\"formatVersion\": 2}"])
        #expect(try Validator.validate(directory: broken).errors == ["demos/squat.json: formatVersion must be 1"])
    }

    /// specs/05 "Seviye kaydı ve doğrulama": schema, file name = id, templates and the combo gap (AC-5.6).
    @Test func reflexCatalogsAreChecked() throws {
        let catalog = try String(contentsOf: Self.repoExercises.appendingPathComponent("reflex/muay_thai.json"), encoding: .utf8)
        let template = { (id: String) in try String(contentsOf: Self.repoExercises.appendingPathComponent("\(id).json"), encoding: .utf8) }
        var files: [String: String] = ["reflex/muay_thai.json": catalog]
        for id in ["slip_left", "slip_right", "duck", "bob_weave_left", "bob_weave_right"] { files["\(id).json"] = try template(id) }
        #expect(try Validator.validate(directory: makeDirectory(files)).errors == [])

        var noDuck = files
        noDuck["duck.json"] = nil
        #expect(try Validator.validate(directory: makeDirectory(noDuck)).errors
            == ["reflex/muay_thai.json: responses.2: no front-view template 'duck' in exercises/"])

        var short = files
        short["reflex/muay_thai.json"] = catalog.replacingOccurrences(of: "\"comboGapMs\": 450", with: "\"comboGapMs\": 100")
        #expect(try Validator.validate(directory: makeDirectory(short)).errors.contains { $0.hasPrefix("reflex/muay_thai.json: levels.5.comboGapMs") })

        let renamed = try makeDirectory(["reflex/kick.json": catalog])
        #expect(try Validator.validate(directory: renamed).errors.contains("reflex/kick.json: id 'muay_thai' does not match the file name"))
        let broken = try makeDirectory(["reflex/muay_thai.json": "{\"id\": 1}"])
        #expect(try Validator.validate(directory: broken).errors.contains { $0.hasPrefix("reflex/muay_thai.json: ") })
    }

    @Test func aWorkoutsReflexCatalogMustExist() throws {
        let w = #"{"formatVersion": 1, "id": "w", "name": {"tr": "a", "en": "b"}, "sport": "muay_thai", "estimatedMinutes": 5, "blocks": [{"type": "reflex", "catalogId": "boxing", "level": 1, "restSec": 0}]}"#
        let errors = try Validator.validate(directory: makeDirectory(["workouts/w.json": w])).errors
        #expect(errors == ["workouts/w.json: blocks[0].catalogId: no catalog 'boxing' in exercises/reflex/ (specs/06)"])
    }

    @Test func workoutsAreChecked() throws {
        let w = #"{"formatVersion": 1, "id": "w", "name": {"tr": "a", "en": "b"}, "sport": "muay_thai", "estimatedMinutes": 5, "blocks": [{"type": "technique", "exerciseId": "nope", "sets": 1, "reps": 5, "restSec": 0}]}"#
        let dir = try makeDirectory(["workouts/w.json": w, "workouts/bad.json": "{\"formatVersion\": 1}"])
        let errors = try Validator.validate(directory: dir).errors
        #expect(errors.contains("workouts/w.json: blocks[0].exerciseId: no template 'nope' in exercises/ (specs/06 AC-6.5)"))
        #expect(errors.contains { $0.hasPrefix("workouts/bad.json: id") })
    }

    @Test func stepDemosAreChecked() throws {
        let demo = try String(contentsOf: Self.repoExercises.appendingPathComponent("demos/steps/warmup.shadow.json"), encoding: .utf8)
        let template = try String(contentsOf: Self.repoExercises.appendingPathComponent("demos/squat.json"), encoding: .utf8)
        let dir = try makeDirectory(["demos/steps/warmup.shadow.json": demo, "demos/steps/x.json": demo, "demos/steps/squat.json": template])
        let errors = try Validator.validate(directory: dir).errors
        #expect(errors.sorted() == ["demos/steps/squat.json: a step demo needs step, not exercise",
                                    "demos/steps/x.json: step 'warmup.shadow' does not match the file name"])
    }

    @Test func unknownFileKindsAreErrors() throws {
        let dir = try makeDirectory(["programs/week.json": "{}"])
        let report = try Validator.validate(directory: dir)
        #expect(report.errors == ["programs/week.json: no validator for this file kind yet"])
    }

    @Test func exitCodes() throws {
        let good = try makeDirectory(["source/squat.json": try Self.squat])
        let bad = try makeDirectory(["source/squat.json": "{"])
        var lines: [String] = []
        #expect(CLI.run(["validate", good.path]) { lines.append($0) } == 0)
        #expect(CLI.run(["validate", bad.path]) { lines.append($0) } == 1)
        #expect(CLI.run(["validate", "/nonexistent-\(UUID().uuidString)"]) { lines.append($0) } == 2)
        #expect(CLI.run([]) { lines.append($0) } == 2)
        #expect(CLI.run(["report", "--files", good.path]) { lines.append($0) } == 2)
    }
}
