import Foundation
import Testing
@testable import SoloCalibrateKit
import SoloEngine
import SoloEngineTesting

// `solo-calibrate suggest` (specs/03 "Şablon önerisi", AC-3.8): rep thresholds from labeled recordings.

private let sourceExercises = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("exercises/source", isDirectory: true)

private let valid = RepLabel(outcome: .valid, faults: [])
private let incomplete = RepLabel(outcome: .incomplete, faults: [])

/// A squat set: knee angle at the bottom, duration and label per attempt; rest at 172°.
private func squats(_ reps: [(Double, Double, RepLabel)], seed: Int) -> LandmarkSequence {
    var s = squatSequence(view: .front, reps: reps.map { squatRep(kneeAngle: $0.0, durationMs: $0.1, label: $0.2) },
                          options: SequenceOptions(noise: 0.002, seed: seed, leadInMs: 3000, restMs: 1200))
    s.source = .calibration
    return s
}

/// The source squat with a deliberately wrong draft `rep` (same direction: the angle goes down).
private func draft() throws -> JSONValue {
    var pack = try JSONValue.parse(contentsOf: sourceExercises.appendingPathComponent("squat.json"))
    pack["rep"]!["start"] = ["enter": 165, "exit": 163]
    pack["rep"]!["target"] = ["enter": 80, "exit": 82]  // deeper than anyone goes: the draft counts nothing
    pack["rep"]!["attemptMinExcursion"] = 1
    pack["rep"]!["minDurationMs"] = 100
    pack["rep"]!["maxDurationMs"] = 20000
    return pack
}

private func tempDirectory(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("suggest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (name, content) in files { try Data(content.utf8).write(to: root.appendingPathComponent(name)) }
    return root
}

@Suite struct SuggestTests {
    let sets = [
        squats([(92, 1800, valid), (140, 1500, incomplete), (95, 2200, valid), (90, 2000, valid)], seed: 5),
        squats([(94, 1600, valid), (88, 2400, valid), (138, 1400, incomplete)], seed: 6),
    ]

    @Test func suggestsThresholdsThatCountEveryValidAttempt() throws {
        let pack = try draft()
        let s = try Suggest.suggest(pack: pack, sequences: sets)
        #expect(s.used == 2 && s.unmatched.isEmpty)
        // rest ≈ 172°, weakest valid ≈ 95°, strongest incomplete ≈ 138°: the target sits between them
        #expect(abs(s.rest - 172) < 2)
        #expect(s.rep.target.enter < 138 && s.rep.target.enter > 95)
        #expect(s.rep.start.enter > s.rep.start.exit && s.rep.start.exit > s.rep.target.exit && s.rep.target.exit > s.rep.target.enter)
        #expect(s.rep.minDurationMs >= 100 && s.rep.minDurationMs < 1600 && s.rep.maxDurationMs > 2400)
        #expect(s.warnings.isEmpty, "\(s.warnings)")
        // the suggestion counts every valid attempt; the draft does not
        #expect(s.suggested.countAccuracy == 1, "\(s.suggested)")
        #expect(s.draft.countAccuracy < 1)
    }

    @Test func aSequenceWhoseLabelsDoNotMatchIsLeftOut() throws {
        var wrong = squats([(92, 1800, valid), (93, 1800, valid)], seed: 7)
        wrong.labels = [valid, valid, valid]  // three labels, two attempts
        let s = try Suggest.suggest(pack: draft(), sequences: sets + [wrong])
        #expect(s.used == 2 && s.unmatched == [2])
    }

    @Test func withoutValidAttemptsThereIsNoSuggestion() throws {
        let only = squats([(140, 1500, incomplete)], seed: 8)
        #expect(throws: SuggestError.self) { try Suggest.suggest(pack: draft(), sequences: [only]) }
    }

    @Test func cliWritesAValidatedCopyWithTheNextVersion() throws {
        let rules = try tempDirectory(["squat.json": draft().serialized()])
        let files = try tempDirectory(Dictionary(uniqueKeysWithValues: sets.enumerated().map { ("s\($0.offset).json", $0.element.json.serialized()) }))
        // under `source/`: the source squat has no `howTo`, which only `source/` files may lack
        let out = rules.appendingPathComponent("out/source/squat.json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines: [String] = []
        let code = CLI.run(["suggest", "--files", files.path, "--rules", rules.path, "--exercise", "squat", "--out", out.path]) { lines.append($0) }
        let text = lines.joined(separator: "\n")
        #expect(code == 0, "\(text)")
        #expect(text.contains("# Şablon önerisi: squat"))
        #expect(text.contains("| Sayım doğruluğu |"))
        #expect(text.contains("\"target\""))
        let written = try JSONValue.parse(contentsOf: out)
        #expect(written["version"]?.numberValue == (try draft())["version"]!.numberValue! + 1)
        #expect(written["status"]?.stringValue == "draft")
        let v = try Validator.validate(directory: out.deletingLastPathComponent().deletingLastPathComponent())
        #expect(v.isValid, "\(v.errors)")
        // the draft itself is untouched
        #expect(try JSONValue.parse(contentsOf: rules.appendingPathComponent("squat.json")) == (try draft()))
    }
}
