import Foundation
import Testing
@testable import SoloCalibrateKit
import SoloEngine
import SoloEngineTesting

// `solo-calibrate report` end to end (T2.9): files on disk → markdown report.

private let sourceExercises = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("exercises/source", isDirectory: true)

private func tempDirectory(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("solo-calibrate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (name, content) in files { try Data(content.utf8).write(to: root.appendingPathComponent(name)) }
    return root
}

private func squatRecording(_ reps: [(Double, RepLabel)], seed: Int = 3) -> String {
    var s = squatSequence(view: .front, reps: reps.map { squatRep(kneeAngle: $0.0, label: $0.1) },
                          options: SequenceOptions(noise: 0.002, seed: seed, leadInMs: 5000))
    s.source = .calibration
    return s.json.serialized()
}

private let valid = RepLabel(outcome: .valid, faults: [])
private let shallow = RepLabel(outcome: .faulty, faults: ["insufficient_depth"])

private func run(_ args: [String]) -> (code: Int32, out: String) {
    var lines: [String] = []
    let code = CLI.run(args) { lines.append($0) }
    return (code, lines.joined(separator: "\n"))
}

@Suite struct ReportTests {
    @Test func reportsCountAccuracyFalseAlarmsAndPerFaultCounts() throws {
        let dir = try tempDirectory([
            "a.json": squatRecording([(90, valid), (120, shallow), (92, valid)]),
            "b.json": squatRecording([(90, valid)], seed: 4),
        ])
        let (code, out) = run(["report", "--files", dir.path, "--rules", sourceExercises.path])
        #expect(code == 0, "\(out)")
        #expect(out.contains("## squat"))
        #expect(out.contains("- Kayıt: 2, deneme: 4"))
        #expect(out.contains("- Sayım doğruluğu: 100.0% (hedef ≥ 95%)"))
        #expect(out.contains("- Yanlış alarm oranı: 0.0% (hedef ≤ 10%)"))
        #expect(out.contains("- Pilot hedefleri: karşılanıyor"))
        #expect(out.contains("| insufficient_depth | 1 | 0 | 0 |"))
    }

    @Test func sweepAddsOneRowPerValueAndReportsInvalidCandidates() throws {
        let dir = try tempDirectory(["a.json": squatRecording([(90, valid), (120, shallow)])])
        let (code, out) = run(["report", "--files", dir.path, "--rules", sourceExercises.path, "--sweep", "rep.target.enter=100,140"])
        #expect(code == 0, "\(out)")
        #expect(out.contains("### Tarama: `rep.target.enter`"))
        #expect(out.contains("| 100 | 100.0% | 0.0% | ✓ |"))
        #expect(out.contains("| 140 | – | – | geçersiz: invalid rule pack:"))
    }

    @Test func exerciseFilterAndSequencesWithoutLabelsOrPacks() throws {
        var unlabeled = squatSequence(view: .front, reps: [squatRep(kneeAngle: 90)])
        unlabeled.labels = nil
        var unknown = squatSequence(view: .front, reps: [squatRep(kneeAngle: 90, label: valid)])
        unknown.exerciseId = "no_such_pack"
        let dir = try tempDirectory([
            "a.json": squatRecording([(90, valid)]),
            "b.json": unlabeled.json.serialized(),
            "c.json": unknown.json.serialized(),
        ])
        let all = run(["report", "--files", dir.path, "--rules", sourceExercises.path])
        #expect(all.code == 0)
        #expect(all.out.contains("- Kayıt: 1, deneme: 1"))  // only the labeled squat
        #expect(!all.out.contains("no_such_pack"))
        let none = run(["report", "--files", dir.path, "--rules", sourceExercises.path, "--exercise", "pushup"])
        #expect(none.out == "# Kalibrasyon raporu\n")
    }

    @Test func errors() throws {
        let dir = try tempDirectory(["bad.json": #"{"formatVersion": 3}"#])
        let bad = run(["report", "--files", dir.path, "--rules", sourceExercises.path])
        #expect(bad.code == 1)
        #expect(bad.out.hasPrefix("error: bad.json: invalid landmark sequence"))
        #expect(run(["report"]).code == 2)
        #expect(run(["report", "--files"]).code == 2)
        #expect(run(["report", "--files", "/nonexistent-dir"]).code == 2)
        let good = try tempDirectory(["a.json": squatRecording([(90, valid)])])
        let sweep = run(["report", "--files", good.path, "--rules", sourceExercises.path, "--sweep", "rep.target.enter"])
        #expect(sweep.code == 1 && sweep.out.contains("bad --sweep"))
        let path = run(["report", "--files", good.path, "--rules", sourceExercises.path, "--sweep", "rep.nothing=1"])
        #expect(path.code == 1 && path.out == "error: no numeric parameter 'rep.nothing'")
    }

    @Test func sweepSpecParsing() throws {
        let s = try Report.parseSweep("faults.knee_valgus.threshold=0.1, 0.15,0.2")
        #expect(s.path == "faults.knee_valgus.threshold" && s.values == [0.1, 0.15, 0.2])
        #expect(throws: ReportError.self) { try Report.parseSweep("=1") }
        #expect(throws: ReportError.self) { try Report.parseSweep("a=1,,2") }
        #expect(throws: ReportError.self) { try Report.parseSweep("a=x") }
    }
}
