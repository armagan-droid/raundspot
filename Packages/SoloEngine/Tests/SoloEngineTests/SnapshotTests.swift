import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// End-to-end snapshots (specs/03, T2.5) and the AC-4.3 snapshot part: the
// specs/04 metric functions over synthetic sequences, reduced to vision19.

private func slip(_ s: Double) -> SyntheticRep<EvaderParams> { SyntheticRep(EvaderParams(slip: s), durationMs: 700) }

@Suite("Snapshots") struct SnapshotTests {
    @Test func frontView2DMetricsOnSlipsAndADuck() throws {
        try Snapshots.check(.init(
            name: "snap_front_2d_slips", rulePackFile: "fixtures/snapshots/packs/snap_front_2d.json",
            setup: ExerciseSetup(view: .front, nearSide: .left)) {
                var seq = evaderSequence(
                    exerciseId: "snap_front_2d",
                    reps: [slip(25), slip(-25), slip(15), SyntheticRep(EvaderParams(slip: 25, guardDrop: 1), durationMs: 900),
                           SyntheticRep(EvaderParams(kneeAngle: 110, torsoLean: 25), durationMs: 900), slip(30)],
                    start: EvaderParams(dropSide: .right), options: SequenceOptions(noise: 0.003, seed: 11))
                seq = toVision19(seq)
                return seq
            })
    }

    @Test func sideView2DLeanBack() throws {
        try Snapshots.check(.init(
            name: "snap_side_2d_lean_back", rulePackFile: "fixtures/snapshots/packs/snap_side_2d.json",
            setup: ExerciseSetup(view: .side, nearSide: .left),
            cuesEnabled: [CueSwitch(fromT: 0, enabled: true), CueSwitch(fromT: 6000, enabled: false)]) {
                let reps = [30.0, 15, 40, 70, 35].map { SyntheticRep(FighterParams(torsoLean: $0), durationMs: 1200) }
                return toVision19(fighterSequence(exerciseId: "snap_side_2d", reps: reps, start: FighterParams(kneeAngle: 175),
                                                  options: SequenceOptions(facing: .left, noise: 0.002, seed: 5)), world: false)
            })
    }

    @Test func sourceSquatEndToEnd() throws {
        try Snapshots.check(.init(
            name: "source_squat_front", rulePackFile: "exercises/source/squat.json",
            setup: ExerciseSetup(view: .front, nearSide: .left)) {
                squatSequence(view: .front, reps: [squatRep(kneeAngle: 120), squatRep(kneeAngle: 92, valgus: 0.25),
                                                   squatRep(kneeAngle: 90, valgus: 0.25)],
                              options: SequenceOptions(noise: 0.002, seed: 9))
            })
    }
}

@Suite("Engine case format (specs/03)") struct EngineCaseFormatTests {
    private func outcome() throws -> EngineOutcome {
        let loaded = try Repo.load("squat")
        let seq = squatSequence(view: .front, reps: [squatRep(kneeAngle: 120)])
        return EngineCase.run(loaded, seq, setup: ExerciseSetup(view: .front, nearSide: .left))
    }

    @Test func roundTripsThroughJSON() throws {
        let o = try outcome()
        let c = EngineCase(origin: JSONObject([("source", ["repo": "armagan-droid/gymspot", "commit": "c2fe3fd"])]),
                           rulePack: "squat", rulePackVersion: 1, rulePackFile: nil,
                           setup: ExerciseSetup(view: .ambiguous, nearSide: .right), options: ExerciseEngineOptions(safetyPause: false),
                           cuesEnabled: [CueSwitch(fromT: 100, enabled: false)], sequence: "sequences/x.json", expected: o)
        let back = try EngineCase(json: JSONValue.parse(c.json.serialized()))
        #expect(back == c)
        #expect(EngineCase.differences(expected: c.expected, actual: back.expected).isEmpty)
    }

    @Test func eventsCarryFrameTimeAndFields() throws {
        let o = try outcome()
        let json = o.json
        let completed = json["events"]!.arrayValue!.first { $0["type"] == "REP_COMPLETED" }!
        #expect(completed.objectValue!.keys == ["frame", "t", "type", "outcome", "faults", "durationMs"])
        #expect(completed["faults"] == ["insufficient_depth"])
        #expect(json["metrics"]!["every"] == 10)
        #expect(json["metrics"]!["values"]![1]!["frame"] == 10)
        #expect(json["repStates"]!.arrayValue!.count == o.repStates.count)
    }

    @Test func differencesFollowTheEqualityRules() throws {
        let o = try outcome()
        var nudged = o
        nudged.metrics[1].values[0].value += 1e-12  // within 1e-9
        #expect(EngineCase.differences(expected: o, actual: nudged).isEmpty)
        nudged.metrics[1].values[0].value += 1e-3
        #expect(EngineCase.differences(expected: o, actual: nudged).count == 1)
        var moved = o
        moved.events[0].frame += 1
        #expect(EngineCase.differences(expected: o, actual: moved).first?.hasPrefix("events[0]") == true)
        var state = o
        let first = o.repStates[0]
        state.repStates[0] = first == .inRep ? .waiting : .inRep
        #expect(EngineCase.differences(expected: o, actual: state)
            == ["repStates[0]: expected \(first.rawValue), got \(state.repStates[0].rawValue)"])
        var nan = o
        nan.metrics[0].values[0].value = .nan
        var nan2 = nan
        nan2.metrics[0].values[0].value = .nan
        #expect(EngineCase.differences(expected: nan, actual: nan2).isEmpty)
        #expect(!EngineCase.differences(expected: o, actual: nan).isEmpty)
    }

    @Test func cueSwitchesApplyFromTheirTime() throws {
        let loaded = try Repo.load("squat")
        let seq = squatSequence(view: .front, reps: [squatRep(kneeAngle: 120), squatRep(kneeAngle: 120), squatRep(kneeAngle: 120)])
        let setup = ExerciseSetup(view: .front, nearSide: .left)
        func cues(_ s: [CueSwitch]) -> Int {
            EngineCase.run(loaded, seq, setup: setup, cuesEnabled: s).events.count { if case .faultDetected = $0.event { true } else { false } }
        }
        let all = cues([])
        #expect(all > 0)
        #expect(cues([CueSwitch(fromT: 0, enabled: false)]) == 0)
        #expect(cues([CueSwitch(fromT: 0, enabled: false), CueSwitch(fromT: 4000, enabled: true)]) < all)
    }
}
