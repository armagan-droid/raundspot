import Foundation
import SoloEngine

// `solo-calibrate suggest` (specs/03 "Şablon önerisi", T2.10): the `rep` numbers of a template from labeled
// recordings. Only a suggestion: the draft file is never changed; `--out` writes a copy.

public enum SuggestError: Error, Equatable, CustomStringConvertible {
    case invalidRulePack(String)
    case noLabeledSequences
    case noValidAttempt

    public var description: String {
        switch self {
        case .invalidRulePack(let m): "invalid rule pack: \(m)"
        case .noLabeledSequences: "no labeled sequence of this exercise matched its labels"
        case .noValidAttempt: "no valid attempt to suggest from"
        }
    }
}

/// A suggested `rep` block, in the metric's units.
public struct SuggestedRep: Sendable, Equatable {
    public struct Zone: Sendable, Equatable {
        public var enter: Double
        public var exit: Double
    }

    public var metric: String
    public var start: Zone
    public var target: Zone
    public var attemptMinExcursion: Double
    public var minDurationMs: Int
    public var maxDurationMs: Int

    public var json: JSONValue {
        var o: JSONValue = ["metric": .string(metric)]
        o["start"] = ["enter": .number(start.enter), "exit": .number(start.exit)]
        o["target"] = ["enter": .number(target.enter), "exit": .number(target.exit)]
        o["attemptMinExcursion"] = .number(attemptMinExcursion)
        o["minDurationMs"] = .number(Double(minDurationMs))
        o["maxDurationMs"] = .number(Double(maxDurationMs))
        return o
    }
}

public struct SuggestResult: Sendable {
    public var exerciseId: String
    public var rep: SuggestedRep
    /// Rest level, noise and the weakest valid depth, in the metric's units.
    public var rest: Double
    public var noise: Double
    public var depth: Double
    /// Sequences used, and the indices of those whose attempts did not match their labels.
    public var used: Int
    public var unmatched: [Int]
    public var attempts: [RepOutcome: Int]
    public var warnings: [String]
    public var draft: CalibrationSummary
    public var suggested: CalibrationSummary
    /// The template with the suggested `rep`, `version` + 1, still `draft`.
    public var pack: JSONValue
}

public enum Suggest {
    // Depth fractions of the weakest valid attempt (specs/03 table).
    static let startEnter = 0.20, startExit = 0.30, excursion = 0.15, targetExit = 0.70, targetEnter = 0.80

    /// One sequence's rep metric as the engine sees it (smoothed), in "toward the target" orientation.
    struct Series {
        var t: [Double] = []
        var x: [Double] = []
    }

