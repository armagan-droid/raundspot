import Foundation

// Calorie estimate (specs/08): net kcal = (MET − 1) × kg × hours, per segment of the session's timeline.
// Always an estimate; HealthKit gets the net value.

public struct EnergyError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var description: String { message }
}

/// `exercises/energy/met.json`: MET by segment kind, with its Compendium code and status.
public struct METTable: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public var met: Double
        public var code: String?
        public var status: String
    }

    public var rows: [String: Row]

    public func met(_ kind: String) -> Double? { rows[kind]?.met }

    public static func parse(_ json: JSONValue) throws -> METTable {
        guard json["formatVersion"]?.numberValue == 1, let segs = json["segments"]?.objectValue else {
            throw EnergyError(message: "met.json: formatVersion 1 and segments")
        }
        var rows: [String: Row] = [:]
        for (kind, v) in segs.entries {
            guard let met = v["met"]?.numberValue, met >= 1, met < 25,
                  let status = v["status"]?.stringValue, ["verified", "assumption", "unverified"].contains(status) else {
                throw EnergyError(message: "met.json: segments.\(kind)")
            }
            rows[kind] = Row(met: met, code: v["code"]?.stringValue, status: status)
        }
        return METTable(rows: rows)
    }
}

public struct EnergySegment: Sendable, Equatable {
    public var kind: String
    public var durationMs: Double
}

/// The session's timeline as segments (specs/08): a kind runs until the next one; a pause stops the clock.
public struct EnergyTimeline: Sendable, Equatable {
    public private(set) var segments: [EnergySegment] = []
    private var currentKind: String?
    private var currentSince: Double = 0
    private var pausedKind: String?

    public init() {}

    public mutating func enter(_ kind: String, at t: Double) {
        close(at: t)
        pausedKind = nil
        currentKind = kind
        currentSince = t
    }

    public mutating func pause(at t: Double) {
        guard let k = currentKind else { return }
        close(at: t)
        pausedKind = k
    }

    public mutating func resume(at t: Double) {
        guard currentKind == nil, let k = pausedKind else { return }
        currentKind = k
        currentSince = t
        pausedKind = nil
    }

    public mutating func finish(at t: Double) {
        close(at: t)
        pausedKind = nil
    }

    private mutating func close(at t: Double) {
        if let k = currentKind, t > currentSince { segments.append(EnergySegment(kind: k, durationMs: t - currentSince)) }
        currentKind = nil
    }
}

/// Fraction of the active minutes with at least one heart rate sample (specs/08 "Yeterlilik").
public enum HeartRateCoverage {
    public static func fraction(_ sampleTimes: [Double], active: [ClosedRange<Double>]) -> Double {
        var minutes = 0, covered = 0
        for r in active {
            var start = r.lowerBound
            while start < r.upperBound {
                let end = Swift.min(start + 60_000, r.upperBound)
                minutes += 1
                if sampleTimes.contains(where: { $0 >= start && $0 < end }) { covered += 1 }
                start = end
            }
        }
        return minutes == 0 ? 0 : Double(covered) / Double(minutes)
    }
}

public enum EnergyMethod: String, Sendable, Equatable { case met, heartRate = "heart_rate" }

public enum BiologicalSex: Sendable, Equatable { case male, female }

/// `exercises/energy/keytel.json` (specs/08 "Nabızla iyileştirme").
public struct KeytelEquations: Sendable, Equatable {
    public struct Row: Sendable, Equatable { public var a, b, c, d: Double }
    public var verified: Bool
    public var male: Row
    public var female: Row

    /// kJ/min → kcal/min.
    public func kcalPerMinute(sex: BiologicalSex, heartRate: Double, weightKg: Double, age: Double) -> Double {
        let r = sex == .male ? male : female
        return (r.a + r.b * heartRate + r.c * weightKg + r.d * age) / 4.184
    }

    public static func parse(_ json: JSONValue) throws -> KeytelEquations {
        func row(_ k: String) throws -> Row {
            guard let o = json[k], let a = o["a"]?.numberValue, let b = o["b"]?.numberValue, let c = o["c"]?.numberValue,
                  let d = o["d"]?.numberValue else { throw EnergyError(message: "keytel.json: \(k)") }
            return Row(a: a, b: b, c: c, d: d)
        }
        guard json["formatVersion"]?.numberValue == 1, case .bool(let v)? = json["verified"] else {
            throw EnergyError(message: "keytel.json: formatVersion 1 and verified")
        }
        return KeytelEquations(verified: v, male: try row("male"), female: try row("female"))
    }
}

public enum Energy {
    /// Net kcal; nil without a weight (no estimate shown, no energy sample written; specs/08 "Kilo").
    public static func netKcal(_ segments: [EnergySegment], weightKg: Double?, table: METTable) throws -> Double? {
        guard let kg = weightKg else { return nil }
        var total = 0.0
        for s in segments {
            guard let met = table.met(s.kind) else { throw EnergyError(message: "no MET for '\(s.kind)'") }
            total += (met - 1) * kg * s.durationMs / 3_600_000
        }
        return total
    }

    /// specs/08: heart rate when the coverage is enough, age and sex are known and the equations are verified.
    public static func method(coverage: Double, ageAndSexKnown: Bool, equationsVerified: Bool) -> EnergyMethod {
        coverage >= 0.70 - 1e-9 && ageAndSexKnown && equationsVerified ? .heartRate : .met
    }

    /// HealthKit's last weight if newer than 90 days, else the profile's; never stored from HealthKit.
    public static func weight(healthKit: (kg: Double, date: Date)?, profile: Double?, now: Date) -> Double? {
        if let h = healthKit, now.timeIntervalSince(h.date) <= 90 * 86_400 { return h.kg }
        return profile
    }

    /// "≈ 135 kcal (tahmin)": rounded to 5.
    public static func display(_ kcal: Double) -> Int { Int((kcal / 5).rounded()) * 5 }
}
