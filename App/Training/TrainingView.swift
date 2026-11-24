import SoloEngine
import SwiftUI

/// A workout through the session engine (specs/12 S2 → S1 → S3 → T1 → T2 → T3 → Y1).
struct TrainingView: SwiftUI.View {
    @State private var model: TrainingModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var taps = 0

    init(_ model: TrainingModel) {
        _model = State(initialValue: model)
    }

    var body: some SwiftUI.View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.screen {
            case .cameraDenied: message("training.camera.denied", button: "training.camera.settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .cameraFailed: message("training.camera.failed", button: nil) {}
            case .finished: finished
            case .live: model.spaceConfirmed ? AnyView(live) : AnyView(safety)
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appWentToBackground() }
        }
    }

    // MARK: S2

    private var safety: some SwiftUI.View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.name).font(.largeTitle.bold())
                Label("training.safety.medical", systemImage: "cross.case").font(.headline)
                Label("training.safety.space", systemImage: "square.dashed").font(.body)
                if !model.setupHint.isEmpty { Text(model.setupHint).font(.callout).foregroundStyle(.secondary) }
                Button {
                    Task { await model.confirmSpace() }
                } label: {
                    Text("training.safety.confirm").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                Button("training.cancel") {
                    model.act(.abort)
                    dismiss()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
    }

    // MARK: Live screens

    private var live: some SwiftUI.View {
        GeometryReader { geo in
            ZStack {
                if model.workout.usesCamera {
                    if let camera = (model.source as? CameraFrameSource)?.camera {
                        CameraPreview(camera: camera).ignoresSafeArea()
                    } else {
                        Color.black.ignoresSafeArea()
                    }
                    if model.showSkeleton {
                        SkeletonOverlay(frame: model.frame, aspect: model.aspect, mirrored: model.isFrontCamera,
                                        minVisibility: model.minVisibility)
                            .ignoresSafeArea()
                    }
                    if [.ready, .countdown, .active, .confirm].contains(model.state) {
                        GuideOverlay(guide: model.guide, line: model.targetLine, aspect: model.aspect, mirrored: model.isFrontCamera)
                            .ignoresSafeArea()
                    }
                }
                if model.state == .paused, model.snapshot.pauseReason == .safety {
                    Rectangle().strokeBorder(.red, lineWidth: 12).ignoresSafeArea()
                }
                VStack {
                    panel
                    Spacer()
                    if let band = model.band {
                        Label(band, systemImage: model.bandIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(model.bandIsWarning ? Color.orange.opacity(0.85) : Color.green.opacity(0.8), in: .capsule)
                    }
                    controls
                }
                .padding()
                if [.active, .confirm].contains(model.state) || (model.state == .paused && model.snapshot.resumeTo == .active) {
                    if model.reflexCount == nil { counter(height: geo.size.height) } else { reflexCounter }
                }
                if model.state == .active, model.reflexCount != nil { reflexLive(height: geo.size.height) }
                if model.state == .countdown {
                    Text("\(model.secondsLeft)")
                        .font(.system(size: max(geo.size.height * 0.35, 80), weight: .bold, design: .rounded))
                        .shadow(radius: 8)
                        .accessibilityLabel(Text("training.countdown.accessibility \(model.secondsLeft)"))
                }
                if model.showDiagnostics { diagnostics }
            }
        }
    }

    private func card<C: SwiftUI.View>(@ViewBuilder _ content: () -> C) -> some SwiftUI.View {
        VStack(spacing: 8, content: content)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: 620)
            .background(.black.opacity(0.6), in: .rect(cornerRadius: 16))
            .onTapGesture { tapForDiagnostics() }
    }

    @ViewBuilder private var panel: some SwiftUI.View {
        switch model.state {
        case .setup:
            card {
                Text(model.hints.first.map { LocalizedStringKey($0.rawValue) } ?? "training.setup.hold").font(.title.bold())
                Text(model.setupHint).font(.callout)
            }
        case .warmup, .cooldown:
            card {
                Text(model.state == .warmup ? "training.warmup.title" : "training.cooldown.title").font(.headline)
                Text(model.stepText).font(.title.bold())
                if let demo = model.stepDemo {
                    DemoPanel(demo: demo, guides: [], mirrored: model.isFrontCamera)
                        .frame(maxWidth: 220, maxHeight: 220)
                        .padding(6)
                        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
                }
                Text("\(model.secondsLeft)").font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
            }
        case .ready:
            card {
                Text(model.blockName).font(.title.bold())
                Text("training.set \(model.setLabel)").font(.headline)
                if let h = model.hints.first { Text(LocalizedStringKey(h.rawValue)).font(.title2.bold()).foregroundStyle(.yellow) }
                if !model.howTo.isEmpty { Text(model.howTo).font(.callout) }
                if model.reflexCount != nil { reflexInfo }
                demoPanel
                Text("training.ready.prompt").font(.headline)
            }
        case .active where model.reflex?.phase == .preparing:
            // R1
            card {
                Text("reflex.get_ready").font(.title.bold())
                reflexInfo
            }
        case .rest:
            card {
                Text("training.rest.title").font(.headline)
                Text("\(model.secondsLeft)").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                if let summary = model.reflexSummary {
                    reflexSummary(summary)
                } else if let last = model.lastSet {
                    Text("training.summary \(last.valid) \(last.faulty)").font(.callout)
                }
                Text("training.next \(model.blockName) \(model.setLabel)").font(.callout)
            }
        case .confirm:
            card { Text("prompt.set_confirm").font(.title.bold()) }
        case .paused:
            card {
                Text(pauseTitle).font(.title.bold())
                if model.snapshot.pauseReason == .tracking { Text("training.paused.tracking").font(.callout) }
                if model.snapshot.pauseReason == .safety { Text("training.paused.safety").font(.callout) }
            }
        default:
            EmptyView()
        }
    }

    // MARK: R1–R3 (specs/12)

    @ViewBuilder private var reflexInfo: some SwiftUI.View {
        if let count = model.reflexCount {
            HStack(spacing: 12) {
                if let n = model.reflexLevelNumber { Text("reflex.level \(n)") }
                Text("reflex.cues \(count.total)")
            }
            .font(.headline)
        }
        if model.reflexRTApproximate { Text("reflex.rt_approximate").font(.caption) }
        if model.reflexIsDraft {
            Text("reflex.draft").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                .background(.yellow.opacity(0.3), in: .capsule)
        }
    }

    private var reflexCounter: some SwiftUI.View {
        VStack {
            HStack {
                Spacer()
                if let c = model.reflexCount {
                    Text("\(c.done)/\(c.total)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        .shadow(radius: 6).padding(.trailing, 24)
                        .accessibilityLabel(Text("reflex.count.accessibility \(c.done) \(c.total)"))
                }
            }
            Spacer()
        }
    }

    /// R2: the strike's name large at the cue (≥ 20 % of the height, 600 ms), then the result and RT for a second.
    @ViewBuilder private func reflexLive(height: CGFloat) -> some SwiftUI.View {
        if let s = model.shownStrike, model.now < s.until {
            Text(s.text)
                .font(.system(size: max(height * 0.22, 56), weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
                .shadow(radius: 10)
                .allowsHitTesting(false)
        } else if let t = model.lastTrial, model.now < t.until {
            VStack(spacing: 4) {
                Image(systemName: Self.icon(t.record.result)).font(.system(size: max(height * 0.14, 44)))
                    .foregroundStyle(t.record.result.isHit ? .green : .orange)
                if let rt = t.record.reactionMs { Text("reflex.rt \(Int(rt.rounded()))").font(.title.bold()).monospacedDigit() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(LocalizedStringKey("reflex.result.\(t.record.result.rawValue)")))
            .allowsHitTesting(false)
        }
    }

    static func icon(_ r: ReflexResult) -> String {
        switch r {
        case .correct, .correctFaulty, .feintOk: "checkmark.circle.fill"
        case .missed: "timer"
        case .early: "bolt.fill"
        case .wrong, .partial, .feintBitten: "xmark.circle.fill"
        }
    }

    /// R3: hits, median and p90 RT, per strike, preferred responses, feints, the most frequent fault, the level advice.
    @ViewBuilder private func reflexSummary(_ s: ReflexSetSummary) -> some SwiftUI.View {
        Text("reflex.summary.title").font(.headline)
        Text("reflex.summary.hits \(s.hits) \(s.total)").font(.title2.bold())
        if let m = s.medianRtMs { Text("reflex.summary.rt \(Int(m.rounded())) \(Int((s.p90RtMs ?? m).rounded()))").font(.callout) }
        ForEach(s.byStrike.keys.sorted(), id: \.self) { id in
            if let row = s.byStrike[id] {
                Text("reflex.summary.strike \(model.strikeName(id)) \(row.hits) \(row.total) \(Int((row.medianRtMs ?? 0).rounded()))")
                    .font(.caption)
            }
        }
        if let p = s.preferredRatio { Text("reflex.summary.preferred \(Int((p * 100).rounded()))").font(.caption) }
        if s.feints > 0 { Text("reflex.summary.feints \(s.feintsOk) \(s.feints)").font(.caption) }
        if let f = s.mostFrequentFault { Text("reflex.summary.fault \(model.faultName(f))").font(.caption) }
        switch model.reflexAdvice {
        case .tryHigher?: Text("reflex.advice.higher").font(.callout.bold()).foregroundStyle(.green)
        case .tryLower?: Text("reflex.advice.lower").font(.callout.bold()).foregroundStyle(.orange)
        case nil: EmptyView()
        }
    }

    private var pauseTitle: LocalizedStringKey {
        switch model.snapshot.pauseReason {
        case .safety?: "training.safety.paused"
        case .tracking?: "tracking.lost"
        case .restored?: "session.resume_offer"
        default: "session.paused"
        }
    }

    private func counter(height: CGFloat) -> some SwiftUI.View {
        VStack {
            HStack {
                Spacer()
                Text(model.target.map { "\(model.counted)/\($0)" } ?? "\(model.counted)")
                    .font(.system(size: max(height * 0.25, 60), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .shadow(radius: 6)
                    .padding(.trailing, 24)
                    .onTapGesture { tapForDiagnostics() }
                    .accessibilityLabel(Text("training.count.accessibility \(model.counted)"))
            }
            Spacer()
        }
    }

    @ViewBuilder private var demoPanel: some SwiftUI.View {
        if let id = model.block?.exerciseId, let (demo, guides) = model.demo(for: id) {
            DemoPanel(demo: demo, guides: guides, mirrored: model.isFrontCamera)
                .frame(maxWidth: demo.extra == nil ? 180 : 300, maxHeight: 180)
                .padding(6)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
        }
    }

    /// specs/02 "Tanı paneli": opened by 5 taps.
    private func tapForDiagnostics() {
        taps += 1
        if taps >= 5 {
            taps = 0
            model.showDiagnostics.toggle()
        }
    }

    private var controls: some SwiftUI.View {
        HStack(spacing: 12) {
            Button { model.soundOn.toggle() } label: {
                Image(systemName: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("training.sound"))
            if model.workout.usesCamera {
                Button { model.showSkeleton.toggle() } label: {
                    Image(systemName: "figure.stand").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("training.skeleton"))
            }
            switch model.state {
            case .warmup:
                Button("training.skip_warmup") { model.act(.skipWarmup) }.buttonStyle(.bordered)
            case .cooldown:
                Button("training.skip") { model.act(.skipBlock) }.buttonStyle(.bordered)
            case .ready:
                Button("training.start") { model.act(.start) }.buttonStyle(.borderedProminent)
                Button("training.skip") { model.act(.skipBlock) }.buttonStyle(.bordered)
                if model.snapshot.pendingSkip != nil { Button("training.undo_skip") { model.act(.undoSkip) }.buttonStyle(.bordered) }
            case .active:
                Button("training.end_set") { model.act(.endSet) }.buttonStyle(.bordered)
            case .confirm:
                Button("training.continue_set") { model.act(.continueSet) }.buttonStyle(.borderedProminent)
                Button("training.end_set") { model.act(.endSet) }.buttonStyle(.bordered)
            case .rest:
                Button("training.ready_now") { model.act(.ready) }.buttonStyle(.borderedProminent)
                Button("training.skip") { model.act(.skipBlock) }.buttonStyle(.bordered)
            case .paused:
                Button("training.resume") { model.act(.resume) }.buttonStyle(.borderedProminent)
            default:
                EmptyView()
            }
            if ![.paused, .setup].contains(model.state) {
                Button { model.act(.pause) } label: { Image(systemName: "pause.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(Text("training.pause"))
            }
            Button("training.finish") { model.act(.abort) }.buttonStyle(.bordered)
        }
        .font(.title3)
        .padding(10)
        .background(.black.opacity(0.5), in: .capsule)
    }

    private var diagnostics: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "FPS %.1f · drop %d · lat %.0f ms", model.fps, model.dropped, model.latencyMs))
            Text("state \(model.state.rawValue) · block \(model.snapshot.blockIndex) · set \(model.snapshot.setIndex)")
            Text("view \(model.setupView.rawValue) · aspect \(String(format: "%.2f", model.aspect)) · people \(model.candidateCount)")
            Text("hints \(model.hints.map { $0.rawValue.replacingOccurrences(of: "setup.hint.", with: "") }.joined(separator: ", "))")
            ForEach(model.metricRows, id: \.0) { row in
                Text(String(format: "%@ %.3f", row.0, row.1))
            }
        }
        .font(.caption.monospaced())
        .padding(8)
        .background(.black.opacity(0.7), in: .rect(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .allowsHitTesting(false)
    }

    // MARK: Y1 (minimal), E1

    private var finished: some SwiftUI.View {
        let sets = model.records.compactMap { r -> (Int, Int)? in
            if case .set(_, _, _, let v, let f, _, _, _, _) = r { (v, f) } else { nil }
        }
        let valid = sets.map(\.0).reduce(0, +), faulty = sets.map(\.1).reduce(0, +)
        return VStack(spacing: 20) {
            Text(model.name).font(.title2)
            Text(model.state == .aborted ? "training.finished.aborted" : "training.finished.done").font(.headline)
            Text("\(valid)").font(.system(size: 96, weight: .bold, design: .rounded))
            Text("training.summary \(valid) \(faulty)").font(.headline)
            Text("training.finished.sets \(sets.count)").font(.callout)
            Button("training.close") { dismiss() }.buttonStyle(.borderedProminent).frame(minHeight: 44)
        }
        .padding()
    }

    private func message(_ text: LocalizedStringKey, button: LocalizedStringKey?, action: @escaping () -> Void) -> some SwiftUI.View {
        VStack(spacing: 20) {
            Text(text).font(.title3).multilineTextAlignment(.center)
            if let button { Button(button, action: action).buttonStyle(.borderedProminent) }
            Button("training.close") { dismiss() }
        }
        .padding(32)
    }
}
