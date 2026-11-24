// Recording mode exists only in the GymSpotSoloBeta target (specs/02 "Derleme
// yapılandırmaları", specs/09). In GymSpotSolo this file compiles to nothing and
// SoloRecording is not linked (AC-2.3).
#if RECORDING_MODE
import CoreMedia
import CoreVideo
import SoloEngine
import SoloPose
import SoloRecording
import SwiftUI

#if RECORDING_MODE_RELEASE_FORBIDDEN
#error("GymSpotSoloBeta cannot be built with the Release configuration (specs/02). Archive GymSpotSolo for the App Store.")
#endif

enum RecordingFeature {
    /// The library in the app container (excluded from backup, complete protection; specs/09).
    @MainActor static let library: RecordingLibrary? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Recording", isDirectory: true) else { return nil }
        let lib = try? RecordingLibrary(root: dir)
        try? lib?.purgeExpired(now: Date())  // 12 months at most (specs/09)
        return lib
    }()

    static func link() { _ = SoloRecording.moduleName }

    /// Vision's poses as a pose line: the most confident person's 2D joints (selection happens later, on the main actor).
    static func poseLine(_ poses: [DetectedPose]) -> PoseLine {
        guard let best = poses.max(by: { $0.confidence < $1.confidence }) else { return PoseLine(joints: nil, people: 0, selected: nil) }
        var joints: [String: [Double]] = [:]
        for (j, p) in best.joints { joints[j.rawValue] = [p.x, p.y, p.confidence] }
        return PoseLine(joints: joints, people: poses.count, selected: 0)
    }
}

/// The package writer as the workout's sink.
final class RecordingSinkAdapter: RecordingSink, @unchecked Sendable {
    let writer: RecordingWriter
    init(_ writer: RecordingWriter) { self.writer = writer }
    func engineLine(_ line: [String: Any]) { writer.engineLine(line) }
    func appLine(_ line: [String: Any]) { writer.appLine(line) }
    func finish() { let w = writer; Task { await w.finish() } }
}

/// X1–X4 (specs/12, specs/09): turning the mode on, participants and consent, recordings, starting one.
struct RecordingHome: SwiftUI.View {
    @State private var lib = RecordingFeature.library
    @State private var refresh = 0
    @State private var confirmOn = false
    @State private var newCode = ""
    @State private var running: TrainingModel?
    @State private var participant = ""
    @State private var template = "slip_left"
    @State private var withdrawn: [String]?

    var body: some SwiftUI.View {
        Form {
            if let lib {
                if !lib.isEnabled {
                    Section { Button("rec.enable") { confirmOn = true } } footer: { Text("rec.enable.warning") }
                } else {
                    participantsSection(lib)
                    startSection(lib)
                    recordingsSection(lib)
                    Section { Button("rec.disable", role: .destructive) { try? lib.setEnabled(false); refresh += 1 } }
                }
            }
        }
        .id(refresh)
        .navigationTitle(Text("rec.title"))
        .alert("rec.enable", isPresented: $confirmOn) {
            Button("rec.enable.confirm") { try? lib?.setEnabled(true); refresh += 1 }
            Button("training.cancel", role: .cancel) {}
        } message: { Text("rec.enable.warning") }
        .alert("rec.withdrawn", isPresented: .constant(withdrawn != nil)) {
            Button("training.close") { withdrawn = nil }
        } message: { Text("rec.withdrawn.exports \(withdrawn?.joined(separator: ", ") ?? "")") }
        .fullScreenCover(item: Binding(get: { running.map(RunningBox.init) }, set: { running = $0?.model })) { TrainingView($0.model) }
    }

    struct RunningBox: Identifiable { let model: TrainingModel; var id: ObjectIdentifier { ObjectIdentifier(model) } }

