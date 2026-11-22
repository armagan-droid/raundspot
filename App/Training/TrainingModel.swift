import AVFoundation
import Foundation
import Observation
import SoloCapture
import SoloEngine
import UIKit

/// A workout run by the session engine (specs/06 Bölüm 1; specs/12 S2 → S1 →
/// S3 → T1 → T2 → T3 → Y1). A single template from the list runs as a
/// one-block workout. Records stay in memory until the SwiftData model (T3.4).
@Observable final class TrainingModel {
    enum Screen: Equatable { case live, cameraDenied, cameraFailed, finished }

    let workout: Workout
    let packs: [String: LoadedRulePack]
    private(set) var screen: Screen = .live
    private(set) var session: SessionMachine
    private(set) var band: String?
    private(set) var bandIsWarning = false
    private(set) var hints: [SetupHint] = []
    private(set) var frame: Frame?
    private(set) var aspect: Double = 16.0 / 9
    private(set) var records: [SessionRecord] = []
    private(set) var lastSet: (valid: Int, faulty: Int)?
    private(set) var now: Double = HostClock.nowMs
    var showSkeleton = true
    var showDiagnostics = false
    var soundOn = true { didSet { speech.enabled = soundOn } }

    // diagnostics (specs/02 "Tanı paneli")
    private(set) var fps = 0.0
    private(set) var dropped = 0
    private(set) var latencyMs = 0.0
    private(set) var metricRows: [(String, Double)] = []
    private(set) var setupView: View = .ambiguous
    private(set) var candidateCount = 0
    private(set) var guide: HeadGuide?
    private(set) var targetLine: TargetLineGuide?

    let camera = CameraSession(position: .front)
    private let speech = SpeechOut(language: Lang.code)
    private var pipeline: FramePipeline?
    private var engine: ExerciseEngine?
    private var engineBlock: Int?
    private var guideTracker: HeadGuideTracker?
    private var lineTracker: TargetLineTracker?
    private var track: PersonTrack?
    private var samples: [(t: Double, s: SetupSample)] = []
    private var readySince: Double?
    private var meter = FrameRateMeter()
    private var bandUntil: Double = 0
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var demoCache: [String: (ExerciseDemo, [(head: HeadGuide?, line: TargetLineGuide?)])] = [:]

    init(workout: Workout, packs: [String: LoadedRulePack]) {
        self.workout = workout
        self.packs = packs
        var versions: [String: Int] = [:]
        for (id, p) in packs { versions[id] = p.pack.version }
        session = SessionMachine(workout: workout, exerciseVersions: versions, makeId: { UUID().uuidString })
        apply(session.handle(.user(.start)))
    }

    /// One template from the list: one set of 10 (specs/12 H2).
    convenience init(single loaded: LoadedRulePack) {
        let id = loaded.pack.id
        let block: Block = ExerciseCatalog.eskivIds.contains(id)
            ? .technique(exerciseId: id, sets: 1, reps: 10, restSec: 0, mode: .lenient)
            : .conditioning(exerciseId: id, sets: 1, reps: 10, durationSec: nil, restSec: 0, mode: .lenient)
        self.init(workout: Workout(id: "single_\(id)", name: loaded.pack.name, estimatedMinutes: 3, blocks: [block]),
                  packs: [id: loaded])
    }

    // MARK: - What the screen shows

    var state: SessionState { session.state }
    var snapshot: SessionSnapshot { session.s }
    var name: String { Lang.text(workout.name) }
    var isFrontCamera: Bool { camera.position == .front }
    var spaceConfirmed: Bool { session.s.spaceConfirmed }
    var block: Block? { session.block }
    var currentPack: LoadedRulePack? { block?.exerciseId.flatMap { packs[$0] } }
    var blockName: String { currentPack.map { Lang.text($0.pack.name) } ?? name }
    var howTo: String { currentPack?.pack.howTo.map(Lang.text) ?? "" }
    var setupHint: String {
        currentPack.map { Lang.text($0.pack.camera.setupHint) }
            ?? workout.blocks.compactMap { $0.exerciseId.flatMap { packs[$0] } }.first.map { Lang.text($0.pack.camera.setupHint) } ?? ""
    }
    var minVisibility: Double { currentPack?.pack.camera.minVisibility ?? 0.5 }
    var counted: Int { session.s.counted }
    var target: Int? {
        switch block {
        case .technique(_, _, let r, _, _)?: r
        case .conditioning(_, _, let r, _, _, _)?: r
        default: nil
        }
    }
    var setLabel: String { "\(min(session.s.setIndex + 1, block?.sets ?? 1))/\(block?.sets ?? 1)" }

