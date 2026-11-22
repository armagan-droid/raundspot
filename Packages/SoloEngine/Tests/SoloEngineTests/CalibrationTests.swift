import Testing
@testable import SoloEngine
import SoloEngineTesting

// Port of the source `engine/test/calibration.test.ts` (commit c2fe3fd), plus
// the JSON writer the report and fixtures use.

private let squatJSON = try! Repo.sourceJSON("squat")

private func labeled(_ reps: [SyntheticRep<SquatParams>], leadInMs: Double = 5000) -> LandmarkSequence {
    var s = squatSequence(view: .front, reps: reps, options: SequenceOptions(noise: 0.002, seed: 3, leadInMs: leadInMs))
    s.source = .calibration
    return s
}

private let clean = labeled([
    squatRep(kneeAngle: 90, label: RepLabel(outcome: .valid, faults: [])),
    squatRep(kneeAngle: 120, label: RepLabel(outcome: .faulty, faults: ["insufficient_depth"])),
    squatRep(kneeAngle: 92, label: RepLabel(outcome: .valid, faults: [])),
])

private func summary(_ r: Calibration.SweepResult) -> CalibrationSummary? {
    if case .summary(let s) = r { s } else { nil }
}

@Suite("Calibration.evaluate (ref 09 pilot metrics)") struct CalibrationEvaluateTests {
    @Test func predictionsAreAlignedWithLabelsAttemptByAttempt() throws {
        let r = try Calibration.evaluate(squatJSON, clean)
        #expect(r.attempts.map { [$0.predicted?.outcome, $0.label?.outcome] } == [[.valid, .valid], [.faulty, .faulty], [.valid, .valid]])
        #expect(r.labeledCount == 2)
        #expect(r.predictedCount == 2)
        #expect(r.cues == [CueComparison(attempt: 1, faultId: "insufficient_depth", correct: true)])
    }

    @Test func aMislabeledRepLowersTheCountAccuracy() throws {
        var wrong = clean
        wrong.labels![1] = RepLabel(outcome: .valid, faults: [])
        let s = Calibration.summarize([try Calibration.evaluate(squatJSON, wrong)])
        #expect(Swift.abs(s.countAccuracy - (1 - 1.0 / 3)) < 0.005)
        #expect(s.falseAlarmRate == 1)  // the cue's fault is not in the label
    }

    @Test func perfectAgreement() throws {
        let s = Calibration.summarize([try Calibration.evaluate(squatJSON, clean)])
        #expect(s.countAccuracy == 1 && s.falseAlarmRate == 0 && s.sequences == 1 && s.attempts == 3)
        #expect(s.faults["insufficient_depth"] == FaultStats(hits: 1, misses: 0, falseAlarms: 0))
        #expect(s.meetsTargets)
    }

    @Test func aLabeledFaultTheEngineMissesIsAMiss() throws {
        let missed = labeled([squatRep(kneeAngle: 90, label: RepLabel(outcome: .valid, faults: ["knee_valgus"]))])
        #expect(Calibration.summarize([try Calibration.evaluate(squatJSON, missed)]).faults["knee_valgus"]
            == FaultStats(hits: 0, misses: 1, falseAlarms: 0))
    }

    @Test func sequencesWithoutLabelsAreRejected() {
        var noLabels = clean
        noLabels.labels = nil
        #expect(throws: CalibrationError.noLabels) { try Calibration.evaluate(squatJSON, noLabels) }
    }

    @Test func theTemplateMustRunOnTheSequencesSkeleton() {
        // a world-angle squat cannot be evaluated on a 2D-only vision19 recording (specs/03)
        let reduced = toVision19(clean, world: false)
        #expect {
            try Calibration.evaluate(squatJSON, reduced)
        } throws: { e in
            guard case CalibrationError.invalidRulePack(let m) = e else { return false }
            return m.contains("world")
        }
    }
}

@Suite("Calibration threshold tools") struct CalibrationSweepTests {
    @Test func withParameterChangesARepZoneValueOrAFaultThreshold() throws {
        #expect(try Calibration.withParameter(squatJSON, path: "rep.target.enter", value: 95)["rep"]?["target"]?["enter"] == 95)
        let changed = try Calibration.withParameter(squatJSON, path: "faults.knee_valgus.threshold", value: 0.2)
        #expect(changed["faults"]?[1]?["check"]?.stringValue == "during_rep: knee_valgus_l > 0.15 or knee_valgus_r > 0.2")
        #expect(throws: CalibrationError.noFault("nope")) { try Calibration.withParameter(squatJSON, path: "faults.nope.threshold", value: 1) }
        #expect(throws: CalibrationError.noParameter("rep.nothing")) { try Calibration.withParameter(squatJSON, path: "rep.nothing", value: 1) }
    }

