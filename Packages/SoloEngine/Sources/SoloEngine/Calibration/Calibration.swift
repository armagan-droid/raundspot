// Pilot calibration metrics (ref 09 "Pilot ölçütleri"; source
// `calibration/evaluate.ts`, commit c2fe3fd). Replays labeled landmark
// sequences through the engine and compares the results with the labels.

public struct PredictedAttempt: Sendable, Equatable {
    public var outcome: RepOutcome
    public var faults: [String]
}

public struct AttemptComparison: Sendable, Equatable {
    public var index: Int
    public var predicted: PredictedAttempt?
    public var label: RepLabel?
}

public struct CueComparison: Sendable, Equatable {
    /// Attempt the cue belongs to (the attempt in progress or just completed).
    public var attempt: Int
    public var faultId: String
    public var correct: Bool
}

public struct SequenceEvaluation: Sendable, Equatable {
    public var exerciseId: String
    public var attempts: [AttemptComparison]
    public var cues: [CueComparison]
    /// Reps counted in strict mode (valid only).
    public var labeledCount: Int
    public var predictedCount: Int
}

public struct FaultStats: Sendable, Equatable {
    public var hits = 0
    public var misses = 0
    public var falseAlarms = 0

    public init(hits: Int = 0, misses: Int = 0, falseAlarms: Int = 0) {
        self.hits = hits
        self.misses = misses
        self.falseAlarms = falseAlarms
    }
}

public struct CalibrationSummary: Sendable, Equatable {
    public var sequences: Int
    public var attempts: Int
    /// Mean over sequences (sets) of 1 − |counted − labeled| / labeled.
    public var countAccuracy: Double
    /// Cues for faults not in the label / all cues (0 when there were no cues).
    public var falseAlarmRate: Double
    public var faults: [String: FaultStats]
    /// ref 09 targets: ≥ 95 % counting, ≤ 10 % false alarms.
    public var meetsTargets: Bool
}

public enum CalibrationError: Error, Sendable, Equatable, CustomStringConvertible {
    case noLabels
    case invalidRulePack(String)
    case noParameter(String)
    case noFault(String)
    case noThreshold(String)

    public var description: String {
        switch self {
        case .noLabels: "sequence has no labels"
        case .invalidRulePack(let message): message
        case .noParameter(let path): "no numeric parameter '\(path)'"
        case .noFault(let id): "no fault '\(id)'"
        case .noThreshold(let id): "fault '\(id)' has no threshold"
        }
    }
}

public enum Calibration {
    public static let countTarget = 0.95
    public static let falseAlarmTarget = 0.1

