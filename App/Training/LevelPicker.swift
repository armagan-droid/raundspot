import SoloEngine
import SwiftUI

/// H3 (specs/12): the reflex level for a workout whose reflex blocks say `level: "chosen"`.
/// The levels of specs/05 in plain words; the suggested one stands out.
struct LevelPicker: SwiftUI.View {
    let catalog: ReflexCatalog
    let suggested: Int
    let pick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some SwiftUI.View {
        NavigationStack {
            List(catalog.levels, id: \.level) { lv in
                Button {
                    dismiss()
                    pick(lv.level)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("reflex.level \(lv.level)").font(.headline)
                            if lv.level == suggested {
                                Text("reflex.level.suggested").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.green.opacity(0.25), in: .capsule)
                            }
                        }
                        Text(Self.describe(lv)).font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
                .foregroundStyle(.primary)
                .listRowBackground(lv.level == suggested ? Color.green.opacity(0.08) : nil)
            }
            .navigationTitle(Text("reflex.level.title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("training.cancel") { dismiss() } } }
        }
    }

    /// "2 strikes · single cues · reaction window 1.5 s", from the level record.
    static func describe(_ lv: ReflexCatalog.Level) -> String {
        var parts = [String(localized: "reflex.level.card.strikes \(lv.strikes.count)")]
        parts.append(lv.comboLen.upperBound == 1 ? String(localized: "reflex.level.card.single")
                     : String(localized: "reflex.level.card.combo \(lv.comboLen.lowerBound) \(lv.comboLen.upperBound)"))
        if lv.feintRate > 0 { parts.append(String(localized: "reflex.level.card.feint \(Int((lv.feintRate * 100).rounded()))")) }
        let window = (Double(lv.windowMs) / 1000).formatted(.number.precision(.fractionLength(0...1)))
        parts.append(String(localized: "reflex.level.card.window \(window)"))
        return parts.joined(separator: " · ")
    }
}
