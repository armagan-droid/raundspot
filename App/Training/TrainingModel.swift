import AVFoundation
import Foundation
import Observation
import SoloCapture
import SoloEngine
import UIKit

/// One technique or conditioning set (specs/12 S2 → S1 → T1 → T2), without
/// the session engine (T3.4): a trial slice of Phase 3.
@Observable final class TrainingModel {
    enum Phase: Equatable { case safety, cameraDenied, cameraFailed, setup, ready, active, paused, finished }

    let loaded: LoadedRulePack
    private(set) var phase: Phase = .safety
    private(set) var count = 0
    private(set) var faultyCount = 0
    private(set) var band: String?
    private(set) var bandIsWarning = false
    private(set) var hints: [SetupHint] = []
    private(set) var frame: Frame?
    private(set) var aspect: Double = 16.0 / 9
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
    private var guideTracker: HeadGuideTracker?
    private(set) var targetLine: TargetLineGuide?
    private var lineTracker: TargetLineTracker?
    let demo: ExerciseDemo?
    /// The template's marks on each demo frame (specs/04).
    let demoGuides: [(head: HeadGuide?, line: TargetLineGuide?)]

    let camera = CameraSession(position: .front)
    private let speech = SpeechOut(language: Lang.code)
    private var pipeline: FramePipeline?
    private var engine: ExerciseEngine?
    private var track: PersonTrack?
    private var samples: [(t: Double, s: SetupSample)] = []
    private var readySince: Double?
    private var meter = FrameRateMeter()
    private var bandUntil: Double = 0

    init(_ loaded: LoadedRulePack) {
        self.loaded = loaded
        demo = ExerciseCatalog.demo(for: loaded.pack.id)
        demoGuides = demo?.guides(loaded) ?? []
    }

    var name: String { Lang.text(loaded.pack.name) }
    var howTo: String { loaded.pack.howTo.map(Lang.text) ?? "" }
    var setupHint: String { Lang.text(loaded.pack.camera.setupHint) }
    var isFrontCamera: Bool { camera.position == .front }

    // MARK: - Flow

    /// S2: a deliberate tap, before the camera (specs/12, rule 7).
    func confirmSpace() async {
        guard await CameraSession.requestAccess() else {
            phase = .cameraDenied
            return
        }
        let pipeline = FramePipeline { [weak self] candidates, t in
            Task { @MainActor in self?.receive(candidates, t) }
        }
        self.pipeline = pipeline
        do {
            try camera.configure { frame in pipeline.process(frame) }
        } catch {
            phase = .cameraFailed
            return
        }
        speech.activate()
        UIApplication.shared.isIdleTimerDisabled = true
        phase = .setup
        camera.start()
        speech.say(setupHint)
    }

    func startNow() {
        guard phase == .ready else { return }
        begin()
    }

    func resume() {
        guard phase == .paused else { return }
        engine?.reset()
        phase = .active
        showBand(String(localized: "training.resumed"), warning: false, now: HostClock.nowMs)
    }

    func finish() {
        guard phase != .finished else { return }
        camera.stop()
        speech.say(String(localized: "training.finished.spoken \(count)"))
        phase = .finished
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func close() {
        camera.stop()
        speech.deactivate()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func begin() {
        engine?.reset()
        count = 0
        faultyCount = 0
        phase = .active
        speech.say(String(localized: "training.go"))
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
        if t > bandUntil, band != nil, bandUntil > 0 { band = nil }

        switch phase {
        case .setup: assess(selection, t)
        case .ready, .active: run(selection.frame ?? emptyFrame(t), t)
        default: break
        }
        latencyMs = HostClock.nowMs - t
    }

    private func assess(_ selection: PersonSelection, _ t: Double) {
        samples.append((t, SetupSample(frame: selection.frame, ambiguous: selection.ambiguous)))
        samples.removeAll { $0.t < t - 1000 }
        let a = assessSetup(samples.map(\.s), pack: loaded.pack, context: SetupContext(verticalFOVDegrees: verticalFOV()))
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
            engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: a.view, nearSide: a.nearSide))
            guideTracker = HeadGuideTracker(loaded.pack, nearSide: a.nearSide)
            lineTracker = TargetLineTracker(loaded.pack, nearSide: a.nearSide)
            samples = []
            phase = .ready
            speech.say(String(localized: "training.ready.spoken"))
        }
    }

    private func run(_ f: Frame, _ t: Double) {
        guard let engine else { return }
        let events = engine.push(f)
        guide = guideTracker?.update(f, repMetric: engine.metrics[loaded.pack.rep.metric], inRep: engine.repState == .inRep,
                                     minVisibility: loaded.pack.camera.minVisibility)
        targetLine = lineTracker?.update(f, repMetric: engine.metrics[loaded.pack.rep.metric],
                                         minVisibility: loaded.pack.camera.minVisibility)
        metricRows = engine.metricOrder.map { ($0, engine.metrics[$0] ?? .nan) }
        for e in events { handle(e.event, t) }
    }

    private func handle(_ e: EngineEvent, _ t: Double) {
        switch e {
        case .readyPoseHeld:
            if phase == .ready { begin() }
        case .repCompleted(let outcome, let faults, _):
            guard phase == .active else { return }
            switch outcome {
            case .valid:
                count += 1
                speech.say("\(count)")
                showBand(String(localized: "training.rep.valid"), warning: false, now: t)
            case .faulty:
                faultyCount += 1
                let names = faults.compactMap { id in loaded.pack.faults.first { $0.id == id }.map { Lang.text($0.name) } }
                showBand(String(localized: "training.rep.faulty \(names.joined(separator: ", "))"), warning: true, now: t)
            case .incomplete:
                showBand(String(localized: "training.rep.incomplete"), warning: true, now: t)
            }
        case .faultDetected(let id):
            guard phase == .active, let fault = loaded.pack.faults.first(where: { $0.id == id }) else { return }
            let cue = Lang.text(fault.cue)
            speech.say(cue)
            showBand(cue, warning: true, now: t)
        case .safetyPause:
            guard phase == .active else { return }
            phase = .paused
            speech.say(String(localized: "training.safety.spoken"))
        case .trackingLost:
            if phase == .active { showBand(String(localized: "training.tracking.lost"), warning: true, now: t + 600_000) }
        case .trackingRestored:
            if phase == .active { band = nil }
        case .repStarted:
            break
        }
    }

    private func showBand(_ text: String, warning: Bool, now: Double) {
        band = text
        bandIsWarning = warning
        bandUntil = now + 2500
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
