import Foundation
import Testing
@testable import SoloEngine
import SoloEngineTesting

// specs/05 reflex loop (T4.2): AC-5.1, AC-5.2, AC-5.4, AC-5.5, AC-5.6.

private func catalog(_ stance: Stance = .orthodox) throws -> (ReflexCatalog, ResolvedCatalog) {
    let c = try ReflexCatalog.parse(Repo.read(Repo.exercises.appendingPathComponent("reflex/muay_thai.json"))).get()
    return (c, c.resolved(for: stance))
}

private let responsePacks: [String: LoadedRulePack] = {
    var out: [String: LoadedRulePack] = [:]
    for id in ["slip_left", "slip_right", "duck", "bob_weave_left", "bob_weave_right"] {
        let j = try! Repo.read(Repo.exercises.appendingPathComponent("\(id).json"))
        out[id] = try! RulePackLoader.load(j, capabilities: .vision19TwoD).get()
    }
    return out
}()

// MARK: - AC-5.2 classification table

@Suite("Reflex — classification (AC-5.2)") struct ReflexClassificationTests {
    let cat = try! catalog().1
    var jab: ResolvedCatalog.Strike { cat.strikes.first { $0.id == "jab" }! }
    var leadHook: ResolvedCatalog.Strike { cat.strikes.first { $0.id == "lead_hook" }! }
    let cue = 10_000.0

    func c(_ id: String, _ o: RepOutcome, _ faults: [String] = [], at: Double = 10_400, turn: Double = 1) -> ReflexCandidate {
        ReflexCandidate(exerciseId: id, outcome: o, faults: faults, moveAt: at, turnProgress: turn)
    }

    func classify(_ s: ResolvedCatalog.Strike?, _ cs: [ReflexCandidate]) -> ReflexClassification {
        classifyReflexTrial(strike: s, cueAt: cue, candidates: cs, catalog: cat)
    }

    @Test func eachResult() {
        #expect(classify(jab, [c("slip_right", .valid)]).result == .correct)
        #expect(classify(jab, [c("slip_right", .valid, ["guard_dropped"])]).result == .correctFaulty)
        #expect(classify(jab, [c("slip_right", .faulty, ["neck_only"])]).result == .correctFaulty)
        #expect(classify(jab, [c("duck", .valid)]).result == .wrong)
        #expect(classify(jab, []).result == .missed)
        #expect(classify(jab, [c("slip_right", .valid, at: 9_990)]).result == .early)
        #expect(classify(jab, [c("slip_right", .valid, at: 10_100)]).result == .early)  // < 120 ms
        #expect(classify(jab, [c("slip_right", .valid, at: 10_120)]).result == .correct)
        #expect(classify(jab, [c("slip_right", .incomplete)]).result == .partial)
        #expect(classify(nil, []).result == .feintOk)
        #expect(classify(nil, [c("duck", .incomplete)]).result == .feintBitten)
    }

    @Test func thePreferredResponseIsTracked() {
        #expect(classify(jab, [c("slip_right", .valid)]).preferred == true)
        let inside = classify(jab, [c("slip_left", .valid)])
        #expect(inside.result == .correct && inside.preferred == false)
        #expect(classify(jab, [c("duck", .valid)]).preferred == nil)
    }

    /// specs/05 example: a dip that does not weave is a faulty bob & weave but a valid duck → duck, accepted.
    @Test func specificityAndTheBobWeaveExample() {
        let noWeave = classify(leadHook, [c("bob_weave_left", .faulty, ["no_weave"]), c("duck", .valid)])
        #expect(noWeave.result == .correct && noWeave.chosen?.exerciseId == "duck" && noWeave.preferred == false)
        // both valid: bob & weave is more specific than duck
        let weave = classify(leadHook, [c("duck", .valid, turn: 1.5), c("bob_weave_left", .valid, turn: 1.1)])
        #expect(weave.chosen?.exerciseId == "bob_weave_left" && weave.preferred == true)
        // and more specific than a slip to the same side
        let slip = classify(leadHook, [c("slip_left", .valid, turn: 2), c("bob_weave_left", .valid)])
        #expect(slip.chosen?.exerciseId == "bob_weave_left")
        // no order between the two slips: the deeper turn wins
        let tie = classify(jab, [c("slip_left", .valid, turn: 1.2), c("slip_right", .valid, turn: 1.4)])
        #expect(tie.chosen?.exerciseId == "slip_right")
        // valid before faulty
        let mixed = classify(jab, [c("slip_right", .faulty, ["neck_only"], turn: 3), c("slip_left", .valid, turn: 1)])
        #expect(mixed.chosen?.exerciseId == "slip_left" && mixed.result == .correct)
    }
}