    /// Replays one labeled sequence (safety pause off). The template must
    /// load for the sequence's skeleton and 3D availability (specs/03).
    public static func evaluate(_ rulePack: JSONValue, _ seq: LandmarkSequence) throws(CalibrationError) -> SequenceEvaluation {
        guard let labels = seq.labels else { throw .noLabels }
        let capabilities = PoseCapabilities(skeleton: seq.skeleton, worldAvailable: seq.hasWorld)
        let loaded: LoadedRulePack
        switch RulePackLoader.load(rulePack, capabilities: capabilities) {
        case .success(let l): loaded = l
        case .failure(let issues): throw .invalidRulePack(issues.description)
        }
        let view: View = seq.view == .front ? .front : .side
        let engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: view, nearSide: chooseNearSide(Array(seq.frames.prefix(30)))),
                                    options: ExerciseEngineOptions(safetyPause: false))
        var predicted: [PredictedAttempt] = []
        var cues: [(attempt: Int, faultId: String)] = []
        for frame in seq.frames {
            for e in engine.push(frame) {
                switch e.event {
                case .repCompleted(let outcome, let faults, _): predicted.append(PredictedAttempt(outcome: outcome, faults: faults))
                case .faultDetected(let id): cues.append((predicted.count, id))
                default: break
                }
            }
        }
        let reps = labels
        let n = Swift.max(predicted.count, reps.count)
        return SequenceEvaluation(
            exerciseId: seq.exerciseId,
            attempts: (0..<n).map {
                AttemptComparison(index: $0, predicted: $0 < predicted.count ? predicted[$0] : nil, label: $0 < reps.count ? reps[$0] : nil)
            },
            cues: cues.map { c in
                CueComparison(attempt: c.attempt, faultId: c.faultId,
                              correct: c.attempt < reps.count && reps[c.attempt].faults.contains(c.faultId))
            },
            labeledCount: reps.count { $0.outcome == .valid },
            predictedCount: predicted.count { $0.outcome == .valid })
    }

    public static func summarize(_ evals: [SequenceEvaluation]) -> CalibrationSummary {
        let perSet = evals.map { e -> Double in
            if e.labeledCount == 0 { return e.predictedCount == 0 ? 1 : 0 }
            return Swift.max(0, 1 - Double(Swift.abs(e.predictedCount - e.labeledCount)) / Double(e.labeledCount))
        }
        let cues = evals.flatMap(\.cues)
        var faults: [String: FaultStats] = [:]
        for e in evals {
            for a in e.attempts {
                let labeled = Set(a.label?.faults ?? []), predicted = Set(a.predicted?.faults ?? [])
                for id in labeled {
                    if predicted.contains(id) { faults[id, default: FaultStats()].hits += 1 } else { faults[id, default: FaultStats()].misses += 1 }
                }
                for id in predicted where !labeled.contains(id) { faults[id, default: FaultStats()].falseAlarms += 1 }
            }
        }
        let countAccuracy = perSet.isEmpty ? 0 : perSet.reduce(0, +) / Double(perSet.count)
        let falseAlarmRate = cues.isEmpty ? 0 : Double(cues.count { !$0.correct }) / Double(cues.count)
        return CalibrationSummary(
            sequences: evals.count, attempts: evals.reduce(0) { $0 + $1.attempts.count },
            countAccuracy: countAccuracy, falseAlarmRate: falseAlarmRate, faults: faults,
            meetsTargets: countAccuracy >= countTarget && falseAlarmRate <= falseAlarmTarget)
    }

    /// A copy of a rule pack with one parameter changed: `rep.<…>` (or any
    /// numeric field path) sets a number; `faults.<id>.threshold` replaces the
    /// last number in that fault's check expression (ref 09 sweep paths).
    public static func withParameter(_ rulePack: JSONValue, path: String, value: Double) throws(CalibrationError) -> JSONValue {
        var pack = rulePack
        let parts = path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3, parts[0] == "faults", parts[2] == "threshold" {
            let id = parts[1]
            guard let faults = pack["faults"]?.arrayValue,
                  let i = faults.firstIndex(where: { $0["id"]?.stringValue == id }),
                  let check = faults[i]["check"]?.stringValue else { throw .noFault(id) }
            guard let range = lastNumber(in: check) else { throw .noThreshold(id) }
            var chars = Array(check.utf16)
            chars.replaceSubrange(range, with: Array(jsNumberString(value).utf16))
            pack["faults"]![i]!["check"] = .string(String(decoding: chars, as: UTF16.self))
            return pack
        }
        func set(_ node: inout JSONValue, _ rest: ArraySlice<String>) -> Bool {
            guard let key = rest.first else { return false }
            if rest.count == 1 {
                guard node[key]?.numberValue != nil else { return false }
                node[key] = .number(value)
                return true
            }
            guard var child = node[key], child.objectValue != nil else { return false }
            let ok = set(&child, rest.dropFirst())
            if ok { node[key] = child }
            return ok
        }
        guard set(&pack, parts[...]) else { throw .noParameter(path) }
        return pack
    }

    public enum SweepResult: Sendable, Equatable {
        case summary(CalibrationSummary)
        /// The candidate made the rule pack invalid (first three message lines).
        case error(String)
    }

    /// Candidate values that make the rule pack invalid are reported, not thrown.
    public static func sweep(_ rulePack: JSONValue, _ sequences: [LandmarkSequence], path: String,
                             values: [Double]) throws(CalibrationError) -> [(value: Double, result: SweepResult)] {
        var rows: [(Double, SweepResult)] = []
        for value in values {
            let pack = try withParameter(rulePack, path: path, value: value)
            do {
                var evals: [SequenceEvaluation] = []
                for s in sequences { evals.append(try evaluate(pack, s)) }
                rows.append((value, .summary(summarize(evals))))
            } catch {
                let lines = error.description.split(separator: "\n", omittingEmptySubsequences: false).prefix(3)
                rows.append((value, .error(lines.joined(separator: " "))))
            }
        }
        return rows
    }

    /// UTF-16 range of the last match of `-?\d+(\.\d+)?` (the source regex).
    static func lastNumber(in s: String) -> Range<Int>? {
        let c = Array(s.utf16)
        func isDigit(_ i: Int) -> Bool { i < c.count && c[i] >= 0x30 && c[i] <= 0x39 }
        var last: Range<Int>?
        var i = 0
        while i < c.count {
            var j = i
            if c[j] == 0x2D { j += 1 }  // "-"
            guard isDigit(j) else { i += 1; continue }
            while isDigit(j) { j += 1 }
            if j < c.count, c[j] == 0x2E, isDigit(j + 1) {  // ".\d"
                j += 1
                while isDigit(j) { j += 1 }
            }
            last = i..<j
            i = j
        }
        return last
    }

    /// JavaScript `String(number)` for the values a sweep uses.
    public static func jsNumberString(_ x: Double) -> String {
        if x == x.rounded(), Swift.abs(x) < 1e21 { return String(Int64(x)) }
        return "\(x)"
    }
}
