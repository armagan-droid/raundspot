import AVFoundation
import Foundation
import Observation
import SoloCapture
import SoloEngine
import SoloHealth
import UIKit

/// A workout run by the session engine (specs/06 Bölüm 1; specs/12 S2 → S1 →
/// S3 → T1 → T2 → T3 → Y1). A single template from the list runs as a
/// one-block workout. Records go to the store through `SessionRecorder` (specs/11).
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
    private(set) var now: Double
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
    private(set) var thermal: ProcessInfo.ThermalState = .nominal
    /// Degradation steps taken (specs/02 "Kademeli çalışma"); also in the session record.
    private(set) var degradations: [String] = []
    private(set) var guide: HeadGuide?
    private(set) var targetLine: TargetLineGuide?

    let source: FrameSource
    let clock: SoloClock
    private let speech = SpeechOut(language: Lang.code)
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
    @ObservationIgnored private var demoCache: [String: (ExerciseDemo, [(head: HeadGuide?, line: TargetLineGuide?)])] = [:]

    private let recorder: SessionRecorder?
    let settings: TrainingSettings

    // energy and Apple Health (specs/08)
    private let metTable = ExerciseCatalog.metTable()
    private var energy = EnergyTimeline()
    private var energyKind: String?
    /// The block being timed: its index, its first segment and when it started (host ms).
    private var energyBlock: (index: Int, firstSegment: Int, at: Double)?
    private let health: HealthWorkout?
    /// The session's net kcal estimate (Y1), nil without a weight.
    private(set) var sessionKcal: Double?
    private var activeSince: Double?
    private var activeMs = 0.0
    private var lastDurationMs: Double?

    // reflex (specs/05, specs/12 R1–R3)
    let reflexCatalog: ResolvedCatalog?
    /// The catalog is a draft (TestFlight label, AC-5.8).
    let reflexIsDraft: Bool
    private let reflexUsable: Bool
    private(set) var reflex: ReflexSet?
    private(set) var reflexLevel: ReflexCatalog.Level?
    /// R2: the strike name shown large until a host time.
    private(set) var shownStrike: (text: String, until: Double)?
    /// R2: the last trial's result, shown for a second.
    private(set) var lastTrial: (record: ReflexTrialRecord, until: Double)?
    /// R3: the last reflex set.
    private(set) var reflexSummary: ReflexSetSummary?
    private(set) var reflexAdvice: ReflexLevelAdvice?
    /// The reaction times of the current set are approximate (TTS fallback or Bluetooth; specs/05).
    private(set) var reflexRTApproximate = true
    /// Cue sounds of the language (T3.3); a cue without a file falls back to TTS.
    private let cueOut = CueOut(dir: Bundle.main.url(forResource: Lang.code, withExtension: nil, subdirectory: "audio"))
    private var reflexSets: [[ReflexTrialRecord]] = []
    private let tones = ToneOut()
    @ObservationIgnored private var cueTasks: [Task<Void, Never>] = []

    /// - Parameters:
    ///   - source: the camera by default; a sequence file for the fake camera (AC-2.2).
    ///   - clock: the host clock by default; frames, ticks and records all use it.
    ///   - reflexLevel: the level picked in H3 for blocks with `level: "chosen"`.
    init(workout: Workout, packs: [String: LoadedRulePack], recorder: SessionRecorder? = nil,
         source: FrameSource = CameraFrameSource(), clock: SoloClock = LiveClock.shared,
         reflexCatalog: ReflexCatalog? = ExerciseCatalog.reflexCatalog(), stance: Stance = .orthodox, reflexLevel: Int = 1,
         settings: TrainingSettings = TrainingSettings(), health: HealthStore? = nil) {
        self.settings = settings
        self.health = health.map { HealthWorkout(store: $0, sport: workout.sport) }
        let usable = reflexCatalog?.isUsable(release: ExerciseCatalog.isReleaseBuild) ?? false
        self.workout = Self.resolveReflexBlocks(workout, catalog: reflexCatalog, chosen: reflexLevel)
        var packs = packs
        // slow tempo: twice the eskiv's minimum duration in technique blocks (specs/05 "Yavaş tempo")
        if settings.slowTempo {
            for case .technique(let id, _, _, _, _) in workout.blocks {
                if var p = packs[id] { p.pack.rep.minDurationMs *= 2; packs[id] = p }
            }
        }
        // the reflex response templates (specs/05 "Tepki motorları")
        for id in reflexCatalog?.responses ?? [] where packs[id] == nil { packs[id] = ExerciseCatalog.pack(id) }
        self.packs = packs
        self.reflexCatalog = reflexCatalog?.resolved(for: stance)
        reflexIsDraft = reflexCatalog?.status == .draft
        reflexUsable = usable
        self.recorder = recorder
        self.source = source
        self.clock = clock
        let start = clock.nowMs
        now = start
        recorder?.sessionStartMs = start
        var versions: [String: Int] = [:]
        for (id, p) in packs { versions[id] = p.pack.version }
        session = SessionMachine(workout: Self.resolveReflexBlocks(workout, catalog: reflexCatalog, chosen: reflexLevel),
                                 exerciseVersions: versions, makeId: { UUID().uuidString })
        apply(session.handle(.user(.start)))
    }

    /// One template from the list: one set of 10 (specs/12 H2).
    convenience init(single loaded: LoadedRulePack, recorder: SessionRecorder? = nil,
                     source: FrameSource = CameraFrameSource(), clock: SoloClock = LiveClock.shared,
                     settings: TrainingSettings = TrainingSettings(), health: HealthStore? = nil) {
        let id = loaded.pack.id
        let block: Block = ExerciseCatalog.eskivIds.contains(id)
            ? .technique(exerciseId: id, sets: 1, reps: 10, restSec: 0, mode: .lenient)
            : .conditioning(exerciseId: id, sets: 1, reps: 10, durationSec: nil, restSec: 0, mode: .lenient)
        self.init(workout: Workout(id: "single_\(id)", name: loaded.pack.name, estimatedMinutes: 3, blocks: [block]),
                  packs: [id: loaded], recorder: recorder, source: source, clock: clock, settings: settings, health: health)
    }

    /// Reflex blocks with a fixed level and cue count before the session starts: the machine and the set
    /// count the same cues (specs/05: the block's `cues`, else the level's).
    static func resolveReflexBlocks(_ w: Workout, catalog: ReflexCatalog?, chosen: Int) -> Workout {
        var out = w
        out.blocks = w.blocks.map { b in
            guard case .reflex(let id, let level, let cues, let rest, let sets) = b else { return b }
            let n: Int = if case .fixed(let k) = level { k } else { chosen }
            let lv = catalog?.level(n) ?? catalog?.levels.first
            return .reflex(catalogId: id, level: .fixed(lv?.level ?? n), cues: cues ?? lv?.cues, restSec: rest, sets: sets)
        }
        return out
    }

    // MARK: - What the screen shows

    var state: SessionState { session.state }
    var snapshot: SessionSnapshot { session.s }
    var name: String { Lang.text(workout.name) }
    var isFrontCamera: Bool { source.isFrontCamera }
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

    /// The current warm-up or cool-down step's demo.
    var stepDemo: ExerciseDemo? {
        let steps = block?.steps ?? []
        guard session.s.stepIndex < steps.count else { return nil }
        let key = steps[session.s.stepIndex].textKey
        if let d = stepDemoCache[key] { return d }
        let d = ExerciseCatalog.stepDemo(for: key)
        stepDemoCache[key] = d
        return d
    }

    @ObservationIgnored private var stepDemoCache: [String: ExerciseDemo?] = [:]

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
            if source.needsCameraAccess {
                guard await CameraSession.requestAccess() else {
                    screen = .cameraDenied
                    return
                }
            }
            do {
                try source.start { [weak self] candidates, t in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { self?.receive(candidates, t) }
                    } else {
                        Task { @MainActor in self?.receive(candidates, t) }
                    }
                }
            } catch {
                screen = .cameraFailed
                return
            }
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
        cancelCues()
        tones.stop()
        cueOut.shutdown()
        source.stop()
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
                self.tick()
            }
        }
    }

    /// One clock step: the session machine's TICK (also driven by tests on a manual clock).
    func tick() {
        now = clock.nowMs
        send(.tick(now: now))
        if let r = reflex, session.state == .active { handleReflex(r.tick(now)) }
        if now > bandUntil, bandUntil > 0 { band = nil }
    }

    /// Time spent in sets (specs/11 `activeMs`).
    private var currentActiveMs: Double { activeMs + (activeSince.map { clock.nowMs - $0 } ?? 0) }

    private func afterTransition(from before: SessionSnapshot) {
        let s = session.s
        let inSet = { (st: SessionState) in st == .active || st == .confirm }
        if inSet(s.state), !inSet(before.state) {
            activeSince = clock.nowMs
            if let setId = s.setId { recorder?.setStarted(setId, at: Date()) }
        } else if !inSet(s.state), inSet(before.state), let since = activeSince {
            activeMs += clock.nowMs - since
            activeSince = nil
        }
        // a new set starts with a fresh rep counter in the template engine
        if s.state == .countdown, before.state != .countdown, !s.countdownResumes {
            engine = nil  // rebuilt on the next frame with the near side the person shows now
        }
        if before.state != s.state || before.blockIndex != s.blockIndex {
            band = nil
            bandUntil = 0
        }
        reflexTransition(from: before)
        energyTransition(from: before)
        if s.state.isTerminal, screen == .live {
            screen = .finished
            ticker?.cancel()
            source.stop()
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
                do {
                    try recorder?.write(r, now: Date(), view: setupView.rawValue, activeMs: Int(currentActiveMs))
                } catch {
                    assertionFailure("store write failed: \(error)")
                }
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
        bandUntil = sticky ? .infinity : clock.nowMs + 2500
    }

    // MARK: - Frames

    private func receive(_ candidates: [Frame], _ t: Double) {
        meter.record(t)
        fps = meter.fps
        dropped = source.dropped
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
        if session.state == .ready, let pack = currentPack {
            // a block with another view (squat after jumping jack): say how to stand
            let a = assessSetup(samples.map(\.s), pack: pack.pack, context: context)
            if hints.first != a.hints.first, let h = a.hints.first { speech.say(String(localized: String.LocalizationValue(h.rawValue))) }
            hints = a.hints
        }
        if case .reflex? = block, session.state == .active, let r = reflex {
            handleReflex(r.push(selection.frame ?? emptyFrame(t)))
        } else if let pack = currentPack, [.ready, .countdown, .active, .confirm, .rest, .paused].contains(session.state) {
            run(selection.frame ?? emptyFrame(t), pack)
        } else {
            guide = nil
            targetLine = nil
        }
        latencyMs = clock.nowMs - t
    }

    private var context: SetupContext { SetupContext(verticalFOVDegrees: verticalFOV()) }

    /// S1 checks the first camera block (specs/06 SETUP): a reflex block by the
    /// eskiv templates its level accepts (here the ones in the bundle, 05),
    /// otherwise its own template. Later blocks show their view hint in READY.
    private var setupPacks: [RulePack] {
        guard let first = workout.blocks.first(where: \.usesCamera) else { return [] }
        if case .reflex = first {
            return ["slip_left", "slip_right", "duck"].compactMap { packs[$0]?.pack ?? ExerciseCatalog.pack($0)?.pack }
        }
        return first.exerciseId.flatMap { packs[$0]?.pack }.map { [$0] } ?? []
    }

    private func assessForSetup(_ t: Double) {
        let camPacks = setupPacks
        guard !camPacks.isEmpty else {
            send(.setupReady)  // nothing to check against
            return
        }
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
            // the template's view when it has one; the person may still be turning
            let views = loaded.pack.camera.views
            let view: View = views.count == 1 ? View(views[0]) : (a.view == .ambiguous ? View(views[0]) : a.view)
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
            if case .repCompleted(let outcome, let faults, let d) = e.event, wasActive {
                lastDurationMs = Double(d)
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
            // too fast for the slow tempo (specs/05)
            if settings.slowTempo, case .technique? = block, let d = lastDurationMs, d < Double(loaded.pack.rep.minDurationMs) {
                speech.say(String(localized: "technique.slow_down"))
            }
        }
    }

    // MARK: - Reflex (specs/05, T4.4)

    private func reflexTransition(from before: SessionSnapshot) {
        let s = session.s
        let wasReflex = workout.blocks[safe: before.blockIndex].map { if case .reflex = $0 { true } else { false } } ?? false
        guard case .reflex(_, let level, let cues, _, _)? = block else {
            if wasReflex { endReflexSet(before, s) }
            return
        }
        if s.state == .ready, !reflexUsable || reflexCatalog == nil {
            // AC-5.8: the App Store build runs an approved catalog only
            showBand(String(localized: "reflex.unavailable"), warning: false)
            speech.say(String(localized: "reflex.unavailable"))
            send(.user(.skipBlock))
            return
        }
        // a new set: a new reflex set; a resumed one keeps it
        if s.state == .active, before.state != .active, reflex == nil, let cat = reflexCatalog,
           case .fixed(let n) = level, let lv = cat.levels.first(where: { $0.level == n }) {
            var options = ReflexSet.Options()
            // when each cue is heard, read at the set's start (specs/05 "İşaret anı"); TTS: unknown, approximate
            var delays: [String: (ms: Double, approximate: Bool)] = [:]
            for k in cat.strikes.map(\.say) + cat.feints.map(\.say) { delays[k] = cueOut.cueDelay(k) }
            let fixed = delays
            options.cueDelay = { key in fixed[key] ?? (0, true) }
            reflexRTApproximate = fixed.values.contains { $0.approximate }
            options.resultTones = settings.resultTones
            options.faultCueVoice = settings.faultCueVoice
            options.speechMs = { key in Double(String(localized: String.LocalizationValue(key)).count) * 70 + 400 }
            reflexLevel = lv
            reflexSummary = nil
            reflex = ReflexSet(catalog: cat, level: lv, packs: packs, cues: cues, seed: UInt64.random(in: 0...UInt64.max), now: now,
                               options: options)
        }
        if s.state == .paused, before.state == .active, let r = reflex { handleReflex(r.pause()) }
        if wasReflex { endReflexSet(before, s) }
    }

    /// The set ended (rest, next block, cool-down, end): R3 shows its summary.
    private func endReflexSet(_ before: SessionSnapshot, _ s: SessionSnapshot) {
        guard before.state == .active, s.state != .active, s.state != .paused, let r = reflex else { return }
        reflexSets.append(r.trials)
        reflexSummary = ReflexSetSummary(r.trials)
        reflexAdvice = reflexSets.count >= 2
            ? ReflexLevelAdvice.advise(lastTwoSets: Array(reflexSets.suffix(2)), windowMs: r.level.windowMs) : nil
        reflex = nil
    }

    private func handleReflex(_ commands: [ReflexCommand]) {
        for c in commands {
            switch c {
            case .playCue(let key, let at):
                let text = text(key)
                let scheduled = cueOut.schedule(key, atMs: at)  // the sound file on the host clock (T3.3)
                let delay = max(0, at - clock.nowMs)
                cueTasks.append(Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(Int(delay)))
                    guard let self, !Task.isCancelled else { return }
                    if !scheduled { self.speech.say(text) }  // TTS fallback
                    self.shownStrike = (text, self.clock.nowMs + 600)
                })
            case .cancelCues:
                cancelCues()
                cueOut.stopAll()
            case .speak(let key):
                speech.say(text(key))
            case .tone(let t):
                tones.play(t == .correct ? .correct : t == .wrong ? .wrong : .doubleWrong)
            case .trial(let r):
                lastTrial = (r, now + 1000)
                if let setId = session.s.setId { recorder?.writeReflexTrial(r, setId: setId, at: Date()) }
                if r.result == .correctFaulty, let ex = r.responseExerciseId, let p = packs[ex] {
                    let names = r.faults.compactMap { id in p.pack.faults.first { $0.id == id }.map { Lang.text($0.name) } }
                    showBand(String(localized: "training.rep.faulty \(names.joined(separator: ", "))"), warning: true)
                }
                send(.reflexAttemptDone)
            case .safetyPause(let fault):
                send(.engine(.safetyPause(faultId: fault)))
            case .tracking(let lost):
                send(.engine(lost ? .trackingLost : .trackingRestored))
            case .speakSetSummary(let cues, let hits, let mean, let hardest):
                var line = String(localized: "reflex.set_summary \(cues) \(hits) \(mean ?? 0)")
                if let hardest { line += " " + String(localized: "reflex.set_summary.hardest \(text(hardest))") }
                speech.say(line)
            case .setDone:
                break
            }
        }
    }

    private func cancelCues() {
        for t in cueTasks { t.cancel() }
        cueTasks = []
    }

    var reflexLevelNumber: Int? {
        if case .reflex(_, .fixed(let n), _, _, _)? = block { n } else { nil }
    }

    /// A strike's spoken name in the stance's words (summary rows).
    func strikeName(_ id: String) -> String {
        guard let say = reflexCatalog?.strikes.first(where: { $0.id == id })?.say else { return id }
        return text(say.replacingOccurrences(of: "strike.", with: "strike.name."))
    }

    /// A fault id's name from any response template.
    func faultName(_ id: String) -> String {
        for p in packs.values { if let f = p.pack.faults.first(where: { $0.id == id }) { return Lang.text(f.name) } }
        return id
    }

    /// R2 counter: cues done / cues of the set.
    var reflexCount: (done: Int, total: Int)? {
        guard case .reflex(_, _, let c, _, _)? = block else { return nil }
        return (session.s.attempts, c ?? SessionMachine.defaultReflexCues)
    }

    // MARK: - Energy and Apple Health (specs/08)

    /// The timeline kind of a session state: warm-up, cool-down, the block's kind in a set, rest between.
    private func energyKind(_ s: SessionSnapshot) -> String? {
        switch s.state {
        case .warmup: "warmup"
        case .cooldown: "cooldown"
        case .active, .confirm: workout.blocks[safe: s.blockIndex].map { $0.kind == "guided" ? "cooldown" : $0.kind }
        case .ready, .countdown, .rest: "rest"
        default: nil
        }
    }

    private func date(_ ms: Double) -> Date { Date().addingTimeInterval((ms - clock.nowMs) / 1000) }

    private func energyTransition(from before: SessionSnapshot) {
        let s = session.s
        let t = clock.nowMs
        // the workout starts with the first block (setup time is not part of it)
        if before.state == .setup || before.state == .idle, s.state != .setup, s.state != .idle, !s.state.isTerminal {
            health?.begin(at: date(t))
        }
        if s.state == .paused, before.state != .paused {
            energy.pause(at: t)
            health?.pause(at: date(t))
        } else if before.state == .paused, s.state != .paused, !s.state.isTerminal {
            energy.resume(at: t)
            health?.resume(at: date(t))
        }
        // a block ended: its kcal and its activity
        if let b = energyBlock, b.index != s.blockIndex || s.state.isTerminal {
            closeEnergyBlock(b, at: t)
            energyBlock = nil
        }
        if energyBlock == nil, !s.state.isTerminal, energyKind(s) != nil {
            energyBlock = (s.blockIndex, energy.segments.count, t)
        }
        let kind = s.state == .paused ? energyKind : energyKind(s)
        if s.state != .paused, kind != energyKind {
            if let kind { energy.enter(kind, at: t) } else { energy.finish(at: t) }
            energyKind = kind
        }
        if s.state.isTerminal {
            energy.finish(at: t)
            if let table = metTable { sessionKcal = (try? Energy.netKcal(energy.segments, weightKg: settings.weightKg, table: table)) ?? nil }
            health?.finish(at: date(t), aborted: s.state == .aborted, activeMs: Int(currentActiveMs))
        }
    }

    private func closeEnergyBlock(_ b: (index: Int, firstSegment: Int, at: Double), at t: Double) {
        var line = energy
        line.finish(at: t)  // a copy: the segments up to now
        let segs = Array(line.segments.dropFirst(b.firstSegment))
        let kcal = metTable.flatMap { (try? Energy.netKcal(segs, weightKg: settings.weightKg, table: $0)) ?? nil }
        let kind = workout.blocks[safe: b.index]?.kind ?? "technique"
        health?.block(kind, start: date(b.at), end: date(t), kcal: kcal)
    }

    // MARK: - Degraded operation (specs/02, AC-2.6; specs/12 E4)

    /// `serious`: 24 fps, nothing shown to the user, the workout goes on. `critical`: also a short break (E4).
    func thermalChanged(_ state: ProcessInfo.ThermalState) {
        thermal = state
        guard state == .serious || state == .critical else { return }
        if !degradations.contains("fps24") {
            degradations.append("fps24")
            source.limitFrameRate(24)
            recorder?.noteDegradation("fps24")
        }
        if state == .critical, !session.state.isTerminal, session.state != .paused, session.state != .idle {
            send(.user(.pause))
            // after the pause's own prompt, so the reason stays on screen
            showBand(String(localized: "thermal.critical"), warning: true, sticky: true)
            speech.say(String(localized: "thermal.critical"))
        }
    }

    // MARK: - Interruptions (specs/06 INTERRUPTED, E2)

    private func observeInterruptions() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            MainActor.assumeIsolated { self?.thermalChanged(state) }
        })
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            thermalChanged(ProcessInfo.processInfo.thermalState)
        }
        if let session = source.captureSession {
            observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.send(.interrupted(.camera)) }
            })
        }
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
        guard let h = source.horizontalFOVDegrees else { return nil }
        if aspect < 1 { return h }
        let half = tan(h * .pi / 360) / aspect
        return 2 * atan(half) * 180 / .pi
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Profile settings a workout uses (specs/11 Profile, specs/12 A).
struct TrainingSettings {
    var slowTempo = true
    var resultTones = true
    var faultCueVoice = true
    var backCamera = false
    /// For the calorie estimate (specs/08 "Kilo"): the profile's; HealthKit's comes with T6.2's reading.
    var weightKg: Double?

    init(slowTempo: Bool = true, resultTones: Bool = true, faultCueVoice: Bool = true, backCamera: Bool = false, weightKg: Double? = nil) {
        self.slowTempo = slowTempo
        self.resultTones = resultTones
        self.faultCueVoice = faultCueVoice
        self.backCamera = backCamera
        self.weightKg = weightKg
    }

    init(_ p: Profile?) {
        self.init(slowTempo: (p?.techniqueTempo ?? "slow") == "slow", resultTones: p?.resultTones ?? true,
                  faultCueVoice: p?.faultCueVoice ?? true, backCamera: p?.camera == "back", weightKg: p?.weightKg)
    }
}