// MARK: - The loop on a synthetic boxer

/// A front-view boxer that answers each cue the way `respond` says, at 30 fps.
private struct Boxer {
    struct Move { var start: Double; var duration: Double; var to: EvaderParams }

    let reflex: ReflexSet
    var t: Double
    var moves: [Move] = []
    var commands: [ReflexCommand] = []
    var cues: [(key: String, at: Double)] = []
    let fps = 30.0

    init(level: ReflexCatalog.Level, cat: ResolvedCatalog, cues: Int? = nil, seed: UInt64 = 7, t0: Double = 100_000,
         options: ReflexSet.Options = .init(), packs: [String: LoadedRulePack] = responsePacks) {
        reflex = ReflexSet(catalog: cat, level: level, packs: packs, cues: cues, seed: seed, now: t0, options: options)
        t = t0
    }

    func pose(at t: Double) -> EvaderParams {
        for m in moves where t >= m.start && t < m.start + m.duration {
            let p = (t - m.start) / m.duration
            return EvaderParams.lerp(EvaderParams(), m.to, (1 - cos(2 * .pi * p)) / 2)
        }
        return EvaderParams()
    }

    static func frame(_ p: EvaderParams, _ t: Double) -> Frame {
        toVision19(evaderFrame(p, FrameOptions(view: .front, t: t)), world: false)
    }

    /// Runs frames until `ms` passes; `react` sees each new cue and may add moves.
    mutating func run(_ ms: Double, react: (_ key: String, _ cueAt: Double, inout [Move]) -> Void = { _, _, _ in }) {
        let end = t + ms
        while t < end, reflex.phase != .done, reflex.phase != .stopped {
            t += 1000 / fps
            let out = reflex.push(Self.frame(pose(at: t), t))
            commands += out
            for case .playCue(let key, let at) in out {
                cues.append((key, at))
                react(key, at, &moves)
            }
        }
    }

    var trials: [ReflexTrialRecord] { reflex.trials }
}

private let slipL = EvaderParams(slip: 25), slipR = EvaderParams(slip: -25)
private let duck = EvaderParams(kneeAngle: 110, torsoLean: 25)
private func weave(_ side: Double) -> EvaderParams { EvaderParams(slip: side, kneeAngle: 110, torsoLean: 25) }

/// The preferred answer of each strike, orthodox.
private func answer(_ key: String, at: Double) -> Boxer.Move? {
    switch key {
    case "strike.jab": Boxer.Move(start: at, duration: 700, to: slipR)
    case "strike.cross": Boxer.Move(start: at, duration: 700, to: slipL)
    case "strike.left_hook": Boxer.Move(start: at, duration: 1000, to: weave(20))
    case "strike.right_hook": Boxer.Move(start: at, duration: 1000, to: weave(-20))
    default: nil
    }
}

