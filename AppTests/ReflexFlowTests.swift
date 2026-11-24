import Foundation
import SoloCapture
import SoloEngine
import SwiftData
import Testing
@testable import GymSpotSolo

/// A reflex block end to end on the fake camera (T4.4): cues planned, the machine ends the set at its cue
/// count, trials go to the store with their set, R3 has the summary.
@MainActor @Suite struct ReflexFlowTests {
    /// The guard pose, standing still: the lead-in of the slips snapshot sequence, looped.
    static func still() throws -> LandmarkSequence {
        var seq = try FakeCameraTests.slips()
        seq.frames = Array(seq.frames.prefix { $0.t < 1500 })
        return seq
    }

    @Test func aReflexSetOfMissedCues() async throws {
        let catalog = try #require(ExerciseCatalog.reflexCatalog())
        let container = try SoloStore.container(inMemory: true)
        let info = RecordContext(workoutVersion: nil, sport: "muay_thai", stance: "orthodox", appVersion: "test",
                                 blockKind: { _ in "reflex" }, catalog: { _ in ("muay_thai", 1, 1) })
        let recorder = SessionRecorder(context: container.mainContext, info: info)
        let clock = ManualClock(startMs: 9_000_000)
        let seq = try Self.still()
        let source = SequenceFrameSource(sequence: seq, clock: clock)
        let workout = Workout(id: "r", name: LocalizedText(tr: "r", en: "r"), estimatedMinutes: 2,
                              blocks: [.reflex(catalogId: "muay_thai", level: .fixed(1), cues: 2, restSec: 0, sets: 1)])
        let model = TrainingModel(workout: workout, packs: [:], recorder: recorder, source: source, clock: clock, reflexCatalog: catalog)
        defer { model.close() }
        #expect(model.reflexIsDraft)

        await model.confirmSpace()
        let step = 1000 / seq.fps
        func run(until done: () -> Bool, maxMs: Double) {
            var elapsed = 0.0
            while !done(), elapsed < maxMs {
                clock.advance(byMs: step)
                elapsed += step
                source.pump()
                model.tick()
            }
        }
        run(until: { model.state == .ready }, maxMs: 30_000)
        #expect(model.state == .ready)
        #expect(model.reflexCount?.total == 2)
        model.act(.start)
        run(until: { model.reflex != nil }, maxMs: 5000)
        #expect(model.reflex != nil)
        run(until: { model.state.isTerminal }, maxMs: 60_000)
        #expect(model.state == .sessionDone)

        let summary = try #require(model.reflexSummary)
        #expect(summary.total == 2 && summary.hits == 0)
        let trials = try container.mainContext.fetch(FetchDescriptor<StoredReflexTrial>())
        #expect(trials.count == 2 && trials.allSatisfy { $0.result == "missed" && $0.rtApproximate })  // no cue files yet: TTS
        #expect(trials.allSatisfy { $0.set != nil && $0.cueAtMs > 0 })
        let sets = try container.mainContext.fetch(FetchDescriptor<StoredSet>())
        #expect(sets.count == 1 && sets.first?.incompleteReps == 0 && sets.first?.trials.count == 2)
    }

    @Test func chosenLevelsAndCueCountsAreFixedBeforeTheSession() throws {
        let catalog = try #require(ExerciseCatalog.reflexCatalog())
        let w = Workout(id: "r", name: LocalizedText(tr: "r", en: "r"), estimatedMinutes: 2,
                        blocks: [.reflex(catalogId: "muay_thai", level: .chosen, cues: nil, restSec: 60, sets: 3),
                                 .reflex(catalogId: "muay_thai", level: .fixed(1), cues: 15, restSec: 0, sets: 1)])
        let r = TrainingModel.resolveReflexBlocks(w, catalog: catalog, chosen: 4)
        #expect(r.blocks[0] == .reflex(catalogId: "muay_thai", level: .fixed(4), cues: 24, restSec: 60, sets: 3))
        #expect(r.blocks[1] == w.blocks[1])
    }

    @Test func levelCardsInPlainWords() throws {
        let catalog = try #require(ExerciseCatalog.reflexCatalog())
        let one = LevelPicker.describe(catalog.level(1)!), four = LevelPicker.describe(catalog.level(4)!)
        #expect(!one.isEmpty && one != four)
        #expect(four.contains("10"))
    }
}
