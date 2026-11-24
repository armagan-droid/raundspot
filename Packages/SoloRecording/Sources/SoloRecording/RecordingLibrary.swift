import Foundation

// Recording mode's participants, consents and packages (specs/09 "Rıza", "Depolama ve güvenlik").
// Everything lives under one directory that is excluded from backup and protected with
// NSFileProtectionComplete (AC-9.8). Real names never enter: a participant is a code (P07).

public enum RecordingError: Error, Equatable {
    case invalidCode, duplicateCode, unknownParticipant, adultNotConfirmed, noConsent, lowStorage
}

public struct Participant: Codable, Sendable, Equatable {
    public var code: String
    public var createdAt: Date
}

public struct RecordingConsent: Codable, Sendable, Equatable {
    public var id: UUID
    public var participantRef: String
    public var consentVersion: Int
    public var consentedAt: Date
    public var withdrawnAt: Date?
}

/// `meta.json` of a package (specs/09 "Ne kaydedilir"): no name, no free text.
public struct RecordingMeta: Codable, Sendable, Equatable {
    public var recordingId: UUID
    public var participant: String
    public var consentId: UUID
    public var createdAt: Date
    public var device: String
    public var osVersion: String
    public var appVersion: String
    public var mode: String
    public var stance: String
    public var camera: String
    public var pose3D: Bool
    /// Template id → its full JSON, as used.
    public var templates: [String: String]
    /// Exports made from this package (specs/09 "Dışa aktarma").
    public var exports: [String]

    public init(recordingId: UUID = UUID(), participant: String, consentId: UUID, createdAt: Date, device: String, osVersion: String,
                appVersion: String, mode: String, stance: String, camera: String, pose3D: Bool, templates: [String: String], exports: [String] = []) {
        self.recordingId = recordingId
        self.participant = participant
        self.consentId = consentId
        self.createdAt = createdAt
        self.device = device
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.mode = mode
        self.stance = stance
        self.camera = camera
        self.pose3D = pose3D
        self.templates = templates
        self.exports = exports
    }
}

/// Free space rule before recording (specs/09): warn under 2 GB, refuse under 500 MB.
public enum StorageCheck: Equatable {
    case ok, warn, refuse

    public static func check(freeBytes: Int64) -> StorageCheck {
        freeBytes < 500_000_000 ? .refuse : freeBytes < 2_000_000_000 ? .warn : .ok
    }
}

public final class RecordingLibrary {
    /// The consent text's version; a new version asks every participant again (specs/09 rule 4).
    public static let consentVersion = 1

    public let root: URL
    private var state: State

    private struct State: Codable {
        var participants: [Participant] = []
        var consents: [RecordingConsent] = []
    }

    public var participants: [Participant] { state.participants }
    public var consents: [RecordingConsent] { state.consents }
    var packagesDir: URL { root.appendingPathComponent("Recordings", isDirectory: true) }
    private var stateURL: URL { root.appendingPathComponent("library.json") }

    /// - Parameter root: the recording directory in the app container.
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Recordings"), withIntermediateDirectories: true)
        try Self.secure(root)
        state = (try? JSONDecoder.iso.decode(State.self, from: Data(contentsOf: root.appendingPathComponent("library.json")))) ?? State()
    }

    /// AC-9.8: excluded from backup, complete protection.
    static func secure(_ url: URL) throws {
        var u = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try u.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private func save() throws {
        try JSONEncoder.iso.encode(state).write(to: stateURL, options: [.atomic, .completeFileProtection])
    }

    /// A pseudonymous code: P and two or more digits.
    public func addParticipant(_ code: String, at: Date) throws {
        guard code.range(of: #"^P[0-9]{2,}$"#, options: .regularExpression) != nil else { throw RecordingError.invalidCode }
        guard !state.participants.contains(where: { $0.code == code }) else { throw RecordingError.duplicateCode }
        state.participants.append(Participant(code: code, createdAt: at))
        try save()
    }

    /// The participant checks "18+" and accepts themselves (AC-9.2).
    @discardableResult
    public func consent(_ code: String, adultConfirmed: Bool, at: Date) throws -> RecordingConsent {
        guard state.participants.contains(where: { $0.code == code }) else { throw RecordingError.unknownParticipant }
        guard adultConfirmed else { throw RecordingError.adultNotConfirmed }
        let c = RecordingConsent(id: UUID(), participantRef: code, consentVersion: Self.consentVersion, consentedAt: at, withdrawnAt: nil)
        state.consents.append(c)
        try save()
        return c
    }

    /// The consent that allows recording: the current version, not withdrawn.
    public func activeConsent(_ code: String) -> RecordingConsent? {
        state.consents.last { $0.participantRef == code && $0.consentVersion == Self.consentVersion && $0.withdrawnAt == nil }
    }

    public func canRecord(_ code: String) -> Bool { activeConsent(code) != nil }

    /// Withdrawal (AC-9.7): every package of the participant is deleted; returns the export file names made from them.
    @discardableResult
    public func withdraw(_ code: String, at: Date) throws -> [String] {
        var exports: [String] = []
        for p in packages() where p.meta.participant == code {
            exports += p.meta.exports
            try FileManager.default.removeItem(at: p.url)
        }
        for i in state.consents.indices where state.consents[i].participantRef == code && state.consents[i].withdrawnAt == nil {
            state.consents[i].withdrawnAt = at
        }
        try save()
        return exports
    }

    public struct PackageInfo {
        public var url: URL
        public var meta: RecordingMeta
    }

    public func packages() -> [PackageInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: packagesDir.path)) ?? []
        return names.filter { $0.hasSuffix(".gsrec") }.sorted().compactMap { name in
            let url = packagesDir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url.appendingPathComponent("meta.json")),
                  let meta = try? JSONDecoder.iso.decode(RecordingMeta.self, from: data) else { return nil }
            return PackageInfo(url: url, meta: meta)
        }
    }

    /// A new package for a participant with an active consent (AC-9.2) and enough space.
    public func newPackage(_ meta: RecordingMeta, freeBytes: Int64) throws -> RecordingWriter {
        guard let c = activeConsent(meta.participant), c.id == meta.consentId else { throw RecordingError.noConsent }
        guard StorageCheck.check(freeBytes: freeBytes) != .refuse else { throw RecordingError.lowStorage }
        return try RecordingWriter(dir: packagesDir.appendingPathComponent("\(meta.recordingId.uuidString).gsrec", isDirectory: true), meta: meta)
    }

    /// Retention (specs/09): suggest deleting after 11 months, delete at 12.
    public func retention(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> (suggest: [UUID], delete: [UUID]) {
        var suggest: [UUID] = [], delete: [UUID] = []
        for p in packages() {
            let created = p.meta.createdAt
            if let d12 = calendar.date(byAdding: .month, value: 12, to: created), now >= d12 {
                delete.append(p.meta.recordingId)
            } else if let d11 = calendar.date(byAdding: .month, value: 11, to: created), now >= d11 {
                suggest.append(p.meta.recordingId)
            }
        }
        return (suggest, delete)
    }

    /// Deletes the packages at 12 months (app launch or background refresh).
    public func purgeExpired(now: Date) throws {
        let delete = Set(retention(now: now).delete)
        for p in packages() where delete.contains(p.meta.recordingId) { try FileManager.default.removeItem(at: p.url) }
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