@Suite("Reflex — loop (AC-5.1, AC-5.4–AC-5.6)") struct ReflexLoopTests {
    let raw = try! catalog().0
    let cat = try! catalog().1

    /// A level-1 set answered with the preferred slip 300 ms after each cue: all correct.
    @Test func aLevelOneSetAnsweredWell() throws {
        var b = Boxer(level: raw.level(1)!, cat: cat, cues: 5)
        b.run(60_000) { key, at, moves in if let m = answer(key, at: at + 300) { moves.append(m) } }
        #expect(b.reflex.phase == .done)
        #expect(b.trials.count == 5)
        #expect(b.trials.allSatisfy { $0.result == .correct && $0.preferred == true }, "\(b.trials.map(\.result))")
        #expect(Set(b.cues.map(\.key)).isSubset(of: ["strike.jab", "strike.cross"]))
        #expect(b.commands.last == .setDone)
        // cues are scheduled ahead and spaced by the wait (2–4 s at level 1) plus the answer
        for (a, n) in zip(b.cues, b.cues.dropFirst()) { #expect(n.at - a.at >= 2000) }
    }

    @Test func theSameSeedGivesTheSameSetAndAnotherSeedAnother() {
        func run(_ seed: UInt64) -> ([String], [Double], [ReflexResult]) {
            var b = Boxer(level: raw.level(2)!, cat: cat, cues: 6, seed: seed)
            b.run(80_000) { key, at, moves in if let m = answer(key, at: at + 350) { moves.append(m) } }
            return (b.cues.map(\.key), b.cues.map(\.at), b.trials.map(\.result))
        }
        let a = run(42), again = run(42), other = run(43)
        #expect(a.0 == again.0 && a.1 == again.1 && a.2 == again.2)
        #expect(a.1 != other.1)
        #expect(a.0.count == 6)
    }

    @Test func noAnswerIsMissedAndAWrongOneIsWrong() {
        var b = Boxer(level: raw.level(1)!, cat: cat, cues: 2)
        var n = 0
        b.run(40_000) { _, at, moves in
            n += 1
            if n == 2 { moves.append(.init(start: at + 300, duration: 900, to: duck)) }
        }
        #expect(b.trials.map(\.result) == [.missed, .wrong])
        #expect(b.trials[0].reactionMs == nil && b.trials[1].reactionMs != nil && b.trials[1].responseExerciseId == "duck")
    }

    /// AC-5.5: moving during the wait delays the cue; a movement that starts when the cue is scheduled, before the
    /// sound is heard (100 ms output delay), confirms within 120 ms of the cue: early, no RT.
    @Test func movingBeforeTheCue() {
        var options = ReflexSet.Options()
        options.cueDelay = { _ in (100, false) }
        var b = Boxer(level: raw.level(1)!, cat: cat, cues: 1, options: options)
        // become ready, then slip 1.2 s into the wait (the wait is ≥ 2 s)
        b.run(1500)
        let readyAt = b.t
        b.moves.append(.init(start: readyAt + 1200, duration: 700, to: slipL))
        b.run(30_000) { key, at, moves in if let m = answer(key, at: at) { moves.append(m) } }
        #expect(b.commands.contains(.speak("reflex.wait_for_cue")))
        #expect((b.cues.first?.at ?? 0) > readyAt + 1900)
        #expect(b.trials.map(\.result) == [.early] && b.trials[0].reactionMs == nil)
    }

    /// AC-5.4: RT within one frame of the known movement start (raw metric crossing the confirmation threshold),
    /// and the smoothed confirmation alone lags more.
    @Test func reactionTimeIsWithinAFrame() throws {
        let delay = 25.0
        var options = ReflexSet.Options()
        options.cueDelay = { _ in (delay, false) }
        var b = Boxer(level: raw.level(1)!, cat: cat, cues: 4, options: options)
        let rt = 330.0
        b.run(60_000) { key, at, moves in if let m = answer(key, at: at + delay + rt) { moves.append(m) } }
        #expect(b.trials.count == 4)
        let slip = responsePacks["slip_right"]!
        let computer = try MetricComputer(pack: slip.pack)
        let counter = RepCounter(slip.pack.rep)
        for (trial, cue) in zip(b.trials, b.cues) {
            #expect(trial.cueAt == cue.at + delay)
            let id = trial.responseExerciseId ?? ""
            let pack = responsePacks[id]!
            let cpu = try MetricComputer(pack: pack.pack), rc = RepCounter(pack.pack.rep)
            // the known start: the raw metric of the continuous pose crosses the threshold
            let move = try #require(b.moves.first { $0.start >= cue.at })
            var lo = move.start, hi = move.start + move.duration / 2
            for _ in 0..<40 {
                let mid = (lo + hi) / 2
                let v = cpu.compute(Boxer.frame(b.pose(at: mid), mid), near: .left)[pack.pack.rep.metric]!
                if rc.isBeyondConfirm(v) { hi = mid } else { lo = mid }
            }
            let truth = hi - trial.cueAt
            let measured = try #require(trial.reactionMs)
            #expect(abs(measured - truth) <= 1000 / 30, "\(trial.strikeId): measured \(measured), truth \(truth)")
        }
        _ = (computer, counter)
    }

    @Test func theSmoothingCorrectionRemovesLag() throws {
        let pack = responsePacks["slip_right"]!
        let e = ExerciseEngine(pack, setup: ExerciseSetup(view: .front, nearSide: .left))
        let cpu = try MetricComputer(pack: pack.pack), rc = RepCounter(pack.pack.rep)
        let start = 2000.0, dur = 700.0
        func pose(_ t: Double) -> EvaderParams {
            guard t >= start, t < start + dur else { return EvaderParams() }
            return EvaderParams.lerp(EvaderParams(), slipR, (1 - cos(2 * .pi * (t - start) / dur)) / 2)
        }
        var smoothed: Double?, corrected: Double?
        var t = 0.0
        while t < 4000, smoothed == nil {
            t += 1000 / 30
            for te in e.push(Boxer.frame(pose(t), t)) where te.event == .repStarted {
                smoothed = te.t
                corrected = e.rawConfirmCrossing(confirmedAt: te.t)
            }
        }
        var lo = start, hi = start + dur / 2
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if rc.isBeyondConfirm(cpu.compute(Boxer.frame(pose(mid), mid), near: .left)[pack.pack.rep.metric]!) { hi = mid } else { lo = mid }
        }
        let s = try #require(smoothed), c = try #require(corrected)
        #expect(abs(c - hi) <= 1000 / 30)
        #expect(s - hi > abs(c - hi), "smoothed lag \(s - hi), corrected \(c - hi)")
    }

    /// AC-5.6: in a combo each window gets at most one attempt per engine; one slip answers one cue only.
    @Test func comboWindowsTakeOneAttemptEach() throws {
        var level = raw.level(3)!
        level.comboLen = 2...2
        level.comboGapMs = 900
        var b = Boxer(level: level, cat: cat, cues: 2)
        var first = true
        b.run(40_000) { key, at, moves in
            if first, let m = answer(key, at: at + 300) { moves.append(m) }
            first = false
        }
        #expect(b.cues.count == 2)
        #expect(b.cues[1].at - b.cues[0].at == 900)
        #expect(b.trials.map(\.comboIndex) == [0, 1] && b.trials[0].comboId == b.trials[1].comboId)
        #expect(b.trials[0].result == .correct)
        #expect(b.trials[1].result == .missed, "\(b.trials.map(\.result))")
    }

    @Test func feints() throws {
        var level = raw.level(4)!
        level.comboLen = 1...1
        level.comboGapMs = nil
        level.feintRate = 0.999
        var still = Boxer(level: level, cat: cat, cues: 2)
        still.run(40_000)
        #expect(still.trials.map(\.result) == [.feintOk, .feintOk] && still.trials.allSatisfy(\.isFeint))
        #expect(still.cues.allSatisfy { $0.key == "strike.stop" })
        var bitten = Boxer(level: level, cat: cat, cues: 1)
        bitten.run(40_000) { _, at, moves in moves.append(.init(start: at + 300, duration: 700, to: slipL)) }
        #expect(bitten.trials.map(\.result) == [.feintBitten])
    }

    /// AC-5.3 on the loop: a southpaw's jab is answered with slip_left (the mirror of slip_right).
    @Test func southpawAnswersMirror() throws {
        let south = try catalog(.southpaw).1
        var b = Boxer(level: raw.level(1)!, cat: south, cues: 3)
        b.run(60_000) { key, at, moves in
            moves.append(.init(start: at + 300, duration: 700, to: key == "strike.jab" ? slipL : slipR))
        }
        #expect(b.trials.allSatisfy { $0.result == .correct && $0.preferred == true }, "\(b.trials.map(\.result))")
    }
}

