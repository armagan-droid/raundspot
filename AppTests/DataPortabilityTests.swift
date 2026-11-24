import Foundation
import SoloEngine
import SwiftData
import Testing
@testable import GymSpotSolo

/// specs/10 "Kullanıcı hakları": AC-10.3 (delete everything) and AC-10.4 (strict export, no landmarks).
@MainActor @Suite struct DataPortabilityTests {
    func filled() throws -> ModelContainer {
        let c = try SoloStore.container(inMemory: true)
        let p = Profile(createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        p.weightKg = 70
        c.mainContext.insert(p)
        let info = RecordContext(workoutVersion: nil, sport: "muay_thai", stance: "orthodox", appVersion: "t",
                                 blockKind: { _ in "reflex" }, catalog: { _ in ("muay_thai", 1, 1) })
        let r = SessionRecorder(context: c.mainContext, info: info)
        let ids = (0..<5).map { _ in UUID().uuidString }
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        try r.write(.session(id: ids[0], workoutId: "refleks", status: .active, warmupSkipped: false), now: now, view: "front", activeMs: 0)
        r.writeReflexTrial(ReflexTrialRecord(index: 0, comboId: nil, comboIndex: nil, strikeId: "jab", isFeint: false, cueAt: 5000,
                                             result: .correct, responseExerciseId: "slip_right", preferred: true, reactionMs: 400,
                                             rtApproximate: true, faults: []), setId: ids[2], at: now)
        try r.write(.rep(id: ids[4], setId: ids[2], outcome: .valid, faults: [], durationMs: 700, counted: true), now: now, view: "front", activeMs: 0)
        try r.write(.set(id: ids[2], blockId: ids[1], index: 0, validReps: 0, faultyReps: 0, attempts: 1, target: 1, belowTarget: false, mode: nil),
                    now: now, view: "front", activeMs: 1000)
        try r.write(.block(id: ids[1], sessionId: ids[0], index: 0, exerciseId: nil, exerciseVersion: nil, status: .done), now: now, view: "front", activeMs: 1000)
        try r.write(.session(id: ids[0], workoutId: "refleks", status: .done, warmupSkipped: false), now: now, view: "front", activeMs: 1000)
        return c
    }

    @Test func theExportFollowsTheSchemaAndHoldsNoPicture() throws {
        let c = try filled()
        let data = try DataPortability.export(c.mainContext)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        func keys(_ o: Any?, _ kind: String) {
            guard let d = o as? [String: Any] else { return }
            #expect(Set(d.keys) == DataPortability.fields[kind], "\(kind)")
        }
        keys(root, "root")
        #expect(root["exportVersion"] as? Int == 1)
        keys(root["profile"], "profile")
        let session = try #require((root["sessions"] as? [[String: Any]])?.first)
        keys(session, "session")
        let block = try #require((session["blocks"] as? [[String: Any]])?.first)
        keys(block, "block")
        let set = try #require((block["sets"] as? [[String: Any]])?.first)
        keys(set, "set")
        keys((set["attempts"] as? [Any])?.first, "attempt")
        keys((set["trials"] as? [Any])?.first, "trial")
        #expect((set["trials"] as? [Any])?.count == 1 && (set["attempts"] as? [Any])?.count == 1)
        let text = String(decoding: data, as: UTF8.self)
        for word in ["landmark", "image", "frames", "pixel", "video"] { #expect(!text.contains(word), "\(word)") }
    }

    @Test func deletingEverythingLeavesAnEmptyStore() throws {
        let c = try filled()
        try DataPortability.deleteAll(c.mainContext)
        let ctx = c.mainContext
        #expect(try ctx.fetchCount(FetchDescriptor<Profile>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<StoredSession>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<StoredBlock>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<StoredSet>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<StoredAttempt>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<StoredReflexTrial>()) == 0)
        // no profile: the app opens on onboarding again
        #expect(AppStart.needsOnboarding(profiles: try ctx.fetch(FetchDescriptor<Profile>())))
    }

    /// AC-10.7: the health questions' answers have no place in the store; only that they were shown does.
    @Test func healthAnswersAreNotStored() {
        let entity = SoloStore.schema.entities.first { $0.name == "Profile" }
        let names = Set(entity?.properties.map(\.name) ?? [])
        #expect(names.contains("healthScreeningShownAt"))
        #expect(names.filter { $0.lowercased().contains("answer") || $0.lowercased().contains("screeningresult") }.isEmpty)
        #expect(names == DataPortability.fields["profile"])
    }
}
