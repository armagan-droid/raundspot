import Foundation
import SoloEngine

/// An attempt the coach marked in playback (specs/09 "Deneme işaretleme"): its range and label.
public struct AttemptMark: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Host time, ms.
    public var start: Double
    public var end: Double
    public var label: RecordingNote.Label

    public init(id: UUID = UUID(), start: Double, end: Double, label: RecordingNote.Label) {
        self.id = id
        self.start = start
        self.end = end
        self.label = label
    }
}

/// `marks.json` of a package.
public enum RecordingMarks {
    public enum MarkError: Error, Equatable { case reversed, overlap }

    public static func load(_ dir: URL) -> [AttemptMark] {
        (try? JSONDecoder.iso.decode([AttemptMark].self, from: Data(contentsOf: dir.appendingPathComponent("marks.json")))) ?? []
    }

    public static func save(_ marks: [AttemptMark], _ dir: URL) throws {
        try JSONEncoder.iso.encode(marks.sorted { $0.start < $1.start })
            .write(to: dir.appendingPathComponent("marks.json"), options: [.atomic, .completeFileProtection])
    }

    /// The marks with a new one, in time order; a reversed or overlapping mark is refused.
    public static func adding(_ mark: AttemptMark, to marks: [AttemptMark]) throws -> [AttemptMark] {
        guard mark.start < mark.end else { throw MarkError.reversed }
        guard !marks.contains(where: { $0.id != mark.id && mark.start < $0.end && $0.start < mark.end }) else { throw MarkError.overlap }
        return (marks.filter { $0.id != mark.id } + [mark]).sorted { $0.start < $1.start }
    }

    /// `labels.reps` from the marks, each with its span; nil without marks or with a mark lacking an outcome.
    public static func labels(_ marks: [AttemptMark]) -> [RepLabel]? {
        guard !marks.isEmpty else { return nil }
        var out: [RepLabel] = []
        for m in marks.sorted(by: { $0.start < $1.start }) {
            guard let o = m.label.outcome.flatMap(RepOutcome.init(rawValue:)) else { return nil }
            out.append(RepLabel(outcome: o, faults: m.label.faults, span: [m.start, m.end]))
        }
        return out
    }
}
