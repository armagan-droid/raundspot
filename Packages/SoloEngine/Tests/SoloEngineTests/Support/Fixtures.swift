import Foundation
@testable import SoloEngine

/// Repository paths for tests (works on macOS and Linux).
enum Repo {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Support
        .deletingLastPathComponent()  // SoloEngineTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SoloEngine
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root

    static let exercises = root.appendingPathComponent("exercises")
    static let sourceExercises = exercises.appendingPathComponent("source")

    static func jsonFiles(in dir: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { dir.appendingPathComponent($0) }
    }

    static func read(_ url: URL) throws -> JSONValue {
        try JSONValue.parse(contentsOf: url)
    }

    /// The source squat template, the base of the schema tests (as in the source repo).
    static func squat() throws -> JSONValue {
        try read(sourceExercises.appendingPathComponent("squat.json"))
    }
}

/// "path: message" strings, like the source test helper `issuesOf`.
func issuesOf(_ json: JSONValue) -> [String] {
    switch RulePackParser.parse(json) {
    case .success: []
    case .failure(let e): e.issues.map(\.description)
    }
}

func loadIssues(_ json: JSONValue, capabilities: PoseCapabilities? = nil) -> [SchemaIssue] {
    switch RulePackLoader.load(json, capabilities: capabilities) {
    case .success: []
    case .failure(let e): e.issues
    }
}

/// Some issue contains both fragments (source `expectInvalid`).
func hasIssue(_ json: JSONValue, _ pathFragment: String, _ messageFragment: String = "") -> Bool {
    // Swift's `contains("")` is false (JavaScript's `includes("")` is true).
    func has(_ s: String, _ fragment: String) -> Bool { fragment.isEmpty || s.contains(fragment) }
    return issuesOf(json).contains { has($0, pathFragment) && has($0, messageFragment) }
}
