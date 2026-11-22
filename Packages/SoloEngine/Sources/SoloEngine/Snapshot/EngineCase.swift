// One engine case (specs/03 "Kaynak uyumluluğu" and "anlık görüntüler"): a
// rule pack, a setup, a sequence and the expected events, metrics and rep
// states. Source golden files and snapshots share this format.

public struct CueSwitch: Sendable, Equatable {
    public var fromT: Double
    public var enabled: Bool

    public init(fromT: Double, enabled: Bool) {
        self.fromT = fromT
        self.enabled = enabled
    }
}

public struct RecordedEvent: Sendable, Equatable {
    public var frame: Int
    public var t: Double
    public var event: EngineEvent
}

public struct MetricSample: Sendable, Equatable {
    public var frame: Int
    /// Evaluation order; NaN for unknown.
    public var values: [(name: String, value: Double)]

    public static func == (a: Self, b: Self) -> Bool {
        a.frame == b.frame && a.values.count == b.values.count
            && zip(a.values, b.values).allSatisfy { $0.name == $1.name && ($0.value == $1.value || ($0.value.isNaN && $1.value.isNaN)) }
    }
}

public struct EngineOutcome: Sendable, Equatable {
    public var events: [RecordedEvent]
    public var metricsEvery: Int
    public var metrics: [MetricSample]
    public var repStates: [RepCounterState]
}

public struct EngineCase: Sendable, Equatable {
    /// `"source": {repo, commit}` (golden) or `"generatedBy"` (snapshot), kept as written.
    public var origin: JSONObject
    public var rulePack: String
    public var rulePackVersion: Int
    /// Repo-relative template path (snapshots).
    public var rulePackFile: String?
    public var setup: ExerciseSetup
    public var options: ExerciseEngineOptions
    public var cuesEnabled: [CueSwitch]
    /// Relative to the case file's directory.
    public var sequence: String
    public var expected: EngineOutcome

    public init(origin: JSONObject, rulePack: String, rulePackVersion: Int, rulePackFile: String?, setup: ExerciseSetup,
                options: ExerciseEngineOptions, cuesEnabled: [CueSwitch], sequence: String, expected: EngineOutcome) {
        self.origin = origin
        self.rulePack = rulePack
        self.rulePackVersion = rulePackVersion
        self.rulePackFile = rulePackFile
        self.setup = setup
        self.options = options
        self.cuesEnabled = cuesEnabled
        self.sequence = sequence
        self.expected = expected
    }

    /// Runs the engine over a sequence and records what a case compares.
    public static func run(_ loaded: LoadedRulePack, _ seq: LandmarkSequence, setup: ExerciseSetup,
                           options: ExerciseEngineOptions = .init(), cuesEnabled: [CueSwitch] = [],
                           metricsEvery: Int = 10) -> EngineOutcome {
        let engine = ExerciseEngine(loaded, setup: setup, options: options)
        var switches = cuesEnabled.sorted { $0.fromT < $1.fromT }[...]
        var events: [RecordedEvent] = []
        var metrics: [MetricSample] = []
        var states: [RepCounterState] = []
        for (i, frame) in seq.frames.enumerated() {
            while let s = switches.first, frame.t >= s.fromT {
                engine.setCuesEnabled(s.enabled)
                switches.removeFirst()
            }
            for e in engine.push(frame) { events.append(RecordedEvent(frame: i, t: e.t, event: e.event)) }
            if metricsEvery > 0, i % metricsEvery == 0 {
                metrics.append(MetricSample(frame: i, values: engine.metricOrder.map { ($0, engine.metrics[$0] ?? .nan) }))
            }
            states.append(engine.repState)
        }
        return EngineOutcome(events: events, metricsEvery: metricsEvery, metrics: metrics, repStates: states)
    }

