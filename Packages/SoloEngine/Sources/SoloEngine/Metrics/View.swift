// Camera view detection (ref 04 "Görünüm tespiti"): shoulder width over
// torso length in the image. Translated from the source `metrics/view.ts`.

/// View detected by the engine; templates only declare `front`/`side`.
public enum View: String, CaseIterable, Sendable, Hashable {
    case front, side, ambiguous

    public init(_ view: CameraView) {
        self = view == .front ? .front : .side
    }
}

public struct ViewThresholds: Sendable, Equatable {
    /// ratio ≥ front → front
    public var front: Double
    /// ratio ≤ side → side
    public var side: Double

    public static let `default` = ViewThresholds(front: 0.45, side: 0.2)
}

public func detectView(_ frame: Frame, thresholds: ViewThresholds = .default) -> View {
    let torso = torsoLength(frame)
    if torso == 0 { return .ambiguous }
    let ratio = Swift.abs(frame[image: .leftShoulder].x - frame[image: .rightShoulder].x) / torso
    if ratio >= thresholds.front { return .front }
    if ratio <= thresholds.side { return .side }
    return .ambiguous
}

/// Most frequent view; ties and empty input are ambiguous.
public func dominantView<S: Sequence>(_ views: S) -> View where S.Element == View {
    var counts: [View: Int] = [:]
    for v in views { counts[v, default: 0] += 1 }
    guard let best = counts.values.max() else { return .ambiguous }
    let leaders = counts.filter { $0.value == best }
    return leaders.count == 1 ? leaders.first!.key : .ambiguous
}
