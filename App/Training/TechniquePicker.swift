import SoloEngine
import SwiftUI

/// H3, first step (specs/12, specs/06 "Seçim"): pick exactly `count` eskivs for a workout's choice.
struct TechniquePicker: SwiftUI.View {
    let choice: Workout.Choice
    let packs: [String: LoadedRulePack]
    let done: ([String]) -> Void
    @State private var picked: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some SwiftUI.View {
        NavigationStack {
            List(choice.from, id: \.self) { id in
                Button {
                    if let i = picked.firstIndex(of: id) { picked.remove(at: i) } else if picked.count < choice.count { picked.append(id) }
                } label: {
                    HStack {
                        Text(packs[id].map { Lang.text($0.pack.name) } ?? id)
                        Spacer()
                        if picked.contains(id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .frame(minHeight: 44)
                }
                .foregroundStyle(.primary)
                .accessibilityAddTraits(picked.contains(id) ? .isSelected : [])
            }
            .navigationTitle(Text("choose.title \(choice.count)"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("training.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("choose.continue") {
                        dismiss()
                        done(picked)
                    }
                    .disabled(picked.count != choice.count)
                }
            }
        }
    }
}