// MARK: - Summary and advice

@Suite("Reflex — summary and level advice") struct ReflexSummaryTests {
    func t(_ s: String, _ r: ReflexResult, rt: Double? = nil, pref: Bool? = nil, faults: [String] = [], feint: Bool = false) -> ReflexTrialRecord {
        ReflexTrialRecord(index: 0, comboId: nil, comboIndex: nil, strikeId: s, isFeint: feint, cueAt: 0, result: r, responseExerciseId: nil,
                          preferred: pref, reactionMs: rt, rtApproximate: false, faults: faults)
    }

    @Test func summary() {
        let s = ReflexSetSummary([
            t("jab", .correct, rt: 300, pref: true), t("jab", .correctFaulty, rt: 500, pref: false, faults: ["guard_dropped"]),
            t("cross", .wrong, rt: 400), t("cross", .missed), t("stop", .feintOk, feint: true),
        ])
        #expect(s.total == 5 && s.hits == 3)
        #expect(s.medianRtMs == 400 && s.p90RtMs == 500)
        #expect(s.byStrike["jab"] == .init(hits: 2, total: 2, medianRtMs: 400))
        #expect(s.byStrike["cross"] == .init(hits: 0, total: 2, medianRtMs: 400))
        #expect(s.byStrike["stop"] == nil && s.feints == 1 && s.feintsOk == 1)
        #expect(s.preferredRatio == 0.5 && s.mostFrequentFault == "guard_dropped")
    }

