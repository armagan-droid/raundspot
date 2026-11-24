#if canImport(HealthKit) && os(iOS)
import HealthKit

/// HealthKit on iPhone (specs/08): an `HKWorkoutSession` with its live builder. The builder's own energy
/// collection is off (the app writes one net sample per block, no double count; open question 3 of specs/08).
/// Its behaviour is checked on a device (AC-8.4).
public final class LiveHealthStore: HealthStore, @unchecked Sendable {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    public init() {}

    public static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Write: workouts, active energy, heart rate. Read: body mass, heart rate, date of birth, sex (specs/08 "İzinler").
    public func requestAuthorization() async -> Bool {
        let write: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.bodyMass), HKQuantityType(.heartRate), HKCharacteristicType(.dateOfBirth),
                                       HKCharacteristicType(.biologicalSex)]
        return (try? await store.requestAuthorization(toShare: write, read: read)) != nil
    }

    private static func configuration(_ type: HealthActivity) -> HKWorkoutConfiguration {
        let c = HKWorkoutConfiguration()
        c.activityType = switch type {
        case .martialArts: .martialArts
        case .kickboxing: .kickboxing
        case .boxing: .boxing
        case .functionalStrengthTraining: .functionalStrengthTraining
        case .mixedCardio: .mixedCardio
        case .preparationAndRecovery: .preparationAndRecovery
        case .flexibility: .flexibility
        }
        c.locationType = .indoor
        return c
    }

    public func begin(at t: Date) {
        let config = Self.configuration(.martialArts)
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return }
        let b = s.associatedWorkoutBuilder()
        let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        source.disableCollection(for: HKQuantityType(.activeEnergyBurned))
        b.dataSource = source
        session = s
        builder = b
        s.startActivity(with: t)
        b.beginCollection(withStart: t) { _, _ in }
        b.addMetadata([HKMetadataKeyIndoorWorkout: true]) { _, _ in }
    }

    public func addActivity(_ type: HealthActivity, start: Date, end: Date) {
        let a = HKWorkoutActivity(workoutConfiguration: Self.configuration(type), start: start, end: end, metadata: nil)
        builder?.addWorkoutActivity(a) { _, _ in }
    }

    public func addEnergy(kcal: Double, start: Date, end: Date) {
        let sample = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                      start: start, end: end)
        builder?.add([sample]) { _, _ in }
    }

    public func pause(at t: Date) { session?.pause() }
    public func resume(at t: Date) { session?.resume() }

    public func finish(at t: Date, mainActivity: HealthActivity) -> Bool {
        guard let session, let builder else { return false }
        session.end()
        builder.endCollection(withEnd: t) { _, _ in
            builder.finishWorkout { _, _ in }
        }
        self.session = nil
        self.builder = nil
        return true
    }

    public func discard() {
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
    }
}
#endif
