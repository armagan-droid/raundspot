// The reflex trial loop (specs/05 "Deneme döngüsü", "Sınıflandırma", "Tepki
// süresi", "Kombinasyonlar", "Aldatma", "Uygulama ayrıntıları"). Pure and
// deterministic: time moves with frames and TICK; randomness is a seeded
// SplitMix64. Inputs are pose frames and ticks, outputs commands.

/// Seeded SplitMix64 (specs/05 "Rastgelelik").
public struct ReflexRandom: Sendable, Equatable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    public mutating func uniform(_ r: ClosedRange<Double>) -> Double { r.lowerBound + unit() * (r.upperBound - r.lowerBound) }

    public mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
}

public enum ReflexResult: String, Sendable, Equatable, CaseIterable {
    case correct
    case correctFaulty = "correct_faulty"
    case wrong, partial, missed, early
    case feintOk = "feint_ok"
    case feintBitten = "feint_bitten"

    /// A hit for the summary and the level advice (specs/05 "Seviye önerisi").
    public var isHit: Bool { self == .correct || self == .correctFaulty || self == .feintOk }
    /// Enters the reaction time statistics.
    public var hasReactionTime: Bool { self == .correct || self == .correctFaulty || self == .wrong || self == .partial }
}

/// One response engine's completed attempt in a cue's window.
public struct ReflexCandidate: Sendable, Equatable {
    public var exerciseId: String
    public var outcome: RepOutcome
    public var faults: [String]
    /// Movement start (raw-corrected), host ms.
    public var moveAt: Double
    /// How far the turn went toward the target (tie-break).
    public var turnProgress: Double

    public init(exerciseId: String, outcome: RepOutcome, faults: [String], moveAt: Double, turnProgress: Double) {
        self.exerciseId = exerciseId
        self.outcome = outcome
        self.faults = faults
        self.moveAt = moveAt
        self.turnProgress = turnProgress
    }
}

public struct ReflexClassification: Sendable, Equatable {
    public var result: ReflexResult
    public var chosen: ReflexCandidate?
    /// The chosen response is the strike's preferred one (nil without a chosen response).
    public var preferred: Bool?
}

/// specs/05 "Sınıflandırma", steps 1–7. `strike` nil: a feint.
public func classifyReflexTrial(strike: ResolvedCatalog.Strike?, cueAt: Double, candidates: [ReflexCandidate],
                                catalog: ResolvedCatalog, minHumanRtMs: Double = 120) -> ReflexClassification {
    guard let strike else {
        return ReflexClassification(result: candidates.isEmpty ? .feintOk : .feintBitten, chosen: nil, preferred: nil)
    }
    guard let first = candidates.map(\.moveAt).min() else { return ReflexClassification(result: .missed, chosen: nil, preferred: nil) }
    if first < cueAt || first - cueAt < minHumanRtMs { return ReflexClassification(result: .early, chosen: nil, preferred: nil) }

    func pick(_ pool: [ReflexCandidate]) -> ReflexCandidate? {
        // the most specific: no other candidate in the pool is more specific than it; then the deepest turn
        let top = pool.filter { c in !pool.contains { $0.exerciseId != c.exerciseId && catalog.isMoreSpecific($0.exerciseId, than: c.exerciseId) } }
        return top.max { $0.turnProgress < $1.turnProgress }
    }
    let chosen = pick(candidates.filter { $0.outcome == .valid }) ?? pick(candidates.filter { $0.outcome == .faulty })
    guard let chosen else {
        let partial = pick(candidates)
        return ReflexClassification(result: .partial, chosen: partial, preferred: nil)
    }
    let accepted = strike.accept.contains(chosen.exerciseId)
    let result: ReflexResult = !accepted ? .wrong : (chosen.faults.isEmpty && chosen.outcome == .valid ? .correct : .correctFaulty)
    return ReflexClassification(result: result, chosen: chosen, preferred: accepted ? chosen.exerciseId == strike.prefer : nil)
}

/// A trial as recorded (specs/11 `ReflexTrial`).
public struct ReflexTrialRecord: Sendable, Equatable {
    public var index: Int
    public var comboId: Int?
    public var comboIndex: Int?
    public var strikeId: String
    public var isFeint: Bool
    /// `t_cue`, host ms.
    public var cueAt: Double
    public var result: ReflexResult
    public var responseExerciseId: String?
    public var preferred: Bool?
    public var reactionMs: Double?
    public var rtApproximate: Bool
    public var faults: [String]

