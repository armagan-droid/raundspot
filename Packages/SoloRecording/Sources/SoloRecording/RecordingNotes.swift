import Foundation
import SoloEngine

/// Notes added in playback (specs/09 "Oynatma ekranı"): `notes.json` of a package.
public struct RecordingNote: Codable, Sendable, Equatable, Identifiable {
    public enum Author: String, Codable, Sendable { case coach, developer }

    /// A note's optional label: the attempt's outcome and faults (reflex: the right response template).
    public struct Label: Codable, Sendable, Equatable {
        public var outcome: String
        public var faults: [String]
        public var response: String?

        public init(outcome: String, faults: [String], response: String? = nil) {
            self.outcome = outcome
            self.faults = faults
            self.response = response
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
            guard let l = byAttempt[i], let o = RepOutcome(rawValue: l.outcome) else { return nil }
            out.append(RepLabel(outcome: o, faults: l.faults))
        }
        return out
    }
}
