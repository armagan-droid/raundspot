// Frame → event pipeline for one exercise set (ref 04, 05; source
// `exercise/exercise-engine.ts`): metrics → smoothing → rep counter → fault
// detection → cue rules → safety pause. Each event carries its frame's time
// (specs/03 "Zaman damgalı olaylar") and the raw metrics are kept for the
// reaction time (specs/05 "Tepki süresi").

public struct ExerciseSetup: Sendable, Equatable {
    /// Dominant view for this set (from setup, ref 04 "Görünüm").
    public var view: View
    public var nearSide: PersonSide

    public init(view: View, nearSide: PersonSide) {
        self.view = view
        self.nearSide = nearSide
    }
}

public struct ExerciseEngineOptions: Sendable, Equatable {
    /// Gym setting (ref C8): pause on a major fault in two consecutive attempts.
    public var safetyPause: Bool
    /// Low visibility duration before `trackingLost`.
    public var trackingLostAfterMs: Double

    public init(safetyPause: Bool = true, trackingLostAfterMs: Double = 1000) {
        self.safetyPause = safetyPause
        self.trackingLostAfterMs = trackingLostAfterMs
    }
}

/// Turning detection (ref 04): the other side must be this much more visible for this long.
public enum SideSwitch {
    public static let margin = 0.3
    public static let afterMs = 1000.0
}

/// Whether a fault with these views is evaluated in the set's view (ref 04):
/// ambiguous → only faults valid in every view.
public func faultEnabledInView(_ views: [CameraView], _ view: View) -> Bool {
    switch view {
    case .ambiguous: views.count > 1
    case .front: views.contains(.front)
    case .side: views.contains(.side)
    }
}

/// Index of the same landmark on the other side of the body; only `left_` and
/// `right_` prefixes count, as in the source (`mouth_left` stays itself).
private let mirrorIndex: [Int] = LandmarkName.allCases.map { name in
    let raw = name.rawValue
    let other = raw.hasPrefix("left_") ? "right_" + raw.dropFirst(5)
        : raw.hasPrefix("right_") ? "left_" + raw.dropFirst(6) : raw
    return LandmarkName(rawValue: other)!.index
}

public final class ExerciseEngine {
    private struct FaultRuntime {
        var fault: CompiledFault
        var landmarks: [Int]
        /// Allowed in this set's view.
        var enabled: Bool
    }

    private struct FrameRecord {
        var values: [String: Double]
        var visible: [Bool]
    }

    private struct Attempt {
        var frames: [Double: FrameRecord] = [:]
        var detected = Set<Int>()
        var holdSince: [Double?]
        /// `during_rep` detections waiting for the attempt to be confirmed.
        var pending: [Int] = []
        var confirmed = false
        var safetyEmitted = false
    }

    public let loaded: LoadedRulePack
    private let computer: MetricComputer
    private let smoothing: OneEuroParams
    private var smoother: MetricSmoother
    private var counter: RepCounter
    private var faults: [FaultRuntime] = []
    private var readyPose: (expr: Expr, durationMs: Double, landmarks: [Int])
    private var trackingLandmarks: [Int] = []
    private let minVisibility: Double
    private let options: ExerciseEngineOptions
    private let view: View
    private var otherSideSince: Double?

    private var cuesEnabled = true
    private var attempt: Attempt?
    private var streak: [Int]
    private var lastCueAt: [Double]
    private var readySince: Double?
    private var readyFired = false
    private var lowSince: Double?
    private var trackingLost = false

    /// The body side the metrics use; follows the member when they turn in a side view (ref 04).
    public private(set) var nearSide: PersonSide
    /// Tracking landmarks (indices) not seen in the latest frame (why tracking is lost, ref 08 A5).
    public private(set) var missingLandmarks: [Int] = []
    /// Unsmoothed metrics of recent frames, at least one maximum rep duration back.
    public private(set) var rawHistory: RawMetricHistory

    /// The landmarks that must stay in view (`camera.minVisibleLandmarks` on the current side).
    public var trackedLandmarks: [Int] { trackingLandmarks }
    public var repState: RepCounterState { counter.state }
    /// Where the attempt in progress left the start zone (smoothed metric).
    public var attemptStart: Snapshot? { counter.attemptStart }

