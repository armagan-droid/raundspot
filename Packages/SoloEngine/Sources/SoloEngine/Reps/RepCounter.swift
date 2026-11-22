// Rep state machine (ref 04 "Tekrar algılama"; source `reps/rep-counter.ts`).
// Works on the (smoothed) rep metric; increasing movements are handled by
// flipping the sign so that every movement looks like a decreasing one.

/// Metric values of one frame.
public struct Snapshot: Sendable, Equatable {
    public var t: Double
    public var values: [String: Double]

    public init(t: Double, values: [String: Double]) {
        self.t = t
        self.values = values
    }
}

/// The frame with the most extreme rep metric value (`at_turn`).
public struct TurnSnapshot: Sendable, Equatable {
    public var t: Double
    public var values: [String: Double]
    public var value: Double
}

public struct AttemptCompleted: Sendable, Equatable {
    /// Time the metric re-entered the start zone.
    public var t: Double
    public var durationMs: Double
    public var reachedTarget: Bool
    /// Frame where the metric left the start zone (`at_start`).
    public var start: Snapshot
    public var turn: TurnSnapshot
}

public enum RepCounterEvent: Sendable, Equatable {
    case repStarted(t: Double)
    case attemptCompleted(AttemptCompleted)
}

public enum RepCounterState: String, Sendable, Equatable {
    case waiting = "WAITING"
    case atStart = "AT_START"
    case inRep = "IN_REP"
}

public struct RepCounter: Sendable {
    public let rep: RepDefinition
    private let sign: Double
    private let startEnter: Double
    private let startExit: Double
    private let targetEnter: Double
    private let confirmAt: Double

    public private(set) var state: RepCounterState = .waiting
    private var start: Snapshot?
    private var turn: TurnSnapshot?
    private var reachedTarget = false
    private var confirmed = false

    public init(_ rep: RepDefinition) {
        self.rep = rep
        let s: Double = rep.start.enter > rep.target.enter ? 1 : -1
        sign = s
        startEnter = s * rep.start.enter
        startExit = s * rep.start.exit
        targetEnter = s * rep.target.enter
        confirmAt = s * rep.start.exit - rep.attemptMinExcursion
    }

    /// Frame where the current attempt left the start zone, while in a rep.
    public var attemptStart: Snapshot? { state == .inRep ? start : nil }

    public mutating func reset() {
        state = .waiting
        start = nil
        turn = nil
    }

    /// Feeds one frame's metric values (must contain `rep.metric`).
    public mutating func push(_ t: Double, _ values: [String: Double]) -> [RepCounterEvent] {
        guard let v = values[rep.metric], !v.isNaN else { return [] }
        let x = sign * v
        var events: [RepCounterEvent] = []

        switch state {
        case .waiting:
            if x >= startEnter { state = .atStart }
            return events
        case .atStart:
            if x >= startExit { return events }
            state = .inRep
            start = Snapshot(t: t, values: values)
            turn = TurnSnapshot(t: t, values: values, value: v)
            reachedTarget = false
            confirmed = false
        case .inRep:
            if x >= startEnter {
                state = .atStart
                if confirmed, let start, let turn {
                    events.append(.attemptCompleted(AttemptCompleted(
                        t: t, durationMs: t - start.t, reachedTarget: reachedTarget, start: start, turn: turn)))
                }
                return events
            }
            if x < sign * turn!.value {
                turn = TurnSnapshot(t: t, values: values, value: v)
            }
        }

        if x <= targetEnter { reachedTarget = true }
        if !confirmed, x <= confirmAt {
            confirmed = true
            events.append(.repStarted(t: t))
        }
        return events
    }
}

/// Outcome table from ref 04 (duration out of range always wins).
public func classifyAttempt(reachedTarget: Bool, durationMs: Double, hasValidityFault: Bool,
                            minDurationMs: Int, maxDurationMs: Int) -> RepOutcome {
    if durationMs < Double(minDurationMs) || durationMs > Double(maxDurationMs) { return .incomplete }
    if hasValidityFault { return .faulty }
    return reachedTarget ? .valid : .incomplete
}
