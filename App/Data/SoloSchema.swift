import Foundation
import SoloEngine
import SwiftData

// Local data model (specs/11 Bölüm 1). Ids are UUIDs, times UTC `Date`,
// durations integer ms. Enumerations are stored as their raw strings so that a
// renamed Swift case never silently changes stored data. Engine records
// (Attempt, ReflexTrial) are written once and never change (AC-11.2): their
// properties are read-only outside this file and the only way in is
// `SessionRecorder`.
//
// Every schema change adds a new `VersionedSchema`, a stage in
// `SoloMigrationPlan` and a migration test (AC-11.1). v1.0 entities
// (RoundSummary, PostureAssessment, WeekPlan, EntitlementCache) come with
// their own schema version.

enum SoloSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Profile.self, Session.self, SessionBlock.self, SetRecord.self, Attempt.self, ReflexTrial.self]
    }

    /// The single profile (onboarding, settings).
    @Model final class Profile {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var language: String          // tr | en | system
        var stance: String            // orthodox | southpaw
        var level: String             // beginner | intermediate | advanced
        var goal: String              // defense | conditioning | balanced
        /// Entered by hand only; HealthKit weight is not stored (specs/08).
        var weightKg: Double?
        var heightCm: Double?
        var adultConfirmedAt: Date?
        var disclaimerShownVersion: Int?
        var healthScreeningShownAt: Date?
        var camera: String            // front | back
        var faultCueVoice: Bool
        var resultTones: Bool
        var techniqueTempo: String    // slow | normal
        var reflexLevel: Int
        var sportPack: String

        init(id: UUID = UUID(), createdAt: Date) {
            self.id = id
            self.createdAt = createdAt
            language = "system"
            stance = "orthodox"
            level = "beginner"
            goal = "balanced"
            camera = "front"
            faultCueVoice = true
            resultTones = true
            techniqueTempo = "normal"
            reflexLevel = 1
            sportPack = "muay_thai"
        }
    }

    @Model final class Session {
        @Attribute(.unique) private(set) var id: UUID
        private(set) var workoutId: String
        /// Ready-made workout files carry no version yet (specs/11, specs/06).
        private(set) var workoutVersion: Int?
        private(set) var sport: String
        private(set) var startedAt: Date
        fileprivate(set) var endedAt: Date?
        fileprivate(set) var status: String       // active | paused | done | aborted
        fileprivate(set) var warmupSkipped: Bool
        fileprivate(set) var activeMs: Int
        var energyKcal: Double?
        var energyMethod: String?                 // met | heart_rate
        var healthKitWorkoutUUID: UUID?
        private(set) var stance: String
        private(set) var appVersion: String
        /// Empty: no degraded operation (specs/02).
        fileprivate(set) var degradations: [String]
        @Relationship(deleteRule: .cascade, inverse: \SessionBlock.session) private(set) var blocks: [SessionBlock] = []

        fileprivate init(id: UUID, workoutId: String, workoutVersion: Int?, sport: String, startedAt: Date, stance: String,
                         appVersion: String) {
            self.id = id
            self.workoutId = workoutId
            self.workoutVersion = workoutVersion
            self.sport = sport
            self.startedAt = startedAt
            status = "active"
            warmupSkipped = false
            activeMs = 0
            self.stance = stance
            self.appVersion = appVersion
            degradations = []
        }
    }

    @Model final class SessionBlock {
        @Attribute(.unique) private(set) var id: UUID
        fileprivate(set) var session: Session?
        private(set) var position: Int
        private(set) var kind: String             // warmup | technique | reflex | conditioning | round | guided
        private(set) var exerciseId: String?
        private(set) var exerciseVersion: Int?
        private(set) var catalogId: String?
        private(set) var catalogVersion: Int?
        private(set) var level: Int?
        private(set) var status: String           // done | skipped | partial
        @Relationship(deleteRule: .cascade, inverse: \SetRecord.block) private(set) var sets: [SetRecord] = []

        fileprivate init(id: UUID, position: Int, kind: String, exerciseId: String?, exerciseVersion: Int?, catalogId: String?,
                         catalogVersion: Int?, level: Int?, status: String) {
            self.id = id
            self.position = position
            self.kind = kind
            self.exerciseId = exerciseId
            self.exerciseVersion = exerciseVersion
            self.catalogId = catalogId
            self.catalogVersion = catalogVersion
            self.level = level
            self.status = status
        }
    }

    @Model final class SetRecord {
        @Attribute(.unique) private(set) var id: UUID
        fileprivate(set) var block: SessionBlock?
        private(set) var setIndex: Int
        private(set) var startedAt: Date
        private(set) var endedAt: Date
        private(set) var plannedReps: Int?
        private(set) var validReps: Int
        private(set) var faultyReps: Int
        private(set) var incompleteReps: Int
        private(set) var view: String             // front | side | ambiguous
        private(set) var belowTarget: Bool
        @Relationship(deleteRule: .cascade, inverse: \Attempt.set) private(set) var attempts: [Attempt] = []
        @Relationship(deleteRule: .cascade, inverse: \ReflexTrial.set) private(set) var trials: [ReflexTrial] = []

        fileprivate init(id: UUID, setIndex: Int, startedAt: Date, endedAt: Date, plannedReps: Int?, validReps: Int,
                         faultyReps: Int, incompleteReps: Int, view: String, belowTarget: Bool) {
            self.id = id
            self.setIndex = setIndex
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.plannedReps = plannedReps
            self.validReps = validReps
            self.faultyReps = faultyReps
            self.incompleteReps = incompleteReps
            self.view = view
            self.belowTarget = belowTarget
        }
    }

    /// A technique or conditioning repetition.
    @Model final class Attempt {
        @Attribute(.unique) private(set) var id: UUID
        fileprivate(set) var set: SetRecord?
        private(set) var index: Int
        private(set) var outcome: String          // valid | faulty | incomplete
        private(set) var durationMs: Int
        private(set) var faults: [String]

        fileprivate init(id: UUID, index: Int, outcome: String, durationMs: Int, faults: [String]) {
            self.id = id
            self.index = index
            self.outcome = outcome
            self.durationMs = durationMs
            self.faults = faults
        }
    }

    /// A reflex or round trial (written by the reflex loop, Phase 4).
    @Model final class ReflexTrial {
        @Attribute(.unique) private(set) var id: UUID
        fileprivate(set) var set: SetRecord?
        private(set) var index: Int
        private(set) var comboId: String?
        private(set) var comboIndex: Int?
        private(set) var strikeId: String
        private(set) var isFeint: Bool
        /// From the session start.
        private(set) var cueAtMs: Int
        private(set) var result: String           // correct | correct_faulty | wrong | partial | missed | early | feint_ok | feint_bitten
        private(set) var responseExerciseId: String?
        private(set) var preferred: Bool?
        private(set) var reactionMs: Int?
        private(set) var rtApproximate: Bool
        private(set) var faults: [String]

        fileprivate init(id: UUID, index: Int, comboId: String?, comboIndex: Int?, strikeId: String, isFeint: Bool, cueAtMs: Int,
                         result: String, responseExerciseId: String?, preferred: Bool?, reactionMs: Int?, rtApproximate: Bool,
                         faults: [String]) {
            self.id = id
            self.index = index
            self.comboId = comboId
            self.comboIndex = comboIndex
            self.strikeId = strikeId
            self.isFeint = isFeint
            self.cueAtMs = cueAtMs
            self.result = result
            self.responseExerciseId = responseExerciseId
            self.preferred = preferred
            self.reactionMs = reactionMs
            self.rtApproximate = rtApproximate
            self.faults = faults
        }
    }
}