    public init(index: Int, comboId: Int?, comboIndex: Int?, strikeId: String, isFeint: Bool, cueAt: Double, result: ReflexResult,
                responseExerciseId: String?, preferred: Bool?, reactionMs: Double?, rtApproximate: Bool, faults: [String]) {
        self.index = index
        self.comboId = comboId
        self.comboIndex = comboIndex
        self.strikeId = strikeId
        self.isFeint = isFeint
        self.cueAt = cueAt
        self.result = result
        self.responseExerciseId = responseExerciseId
        self.preferred = preferred
        self.reactionMs = reactionMs
        self.rtApproximate = rtApproximate
        self.faults = faults
    }
}

/// Result tones (specs/05 "Sonuç sesi"): no speech.
public enum ReflexTone: String, Sendable, Equatable { case correct, wrong, feintBitten = "feint_bitten" }

public enum ReflexCommand: Sendable, Equatable {
    /// Schedule a cue sound at a host time (ms).
    case playCue(key: String, atMs: Double)
    /// Stop every scheduled or playing cue (safety pause).
    case cancelCues
    case speak(String)
    case tone(ReflexTone)
    case trial(ReflexTrialRecord)
    /// A response engine stopped the set; planned cues are dropped and not recorded.
    case safetyPause(faultId: String)
    /// Tracking lost or restored (one response engine's view; the session pauses on it, ref 03 rule 10).
    case tracking(lost: Bool)
    /// Spoken set summary (≤ 8 s): cues, hits, mean RT (ms, rounded) and the hardest strike's name key.
    case speakSetSummary(cues: Int, hits: Int, meanRtMs: Int?, hardestNameKey: String?)
    case setDone
}

/// One reflex set (specs/05): N cues of one level, the response engines run on every frame.
public final class ReflexSet {
    public enum Phase: Sendable, Equatable {
        case preparing
        case waiting(until: Double)
        /// Cues of the current combo planned; windows open or resolving.
        case cueing
        case stopped
        case done
    }

    public struct Options: Sendable {
        public var minHumanRtMs: Double = 120
        /// A cue is scheduled at least this far ahead (audio path ready).
        public var planAheadMs: Double = 80
        public var getReadyAfterMs: Double = 5000
        public var getReadyEveryMs: Double = 10_000
        public var waitForCueCooldownMs: Double = 15_000
        /// The cue sound's onset after its scheduled time and whether it is only approximate (TTS, Bluetooth).
        public var cueDelay: @Sendable (_ key: String) -> (ms: Double, approximate: Bool) = { _ in (0, false) }
        /// How long a cue sound and a spoken key last (estimates for the timeline, specs/05 "Öncelik").
        public var cueSoundMs: Double = 600
        public var speechMs: @Sendable (_ key: String) -> Double = { _ in 1500 }
        /// No speech in the last 600 ms before a cue (specs/05).
        public var speechGuardMs: Double = 600
        /// Settings (specs/11): result tones and the fault cue voice can be turned off; the cue sound cannot.
        public var resultTones = true
        public var faultCueVoice = true

        public init() {}
    }

    private struct Window {
        var cueIndex: Int
        var comboId: Int?
        var comboIndex: Int?
        var strike: ResolvedCatalog.Strike?
        var feintId: String?
        var planAt: Double
        var cueAt: Double
        var approximate: Bool
        /// Per engine: an attempt assigned here (start time, then its completion).
        var assigned: [String: Double] = [:]
        var completed: [ReflexCandidate] = []
    }

    public let catalog: ResolvedCatalog
    public let level: ReflexCatalog.Level
    public let cueCount: Int
    public private(set) var phase: Phase = .preparing
    public private(set) var trials: [ReflexTrialRecord] = []
    public private(set) var engines: [String: ExerciseEngine]

    private var options: Options
    private var rng: ReflexRandom
    private let maxDurationMs: Double
    private var now: Double
    private var preparingSince: Double
    private var lastGetReadyAt: Double?
    private var lastWaitForCueAt = -Double.infinity
    private var windows: [Window] = []
    private var cuesUsed = 0
    private var comboCount = 0
    private var lastStrike: String?
    /// Movement starts of attempts in progress, by engine.
    private var moving: [String: Double] = [:]
    // feedback (T4.3)
    private var speechUntil = -Double.infinity
    private var queuedSpeech: [String] = []
    private var lastFaultCueAt: [String: Double] = [:]
    /// Consecutive wrong answers among each strike's own trials.
    private var wrongStreak: [String: Int] = [:]
    private var hinted: Set<String> = []
    /// Cue sounds still to start or playing: (start, end).
    private var plannedCues: [(start: Double, end: Double)] = []

