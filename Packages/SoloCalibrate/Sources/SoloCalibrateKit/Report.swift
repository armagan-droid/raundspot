import Foundation
import SoloEngine

// `solo-calibrate report` (specs/03 "Kalibrasyon", ref 09 metrics; source
// `apps/api/src/cli/calibration-report.ts`, commit c2fe3fd): replays labeled
// recordings through the engine with the current rule packs.

public struct ReportOptions: Sendable, Equatable {
    /// Directory of landmark sequences (`*.json`, not recursive).
    public var files: URL
    /// Rule packs by file name (`<id>.json`); default `exercises`.
    public var rules: URL
    public var exercise: String?
    /// `<path>=<v1>,<v2>,…`
    public var sweep: String?

    public init(files: URL, rules: URL, exercise: String? = nil, sweep: String? = nil) {
        self.files = files
        self.rules = rules
        self.exercise = exercise
        self.sweep = sweep
    }
}

public struct ExerciseReport: Sendable, Equatable {
    public var exerciseId: String
    public var summary: CalibrationSummary
    public var sweepPath: String?
    public var sweep: [SweepRow]

    public struct SweepRow: Sendable, Equatable {
        public var value: Double
        public var result: Calibration.SweepResult
    }
}

public enum Report {
    /// Rule pack JSON by id (file name without `.json`), top level of `dir` only.
    public static func loadRulePacks(_ dir: URL) throws -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for url in try jsonFiles(dir) {
            out[url.deletingPathExtension().lastPathComponent] = try JSONValue.parse(contentsOf: url)
        }
        return out
    }

    public static func loadSequences(_ dir: URL) throws -> [LandmarkSequence] {
        try jsonFiles(dir).map { url in
            switch LandmarkSequence.parse(data: try Data(contentsOf: url)) {
            case .success(let s): return s
            case .failure(let issues): throw ReportError.invalidSequence(url.lastPathComponent, issues.description)
            }
        }
    }

    static func jsonFiles(_ dir: URL) throws -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            throw CalibrateError.notADirectory(dir.path)
        }
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".json") }.sorted()
            .map { dir.appendingPathComponent($0) }
    }

    /// Parses `<path>=<v1>,<v2>,…`.
    public static func parseSweep(_ spec: String) throws -> (path: String, values: [Double]) {
        let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else { throw ReportError.badSweep(spec) }
        let values = parts[1].split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil && $0!.isFinite }) else { throw ReportError.badSweep(spec) }
        return (parts[0], values.map { $0! })
    }

    /// Labeled sequences grouped by exercise, in first-seen order; exercises without a rule pack are skipped.
    public static func build(packs: [String: JSONValue], sequences: [LandmarkSequence], exercise: String? = nil,
                             sweep: String? = nil) throws -> [ExerciseReport] {
        var order: [String] = []
        var byExercise: [String: [LandmarkSequence]] = [:]
        for s in sequences where s.labels != nil && (exercise == nil || s.exerciseId == exercise) {
            if byExercise[s.exerciseId] == nil { order.append(s.exerciseId) }
            byExercise[s.exerciseId, default: []].append(s)
        }
        let parsedSweep = try sweep.map(parseSweep)
        var out: [ExerciseReport] = []
        for id in order {
            guard let pack = packs[id], let seqs = byExercise[id] else { continue }
            var evals: [SequenceEvaluation] = []
            for s in seqs { evals.append(try Calibration.evaluate(pack, s)) }
            var rows: [ExerciseReport.SweepRow] = []
            if let parsedSweep {
                rows = try Calibration.sweep(pack, seqs, path: parsedSweep.path, values: parsedSweep.values)
                    .map { ExerciseReport.SweepRow(value: $0.value, result: $0.result) }
            }
            out.append(ExerciseReport(exerciseId: id, summary: Calibration.summarize(evals), sweepPath: parsedSweep?.path, sweep: rows))
        }
        return out
    }

    public static func run(_ o: ReportOptions) throws -> String {
        format(try build(packs: loadRulePacks(o.rules), sequences: loadSequences(o.files), exercise: o.exercise, sweep: o.sweep))
    }

    static func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    static func number(_ x: Double) -> String { Calibration.jsNumberString(x) }

    /// Markdown, as the source report.
    public static func format(_ results: [ExerciseReport]) -> String {
        var lines = ["# Kalibrasyon raporu", ""]
        for r in results {
            let s = r.summary
            lines += ["## \(r.exerciseId)", ""]
            lines.append("- Kayıt: \(s.sequences), deneme: \(s.attempts)")
            lines.append("- Sayım doğruluğu: \(pct(s.countAccuracy)) (hedef ≥ 95%)")
            lines.append("- Yanlış alarm oranı: \(pct(s.falseAlarmRate)) (hedef ≤ 10%)")
            lines += ["- Pilot hedefleri: \(s.meetsTargets ? "karşılanıyor" : "KARŞILANMIYOR")", ""]
            lines += ["| Hata | İsabet | Kaçırma | Yanlış alarm |", "|---|---|---|---|"]
            for id in s.faults.keys.sorted() {
                let f = s.faults[id]!
                lines.append("| \(id) | \(f.hits) | \(f.misses) | \(f.falseAlarms) |")
            }
            if let path = r.sweepPath {
                lines += ["", "### Tarama: `\(path)`", "", "| Değer | Sayım | Yanlış alarm | Hedef |", "|---|---|---|---|"]
                for row in r.sweep {
                    switch row.result {
                    case .summary(let t):
                        lines.append("| \(number(row.value)) | \(pct(t.countAccuracy)) | \(pct(t.falseAlarmRate)) | \(t.meetsTargets ? "✓" : "✗") |")
                    case .error(let message):
                        lines.append("| \(number(row.value)) | – | – | geçersiz: \(message) |")
                    }
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

public enum ReportError: Error, Equatable, CustomStringConvertible {
    case invalidSequence(String, String)
    case badSweep(String)

    public var description: String {
        switch self {
        case .invalidSequence(let file, let message): "\(file): \(message)"
        case .badSweep(let spec): "bad --sweep '\(spec)': expected <path>=<v1>,<v2>,..."
        }
    }
}
