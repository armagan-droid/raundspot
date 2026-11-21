// Rule pack model: ref 04 schema (source `packages/shared/src/rule-pack.ts`,
// commit c2fe3fd) plus the MVP additions of specs/04 "Şema eklemeleri".

public struct LocalizedText: Sendable, Equatable {
    public var tr: String
    public var en: String

    public init(tr: String, en: String) {
        self.tr = tr
        self.en = en
    }
}

public enum RulePackStatus: String, Sendable, Equatable { case draft, calibrated }
public enum RulePackType: String, Sendable, Equatable { case reps, hold }
public enum CameraView: String, CaseIterable, Sendable, Hashable { case front, side }
public enum Posture: String, Sendable, Equatable { case standing, horizontal }
public enum Severity: String, Sendable, Equatable { case minor, major }

public enum RulePackDefaults {
    public static let minVisibility = 0.6
    public static let cooldownMs = 4000
    public static let minConsecutiveReps = 1
    public static let holdMs = 150
}

/// Words a metric may not be named (source `RESERVED_WORDS`).
public let reservedExpressionWords: Set<String> =
    Set(["and", "or", "not", "for", "ms"])
    .union(ExpressionFunction.allCases.map(\.rawValue))
    .union(CheckPosition.allCases.map(\.rawValue))

/// Closed list of metric functions (ref 04 "Metrik fonksiyonları" + specs/04).
public enum MetricDefinition: Sendable, Equatable {
    // Source functions (ref 04).
    case angle(LandmarkRef, LandmarkRef, LandmarkRef)
    case avg(String, String)
    case absDiff(String, String)
    case max(String, String)
    case diffY(LandmarkRef, LandmarkRef)
    case angleFromVertical(LandmarkRef, LandmarkRef)
    case kneeInwardRatio(LandmarkRef, LandmarkRef, LandmarkRef)
    case signedOffset(LandmarkRef, LandmarkRef, LandmarkRef)
    case lateralLean(LandmarkRef, LandmarkRef)
    case chainHeight([LandmarkRef])
    // specs/04 MVP additions.
    case min(String, String)
    case angle2d(LandmarkRef, LandmarkRef, LandmarkRef)
    case lateralLean2d(LandmarkRef, LandmarkRef)
    case chainHeight2d([LandmarkRef])
    case sagittalLean(LandmarkRef, LandmarkRef)
    case sagittalLean2d(LandmarkRef, LandmarkRef)

    public enum Arguments: Sendable {
        case metrics(count: Int)
        case landmarks(count: Int)
        case landmarkChain(min: Int, max: Int)
    }

    /// JSON key and argument shape of every function, in source order then specs/04 order.
    public static let functions: [(name: String, arguments: Arguments)] = [
        ("angle", .landmarks(count: 3)),
        ("avg", .metrics(count: 2)),
        ("absDiff", .metrics(count: 2)),
        ("max", .metrics(count: 2)),
        ("diffY", .landmarks(count: 2)),
        ("angleFromVertical", .landmarks(count: 2)),
        ("kneeInwardRatio", .landmarks(count: 3)),
        ("signedOffset", .landmarks(count: 3)),
        ("lateralLean", .landmarks(count: 2)),
        ("chainHeight", .landmarkChain(min: 2, max: 6)),
        ("min", .metrics(count: 2)),
        ("angle2d", .landmarks(count: 3)),
        ("lateralLean2d", .landmarks(count: 2)),
        ("chainHeight2d", .landmarkChain(min: 2, max: 6)),
        ("sagittalLean", .landmarks(count: 2)),
        ("sagittalLean2d", .landmarks(count: 2)),
    ]

