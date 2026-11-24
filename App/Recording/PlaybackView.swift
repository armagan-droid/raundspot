#if RECORDING_MODE
import AVKit
import SoloEngine
import SoloPose
import SoloRecording
import SwiftUI

/// The pose of each video frame of a package, by its time in the video (specs/09: same PTS, AC-9.4).
struct PlaybackPoses {
    struct Item { let videoSec: Double; let hostMs: Double; let frame: Frame? }
    let items: [Item]
    let aspect: Double

    init(_ dir: URL) {
        var items: [Item] = []
        var aspect = 16.0 / 9
        let text = (try? String(contentsOf: dir.appendingPathComponent("poses.jsonl"), encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], (o["inVideo"] as? Bool) != false,
                  let v = (o["videoValue"] as? NSNumber)?.doubleValue, let s = (o["videoScale"] as? NSNumber)?.doubleValue,
                  let t = o["t"] as? Double else { continue }
            var frame: Frame?
            if (o["skipped"] as? Bool) != true, let joints = o["joints"] as? [String: [Double]] {
                aspect = (o["aspect"] as? Double) ?? aspect
                let j = Dictionary(uniqueKeysWithValues: joints.compactMap { k, p in
                    p.count == 3 ? VisionJoint(rawValue: k).map { ($0, DetectedJoint(x: p[0], y: p[1], confidence: p[2])) } : nil })
                frame = FrameMapper.candidates([DetectedPose(confidence: 1, joints: j)], t: t, imageAspect: aspect).first
            }
            items.append(Item(videoSec: v / s, hostMs: t, frame: frame))
        }
        self.items = items.sorted { $0.videoSec < $1.videoSec }
        self.aspect = aspect
    }

