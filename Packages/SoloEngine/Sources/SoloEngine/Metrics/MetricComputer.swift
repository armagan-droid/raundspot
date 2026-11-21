import Foundation

// Metric functions from the closed list (ref 04 "Metrik fonksiyonları"),
// translated from the source `metrics/compute.ts` (commit c2fe3fd). Angles,
// lateralLean and chainHeight use world (3D) coordinates; everything else uses
// image (2D) coordinates.

/// Image distance between the shoulder midpoint and the hip midpoint (ref 04 "Gövde boyu").
public func torsoLength(_ frame: Frame) -> Double {
    let ls = frame[image: .leftShoulder], rs = frame[image: .rightShoulder]
    let lh = frame[image: .leftHip], rh = frame[image: .rightHip]
    let shoulderX: Double = (ls.x + rs.x) / 2
    let shoulderY: Double = (ls.y + rs.y) / 2
    let hipX: Double = (lh.x + rh.x) / 2
    let hipY: Double = (lh.y + rh.y) / 2
    return JSMath.hypot(shoulderX - hipX, shoulderY - hipY)
}

enum MetricMath {
    static func dist(_ a: Landmark, _ b: Landmark) -> Double { JSMath.hypot(a.x - b.x, a.y - b.y) }
    static func dist3(_ a: Landmark, _ b: Landmark) -> Double { JSMath.hypot(a.x - b.x, a.y - b.y, a.z - b.z) }

    static func angle3(_ a: Landmark, _ b: Landmark, _ c: Landmark) -> Double {
        let ux = a.x - b.x, uy = a.y - b.y, uz = a.z - b.z
        let vx = c.x - b.x, vy = c.y - b.y, vz = c.z - b.z
        let n = JSMath.hypot(ux, uy, uz) * JSMath.hypot(vx, vy, vz)
        if n == 0 { return .nan }
        return acos(JSMath.clampUnit((ux * vx + uy * vy + uz * vz) / n)) * JSMath.degreesPerRadian
    }

    static func diffY(_ frame: Frame, _ a: Landmark, _ b: Landmark) -> Double {
        JSMath.safeDiv(b.y - a.y, torsoLength(frame))
    }

    static func angleFromVertical(_ a: Landmark, _ b: Landmark) -> Double {
        let vx = b.x - a.x, vy = b.y - a.y
        let n = JSMath.hypot(vx, vy)
        if n == 0 { return .nan }
        return acos(JSMath.clampUnit(-vy / n)) * JSMath.degreesPerRadian  // image "up" is −y
    }

    static func kneeInwardRatio(_ frame: Frame, _ hip: Landmark, _ knee: Landmark, _ ankle: Landmark) -> Double {
        if hip.y == ankle.y { return .nan }
        let t = (knee.y - hip.y) / (ankle.y - hip.y)
        let lineX = hip.x + t * (ankle.x - hip.x)
        let midX = (frame[image: .leftHip].x + frame[image: .rightHip].x) / 2
        let inward = JSMath.sign(midX - lineX)
        if inward == 0 { return .nan }
        return JSMath.safeDiv(inward * (knee.x - lineX), dist(hip, knee) + dist(knee, ankle))
    }

    static func signedOffset(_ a: Landmark, _ b: Landmark, _ c: Landmark) -> Double {
        let wx = c.x - a.x, wy = c.y - a.y
        let len = JSMath.hypot(wx, wy)
        if len == 0 { return .nan }
        // Unit normal pointing image-up (−y); +x if the line is vertical.
        var nx = -wy / len
        var ny = wx / len
        if ny > 0 || (ny == 0 && nx < 0) {
            nx = -nx
            ny = -ny
        }
        return ((b.x - a.x) * nx + (b.y - a.y) * ny) / len
    }

    /// Signed frontal-plane lean of the b→a line toward the person's left.
    /// NaN when the person is turned sideways.
    static func lateralLean(_ frame: Frame, _ a: Landmark, _ b: Landmark) -> Double {
        let ls = frame[world: .leftShoulder], rs = frame[world: .rightShoulder]
        let dx = ls.x - rs.x
        if Swift.abs(dx) < 0.5 * dist3(ls, rs) { return .nan }
        return JSMath.safeDiv(JSMath.sign(dx) * (a.x - b.x), dist3(a, b))
    }

    /// First point's height above the last over the chain's summed segment
    /// lengths (1 = straight and upright). World y points down.
    static func chainHeight(_ points: [Landmark]) -> Double {
        var length = 0.0
        for i in 1..<points.count { length += dist3(points[i - 1], points[i]) }
        return JSMath.safeDiv(points[points.count - 1].y - points[0].y, length)
    }
}

