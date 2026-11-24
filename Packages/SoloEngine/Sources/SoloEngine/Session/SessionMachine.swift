import Foundation

// Session engine (specs/06 Bölüm 1; ref 03 rules 2–7, 9–12, 15 without the
// station parts; E1–E4). Pure and deterministic: time moves only with TICK,
// every other input is handled at the last TICK time.

public enum SessionState: String, Sendable, Equatable, Codable {
    case idle, setup, warmup, ready, countdown, active, confirm, rest, cooldown, paused, sessionDone, aborted

    public var isTerminal: Bool { self == .sessionDone || self == .aborted }
}

public enum UserAction: String, Sendable, Equatable, Codable {
    case start, ready, pause, resume, endSet, continueSet, skipBlock, undoSkip, abort, confirmSpace, skipWarmup
}

public enum Interruption: String, Sendable, Equatable, Codable { case background, call, camera }

public enum SessionInput: Sendable, Equatable {
    case tick(now: Double)
    case user(UserAction)
    case engine(EngineEvent)
    case setupReady
    case interrupted(Interruption)
    case audioInterrupted
    case audioResumed
    case reflexAttemptDone
    case restored(now: Double)
}

public enum SessionStatus: String, Sendable, Equatable, Codable { case active, done, aborted }
public enum BlockStatus: String, Sendable, Equatable, Codable { case done, partial, skipped }

public enum SessionRecord: Sendable, Equatable {
    case session(id: String, workoutId: String, status: SessionStatus, warmupSkipped: Bool)
    case block(id: String, sessionId: String, index: Int, exerciseId: String?, exerciseVersion: Int?, status: BlockStatus)
    case set(id: String, blockId: String, index: Int, validReps: Int, faultyReps: Int, attempts: Int, target: Int?,
             belowTarget: Bool, mode: SetMode?)
    case rep(id: String, setId: String, outcome: RepOutcome, faults: [String], durationMs: Int, counted: Bool)
}

public enum SessionCommand: Sendable, Equatable {
    case speak(String)
    case show(String)
    case persist(SessionRecord)
}

public enum SessionTiming {
    public static let countdownMs = 3000.0
    public static let confirmAfterMs = 10_000.0
    public static let autoEndAfterMs = 20_000.0
    public static let trackingLostPauseMs = 5000.0
    public static let resumeOfferMs = 30 * 60 * 1000.0
}

/// Serializable session state (E4).
public struct SessionSnapshot: Sendable, Equatable, Codable {
    public enum PauseReason: String, Sendable, Equatable, Codable { case manual, tracking, safety, interruption, restored }

    public var state: SessionState = .idle
    public var now: Double = 0
    public var sessionId: String?
    public var spaceConfirmed = false
    public var warmupSkipped = false
    public var blockIndex = 0
    public var blockId: String?
    public var setIndex = 0
    public var stepIndex = 0
    public var phaseStartedAt: Double = 0
    // countdown
    public var countdownSpoken = 0
    public var countdownResumes = false
    public var countdownSafety = false
    // current set
    public var setId: String?
    public var setStartedAt: Double = 0
    public var lastActivityAt: Double?
    public var counted = 0
    public var validReps = 0
    public var faultyReps = 0
    public var attempts = 0
    // rest
    public var restRemainingMs: Double = 0
    // pause
    public var resumeTo: SessionState?
    public var pauseReason: PauseReason?
    public var safetyFaultId: String?
    public var trackingLostAt: Double?
    public var audioMuted = false
    // skip / undo (ref 03 rule 9)
    public var pendingSkip: PendingSkip?
    public var setStartedInBlock = false

    public struct PendingSkip: Sendable, Equatable, Codable {
        public var blockIndex: Int
        public var blockId: String
        public var setIndex: Int
        public var status: BlockStatus
    }

    public init() {}
}

public struct SessionMachine {
    public let workout: Workout
    /// Template versions fixed at the start (ref 03), by exercise id.
    public let exerciseVersions: [String: Int]
    private let makeId: () -> String
    public private(set) var s: SessionSnapshot

    public init(workout: Workout, exerciseVersions: [String: Int], snapshot: SessionSnapshot = .init(), makeId: @escaping () -> String) {
        self.workout = workout
        self.exerciseVersions = exerciseVersions
        self.makeId = makeId
        s = snapshot
    }

    public var state: SessionState { s.state }
    public var block: Block? { workout.blocks.indices.contains(s.blockIndex) ? workout.blocks[s.blockIndex] : nil }

