import Foundation
import SoloEngine
import SwiftData
import Testing
@testable import GymSpotSolo

/// specs/11 Bölüm 1: the SwiftData model, its migration plan (AC-11.1) and the
/// insert-only engine records (AC-11.2).
@MainActor @Suite struct DataStoreTests {
    static let info = RecordContext(workoutVersion: nil, sport: "muay_thai", stance: "orthodox", appVersion: "test",
                                    blockKind: { $0 == 0 ? "warmup" : "technique" }, catalog: { _ in nil })

    // MARK: AC-11.1

    @Test func theCurrentSchemaIsTheLastOfTheMigrationPlan() {
        let schemas = SoloMigrationPlan.schemas
        #expect(schemas.last.map { ObjectIdentifier($0) } == ObjectIdentifier(SoloSchemaV1.self))
        let versions = schemas.map { $0.versionIdentifier }
        #expect(versions == versions.sorted() && Set(versions).count == versions.count)
        // one stage between each pair of schema versions
        #expect(SoloMigrationPlan.stages.count == schemas.count - 1)
        #expect(SoloStore.schema.entities.count == SoloSchemaV1.models.count)
    }

    /// The migration test of the first version: a store written by V1 opens through the plan with its data.
    /// Each later schema adds a case that opens a store written by the previous one.
    @Test func aStoreWrittenByV1OpensThroughTheMigrationPlan() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("solo.store")
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let v1 = try ModelContainer(for: Schema(versionedSchema: SoloSchemaV1.self),
                                        configurations: ModelConfiguration(url: url))
            let p = Profile(createdAt: created)
            p.stance = "southpaw"
            v1.mainContext.insert(p)
            try v1.mainContext.save()
        }
        let reopened = try SoloStore.container(url: url)
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<Profile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.stance == "southpaw" && profiles.first?.createdAt == created)
    }

    // MARK: records

    private func ids(_ n: Int) -> [String] { (0..<n).map { _ in UUID().uuidString } }

    @Test func theEngineRecordsBecomeASessionTree() throws {
        let container = try SoloStore.container(inMemory: true)
        let recorder = SessionRecorder(context: container.mainContext, info: Self.info)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let at = { (s: Double) in t0.addingTimeInterval(s) }
        let id = ids(8)
        let (session, warmup, block, set) = (id[0], id[1], id[2], id[3])

        try recorder.write(.session(id: session, workoutId: "eskiv_temeli", status: .active, warmupSkipped: false), now: at(0), view: "front", activeMs: 0)
        try recorder.write(.block(id: warmup, sessionId: session, index: 0, exerciseId: nil, exerciseVersion: nil, status: .done), now: at(60), view: "front", activeMs: 0)
        recorder.setStarted(set, at: at(70))
        try recorder.write(.rep(id: id[4], setId: set, outcome: .valid, faults: [], durationMs: 700, counted: true), now: at(72), view: "front", activeMs: 0)
        try recorder.write(.rep(id: id[5], setId: set, outcome: .faulty, faults: ["guard_dropped"], durationMs: 800, counted: true), now: at(74), view: "front", activeMs: 0)
        try recorder.write(.rep(id: id[6], setId: set, outcome: .incomplete, faults: [], durationMs: 400, counted: false), now: at(76), view: "front", activeMs: 0)
        // nothing below the session is stored before its set is final
        #expect(try container.mainContext.fetchCount(FetchDescriptor<StoredAttempt>()) == 0)
        try recorder.write(.set(id: set, blockId: block, index: 0, validReps: 1, faultyReps: 1, attempts: 3, target: 10, belowTarget: true,
                                mode: .lenient), now: at(80), view: "front", activeMs: 10_000)
        try recorder.write(.block(id: block, sessionId: session, index: 1, exerciseId: "slip_left", exerciseVersion: 2, status: .done), now: at(81), view: "front", activeMs: 10_000)
        try recorder.write(.session(id: session, workoutId: "eskiv_temeli", status: .done, warmupSkipped: false), now: at(90), view: "front", activeMs: 10_000)

        let sessions = try container.mainContext.fetch(FetchDescriptor<StoredSession>())
        let s = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(s.id.uuidString == session && s.status == "done" && s.startedAt == at(0) && s.endedAt == at(90) && s.activeMs == 10_000)
        #expect(s.sport == "muay_thai" && s.workoutVersion == nil && s.degradations.isEmpty)
        let blocks = s.blocks.sorted { $0.position < $1.position }
        #expect(blocks.map(\.kind) == ["warmup", "technique"])
        #expect(blocks[1].exerciseId == "slip_left" && blocks[1].exerciseVersion == 2)
        let stored = try #require(blocks[1].sets.first)
        #expect(stored.startedAt == at(70) && stored.endedAt == at(80))
        #expect(stored.validReps == 1 && stored.faultyReps == 1 && stored.incompleteReps == 1 && stored.plannedReps == 10 && stored.belowTarget)
        let attempts = stored.attempts.sorted { $0.index < $1.index }
        #expect(attempts.map(\.outcome) == ["valid", "faulty", "incomplete"])
        #expect(attempts[1].faults == ["guard_dropped"] && attempts[1].durationMs == 800)
    }

    /// AC-11.2: engine records are insert-only. Their properties have no public setter (compile time); a record
    /// emitted again with the same id, even with other values, leaves the stored one as it was.
    @Test func anEngineRecordIsWrittenOnce() throws {
        let container = try SoloStore.container(inMemory: true)
        let recorder = SessionRecorder(context: container.mainContext, info: Self.info)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = ids(4)
        try recorder.write(.session(id: id[0], workoutId: "w", status: .active, warmupSkipped: false), now: now, view: "side", activeMs: 0)
        try recorder.write(.rep(id: id[1], setId: id[2], outcome: .valid, faults: [], durationMs: 700, counted: true), now: now, view: "side", activeMs: 0)
        try recorder.write(.rep(id: id[1], setId: id[2], outcome: .faulty, faults: ["x"], durationMs: 1, counted: true), now: now, view: "side", activeMs: 0)
        let set = SessionRecord.set(id: id[2], blockId: id[3], index: 0, validReps: 1, faultyReps: 0, attempts: 1, target: nil,
                                    belowTarget: false, mode: nil)
        try recorder.write(set, now: now, view: "side", activeMs: 0)
        try recorder.write(.set(id: id[2], blockId: id[3], index: 0, validReps: 9, faultyReps: 9, attempts: 18, target: nil,
                                belowTarget: true, mode: nil), now: now, view: "side", activeMs: 0)
        let sets = try container.mainContext.fetch(FetchDescriptor<StoredSet>())
        let attempts = try container.mainContext.fetch(FetchDescriptor<StoredAttempt>())
        #expect(sets.count == 1 && sets.first?.validReps == 1 && sets.first?.view == "side")
        #expect(attempts.count == 1 && attempts.first?.outcome == "valid")
    }
}