    @Test func lastNumberFollowsTheSourceRegex() {
        func last(_ s: String) -> String? {
            Calibration.lastNumber(in: s).map { r in String(decoding: Array(s.utf16)[r], as: UTF16.self) }
        }
        #expect(last("at_turn: a > -1.5 and b < 20") == "20")
        #expect(last("at_turn: a > -1.5") == "-1.5")
        #expect(last("at_turn: a > 1.") == "1")
        #expect(last("at_turn: head_l2 > x") == "2")  // no word boundary, as the source
        #expect(last("at_turn: a > b") == nil)
    }

    @Test func sweepReportsMetricsPerCandidateValue() throws {
        // a 112° rep labeled as a valid full squat: only a looser depth threshold counts it
        let seq = labeled([
            squatRep(kneeAngle: 90, label: RepLabel(outcome: .valid, faults: [])),
            squatRep(kneeAngle: 112, label: RepLabel(outcome: .valid, faults: [])),
        ])
        let base = try Calibration.withParameter(squatJSON, path: "rep.target.exit", value: 125)  // room for a deeper target zone
        let rows = try Calibration.sweep(base, [seq], path: "rep.target.enter", values: [100, 115])
        #expect(rows.map(\.value) == [100, 115])
        #expect(summary(rows[0].result)!.countAccuracy < 1)
        // the depth fault threshold must move with the zone for the 112° rep to be valid
        let moved = try Calibration.withParameter(base, path: "faults.insufficient_depth.threshold", value: 115)
        let both = try Calibration.sweep(moved, [seq], path: "rep.target.enter", values: [115])
        #expect(summary(both[0].result)!.countAccuracy == 1)
    }

    @Test func candidateValuesThatBreakTheRulePackAreReportedNotThrown() throws {
        let rows = try Calibration.sweep(squatJSON, [clean], path: "rep.target.enter", values: [100, 140])  // 140 > target.exit (110)
        #expect(summary(rows[0].result) != nil)
        #expect(rows[1].value == 140)
        guard case .error(let message) = rows[1].result else { Issue.record("no error"); return }
        #expect(message.contains("invalid rule pack"))
    }
}

@Suite("JSON writer") struct JSONWriterTests {
    @Test func numbersFollowJavaScript() {
        let cases: [(Double, String)] = [
            (0, "0"), (-0.0, "0"), (1, "1"), (-2, "-2"), (1.5, "1.5"), (100, "100"), (0.1 + 0.2, "0.30000000000000004"),
            (1e20, "100000000000000000000"), (1e21, "1e+21"), (1.2345e22, "1.2345e+22"), (0.000001, "0.000001"),
            (1e-7, "1e-7"), (2.5e-7, "2.5e-7"), (5e-324, "5e-324"), (1.7976931348623157e308, "1.7976931348623157e+308"),
            (1666.6666666666667, "1666.6666666666667"), (123456789012, "123456789012"), (0.5625, "0.5625"),
        ]
        for (x, s) in cases { #expect(JSONValue.jsNumber(x) == s, "\(x)") }
    }

    @Test func stringsAndStructure() {
        let v: JSONValue = ["a": "x\"y\\\n\u{01}ü", "b": [1, true, .null], "c": [:], "d": []]
        #expect(v.serialized() == #"{"a":"x\"y\\\n\u0001ü","b":[1,true,null],"c":{},"d":[]}"#)
        #expect(JSONValue.number(.nan).serialized() == "null")
        #expect(v.serialized(indent: 2) == """
            {
              "a": "x\\"y\\\\\\n\\u0001ü",
              "b": [
                1,
                true,
                null
              ],
              "c": {},
              "d": []
            }
            """)
    }

    @Test func roundTripThroughTheParser() throws {
        let v: JSONValue = ["k": [0.1, -3e-9, 12345.678, "s"], "n": .null]
        #expect(try JSONValue.parse(v.serialized()) == v)
    }

    @Test func sequencesRoundTrip() throws {
        let v1 = clean
        #expect(try LandmarkSequence.parse(v1.json).get() == v1)
        var v2 = toVision19(clean)
        v2.imageAspect = 0.5625
        v2.frames = v2.frames.map { var f = $0; f.imageAspect = 0.5625; return f }
        let back = try LandmarkSequence.parse(JSONValue.parse(v2.json.serialized())).get()
        #expect(back.skeleton == .vision19 && back.hasWorld && back.imageAspect == 0.5625 && back.labels == v2.labels)
        // 3D-missing eyes and ears of a vision19 joint set are written unseen
        #expect(back.frames[0][world: .leftEar].visibility == 0)
        #expect(back.frames[0][image: .leftEar] == v2.frames[0][image: .leftEar])
        let noWorld = toVision19(clean, world: false)
        let parsed = try LandmarkSequence.parse(noWorld.json).get()
        #expect(!parsed.hasWorld && parsed.frames == noWorld.frames)
    }
}