    /// - Parameters:
    ///   - packs: the response templates by id (front view, near side left; specs/05 "Tepki motorları").
    ///   - cues: the block's cue count; the level's when nil.
    public init(catalog: ResolvedCatalog, level: ReflexCatalog.Level, packs: [String: LoadedRulePack], cues: Int? = nil,
                seed: UInt64, now: Double, options: Options = Options()) {
        self.catalog = catalog
        self.level = level
        cueCount = cues ?? level.cues
        self.options = options
        rng = ReflexRandom(seed: seed)
        self.now = now
        preparingSince = now
        var engines: [String: ExerciseEngine] = [:]
        for id in catalog.responses {
            guard let p = packs[id] else { continue }
            let e = ExerciseEngine(p, setup: ExerciseSetup(view: .front, nearSide: .left))
            e.setCuesEnabled(false)
            engines[id] = e
        }
        self.engines = engines
        maxDurationMs = Double(engines.values.map { $0.loaded.pack.rep.maxDurationMs }.max() ?? 3000)
    }

    /// Every String Catalog key a set of this catalog can speak besides cue sounds and fault cues (specs/00 rule 8).
    public static func spokenKeys(_ catalog: ReflexCatalog) -> [String] {
        var keys = ["reflex.get_ready", "reflex.wait_for_cue"]
        for s in catalog.strikes {
            for st in Stance.allCases {
                keys.append("reflex.hint.\(s.id).\(st.rawValue)")
                if let say = s.say[st] { keys.append(say.replacingPrefix("strike.", with: "strike.name.")) }
            }
        }
        return Array(Set(keys)).sorted()
    }

    /// The combined ready pose holds (specs/05 "Hazır olma").
    public var isReady: Bool {
        guard !engines.isEmpty else { return false }
        var latest = -Double.infinity
        var longest = 0.0
        for e in engines.values {
            guard e.repState == .atStart, let since = e.readyPoseHeldSince else { return false }
            latest = Swift.max(latest, since)
            longest = Swift.max(longest, e.readyPoseDurationMs)
        }
        return now - latest >= longest
    }

    public func push(_ frame: Frame) -> [ReflexCommand] {
        guard phase != .stopped, phase != .done else { return [] }
        now = Swift.max(now, frame.t)
        var out: [ReflexCommand] = []
        let tracker = engines.keys.sorted().first
        for id in engines.keys.sorted() {
            let e = engines[id]!
            for te in e.push(frame) {
                switch te.event {
                case .trackingLost where id == tracker: out.append(.tracking(lost: true))
                case .trackingRestored where id == tracker: out.append(.tracking(lost: false))
                case .repStarted:
                    let move = e.rawConfirmCrossing(confirmedAt: te.t) ?? te.t
                    moving[id] = move
                    onMovement(id, at: move, &out)
                case .repCompleted(let outcome, let faults, _):
                    guard let move = moving.removeValue(forKey: id) else { continue }
                    let c = ReflexCandidate(exerciseId: id, outcome: outcome, faults: faults, moveAt: move,
                                            turnProgress: e.lastTurnProgress ?? 0)
                    if let w = windows.firstIndex(where: { $0.assigned[id] == move }) { windows[w].completed.append(c) }
                case .safetyPause(let fault):
                    stop(fault, &out)
                    return out
                default:
                    break
                }
            }
            // an attempt that left without completing (noise) is not a candidate
            if e.repState != .inRep, let move = moving.removeValue(forKey: id) {
                for w in windows.indices where windows[w].assigned[id] == move { windows[w].assigned[id] = nil }
            }
        }
        out += step()
        return out
    }

    /// The session paused (manual, tracking, interruption): planned cues are cancelled and their trials dropped;
    /// the set goes back to preparing and goes on when frames come again.
    public func pause() -> [ReflexCommand] {
        guard phase != .stopped, phase != .done else { return [] }
        var out: [ReflexCommand] = []
        if !plannedCues.isEmpty || !windows.isEmpty { out.append(.cancelCues) }
        cuesUsed -= windows.count
        plannedCues.removeAll()
        windows.removeAll()
        queuedSpeech.removeAll()
        moving.removeAll()
        phase = .preparing
        preparingSince = now
        return out
    }

