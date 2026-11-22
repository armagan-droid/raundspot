import Foundation

// One Euro filter (Casiez et al., 2012) on metric values (ref 04
// "Yumuşatma"), translated from the source `metrics/smoothing.ts`.

public struct OneEuroParams: Sendable, Equatable {
    public var minCutoff: Double
    public var beta: Double
    /// Cutoff for the derivative filter, Hz.
    public var dCutoff: Double

    public init(minCutoff: Double, beta: Double, dCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    public init(_ smoothing: Smoothing) {
        self.init(minCutoff: smoothing.minCutoff, beta: smoothing.beta)
    }
}

public struct OneEuroFilter: Sendable {
    public let params: OneEuroParams
    private var x: Double?
    private var dx = 0.0
    private var t = 0.0

    public init(_ params: OneEuroParams) { self.params = params }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        1 / (1 + 1 / (2 * Double.pi * cutoff) / dt)
    }

    /// - Parameter tMs: timestamp in milliseconds.
    /// NaN passes through without touching the state.
    public mutating func filter(_ value: Double, tMs: Double) -> Double {
        if value.isNaN { return .nan }
        guard let previous = x else {
            x = value
            t = tMs
            return value
        }
        let dt = (tMs - t) / 1000
        if dt <= 0 { return previous }
        let aD = Self.alpha(params.dCutoff, dt)
        dx = aD * ((value - previous) / dt) + (1 - aD) * dx
        let a = Self.alpha(params.minCutoff + params.beta * Swift.abs(dx), dt)
        let next = a * value + (1 - a) * previous
        x = next
        t = tMs
        return next
    }
}

/// One filter per metric (source `createMetricSmoother`).
public struct MetricSmoother: Sendable {
    public let names: [String]
    private var filters: [OneEuroFilter]

    public init(names: [String], params: OneEuroParams) {
        self.names = names
        filters = names.map { _ in OneEuroFilter(params) }
    }

    /// Smoothed value of every metric; a missing input is NaN.
    public mutating func smooth(_ values: [String: Double], tMs: Double) -> [String: Double] {
        var out: [String: Double] = [:]
        out.reserveCapacity(names.count)
        for i in names.indices {
            out[names[i]] = filters[i].filter(values[names[i]] ?? .nan, tMs: tMs)
        }
        return out
    }
}