    @Test func advice() {
        let good = Array(repeating: t("jab", .correct, rt: 400), count: 10)
        #expect(ReflexLevelAdvice.advise(lastTwoSets: [good, good], windowMs: 1500) == .tryHigher)
        // fast enough is part of it: 60 % of a 600 ms window is 360 ms
        #expect(ReflexLevelAdvice.advise(lastTwoSets: [good, good], windowMs: 600) == nil)
        let bad = Array(repeating: t("jab", .missed), count: 10)
        #expect(ReflexLevelAdvice.advise(lastTwoSets: [bad, good], windowMs: 1500) == nil)  // 50 %
        #expect(ReflexLevelAdvice.advise(lastTwoSets: [bad, bad], windowMs: 1500) == .tryLower)
        #expect(ReflexLevelAdvice.advise(lastTwoSets: [good], windowMs: 1500) == nil)
    }

    @Test func randomIsSeeded() {
        var a = ReflexRandom(seed: 1), b = ReflexRandom(seed: 1)
        let xs = (0..<5).map { _ in a.unit() }
        #expect(xs == (0..<5).map { _ in b.unit() })
        #expect(xs.allSatisfy { $0 >= 0 && $0 < 1 })
        var c = ReflexRandom(seed: 9)
        #expect((0..<200).map { _ in c.int(1...3) }.allSatisfy { (1...3).contains($0) })
    }
}

// MARK: - AC-5.7 feedback and the audio timeline (T4.3)

/// A fake audio output: cue sounds and speech as time intervals.
private struct Timeline {
    var cues: [ClosedRange<Double>] = []
    var speech: [(key: String, at: ClosedRange<Double>)] = []

    mutating func record(_ out: [ReflexCommand], now: Double, cueMs: Double, speechMs: Double) {
        for c in out {
            switch c {
            case .playCue(_, let at): cues.append(at...(at + cueMs))
            case .speak(let k): speech.append((k, now...(now + speechMs)))
            default: break
            }
        }
    }

    /// No speech overlaps a cue or its 600 ms lead-in, and no two speeches overlap.
    func overlaps(guardMs: Double) -> [String] {
        var out: [String] = []
        for s in speech {
            for c in cues where s.at.lowerBound < c.upperBound && s.at.upperBound > c.lowerBound - guardMs {
                out.append("\(s.key) \(s.at) over cue \(c)")
            }
        }
        for (a, b) in zip(speech, speech.dropFirst()) where b.at.lowerBound < a.at.upperBound { out.append("\(a.key) and \(b.key)") }
        return out
    }
}

