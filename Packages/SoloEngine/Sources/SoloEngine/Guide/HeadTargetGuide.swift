import Foundation

// Eskiv target circle and guide marks (ref 08 A5 "Hedef dairesi ve
// yönlendirme işaretleri", specs/12 T2, `overlay.headTarget` in ref/specs 04).
// Pure geometry in image coordinates (x right, y down, normalized, never
// mirrored); the app applies the preview transform. The marks only guide:
// counting is always the rep rule.

public struct GuidePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct HeadGuide: Sendable, Equatable {
    public enum Mode: String, Sendable, Equatable {
        /// The head is at the center: the next balloon blinks, an arrow points to it.
        case go
        /// The head passed the threshold: circle and balloon green, the arrow points back to the center.
        case back
    }

    public struct Balloon: Sendable, Equatable {
        public var point: GuidePoint
        /// The balloon the head should go to now.
        public var next: Bool
    }

    public var mode: Mode
    /// Head rest position: followed while the head is in the start zone, held otherwise.
    public var center: GuidePoint
    /// In image heights (pixels = radius × image height).
    public var radius: Double
    public var balloons: [Balloon]
    /// Dashed duck line (front view), image y.
    public var duckLineY: Double?
    /// Dashed lean-back line (side view), image x.
    public var backLineX: Double?
    public var head: GuidePoint
    public var arrowTo: GuidePoint
}

/// Follows one set and produces the marks for each frame.
public struct HeadGuideTracker: Sendable {
    public let target: HeadTarget
    public let rep: RepDefinition
    public let nearSide: PersonSide
    private let sides: [PersonSide]
    private var nextIndex = 0
    private var mode: HeadGuide.Mode = .go
    private var rest: Rest?
    /// The duck line follows the live shoulder width and ankles (lightly smoothed),
    /// so the head crosses it where the metric crosses the threshold.
    private var live: (ankleV: Double, shoulder: Double)?
    public static let liveAlpha = 0.5
    /// Rest smoothing per frame while not in a rep.
    public static let restAlpha = 0.25

    private struct Rest: Sendable {
        var nose: (u: Double, v: Double)
        var hip: (u: Double, v: Double)
        var ankleV: Double
        var shoulder: Double
    }

    public init?(_ pack: RulePack, nearSide: PersonSide) {
        guard let t = pack.overlay?.headTarget, t.lateral != nil || t.height != nil || t.back != nil else { return nil }
        target = t
        rep = pack.rep
        self.nearSide = nearSide
        // the first target is the person's left (ref 08)
        sides = t.lateral == nil ? [] : (t.sides ?? [.left, .right])
    }

    /// Lower values are the target (duck, bob & weave).
    private var decreasing: Bool { rep.target.enter < rep.start.enter }

