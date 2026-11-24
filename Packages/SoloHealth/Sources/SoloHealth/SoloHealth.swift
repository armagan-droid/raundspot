import Foundation

/// HealthKit workout session and energy samples (specs/08 "HealthKit'e yazma"; T6.2).
public enum SoloHealth {
    public static let moduleName = "SoloHealth"
}

/// The workout activity types the app writes (specs/08 table); raw values name `HKWorkoutActivityType` cases.
public enum HealthActivity: String, Sendable, Equatable {
    case martialArts, kickboxing, boxing, functionalStrengthTraining, mixedCardio, preparationAndRecovery, flexibility

    /// A block's type: technique, reflex and round by the sport pack; conditioning; warm-up; cool-down and mobility.
    public init(blockKind: String, sport: String) {
        switch blockKind {
        case "technique", "reflex", "round":
            self = sport == "kickboxing" ? .kickboxing : sport == "boxing" ? .boxing : .martialArts
        case "conditioning": self = .functionalStrengthTraining
        case "warmup": self = .preparationAndRecovery
        default: self = .flexibility
        }
    }
}

/// What the app needs from HealthKit; the live store wraps `HKWorkoutSession` and `HKLiveWorkoutBuilder`.
public protocol HealthStore: AnyObject {
    func begin(at: Date)
    func addActivity(_ type: HealthActivity, start: Date, end: Date)
    /// Net active kcal for a block (`activeEnergyBurned`), attached to the workout.
    func addEnergy(kcal: Double, start: Date, end: Date)
    func pause(at: Date)
    func resume(at: Date)
    /// Ends and saves the workout; false if it could not be saved.
    func finish(at: Date, mainActivity: HealthActivity) -> Bool
    func discard()
}

/// One session as one HealthKit workout (specs/08 "Yaşam döngüsü"): an activity and an energy sample per
/// block, the longest block's type as the workout's; an aborted session under 3 active minutes is discarded.
public final class HealthWorkout {
    private let store: HealthStore
    private let sport: String
    private var durations: [HealthActivity: TimeInterval] = [:]
    private var started = false

    public init(store: HealthStore, sport: String) {
        self.store = store
        self.sport = sport
    }

    /// When the first block starts (setup time is not part of the workout).
    public func begin(at t: Date) {
        guard !started else { return }
        started = true
        store.begin(at: t)
    }

    /// A finished block; `kcal` nil without a weight (AC-8.2: no energy sample).
    public func block(_ kind: String, start: Date, end: Date, kcal: Double?) {
        guard started, end > start else { return }
        let type = HealthActivity(blockKind: kind, sport: sport)
        durations[type, default: 0] += end.timeIntervalSince(start)
        store.addActivity(type, start: start, end: end)
        if let kcal, kcal > 0 { store.addEnergy(kcal: kcal, start: start, end: end) }
    }

    public func pause(at t: Date) { if started { store.pause(at: t) } }
    public func resume(at t: Date) { if started { store.resume(at: t) } }

    /// Returns whether the workout was written (AC-8.5).
    @discardableResult
    public func finish(at t: Date, aborted: Bool, activeMs: Int) -> Bool {
        guard started else { return false }
        if aborted, activeMs < 180_000 {
            store.discard()
            return false
        }
        let main = durations.max { $0.value < $1.value }?.key ?? HealthActivity(blockKind: "technique", sport: sport)
        return store.finish(at: t, mainActivity: main)
    }
}