@Suite("Reflex — feedback and audio priority (AC-5.7)") struct ReflexFeedbackTests {
    let raw = try! catalog().0
    let cat = try! catalog().1

    /// Runs a boxer on a fake audio output; `react` answers cues.
    fileprivate func run(_ level: ReflexCatalog.Level, cues: Int, seed: UInt64 = 3, packs: [String: LoadedRulePack] = responsePacks,
             options: ReflexSet.Options = .init(), ms: Double = 90_000,
             react: @escaping (_ n: Int, _ key: String, _ at: Double) -> Boxer.Move?) -> (Boxer, Timeline) {
        var b = Boxer(level: level, cat: cat, cues: cues, seed: seed, options: options, packs: packs)
        var tl = Timeline()
        var n = 0
        let end = b.t + ms
        while b.t < end, b.reflex.phase != .done, b.reflex.phase != .stopped {
            b.t += 1000 / b.fps
            let out = b.reflex.push(Boxer.frame(b.pose(at: b.t), b.t))
            b.commands += out
            tl.record(out, now: b.t, cueMs: options.cueSoundMs, speechMs: options.speechMs(""))
            for case .playCue(let key, let at) in out {
                b.cues.append((key, at))
                if let m = react(n, key, at) { b.moves.append(m) }
                n += 1
            }
        }
        return (b, tl)
    }

    /// Feedback of every kind on a fast level with combos: tones, fault cues, the wrong-direction hint, the summary;
    /// no speech ever overlaps a cue.
    @Test func speechNeverOverlapsACue() throws {
        var options = ReflexSet.Options()
        options.speechMs = { _ in 1400 }
        let (b, tl) = run(raw.level(5)!, cues: 24, options: options) { n, key, at in
            switch n % 4 {
            case 0: return answer(key, at: at + 300).map { var m = $0; m.to.guardDrop = 1; m.duration = 1100; return m }  // faulty
            case 1: return .init(start: at + 300, duration: 900, to: duck)  // wrong for slips
            case 2: return answer(key, at: at + 300)
            default: return nil  // missed
            }
        }
        #expect(b.reflex.phase == .done)
        #expect(b.commands.contains(.tone(.correct)) && b.commands.contains(.tone(.wrong)))
        #expect(b.commands.contains { if case .speak(let k) = $0 { k.hasPrefix("cue.") } else { false } })
        #expect(b.commands.contains { if case .speakSetSummary = $0 { true } else { false } })
        #expect(tl.overlaps(guardMs: options.speechGuardMs) == [])
        #expect(!tl.cues.isEmpty && !tl.speech.isEmpty)
    }

    @Test func twoWrongOnTheSameStrikeGiveTheHintOnce() {
        // level 1, jab and cross: answer every cue with a duck (wrong)
        let (b, _) = run(raw.level(1)!, cues: 8) { _, _, at in .init(start: at + 300, duration: 900, to: duck) }
        let hints = b.commands.compactMap { if case .speak(let k) = $0, k.hasPrefix("reflex.hint.") { k } else { nil } }
        #expect(!hints.isEmpty)
        #expect(Set(hints).count == hints.count)
        #expect(hints.allSatisfy { $0.hasSuffix(".orthodox") })
    }

    @Test func tonesAndFaultCuesCanBeTurnedOffTheCueCannot() {
        var options = ReflexSet.Options()
        options.resultTones = false
        options.faultCueVoice = false
        let (b, tl) = run(raw.level(1)!, cues: 3, options: options) { _, key, at in
            answer(key, at: at + 300).map { var m = $0; m.to.guardDrop = 1; m.duration = 1100; return m }
        }
        #expect(!b.commands.contains { if case .tone = $0 { true } else { false } })
        #expect(!b.commands.contains { if case .speak(let k) = $0 { k.hasPrefix("cue.") } else { false } })
        #expect(tl.cues.count == 3)
        #expect(b.reflex.trials.allSatisfy { $0.result == .correctFaulty })
    }

    /// The summary: cues, hits, mean RT and the hardest strike.
    @Test func theSetSummaryIsSpoken() {
        let (b, _) = run(raw.level(1)!, cues: 4) { n, key, at in n == 0 ? nil : answer(key, at: at + 400) }
        guard case .speakSetSummary(let cues, let hits, let mean, let hardest)? = b.commands.dropLast().last else {
            Issue.record("no summary before setDone")
            return
        }
        #expect(cues == 4 && hits == 3)
        #expect(mean != nil && hardest?.hasPrefix("strike.name.") == true)
    }

    /// A major fault in two attempts in a row stops the set and cancels the next planned cue of the combo,
    /// whose trial is not recorded.
    @Test func theSafetyPauseCancelsPlannedCues() throws {
        var j = try Repo.read(Repo.exercises.appendingPathComponent("slip_right.json"))
        var faults = j["faults"]!.arrayValue!
        let gd = faults.firstIndex { $0["id"]?.stringValue == "guard_dropped" }!
        faults[gd]["severity"] = "major"
        j["faults"] = .array(faults)
        var packs = responsePacks
        packs["slip_right"] = try RulePackLoader.load(j, capabilities: .vision19TwoD).get()
        // jab only, combos of two 900 ms apart: answer each cue with a guard-dropping slip to the right
        var level = raw.level(3)!
        level.strikes = ["jab"]
        level.comboLen = 2...2
        level.comboGapMs = 1500
        let (b, _) = run(level, cues: 6, packs: packs) { n, _, at in
            n % 2 == 0 ? .init(start: at + 300, duration: 900, to: EvaderParams(slip: -25, guardDrop: 1)) : nil
        }
        #expect(b.reflex.phase == .stopped)
        let i = try #require(b.commands.firstIndex(of: .cancelCues))
        #expect(b.commands[i + 1] == .safetyPause(faultId: "guard_dropped"))
        #expect(b.reflex.trials.count < 6)
        #expect(!b.commands.contains(.setDone))
    }
}
