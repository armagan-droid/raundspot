import SoloEngine

// Ports of the source `testing/timeline.ts` (`scalarSignal`) and
// `testing/player.ts` (`playSequence`).

public struct SignalRep: Sendable {
    public var to: Double
    public var durationMs: Double

    public init(to: Double, durationMs: Double = 2000) {
        self.to = to
        self.durationMs = durationMs
    }
}

public struct SignalPoint: Sendable, Equatable {
    public var t: Double
    public var repIndex: Int?
    public var progress: Double
    public var value: Double

    public init(t: Double, repIndex: Int?, progress: Double, value: Double) {
        self.t = t
        self.repIndex = repIndex
        self.progress = progress
        self.value = value
    }
}

/// A metric-level signal (e.g. `knee_angle_avg` over time) for rep counter tests.
public func scalarSignal(fps: Double, from: Double, reps: [SignalRep], leadInMs: Double = 1000, restMs: Double = 800,
                         leadOutMs: Double = 1000, noise: Double = 0, seed: Int = 1) -> [SignalPoint] {
    let rng = SeededRandom(seed: seed)
    return repTimeline(fps: fps, repDurationsMs: reps.map(\.durationMs), leadInMs: leadInMs, restMs: restMs,
                       leadOutMs: leadOutMs).map { p in
        let target = p.repIndex.map { reps[$0].to } ?? from
        let clean = from + (target - from) * p.progress
        return SignalPoint(t: p.t, repIndex: p.repIndex, progress: p.progress,
                           value: noise > 0 ? clean + rng.gaussian(noise) : clean)
    }
}

/// Feeds a sequence's frames, in order, to an engine stage and collects its
/// outputs. With `fps`, drops frames to simulate a slower device (keeps a
/// frame once ≥ 1000/fps ms passed).
public func playSequence<T>(_ seq: LandmarkSequence, fps: Double? = nil, _ consume: (Frame) -> [T]) -> [T] {
    let minGap = fps.map { 1000 / $0 - 1e-6 } ?? 0
    var out: [T] = []
    var last = -Double.infinity
    for frame in seq.frames {
        if frame.t - last < minGap { continue }
        last = frame.t
        out += consume(frame)
    }
    return out
}
