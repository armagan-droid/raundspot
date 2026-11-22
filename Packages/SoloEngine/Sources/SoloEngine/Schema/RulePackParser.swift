/// Validates a rule pack JSON document against the schema (source
/// `RulePackSchema`, plus specs/04 additions). Expressions are only
/// shape-checked here; `RulePackLoader` parses them.
public enum RulePackParser {
    public static func parse(_ json: JSONValue) -> Result<RulePack, RulePackIssues> {
        var r = SchemaReader()
        guard let pack = readPack(json, &r), r.issues.isEmpty else {
            return .failure(RulePackIssues(issues: r.issues))
        }
        crossFieldChecks(pack, &r)
        return r.issues.isEmpty ? .success(pack) : .failure(RulePackIssues(issues: r.issues))
    }

    static let topLevelKeys = [
        "id", "version", "status", "name", "howTo", "derivedFrom", "type", "camera", "metrics", "rep",
        "readyPose", "faults", "smoothing", "overlay",
    ]

    private static func readPack(_ json: JSONValue, _ r: inout SchemaReader) -> RulePack? {
        guard let o = r.object(json, [], keys: topLevelKeys) else { return nil }
        let id = r.identifier(o["id"], ["id"])
        let version = r.int(o["version"], ["version"], min: 1)
        let status = r.enumValue(o["status"], ["status"], RulePackStatus.self, options: ["draft", "calibrated"])
        let name = r.localizedText(o["name"], ["name"])
        let howTo = o["howTo"] == nil ? .some(nil) : r.localizedText(o["howTo"], ["howTo"]).map { Optional($0) }
        let derivedFrom = o["derivedFrom"] == nil ? .some(nil) : readDerivedFrom(o["derivedFrom"], &r).map { Optional($0) }
        let type = r.enumValue(o["type"], ["type"], RulePackType.self, options: ["reps", "hold"])
        let camera = readCamera(o["camera"], &r)
        let metrics = readMetrics(o["metrics"], &r)
        let rep = readRep(o["rep"], &r)
        let readyPose = readReadyPose(o["readyPose"], &r)
        let faults = r.array(o["faults"], ["faults"]).flatMap { r.elements($0, ["faults"], readFault) }
        let smoothing = readSmoothing(o["smoothing"], &r)
        let overlay = o["overlay"] == nil ? .some(nil) : readOverlay(o["overlay"], &r).map { Optional($0) }

        guard let id, let version, let status, let name, let howTo, let derivedFrom, let type, let camera,
              let metrics, let rep, let readyPose, let faults, let smoothing, let overlay
        else { return nil }
        return RulePack(
            id: id, version: version, status: status, name: name, howTo: howTo, derivedFrom: derivedFrom,
            type: type, camera: camera, metrics: metrics, rep: rep, readyPose: readyPose, faults: faults,
            smoothing: smoothing, overlay: overlay)
    }

    private static func readDerivedFrom(_ v: JSONValue?, _ r: inout SchemaReader) -> DerivedFrom? {
        let p = ["derivedFrom"]
        guard let o = r.object(v, p, keys: ["id", "version", "commit"]) else { return nil }
        let id = r.identifier(o["id"], p + ["id"])
        let version = r.int(o["version"], p + ["version"], min: 1)
        let commit = r.nonEmptyString(o["commit"], p + ["commit"])
        guard let id, let version, let commit else { return nil }
        return DerivedFrom(id: id, version: version, commit: commit)
    }

    private static func readViews(_ v: JSONValue?, _ path: [String], _ r: inout SchemaReader) -> [CameraView]? {
        guard let a = r.array(v, path, minCount: 1) else { return nil }
        return r.elements(a, path) { r, e, p in
            r.enumValue(e, p, CameraView.self, options: ["front", "side"])
        }
    }

    private static func readCamera(_ v: JSONValue?, _ r: inout SchemaReader) -> Camera? {
        let p = ["camera"]
        guard let o = r.object(v, p, keys: ["views", "minVisibleLandmarks", "minVisibility", "posture", "setupHint"])
        else { return nil }
        var views = readViews(o["views"], p + ["views"], &r)
        if let v = views, Set(v).count != v.count {
            r.add(p + ["views"], "views must be unique")
            views = nil
        }
        let landmarks = r.array(o["minVisibleLandmarks"], p + ["minVisibleLandmarks"], minCount: 1)
            .flatMap { r.elements($0, p + ["minVisibleLandmarks"]) { r, e, path in r.landmarkRef(e, path) } }
        let minVisibility = o["minVisibility"] == nil
            ? RulePackDefaults.minVisibility
            : r.number(o["minVisibility"], p + ["minVisibility"], where: { $0 >= 0 && $0 <= 1 }, "must be between 0 and 1")
        let posture = o["posture"] == nil
            ? Posture.standing
            : r.enumValue(o["posture"], p + ["posture"], Posture.self, options: ["standing", "horizontal"])
        let setupHint = r.localizedText(o["setupHint"], p + ["setupHint"])
        guard let views, let landmarks, let minVisibility, let posture, let setupHint else { return nil }
        return Camera(views: views, minVisibleLandmarks: landmarks, minVisibility: minVisibility,
                      posture: posture, setupHint: setupHint)
    }