    static func series(_ loaded: LoadedRulePack, _ seq: LandmarkSequence, orientation: Double) -> Series {
        let view: View = seq.view == .front ? .front : .side
        let engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: view, nearSide: chooseNearSide(Array(seq.frames.prefix(30)))),
                                    options: ExerciseEngineOptions(safetyPause: false))
        var s = Series()
        for f in seq.frames {
            _ = engine.push(f)
            guard let v = engine.metrics[loaded.pack.rep.metric], !v.isNaN else { continue }
            s.t.append(f.t)
            s.x.append(orientation * v)
        }
        return s
    }

    static func quantile(_ a: [Double], _ q: Double) -> Double {
        let s = a.sorted()
        guard !s.isEmpty else { return .nan }
        return s[min(s.count - 1, max(0, Int((Double(s.count - 1) * q).rounded())))]
    }

    static func median(_ a: [Double]) -> Double {
        let s = a.sorted()
        guard !s.isEmpty else { return .nan }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func noise(_ x: [Double]) -> [Double] { zip(x.dropFirst(), x).map { abs($0 - $1) } }

    /// `count` peaks, separated by a dip to half the smaller one; nil when there are fewer.
    static func peaks(_ x: [Double], count: Int, sigma: Double) -> [Int]? {
        guard x.count > 2, count > 0 else { return count == 0 ? [] : nil }
        let ref = quantile(x, 0.2)
        let deepest = x.max()! - ref
        let minDepth = max(6 * sigma, 0.1 * deepest)
        var candidates: [Int] = []
        for i in 1..<(x.count - 1) where x[i] >= x[i - 1] && x[i] > x[i + 1] && x[i] - ref >= minDepth { candidates.append(i) }
        candidates.sort { x[$0] > x[$1] }
        var accepted: [Int] = []
        for c in candidates {
            let separated = accepted.allSatisfy { a in
                let lo = min(a, c), hi = max(a, c)
                return x[lo...hi].min()! <= ref + 0.5 * (min(x[a], x[c]) - ref)
            }
            if separated { accepted.append(c) }
            if accepted.count == count { break }
        }
        return accepted.count == count ? accepted.sorted() : nil
    }

    public static func suggest(pack: JSONValue, sequences: [LandmarkSequence]) throws -> SuggestResult {
        guard let first = sequences.first else { throw SuggestError.noLabeledSequences }
        let caps = PoseCapabilities(skeleton: first.skeleton, worldAvailable: first.hasWorld)
        let loaded: LoadedRulePack
        switch RulePackLoader.load(pack, capabilities: caps) {
        case .success(let l): loaded = l
        case .failure(let issues): throw SuggestError.invalidRulePack(issues.description)
        }
        let rep = loaded.pack.rep
        // + when the metric grows toward the target
        let orientation: Double = rep.target.enter > rep.start.enter ? 1 : -1

        struct Matched { var seq: LandmarkSequence; var s: Series; var peaks: [Int]; var labels: [RepLabel] }
        var matched: [Matched] = []
        var unmatched: [Int] = []
        var diffs: [Double] = []
        for (i, seq) in sequences.enumerated() {
            guard let labels = seq.labels else { unmatched.append(i); continue }
            let s = series(loaded, seq, orientation: orientation)
            let d = noise(s.x)
            let sigma = median(d) * 1.4826 / 2.0.squareRoot()
            guard let p = peaks(s.x, count: labels.count, sigma: sigma.isNaN ? 0 : sigma) else { unmatched.append(i); continue }
            diffs += d
            matched.append(Matched(seq: seq, s: s, peaks: p, labels: labels))
        }
        guard !matched.isEmpty else { throw SuggestError.noLabeledSequences }
        let sigma = median(diffs) * 1.4826 / 2.0.squareRoot()

        // rest: the lowest values between (and around) the attempts
        var valleys: [Double] = []
        for m in matched {
            let bounds = [0] + m.peaks + [m.s.x.count - 1]
            for (a, b) in zip(bounds, bounds.dropFirst()) where b > a { valleys.append(m.s.x[a...b].min()!) }
        }
        let rest = median(valleys)
        var validDepths: [Double] = [], incompleteDepths: [Double] = []
        var counts: [RepOutcome: Int] = [:]
        for m in matched {
            for (p, l) in zip(m.peaks, m.labels) {
                counts[l.outcome, default: 0] += 1
                if l.outcome == .valid { validDepths.append(m.s.x[p] - rest) }
                if l.outcome == .incomplete { incompleteDepths.append(m.s.x[p] - rest) }
            }
        }
        guard let depth = validDepths.min(), depth > 0 else { throw SuggestError.noValidAttempt }

        var te = targetEnter * depth, tx = targetExit * depth
        if let inc = incompleteDepths.max() {
            te = min(max((inc + depth) / 2, 0.45 * depth), 0.95 * depth)
            tx = te - 0.10 * depth
        }
        let step = pow(10, floor(log10(depth)) - 2)
        func round(_ v: Double) -> Double { ((v / step).rounded() * step * 1e9).rounded() / 1e9 }
        func value(_ d: Double) -> Double { round(orientation * (rest + d)) }

        // durations of the valid attempts with the suggested start zone
        let seX = orientation * value(startEnter * depth), sxX = orientation * value(startExit * depth)
        var durations: [Double] = []
        for m in matched {
            for (p, l) in zip(m.peaks, m.labels) where l.outcome == .valid {
                var a = p
                while a > 0, m.s.x[a - 1] >= sxX { a -= 1 }
                var b = p
                while b < m.s.x.count - 1, m.s.x[b] > seX { b += 1 }
                durations.append(m.s.t[b] - m.s.t[a])
            }
        }
        let minMs = max(100, Int((0.6 * durations.min()! / 50).rounded(.down)) * 50)
        let maxMs = Int((1.5 * durations.max()! / 100).rounded(.up)) * 100

        let suggested = SuggestedRep(metric: rep.metric,
                                     start: .init(enter: value(startEnter * depth), exit: value(startExit * depth)),
                                     target: .init(enter: value(te), exit: value(tx)),
                                     attemptMinExcursion: round(excursion * depth), minDurationMs: minMs, maxDurationMs: maxMs)

        var warnings: [String] = []
        if (startExit - startEnter) * depth < 3 * sigma {
            warnings.append("hysteresis \(Calibration.jsNumberString(round((startExit - startEnter) * depth))) is under 3σ: the movement is small for its noise")
        }
        if valleys.contains(where: { $0 - rest > startEnter * depth }) {
            warnings.append("between attempts the metric does not always come back to start.enter")
        }
        if let inc = incompleteDepths.max(), inc >= depth {
            warnings.append("an incomplete attempt goes deeper than the weakest valid one: the rep metric cannot tell them apart")
        }

        var out = pack
        out["rep"] = suggested.json
        out["version"] = .number((pack["version"]?.numberValue ?? 0) + 1)
        out["status"] = "draft"
        let seqs = matched.map(\.seq)
        let draftSummary = try Calibration.summarize(seqs.map { s throws(CalibrationError) in try Calibration.evaluate(pack, s) })
        let suggestedSummary = try Calibration.summarize(seqs.map { s throws(CalibrationError) in try Calibration.evaluate(out, s) })
        return SuggestResult(exerciseId: loaded.pack.id, rep: suggested, rest: orientation * rest, noise: sigma, depth: depth,
                             used: matched.count, unmatched: unmatched, attempts: counts, warnings: warnings,
                             draft: draftSummary, suggested: suggestedSummary, pack: out)
    }

    /// Markdown report.
    public static func format(_ r: SuggestResult) -> String {
        func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
        func n(_ x: Double) -> String { Calibration.jsNumberString((x * 1e4).rounded() / 1e4) }
        var lines = ["# Şablon önerisi: \(r.exerciseId)", ""]
        lines.append("- Kayıt: \(r.used) (etiketle eşleşmeyen: \(r.unmatched.count))")
        lines.append("- Deneme: " + RepOutcome.allCases.map { "\($0.rawValue) \(r.attempts[$0] ?? 0)" }.joined(separator: ", "))
        lines.append("- Dinlenme: \(n(r.rest)), gürültü σ: \(n(r.noise)), en zayıf geçerli derinlik D: \(n(r.depth))")
        lines += ["", "```json", "\"rep\": " + r.rep.json.serialized(indent: 2), "```", ""]
        lines += ["| | Taslak | Öneri |", "|---|---|---|"]
        lines.append("| Sayım doğruluğu | \(pct(r.draft.countAccuracy)) | \(pct(r.suggested.countAccuracy)) |")
        lines.append("| Yanlış alarm | \(pct(r.draft.falseAlarmRate)) | \(pct(r.suggested.falseAlarmRate)) |")
        lines.append("| Pilot hedefleri | \(r.draft.meetsTargets ? "✓" : "✗") | \(r.suggested.meetsTargets ? "✓" : "✗") |")
        if !r.warnings.isEmpty { lines += ["", "## Uyarılar", ""] + r.warnings.map { "- \($0)" } }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func run(files: URL, rules: URL, exercise: String, out: URL?) throws -> String {
        let packURL = rules.appendingPathComponent("\(exercise).json")
        let pack = try JSONValue.parse(contentsOf: packURL)
        let seqs = try Report.loadSequences(files).filter { $0.exerciseId == exercise && $0.labels != nil }
        let r = try suggest(pack: pack, sequences: seqs)
        if let out {
            guard out.standardizedFileURL != packURL.standardizedFileURL else { throw CalibrateError.usage("--out must not be the draft itself") }
            try Data((r.pack.serialized(indent: 2) + "\n").utf8).write(to: out, options: .atomic)
        }
        return format(r)
    }
}