    public mutating func update(_ frame: Frame, repMetric: Double?, inRep: Bool, minVisibility: Double) -> HeadGuide? {
        let k = frame.imageAspect
        func p(_ n: LandmarkName) -> (u: Double, v: Double)? {
            let l = frame[image: n]
            guard l.visibility >= minVisibility, l.x.isFinite, l.y.isFinite else { return nil }
            return (l.x * k, l.y)
        }
        func mid(_ a: LandmarkName, _ b: LandmarkName) -> (u: Double, v: Double)? {
            switch (p(a), p(b)) {
            case let (x?, y?): ((x.u + y.u) / 2, (x.v + y.v) / 2)
            case let (x?, nil): x
            case let (nil, y?): y
            default: nil
            }
        }
        guard let nose = p(.nose), let hip = mid(.leftHip, .rightHip) else { return nil }
        let ls = p(.leftShoulder), rs = p(.rightShoulder)
        let shoulder = ls.flatMap { a in rs.map { b in JSMath.hypot(a.u - b.u, a.v - b.v) } }
        let ankleV = mid(.leftAnkle, .rightAnkle)?.v

        // mode: go → back when the rep metric reaches the target; back → go at the start zone
        var inStartZone = true
        if let m = repMetric, m.isFinite {
            let reached = decreasing ? m <= rep.target.enter : m >= rep.target.enter
            let atStart = decreasing ? m >= rep.start.enter : m <= rep.start.enter
            inStartZone = atStart
            if mode == .go, reached {
                mode = .back
            } else if mode == .back, atStart {
                mode = .go
                if !sides.isEmpty { nextIndex = (nextIndex + 1) % sides.count }
            }
        }

        // rest follows the body only between reps, with the head in the start zone
        let now = Rest(nose: nose, hip: hip, ankleV: ankleV ?? rest?.ankleV ?? .nan, shoulder: shoulder ?? rest?.shoulder ?? .nan)
        if rest == nil {
            rest = now
        } else if !inRep, mode == .go, inStartZone {
            let a = Self.restAlpha
            func s(_ x: Double, _ y: Double) -> Double { x.isFinite ? (y.isFinite ? x + a * (y - x) : x) : y }
            rest = Rest(nose: (s(rest!.nose.u, nose.u), s(rest!.nose.v, nose.v)), hip: (s(rest!.hip.u, hip.u), s(rest!.hip.v, hip.v)),
                        ankleV: s(rest!.ankleV, now.ankleV), shoulder: s(rest!.shoulder, now.shoulder))
        }
        let r = rest!
        if let ankleV, let shoulder {
            if let l = live {
                let a = Self.liveAlpha
                live = (l.ankleV + a * (ankleV - l.ankleV), l.shoulder + a * (shoulder - l.shoulder))
            } else {
                live = (ankleV, shoulder)
            }
        }
        let length = JSMath.hypot(r.nose.u - r.hip.u, r.nose.v - r.hip.v)
        guard length > 0 else { return nil }

        // the person's left in the image: where the left shoulder is (front view)
        let leftDir: Double = {
            guard let ls, let rs else { return 1 }
            return ls.u >= rs.u ? 1 : -1
        }()
        func dir(_ side: PersonSide) -> Double { side == .left ? leftDir : -leftDir }

        var balloons: [(u: Double, v: Double)] = []
        var radius = 0.0
        var duckLineV: Double?
        var backLineU: Double?

        if let height = target.height, let l = live {
            // heightOverShoulders2d = (ankle.y − nose.y) / shoulder width (specs/04, specs/12 T2)
            let line = l.ankleV - height * l.shoulder
            duckLineV = line
            let below = line + 0.35 * l.shoulder
            if let lateral = target.lateral {
                balloons = sides.map { (r.nose.u + dir($0) * lateral * length, below) }
            } else {
                balloons = [(r.nose.u, below)]
            }
            radius = 0.35 * l.shoulder
        } else if let lateral = target.lateral {
            // lateralLean2d(nose, hip) = sideways offset / |nose − hip|: the balloon on that arc around the hip
            let s = Swift.min(lateral, 0.95)
            let c = (1 - s * s).squareRoot()
            balloons = sides.map { (r.hip.u + dir($0) * s * length, r.hip.v - c * length) }
            radius = s * length
        } else if let back = target.back {
            // sagittalLean2d(nose, near_hip): behind = away from the nose side of the near ear
            let ear = p(LandmarkName(side: nearSide, joint: "ear")!)
            let front: Double = ear.map { nose.u >= $0.u ? 1 : -1 } ?? 1
            let s = Swift.min(back, 0.95)
            let c = (1 - s * s).squareRoot()
            let u = r.hip.u - front * s * length
            backLineU = u
            balloons = [(u, r.hip.v - c * length)]
            radius = 0.12 * length
        }
        guard !balloons.isEmpty else { return nil }

        let nextBalloon = sides.isEmpty ? 0 : Swift.min(nextIndex, balloons.count - 1)
        func g(_ q: (u: Double, v: Double)) -> GuidePoint { GuidePoint(x: q.u / k, y: q.v) }
        let center = g(r.nose)
        let target = g(balloons[nextBalloon])
        return HeadGuide(
            mode: mode, center: center, radius: radius,
            balloons: balloons.enumerated().map { HeadGuide.Balloon(point: g($0.element), next: $0.offset == nextBalloon) },
            duckLineY: duckLineV, backLineX: backLineU.map { $0 / k },
            head: g(nose), arrowTo: mode == .go ? target : center)
    }
}