typealias Profile = SoloSchemaV1.Profile
typealias StoredSession = SoloSchemaV1.Session
typealias StoredBlock = SoloSchemaV1.SessionBlock
typealias StoredSet = SoloSchemaV1.SetRecord
typealias StoredAttempt = SoloSchemaV1.Attempt
typealias StoredReflexTrial = SoloSchemaV1.ReflexTrial

enum SoloMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SoloSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum SoloStore {
    /// The current schema: the last one of the migration plan.
    static var schema: Schema { Schema(versionedSchema: SoloSchemaV1.self) }

    /// The app's store. `inMemory` for tests and previews. The file is protected
    /// until first unlock so a backgrounded session can still write (specs/10).
    static func container(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let config = if inMemory {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            ModelConfiguration(schema: schema, url: url)
        } else {
            ModelConfiguration(schema: schema)
        }
        let container = try ModelContainer(for: schema, migrationPlan: SoloMigrationPlan.self, configurations: [config])
        if !inMemory { protect(config.url) }
        return container
    }

    static func protect(_ url: URL) {
        #if os(iOS)
        let dir = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasPrefix(url.lastPathComponent) {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                   ofItemAtPath: dir.appendingPathComponent(name).path)
        }
        #endif
    }
}

// MARK: - Writes (the only mutations of engine records)

extension SoloSchemaV1.Session {
    fileprivate func finish(status: String, warmupSkipped: Bool, endedAt: Date?, activeMs: Int) {
        self.status = status
        self.warmupSkipped = warmupSkipped
        self.endedAt = endedAt
        self.activeMs = activeMs
    }
}

/// Context the session engine's records do not carry (specs/11 fields).
struct RecordContext {
    var workoutVersion: Int?
    var sport: String
    var stance: String
    var appVersion: String
    var blockKind: (Int) -> String
    var catalog: (Int) -> (id: String, version: Int?, level: Int?)?
}

/// Writes the session engine's `PERSIST` records (specs/06) into the store.
/// A record is written when it is final (specs/11): reps wait for their set,
/// sets for their block. Engine records are insert-only; a record id seen
/// twice is ignored (AC-11.2). The session row is created at the start and
/// gets its final status at the end.
@MainActor final class SessionRecorder {
    private let context: ModelContext
    private let info: RecordContext
    private var session: StoredSession?
    private var pendingReps: [String: [SessionRecord]] = [:]
    private var pendingTrials: [String: [ReflexTrialRecord]] = [:]
    private var pendingSets: [String: [StoredSet]] = [:]
    private var setStarts: [String: Date] = [:]
    private var written: Set<String> = []