    /// Equality rules of specs/03 "Doğrulama": events (type, order, frame,
    /// fields) exact, metrics within `tolerance` absolute or relative, NaN = NaN,
    /// rep states exact. Returns readable differences (empty = equal).
    public static func differences(expected: EngineOutcome, actual: EngineOutcome, tolerance: Double = 1e-9,
                                   limit: Int = 20) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if out.count < limit { out.append(s) } }

        if expected.events.count != actual.events.count {
            add("events: expected \(expected.events.count), got \(actual.events.count)")
        }
        for (i, (e, a)) in zip(expected.events, actual.events).enumerated() where e.frame != a.frame || e.event != a.event {
            add("events[\(i)]: expected \(describe(e)), got \(describe(a))")
        }
        if expected.repStates.count != actual.repStates.count {
            add("repStates: expected \(expected.repStates.count) frames, got \(actual.repStates.count)")
        }
        for (i, (e, a)) in zip(expected.repStates, actual.repStates).enumerated() where e != a {
            add("repStates[\(i)]: expected \(e.rawValue), got \(a.rawValue)")
        }
        if expected.metrics.count != actual.metrics.count || expected.metricsEvery != actual.metricsEvery {
            add("metrics: expected \(expected.metrics.count) samples every \(expected.metricsEvery), got \(actual.metrics.count) every \(actual.metricsEvery)")
        }
        for (e, a) in zip(expected.metrics, actual.metrics) {
            if e.frame != a.frame || e.values.map(\.name) != a.values.map(\.name) {
                add("metrics at frame \(e.frame): expected names \(e.values.map(\.name)) at frame \(e.frame), got \(a.values.map(\.name)) at frame \(a.frame)")
                continue
            }
            for (x, y) in zip(e.values, a.values) where !close(x.value, y.value, tolerance) {
                add("metrics[frame \(e.frame)].\(x.name): expected \(x.value), got \(y.value)")
            }
        }
        return out
    }

    static func close(_ a: Double, _ b: Double, _ tol: Double) -> Bool {
        if a.isNaN || b.isNaN { return a.isNaN && b.isNaN }
        if a == b { return true }
        let d = Swift.abs(a - b)
        return d <= tol || d <= tol * Swift.max(Swift.abs(a), Swift.abs(b))
    }

    static func describe(_ e: RecordedEvent) -> String { "frame \(e.frame) \(e.event)" }
}

// MARK: - JSON

extension EngineEvent {
    var jsonFields: [(String, JSONValue)] {
        switch self {
        case .repCompleted(let outcome, let faults, let durationMs):
            [("outcome", .string(outcome.rawValue)), ("faults", .array(faults.map { .string($0) })), ("durationMs", .number(Double(durationMs)))]
        case .faultDetected(let id), .safetyPause(let id): [("faultId", .string(id))]
        default: []
        }
    }

    init?(type: String, _ o: JSONValue) {
        switch type {
        case "REP_STARTED": self = .repStarted
        case "TRACKING_LOST": self = .trackingLost
        case "TRACKING_RESTORED": self = .trackingRestored
        case "READY_POSE_HELD": self = .readyPoseHeld
        case "FAULT_DETECTED", "SAFETY_PAUSE":
            guard let id = o["faultId"]?.stringValue else { return nil }
            self = type == "FAULT_DETECTED" ? .faultDetected(faultId: id) : .safetyPause(faultId: id)
        case "REP_COMPLETED":
            guard let outcome = o["outcome"]?.stringValue.flatMap(RepOutcome.init(rawValue:)),
                  let faults = o["faults"]?.arrayValue?.compactMap(\.stringValue),
                  let d = o["durationMs"]?.numberValue, d == d.rounded() else { return nil }
            self = .repCompleted(outcome: outcome, faults: faults, durationMs: Int(d))
        default: return nil
        }
    }
}

public struct EngineCaseError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String
    public var description: String { "invalid engine case: \(message)" }
}

extension EngineOutcome {
    public var json: JSONValue {
        var o: JSONValue = [:]
        o["events"] = .array(events.map { e in
            var v: JSONValue = ["frame": .number(Double(e.frame)), "t": .number(e.t), "type": .string(e.event.type)]
            for (k, x) in e.event.jsonFields { v[k] = x }
            return v
        })
        var metricsJSON: JSONValue = ["every": .number(Double(metricsEvery))]
        metricsJSON["values"] = .array(metrics.map { m in
            var values: JSONValue = [:]
            for (name, value) in m.values { values[name] = value.isNaN ? .null : .number(value) }
            return ["frame": .number(Double(m.frame)), "values": values]
        })
        o["metrics"] = metricsJSON
        o["repStates"] = .array(repStates.map { .string($0.rawValue) })
        return o
    }