    public func tick(_ t: Double) -> [ReflexCommand] {
        guard phase != .stopped, phase != .done else { return [] }
        now = Swift.max(now, t)
        return step()
    }

    // MARK: - Loop

    private func onMovement(_ id: String, at move: Double, _ out: inout [ReflexCommand]) {
        switch phase {
        case .waiting:
            // moving during the wait: back to preparing, and the user hears why (15 s cooldown)
            phase = .preparing
            preparingSince = now
            if now - lastWaitForCueAt >= options.waitForCueCooldownMs {
                lastWaitForCueAt = now
                say("reflex.wait_for_cue", droppable: true, &out)
            }
        case .cueing:
            // the earliest open window containing the start that has nothing from this engine yet
            if let w = windows.firstIndex(where: { move >= $0.planAt && move <= $0.cueAt + Double(level.windowMs) && $0.assigned[id] == nil }) {
                windows[w].assigned[id] = move
            }
        default:
            break
        }
    }

    private func step() -> [ReflexCommand] {
        var out: [ReflexCommand] = []
        plannedCues.removeAll { $0.end <= now }
        flushSpeech(&out)
        switch phase {
        case .preparing:
            if isReady {
                phase = .waiting(until: now + rng.uniform(level.foreMs))
                lastGetReadyAt = nil
            } else if now - preparingSince >= options.getReadyAfterMs,
                      lastGetReadyAt.map({ now - $0 >= options.getReadyEveryMs }) ?? true {
                lastGetReadyAt = now
                say("reflex.get_ready", droppable: true, &out)
            }
        case .waiting(let until):
            if now >= until { planCombo(&out) }
        case .cueing:
            resolveWindows(&out)
            if windows.isEmpty {
                if cuesUsed >= cueCount {
                    phase = .done
                    out.append(summaryCommand())
                    out.append(.setDone)
                } else {
                    phase = .preparing
                    preparingSince = now
                }
            }
        case .stopped, .done:
            break
        }
        return out
    }

    private func planCombo(_ out: inout [ReflexCommand]) {
        let left = cueCount - cuesUsed
        var length = Swift.min(left, rng.int(level.comboLen))
        length = Swift.max(1, length)
        let feint = level.feintRate > 0 && !catalog.feints.isEmpty && rng.unit() < level.feintRate
        let comboId: Int? = length > 1 ? comboCount : nil
        if length > 1 { comboCount += 1 }
        // a cue never starts over speech: after it ends, with the guard (specs/05 "Öncelik")
        var at = Swift.max(now + options.planAheadMs, speechUntil + options.speechGuardMs)
        for i in 0..<length {
            var w: Window
            if feint, i == length - 1 {
                let f = catalog.feints[rng.int(0...(catalog.feints.count - 1))]
                let d = options.cueDelay(f.say)
                w = Window(cueIndex: cuesUsed, comboId: comboId, comboIndex: comboId == nil ? nil : i, strike: nil, feintId: f.id,
                           planAt: at, cueAt: at + d.ms, approximate: d.approximate)
                out.append(.playCue(key: f.say, atMs: at))
            } else {
                let pool = level.strikes.filter { $0 != lastStrike }
                let id = (pool.isEmpty ? level.strikes : pool)[rng.int(0...((pool.isEmpty ? level.strikes : pool).count - 1))]
                lastStrike = id
                let strike = catalog.strikes.first { $0.id == id }!
                let d = options.cueDelay(strike.say)
                w = Window(cueIndex: cuesUsed, comboId: comboId, comboIndex: comboId == nil ? nil : i, strike: strike, feintId: nil,
                           planAt: at, cueAt: at + d.ms, approximate: d.approximate)
                out.append(.playCue(key: strike.say, atMs: at))
            }
            windows.append(w)
            plannedCues.append((at, at + options.cueSoundMs))
            cuesUsed += 1
            at += Double(level.comboGapMs ?? 0)
        }
        phase = .cueing
    }

