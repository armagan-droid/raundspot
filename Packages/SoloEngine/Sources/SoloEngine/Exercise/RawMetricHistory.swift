/// Unsmoothed metric values of recent frames (specs/05 "Tepki süresi": the
/// reaction moment is interpolated on the raw metric, because the One Euro
/// filter adds delay). Keeps frames newer than `retentionMs` before the latest.
public struct RawMetricHistory: Sendable {
    public let retentionMs: Double
    private var storage: [Snapshot] = []
    private var head = 0

    public init(retentionMs: Double) {
        self.retentionMs = retentionMs
    }

    /// Frames in time order, oldest first.
    public var frames: ArraySlice<Snapshot> { storage[head...] }

    /// Frames with `t >= from`, oldest first.
    public func frames(since from: Double) -> ArraySlice<Snapshot> {
        let all = frames
        let first = all.firstIndex { $0.t >= from } ?? all.endIndex
        return all[first...]
    }

    mutating func append(_ snapshot: Snapshot) {
        storage.append(snapshot)
        let cutoff = snapshot.t - retentionMs
        while head < storage.count - 1, storage[head].t < cutoff { head += 1 }
        if head > 256, head * 2 > storage.count {
            storage.removeFirst(head)
            head = 0
        }
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }
}