    /// Seconds left in the warm-up step, the rest or the countdown.
    var secondsLeft: Int {
        let s = session.s
        let elapsed = now - s.phaseStartedAt
        switch s.state {
        case .rest: return max(0, Int(((s.restRemainingMs - elapsed) / 1000).rounded(.up)))
        case .countdown: return max(1, Int(((SessionTiming.countdownMs - elapsed) / 1000).rounded(.up)))
        case .warmup, .cooldown:
            let steps = block?.steps ?? []
            guard s.stepIndex < steps.count else { return 0 }
            return max(0, Int((Double(steps[s.stepIndex].durationSec) - elapsed / 1000).rounded(.up)))
        default: return 0
        }
    }

    var stepText: String {
        let steps = block?.steps ?? []
        guard session.s.stepIndex < steps.count else { return "" }
        return String(localized: String.LocalizationValue(steps[session.s.stepIndex].textKey))
    }

    func demo(for id: String) -> (ExerciseDemo, [(head: HeadGuide?, line: TargetLineGuide?)])? {
        if let d = demoCache[id] { return d }
        guard let d = ExerciseCatalog.demo(for: id), let p = packs[id] else { return nil }
        let entry = (d, d.guides(p))
        demoCache[id] = entry
        return entry
    }

    // MARK: - User actions

    /// S2: a deliberate tap, before the camera (specs/12, rule 7).
    func confirmSpace() async {
        if workout.usesCamera {
            guard await CameraSession.requestAccess() else {
                screen = .cameraDenied
                return
            }
            let pipeline = FramePipeline { [weak self] candidates, t in
                Task { @MainActor in self?.receive(candidates, t) }
            }
            self.pipeline = pipeline
            do {
                try camera.configure { frame in pipeline.process(frame) }
            } catch {
                screen = .cameraFailed
                return
            }
            camera.start()
            observeInterruptions()
        }
        speech.activate()
        UIApplication.shared.isIdleTimerDisabled = true
        startTicker()
        send(.user(.confirmSpace))
        if workout.usesCamera { speech.say(setupHint) }
    }

    func act(_ a: UserAction) { send(.user(a)) }

    func appWentToBackground() { send(.interrupted(.background)) }

