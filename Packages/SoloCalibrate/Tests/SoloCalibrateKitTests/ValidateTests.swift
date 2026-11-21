import Foundation
import Testing
@testable import SoloCalibrateKit

@Suite struct ValidateTests {
    private func makeDirectory(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("solo-calibrate-\(UUID().uuidString)", isDirectory: true)
        for (name, content) in files {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    @Test func acceptsWellFormedJsonRecursively() throws {
        let dir = try makeDirectory(["a.json": "{\"id\": \"a\"}", "source/b.json": "[1, 2]", "notes.txt": "x"])
        let report = try Validator.validate(directory: dir)
        #expect(report.isValid)
        #expect(report.checkedFiles == ["a.json", "source/b.json"])
    }

    @Test func reportsMalformedJson() throws {
        let dir = try makeDirectory(["bad.json": "{\"id\": "])
        let report = try Validator.validate(directory: dir)
        #expect(!report.isValid)
        #expect(report.errors.count == 1)
        #expect(report.errors[0].hasPrefix("bad.json"))
    }

    @Test func exitCodes() throws {
        let good = try makeDirectory(["a.json": "{}"])
        let bad = try makeDirectory(["a.json": "{"])
        var lines: [String] = []
        #expect(CLI.run(["validate", good.path]) { lines.append($0) } == 0)
        #expect(CLI.run(["validate", bad.path]) { lines.append($0) } == 1)
        #expect(CLI.run(["validate", "/nonexistent-\(UUID().uuidString)"]) { lines.append($0) } == 2)
        #expect(CLI.run([]) { lines.append($0) } == 2)
        #expect(CLI.run(["report", "--files", good.path]) { lines.append($0) } == 2)
    }
}
