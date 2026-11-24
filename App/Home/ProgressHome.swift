import Charts
import SoloEngine
import SwiftData
import SwiftUI

/// İlerleme (specs/12 G1–G3).
struct ProgressHome: SwiftUI.View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredSession.startedAt, order: .reverse) private var sessions: [StoredSession]

    var body: some SwiftUI.View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("progress.empty").foregroundStyle(.secondary)
                } else {
                    overview
                    eskivSection
                    Section("progress.history") {
                        ForEach(sessions) { s in
                            NavigationLink { SessionDetail(session: s) } label: { SessionRow(session: s) }
                        }
                        .onDelete { idx in
                            for i in idx { delete(sessions[i]) }
                        }
                    }
                }
            }
            .navigationTitle(Text("tab.progress"))
        }
    }

    // G1
    @ViewBuilder private var overview: some SwiftUI.View {
        let weeks = ProgressStats.weeks(sessions, now: Date())
        Section("progress.weeks") {
            Chart(weeks, id: \.start) { w in
                BarMark(x: .value("week", w.start, unit: .weekOfYear), y: .value("workouts", w.workouts))
            }
            .frame(height: 140)
            .accessibilityLabel(Text("progress.weeks"))
            let rt = weeks.flatMap { w in w.medianRtByLevel.map { (week: w.start, level: $0.key, ms: $0.value) } }
            if !rt.isEmpty {
                Text("progress.rt").font(.headline)
                Chart(rt, id: \.week) { p in
                    LineMark(x: .value("week", p.week, unit: .weekOfYear), y: .value("ms", p.ms))
                        .foregroundStyle(by: .value("level", String(localized: "reflex.level \(p.level)")))
                    PointMark(x: .value("week", p.week, unit: .weekOfYear), y: .value("ms", p.ms))
                        .foregroundStyle(by: .value("level", String(localized: "reflex.level \(p.level)")))
                }
                .frame(height: 140)
            }
            let hits = weeks.compactMap { w in w.hitRate.map { (week: w.start, rate: $0) } }
            if !hits.isEmpty {
                Text("progress.hits").font(.headline)
                Chart(hits, id: \.week) { p in
                    LineMark(x: .value("week", p.week, unit: .weekOfYear), y: .value("%", p.rate * 100))
                    PointMark(x: .value("week", p.week, unit: .weekOfYear), y: .value("%", p.rate * 100))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 120)
            }
        }
    }

    // G3
    @ViewBuilder private var eskivSection: some SwiftUI.View {
        let details = ProgressStats.eskivs(sessions, now: Date(), eskivIds: Set(ExerciseCatalog.eskivIds))
        if !details.isEmpty {
            Section("progress.eskivs") {
                ForEach(details, id: \.exerciseId) { d in
                    let pack = ExerciseCatalog.pack(d.exerciseId)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pack.map { Lang.text($0.pack.name) } ?? d.exerciseId).font(.headline)
                        Text("progress.clean \(Int((d.cleanRate * 100).rounded())) \(d.attempts)").font(.callout)
                        ForEach(d.topFaults, id: \.id) { f in
                            let name = pack?.pack.faults.first { $0.id == f.id }.map { Lang.text($0.name) } ?? f.id
                            Text("progress.fault \(name) \(f.count)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// G2 delete (the Apple Health question joins with T6.2, specs/08).
    private func delete(_ s: StoredSession) {
        for b in s.blocks {
            for set in b.sets {
                for a in set.attempts { context.delete(a) }
                for t in set.trials { context.delete(t) }
                context.delete(set)
            }
            context.delete(b)
        }
        context.delete(s)
        try? context.save()
    }
}

/// A workout's name: ready-made by id, single moves by their template.
enum WorkoutNames {
    private static let workouts = ExerciseCatalog.workouts(ExerciseCatalog.load())

    static func name(_ id: String) -> String {
        if id.hasPrefix("single_"), let p = ExerciseCatalog.pack(String(id.dropFirst(7))) { return Lang.text(p.pack.name) }
        if let w = workouts.first(where: { $0.id == id }) { return Lang.text(w.name) }
        return id
    }
}

struct SessionRow: SwiftUI.View {
    let session: StoredSession
    var body: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WorkoutNames.name(session.workoutId)).font(.headline)
            HStack {
                Text(session.startedAt, style: .date)
                Text("progress.minutes \(max(1, session.activeMs / 60_000))")
                if session.status == "aborted" { Text("progress.aborted") }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }
}

/// G2 detail: blocks, sets, attempts and trials with their faults.
struct SessionDetail: SwiftUI.View {
    let session: StoredSession

    var body: some SwiftUI.View {
        List {
            ForEach(session.blocks.sorted { $0.position < $1.position }, id: \.id) { b in
                Section(b.exerciseId.flatMap { ExerciseCatalog.pack($0).map { Lang.text($0.pack.name) } } ?? String(localized: LocalizedStringResource(stringLiteral: "progress.kind.\(b.kind)"))) {
                    ForEach(b.sets.sorted { $0.setIndex < $1.setIndex }, id: \.id) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            if s.trials.isEmpty {
                                Text("training.summary \(s.validReps) \(s.faultyReps)").font(.callout)
                                ForEach(s.attempts.sorted { $0.index < $1.index }.filter { !$0.faults.isEmpty }, id: \.id) { a in
                                    Text("progress.attempt.faults \(a.index + 1) \(a.faults.joined(separator: ", "))").font(.caption)
                                }
                            } else {
                                let hits = s.trials.filter { ProgressStats.hits.contains($0.result) }.count
                                Text("reflex.summary.hits \(hits) \(s.trials.count)").font(.callout)
                                if let m = ProgressStats.median(s.trials.compactMap { $0.reactionMs.map(Double.init) }) {
                                    Text("reflex.rt \(Int(m))").font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(WorkoutNames.name(session.workoutId)))
    }
}