    public init(_ loaded: LoadedRulePack, setup: ExerciseSetup, options: ExerciseEngineOptions = .init()) {
        let pack = loaded.pack
        self.loaded = loaded
        self.options = options
        nearSide = setup.nearSide
        view = setup.view
        // A loaded pack has passed the dependency and cycle checks.
        computer = try! MetricComputer(pack: pack)
        smoothing = OneEuroParams(pack.smoothing)
        smoother = MetricSmoother(names: computer.order, params: smoothing)
        counter = RepCounter(pack.rep)
        minVisibility = pack.camera.minVisibility
        rawHistory = RawMetricHistory(retentionMs: Double(pack.rep.maxDurationMs) + 1000)
        readyPose = (loaded.readyPose.expr, Double(loaded.readyPose.durationMs), [])
        streak = Array(repeating: 0, count: loaded.faults.count)
        lastCueAt = Array(repeating: -.infinity, count: loaded.faults.count)
        bindSide(setup.nearSide)
    }

    /// Resolves every near/far landmark for `side`.
    private func bindSide(_ side: PersonSide) {
        let pack = loaded.pack
        nearSide = side
        func landmarks(of expr: Expr) -> [Int] {
            var set = Set<LandmarkName>()
            for m in expr.metricNames { set.formUnion(computer.landmarks(of: m, near: side)) }
            return set.map(\.index).sorted()
        }
        faults = loaded.faults.map { fault in
            FaultRuntime(fault: fault, landmarks: landmarks(of: fault.expr),
                         enabled: faultEnabledInView(fault.fault.views ?? pack.camera.views, view))
        }
        readyPose.landmarks = landmarks(of: readyPose.expr)
        trackingLandmarks = pack.camera.minVisibleLandmarks.map { $0.resolve(near: side).index }
    }

    /// Side view: when the other side of the body has been clearly better seen
    /// for a while (the member turned around), switch to it between attempts.
    private func followTurn(_ frame: Frame, _ t: Double) {
        if view != .side || counter.state == .inRep {
            otherSideSince = nil
            return
        }
        func mean(_ idx: [Int]) -> Double {
            idx.reduce(0.0) { $0 + frame.image[$1].visibility } / Double(idx.count)
        }
        let here = mean(trackingLandmarks)
        let there = mean(trackingLandmarks.map { mirrorIndex[$0] })
        if there - here < SideSwitch.margin {
            otherSideSince = nil
            return
        }
        let since = otherSideSince ?? t
        otherSideSince = since
        if t - since < SideSwitch.afterMs { return }
        otherSideSince = nil
        bindSide(nearSide.opposite)
        // the old side's history does not apply
        smoother = MetricSmoother(names: computer.order, params: smoothing)
        rawHistory.removeAll()
    }

    /// Cues are off during rest, countdown and pause (ref 05).
    public func setCuesEnabled(_ enabled: Bool) {
        cuesEnabled = enabled
    }

    /// Starts a new set: rep state and consecutive-attempt streaks are cleared.
    public func reset() {
        counter.reset()
        attempt = nil
        streak = Array(repeating: 0, count: faults.count)
    }

    public func push(_ frame: Frame) -> [TimedEvent] {
        let t = frame.t
        var events: [EngineEvent] = []
        func visibleAll(_ idx: [Int]) -> Bool { idx.allSatisfy { frame.image[$0].visibility >= minVisibility } }

        // Tracking loss means the person is out of view, not a blurry frame or a
        // turn (ref 04): half the setup threshold, and either side of the body counts.
        func seen(_ i: Int) -> Bool {
            JSMath.max(frame.image[i].visibility, frame.image[mirrorIndex[i]].visibility) >= minVisibility / 2
        }
        missingLandmarks = trackingLandmarks.filter { !seen($0) }
        trackTracking(t, visible: missingLandmarks.isEmpty, &events)
        followTurn(frame, t)

        let raw = computer.compute(frame, near: nearSide)
        rawHistory.append(Snapshot(t: t, values: raw))
        let values = smoother.smooth(raw, tMs: t)
        let visible = faults.map { visibleAll($0.landmarks) }

        trackReadyPose(t, values, visible: visibleAll(readyPose.landmarks), &events)

        let before = counter.state
        let repEvents = counter.push(t, values)
        let after = counter.state

        if before != .inRep, after == .inRep {
            attempt = Attempt(holdSince: Array(repeating: nil, count: faults.count))
        }
        if attempt != nil {
            attempt!.frames[t] = FrameRecord(values: values, visible: visible)
            if after == .inRep { evaluateDuringRep(t, values, visible, &events) }
        }

        for e in repEvents {
            switch e {
            case .repStarted:
                events.append(.repStarted)
                if attempt != nil {
                    attempt!.confirmed = true
                    let pending = attempt!.pending
                    attempt!.pending = []
                    announce(pending, t, &events)
                }
            case .attemptCompleted(let a):
                guard var current = attempt else { continue }
                var candidates: [Int] = []
                for (i, f) in faults.enumerated() {
                    if !f.enabled || current.detected.contains(i) || f.fault.position == .duringRep { continue }
                    let rec = current.frames[f.fault.position == .atTurn ? a.turn.t : a.start.t]
                    if let rec, rec.visible[i], f.fault.expr.evaluate(rec.values) == true {
                        current.detected.insert(i)
                        candidates.append(i)
                    }
                }
                attempt = current
                announce(candidates, t, &events)
                current = attempt!

                let detected = current.detected.sorted()
                let hasValidityFault = detected.contains { faults[$0].fault.fault.affectsValidity }
                let rep = loaded.pack.rep
                let outcome = classifyAttempt(reachedTarget: a.reachedTarget, durationMs: a.durationMs,
                                              hasValidityFault: hasValidityFault,
                                              minDurationMs: rep.minDurationMs, maxDurationMs: rep.maxDurationMs)
                events.append(.repCompleted(outcome: outcome, faults: detected.map { faults[$0].fault.fault.id },
                                            durationMs: Int(jsRound(a.durationMs))))
                checkSafety(detected, &events)
                streak = streak.indices.map { current.detected.contains($0) ? streak[$0] + 1 : 0 }
                attempt = nil
            }
        }

        // Left the rep without a confirmed attempt: it was noise.
        if before == .inRep, after != .inRep { attempt = nil }
        return events.map { TimedEvent(t: t, event: $0) }
    }