    private static func readMetrics(_ v: JSONValue?, _ r: inout SchemaReader) -> [Metric]? {
        guard let o = v?.objectValue else {
            r.add(["metrics"], "Invalid input: expected record, received \(v?.typeName ?? "undefined")")
            return nil
        }
        var out: [Metric] = []
        var ok = true
        for (name, value) in o.entries {
            let path = ["metrics", name]
            guard SchemaReader.isIdentifier(name) else {
                r.add(path, "must be snake_case starting with a letter")
                ok = false
                continue
            }
            if let def = readMetricDefinition(value, path, &r) {
                out.append(Metric(name: name, definition: def))
            } else {
                ok = false
            }
        }
        return ok ? out : nil
    }

    /// Exactly one function from the closed list, with the right arguments.
    private static func readMetricDefinition(_ v: JSONValue, _ path: [String], _ r: inout SchemaReader) -> MetricDefinition? {
        let names = MetricDefinition.functions.map(\.name)
        guard let o = v.objectValue, o.count == 1, let fn = o.keys.first,
              let spec = MetricDefinition.functions.first(where: { $0.name == fn })
        else {
            r.add(path, "Invalid input: expected exactly one of \(names.joined(separator: ", "))")
            return nil
        }
        let argPath = path + [fn]
        switch spec.arguments {
        case .metrics(let count):
            guard let a = r.array(o[fn], argPath, minCount: count, maxCount: count),
                  let m = r.elements(a, argPath, { r, e, p in r.identifier(e, p) })
            else { return nil }
            switch fn {
            case "avg": return .avg(m[0], m[1])
            case "absDiff": return .absDiff(m[0], m[1])
            case "max": return .max(m[0], m[1])
            default: return .min(m[0], m[1])
            }
        case .landmarks(let count):
            guard let a = r.array(o[fn], argPath, minCount: count, maxCount: count),
                  let l = r.elements(a, argPath, { r, e, p in r.landmarkRef(e, p) })
            else { return nil }
            switch fn {
            case "angle": return .angle(l[0], l[1], l[2])
            case "diffY": return .diffY(l[0], l[1])
            case "angleFromVertical": return .angleFromVertical(l[0], l[1])
            case "kneeInwardRatio": return .kneeInwardRatio(l[0], l[1], l[2])
            case "signedOffset": return .signedOffset(l[0], l[1], l[2])
            case "lateralLean": return .lateralLean(l[0], l[1])
            case "angle2d": return .angle2d(l[0], l[1], l[2])
            case "lateralLean2d": return .lateralLean2d(l[0], l[1])
            case "sagittalLean": return .sagittalLean(l[0], l[1])
            case "heightOverShoulders2d": return .heightOverShoulders2d(l[0], l[1])
            default: return .sagittalLean2d(l[0], l[1])
            }
        case .landmarkChain(let lo, let hi):
            guard let a = r.array(o[fn], argPath, minCount: lo, maxCount: hi),
                  let l = r.elements(a, argPath, { r, e, p in r.landmarkRef(e, p) })
            else { return nil }
            return fn == "chainHeight" ? .chainHeight(l) : .chainHeight2d(l)
        }
    }

    private static func readZone(_ v: JSONValue?, _ path: [String], _ r: inout SchemaReader) -> RepZone? {
        guard let o = r.object(v, path, keys: ["enter", "exit"]) else { return nil }
        let enter = r.number(o["enter"], path + ["enter"])
        let exit = r.number(o["exit"], path + ["exit"])
        guard let enter, let exit else { return nil }
        return RepZone(enter: enter, exit: exit)
    }

    private static func readRep(_ v: JSONValue?, _ r: inout SchemaReader) -> RepDefinition? {
        let p = ["rep"]
        guard let o = r.object(v, p, keys: ["metric", "start", "target", "attemptMinExcursion", "minDurationMs", "maxDurationMs"])
        else { return nil }
        let metric = r.identifier(o["metric"], p + ["metric"])
        let start = readZone(o["start"], p + ["start"], &r)
        let target = readZone(o["target"], p + ["target"], &r)
        let excursion = r.number(o["attemptMinExcursion"], p + ["attemptMinExcursion"], where: { $0 > 0 }, "must be positive")
        let minDuration = r.int(o["minDurationMs"], p + ["minDurationMs"], min: 1)
        let maxDuration = r.int(o["maxDurationMs"], p + ["maxDurationMs"], min: 1)
        guard let metric, let start, let target, let excursion, let minDuration, let maxDuration else { return nil }
        return RepDefinition(metric: metric, start: start, target: target, attemptMinExcursion: excursion,
                             minDurationMs: minDuration, maxDurationMs: maxDuration)
    }

