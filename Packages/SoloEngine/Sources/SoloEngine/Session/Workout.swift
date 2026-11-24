import Foundation

// Ready-made workouts (specs/06 "Hazır antrenman dosyası"): exercises/workouts/<id>.json.

public enum SetMode: String, Sendable, Equatable { case strict, lenient }

public struct GuidedStep: Sendable, Equatable {
    public var textKey: String
    public var durationSec: Int
    public var audioKey: String?

    public init(textKey: String, durationSec: Int, audioKey: String? = nil) {
        self.textKey = textKey
        self.durationSec = durationSec
        self.audioKey = audioKey
    }
}

public enum ReflexLevel: Sendable, Equatable {
    case fixed(Int)
    /// Picked by the user at the start (H3).
    case chosen
}

public enum Block: Sendable, Equatable {
    case warmup(steps: [GuidedStep])
    case technique(exerciseId: String, sets: Int, reps: Int, restSec: Int, mode: SetMode)
    case reflex(catalogId: String, level: ReflexLevel, cues: Int?, restSec: Int, sets: Int)
    case conditioning(exerciseId: String, sets: Int, reps: Int?, durationSec: Int?, restSec: Int, mode: SetMode)
    case guided(steps: [GuidedStep])

    public var usesCamera: Bool {
        switch self {
        case .warmup, .guided: false
        default: true
        }
    }

    public var exerciseId: String? {
        switch self {
        case .technique(let id, _, _, _, _), .conditioning(let id, _, _, _, _, _): id
        default: nil
        }
    }

    public var sets: Int {
        switch self {
        case .technique(_, let s, _, _, _), .conditioning(_, let s, _, _, _, _), .reflex(_, _, _, _, let s): s
        case .warmup, .guided: 1
        }
    }

    public var restSec: Int {
        switch self {
        case .technique(_, _, _, let r, _), .conditioning(_, _, _, _, let r, _), .reflex(_, _, _, let r, _): r
        case .warmup, .guided: 0
        }
    }

    public var steps: [GuidedStep] {
        switch self {
        case .warmup(let s), .guided(let s): s
        default: []
        }
    }
}

public struct Workout: Sendable, Equatable {
    public var id: String
    public var name: LocalizedText
    public var sport: String
    public var estimatedMinutes: Int
    public var blocks: [Block]
    /// Rest in seconds after a block's last set, by block index: the rest between circuit rounds (specs/06 "Devre").
    public var restAfterBlock: [Int: Int]
    /// Technique blocks the user picks at the start (specs/06 "Seçim"), in order; not in `blocks` until resolved.
    public var choices: [Choice]

    /// `count` eskivs from `from`, inserted as technique blocks at `position` of `blocks`.
    public struct Choice: Sendable, Equatable {
        public var position: Int
        public var from: [String]
        public var count: Int
        public var sets: Int
        public var reps: Int
        public var restSec: Int
        public var mode: SetMode

        public init(position: Int, from: [String], count: Int, sets: Int, reps: Int, restSec: Int, mode: SetMode) {
            self.position = position
            self.from = from
            self.count = count
            self.sets = sets
            self.reps = reps
            self.restSec = restSec
            self.mode = mode
        }
    }

    public init(id: String, name: LocalizedText, sport: String = "muay_thai", estimatedMinutes: Int, blocks: [Block],
                restAfterBlock: [Int: Int] = [:], choices: [Choice] = []) {
        self.id = id
        self.name = name
        self.sport = sport
        self.estimatedMinutes = estimatedMinutes
        self.blocks = blocks
        self.restAfterBlock = restAfterBlock
        self.choices = choices
    }

    /// The workout with the user's picks in place, one list per choice in order (specs/06 "Seçim").
    public func resolving(picks: [[String]]) throws(ParseError) -> Workout {
        guard picks.count == choices.count else { throw ParseError(path: "choices", message: "needs one pick list per choice") }
        var out = self
        out.choices = []
        // from the last choice back, so earlier positions stay valid
        for (i, c) in choices.enumerated().reversed() {
            let p = picks[i]
            guard p.count == c.count, Set(p).count == p.count, p.allSatisfy(c.from.contains) else {
                throw ParseError(path: "choices[\(i)]", message: "pick exactly \(c.count) different eskivs from the list")
            }
            out.blocks.insert(contentsOf: p.map { .technique(exerciseId: $0, sets: c.sets, reps: c.reps, restSec: c.restSec, mode: c.mode) },
                              at: c.position)
            out.restAfterBlock = Dictionary(uniqueKeysWithValues: out.restAfterBlock.map { ($0.key >= c.position ? $0.key + p.count : $0.key, $0.value) })
        }
        return out
    }

