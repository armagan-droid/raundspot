import SoloCapture
import SoloEngine
import SoloHealth
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// H1/H2 (specs/12), trial form: ready-made workouts, then single templates.
/// The tab bar (Antrenman · İlerleme · Ayarlar) arrives with the screen tasks.
struct RootView: SwiftUI.View {
    private let packs = ExerciseCatalog.load()
    @State private var running: Running?
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    /// Debug: the fake camera's landmark sequence (specs/02 "Derleme yapılandırmaları").
    @State private var fakeSequence: LandmarkSequence?
    @State private var pickingSequence = false
    /// H3: a workout waiting for its reflex level.
    @State private var levelFor: Workout?
    /// H3, first step: a workout waiting for its eskiv picks (specs/06 "Seçim").
    @State private var choiceFor: Workout?
    @State private var resolvedChoice: Workout?
    /// HealthKit's latest weight, read when the list appears (specs/08 "Kilo"); never stored.
    @State private var healthWeight: (kg: Double, date: Date)?
    private let reflexCatalog = ExerciseCatalog.reflexCatalog()

    struct Running: Identifiable {
        let id = UUID()
        let model: TrainingModel
    }

    var body: some SwiftUI.View {
        let byId = Dictionary(uniqueKeysWithValues: packs.map { ($0.pack.id, $0) })
        NavigationStack {
            List {
                Section("list.workouts") {
                    ForEach(ExerciseCatalog.workouts(packs), id: \.id) { w in
                        Button {
                            prepare(w, packs: byId)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Lang.text(w.name)).font(.headline)
                                Text("list.workout.minutes \(w.estimatedMinutes)").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("list.single") {
                    ForEach(packs, id: \.pack.id) { loaded in
                        Button {
                            running = Running(model: TrainingModel(single: loaded, recorder: recorder(for: nil), source: frameSource(), settings: trainingSettings,
                                                                           health: healthStore()))
                        } label: { row(loaded) }
                            .foregroundStyle(.primary)
                    }
                }
                #if DEBUG
                Section("debug.section") {
                    Button(fakeSequence == nil ? "debug.fake_camera.pick" : "debug.fake_camera.off") {
                        if fakeSequence == nil { pickingSequence = true } else { fakeSequence = nil }
                    }
                    if let seq = fakeSequence {
                        Text("debug.fake_camera.on \(seq.exerciseId) \(seq.frames.count)").font(.caption)
                    }
                }
                #endif
            }
            .fileImporter(isPresented: $pickingSequence, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                fakeSequence = (try? Data(contentsOf: url)).flatMap { try? LandmarkSequence.parse(data: $0).get() }
            }
            .overlay {
                if packs.isEmpty { Text("list.empty") }
            }
            .navigationTitle(AppBrand.name)
            .task {
                if LiveHealthStore.isAvailable { healthWeight = await LiveHealthStore().latestBodyMass() }
            }
        }
        .fullScreenCover(item: $running) { TrainingView($0.model) }
        .sheet(item: $choiceFor, onDismiss: {
            // the next step opens once this sheet is gone
            if let w = resolvedChoice {
                resolvedChoice = nil
                prepare(w, packs: Dictionary(uniqueKeysWithValues: packs.map { ($0.pack.id, $0) }))
            }
        }) { w in
            if let c = w.choices.first {
                TechniquePicker(choice: c, packs: Dictionary(uniqueKeysWithValues: packs.map { ($0.pack.id, $0) })) { picks in
                    // one choice per workout today (Hızlı karma); more would be asked in turn
                    resolvedChoice = try? w.resolving(picks: [picks])
                }
            }
        }
        .sheet(item: $levelFor) { w in
            if let catalog = reflexCatalog {
                LevelPicker(catalog: catalog, suggested: profiles.first?.reflexLevel ?? 1) { n in
                    remember(level: n)
                    start(w, packs: Dictionary(uniqueKeysWithValues: packs.map { ($0.pack.id, $0) }), level: n)
                }
            }
        }
    }

    private func row(_ loaded: LoadedRulePack) -> some SwiftUI.View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: loaded.pack.camera.views.contains(.front) ? "person.fill" : "figure.walk")
                .font(.title2).frame(width: 32)
                .accessibilityLabel(Text(loaded.pack.camera.views.contains(.front) ? "list.view.front" : "list.view.side"))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Lang.text(loaded.pack.name)).font(.headline)
                    if loaded.pack.status == .draft {
                        Text("list.draft").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.yellow.opacity(0.3), in: .capsule)
                    }
                }
                if let how = loaded.pack.howTo {
                    Text(Lang.text(how)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .frame(minHeight: 44)
    }

    /// H3: the start's questions in order (eskivs, then the reflex level), then the workout.
    private func prepare(_ w: Workout, packs: [String: LoadedRulePack]) {
        if w.choices.count == 1 {
            choiceFor = w
        } else if Self.choosesLevel(w), reflexCatalog != nil {
            levelFor = w
        } else {
            start(w, packs: packs, level: profiles.first?.reflexLevel ?? 1)
        }
    }

    private static func choosesLevel(_ w: Workout) -> Bool {
        w.blocks.contains { if case .reflex(_, .chosen, _, _, _) = $0 { true } else { false } }
    }

    private var stance: Stance { profiles.first.flatMap { Stance(rawValue: $0.stance) } ?? .orthodox }

    private func start(_ w: Workout, packs: [String: LoadedRulePack], level: Int) {
        running = Running(model: TrainingModel(workout: w, packs: packs, recorder: recorder(for: w), source: frameSource(),
                                               reflexCatalog: reflexCatalog, stance: stance, reflexLevel: level,
                                               settings: trainingSettings, health: healthStore()))
    }

    /// The picked level becomes the next suggestion (specs/11 `Profile.reflexLevel`).
    private func remember(level: Int) {
        let p = profiles.first ?? {
            let p = Profile(createdAt: Date())
            context.insert(p)
            return p
        }()
        p.reflexLevel = level
        try? context.save()
    }

    /// The profile's settings, with the weight by specs/08's order: HealthKit (≤ 90 days), then the profile.
    private var trainingSettings: TrainingSettings {
        var s = TrainingSettings(profiles.first)
        s.weightKg = Energy.weight(healthKit: healthWeight, profile: profiles.first?.weightKg, now: Date())
        return s
    }

    /// Apple Health when the user allowed workouts (specs/08); nil otherwise, and nothing stops.
    private func healthStore() -> HealthStore? { LiveHealthStore.canWriteWorkouts ? LiveHealthStore() : nil }

    /// The camera, or in Debug the chosen sequence file replayed on the host clock.
    private func frameSource() -> FrameSource {
        if let seq = fakeSequence { return SequenceFrameSource(sequence: seq, clock: LiveClock.shared, autoPump: true) }
        return CameraFrameSource(position: profiles.first?.camera == "back" ? .back : .front)
    }

    /// Writes the workout's records to the store (specs/11).
    private func recorder(for workout: Workout?) -> SessionRecorder {
        let blocks = workout?.blocks ?? []
        let info = RecordContext(
            workoutVersion: nil, sport: workout?.sport ?? "muay_thai", stance: profiles.first?.stance ?? "orthodox",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            blockKind: { i in blocks.indices.contains(i) ? blocks[i].kind : "technique" },
            catalog: { i in
                guard blocks.indices.contains(i), case .reflex(let id, let level, _, _, _) = blocks[i] else { return nil }
                return (id, nil, level.storedLevel)
            })
        return SessionRecorder(context: context, info: info)
    }
}

extension Workout: @retroactive Identifiable {}
