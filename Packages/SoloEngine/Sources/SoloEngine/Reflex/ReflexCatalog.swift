// Reflex cue catalog (specs/05 "İşaret kataloğu ve eşleme", "Seviye kaydı ve
// doğrulama"): strikes, accepted responses and levels are data. Written for an
// orthodox user against a same-stance opponent; southpaw is derived by
// mirroring. Specific to this project; the source format has no counterpart.

public enum Stance: String, CaseIterable, Sendable, Hashable { case orthodox, southpaw }

public struct CatalogIssues: Error, Sendable, Equatable, CustomStringConvertible {
    public var issues: [SchemaIssue]
    public var description: String { "invalid reflex catalog:\n" + issues.map(\.description).joined(separator: "\n") }
}

public struct ReflexCatalog: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable { case draft, approved }

    public struct Strike: Sendable, Equatable {
        public var id: String
        public var say: [Stance: String]
        /// Orthodox template ids.
        public var accept: [String]
        public var prefer: String
    }

    public struct Feint: Sendable, Equatable {
        public var id: String
        public var say: String
    }

    public struct Level: Sendable, Equatable {
        public var level: Int
        public var strikes: [String]
        /// The random wait before a cue, ms (uniform).
        public var foreMs: ClosedRange<Double>
        public var windowMs: Int
        public var comboLen: ClosedRange<Int>
        public var comboGapMs: Int?
        public var feintRate: Double
        public var cues: Int
    }

    public struct Pair: Sendable, Equatable {
        /// `more` is more specific than `less`.
        public var more: String
        public var less: String
    }

    public var id: String
    public var version: Int
    public var status: Status
    public var responses: [String]
    public var specificity: [Pair]
    public var strikes: [Strike]
    public var feints: [Feint]
    public var levels: [Level]

    /// `_left` ↔ `_right`; other ids (duck, lean_back_front) stay (specs/05 "Southpaw aynalaması").
    public static func mirrored(_ id: String) -> String {
        if id.hasSuffix("_left") { return String(id.dropLast(5)) + "_right" }
        if id.hasSuffix("_right") { return String(id.dropLast(6)) + "_left" }
        return id
    }

    /// AC-5.8: a Release build runs only an approved catalog.
    public func isUsable(release: Bool) -> Bool { !release || status == .approved }

    public func level(_ n: Int) -> Level? { levels.first { $0.level == n } }

    /// The catalog for one stance: responses mirrored for southpaw, spoken keys chosen.
    public func resolved(for stance: Stance) -> ResolvedCatalog {
        func m(_ id: String) -> String { stance == .orthodox ? id : Self.mirrored(id) }
        let pairs: [(more: String, less: String)] = specificity.map { (more: m($0.more), less: m($0.less)) }
        let resolved: [ResolvedCatalog.Strike] = strikes.map { s in
            ResolvedCatalog.Strike(id: s.id, say: s.say[stance] ?? "", accept: s.accept.map(m), prefer: m(s.prefer))
        }
        return ResolvedCatalog(stance: stance, responses: responses.map(m), specificity: pairs, strikes: resolved,
                               feints: feints, levels: levels)
    }

    /// Checks that need the templates (specs/05, AC-5.6): every response has a template, and a
    /// level's combo gap is not shorter than the slowest `minDurationMs` among its strikes' accepted responses.
    /// - Parameter minDurationMs: by template id, for the templates that exist and support the front view.
    public func templateIssues(minDurationMs: [String: Int]) -> [SchemaIssue] {
        var out: [SchemaIssue] = []
        for (i, r) in responses.enumerated() where minDurationMs[r] == nil {
            out.append(SchemaIssue(path: "responses.\(i)", message: "no front-view template '\(r)' in exercises/"))
        }
        for (i, l) in levels.enumerated() {
            guard let gap = l.comboGapMs else { continue }
            let accepted = Set(strikes.filter { l.strikes.contains($0.id) }.flatMap(\.accept))
            let slowest = accepted.compactMap { minDurationMs[$0] }.max() ?? 0
            if gap < slowest {
                out.append(SchemaIssue(path: "levels.\(i).comboGapMs",
                                       message: "\(gap) ms is shorter than the slowest accepted response (\(slowest) ms)"))
            }
        }
        return out
    }

    public static func parse(_ json: JSONValue) -> Result<ReflexCatalog, CatalogIssues> {
        var r = SchemaReader()
        let c = read(json, &r)
        guard let c, r.issues.isEmpty else { return .failure(CatalogIssues(issues: r.issues)) }
        return .success(c)
    }

    private static func read(_ json: JSONValue, _ r: inout SchemaReader) -> ReflexCatalog? {
        guard let o = r.object(json, [], keys: ["id", "version", "status", "assumes", "responses", "specificity", "strikes", "feints", "levels"])
        else { return nil }
        let id = r.identifier(o["id"], ["id"])
        let version = r.int(o["version"], ["version"], min: 1)
        let status = r.enumValue(o["status"], ["status"], Status.self, options: ["draft", "approved"])
        if let a = r.object(o["assumes"], ["assumes"], keys: ["opponentStance"]), r.string(a["opponentStance"], ["assumes", "opponentStance"]) != "same" {
            r.add(["assumes", "opponentStance"], "must be same")
        }

        let responses = r.array(o["responses"], ["responses"], minCount: 1).flatMap { r.elements($0, ["responses"]) { r, v, p in r.identifier(v, p) } }
        if let responses, Set(responses).count != responses.count { r.add(["responses"], "must not repeat") }
        let known = Set(responses ?? [])

        let specificity = r.array(o["specificity"], ["specificity"]).flatMap {
            r.elements($0, ["specificity"]) { r, v, p -> Pair? in
                guard let pair = r.array(v, p, minCount: 2, maxCount: 2).flatMap({ r.elements($0, p) { r, v, p in r.identifier(v, p) } })
                else { return nil }
                if pair[0] == pair[1] { r.add(p, "needs two different responses") }
                for (k, x) in pair.enumerated() where !known.contains(x) { r.add(p + ["\(k)"], "'\(x)' is not in responses") }
                return Pair(more: pair[0], less: pair[1])
            }
        }

        let strikes = r.array(o["strikes"], ["strikes"], minCount: 1).flatMap {
            r.elements($0, ["strikes"]) { r, v, p -> Strike? in
                guard let s = r.object(v, p, keys: ["id", "say", "accept", "prefer"]) else { return nil }
                let sid = r.identifier(s["id"], p + ["id"])
                var say: [Stance: String] = [:]
                if let so = r.object(s["say"], p + ["say"], keys: ["orthodox", "southpaw"]) {
                    for st in Stance.allCases {
                        if let k = r.nonEmptyString(so[st.rawValue], p + ["say", st.rawValue]) { say[st] = k }
                    }
                }
                let accept = r.array(s["accept"], p + ["accept"], minCount: 1).flatMap { r.elements($0, p + ["accept"]) { r, v, p in r.identifier(v, p) } }
                for (k, x) in (accept ?? []).enumerated() where !known.contains(x) { r.add(p + ["accept", "\(k)"], "'\(x)' is not in responses") }
                let prefer = r.identifier(s["prefer"], p + ["prefer"])
                if let prefer, let accept, !accept.contains(prefer) { r.add(p + ["prefer"], "must be one of accept") }
                guard let sid, say.count == 2, let accept, let prefer else { return nil }
                return Strike(id: sid, say: say, accept: accept, prefer: prefer)
            }
        }
        let strikeIds = (strikes ?? []).map(\.id)
        if Set(strikeIds).count != strikeIds.count { r.add(["strikes"], "strike ids must not repeat") }

        let feints = r.array(o["feints"], ["feints"]).flatMap {
            r.elements($0, ["feints"]) { r, v, p -> Feint? in
                guard let f = r.object(v, p, keys: ["id", "say"]) else { return nil }
                let fid = r.identifier(f["id"], p + ["id"])
                let say = r.nonEmptyString(f["say"], p + ["say"])
                if let fid, strikeIds.contains(fid) { r.add(p + ["id"], "'\(fid)' is also a strike") }
                guard let fid, let say else { return nil }
                return Feint(id: fid, say: say)
            }
        }

        let levels = r.array(o["levels"], ["levels"], minCount: 1).flatMap {
            r.elements($0, ["levels"]) { r, v, p -> Level? in
                guard let l = r.object(v, p, keys: ["level", "strikes", "foreSec", "windowMs", "comboLen", "comboGapMs", "feintRate", "cues"])
                else { return nil }
                let n = r.int(l["level"], p + ["level"], min: 1)
                let ls = r.array(l["strikes"], p + ["strikes"], minCount: 1).flatMap { r.elements($0, p + ["strikes"]) { r, v, p in r.identifier(v, p) } }
                if let ls {
                    if Set(ls).count != ls.count { r.add(p + ["strikes"], "must not repeat") }
                    for (k, x) in ls.enumerated() where !strikeIds.contains(x) { r.add(p + ["strikes", "\(k)"], "'\(x)' is not a strike") }
                }
                let fore = r.array(l["foreSec"], p + ["foreSec"], minCount: 2, maxCount: 2).flatMap {
                    r.elements($0, p + ["foreSec"]) { r, v, p in r.number(v, p, where: { $0 > 0 && $0.isFinite }, "must be positive") }
                }
                if let fore, fore[0] > fore[1] { r.add(p + ["foreSec"], "minimum must not exceed maximum") }
                let window = r.int(l["windowMs"], p + ["windowMs"], min: 1)
                let combo = r.array(l["comboLen"], p + ["comboLen"], minCount: 2, maxCount: 2).flatMap {
                    r.elements($0, p + ["comboLen"]) { r, v, p in r.int(v, p, min: 1) }
                }
                if let combo, combo[0] > combo[1] { r.add(p + ["comboLen"], "minimum must not exceed maximum") }
                let gap = l["comboGapMs"] == nil ? nil : r.int(l["comboGapMs"], p + ["comboGapMs"], min: 1)
                if let combo, combo.count == 2 {
                    if combo[1] > 1, l["comboGapMs"] == nil { r.add(p + ["comboGapMs"], "required when combos are longer than 1") }
                    if combo[1] == 1, l["comboGapMs"] != nil { r.add(p + ["comboGapMs"], "only for combos longer than 1") }
                }
                let rate = r.number(l["feintRate"], p + ["feintRate"], where: { $0 >= 0 && $0 < 1 }, "must be in [0, 1)")
                let cues = r.int(l["cues"], p + ["cues"], min: 1)
                guard let n, let ls, let fore, fore.count == 2, fore[0] <= fore[1], let window, let combo, combo.count == 2,
                      combo[0] <= combo[1], let rate, let cues else { return nil }
                return Level(level: n, strikes: ls, foreMs: fore[0] * 1000...fore[1] * 1000, windowMs: window,
                             comboLen: combo[0]...combo[1], comboGapMs: gap, feintRate: rate, cues: cues)
            }
        }
        if let levels {
            if levels.map(\.level) != Array(1...max(1, levels.count)) { r.add(["levels"], "levels must be 1, 2, … in order") }
            if levels.contains(where: { $0.feintRate > 0 }), (feints ?? []).isEmpty { r.add(["feints"], "a level with feints needs a feint") }
        }

        guard let id, let version, let status, let responses, let specificity, let strikes, let feints, let levels else { return nil }
        return ReflexCatalog(id: id, version: version, status: status, responses: responses, specificity: specificity,
                             strikes: strikes, feints: feints, levels: levels)
    }
}

/// A catalog for one stance (specs/05): what the reflex loop runs on.
public struct ResolvedCatalog: Sendable, Equatable {
    public struct Strike: Sendable, Equatable {
        public var id: String
        /// String Catalog key of the spoken cue.
        public var say: String
        public var accept: [String]
        public var prefer: String
    }

    public var stance: Stance
    public var responses: [String]
    public var specificity: [(more: String, less: String)]
    public var strikes: [Strike]
    public var feints: [ReflexCatalog.Feint]
    public var levels: [ReflexCatalog.Level]

    public static func == (a: Self, b: Self) -> Bool {
        a.stance == b.stance && a.responses == b.responses && a.strikes == b.strikes && a.feints == b.feints && a.levels == b.levels
            && a.specificity.map(\.more) == b.specificity.map(\.more) && a.specificity.map(\.less) == b.specificity.map(\.less)
    }

    /// `a` is more specific than `b` (specs/05 "Sınıflandırma" step 4).
    public func isMoreSpecific(_ a: String, than b: String) -> Bool {
        specificity.contains { $0.more == a && $0.less == b }
    }
}
