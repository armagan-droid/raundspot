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
    /// A reflex note's right response: a response template or `noResponse`; "" for no label.
    @State private var labelResponse = ""
    /// The note in the form (specs/09 "Not düzenleme"), nil for a new one.
    @State private var editing: UUID?
    // specs/09 "Deneme işaretleme"
    @State private var marks: [AttemptMark]
    @State private var markStart: Double?
    @State private var editingMark: UUID?
    @State private var markOutcome = "valid"
    @State private var markFaults: Set<String> = []
    @State private var markInvalid = false
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
        _marks = State(initialValue: RecordingMarks.load(package.url))
        let p = poses
        if package.meta.isReflex {
            // a reflex recording: its cues and trial results (specs/09 "Refleks kaydı")
            let cues = RecordingNotes.appLines(package.url, type: "cue").compactMap { o in (o["t"] as? Double).flatMap(p.videoSec(host:)).map { ($0, "cue") } }
            let trials = RecordingNotes.appLines(package.url, type: "trial").compactMap { o -> (Double, String)? in
                guard let sec = (o["t"] as? Double).flatMap(p.videoSec(host:)) else { return nil }
                return (sec, o["result"] as? String ?? "trial")
            }
            markers = (cues + trials).sorted { $0.0 < $1.0 }
        } else {
            markers = RecordingReplay.recorded(package: package.url, template: package.meta.templates.keys.sorted().first ?? "").compactMap { e in
                guard let sec = p.videoSec(host: e.t), let v = try? JSONValue.parse(Data(e.json.utf8)), let type = v["type"]?.stringValue,
                      type != "READY_POSE_HELD" else { return nil }
                return (sec, type == "REP_COMPLETED" ? (v["outcome"]?.stringValue ?? type) : type)
            }
        }
    }

    private var isReflex: Bool { package.meta.isReflex }
    /// The faults of the labelled template: the recording's template, or the reflex note's response.
    private var faultIds: [String] {
        let id = isReflex ? labelResponse : template
        return ExerciseCatalog.pack(id)?.pack.faults.map(\.id) ?? []
    }
    private var hasLabel: Bool { isReflex ? !labelResponse.isEmpty : !labelOutcome.isEmpty }

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
            if !isReflex { marksSection }  // reflex trials are the trial lines (specs/09)
            notesSection
            if !isReflex { replaySection }  // reflex replay is not there yet (specs/09)
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
                ForEach(marks) { m in
                    if let a = poses.videoSec(host: m.start), let b = poses.videoSec(host: m.end) {
                        Rectangle().fill(Self.color(m.label.outcome ?? "").opacity(0.35))
                            .frame(width: max(2, g.size.width * (b - a) / duration), height: 14)
                            .offset(x: g.size.width * a / duration)
                    }
                }
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
        case "valid", "correct", "feint_ok": .green
        case "faulty", "FAULT_DETECTED", "correct_faulty", "partial": .orange
        case "incomplete", "missed": .gray
        case "SAFETY_PAUSE", "TRACKING_LOST", "wrong", "early", "feint_bitten": .red
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
                        if let l = n.label { Text(Self.describe(l)) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(editing == n.id ? Color.yellow.opacity(0.15) : nil)
                .contentShape(Rectangle())
                .onTapGesture { edit(n) }
            }
            .onDelete { idx in
                if let e = editing, idx.contains(where: { notes[$0].id == e }) { clearForm() }
                notes.remove(atOffsets: idx)
                try? RecordingNotes.save(notes, package.url)
            }
            TextField("rec.note.text", text: $noteText, axis: .vertical)
            Picker("rec.note.author", selection: $author) {
                Text("rec.note.coach").tag(RecordingNote.Author.coach)
                Text("rec.note.developer").tag(RecordingNote.Author.developer)
            }
            if isReflex {
                Picker("rec.note.response", selection: $labelResponse) {
                    Text("rec.note.no_label").tag("")
                    ForEach(package.meta.templates.keys.sorted(), id: \.self) { Text($0).tag($0) }
                    Text("rec.note.no_response").tag(RecordingNote.Label.noResponse)
                }
            } else {
                Picker("rec.note.outcome", selection: $labelOutcome) {
                    Text("rec.note.no_label").tag("")
                    Text("valid").tag("valid")
                    Text("faulty").tag("faulty")
                    Text("incomplete").tag("incomplete")
                }
            }
            if hasLabel {
                ForEach(faultIds, id: \.self) { f in
                    Toggle(f, isOn: Binding(get: { labelFaults.contains(f) }, set: { on in
                        if on { labelFaults.insert(f) } else { labelFaults.remove(f) }
                    }))
                }
            }
            if editing != nil {
                Button("rec.note.save") { saveNote() }.disabled(noteText.isEmpty && !hasLabel)
                Button("rec.note.cancel", role: .cancel) { clearForm() }
            } else {
                Button("rec.note.add") { saveNote() }.disabled(noteText.isEmpty && !hasLabel)
            }
        }
    }

    private var markFaultToggles: some SwiftUI.View {
        ForEach(faultIds, id: \.self) { f in
            Toggle(f, isOn: Binding(get: { markFaults.contains(f) }, set: { on in
                if on { markFaults.insert(f) } else { markFaults.remove(f) }
            }))
        }
    }

    private var markOutcomePicker: some SwiftUI.View {
        Picker("rec.note.outcome", selection: $markOutcome) {
            Text("valid").tag("valid")
            Text("faulty").tag("faulty")
            Text("incomplete").tag("incomplete")
        }
    }

    /// Attempts marked by hand: start, end and label (specs/09 "Deneme işaretleme").
    private var marksSection: some SwiftUI.View {
        Section {
            ForEach(marks) { m in
                HStack {
                    Text(verbatim: Self.span(m, poses)).monospacedDigit()
                    Spacer()
                    Text(Self.describe(m.label)).font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(editingMark == m.id ? Color.yellow.opacity(0.15) : nil)
                .contentShape(Rectangle())
                .onTapGesture { editMark(m) }
            }
            .onDelete { idx in
                if let e = editingMark, idx.contains(where: { marks[$0].id == e }) { clearMark() }
                marks.remove(atOffsets: idx)
                try? RecordingMarks.save(marks, package.url)
            }
            if let e = editingMark {
                markOutcomePicker
                markFaultToggles
                Button("rec.note.save") {
                    if let i = marks.firstIndex(where: { $0.id == e }) {
                        marks[i].label = RecordingNote.Label(outcome: markOutcome, faults: markFaults.filter(faultIds.contains).sorted())
                        try? RecordingMarks.save(marks, package.url)
                    }
                    clearMark()
                }
                Button("rec.note.cancel", role: .cancel) { clearMark() }
            } else if let start = markStart {
                Text("rec.mark.started \(String(format: "%.2f", poses.videoSec(host: start) ?? 0))").monospacedDigit()
                markOutcomePicker
                markFaultToggles
                Button("rec.mark.end") { endMark(start) }
                Button("rec.note.cancel", role: .cancel) { clearMark() }
            } else {
                Button("rec.mark.start") { markStart = poses.host(videoSec: now); markInvalid = false }
            }
            if markInvalid { Text("rec.mark.invalid").font(.caption).foregroundStyle(.red) }
        } header: {
            Text("rec.marks")
        } footer: {
            Text("rec.marks.footer")
        }
    }

    static func span(_ m: AttemptMark, _ poses: PlaybackPoses) -> String {
        String(format: "%.2f–%.2f s", poses.videoSec(host: m.start) ?? 0, poses.videoSec(host: m.end) ?? 0)
    }

    private func editMark(_ m: AttemptMark) {
        if let s = poses.videoSec(host: m.start) { seek(s) }
        markStart = nil
        editingMark = m.id
        markOutcome = m.label.outcome ?? "valid"
        markFaults = Set(m.label.faults)
        markInvalid = false
    }

    private func endMark(_ start: Double) {
        guard let end = poses.host(videoSec: now) else { return }
        let mark = AttemptMark(start: start, end: end, label: RecordingNote.Label(outcome: markOutcome, faults: markFaults.filter(faultIds.contains).sorted()))
        guard let next = try? RecordingMarks.adding(mark, to: marks) else { markInvalid = true; return }
        marks = next
        try? RecordingMarks.save(marks, package.url)
        clearMark()
    }

    private func clearMark() {
        markStart = nil
        editingMark = nil
        markOutcome = "valid"
        markFaults = []
    }

    static func describe(_ l: RecordingNote.Label) -> String {
        let head = l.response.map { $0 == RecordingNote.Label.noResponse ? String(localized: "rec.note.no_response") : $0 } ?? l.outcome ?? ""
        return ([head] + l.faults).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var formLabel: RecordingNote.Label? {
        let faults = labelFaults.filter(faultIds.contains).sorted()
        if isReflex { return labelResponse.isEmpty ? nil : RecordingNote.Label(response: labelResponse, faults: faults) }
        return labelOutcome.isEmpty ? nil : RecordingNote.Label(outcome: labelOutcome, faults: faults)
    }

    /// Tapping a note seeks to it and loads it into the form.
    private func edit(_ n: RecordingNote) {
        if let s = poses.videoSec(host: n.t) { seek(s) }
        editing = n.id
        noteText = n.text
        author = n.author
        labelOutcome = n.label?.outcome ?? ""
        labelResponse = n.label?.response ?? ""
        labelFaults = Set(n.label?.faults ?? [])
    }

    /// A new note at the current time, or the edited note with its time kept.
    private func saveNote() {
        if let e = editing, let i = notes.firstIndex(where: { $0.id == e }) {
            notes[i] = RecordingNotes.edited(notes[i], text: noteText, author: author, label: formLabel)
        } else {
            guard let host = poses.host(videoSec: now) else { return }
            notes.append(RecordingNote(t: host, text: noteText, author: author, label: formLabel))
            notes.sort { $0.t < $1.t }
        }
        try? RecordingNotes.save(notes, package.url)
        clearForm()
    }

    private func clearForm() {
        editing = nil
        noteText = ""
        labelOutcome = ""
        labelResponse = ""
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