    private func resolveWindows(_ out: inout [ReflexCommand]) {
        // in order: a later window waits for the earlier ones
        while let w = windows.first {
            let closed = now >= w.cueAt + Double(level.windowMs)
            let allDone = w.assigned.allSatisfy { a in w.completed.contains { $0.exerciseId == a.key && $0.moveAt == a.value } }
            let timedOut = now >= w.cueAt + Double(level.windowMs) + maxDurationMs
            guard closed, allDone || timedOut else { return }
            windows.removeFirst()
            let c = classifyReflexTrial(strike: w.strike, cueAt: w.cueAt, candidates: w.completed, catalog: catalog,
                                        minHumanRtMs: options.minHumanRtMs)
            let rt = c.result.hasReactionTime ? c.chosen.map { $0.moveAt - w.cueAt } : nil
            let record = ReflexTrialRecord(
                index: trials.count, comboId: w.comboId, comboIndex: w.comboIndex, strikeId: w.strike?.id ?? w.feintId ?? "",
                isFeint: w.strike == nil, cueAt: w.cueAt, result: c.result,
                responseExerciseId: c.result.hasReactionTime ? c.chosen?.exerciseId : nil, preferred: c.preferred, reactionMs: rt,
                rtApproximate: w.approximate, faults: c.result.hasReactionTime ? c.chosen?.faults ?? [] : [])
            trials.append(record)
            out.append(.trial(record))
            feedback(record, &out)
        }
    }

    // MARK: - Feedback (specs/05 "Geri bildirim", T4.3)

    private func feedback(_ r: ReflexTrialRecord, _ out: inout [ReflexCommand]) {
        if options.resultTones {
            switch r.result {
            case .correct, .correctFaulty, .feintOk: out.append(.tone(.correct))
            case .feintBitten: out.append(.tone(.feintBitten))
            case .wrong, .missed, .early, .partial: out.append(.tone(.wrong))
            }
        }
        // one fault cue at most, on correct_faulty only, with the template cooldown; dropped if it does not fit
        if options.faultCueVoice, r.result == .correctFaulty, let ex = r.responseExerciseId, let fault = r.faults.first {
            let key = "\(ex).\(fault)"
            // the template's cooldown (ref 05)
            let cooldown = engines[ex]?.loaded.pack.faults.first { $0.id == fault }.map { Double($0.cooldownMs) } ?? 4000
            if now - (lastFaultCueAt[key] ?? -Double.infinity) >= cooldown, say("cue.\(key)", droppable: true, &out) {
                lastFaultCueAt[key] = now
            }
        }
        // two wrong in a row among the same strike's trials: the direction, once per strike per set
        guard !r.isFeint else { return }
        if r.result == .wrong {
            let n = (wrongStreak[r.strikeId] ?? 0) + 1
            wrongStreak[r.strikeId] = n
            if n >= 2, !hinted.contains(r.strikeId) {
                hinted.insert(r.strikeId)
                say("reflex.hint.\(r.strikeId).\(catalog.stance.rawValue)", droppable: false, &out)
            }
        } else {
            wrongStreak[r.strikeId] = 0
        }
    }

    /// Speech never overlaps a cue sound or its 600 ms lead-in. Droppable speech that does not fit now is dropped,
    /// the rest waits. Returns whether it was spoken now.
    @discardableResult
    private func say(_ key: String, droppable: Bool, _ out: inout [ReflexCommand]) -> Bool {
        if queuedSpeech.isEmpty, fits(options.speechMs(key)) {
            out.append(.speak(key))
            speechUntil = now + options.speechMs(key)
            return true
        }
        if !droppable { queuedSpeech.append(key) }
        return false
    }

    private func fits(_ ms: Double) -> Bool {
        let s = Swift.max(now, speechUntil), e = s + ms
        guard s == now else { return false }
        return !plannedCues.contains { s < $0.end && e > $0.start - options.speechGuardMs }
    }

    private func flushSpeech(_ out: inout [ReflexCommand]) {
        while let key = queuedSpeech.first, fits(options.speechMs(key)) {
            queuedSpeech.removeFirst()
            out.append(.speak(key))
            speechUntil = now + options.speechMs(key)
        }
    }