    public var functionName: String {
        switch self {
        case .angle: "angle"
        case .avg: "avg"
        case .absDiff: "absDiff"
        case .max: "max"
        case .diffY: "diffY"
        case .angleFromVertical: "angleFromVertical"
        case .kneeInwardRatio: "kneeInwardRatio"
        case .signedOffset: "signedOffset"
        case .lateralLean: "lateralLean"
        case .chainHeight: "chainHeight"
        case .min: "min"
        case .angle2d: "angle2d"
        case .lateralLean2d: "lateralLean2d"
        case .chainHeight2d: "chainHeight2d"
        case .sagittalLean: "sagittalLean"
        case .sagittalLean2d: "sagittalLean2d"
        }
    }

    /// Metric names this definition depends on (empty for landmark functions).
    public var metricDependencies: [String] {
        switch self {
        case .avg(let a, let b), .absDiff(let a, let b), .max(let a, let b), .min(let a, let b): [a, b]
        default: []
        }
    }

    public var landmarks: [LandmarkRef] {
        switch self {
        case .angle(let a, let b, let c), .kneeInwardRatio(let a, let b, let c),
             .signedOffset(let a, let b, let c), .angle2d(let a, let b, let c):
            [a, b, c]
        case .diffY(let a, let b), .angleFromVertical(let a, let b), .lateralLean(let a, let b),
             .lateralLean2d(let a, let b), .sagittalLean(let a, let b), .sagittalLean2d(let a, let b):
            [a, b]
        case .chainHeight(let chain), .chainHeight2d(let chain):
            chain
        case .avg, .absDiff, .max, .min:
            []
        }
    }

    /// Whether the function reads world (3D) coordinates (ref 04 table, specs/03).
    public var usesWorld: Bool {
        switch self {
        case .angle, .lateralLean, .chainHeight, .sagittalLean: true
        default: false
        }
    }
}

public struct Metric: Sendable, Equatable {
    public var name: String
    public var definition: MetricDefinition
}

public struct RepZone: Sendable, Equatable {
    public var enter: Double
    public var exit: Double
}

public struct RepDefinition: Sendable, Equatable {
    public var metric: String
    public var start: RepZone
    public var target: RepZone
    public var attemptMinExcursion: Double
    public var minDurationMs: Int
    public var maxDurationMs: Int
}

public struct Fault: Sendable, Equatable {
    public var id: String
    public var name: LocalizedText
    public var severity: Severity
    public var check: String
    public var views: [CameraView]?
    public var cue: LocalizedText
    public var affectsValidity: Bool
    public var cooldownMs: Int
    public var minConsecutiveReps: Int
    /// Defaults to 150 ms on `during_rep` checks; absent otherwise.
    public var holdMs: Int?
}

public struct Camera: Sendable, Equatable {
    public var views: [CameraView]
    public var minVisibleLandmarks: [LandmarkRef]
    public var minVisibility: Double
    public var posture: Posture
    public var setupHint: LocalizedText
}

public struct Smoothing: Sendable, Equatable {
    /// Always `one_euro`.
    public var method: String
    public var minCutoff: Double
    public var beta: Double
}

public struct HeadTarget: Sendable, Equatable {
    public var lateral: Double?
    public var height: Double?
    /// Side view lean-back threshold (specs/04).
    public var back: Double?
    public var sides: [PersonSide]?
}

public struct Overlay: Sendable, Equatable {
    public var headTarget: HeadTarget?
}

/// Origin of a template derived from a source template (specs/04); informational.
public struct DerivedFrom: Sendable, Equatable {
    public var id: String
    public var version: Int
    public var commit: String
}

public struct RulePack: Sendable, Equatable {
    public var id: String
    public var version: Int
    public var status: RulePackStatus
    public var name: LocalizedText
    public var howTo: LocalizedText?
    public var derivedFrom: DerivedFrom?
    public var type: RulePackType
    public var camera: Camera
    /// In file order.
    public var metrics: [Metric]
    public var rep: RepDefinition
    public var readyPose: String
    public var faults: [Fault]
    public var smoothing: Smoothing
    public var overlay: Overlay?

    public func metric(named name: String) -> MetricDefinition? {
        metrics.first { $0.name == name }?.definition
    }

    public var metricNames: [String] { metrics.map(\.name) }
}
