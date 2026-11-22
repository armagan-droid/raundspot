import Foundation

/// Seeded PRNG (mulberry32), bit-identical to the source
/// `testing/random.ts`, so synthetic fixtures are reproducible across the two
/// implementations. A reference type: one generator feeds a whole sequence.
public final class SeededRandom {
    private var a: UInt32

    public init(seed: Int) {
        a = UInt32(truncatingIfNeeded: seed)  // seed >>> 0
    }

    /// Uniform in [0, 1).
    public func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)            // Math.imul(t ^ (t >>> 15), t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))   // t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    /// Normal distribution (Box–Muller); `1 - next()` keeps the log argument in (0, 1].
    public func gaussian(_ sigma: Double) -> Double {
        let u = 1 - next()
        let v = next()
        return sigma * (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
    }
}