/// Computes a rule pack's metrics for one frame.
public struct MetricComputer: Sendable {
    /// Metric names in evaluation order (dependencies first).
    public let order: [String]
    private let definitions: [String: MetricDefinition]

    public enum BuildError: Error, Equatable {
        case cycle(String)
        case undefinedMetric(String)
    }

    public init(metrics: [Metric]) throws(BuildError) {
        var defs: [String: MetricDefinition] = [:]
        for m in metrics { defs[m.name] = m.definition }
        definitions = defs
        order = try Self.topologicalOrder(metrics.map(\.name), defs)
    }

    public init(pack: RulePack) throws(BuildError) {
        try self.init(metrics: pack.metrics)
    }

    public func compute(_ frame: Frame, near: PersonSide) -> [String: Double] {
        var values: [String: Double] = [:]
        values.reserveCapacity(order.count)
        for name in order {
            values[name] = evaluate(definitions[name]!, frame, near, values)
        }
        return values
    }

    /// Landmarks a metric depends on, transitively, with near_/far_ resolved.
    public func landmarks(of metric: String, near: PersonSide) -> Set<LandmarkName> {
        var out = Set<LandmarkName>()
        func visit(_ name: String) {
            guard let def = definitions[name] else { return }
            for ref in def.landmarks { out.insert(ref.resolve(near: near)) }
            def.metricDependencies.forEach(visit)
        }
        visit(metric)
        return out
    }

    private func evaluate(_ def: MetricDefinition, _ frame: Frame, _ near: PersonSide, _ values: [String: Double]) -> Double {
        func img(_ r: LandmarkRef) -> Landmark { frame.image[r.resolve(near: near).index] }
        func wld(_ r: LandmarkRef) -> Landmark { frame.world[r.resolve(near: near).index] }
        func value(_ name: String) -> Double { values[name] ?? .nan }

        switch def {
        case .angle(let a, let b, let c):
            return MetricMath.angle3(wld(a), wld(b), wld(c))
        case .avg(let a, let b):
            return (value(a) + value(b)) / 2
        case .absDiff(let a, let b):
            return Swift.abs(value(a) - value(b))
        case .max(let a, let b):
            // Either-side techniques: the side that cannot be computed does not count (ref 04).
            let x = value(a), y = value(b)
            return x.isNaN ? y : y.isNaN ? x : Swift.max(x, y)
        case .diffY(let a, let b):
            return MetricMath.diffY(frame, img(a), img(b))
        case .angleFromVertical(let a, let b):
            return MetricMath.angleFromVertical(img(a), img(b))
        case .kneeInwardRatio(let h, let k, let a):
            return MetricMath.kneeInwardRatio(frame, img(h), img(k), img(a))
        case .signedOffset(let a, let b, let c):
            return MetricMath.signedOffset(img(a), img(b), img(c))
        case .lateralLean(let a, let b):
            return MetricMath.lateralLean(frame, wld(a), wld(b))
        case .chainHeight(let chain):
            return MetricMath.chainHeight(chain.map(wld))
        case .min, .angle2d, .lateralLean2d, .chainHeight2d, .sagittalLean, .sagittalLean2d:
            // specs/04 additions are implemented with their tests in T2.7
            // (AC-4.3). Until then they are unknown, which never raises a fault.
            return .nan
        }
    }

    private static func topologicalOrder(_ names: [String], _ defs: [String: MetricDefinition]) throws(BuildError) -> [String] {
        var order: [String] = []
        var state: [String: Bool] = [:]  // false = visiting, true = done
        func visit(_ name: String) throws(BuildError) {
            if state[name] == true { return }
            if state[name] == false { throw .cycle(name) }
            guard let def = defs[name] else { throw .undefinedMetric(name) }
            state[name] = false
            for dep in def.metricDependencies { try visit(dep) }
            state[name] = true
            order.append(name)
        }
        for name in names { try visit(name) }
        return order
    }
}

/// The side with the higher mean visibility over the frames; ties → left (ref 04).
public func chooseNearSide(_ frames: [Frame]) -> PersonSide {
    var left = 0.0, right = 0.0
    let pairs = LandmarkRef.bilateralJoints.map {
        (LandmarkName(side: .left, joint: $0)!.index, LandmarkName(side: .right, joint: $0)!.index)
    }
    for frame in frames {
        for (l, r) in pairs {
            left += frame.image[l].visibility
            right += frame.image[r].visibility
        }
    }
    return right > left ? .right : .left
}