    private func evaluateDuringRep(_ t: Double, _ values: [String: Double], _ visible: [Bool], _ events: inout [EngineEvent]) {
        var newly: [Int] = []
        for (i, f) in faults.enumerated() {
            if !f.enabled || f.fault.position != .duringRep || attempt!.detected.contains(i) { continue }
            let truth = visible[i] ? f.fault.expr.evaluate(values) : nil
            if truth != true {
                attempt!.holdSince[i] = nil
                continue
            }
            let since = attempt!.holdSince[i] ?? t
            attempt!.holdSince[i] = since
            if t - since >= Double(f.fault.fault.holdMs ?? 0) {
                attempt!.detected.insert(i)
                newly.append(i)
            }
        }
        if newly.isEmpty { return }
        if attempt!.confirmed {
            announce(newly, t, &events)
        } else {
            attempt!.pending += newly
        }
    }

    /// Applies cue rules to simultaneous candidates and the during-rep safety check.
    private func announce(_ candidates: [Int], _ t: Double, _ events: inout [EngineEvent]) {
        if candidates.isEmpty { return }
        if cuesEnabled {
            let eligible = candidates.filter { i in
                let f = faults[i].fault.fault
                return streak[i] + 1 >= f.minConsecutiveReps && t - lastCueAt[i] >= Double(f.cooldownMs)
            }
            if let best = eligible.min(by: { priority($0) < priority($1) }) {
                lastCueAt[best] = t
                events.append(.faultDetected(faultId: faults[best].fault.fault.id))
            }
        }
        // during_rep detections can stop the set immediately; at_turn/at_start wait for REP_COMPLETED
        if counter.state == .inRep { checkSafety(candidates, &events) }
    }

    private func checkSafety(_ detected: [Int], _ events: inout [EngineEvent]) {
        guard options.safetyPause, let current = attempt, !current.safetyEmitted else { return }
        if let hit = detected.first(where: { faults[$0].fault.fault.severity == .major && streak[$0] >= 1 }) {
            attempt!.safetyEmitted = true
            events.append(.safetyPause(faultId: faults[hit].fault.fault.id))
        }
    }

    /// Lower is more important: major before minor, then rule pack order.
    private func priority(_ i: Int) -> Int {
        (faults[i].fault.fault.severity == .major ? 0 : 1) * 1000 + i
    }

    private func trackTracking(_ t: Double, visible: Bool, _ events: inout [EngineEvent]) {
        if !visible {
            let since = lowSince ?? t
            lowSince = since
            if !trackingLost, t - since >= options.trackingLostAfterMs {
                trackingLost = true
                events.append(.trackingLost)
            }
            return
        }
        lowSince = nil
        if trackingLost {
            trackingLost = false
            events.append(.trackingRestored)
        }
    }

    private func trackReadyPose(_ t: Double, _ values: [String: Double], visible: Bool, _ events: inout [EngineEvent]) {
        if !(visible && readyPose.expr.evaluate(values) == true) {
            readySince = nil
            readyFired = false
            return
        }
        let since = readySince ?? t
        readySince = since
        if !readyFired, t - since >= readyPose.durationMs {
            readyFired = true
            events.append(.readyPoseHeld)
        }
    }
}
