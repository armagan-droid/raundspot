import Foundation
import SwiftData

/// The user's rights over the local data (specs/10 "Kullanıcı hakları").
enum DataPortability {
    /// Fields of each exported object, exactly (AC-10.4: the schema is strict).
    static let fields: [String: Set<String>] = [
        "root": ["exportVersion", "exportedAt", "profile", "sessions"],
        "profile": ["id", "createdAt", "language", "stance", "level", "goal", "weightKg", "heightCm", "adultConfirmedAt",
                    "disclaimerShownVersion", "healthScreeningShownAt", "camera", "faultCueVoice", "resultTones", "techniqueTempo",
                    "reflexLevel", "sportPack"],
        "session": ["id", "workoutId", "workoutVersion", "sport", "startedAt", "endedAt", "status", "warmupSkipped", "activeMs",
                    "energyKcal", "energyMethod", "healthKitWorkoutUUID", "stance", "appVersion", "degradations", "blocks"],
        "block": ["id", "position", "kind", "exerciseId", "exerciseVersion", "catalogId", "catalogVersion", "level", "status", "sets"],
        "set": ["id", "setIndex", "startedAt", "endedAt", "plannedReps", "validReps", "faultyReps", "incompleteReps", "view",
                "belowTarget", "attempts", "trials"],
        "attempt": ["id", "index", "outcome", "durationMs", "faults"],
        "trial": ["id", "index", "comboId", "comboIndex", "strikeId", "isFeint", "cueAtMs", "result", "responseExerciseId",
                  "preferred", "reactionMs", "rtApproximate", "faults"],
    ]

    /// `exportVersion: 1` JSON of the profile and every session (specs/10, specs/11): no landmark, no image.
    @MainActor static func export(_ context: ModelContext, now: Date = Date()) throws -> Data {
        let iso = ISO8601DateFormatter()
        func d(_ x: Date?) -> Any { x.map { iso.string(from: $0) } ?? NSNull() }
        func o(_ x: Any?) -> Any { x ?? NSNull() }
        let profile: Any = try context.fetch(FetchDescriptor<Profile>()).first.map { p in
            [
                "id": p.id.uuidString, "createdAt": d(p.createdAt), "language": p.language, "stance": p.stance, "level": p.level,
                "goal": p.goal, "weightKg": o(p.weightKg), "heightCm": o(p.heightCm), "adultConfirmedAt": d(p.adultConfirmedAt),
                "disclaimerShownVersion": o(p.disclaimerShownVersion), "healthScreeningShownAt": d(p.healthScreeningShownAt),
                "camera": p.camera, "faultCueVoice": p.faultCueVoice, "resultTones": p.resultTones, "techniqueTempo": p.techniqueTempo,
                "reflexLevel": p.reflexLevel, "sportPack": p.sportPack,
            ] as [String: Any]
        } ?? NSNull()
        let sessions = try context.fetch(FetchDescriptor<StoredSession>(sortBy: [SortDescriptor(\.startedAt)])).map { s -> [String: Any] in
            [
                "id": s.id.uuidString, "workoutId": s.workoutId, "workoutVersion": o(s.workoutVersion), "sport": s.sport,
                "startedAt": d(s.startedAt), "endedAt": d(s.endedAt), "status": s.status, "warmupSkipped": s.warmupSkipped,
                "activeMs": s.activeMs, "energyKcal": o(s.energyKcal), "energyMethod": o(s.energyMethod),
                "healthKitWorkoutUUID": o(s.healthKitWorkoutUUID?.uuidString), "stance": s.stance, "appVersion": s.appVersion,
                "degradations": s.degradations,
                "blocks": s.blocks.sorted { $0.position < $1.position }.map { b -> [String: Any] in
                    [
                        "id": b.id.uuidString, "position": b.position, "kind": b.kind, "exerciseId": o(b.exerciseId),
                        "exerciseVersion": o(b.exerciseVersion), "catalogId": o(b.catalogId), "catalogVersion": o(b.catalogVersion),
                        "level": o(b.level), "status": b.status,
                        "sets": b.sets.sorted { $0.setIndex < $1.setIndex }.map { st -> [String: Any] in
                            [
                                "id": st.id.uuidString, "setIndex": st.setIndex, "startedAt": d(st.startedAt), "endedAt": d(st.endedAt),
                                "plannedReps": o(st.plannedReps), "validReps": st.validReps, "faultyReps": st.faultyReps,
                                "incompleteReps": st.incompleteReps, "view": st.view, "belowTarget": st.belowTarget,
                                "attempts": st.attempts.sorted { $0.index < $1.index }.map { a -> [String: Any] in
                                    ["id": a.id.uuidString, "index": a.index, "outcome": a.outcome, "durationMs": a.durationMs, "faults": a.faults]
                                },
                                "trials": st.trials.sorted { $0.index < $1.index }.map { t -> [String: Any] in
                                    [
                                        "id": t.id.uuidString, "index": t.index, "comboId": o(t.comboId), "comboIndex": o(t.comboIndex),
                                        "strikeId": t.strikeId, "isFeint": t.isFeint, "cueAtMs": t.cueAtMs, "result": t.result,
                                        "responseExerciseId": o(t.responseExerciseId), "preferred": o(t.preferred),
                                        "reactionMs": o(t.reactionMs), "rtApproximate": t.rtApproximate, "faults": t.faults,
                                    ]
                                },
                            ]
                        },
                    ]
                },
            ]
        }
        let root: [String: Any] = ["exportVersion": 1, "exportedAt": iso.string(from: now), "profile": profile, "sessions": sessions]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// "Tüm verilerimi sil" (AC-10.3): every stored object; the app is back at its first launch (no profile).
    @MainActor static func deleteAll(_ context: ModelContext) throws {
        // one by one, children first: a batch delete trips over the relationships' inverses
        for t in try context.fetch(FetchDescriptor<StoredReflexTrial>()) { context.delete(t) }
        for a in try context.fetch(FetchDescriptor<StoredAttempt>()) { context.delete(a) }
        for s in try context.fetch(FetchDescriptor<StoredSet>()) { context.delete(s) }
        for b in try context.fetch(FetchDescriptor<StoredBlock>()) { context.delete(b) }
        for s in try context.fetch(FetchDescriptor<StoredSession>()) { context.delete(s) }
        for p in try context.fetch(FetchDescriptor<Profile>()) { context.delete(p) }
        try context.save()
        // no preferences or caches outside the store today (specs/10; the CI privacy check guards that)
    }
}