    /// The frame shown at a video time: the last one at or before it.
    func item(at sec: Double) -> Item? {
        var lo = 0, hi = items.count - 1, best: Item?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if items[mid].videoSec <= sec + 1e-6 { best = items[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        return best
    }

    /// Host ms → video seconds (for markers and notes).
    func videoSec(host: Double) -> Double? {
        guard let first = items.first else { return nil }
        return first.videoSec + (host - first.hostMs) / 1000
    }

    func host(videoSec: Double) -> Double? {
        guard let first = items.first else { return nil }
        return first.hostMs + (videoSec - first.videoSec) * 1000
    }
}

/// X5 (specs/12, specs/09 "Oynatma ekranı"), with X6 (replay) and X7 (landmark export).
struct PlaybackView: SwiftUI.View {
    let package: RecordingLibrary.PackageInfo
    @State private var player: AVPlayer
    private let poses: PlaybackPoses
    private let template: String
    private let markers: [(sec: Double, type: String)]
    @State private var now = 0.0
    @State private var rate: Float = 1
    @State private var notes: [RecordingNote]
    @State private var noteText = ""
    @State private var author = RecordingNote.Author.coach
    @State private var labelOutcome = ""
    @State private var labelFaults: Set<String> = []
    @State private var exportURL: URL?
    @State private var sweepPath = "rep.target.enter"
    @State private var sweepValues = ""
    @State private var replayResult = ""

    init(package: RecordingLibrary.PackageInfo) {
        self.package = package
        _player = State(initialValue: AVPlayer(url: package.url.appendingPathComponent("video.mov")))
        poses = PlaybackPoses(package.url)
        template = package.meta.templates.keys.sorted().first ?? ""
        _notes = State(initialValue: RecordingNotes.load(package.url))
        let p = poses
        markers = RecordingReplay.recorded(package: package.url, template: package.meta.templates.keys.sorted().first ?? "").compactMap { e in
            guard let sec = p.videoSec(host: e.t), let v = try? JSONValue.parse(Data(e.json.utf8)), let type = v["type"]?.stringValue,
                  type != "READY_POSE_HELD" else { return nil }
            return (sec, type == "REP_COMPLETED" ? (v["outcome"]?.stringValue ?? type) : type)
        }
    }

    private var faultIds: [String] { ExerciseCatalog.pack(template)?.pack.faults.map(\.id) ?? [] }

    var body: some SwiftUI.View {
        Form {
            Section {
                ZStack {
                    VideoPlayer(player: player)
                    // the frame's skeleton: same PTS as the picture (AC-9.4)
                    SkeletonOverlay(frame: poses.item(at: now)?.frame, aspect: poses.aspect, mirrored: false, minVisibility: 0.3)
                        .allowsHitTesting(false)
                }
                .aspectRatio(poses.aspect, contentMode: .fit)
                timeline
                controls
            }
            notesSection
            replaySection
            exportSection
        }
        .navigationTitle(Text("\(package.meta.participant) · \(template)"))
        .onReceive(Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()) { _ in
            now = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        }
    }

    private var duration: Double { max(poses.items.last?.videoSec ?? 1, 0.001) }

    /// Event markers under the video (cue, start, outcome, fault, safety, tracking, notes).
    private var timeline: some SwiftUI.View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.gray.opacity(0.3)).frame(height: 6)
                ForEach(Array(markers.enumerated()), id: \.offset) { _, m in
                    Rectangle().fill(Self.color(m.type)).frame(width: 2, height: 16)
                        .offset(x: g.size.width * m.sec / duration)
                }
                ForEach(notes) { n in
                    if let s = poses.videoSec(host: n.t) {
                        Circle().fill(.yellow).frame(width: 8, height: 8).offset(x: g.size.width * s / duration - 4, y: -10)
                    }
                }
                Rectangle().fill(.white).frame(width: 2, height: 20).offset(x: g.size.width * now / duration)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                seek(max(0, min(duration, duration * v.location.x / g.size.width)))
            })
        }
        .frame(height: 28)
    }

    static func color(_ type: String) -> Color {
        switch type {
        case "valid": .green
        case "faulty", "FAULT_DETECTED": .orange
        case "incomplete": .gray
        case "SAFETY_PAUSE", "TRACKING_LOST": .red
        default: .blue
        }
    }

    private var controls: some SwiftUI.View {
        HStack(spacing: 14) {
            Button { jump(-1) } label: { Image(systemName: "backward.end") }.accessibilityLabel(Text("rec.play.previous_marker"))
            Button { step(-1) } label: { Image(systemName: "backward.frame") }.accessibilityLabel(Text("rec.play.frame_back"))
            Button { player.timeControlStatus == .playing ? player.pause() : player.playImmediately(atRate: rate) } label: {
                Image(systemName: player.timeControlStatus == .playing ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(Text("rec.play.play_pause"))
            Button { step(1) } label: { Image(systemName: "forward.frame") }.accessibilityLabel(Text("rec.play.frame_forward"))
            Button { jump(1) } label: { Image(systemName: "forward.end") }.accessibilityLabel(Text("rec.play.next_marker"))
            Picker("rec.play.speed", selection: $rate) {
                Text("0.25×").tag(Float(0.25))
                Text("0.5×").tag(Float(0.5))
                Text("1×").tag(Float(1))
            }
            .pickerStyle(.segmented)
            .onChange(of: rate) { _, r in if player.timeControlStatus == .playing { player.rate = r } }
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }

    private func seek(_ sec: Double) {
        player.seek(to: CMTime(seconds: sec, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        now = sec
    }

    private func step(_ n: Int) {
        player.pause()
        player.currentItem?.step(byCount: n)
    }

    private func jump(_ dir: Int) {
        let times = (markers.map(\.sec) + notes.compactMap { poses.videoSec(host: $0.t) }).sorted()
        let target = dir > 0 ? times.first { $0 > now + 0.01 } : times.last { $0 < now - 0.01 }
        if let target { seek(target) }
    }

    // MARK: Notes

    private var notesSection: some SwiftUI.View {
        Section("rec.notes") {
            ForEach(notes) { n in
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.text)
                    HStack {
                        Text(n.author == .coach ? "rec.note.coach" : "rec.note.developer")
                        if let l = n.label { Text("\(l.outcome) \(l.faults.joined(separator: ", "))") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .onTapGesture { if let s = poses.videoSec(host: n.t) { seek(s) } }
            }
            .onDelete { idx in
                notes.remove(atOffsets: idx)
                try? RecordingNotes.save(notes, package.url)
            }
            TextField("rec.note.text", text: $noteText, axis: .vertical)
            Picker("rec.note.author", selection: $author) {
                Text("rec.note.coach").tag(RecordingNote.Author.coach)
                Text("rec.note.developer").tag(RecordingNote.Author.developer)
            }
            Picker("rec.note.outcome", selection: $labelOutcome) {
                Text("rec.note.no_label").tag("")
                Text("valid").tag("valid")
                Text("faulty").tag("faulty")
                Text("incomplete").tag("incomplete")
            }
            if !labelOutcome.isEmpty {
                ForEach(faultIds, id: \.self) { f in
                    Toggle(f, isOn: Binding(get: { labelFaults.contains(f) }, set: { on in
                        if on { labelFaults.insert(f) } else { labelFaults.remove(f) }
                    }))
                }
            }
            Button("rec.note.add") { addNote() }.disabled(noteText.isEmpty && labelOutcome.isEmpty)
        }
    }

    private func addNote() {
        guard let host = poses.host(videoSec: now) else { return }
        let label = labelOutcome.isEmpty ? nil : RecordingNote.Label(outcome: labelOutcome, faults: labelFaults.sorted())
        notes.append(RecordingNote(t: host, text: noteText, author: author, label: label))
        notes.sort { $0.t < $1.t }
        try? RecordingNotes.save(notes, package.url)
        noteText = ""
        labelOutcome = ""
        labelFaults = []
    }

    // MARK: X6

    private var replaySection: some SwiftUI.View {
        Section("rec.replay") {
            TextField("rec.replay.path", text: $sweepPath).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("rec.replay.values", text: $sweepValues).keyboardType(.numbersAndPunctuation)
            Button("rec.replay.run") { replay() }
            if !replayResult.isEmpty {
                Text(replayResult).font(.caption.monospaced()).textSelection(.enabled)
                Button("rec.replay.copy") { UIPasteboard.general.string = replayResult }
            }
        }
    }

    /// New thresholds on this recording: the change in events for each value (specs/09; nothing stored).
    private func replay() {
        guard let url = Bundle.main.url(forResource: template, withExtension: "json", subdirectory: "exercises"),
              let json = try? JSONValue.parse(contentsOf: url), let pack = try? RulePackLoader.load(json, capabilities: .vision19TwoD).get(),
              let seq = try? RecordingExport.sequence(package: package.url, consentVersion: RecordingLibrary.consentVersion,
                                                      templateVersions: [template: pack.pack.version]) else {
            replayResult = String(localized: "rec.replay.unavailable")
            return
        }
        let setup = ExerciseSetup(view: seq.view == .side ? .side : .front, nearSide: .left)
        let base = RecordingReplay.run(seq, pack: pack, setup: setup)
        var rows: [String] = ["value\tadded\tremoved\tcompleted"]
        let values = sweepValues.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        for v in values.prefix(7) {
            guard let new = try? RecordingReplay.run(seq, rulePack: json, path: sweepPath, value: v, setup: setup) else {
                rows.append("\(v)\terror")
                continue
            }
            let d = RecordingReplay.diff(old: base, new: new)
            rows.append("\(v)\t\(d.added.count)\t\(d.removed.count)\t\(new.filter { $0.json.contains("REP_COMPLETED") }.count)")
        }
        replayResult = rows.joined(separator: "\n")
    }

    // MARK: X7

    private var exportSection: some SwiftUI.View {
        Section("rec.export") {
            if let exportURL {
                ShareLink(item: exportURL) { Label("rec.export.share", systemImage: "square.and.arrow.up") }
            } else {
                Button("rec.export.make") {
                    let version = ExerciseCatalog.pack(template)?.pack.version ?? 1
                    exportURL = try? RecordingExport.export(package: package.url, consentVersion: RecordingLibrary.consentVersion,
                                                            templateVersions: [template: version], to: FileManager.default.temporaryDirectory)
                }
            }
            Text("rec.export.note").font(.caption).foregroundStyle(.secondary)
        }
    }
}
#endif
