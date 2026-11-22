import SoloEngine
import SwiftUI

/// H2 template list (specs/12) as the trial root. The tab bar (Antrenman ·
/// İlerleme · Ayarlar) arrives with the screen tasks (T3.5 and later).
struct RootView: SwiftUI.View {
    private let packs = ExerciseCatalog.load()
    @State private var selected: LoadedRulePack?

    var body: some SwiftUI.View {
        NavigationStack {
            List(packs, id: \.pack.id) { loaded in
                Button {
                    selected = loaded
                } label: {
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
                .foregroundStyle(.primary)
            }
            .overlay {
                if packs.isEmpty { Text("list.empty") }
            }
            .navigationTitle(AppBrand.name)
        }
        .fullScreenCover(item: $selected) { TrainingView($0) }
    }
}

extension LoadedRulePack: @retroactive Identifiable {
    public var id: String { pack.id }
}
