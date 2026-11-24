import SoloHealth
import SwiftData
import SwiftUI

/// Ayarlar (specs/12 A). The cue sound of the reflex mode has no switch (specs/05).
struct SettingsView: SwiftUI.View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var profiles: [Profile]
    @State private var confirmDelete = false
    @State private var exportURL: URL?
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable { case privacy, terms, medical; var id: String { rawValue } }

    var body: some SwiftUI.View {
        NavigationStack {
            Form {
                if let p = profiles.first { profileSections(p) }
                Section("settings.data") {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("settings.export.share", systemImage: "square.and.arrow.up") }
                    } else {
                        Button("settings.export") { export() }
                    }
                    Button("settings.delete_all", role: .destructive) { confirmDelete = true }
                }
                Section("settings.about") {
                    Button("settings.privacy_policy") { sheet = .privacy }
                    Button("settings.terms") { sheet = .terms }
                    Button("settings.medical") { sheet = .medical }
                    LabeledContent("settings.version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
                #if DEBUG || BETA
                Section("settings.developer") {
                    Text("settings.developer.diagnostics").font(.callout)
                }
                #endif
            }
            .navigationTitle(Text("tab.settings"))
            .confirmationDialog("settings.delete_all.confirm", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("settings.delete_all", role: .destructive) { try? DataPortability.deleteAll(context) }
            }
            .sheet(item: $sheet) { s in
                NavigationStack {
                    ScrollView { Text(LocalizedStringKey("settings.text.\(s.rawValue)")).padding() }
                        .toolbar { Button("training.close") { sheet = nil } }
                }
            }
        }
    }

    @ViewBuilder private func profileSections(_ p: Profile) -> some SwiftUI.View {
        @Bindable var p = p
        Section("settings.language") {
            Button("onboarding.language") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
        }
        Section("settings.you") {
            Picker("onboarding.stance.title", selection: $p.stance) {
                Text("stance.orthodox").tag("orthodox")
                Text("stance.southpaw").tag("southpaw")
            }
            Picker("onboarding.level.title", selection: $p.level) {
                Text("level.beginner").tag("beginner")
                Text("level.intermediate").tag("intermediate")
                Text("level.advanced").tag("advanced")
            }
            Picker("onboarding.goal.title", selection: $p.goal) {
                Text("goal.defense").tag("defense")
                Text("goal.conditioning").tag("conditioning")
                Text("goal.balanced").tag("balanced")
            }
            LabeledContent("settings.weight") {
                TextField("onboarding.weight.placeholder", value: $p.weightKg, format: .number).keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("settings.height") {
                TextField("settings.height.placeholder", value: $p.heightCm, format: .number).keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
        Section("settings.training") {
            Picker("settings.camera", selection: $p.camera) {
                Text("settings.camera.front").tag("front")
                Text("settings.camera.back").tag("back")
            }
            Toggle("settings.fault_voice", isOn: $p.faultCueVoice)
            Toggle("settings.result_tones", isOn: $p.resultTones)
            Text("settings.cue_sound_always").font(.caption).foregroundStyle(.secondary)
            Picker("settings.tempo", selection: $p.techniqueTempo) {
                Text("settings.tempo.slow").tag("slow")
                Text("settings.tempo.normal").tag("normal")
            }
        }
        Section("settings.health") {
            Text(LiveHealthStore.canWriteWorkouts ? "settings.health.on" : "settings.health.off").font(.callout)
            Button("onboarding.healthkit.allow") { Task { _ = await LiveHealthStore().requestAuthorization() } }
                .disabled(!LiveHealthStore.isAvailable)
            Button("settings.health.system") { if let url = URL(string: "x-apple-health://") { openURL(url) } }
        }
    }

    private func export() {
        guard let data = try? DataPortability.export(context) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gymspot-solo-export.json")
        if (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil { exportURL = url }
    }
}
