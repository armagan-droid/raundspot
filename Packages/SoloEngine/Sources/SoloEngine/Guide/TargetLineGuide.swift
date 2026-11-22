import Foundation

// Conditioning target line (specs/04 `overlay.targetLine`, specs/12 T2).
// Computed from the current frame so that the moving point crosses the line
// where its metric crosses `rep.target.enter`. Image coordinates, never
// mirrored. Drawing only: counting is the rep rule.

public struct TargetLineGuide: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        /// Image y of the horizontal line.
        public var y: Double
        /// Where the line is centered, image x.
        public var x: Double
        /// The points that should reach the line.
        public var movers: [GuidePoint]
    }

    public var mode: HeadGuide.Mode
    public var lines: [Line]
}

public struct TargetLineTracker: Sendable {
    private enum Part: Sendable {
        /// angle2d(a, b, c): moving a, vertex b, fixed arm b→c.
        case angle(name: String, a: LandmarkRef, b: LandmarkRef, c: LandmarkRef)
        /// diffY(a, b): moving a, line at b.y − threshold × torso length.
        case diffY(a: LandmarkRef, b: LandmarkRef)
    }

    public let rep: RepDefinition
    public let nearSide: PersonSide
    private let parts: [Part]
    private var mode: HeadGuide.Mode = .go
    /// Last known rotation side of each angle part (+1 / −1).
    private var sides: [String: Double] = [:]
    /// Lines closer than this (image heights) are drawn as one.
    public static let mergeDistance = 0.02
    /// Above this angle the side of the moving point is unclear.
    public static let ambiguousAngle = 170.0

    public init?(_ pack: RulePack, nearSide: PersonSide) {
        guard let line = pack.overlay?.targetLine else { return nil }
        let byName = Dictionary(pack.metrics.map { ($0.name, $0.definition) }, uniquingKeysWith: { a, _ in a })
        func part(_ n: String) -> Part? {
            switch byName[n] {
            case .angle2d(let a, let b, let c)?: .angle(name: n, a: a, b: b, c: c)
            case .diffY(let a, let b)?: .diffY(a: a, b: b)
            default: nil
            }
        }
        let name = line.metric ?? pack.rep.metric
        switch byName[name] {
        case .min(let a, let b)?, .max(let a, let b)?, .avg(let a, let b)?:
            parts = [part(a), part(b)].compactMap { $0 }
        default:
            parts = [part(name)].compactMap { $0 }
        }
        guard !parts.isEmpty else { return nil }
        rep = pack.rep
        self.nearSide = nearSide
    }

    private var decreasing: Bool { rep.target.enter < rep.start.enter }

    public mutating func update(_ frame: Frame, repMetric: Double?, minVisibility: Double) -> TargetLineGuide? {
        if let m = repMetric, m.isFinite {
            let reached = decreasing ? m <= rep.target.enter : m >= rep.target.enter
            let atStart = decreasing ? m >= rep.start.enter : m <= rep.start.enter
            if mode == .go, reached { mode = .back } else if mode == .back, atStart { mode = .go }
        }
        let k = frame.imageAspect
        let threshold = rep.target.enter
        // several arguments: the far leg is partly hidden in side view, so half the
        // threshold (as tracking loss, ref 04)
        let needed = parts.count > 1 ? minVisibility / 2 : minVisibility
        func p(_ ref: LandmarkRef) -> (u: Double, v: Double)? {
            let l = frame[image: ref.resolve(near: nearSide)]
            guard l.visibility >= needed, l.x.isFinite, l.y.isFinite else { return nil }
            return (l.x * k, l.y)
        }

        var lines: [TargetLineGuide.Line] = []
        // of several angle lines only the one with the most vertical fixed arm
        var bestAngle: (line: TargetLineGuide.Line, vertical: Double)?
        for part in parts {
            switch part {
            case .angle(let name, let ar, let br, let cr):
                guard let a = p(ar), let b = p(br), let c = p(cr) else { continue }
                let dl = JSMath.hypot(c.u - b.u, c.v - b.v), r = JSMath.hypot(a.u - b.u, a.v - b.v)
                guard dl > 0, r > 0 else { continue }
                let d = ((c.u - b.u) / dl, (c.v - b.v) / dl)
                let cross = d.0 * (a.v - b.v) - d.1 * (a.u - b.u)
                let dot = d.0 * (a.u - b.u) + d.1 * (a.v - b.v)
                let current = atan2(abs(cross), dot) * 180 / .pi
                if current <= Self.ambiguousAngle, cross != 0 { sides[name] = cross > 0 ? 1 : -1 }
                func point(_ sign: Double) -> (u: Double, v: Double) {
                    let phi = sign * threshold * .pi / 180
                    let ru = d.0 * cos(phi) - d.1 * sin(phi), rv = d.0 * sin(phi) + d.1 * cos(phi)
                    return (b.u + r * ru, b.v + r * rv)
                }
                let target: (u: Double, v: Double)
                if let s = sides[name] {
                    target = point(s)
                } else {
                    let p1 = point(1), p2 = point(-1)
                    target = ((p1.u + p2.u) / 2, (p1.v + p2.v) / 2)
                }
                let line = TargetLineGuide.Line(y: target.v, x: target.u / k, movers: [GuidePoint(x: a.u / k, y: a.v)])
                if bestAngle == nil || abs(d.1) > bestAngle!.vertical { bestAngle = (line, abs(d.1)) }
            case .diffY(let ar, let br):
                guard let a = p(ar), let b = p(br) else { continue }
                let torso = torsoLength(frame)
                guard torso.isFinite, torso > 0 else { continue }
                lines.append(.init(y: b.v - threshold * torso, x: b.u / k, movers: [GuidePoint(x: a.u / k, y: a.v)]))
            }
        }
        if let bestAngle { lines.append(bestAngle.line) }
        guard !lines.isEmpty else { return nil }

        // close lines become one
        var merged: [TargetLineGuide.Line] = []
        for line in lines.sorted(by: { $0.y < $1.y }) {
            if let last = merged.last, abs(last.y - line.y) < Self.mergeDistance {
                let n = Double(last.movers.count), m = Double(line.movers.count)
                merged[merged.count - 1] = .init(y: (last.y * n + line.y * m) / (n + m), x: (last.x * n + line.x * m) / (n + m),
                                                 movers: last.movers + line.movers)
            } else {
                merged.append(line)
            }
        }
        return TargetLineGuide(mode: mode, lines: merged)
    }
}