    func close() {
        ticker?.cancel()
        camera.stop()
        speech.deactivate()
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Session

    private func send(_ input: SessionInput) {
        let before = session.s
        apply(session.handle(input))
        afterTransition(from: before)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                self.now = HostClock.nowMs
                self.send(.tick(now: self.now))
                if self.now > self.bandUntil, self.bandUntil > 0 { self.band = nil }
            }
        }
    }

    private func afterTransition(from before: SessionSnapshot) {
        let s = session.s
        // a new set starts with a fresh rep counter in the template engine
        if s.state == .countdown, before.state != .countdown, !s.countdownResumes { engine?.reset() }
        if before.state != s.state || before.blockIndex != s.blockIndex {
            band = nil
            bandUntil = 0
        }
        // reflex sets need the attempt loop (05, Phase 4): skipped in this build
        if s.state == .ready, case .reflex? = block {
            showBand(String(localized: "training.reflex.later"), warning: false)
            speech.say(String(localized: "training.reflex.later"))
            send(.user(.skipBlock))
        }
        if s.state.isTerminal, screen == .live {
            screen = .finished
            ticker?.cancel()
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func apply(_ commands: [SessionCommand]) {
        for c in commands {
            switch c {
            case .speak(let key): speech.say(text(key))
            case .show(let key):
                let warning = key.hasPrefix("cue.") || key.hasPrefix("safety.") || key == "tracking.lost"
                showBand(text(key), warning: warning, sticky: key == "tracking.lost" || key == "prompt.set_confirm")
            case .persist(let r):
                records.append(r)
                if case .set(_, _, _, let v, let f, _, _, _, _) = r { lastSet = (v, f) }
            }
        }
    }

    /// Catalog text; fault cues come from the template (specs/06).
    private func text(_ key: String) -> String {
        if key.hasPrefix("cue.") {
            let parts = key.split(separator: ".")
            if parts.count == 3, let pack = packs[String(parts[1])], let f = pack.pack.faults.first(where: { $0.id == parts[2] }) {
                return Lang.text(f.cue)
            }
        }
        return String(localized: String.LocalizationValue(key))
    }

    private func showBand(_ text: String, warning: Bool, sticky: Bool = false) {
        band = text
        bandIsWarning = warning
        bandUntil = sticky ? .infinity : HostClock.nowMs + 2500
    }

    // MARK: - Frames

    private func receive(_ candidates: [Frame], _ t: Double) {
        meter.record(t)
        fps = meter.fps
        dropped = camera.dropped
        candidateCount = candidates.count
        let selection = selectPerson(candidates, track: track)
        track = selection.track
        frame = selection.frame
        if let f = selection.frame { aspect = f.imageAspect } else if let c = candidates.first { aspect = c.imageAspect }
        samples.append((t, SetupSample(frame: selection.frame, ambiguous: selection.ambiguous)))
        samples.removeAll { $0.t < t - 1000 }

        let s = session.s
        if s.state == .setup, s.spaceConfirmed {
            assessForSetup(t)
        } else if s.state == .paused, s.pauseReason == .tracking, let pack = currentPack {
            // back in view: S1 checks met again (specs/06 SETUP_READY)
            if assessSetup(samples.map(\.s), pack: pack.pack, context: context).ready { send(.setupReady) }
        }
        if let pack = currentPack, [.ready, .countdown, .active, .confirm, .rest, .paused].contains(session.state) {
            run(selection.frame ?? emptyFrame(t), pack)
        } else {
            guide = nil
            targetLine = nil
        }
        latencyMs = HostClock.nowMs - t
    }

    private var context: SetupContext { SetupContext(verticalFOVDegrees: verticalFOV()) }

    private func assessForSetup(_ t: Double) {
        let camPacks = workout.blocks.compactMap { $0.exerciseId.flatMap { packs[$0]?.pack } }
        guard !camPacks.isEmpty else { return }
        let a = assessSetup(samples.map(\.s), packs: camPacks, context: context)
        setupView = a.view
        if hints.first != a.hints.first, let h = a.hints.first { speech.say(String(localized: String.LocalizationValue(h.rawValue))) }
        hints = a.hints
        guard a.ready else {
            readySince = nil
            return
        }
        if readySince == nil { readySince = t }
        // ready for 1.5 s without a break → next step (ref 08 "Otomatik başlama")
        if let since = readySince, t - since >= 1500 {
            readySince = nil
            send(.setupReady)
        }
    }

    /// One engine per block, set up from the last second of samples.
    private func run(_ f: Frame, _ loaded: LoadedRulePack) {
        if engineBlock != session.s.blockIndex || engine == nil {
            let a = assessSetup(samples.map(\.s), pack: loaded.pack, context: context)
            let view: View = a.view == .ambiguous ? View(loaded.pack.camera.views[0]) : a.view
            engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: view, nearSide: a.nearSide))
            guideTracker = HeadGuideTracker(loaded.pack, nearSide: a.nearSide)
            lineTracker = TargetLineTracker(loaded.pack, nearSide: a.nearSide)
            engineBlock = session.s.blockIndex
        }
        guard let engine else { return }
        let events = engine.push(f)
        let m = engine.metrics[loaded.pack.rep.metric]
        guide = guideTracker?.update(f, repMetric: m, inRep: engine.repState == .inRep, minVisibility: loaded.pack.camera.minVisibility)
        targetLine = lineTracker?.update(f, repMetric: m, minVisibility: loaded.pack.camera.minVisibility)
        metricRows = engine.metricOrder.map { ($0, engine.metrics[$0] ?? .nan) }
        for e in events {
            let wasActive = session.state == .active || session.state == .confirm
            let countedBefore = session.s.counted
            send(.engine(e.event))
            if case .repCompleted(let outcome, let faults, _) = e.event, wasActive {
                repFeedback(outcome, faults, counted: session.s.counted > countedBefore, loaded)
            }
        }
    }

    private func repFeedback(_ outcome: RepOutcome, _ faults: [String], counted: Bool, _ loaded: LoadedRulePack) {
        let setGoesOn = session.state == .active
        switch outcome {
        case .valid:
            if setGoesOn { speech.say("\(session.s.counted)") }
            showBand(String(localized: "training.rep.valid"), warning: false)
        case .faulty:
            if counted, setGoesOn { speech.say("\(session.s.counted)") }
            let names = faults.compactMap { id in loaded.pack.faults.first { $0.id == id }.map { Lang.text($0.name) } }
            showBand(String(localized: "training.rep.faulty \(names.joined(separator: ", "))"), warning: true)
        case .incomplete:
            showBand(String(localized: "training.rep.incomplete"), warning: true)
        }
    }

    // MARK: - Interruptions (specs/06 INTERRUPTED, E2)

    private func observeInterruptions() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: camera.session, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.send(.interrupted(.camera)) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let began = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated { self?.send(began ? .audioInterrupted : .audioResumed) }
        })
    }

    private func emptyFrame(_ t: Double) -> Frame {
        let none = Array(repeating: Landmark(x: 0, y: 0, z: 0, visibility: 0), count: LandmarkName.count)
        return Frame(t: t, image: none, world: Array(repeating: .missing, count: LandmarkName.count), imageAspect: aspect)
    }

    /// The upright vertical field of view: the format's FOV is along the long side.
    private func verticalFOV() -> Double? {
        guard let h = camera.horizontalFOVDegrees else { return nil }
        if aspect < 1 { return h }
        let half = tan(h * .pi / 360) / aspect
        return 2 * atan(half) * 180 / .pi
    }
}
