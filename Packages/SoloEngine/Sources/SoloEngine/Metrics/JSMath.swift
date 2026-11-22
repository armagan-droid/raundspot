import Foundation

/// JavaScript `Math` semantics where they differ from Swift. Metric values
/// must equal the source engine's within 1e-9 (specs/03 "Eşitlik kuralları"),
/// so NaN handling has to match exactly.
enum JSMath {
    /// `Math.min(a, b)`: NaN if either is NaN (`Swift.min(1, .nan)` is 1).
    static func min(_ a: Double, _ b: Double) -> Double {
        a.isNaN || b.isNaN ? .nan : Swift.min(a, b)
    }

    /// `Math.max(a, b)`: NaN if either is NaN.
    static func max(_ a: Double, _ b: Double) -> Double {
        a.isNaN || b.isNaN ? .nan : Swift.max(a, b)
    }

    /// `Math.max(-1, Math.min(1, v))`.
    static func clampUnit(_ v: Double) -> Double { max(-1, min(1, v)) }

    /// `Math.sign`: -1, 0 (keeping the sign of zero), 1, or NaN.
    static func sign(_ v: Double) -> Double {
        if v.isNaN { return .nan }
        if v == 0 { return v }
        return v > 0 ? 1 : -1
    }

    /// `Math.hypot(a, b)`: infinity wins over NaN, like C `hypot`.
    static func hypot(_ a: Double, _ b: Double) -> Double { Foundation.hypot(a, b) }

    /// `Math.hypot(a, b, c)`: infinity wins over NaN; otherwise scaled to
    /// avoid overflow. Differs from V8 by at most a few ULPs.
    static func hypot(_ a: Double, _ b: Double, _ c: Double) -> Double {
        let values = [Swift.abs(a), Swift.abs(b), Swift.abs(c)]
        if values.contains(.infinity) { return .infinity }
        if values.contains(where: \.isNaN) { return .nan }
        let m = values.max()!
        if m == 0 { return 0 }
        let sum = values.reduce(0) { $0 + ($1 / m) * ($1 / m) }
        return sum.squareRoot() * m
    }

    /// `a / b` that is NaN when `b` is 0 (source `safeDiv`).
    static func safeDiv(_ a: Double, _ b: Double) -> Double { b == 0 ? .nan : a / b }

    static let degreesPerRadian = 180 / Double.pi
}
