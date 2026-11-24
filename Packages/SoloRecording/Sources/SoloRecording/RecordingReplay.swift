import Foundation
import SoloEngine

/// Replay of recordings with other thresholds (specs/09 "Yeniden oynatma", T5.3): the Swift engine runs again
/// on the stored poses; nothing is saved, the results are computed each time.
public enum RecordingReplay {
    /// An event with its frame time, comparable across runs.
    public struct Event: Sendable, Equatable, Hashable {
        public var t: Double
        public var json: String
    }

    /// The events the workout wrote to `engine.jsonl` for a template.
    public static func recorded(package dir: URL, template: String) -> [Event] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("engine.jsonl"), encoding: .utf8) else { return [] }
        var out: [Event] = []
        for line in text.split(separator: "\n") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["template"] as? String == template,
                  let t = o["t"] as? Double, let events = o["events"] as? [Any] else { continue }
            for e in events {
                guard let data = try? JSONSerialization.data(withJSONObject: e), let v = try? JSONValue.parse(data),
                      let ev = EngineEvent(jsonObject: v) else { continue }
                out.append(Event(t: t, json: ev.jsonObject.serialized()))
            }
        }
        return out
    }

    /// The template run once over the sequence (one set from its first frame).
    public static func run(_ seq: LandmarkSequence, pack: LoadedRulePack, setup: ExerciseSetup) -> [Event] {
        let engine = ExerciseEngine(pack, setup: setup)
        return seq.frames.flatMap { f in engine.push(f).map { Event(t: $0.t, json: $0.event.jsonObject.serialized()) } }
    }

    /// Old and new event lanes (specs/09): what the change adds and removes.
    public static func diff(old: [Event], new: [Event]) -> (added: [Event], removed: [Event]) {
        let o = Set(old), n = Set(new)
        return (new.filter { !o.contains($0) }, old.filter { !n.contains($0) })
    }

    /// A template parameter changed by its sweep path (`rep.target.enter`, `faults.<id>.threshold`), then run.
    public static func run(_ seq: LandmarkSequence, rulePack: JSONValue, path: String, value: Double,
                           setup: ExerciseSetup) throws -> [Event] {
        let changed = try Calibration.withParameter(rulePack, path: path, value: value)
        let pack = try RulePackLoader.load(changed, capabilities: .vision19TwoD).get()
        return run(seq, pack: pack, setup: setup)
    }

    /// Value sweep over labelled recordings (ref 09 measures; 3–7 values).
    public static func sweep(_ sequences: [LandmarkSequence], rulePack: JSONValue, path: String,
                             values: [Double]) throws -> [(value: Double, result: Calibration.SweepResult)] {
        try Calibration.sweep(rulePack, sequences, path: path, values: values)
    }
}
