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

    @Test func unknownFileKindsAreErrors() throws {
        let dir = try makeDirectory(["reflex/muay_thai.json": "{}"])
        let report = try Validator.validate(directory: dir)
        #expect(report.errors == ["reflex/muay_thai.json: no validator for this file kind yet"])
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
