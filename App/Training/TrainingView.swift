import SoloEngine
import SwiftUI

/// S2 → S1 → T1 → T2 for one template (specs/12).
struct TrainingView: SwiftUI.View {
    @State private var model: TrainingModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var taps = 0

    init(_ loaded: LoadedRulePack) {
        _model = State(initialValue: TrainingModel(loaded))
    }

    var body: some SwiftUI.View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .safety: safety
            case .cameraDenied: message("training.camera.denied", button: "training.camera.settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .cameraFailed: message("training.camera.failed", button: nil) {}
            case .finished: finished
            default: live
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { model.close() }
    }

    // MARK: S2

    private var safety: some SwiftUI.View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.name).font(.largeTitle.bold())
                Label("training.safety.medical", systemImage: "cross.case").font(.headline)
                Label("training.safety.space", systemImage: "square.dashed").font(.body)
                Text(model.setupHint).font(.callout).foregroundStyle(.secondary)
                Button {
                    Task { await model.confirmSpace() }
                } label: {
                    Text("training.safety.confirm").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                Button("training.cancel") { dismiss() }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: 560)
        }
    }

    // MARK: S1, T1, T2

    private var live: some SwiftUI.View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(camera: model.camera).ignoresSafeArea()
                if model.showSkeleton {
                    SkeletonOverlay(frame: model.frame, aspect: model.aspect, mirrored: model.isFrontCamera,
                                    minVisibility: model.loaded.pack.camera.minVisibility)
                        .ignoresSafeArea()
                }
                if model.phase == .ready || model.phase == .active {
                    GuideOverlay(guide: model.guide, line: model.targetLine, aspect: model.aspect, mirrored: model.isFrontCamera)
                        .ignoresSafeArea()
                }
                if model.phase == .paused {
                    Rectangle().strokeBorder(.red, lineWidth: 12).ignoresSafeArea()
                }
                VStack {
                    topText
                    Spacer()
                    if let band = model.band, model.phase == .active || model.phase == .paused {
                        Label(band, systemImage: model.bandIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.title2.bold())
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(model.bandIsWarning ? Color.orange.opacity(0.85) : Color.green.opacity(0.8), in: .capsule)
                    }
                    controls
                }
                .padding()
                if model.phase == .active || model.phase == .paused {
                    counter(height: geo.size.height)
                }
                if model.showDiagnostics { diagnostics }
            }
        }
    }

    @ViewBuilder private var topText: some SwiftUI.View {
        switch model.phase {
        case .setup:
            VStack(spacing: 8) {
                Text(model.hints.first.map { LocalizedStringKey($0.rawValue) } ?? "training.setup.hold")
                    .font(.title.bold())
                Text(model.setupHint).font(.callout)
                if !model.howTo.isEmpty {
                    Label(model.howTo, systemImage: "info.circle").font(.callout).padding(.top, 4)
                }
                demoPanel
            }
            .multilineTextAlignment(.center)
            .padding().background(.black.opacity(0.55), in: .rect(cornerRadius: 16))
            .onTapGesture { tapForDiagnostics() }
        case .ready:
            VStack(spacing: 8) {
                Text(model.name).font(.title.bold())
                Text(model.howTo).font(.callout)
                demoPanel
                Text("training.ready.prompt").font(.headline)
            }
            .multilineTextAlignment(.center)
            .padding().background(.black.opacity(0.55), in: .rect(cornerRadius: 16))
        case .paused:
            Text("training.safety.paused").font(.title.bold()).padding()
                .background(.red.opacity(0.8), in: .rect(cornerRadius: 16))
        default:
            EmptyView()
        }
    }

    private func counter(height: CGFloat) -> some SwiftUI.View {
        VStack {
            HStack {
                Spacer()
                Text("\(model.count)")
                    .font(.system(size: max(height * 0.25, 60), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .shadow(radius: 6)
                    .padding(.trailing, 24)
                    .onTapGesture { tapForDiagnostics() }
                    .accessibilityLabel(Text("training.count.accessibility \(model.count)"))
            }
            Spacer()
        }
    }

    @ViewBuilder private var demoPanel: some SwiftUI.View {
        if let demo = model.demo {
            DemoFigure(demo: demo, mirrored: model.isFrontCamera)
                .frame(maxWidth: 160, maxHeight: 160)
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
        HStack(spacing: 16) {
            Button {
                model.soundOn.toggle()
            } label: {
                Image(systemName: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("training.sound"))
            Button {
                model.showSkeleton.toggle()
            } label: {
                Image(systemName: "figure.stand").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("training.skeleton"))
            if model.phase == .ready {
                Button("training.start") { model.startNow() }.buttonStyle(.borderedProminent)
            }
            if model.phase == .paused {
                Button("training.resume") { model.resume() }.buttonStyle(.borderedProminent)
            }
            Button(model.phase == .active || model.phase == .paused ? "training.finish" : "training.cancel") {
                if model.phase == .active || model.phase == .paused { model.finish() } else { dismiss() }
            }
            .buttonStyle(.bordered)
        }
        .font(.title3)
        .padding(10)
        .background(.black.opacity(0.5), in: .capsule)
    }

    private var diagnostics: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "FPS %.1f · drop %d · lat %.0f ms", model.fps, model.dropped, model.latencyMs))
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
        VStack(spacing: 20) {
            Text(model.name).font(.title2)
            Text("\(model.count)").font(.system(size: 96, weight: .bold, design: .rounded))
            Text("training.summary \(model.count) \(model.faultyCount)").font(.headline)
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