    public init(json o: JSONValue) throws(EngineCaseError) {
        func fail(_ m: String) -> EngineCaseError { EngineCaseError(message: m) }
        guard let evs = o["events"]?.arrayValue, let m = o["metrics"], let every = m["every"]?.numberValue,
              let samples = m["values"]?.arrayValue, let states = o["repStates"]?.arrayValue else { throw fail("expected") }
        var events: [RecordedEvent] = []
        for (i, e) in evs.enumerated() {
            guard let frame = e["frame"]?.numberValue, let t = e["t"]?.numberValue, let type = e["type"]?.stringValue,
                  let event = EngineEvent(type: type, e) else { throw fail("expected.events[\(i)]") }
            events.append(RecordedEvent(frame: Int(frame), t: t, event: event))
        }
        var metrics: [MetricSample] = []
        for (i, s) in samples.enumerated() {
            guard let frame = s["frame"]?.numberValue, let values = s["values"]?.objectValue else { throw fail("expected.metrics.values[\(i)]") }
            var list: [(String, Double)] = []
            for (k, v) in values.entries {
                if v == .null { list.append((k, .nan)) } else if let n = v.numberValue { list.append((k, n)) } else {
                    throw fail("expected.metrics.values[\(i)].\(k)")
                }
            }
            metrics.append(MetricSample(frame: Int(frame), values: list))
        }
        var repStates: [RepCounterState] = []
        for (i, s) in states.enumerated() {
            guard let state = s.stringValue.flatMap(RepCounterState.init(rawValue:)) else { throw fail("expected.repStates[\(i)]") }
            repStates.append(state)
        }
        self.init(events: events, metricsEvery: Int(every), metrics: metrics, repStates: repStates)
    }
}

extension EngineCase {
    public var json: JSONValue {
        var o: JSONValue = ["goldenVersion": 1]
        for (k, v) in origin.entries { o[k] = v }
        o["rulePack"] = .string(rulePack)
        o["rulePackVersion"] = .number(Double(rulePackVersion))
        if let rulePackFile { o["rulePackFile"] = .string(rulePackFile) }
        let view: String = switch setup.view { case .front: "front"; case .side: "side"; case .ambiguous: "ambiguous" }
        o["setup"] = ["view": .string(view), "nearSide": .string(setup.nearSide.rawValue)]
        o["options"] = ["safetyPause": .bool(options.safetyPause)]
        o["cuesEnabled"] = .array(cuesEnabled.map { ["fromT": .number($0.fromT), "enabled": .bool($0.enabled)] })
        o["sequence"] = .string(sequence)
        o["expected"] = expected.json
        return o
    }

    public init(json o: JSONValue) throws(EngineCaseError) {
        func fail(_ m: String) -> EngineCaseError { EngineCaseError(message: m) }
        guard o["goldenVersion"]?.numberValue == 1 else { throw fail("goldenVersion") }
        var origin = JSONObject()
        if let source = o["source"] { origin["source"] = source }
        if let generatedBy = o["generatedBy"] { origin["generatedBy"] = generatedBy }
        guard let rulePack = o["rulePack"]?.stringValue, let version = o["rulePackVersion"]?.numberValue else { throw fail("rulePack") }
        let viewName = o["setup"]?["view"]?.stringValue
        let view: View? = switch viewName { case "front": .front; case "side": .side; case "ambiguous": .ambiguous; default: nil }
        guard let view, let near = o["setup"]?["nearSide"]?.stringValue.flatMap(PersonSide.init(rawValue:)) else { throw fail("setup") }
        var options = ExerciseEngineOptions()
        if let safety = o["options"]?["safetyPause"] {
            guard case .bool(let b) = safety else { throw fail("options.safetyPause") }
            options.safetyPause = b
        }
        var cues: [CueSwitch] = []
        for (i, c) in (o["cuesEnabled"]?.arrayValue ?? []).enumerated() {
            guard let from = c["fromT"]?.numberValue, case .bool(let enabled)? = c["enabled"] else { throw fail("cuesEnabled[\(i)]") }
            cues.append(CueSwitch(fromT: from, enabled: enabled))
        }
        guard let sequence = o["sequence"]?.stringValue, let expected = o["expected"] else { throw fail("sequence") }
        self.init(origin: origin, rulePack: rulePack, rulePackVersion: Int(version), rulePackFile: o["rulePackFile"]?.stringValue,
                  setup: ExerciseSetup(view: view, nearSide: near), options: options, cuesEnabled: cues, sequence: sequence,
                  expected: try EngineOutcome(json: expected))
    }
}
