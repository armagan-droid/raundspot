import Foundation
import SoloEngine

/// Notes added in playback (specs/09 "Oynatma ekranı"): `notes.json` of a package.
public struct RecordingNote: Codable, Sendable, Equatable, Identifiable {
    public enum Author: String, Codable, Sendable { case coach, developer }

    /// A note's optional label: the attempt's outcome and faults; in a reflex recording the right response
    /// template (or `noResponse`) and that template's faults.
    public struct Label: Codable, Sendable, Equatable {
        /// "No response was right" (a feint): `null` as the export's `expected`.
        public static let noResponse = "none"

        public var outcome: String?
        public var faults: [String]
        public var response: String?

        public init(outcome: String, faults: [String]) {
            self.outcome = outcome
            self.faults = faults
        }

        public init(response: String, faults: [String]) {
            self.response = response
            self.faults = faults
        }
    }

    public var id: UUID
    /// Host time of the note, ms (the frame it was written at).
    public var t: Double
    public var text: String
    public var author: Author
    public var label: Label?

    public init(id: UUID = UUID(), t: Double, text: String, author: Author, label: Label? = nil) {
        self.id = id
        self.t = t
        self.text = text
        self.author = author
        self.label = label
    }
}

/// An attempt as the engine recorded it: from REP_STARTED to its REP_COMPLETED.
public struct RecordedAttempt: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var outcome: String
}

public enum RecordingNotes {
    public static func load(_ dir: URL) -> [RecordingNote] {
        (try? JSONDecoder.iso.decode([RecordingNote].self, from: Data(contentsOf: dir.appendingPathComponent("notes.json")))) ?? []
    }

    public static func save(_ notes: [RecordingNote], _ dir: URL) throws {
        try JSONEncoder.iso.encode(notes.sorted { $0.t < $1.t })
            .write(to: dir.appendingPathComponent("notes.json"), options: [.atomic, .completeFileProtection])
    }

    /// The template's attempts in `engine.jsonl`, in order.
    public static func attempts(package dir: URL, template: String) -> [RecordedAttempt] {
        var out: [RecordedAttempt] = []
        var start: Double?
        for e in RecordingReplay.recorded(package: dir, template: template) {
            guard let v = try? JSONValue.parse(Data(e.json.utf8)), let type = v["type"]?.stringValue else { continue }
            if type == "REP_STARTED" { start = e.t }
            if type == "REP_COMPLETED", let s = start {
                out.append(RecordedAttempt(start: s, end: e.t, outcome: v["outcome"]?.stringValue ?? ""))
                start = nil
            }
        }
        return out
    }

    /// A reflex recording's trials in `app.jsonl`: from the cue (`cueAt`) to the trial line, with its result.
    public static func trials(package dir: URL) -> [RecordedAttempt] {
        appLines(dir, type: "trial").compactMap { o in
            guard let t = o["t"] as? Double, let cue = o["cueAt"] as? Double, let r = o["result"] as? String else { return nil }
            return RecordedAttempt(start: cue, end: t, outcome: r)
        }
    }

    /// The lines of one type in `app.jsonl`, in order.
    public static func appLines(_ dir: URL, type: String) -> [[String: Any]] {
        let text = (try? String(contentsOf: dir.appendingPathComponent("app.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], o["type"] as? String == type else { return nil }
            return o
        }
    }

    /// The export's `reflex` (specs/03): the cue and trial lines, each trial with the coach's label when a note holds one.
    public static func reflexLines(package dir: URL, meta: RecordingMeta, notes: [RecordingNote]) -> ReflexLines? {
        guard meta.isReflex, let catalog = meta.reflexCatalog, let level = meta.reflexLevel, let stance = Stance(rawValue: meta.stance) else { return nil }
        let spans = trials(package: dir)
        var expected: [Int: String?] = [:]
        for n in notes.sorted(by: { $0.t < $1.t }) {
            if let r = n.label?.response, let i = attempt(for: n, in: spans) { expected[i] = r == RecordingNote.Label.noResponse ? nil : r }
        }
        let cues = appLines(dir, type: "cue").compactMap { o -> ReflexLines.Cue? in
            guard let t = o["t"] as? Double, let key = o["key"] as? String, let at = o["plannedAt"] as? Double else { return nil }
            return .init(t: t, key: key, plannedAt: at)
        }
        var out: [ReflexLines.Trial] = []
        for o in appLines(dir, type: "trial") {
            guard let t = o["t"] as? Double, let strike = o["strike"] as? String, let feint = o["feint"] as? Bool, let cue = o["cueAt"] as? Double,
                  let result = (o["result"] as? String).flatMap(ReflexResult.init(rawValue:)) else { continue }
            let i = out.count
            out.append(.init(t: t, strike: strike, feint: feint, cueAt: cue, result: result, response: o["response"] as? String,
                             reactionMs: o["reactionMs"] as? Double, approximate: (o["approximate"] as? Bool) ?? false,
                             expected: expected.keys.contains(i) ? .some(expected[i]!) : nil))
        }
        return ReflexLines(catalogId: catalog, level: level, stance: stance, cues: cues, trials: out)
    }

    /// The note with new text, author and label; its time stays (specs/09 "Not düzenleme").
    public static func edited(_ note: RecordingNote, text: String, author: RecordingNote.Author, label: RecordingNote.Label?) -> RecordingNote {
        var n = note
        n.text = text
        n.author = author
        n.label = label
        return n
    }

    /// The attempt a note belongs to: the one whose span holds it (specs/09), nil between attempts.
    public static func attempt(for note: RecordingNote, in attempts: [RecordedAttempt]) -> Int? {
        attempts.firstIndex { note.t >= $0.start && note.t <= $0.end }
    }

    /// `labels.reps` for the export: one per attempt, only when every attempt has a labelled note (the last one wins).
    public static func labels(_ notes: [RecordingNote], attempts: [RecordedAttempt]) -> [RepLabel]? {
        guard !attempts.isEmpty else { return nil }
        var byAttempt: [Int: RecordingNote.Label] = [:]
        for n in notes.sorted(by: { $0.t < $1.t }) {
            if let l = n.label, let i = attempt(for: n, in: attempts) { byAttempt[i] = l }
        }
        guard byAttempt.count == attempts.count else { return nil }
        var out: [RepLabel] = []
        for i in attempts.indices {
            guard let l = byAttempt[i], let o = l.outcome.flatMap(RepOutcome.init(rawValue:)) else { return nil }
            out.append(RepLabel(outcome: o, faults: l.faults))
        }
        return out
    }
}
