// Set summary (ref 05 "Set sonu özeti", AC-5.4; source `exercise/summary.ts`).

public struct SetSummary: Sendable, Equatable {
    /// Reps counted toward the target: valid, plus faulty in lenient mode.
    public var counted: Int
    public var valid: Int
    public var faulty: Int
    public var incomplete: Int
    public var mostFrequentFault: String?
    /// Faults seen in ≥ 3 consecutive attempts, in rule pack order.
    public var frequentFaults: [String]

    public init(counted: Int, valid: Int, faulty: Int, incomplete: Int, mostFrequentFault: String?, frequentFaults: [String]) {
        self.counted = counted
        self.valid = valid
        self.faulty = faulty
        self.incomplete = incomplete
        self.mostFrequentFault = mostFrequentFault
        self.frequentFaults = frequentFaults
    }
}

public enum CountingMode: String, Sendable, Equatable {
    case strict, lenient
}

public let frequentFaultStreak = 3

public func summarizeSet(_ reps: [RepLabel], faults: [Fault], mode: CountingMode) -> SetSummary {
    func count(_ o: RepOutcome) -> Int { reps.count { $0.outcome == o } }
    let valid = count(.valid)
    let faulty = count(.faulty)

    // rank: major first, then rule pack order
    func rank(_ id: String) -> Int {
        let i = faults.firstIndex { $0.id == id }
        let major = i.map { faults[$0].severity == .major } ?? false
        return (major ? 0 : 1) * 1000 + (i ?? 999)
    }
    var totals: [(id: String, count: Int)] = []  // first-seen order, as a JS Map
    var streak: [String: Int] = [:]
    var frequent = Set<String>()
    for rep in reps {
        for id in rep.faults {
            if let i = totals.firstIndex(where: { $0.id == id }) { totals[i].count += 1 } else { totals.append((id, 1)) }
        }
        for f in faults {
            let s = rep.faults.contains(f.id) ? (streak[f.id] ?? 0) + 1 : 0
            streak[f.id] = s
            if s >= frequentFaultStreak { frequent.insert(f.id) }
        }
    }
    // stable sort, like Array.prototype.sort
    let ranked = totals.enumerated().sorted { a, b in
        if a.element.count != b.element.count { return a.element.count > b.element.count }
        let ra = rank(a.element.id), rb = rank(b.element.id)
        return ra != rb ? ra < rb : a.offset < b.offset
    }

    return SetSummary(
        counted: valid + (mode == .lenient ? faulty : 0),
        valid: valid,
        faulty: faulty,
        incomplete: count(.incomplete),
        mostFrequentFault: ranked.first?.element.id,
        frequentFaults: faults.map(\.id).filter(frequent.contains))
}