    // X2, X3
    private func participantsSection(_ lib: RecordingLibrary) -> some SwiftUI.View {
        Section("rec.participants") {
            ForEach(lib.participants, id: \.code) { p in
                NavigationLink {
                    ConsentView(code: p.code) { refresh += 1 }
                } label: {
                    HStack {
                        Text(p.code).font(.headline)
                        Spacer()
                        Text(lib.canRecord(p.code) ? "rec.consent.given" : "rec.consent.missing").font(.caption)
                    }
                }
                .swipeActions {
                    if lib.canRecord(p.code) {
                        Button("rec.withdraw", role: .destructive) {
                            withdrawn = (try? lib.withdraw(p.code, at: Date())) ?? []
                            refresh += 1
                        }
                    }
                }
            }
            HStack {
                TextField("rec.code.placeholder", text: $newCode).textInputAutocapitalization(.characters)
                Button("rec.add") { try? lib.addParticipant(newCode, at: Date()); newCode = ""; refresh += 1 }
            }
        }
    }

    // X4
    private func startSection(_ lib: RecordingLibrary) -> some SwiftUI.View {
        let allowed = lib.participants.map(\.code).filter(lib.canRecord)
        return Section("rec.start") {
            Picker("rec.participant", selection: $participant) {
                Text("rec.participant.none").tag("")
                ForEach(allowed, id: \.self) { Text($0).tag($0) }
            }
            Picker("rec.template", selection: $template) {
                ForEach(ExerciseCatalog.load().map(\.pack.id), id: \.self) { Text($0).tag($0) }
            }
            Button("rec.start.button") { start(lib) }.disabled(!allowed.contains(participant))
        }
    }

    // X1
    private func recordingsSection(_ lib: RecordingLibrary) -> some SwiftUI.View {
        Section("rec.recordings") {
            ForEach(lib.packages(), id: \.meta.recordingId) { p in
                NavigationLink { PlaybackView(package: p) } label: {
                    VStack(alignment: .leading) {
                        Text("\(p.meta.participant) · \(p.meta.templates.keys.sorted().joined(separator: ", "))").font(.headline)
                        Text(p.meta.createdAt, style: .date).font(.caption)
                    }
                }
            }
        }
    }

    /// The template file as shipped: its full JSON goes into the meta (specs/09).
    static func templateText(_ id: String) -> String {
        Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "exercises")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    private func start(_ lib: RecordingLibrary) {
        guard let pack = ExerciseCatalog.pack(template), let consent = lib.activeConsent(participant) else { return }
        let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        let meta = RecordingMeta(participant: participant, consentId: consent.id, createdAt: Date(), device: UIDevice.current.model,
                                 osVersion: UIDevice.current.systemVersion,
                                 appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                                 mode: "technique", stance: "orthodox", camera: "front", pose3D: false,
                                 templates: [pack.pack.id: Self.templateText(pack.pack.id)])
        guard let writer = try? lib.newPackage(meta, freeBytes: free) else { return }
        let source = CameraFrameSource()
        source.record = { pb, pts, poses in writer.frame(pb, pts: pts, pose: RecordingFeature.poseLine(poses)) }
        let model = TrainingModel(single: pack, source: source)
        model.recording = RecordingSinkAdapter(writer)
        running = model
    }
}

/// X3: the participant reads, checks 18+ and accepts themselves (specs/09 "Rıza", AC-9.2).
struct ConsentView: SwiftUI.View {
    let code: String
    let done: () -> Void
    @State private var adult = false
    @Environment(\.dismiss) private var dismiss

    var body: some SwiftUI.View {
        Form {
            Section { Text("rec.consent.text").font(.callout) }
            Section {
                Toggle("onboarding.safety.adult", isOn: $adult)
                Button("rec.consent.accept") {
                    _ = try? RecordingFeature.library?.consent(code, adultConfirmed: adult, at: Date())
                    done()
                    dismiss()
                }
                .disabled(!adult)
            }
        }
        .navigationTitle(Text(code))
    }
}
#endif
