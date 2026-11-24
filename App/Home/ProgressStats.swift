import Foundation

/// İlerleme figures (specs/12 G1–G3), computed from the stored records; nothing derived is stored (specs/11).
enum ProgressStats {
    struct Week: Equatable {
        var start: Date
        var workouts: Int
        /// Reflex trials with a reaction time: median, by level.
        var medianRtByLevel: [Int: Double]
        /// Reflex hits / trials (nil without trials).
        var hitRate: Double?
    }

    struct EskivDetail: Equatable {
        var exerciseId: String
        var attempts: Int
        /// Valid with no fault / attempts.
        var cleanRate: Double
        /// Most frequent first, at most three.
        var topFaults: [(id: String, count: Int)]

        static func == (a: Self, b: Self) -> Bool {
            a.exerciseId == b.exerciseId && a.attempts == b.attempts && a.cleanRate == b.cleanRate
                && a.topFaults.map(\.id) == b.topFaults.map(\.id) && a.topFaults.map(\.count) == b.topFaults.map(\.count)
        }
    }

    static let hits: Set<String> = ["correct", "correct_faulty", "feint_ok"]

    /// G1: the last `weeks` weeks (Monday start), oldest first; finished workouts only.
    static func weeks(_ sessions: [StoredSession], now: Date, weeks: Int = 8, calendar: Calendar = .iso) -> [Week] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        return (0..<weeks).reversed().map { back in
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek)!
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            let inWeek = sessions.filter { $0.status == "done" && $0.startedAt >= start && $0.startedAt < end }
            var rts: [Int: [Double]] = [:]
            var trials = 0, hit = 0
            for s in inWeek {
                for b in s.blocks where b.kind == "reflex" {
                    for set in b.sets {
                        for t in set.trials {
                            trials += 1
                            if hits.contains(t.result) { hit += 1 }
                            if let rt = t.reactionMs, let level = b.level { rts[level, default: []].append(Double(rt)) }
                        }
                    }
                }
            }
            return Week(start: start, workouts: inWeek.count, medianRtByLevel: rts.compactMapValues(median),
                        hitRate: trials == 0 ? nil : Double(hit) / Double(trials))
        }
    }

    /// G3: per eskiv template over the last `days` days.
    static func eskivs(_ sessions: [StoredSession], now: Date, days: Int = 30, eskivIds: Set<String>) -> [EskivDetail] {
        let from = now.addingTimeInterval(-Double(days) * 86_400)
        var attempts: [String: [StoredAttempt]] = [:]
        for s in sessions where s.startedAt >= from {
            for b in s.blocks {
                guard let ex = b.exerciseId, eskivIds.contains(ex) else { continue }
                for set in b.sets { attempts[ex, default: []] += set.attempts }
            }
        }
        return attempts.keys.sorted().map { ex in
            let a = attempts[ex]!
            var counts: [String: Int] = [:]
            for f in a.flatMap(\.faults) { counts[f, default: 0] += 1 }
            let top = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map { (id: $0.key, count: $0.value) }
            let clean = a.filter { $0.outcome == "valid" && $0.faults.isEmpty }.count
            return EskivDetail(exerciseId: ex, attempts: a.count, cleanRate: a.isEmpty ? 0 : Double(clean) / Double(a.count), topFaults: top)
        }
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

extension Calendar {
    /// ISO weeks (Monday first), Gregorian.
    static var iso: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }
}
