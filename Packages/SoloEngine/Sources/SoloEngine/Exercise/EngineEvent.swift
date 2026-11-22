/// Events produced by the rep and fault engine (ref 04; source `EngineEvent`).
public enum EngineEvent: Sendable, Hashable {
    case repStarted
    case repCompleted(outcome: RepOutcome, faults: [String], durationMs: Int)
    /// A fault that passed the cue rules (ref 05) and should be announced.
    case faultDetected(faultId: String)
    /// A major fault in two consecutive attempts (ref 05 "Güvenlik").
    case safetyPause(faultId: String)
    case trackingLost
    case trackingRestored
    case readyPoseHeld

    /// The source `type` discriminator (golden files use it).
    public var type: String {
        switch self {
        case .repStarted: "REP_STARTED"
        case .repCompleted: "REP_COMPLETED"
        case .faultDetected: "FAULT_DETECTED"
        case .safetyPause: "SAFETY_PAUSE"
        case .trackingLost: "TRACKING_LOST"
        case .trackingRestored: "TRACKING_RESTORED"
        case .readyPoseHeld: "READY_POSE_HELD"
        }
    }
}

/// An engine event with the time of the frame that produced it (specs/03
/// "Zaman damgalı olaylar"; the source events carry no time).
public struct TimedEvent: Sendable, Equatable {
    public var t: Double
    public var event: EngineEvent

    public init(t: Double, event: EngineEvent) {
        self.t = t
        self.event = event
    }
}

/// JavaScript `Math.round`: halves round toward +∞.
func jsRound(_ x: Double) -> Double {
    let down = x.rounded(.down)
    return x - down >= 0.5 ? down + 1 : down
}
