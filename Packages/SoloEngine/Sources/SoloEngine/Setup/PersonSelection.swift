// Person selection when the camera sees several people (ref 07 "Seçim
// kuralları"; source `setup/select-person.ts`). Other people's landmarks are
// dropped in the same frame and kept nowhere.

public struct ImagePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PersonTrack: Sendable, Equatable {
    /// Hip center of the tracked person in image coordinates.
    public var hip: ImagePoint

    public init(hip: ImagePoint) {
        self.hip = hip
    }
}

public struct PersonSelection: Sendable, Equatable {
    public var frame: Frame?
    public var track: PersonTrack?
    public var ambiguous: Bool
}

public enum PersonSelectionRules {
    public static let trackRadius = 0.15
    public static let ambiguityRatio = 0.8
    public static let visibleThreshold = 0.5
    /// `numPoses = 2` (ref 07): candidates come sorted by confidence; the rest are dropped (specs/03).
    public static let maxCandidates = 2
}

private func hipCenter(_ f: Frame) -> ImagePoint {
    let l = f[image: .leftHip], r = f[image: .rightHip]
    return ImagePoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
}

/// Box area × centrality (1 − distance of the box center from the image center).
public func personScore(_ f: Frame) -> Double {
    let visible = f.image.filter { $0.visibility >= PersonSelectionRules.visibleThreshold }
    let use = visible.count >= 2 ? visible : f.image
    // Math.min(...xs) / Math.max(...xs): NaN propagates
    let x0 = use.map(\.x).reduce(.infinity, JSMath.min), x1 = use.map(\.x).reduce(-.infinity, JSMath.max)
    let y0 = use.map(\.y).reduce(.infinity, JSMath.min), y1 = use.map(\.y).reduce(-.infinity, JSMath.max)
    let area = (x1 - x0) * (y1 - y0)
    let centrality = JSMath.max(0, 1 - JSMath.hypot((x0 + x1) / 2 - 0.5, (y0 + y1) / 2 - 0.5))
    return area * centrality
}

public func selectPerson(_ candidates: [Frame], track: PersonTrack? = nil) -> PersonSelection {
    let candidates = Array(candidates.prefix(PersonSelectionRules.maxCandidates))
    if candidates.isEmpty { return PersonSelection(frame: nil, track: track, ambiguous: false) }

    if let track {
        var best: Frame?
        var bestDist = PersonSelectionRules.trackRadius
        for c in candidates {
            let h = hipCenter(c)
            let d = JSMath.hypot(h.x - track.hip.x, h.y - track.hip.y)
            if d < bestDist {
                best = c
                bestDist = d
            }
        }
        if let best { return PersonSelection(frame: best, track: PersonTrack(hip: hipCenter(best)), ambiguous: false) }
    }

    // stable descending sort; a NaN score compares equal, as with a JS comparator
    let ranked = candidates.enumerated().map { (i: $0.offset, c: $0.element, s: personScore($0.element)) }
        .sorted { a, b in a.s > b.s || (!(b.s > a.s) && a.i < b.i) }
    let first = ranked[0]
    if ranked.count > 1, ranked[1].s > first.s * PersonSelectionRules.ambiguityRatio {
        return PersonSelection(frame: nil, track: nil, ambiguous: true)
    }
    return PersonSelection(frame: first.c, track: PersonTrack(hip: hipCenter(first.c)), ambiguous: false)
}