    // MARK: serialize (E4)

    public func serialize() -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(s)) ?? Data()
    }

    public static func deserialize(_ data: Data, workout: Workout, exerciseVersions: [String: Int],
                                   makeId: @escaping () -> String) throws -> SessionMachine {
        SessionMachine(workout: workout, exerciseVersions: exerciseVersions,
                       snapshot: try JSONDecoder().decode(SessionSnapshot.self, from: data), makeId: makeId)
    }

    // MARK: input

    public mutating func handle(_ input: SessionInput) -> [SessionCommand] {
        var out: [SessionCommand] = []
        if s.state.isTerminal { return out }
        switch input {
        case .tick(let now):
            s.now = max(s.now, now)
            tick(&out)
        case .user(let a): user(a, &out)
        case .engine(let e): engine(e, &out)
        case .setupReady: setupReady(&out)
        case .interrupted:
            if s.state != .idle, s.state != .paused { pause(.interruption, &out) }
        case .audioInterrupted:
            if s.state == .active, case .reflex? = block { pause(.interruption, &out) } else { s.audioMuted = true }
        case .audioResumed:
            s.audioMuted = false
        case .reflexAttemptDone:
            reflexAttempt(&out)
        case .restored(let now):
            restored(now, &out)
        }
        return out
    }

    // MARK: rules

    private mutating func user(_ a: UserAction, _ out: inout [SessionCommand]) {
        switch (s.state, a) {
        case (.idle, .start):
            let id = makeId()
            s.sessionId = id
            out.append(.persist(.session(id: id, workoutId: workout.id, status: .active, warmupSkipped: false)))
            s.state = .setup
            out.append(.show("setup.space"))
        case (.setup, .confirmSpace) where !s.spaceConfirmed:
            s.spaceConfirmed = true
            if workout.usesCamera { out.append(.show("setup.camera")) } else { enterBlock(0, &out) }
        case (.warmup, .skipWarmup) where isWarmup:
            s.warmupSkipped = true
            out.append(.show("safety.warmup_skipped"))
            out.append(.speak("safety.warmup_skipped"))
            writeBlock(.skipped, &out)
            enterBlock(s.blockIndex + 1, &out)
        case (.cooldown, .skipBlock):
            writeBlock(.skipped, &out)
            enterBlock(s.blockIndex + 1, &out)
        case (.ready, .start):
            startCountdown(resuming: false, safety: false, &out)
        case (.ready, .skipBlock), (.rest, .skipBlock):
            skipBlock(&out)
        case (.ready, .undoSkip) where s.pendingSkip != nil && !s.setStartedInBlock:
            let p = s.pendingSkip!
            s.pendingSkip = nil
            s.blockIndex = p.blockIndex
            s.blockId = p.blockId
            s.setIndex = p.setIndex
            s.setStartedInBlock = p.setIndex > 0
            enterReady(&out)
        case (.rest, .ready):
            enterReady(&out)
        case (.active, .endSet), (.confirm, .endSet):
            endSet(belowTarget: belowTarget, &out)
        case (.confirm, .continueSet):
            s.lastActivityAt = s.now
            s.state = .active
        case (.paused, .resume):
            resume(&out)
        case (let st, .pause) where st != .idle && st != .paused && st != .setup:
            pause(.manual, &out)
        case (let st, .abort) where st != .idle:
            abort(&out)
        default:
            break  // rule 15: invalid input changes nothing
        }
    }

    private mutating func engine(_ e: EngineEvent, _ out: inout [SessionCommand]) {
        switch e {
        case .trackingLost:
            if s.trackingLostAt == nil { s.trackingLostAt = s.now }
            return
        case .trackingRestored:
            s.trackingLostAt = nil
            if s.state == .paused, s.pauseReason == .tracking { resume(&out) } else if s.state == .paused, s.pauseReason == .manual {
                out.append(.show("prompt.resume"))
            }
            return
        case .readyPoseHeld:
            if s.state == .ready {
                startCountdown(resuming: false, safety: false, &out)
            } else if s.state == .paused, s.pauseReason == .safety {
                // rule 11: the form is right again
                startCountdown(resuming: true, safety: true, &out)
            }
            return
        default:
            break
        }
        guard s.state == .active || s.state == .confirm, let block else { return }
        if case .reflex = block { return }  // reflex attempts come as REFLEX_ATTEMPT_DONE
        switch e {
        case .repStarted:
            s.lastActivityAt = s.now
            s.state = .active
        case .repCompleted(let outcome, let faults, let durationMs):
            s.lastActivityAt = s.now
            s.state = .active
            s.attempts += 1
            let strict = mode == .strict
            let counted = outcome == .valid || (!strict && outcome == .faulty)
            if outcome == .valid { s.validReps += 1 }
            if outcome == .faulty { s.faultyReps += 1 }
            if counted { s.counted += 1 }
            out.append(.persist(.rep(id: makeId(), setId: s.setId ?? "", outcome: outcome, faults: faults,
                                     durationMs: durationMs, counted: counted)))
            if let target, s.counted >= target { endSet(belowTarget: false, &out) }
        case .faultDetected(let faultId):
            // rule 3: spoken only while the set is active; E2: silent while another app has the audio
            if s.state == .active, !s.audioMuted, let id = block.exerciseId {
                out.append(.speak("cue.\(id).\(faultId)"))
                out.append(.show("cue.\(id).\(faultId)"))
            }
        case .safetyPause(let faultId):
            if s.state == .active {
                out.append(.speak("safety.stop"))
                out.append(.show("safety.stop"))
                pause(.safety, &out)
                s.safetyFaultId = faultId
            }
        default:
            break
        }
    }

    private mutating func reflexAttempt(_ out: inout [SessionCommand]) {
        guard s.state == .active, case .reflex(_, _, let cues, _, _)? = block else { return }
        s.attempts += 1
        s.lastActivityAt = s.now
        if s.attempts >= (cues ?? Self.defaultReflexCues) { endSet(belowTarget: false, &out) }
    }

    /// specs/05: 20 cues unless the level says otherwise.
    public static let defaultReflexCues = 20

    private mutating func setupReady(_ out: inout [SessionCommand]) {
        if s.state == .setup, s.spaceConfirmed, workout.usesCamera {
            enterBlock(0, &out)
        } else if s.state == .paused, s.pauseReason == .tracking {
            s.trackingLostAt = nil
            resume(&out)
        }
    }

    private mutating func tick(_ out: inout [SessionCommand]) {
        let now = s.now
        // rule 10: tracking lost for 5 s in READY or ACTIVE
        if let lost = s.trackingLostAt, now - lost >= SessionTiming.trackingLostPauseMs, s.state == .ready || s.state == .active {
            out.append(.speak("tracking.lost"))
            out.append(.show("tracking.lost"))
            pause(.tracking, &out)
            return
        }
        switch s.state {
        case .warmup, .cooldown:
            let steps = block?.steps ?? []
            guard s.stepIndex < steps.count else { return }
            if now - s.phaseStartedAt >= Double(steps[s.stepIndex].durationSec) * 1000 {
                s.stepIndex += 1
                s.phaseStartedAt = now
                if s.stepIndex < steps.count {
                    out.append(.speak(steps[s.stepIndex].textKey))
                } else {
                    writeBlock(.done, &out)
                    enterBlock(s.blockIndex + 1, &out)
                }
            }
        case .countdown:
            let elapsed = now - s.phaseStartedAt
            if elapsed >= SessionTiming.countdownMs {
                out.append(.speak("set.go"))
                beginSet(&out)
            } else if elapsed >= 2000, s.countdownSpoken < 2 {
                s.countdownSpoken = 2
                out.append(.speak("countdown.1"))
            } else if elapsed >= 1000, s.countdownSpoken < 1 {
                s.countdownSpoken = 1
                out.append(.speak("countdown.2"))
            }
        case .active, .confirm:
            guard let block else { return }
            if case .conditioning(_, _, _, let dur?, _, _) = block {
                if now - s.setStartedAt >= Double(dur) * 1000 { endSet(belowTarget: false, &out) }
                return
            }
            if case .reflex = block { return }  // rule 5 is not used in reflex sets
            let idle = now - (s.lastActivityAt ?? s.setStartedAt)
            if idle >= SessionTiming.autoEndAfterMs {
                endSet(belowTarget: true, &out)
            } else if idle >= SessionTiming.confirmAfterMs, s.state == .active {
                s.state = .confirm
                out.append(.show("prompt.set_confirm"))
                out.append(.speak("prompt.set_confirm"))
            }
        case .rest:
            if now - s.phaseStartedAt >= s.restRemainingMs {
                out.append(.speak("rest.done"))
                enterReady(&out)
            }
        case .paused:
            if s.pauseReason == .restored, now - s.phaseStartedAt >= SessionTiming.resumeOfferMs { abort(&out) }
        default:
            break
        }
    }

    private mutating func restored(_ now: Double, _ out: inout [SessionCommand]) {
        guard s.state != .idle else { return }
        let last = s.now
        s.now = max(s.now, now)
        if now - last > SessionTiming.resumeOfferMs {
            abort(&out)
            return
        }
        if s.state != .paused {
            pause(.restored, &out)
        } else {
            s.pauseReason = .restored
        }
        s.phaseStartedAt = last
        out.append(.show("session.resume_offer"))
    }

    // MARK: helpers

    private var isWarmup: Bool { if case .warmup? = block { true } else { false } }

    private var mode: SetMode? {
        switch block {
        case .technique(_, _, _, _, let m)?, .conditioning(_, _, _, _, _, let m)?: m
        default: nil
        }
    }

    private var target: Int? {
        switch block {
        case .technique(_, _, let r, _, _)?: r
        case .conditioning(_, _, let r, _, _, _)?: r
        case .reflex(_, _, let c, _, _)?: c ?? Self.defaultReflexCues
        default: nil
        }
    }

    private var belowTarget: Bool {
        if case .reflex(_, _, let c, _, _)? = block { return s.attempts < (c ?? Self.defaultReflexCues) }
        if case .conditioning(_, _, nil, _?, _, _)? = block { return s.now - s.setStartedAt < Double(durationSec ?? 0) * 1000 }
        return s.counted < (target ?? 0)
    }

    private var durationSec: Int? { if case .conditioning(_, _, _, let d, _, _)? = block { d } else { nil } }

    private mutating func enterBlock(_ i: Int, _ out: inout [SessionCommand]) {
        s.blockIndex = i
        s.setIndex = 0
        s.stepIndex = 0
        s.setStartedInBlock = false
        s.trackingLostAt = nil
        guard let block else {
            finishSession(&out)
            return
        }
        s.blockId = makeId()
        switch block {
        case .warmup(let steps), .guided(let steps):
            s.state = block.isWarmupBlock ? .warmup : .cooldown
            s.phaseStartedAt = s.now
            out.append(.speak(steps[0].textKey))
        default:
            enterReady(&out)
        }
    }

    private mutating func enterReady(_ out: inout [SessionCommand]) {
        s.state = .ready
        out.append(.show("prompt.ready"))
    }

    private mutating func startCountdown(resuming: Bool, safety: Bool, _ out: inout [SessionCommand]) {
        // the undo window closes when the next set's countdown starts (rule 9)
        flushPendingSkip(&out)
        s.state = .countdown
        s.phaseStartedAt = s.now
        s.countdownSpoken = 0
        s.countdownResumes = resuming
        s.countdownSafety = safety
        s.pauseReason = nil
        s.resumeTo = nil
        out.append(.speak(safety ? "safety.resumed" : "countdown.3"))
        if safety { out.append(.show("safety.resumed")) }
    }

    private mutating func beginSet(_ out: inout [SessionCommand]) {
        s.state = .active
        if s.countdownResumes {
            s.lastActivityAt = s.now
        } else {
            s.setId = makeId()
            s.setStartedAt = s.now
            s.lastActivityAt = nil
            s.counted = 0
            s.validReps = 0
            s.faultyReps = 0
            s.attempts = 0
            s.setStartedInBlock = true
        }
        s.countdownResumes = false
        s.countdownSafety = false
        s.safetyFaultId = nil
    }

    private mutating func writeSet(belowTarget: Bool, _ out: inout [SessionCommand]) {
        guard let block, let setId = s.setId, let blockId = s.blockId else { return }
        let target: Int? = { if case .conditioning(_, _, nil, _, _, _) = block { nil } else { self.target } }()
        out.append(.persist(.set(id: setId, blockId: blockId, index: s.setIndex, validReps: s.validReps, faultyReps: s.faultyReps,
                                 attempts: s.attempts, target: target, belowTarget: belowTarget, mode: mode)))
        s.setId = nil
    }

    private mutating func endSet(belowTarget: Bool, _ out: inout [SessionCommand]) {
        writeSet(belowTarget: belowTarget, &out)
        out.append(.speak("prompt.set_done"))
        s.setIndex += 1
        if s.setIndex >= (block?.sets ?? 1) {
            let rest = workout.restAfterBlock[s.blockIndex] ?? 0
            writeBlock(.done, &out)
            enterBlock(s.blockIndex + 1, &out)
            // between circuit rounds (specs/06 "Devre"): rest, then the next round's first move
            if rest > 0, s.state == .ready {
                s.state = .rest
                s.phaseStartedAt = s.now
                s.restRemainingMs = Double(rest) * 1000
                out.append(.show("prompt.rest"))
            }
        } else {
            s.state = .rest
            s.phaseStartedAt = s.now
            s.restRemainingMs = Double(block?.restSec ?? 0) * 1000
            out.append(.show("prompt.rest"))
        }
    }

    private mutating func writeBlock(_ status: BlockStatus, _ out: inout [SessionCommand]) {
        guard let blockId = s.blockId, let sessionId = s.sessionId else { return }
        let ex = block?.exerciseId
        out.append(.persist(.block(id: blockId, sessionId: sessionId, index: s.blockIndex, exerciseId: ex,
                                   exerciseVersion: ex.flatMap { exerciseVersions[$0] }, status: status)))
        s.blockId = nil
    }

    private mutating func skipBlock(_ out: inout [SessionCommand]) {
        flushPendingSkip(&out)
        guard let blockId = s.blockId else { return }
        s.pendingSkip = .init(blockIndex: s.blockIndex, blockId: blockId, setIndex: s.setIndex,
                              status: s.setIndex == 0 ? .skipped : .partial)
        s.blockId = nil
        enterBlock(s.blockIndex + 1, &out)
    }

    private mutating func flushPendingSkip(_ out: inout [SessionCommand]) {
        guard let p = s.pendingSkip, let sessionId = s.sessionId else { return }
        let ex = workout.blocks[p.blockIndex].exerciseId
        out.append(.persist(.block(id: p.blockId, sessionId: sessionId, index: p.blockIndex, exerciseId: ex,
                                   exerciseVersion: ex.flatMap { exerciseVersions[$0] }, status: p.status)))
        s.pendingSkip = nil
    }

    private mutating func pause(_ reason: SessionSnapshot.PauseReason, _ out: inout [SessionCommand]) {
        guard s.state != .paused, s.state != .idle, !s.state.isTerminal else { return }
        if s.state == .rest { s.restRemainingMs = max(0, s.restRemainingMs - (s.now - s.phaseStartedAt)) }
        s.resumeTo = s.state
        s.pauseReason = reason
        s.state = .paused
        s.phaseStartedAt = s.now
        out.append(.show("session.paused"))
    }

    private mutating func resume(_ out: inout [SessionCommand]) {
        guard s.state == .paused, let to = s.resumeTo else { return }
        s.trackingLostAt = nil
        switch to {
        case .active, .confirm:
            startCountdown(resuming: true, safety: false, &out)
        case .countdown:
            startCountdown(resuming: s.countdownResumes, safety: false, &out)
        case .rest:
            s.state = .rest
            s.phaseStartedAt = s.now
        case .warmup, .cooldown:
            s.state = to
            s.phaseStartedAt = s.now  // the step restarts its timer
        default:
            s.state = to
        }
        if s.state != .countdown {
            s.pauseReason = nil
            s.resumeTo = nil
        }
    }

    private mutating func abort(_ out: inout [SessionCommand]) {
        let inSet = s.setId != nil && [SessionState.active, .confirm].contains(s.state == .paused ? (s.resumeTo ?? .idle) : s.state)
        if inSet, s.attempts > 0 {
            writeSet(belowTarget: true, &out)
            writeBlock(.partial, &out)
        } else if s.setIndex > 0, block?.usesCamera == true {
            writeBlock(.partial, &out)
        }
        flushPendingSkip(&out)
        if let id = s.sessionId {
            out.append(.persist(.session(id: id, workoutId: workout.id, status: .aborted, warmupSkipped: s.warmupSkipped)))
        }
        s.state = .aborted
    }

    private mutating func finishSession(_ out: inout [SessionCommand]) {
        flushPendingSkip(&out)
        if let id = s.sessionId {
            out.append(.persist(.session(id: id, workoutId: workout.id, status: .done, warmupSkipped: s.warmupSkipped)))
        }
        out.append(.speak("session.done"))
        s.state = .sessionDone
    }
}

extension Block {
    var isWarmupBlock: Bool { if case .warmup = self { true } else { false } }
}