    init(context: ModelContext, info: RecordContext) {
        self.context = context
        self.info = info
    }

    /// The set in progress started at `at` (the first record of a set is its end).
    func setStarted(_ setId: String, at: Date) {
        if setStarts[setId] == nil { setStarts[setId] = at }
    }

    /// A reflex trial of the set in progress (specs/05 "Set özeti ve kayıt"); written with its set.
    func writeReflexTrial(_ r: ReflexTrialRecord, setId: String, at: Date) {
        pendingTrials[setId, default: []].append(r)
        setStarted(setId, at: at)
    }

    /// Host time the session started (ms), for `ReflexTrial.cueAtMs` (specs/11).
    var sessionStartMs: Double = 0

    /// - Parameters:
    ///   - now: when the record was emitted.
    ///   - view: the view of the set in progress.
    ///   - activeMs: time spent in sets so far.
    func write(_ record: SessionRecord, now: Date, view: String, activeMs: Int) throws {
        switch record {
        case .session(let id, let workoutId, let status, let warmupSkipped):
            if let session {
                if status != .active {
                    session.finish(status: status.rawValue, warmupSkipped: warmupSkipped, endedAt: now, activeMs: activeMs)
                }
            } else {
                let s = StoredSession(id: UUID(uuidString: id) ?? UUID(), workoutId: workoutId, workoutVersion: info.workoutVersion,
                                      sport: info.sport, startedAt: now, stance: info.stance, appVersion: info.appVersion)
                context.insert(s)
                session = s
            }
        case .rep(let id, let setId, _, _, _, _):
            guard written.insert(id).inserted else { return }
            pendingReps[setId, default: []].append(record)
            setStarted(setId, at: now)
        case .set(let id, let blockId, let index, let valid, let faulty, let attempts, let target, let below, _):
            guard written.insert(id).inserted else { return }
            let reps = pendingReps.removeValue(forKey: id) ?? []
            // a reflex set's attempts are its trials, not incomplete reps
            let isReflex = pendingTrials[id] != nil
            let set = StoredSet(id: UUID(uuidString: id) ?? UUID(), setIndex: index, startedAt: setStarts.removeValue(forKey: id) ?? now,
                                endedAt: now, plannedReps: target, validReps: valid, faultyReps: faulty,
                                incompleteReps: isReflex ? 0 : max(0, attempts - valid - faulty), view: view, belowTarget: below)
            context.insert(set)
            for (i, r) in reps.enumerated() {
                guard case .rep(let rid, _, let outcome, let faults, let durationMs, _) = r else { continue }
                let a = StoredAttempt(id: UUID(uuidString: rid) ?? UUID(), index: i, outcome: outcome.rawValue, durationMs: durationMs,
                                      faults: faults)
                context.insert(a)
                a.set = set
            }
            for r in pendingTrials.removeValue(forKey: id) ?? [] {
                let trial = StoredReflexTrial(
                    id: UUID(), index: r.index, comboId: r.comboId.map { "\($0)" }, comboIndex: r.comboIndex, strikeId: r.strikeId,
                    isFeint: r.isFeint, cueAtMs: Int((r.cueAt - sessionStartMs).rounded()), result: r.result.rawValue,
                    responseExerciseId: r.responseExerciseId, preferred: r.preferred, reactionMs: r.reactionMs.map { Int($0.rounded()) },
                    rtApproximate: r.rtApproximate, faults: r.faults)
                context.insert(trial)
                trial.set = set
            }
            pendingSets[blockId, default: []].append(set)
        case .block(let id, _, let index, let exerciseId, let exerciseVersion, let status):
            guard written.insert(id).inserted, let session else { return }
            let catalog = info.catalog(index)
            let block = StoredBlock(id: UUID(uuidString: id) ?? UUID(), position: index, kind: info.blockKind(index),
                                    exerciseId: exerciseId, exerciseVersion: exerciseVersion, catalogId: catalog?.id,
                                    catalogVersion: catalog?.version, level: catalog?.level, status: status.rawValue)
            context.insert(block)
            block.session = session
            for set in pendingSets.removeValue(forKey: id) ?? [] { set.block = block }
        }
        try context.save()
    }
}

// MARK: - Stored names of engine values

extension Block {
    /// `SessionBlock.kind` (specs/11).
    var kind: String {
        switch self {
        case .warmup: "warmup"
        case .technique: "technique"
        case .reflex: "reflex"
        case .conditioning: "conditioning"
        case .guided: "guided"
        }
    }
}

extension ReflexLevel {
    /// `SessionBlock.level`: nil until the user's pick is known (H3, Phase 4).
    var storedLevel: Int? {
        if case .fixed(let n) = self { n } else { nil }
    }
}
