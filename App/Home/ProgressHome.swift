import SwiftData
import SwiftUI

/// İlerleme tab (specs/12 G1–G3 come with T7.2): the past workouts for now.
struct ProgressHome: SwiftUI.View {
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var sessions: [StoredSession]

    var body: some SwiftUI.View {
        NavigationStack {
            List(sessions) { s in
                VStack(alignment: .leading) {
                    Text(s.workoutId).font(.headline)
                    Text(s.startedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
            .overlay { if sessions.isEmpty { Text("progress.empty").foregroundStyle(.secondary) } }
            .navigationTitle(Text("tab.progress"))
        }
    }
}
