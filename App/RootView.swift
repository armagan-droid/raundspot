import SoloEngine
import SwiftData
import SwiftUI

/// H1/H2 (specs/12), trial form: ready-made workouts, then single templates.
/// The tab bar (Antrenman · İlerleme · Ayarlar) arrives with the screen tasks.
struct RootView: SwiftUI.View {
    private let packs = ExerciseCatalog.load()
    @State private var running: Running?
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

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
                            running = Running(model: TrainingModel(workout: w, packs: byId, recorder: recorder(for: w)))
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
                            running = Running(model: TrainingModel(single: loaded, recorder: recorder(for: nil)))
                        } label: { row(loaded) }
                            .foregroundStyle(.primary)
                    }
                }
            }
            .overlay {
                if packs.isEmpty { Text("list.empty") }
            }
            .navigationTitle(AppBrand.name)
        }
        .fullScreenCover(item: $running) { TrainingView($0.model) }
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