    private func summaryCommand() -> ReflexCommand {
        let s = ReflexSetSummary(trials)
        let rts = trials.compactMap(\.reactionMs)
        let mean = rts.isEmpty ? nil : Int((rts.reduce(0, +) / Double(rts.count)).rounded())
        // the hardest: the lowest hit rate, then the slower median (strikes with a miss only)
        let hardest = s.byStrike.filter { $0.value.hits < $0.value.total }.min { a, b in
            let ra = Double(a.value.hits) / Double(a.value.total), rb = Double(b.value.hits) / Double(b.value.total)
            return ra != rb ? ra < rb : (a.value.medianRtMs ?? 0) != (b.value.medianRtMs ?? 0) ? (a.value.medianRtMs ?? 0) > (b.value.medianRtMs ?? 0) : a.key < b.key
        }
        let nameKey = hardest.flatMap { h in catalog.strikes.first { $0.id == h.key } }.map { $0.say.replacingPrefix("strike.", with: "strike.name.") }
        return .speakSetSummary(cues: s.total, hits: s.hits, meanRtMs: mean, hardestNameKey: nameKey)
    }

    private func stop(_ fault: String, _ out: inout [ReflexCommand]) {
        // the safety pause cancels planned or playing cues; their trials are not recorded (AC-5.7)
        if !plannedCues.isEmpty || !windows.isEmpty { out.append(.cancelCues) }
        plannedCues.removeAll()
        queuedSpeech.removeAll()
        windows.removeAll()
        phase = .stopped
        out.append(.safetyPause(faultId: fault))
    }
}

// MARK: - Summary and level advice

/// Set summary (specs/05 "Set özeti ve kayıt").
public struct ReflexSetSummary: Sendable, Equatable {
    public struct PerStrike: Sendable, Equatable {
        public var hits: Int
        public var total: Int
        public var medianRtMs: Double?
    }

    public var total: Int
    public var hits: Int
    public var medianRtMs: Double?
    public var p90RtMs: Double?
    public var byStrike: [String: PerStrike]
    /// Among accepted responses, the preferred ones.
    public var preferredRatio: Double?
    public var feintsOk: Int
    public var feints: Int
    public var mostFrequentFault: String?

    public init(_ trials: [ReflexTrialRecord]) {
        total = trials.count
        hits = trials.filter(\.result.isHit).count
        let rts = trials.compactMap(\.reactionMs)
        medianRtMs = Self.quantile(rts, 0.5)
        p90RtMs = Self.quantile(rts, 0.9)
        var by: [String: PerStrike] = [:]
        for s in Set(trials.filter { !$0.isFeint }.map(\.strikeId)) {
            let ts = trials.filter { $0.strikeId == s && !$0.isFeint }
            by[s] = PerStrike(hits: ts.filter(\.result.isHit).count, total: ts.count, medianRtMs: Self.quantile(ts.compactMap(\.reactionMs), 0.5))
        }
        byStrike = by
        let accepted = trials.compactMap(\.preferred)
        preferredRatio = accepted.isEmpty ? nil : Double(accepted.filter { $0 }.count) / Double(accepted.count)
        feints = trials.filter(\.isFeint).count
        feintsOk = trials.filter { $0.result == .feintOk }.count
        var counts: [String: Int] = [:]
        for f in trials.flatMap(\.faults) { counts[f, default: 0] += 1 }
        mostFrequentFault = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Nearest-rank quantile; nil when empty.
    static func quantile(_ xs: [Double], _ q: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        if q == 0.5, s.count % 2 == 0 { return (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
        let rank = Int((q * Double(s.count)).rounded(.up))
        return s[Swift.min(s.count - 1, Swift.max(0, rank - 1))]
    }
}

public enum ReflexLevelAdvice: Sendable, Equatable {
    case tryHigher, tryLower

    /// specs/05 "Seviye önerisi": over the last two sets, hits ≥ 85 % and median RT ≤ 60 % of the window → higher;
    /// hits < 50 % → lower. Advice only; the level never changes by itself.
    public static func advise(lastTwoSets: [[ReflexTrialRecord]], windowMs: Int) -> ReflexLevelAdvice? {
        guard lastTwoSets.count == 2 else { return nil }
        let s = ReflexSetSummary(lastTwoSets.flatMap { $0 })
        guard s.total > 0 else { return nil }
        let rate = Double(s.hits) / Double(s.total)
        if rate >= 0.85, let m = s.medianRtMs, m <= 0.6 * Double(windowMs) { return .tryHigher }
        if rate < 0.5 { return .tryLower }
        return nil
    }
}

extension String {
    func replacingPrefix(_ p: String, with q: String) -> String { hasPrefix(p) ? q + dropFirst(p.count) : self }
}
