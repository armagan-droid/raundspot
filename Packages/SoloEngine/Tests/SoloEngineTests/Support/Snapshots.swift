import Foundation
import Testing
@testable import SoloEngine

/// Snapshot cases under `fixtures/snapshots/` (specs/03 "Yeni davranış:
/// anlık görüntüler"). `UPDATE_SNAPSHOTS=1 swift test …` rewrites the
/// sequence and the expected outcome; otherwise the engine runs on the stored
/// sequence and must reproduce the stored outcome.
enum Snapshots {
    static let dir = Repo.root.appendingPathComponent("fixtures/snapshots", isDirectory: true)
    static var updating: Bool { ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] == "1" }

    struct Case {
        var name: String
        /// Repo-relative rule pack path.
        var rulePackFile: String
        var setup: ExerciseSetup
        var options = ExerciseEngineOptions()
        var cuesEnabled: [CueSwitch] = []
        /// Sequence file name (without `.json`) when several cases share one; default `name`.
        var sequenceName: String? = nil
        /// Used only when updating.
        var makeSequence: () -> LandmarkSequence
    }

    static func check(_ c: Case, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let caseURL = dir.appendingPathComponent("\(c.name).json")
        let sequencePath = "sequences/\(c.sequenceName ?? c.name).json"
        let sequenceURL = dir.appendingPathComponent(sequencePath)
        let packJSON = try JSONValue.parse(contentsOf: Repo.root.appendingPathComponent(c.rulePackFile))
        let loaded = try RulePackLoader.load(packJSON).get()

        if updating {
            // stored coordinates are rounded; the outcome is computed from what is stored
            // a shared sequence is written by its first case and reused as stored
            let seq = c.sequenceName != nil && c.sequenceName != c.name && FileManager.default.fileExists(atPath: sequenceURL.path)
                ? try LandmarkSequence.parse(data: Data(contentsOf: sequenceURL)).get()
                : rounded(c.makeSequence())
            let outcome = EngineCase.run(loaded, seq, setup: c.setup, options: c.options, cuesEnabled: c.cuesEnabled)
            let snapshot = EngineCase(
                origin: JSONObject([("generatedBy", .string(SoloEngine.generatedBy))]), rulePack: loaded.pack.id,
                rulePackVersion: loaded.pack.version, rulePackFile: c.rulePackFile, setup: c.setup, options: c.options,
                cuesEnabled: c.cuesEnabled, sequence: sequencePath, expected: outcome)
            try FileManager.default.createDirectory(at: sequenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((seq.json.serialized() + "\n").utf8).write(to: sequenceURL, options: .atomic)
            try Data((snapshot.json.serialized(indent: 1) + "\n").utf8).write(to: caseURL, options: .atomic)
            return
        }

        guard FileManager.default.fileExists(atPath: caseURL.path), FileManager.default.fileExists(atPath: sequenceURL.path) else {
            Issue.record("snapshot \(c.name) is missing: run UPDATE_SNAPSHOTS=1 swift test (with the spec change) and review the files",
                         sourceLocation: sourceLocation)
            return
        }
        let stored = try EngineCase(json: JSONValue.parse(contentsOf: caseURL))
        #expect(stored.rulePack == loaded.pack.id, sourceLocation: sourceLocation)
        #expect(stored.rulePackVersion == loaded.pack.version,
                "template \(c.rulePackFile) changed version: update the snapshot with its spec change", sourceLocation: sourceLocation)
        #expect(stored.setup == c.setup && stored.options == c.options && stored.cuesEnabled == c.cuesEnabled,
                sourceLocation: sourceLocation)
        let seq = try LandmarkSequence.parse(data: Data(contentsOf: sequenceURL)).get()
        let actual = EngineCase.run(loaded, seq, setup: stored.setup, options: stored.options, cuesEnabled: stored.cuesEnabled,
                                    metricsEvery: stored.expected.metricsEvery)
        let diff = EngineCase.differences(expected: stored.expected, actual: actual)
        #expect(diff.isEmpty, "snapshot \(c.name) differs:\n\(diff.joined(separator: "\n"))", sourceLocation: sourceLocation)
    }

    /// 5 decimals: 1e-5 of the picture or 10 µm, far below pose noise; keeps the files small.
    static func rounded(_ seq: LandmarkSequence) -> LandmarkSequence {
        func r(_ x: Double) -> Double { x.isFinite ? (x * 1e5).rounded() / 1e5 : x }
        func p(_ l: Landmark) -> Landmark { Landmark(x: r(l.x), y: r(l.y), z: r(l.z), visibility: r(l.visibility)) }
        var out = seq
        out.frames = seq.frames.map { f in
            var g = f
            g.image = f.image.map(p)
            g.world = f.world.map(p)
            return g
        }
        return out
    }
}