    public var usesCamera: Bool { blocks.contains(where: \.usesCamera) }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public var path: String
        public var message: String
        public var description: String { "\(path): \(message)" }
    }

    public static func parse(_ json: JSONValue) throws(ParseError) -> Workout {
        func fail(_ path: String, _ m: String) -> ParseError { ParseError(path: path, message: m) }
        func object(_ v: JSONValue?, _ path: String, _ keys: Set<String>) throws(ParseError) -> JSONObject {
            guard let o = v?.objectValue else { throw fail(path, "must be an object") }
            if let k = o.keys.first(where: { !keys.contains($0) }) { throw fail(path, "unknown field '\(k)'") }
            return o
        }
        func int(_ v: JSONValue?, _ path: String, min: Int) throws(ParseError) -> Int {
            guard let n = v?.numberValue, n == n.rounded(), n >= Double(min), n < 1e6 else { throw fail(path, "must be an integer ≥ \(min)") }
            return Int(n)
        }
        func string(_ v: JSONValue?, _ path: String) throws(ParseError) -> String {
            guard let s = v?.stringValue, !s.isEmpty else { throw fail(path, "must be a non-empty string") }
            return s
        }
        func mode(_ v: JSONValue?, _ path: String) throws(ParseError) -> SetMode {
            guard let v else { return .lenient }
            guard let s = v.stringValue, let m = SetMode(rawValue: s) else { throw fail(path, "must be strict or lenient") }
            return m
        }
        func steps(_ v: JSONValue?, _ path: String) throws(ParseError) -> [GuidedStep] {
            guard let list = v?.arrayValue, !list.isEmpty else { throw fail(path, "needs at least one step") }
            var out: [GuidedStep] = []
            for (i, e) in list.enumerated() {
                let p = "\(path)[\(i)]"
                let o = try object(e, p, ["textKey", "durationSec", "audioKey"])
                out.append(GuidedStep(textKey: try string(o["textKey"], p + ".textKey"), durationSec: try int(o["durationSec"], p + ".durationSec", min: 1),
                                      audioKey: o["audioKey"] == nil ? nil : try string(o["audioKey"], p + ".audioKey")))
            }
            return out
        }

        /// In a circuit a move is one set and the circuit owns the rest.
        func conditioning(_ e: JSONValue, _ p: String, inCircuit: Bool) throws(ParseError) -> Block {
            let keys: Set<String> = inCircuit ? ["type", "exerciseId", "reps", "durationSec", "mode"]
                : ["type", "exerciseId", "sets", "reps", "durationSec", "restSec", "mode"]
            let b = try object(e, p, keys)
            let reps = b["reps"] == nil ? nil : try int(b["reps"], p + ".reps", min: 1)
            let dur = b["durationSec"] == nil ? nil : try int(b["durationSec"], p + ".durationSec", min: 1)
            guard (reps == nil) != (dur == nil) else { throw fail(p, "needs exactly one of reps and durationSec") }
            return .conditioning(exerciseId: try string(b["exerciseId"], p + ".exerciseId"),
                                 sets: inCircuit ? 1 : try int(b["sets"], p + ".sets", min: 1), reps: reps, durationSec: dur,
                                 restSec: inCircuit ? 0 : try int(b["restSec"], p + ".restSec", min: 0), mode: try mode(b["mode"], p + ".mode"))
        }

        let o = try object(json, "", ["formatVersion", "id", "name", "sport", "estimatedMinutes", "blocks"])
        guard o["formatVersion"]?.numberValue == 1 else { throw fail("formatVersion", "must be 1") }
        let id = try string(o["id"], "id")
        let n = try object(o["name"], "name", ["tr", "en"])
        let name = LocalizedText(tr: try string(n["tr"], "name.tr"), en: try string(n["en"], "name.en"))
        let sport = try string(o["sport"], "sport")
        guard sport == "muay_thai" else { throw fail("sport", "must be muay_thai") }
        let minutes = try int(o["estimatedMinutes"], "estimatedMinutes", min: 1)
        guard let list = o["blocks"]?.arrayValue, !list.isEmpty else { throw fail("blocks", "needs at least one block") }
        var blocks: [Block] = []
        var restAfter: [Int: Int] = [:]
        var choices: [Choice] = []
        for (i, e) in list.enumerated() {
            let p = "blocks[\(i)]"
            guard let type = e["type"]?.stringValue else { throw fail(p + ".type", "missing") }
            switch type {
            case "warmup", "guided":
                let b = try object(e, p, ["type", "steps"])
                let s = try steps(b["steps"], p + ".steps")
                blocks.append(type == "warmup" ? .warmup(steps: s) : .guided(steps: s))
            case "technique" where e["choose"] != nil:
                let b = try object(e, p, ["type", "choose", "sets", "reps", "restSec", "mode"])
                let c = try object(b["choose"], p + ".choose", ["from", "count"])
                guard let from = c["from"]?.arrayValue, !from.isEmpty else { throw fail(p + ".choose.from", "needs at least one template") }
                var ids: [String] = []
                for (k, v) in from.enumerated() { ids.append(try string(v, "\(p).choose.from[\(k)]")) }
                guard Set(ids).count == ids.count else { throw fail(p + ".choose.from", "must not repeat") }
                let count = try int(c["count"], p + ".choose.count", min: 1)
                guard count <= ids.count else { throw fail(p + ".choose.count", "must not exceed the list") }
                choices.append(Choice(position: blocks.count, from: ids, count: count, sets: try int(b["sets"], p + ".sets", min: 1),
                                      reps: try int(b["reps"], p + ".reps", min: 1), restSec: try int(b["restSec"], p + ".restSec", min: 0),
                                      mode: try mode(b["mode"], p + ".mode")))
            case "technique":
                let b = try object(e, p, ["type", "exerciseId", "sets", "reps", "restSec", "mode"])
                blocks.append(.technique(exerciseId: try string(b["exerciseId"], p + ".exerciseId"), sets: try int(b["sets"], p + ".sets", min: 1),
                                         reps: try int(b["reps"], p + ".reps", min: 1), restSec: try int(b["restSec"], p + ".restSec", min: 0),
                                         mode: try mode(b["mode"], p + ".mode")))
            case "conditioning":
                blocks.append(try conditioning(e, p, inCircuit: false))
            case "circuit":
                // specs/06 "Devre": opened into one-set blocks; the rest comes after the last move of every round but the last
                let b = try object(e, p, ["type", "rounds", "restSec", "blocks"])
                let rounds = try int(b["rounds"], p + ".rounds", min: 1)
                let rest = try int(b["restSec"], p + ".restSec", min: 0)
                guard let items = b["blocks"]?.arrayValue, !items.isEmpty else { throw fail(p + ".blocks", "needs at least one block") }
                var moves: [Block] = []
                for (j, item) in items.enumerated() {
                    let q = "\(p).blocks[\(j)]"
                    guard item["type"]?.stringValue == "conditioning" else { throw fail(q + ".type", "must be conditioning") }
                    moves.append(try conditioning(item, q, inCircuit: true))
                }
                for r in 0..<rounds {
                    for (j, m) in moves.enumerated() {
                        guard case .conditioning(let id, _, let reps, let dur, _, let md) = m else { continue }
                        if j == moves.count - 1, r < rounds - 1, rest > 0 { restAfter[blocks.count] = rest }
                        blocks.append(.conditioning(exerciseId: id, sets: 1, reps: reps, durationSec: dur, restSec: 0, mode: md))
                    }
                }
            case "reflex":
                let b = try object(e, p, ["type", "catalogId", "level", "cues", "sets", "restSec"])
                let level: ReflexLevel
                if b["level"]?.stringValue == "chosen" {
                    level = .chosen
                } else {
                    level = .fixed(try int(b["level"], p + ".level", min: 1))
                }
                blocks.append(.reflex(catalogId: try string(b["catalogId"], p + ".catalogId"), level: level,
                                      cues: b["cues"] == nil ? nil : try int(b["cues"], p + ".cues", min: 1),
                                      restSec: try int(b["restSec"], p + ".restSec", min: 0),
                                      sets: b["sets"] == nil ? 1 : try int(b["sets"], p + ".sets", min: 1)))
            default:
                throw fail(p + ".type", "unknown block type '\(type)'")
            }
        }
        return Workout(id: id, name: name, sport: sport, estimatedMinutes: minutes, blocks: blocks, restAfterBlock: restAfter, choices: choices)
    }
}