    private static func readReadyPose(_ v: JSONValue?, _ r: inout SchemaReader) -> String? {
        guard let s = r.string(v, ["readyPose"]) else { return nil }
        guard JSRegex.matchesReadyPose(s) else {
            r.add(["readyPose"], "must be '<expression> for <n>ms'")
            return nil
        }
        return s
    }

    private static func readFault(_ r: inout SchemaReader, _ v: JSONValue, _ p: [String]) -> Fault? {
        guard let o = r.object(v, p, keys: [
            "id", "name", "severity", "check", "views", "cue", "affectsValidity", "cooldownMs",
            "minConsecutiveReps", "holdMs",
        ]) else { return nil }
        let id = r.identifier(o["id"], p + ["id"])
        let name = r.localizedText(o["name"], p + ["name"])
        let severity = r.enumValue(o["severity"], p + ["severity"], Severity.self, options: ["minor", "major"])
        var check = r.string(o["check"], p + ["check"])
        if let c = check, !JSRegex.matchesCheck(c) {
            let names = CheckPosition.allCases.map(\.rawValue).joined(separator: ", ")
            r.add(p + ["check"], "must start with one of \(names) followed by ':'")
            check = nil
        }
        let views = o["views"] == nil ? .some(nil) : readViews(o["views"], p + ["views"], &r).map { Optional($0) }
        let cue = r.localizedText(o["cue"], p + ["cue"])
        let affectsValidity = r.bool(o["affectsValidity"], p + ["affectsValidity"])
        let cooldown = o["cooldownMs"] == nil ? RulePackDefaults.cooldownMs : r.int(o["cooldownMs"], p + ["cooldownMs"], min: 0)
        let consecutive = o["minConsecutiveReps"] == nil
            ? RulePackDefaults.minConsecutiveReps
            : r.int(o["minConsecutiveReps"], p + ["minConsecutiveReps"], min: 1)
        let hold = o["holdMs"] == nil ? .some(nil) : r.int(o["holdMs"], p + ["holdMs"], min: 1).map { Optional($0) }
        guard let id, let name, let severity, let check, let views, let cue, let affectsValidity, let cooldown,
              let consecutive, var hold
        else { return nil }

        let isDuringRep = check.hasPrefix(CheckPosition.duringRep.rawValue + ":")
        if hold != nil, !isDuringRep {
            r.add(p + ["holdMs"], "holdMs is only allowed on during_rep checks")
            return nil
        }
        if hold == nil, isDuringRep { hold = RulePackDefaults.holdMs }
        return Fault(id: id, name: name, severity: severity, check: check, views: views, cue: cue,
                     affectsValidity: affectsValidity, cooldownMs: cooldown, minConsecutiveReps: consecutive,
                     holdMs: hold)
    }

    private static func readSmoothing(_ v: JSONValue?, _ r: inout SchemaReader) -> Smoothing? {
        let p = ["smoothing"]
        guard let o = r.object(v, p, keys: ["method", "minCutoff", "beta"]) else { return nil }
        var method = r.string(o["method"], p + ["method"])
        if let m = method, m != "one_euro" {
            r.add(p + ["method"], "Invalid input: expected \"one_euro\"")
            method = nil
        }
        let minCutoff = r.number(o["minCutoff"], p + ["minCutoff"], where: { $0 > 0 }, "must be positive")
        let beta = r.number(o["beta"], p + ["beta"], where: { $0 >= 0 }, "must be non-negative")
        guard let method, let minCutoff, let beta else { return nil }
        return Smoothing(method: method, minCutoff: minCutoff, beta: beta)
    }

    private static func readOverlay(_ v: JSONValue?, _ r: inout SchemaReader) -> Overlay? {
        let p = ["overlay"]
        guard let o = r.object(v, p, keys: ["headTarget"]) else { return nil }
        guard o["headTarget"] != nil else { return Overlay(headTarget: nil) }
        let hp = p + ["headTarget"]
        guard let h = r.object(o["headTarget"], hp, keys: ["lateral", "height", "back", "sides"]) else { return nil }
        func positive(_ key: String, _ r: inout SchemaReader) -> Double?? {
            h[key] == nil ? .some(nil) : r.number(h[key], hp + [key], where: { $0 > 0 }, "must be positive").map { Optional($0) }
        }
        let lateral = positive("lateral", &r)
        let height = positive("height", &r)
        let back = positive("back", &r)
        var sides: [PersonSide]?? = .some(nil)
        if h["sides"] != nil {
            sides = r.array(h["sides"], hp + ["sides"], minCount: 1)
                .flatMap { r.elements($0, hp + ["sides"]) { r, e, path in
                    r.enumValue(e, path, PersonSide.self, options: ["left", "right"])
                } }
                .map { Optional($0) }
            if case .some(.some(let s)) = sides, Set(s).count != s.count {
                r.add(hp + ["sides"], "duplicate side")
                sides = nil
            }
        }
        guard let lateral, let height, let back, let sides else { return nil }
        if lateral == nil, height == nil, back == nil {
            r.add(hp, "headTarget needs lateral, height or back")
            return nil
        }
        if sides != nil, lateral == nil {
            r.add(hp, "sides need a lateral target")
            return nil
        }
        return Overlay(headTarget: HeadTarget(lateral: lateral, height: height, back: back, sides: sides))
    }

    // MARK: Cross-field rules (source superRefine)

    private static func crossFieldChecks(_ pack: RulePack, _ r: inout SchemaReader) {
        if pack.type == .hold {
            r.add(["type"], "hold rule packs are not supported in the MVP")
        }

        let names = Set(pack.metricNames)
        for metric in pack.metrics {
            if reservedExpressionWords.contains(metric.name) {
                r.add(["metrics", metric.name], "'\(metric.name)' is a reserved expression word")
            }
            for dep in metric.definition.metricDependencies where !names.contains(dep) {
                r.add(["metrics", metric.name], "references undefined metric '\(dep)'")
            }
        }
        if let cycle = findMetricCycle(pack.metrics) {
            r.add(["metrics", cycle[0]], "metric cycle: \(cycle.joined(separator: " -> "))")
        }

        let rep = pack.rep
        if !names.contains(rep.metric) {
            r.add(["rep", "metric"], "undefined metric '\(rep.metric)'")
        }
        if rep.start.enter == rep.target.enter {
            r.add(["rep"], "start.enter and target.enter must differ")
        } else {
            // s = +1 for decreasing movements (squat), -1 for increasing (press).
            let s: Double = rep.start.enter > rep.target.enter ? 1 : -1
            if !(s * rep.start.exit < s * rep.start.enter) {
                r.add(["rep", "start"], "exit must be inside the movement range relative to enter")
            }
            if !(s * rep.target.exit > s * rep.target.enter) {
                r.add(["rep", "target"], "exit must be inside the movement range relative to enter")
            }
            if !(s * rep.target.exit < s * rep.start.exit) {
                r.add(["rep"], "start and target zones overlap")
            }
        }
        if rep.minDurationMs >= rep.maxDurationMs {
            r.add(["rep"], "minDurationMs must be below maxDurationMs")
        }

        var seen = Set<String>()
        for (i, fault) in pack.faults.enumerated() {
            if seen.contains(fault.id) {
                r.add(["faults", "\(i)", "id"], "duplicate fault id '\(fault.id)'")
            }
            seen.insert(fault.id)
            let outside = (fault.views ?? []).filter { !pack.camera.views.contains($0) }
            if !outside.isEmpty {
                r.add(["faults", "\(i)", "views"], "not in camera.views: \(outside.map(\.rawValue).joined(separator: ", "))")
            }
        }
    }

    /// One dependency cycle (first name repeated at the end), or nil. Same
    /// traversal order as the source, so the reported cycle is the same.
    static func findMetricCycle(_ metrics: [Metric]) -> [String]? {
        var state: [String: Bool] = [:]  // false = visiting, true = done
        var stack: [String] = []
        let byName = Dictionary(metrics.map { ($0.name, $0.definition) }, uniquingKeysWith: { _, last in last })

        func visit(_ name: String) -> [String]? {
            if state[name] == true { return nil }
            if state[name] == false {
                return Array(stack[stack.firstIndex(of: name)!...]) + [name]
            }
            guard let def = byName[name] else { return nil }
            state[name] = false
            stack.append(name)
            for dep in def.metricDependencies {
                if let cycle = visit(dep) { return cycle }
            }
            stack.removeLast()
            state[name] = true
            return nil
        }

        for metric in metrics {
            if let cycle = visit(metric.name) { return cycle }
        }
        return nil
    }
}

/// Issues of a rule pack that failed validation or loading.
public struct RulePackIssues: Error, Sendable, Equatable, CustomStringConvertible {
    public var issues: [SchemaIssue]

    public var description: String {
        "invalid rule pack:\n" + issues.map(\.description).joined(separator: "\n")
    }
}
