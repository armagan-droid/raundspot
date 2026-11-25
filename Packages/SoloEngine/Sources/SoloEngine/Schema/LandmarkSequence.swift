import Foundation

/// One landmark (ref 02 `Frame`). A missing joint (`null` in v2 `vision19`
/// sequences, specs/03) is visibility 0 with NaN coordinates.
public struct Landmark: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var visibility: Double

    public init(x: Double, y: Double, z: Double, visibility: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility
    }

    public static let missing = Landmark(x: .nan, y: .nan, z: .nan, visibility: 0)

    public var isMissing: Bool { x.isNaN && y.isNaN && z.isNaN && visibility == 0 }

    /// NaN-aware equality: missing equals missing (specs/03 "Eşitlik kuralları").
    public static func == (lhs: Landmark, rhs: Landmark) -> Bool {
        func same(_ a: Double, _ b: Double) -> Bool { a == b || (a.isNaN && b.isNaN) }
        return same(lhs.x, rhs.x) && same(lhs.y, rhs.y) && same(lhs.z, rhs.z) && same(lhs.visibility, rhs.visibility)
    }
}

/// One processed camera frame (ref 02). In memory only; never leaves the
/// device. Arrays hold 33 landmarks in MediaPipe order.
public struct Frame: Sendable, Equatable {
    /// Frame time in ms (presentation timestamp, specs/02 "Saat tabanı").
    public var t: Double
    /// Normalized [0, 1] image coordinates, origin top-left.
    public var image: [Landmark]
    /// Meters, hip-centered (ref 04 axes). All NaN when 3D is unavailable.
    public var world: [Landmark]
    /// Image width / height, upright (specs/03). The specs/04 2D functions
    /// scale x by it; 1 for the source's square synthetic images.
    public var imageAspect: Double

    public init(t: Double, image: [Landmark], world: [Landmark], imageAspect: Double = 1) {
        self.t = t
        self.image = image
        self.world = world
        self.imageAspect = imageAspect
    }

    public subscript(image name: LandmarkName) -> Landmark { image[name.index] }
    public subscript(world name: LandmarkName) -> Landmark { world[name.index] }
}

public enum RepOutcome: String, CaseIterable, Sendable, Equatable {
    case valid, faulty, incomplete
}

public struct RepLabel: Sendable, Equatable {
    public var outcome: RepOutcome
    public var faults: [String]

    public init(outcome: RepOutcome, faults: [String]) {
        self.outcome = outcome
        self.faults = faults
    }
}

/// Landmark sequence used by fixtures and recordings (ref 04 "fixture
/// formatı", extended by specs/03: `formatVersion` 2 with `skeleton`).
public struct LandmarkSequence: Sendable, Equatable {
    public enum Source: String, Sendable, Equatable { case synthetic, calibration, team }

    public var formatVersion: Int
    /// `mediapipe33` for every v1 file.
    public var skeleton: Skeleton
    public var exerciseId: String
    public var source: Source
    public var view: CameraView
    public var fps: Double
    public var labels: [RepLabel]?
    public var frames: [Frame]
    /// False when a v2 sequence stores `world: null` (no 3D data).
    public var hasWorld: Bool
    /// Required in v2, 1 in v1; copied into every frame.
    public var imageAspect: Double
    /// Recording export metadata (specs/03, specs/09; v2 `team` only).
    public var meta: ExportMeta?
    /// A reflex recording's cue and trial lines (specs/03 `reflex`, T5.2; v2 `team` only).
    public var reflex: ReflexLines?

    public init(formatVersion: Int, skeleton: Skeleton, exerciseId: String, source: Source, view: CameraView,
                fps: Double, labels: [RepLabel]?, frames: [Frame], hasWorld: Bool, imageAspect: Double = 1) {
        self.formatVersion = formatVersion
        self.skeleton = skeleton
        self.exerciseId = exerciseId
        self.source = source
        self.view = view
        self.fps = fps
        self.labels = labels
        self.frames = frames
        self.hasWorld = hasWorld
        self.imageAspect = imageAspect
    }

    public static func parse(_ json: JSONValue) -> Result<LandmarkSequence, SequenceIssues> {
        var r = SchemaReader()
        let seq = read(json, &r)
        guard let seq, r.issues.isEmpty else { return .failure(SequenceIssues(issues: r.issues)) }
        return .success(seq)
    }

    public static func parse(data: Data) -> Result<LandmarkSequence, SequenceIssues> {
        do {
            return parse(try JSONValue.parse(data))
        } catch {
            return .failure(SequenceIssues(issues: [SchemaIssue(path: "", message: error.description)]))
        }
    }

    private static func read(_ json: JSONValue, _ r: inout SchemaReader) -> LandmarkSequence? {
        let common = ["formatVersion", "exerciseId", "source", "view", "fps", "labels", "frames"]
        let v2Keys = ["skeleton", "imageAspect", "meta", "reflex"]
        // The version decides the allowed keys, so read it first.
        let version = json["formatVersion"]?.numberValue
        guard version == 1 || version == 2 else {
            r.add(["formatVersion"], "Invalid input: expected 1 or 2")
            return nil
        }
        let v2 = version == 2
        guard let o = r.object(json, [], keys: v2 ? common + v2Keys : common) else { return nil }

        var skeleton: Skeleton? = .mediapipe33
        if v2 {
            skeleton = o["skeleton"] == nil
                ? { r.add(["skeleton"], "skeleton is required in formatVersion 2"); return nil }()
                : r.enumValue(o["skeleton"], ["skeleton"], Skeleton.self, options: ["mediapipe33", "vision19"])
        }
        var imageAspect: Double? = 1
        if v2 {
            imageAspect = o["imageAspect"] == nil
                ? { r.add(["imageAspect"], "imageAspect is required in formatVersion 2"); return nil }()
                : r.number(o["imageAspect"], ["imageAspect"], where: { $0 > 0 && $0.isFinite }, "must be positive")
        }
        let exerciseId = r.identifier(o["exerciseId"], ["exerciseId"])
        let source = r.enumValue(o["source"], ["source"], Source.self, options: ["synthetic", "calibration", "team"])
        let view = r.enumValue(o["view"], ["view"], CameraView.self, options: ["front", "side"])
        let fps = r.number(o["fps"], ["fps"], where: { $0 > 0 }, "must be positive")
        let labels = o["labels"] == nil ? .some(nil) : readLabels(o["labels"], &r).map { Optional($0) }

        guard let skeleton, let imageAspect else { return nil }
        var hasWorld = true
        let frames: [Frame]? = r.array(o["frames"], ["frames"], minCount: 1).flatMap { values in
            r.elements(values, ["frames"]) { r, value, path in
                readFrame(value, path, skeleton: skeleton, v2: v2, imageAspect: imageAspect, hasWorld: &hasWorld, &r)
            }
        }
        if let frames {
            for i in frames.indices.dropFirst() where !(frames[i].t > frames[i - 1].t) {
                r.add(["frames"], "frame timestamps must be strictly increasing")
                break
            }
        }
        var meta: ExportMeta?
        if let m = o["meta"] {
            if source != .team { r.add(["meta"], "only team recordings carry meta") }
            meta = ExportMeta.read(m, &r)
        }
        var reflex: ReflexLines?
        if let x = o["reflex"] {
            if source != .team { r.add(["reflex"], "only team recordings carry reflex lines") }
            reflex = ReflexLines.read(x, &r)
        }
        guard let exerciseId, let source, let view, let fps, let labels, let frames else { return nil }
        var seq = LandmarkSequence(
            formatVersion: v2 ? 2 : 1, skeleton: skeleton, exerciseId: exerciseId, source: source, view: view,
            fps: fps, labels: labels, frames: frames, hasWorld: hasWorld, imageAspect: imageAspect)
        seq.meta = meta
        seq.reflex = reflex
        return seq
    }

    private static func readLabels(_ v: JSONValue?, _ r: inout SchemaReader) -> [RepLabel]? {
        guard let o = r.object(v, ["labels"], keys: ["reps"]) else { return nil }
        guard let reps = r.array(o["reps"], ["labels", "reps"]) else { return nil }
        return r.elements(reps, ["labels", "reps"]) { r, value, path in
            guard let l = r.object(value, path, keys: ["outcome", "faults"]) else { return nil }
            let outcome = r.enumValue(l["outcome"], path + ["outcome"], RepOutcome.self,
                                      options: RepOutcome.allCases.map(\.rawValue))
            let faults = r.array(l["faults"], path + ["faults"])
                .flatMap { r.elements($0, path + ["faults"]) { r, e, p in r.identifier(e, p) } }
            guard let outcome, let faults else { return nil }
            return RepLabel(outcome: outcome, faults: faults)
        }
    }

    /// `world: null` (v2 only) means no 3D data; it must then be null in every frame.
    private static func readFrame(
        _ v: JSONValue, _ path: [String], skeleton: Skeleton, v2: Bool, imageAspect: Double, hasWorld: inout Bool,
        _ r: inout SchemaReader
    ) -> Frame? {
        guard let o = r.object(v, path, keys: ["t", "image", "world"]) else { return nil }
        let t = r.number(o["t"], path + ["t"], where: { $0 >= 0 }, "must be non-negative")
        let image = readLandmarks(o["image"], path + ["image"], skeleton: skeleton, &r)
        var world: [Landmark]?
        if v2, o["world"] == .null {
            if path.last == "0" { hasWorld = false }
            if hasWorld {
                r.add(path + ["world"], "world must be null in every frame or in none")
                return nil
            }
            world = Array(repeating: .missing, count: LandmarkName.count)
        } else {
            if !hasWorld {
                r.add(path + ["world"], "world must be null in every frame or in none")
                return nil
            }
            world = readLandmarks(o["world"], path + ["world"], skeleton: skeleton, &r)
        }
        guard let t, let image, let world else { return nil }
        return Frame(t: t, image: image, world: world, imageAspect: imageAspect)
    }

    private static func readLandmarks(_ v: JSONValue?, _ path: [String], skeleton: Skeleton, _ r: inout SchemaReader) -> [Landmark]? {
        guard let a = r.array(v, path, minCount: LandmarkName.count, maxCount: LandmarkName.count) else { return nil }
        let present = skeleton.landmarks
        var out: [Landmark] = []
        var ok = true
        for (i, value) in a.enumerated() {
            let name = LandmarkName.allCases[i]
            let p = path + ["\(i)"]
            if value == .null {
                if present.contains(name) {
                    r.add(p, "\(name.rawValue) is in skeleton \(skeleton.rawValue) and cannot be null")
                    ok = false
                }
                out.append(.missing)
                continue
            }
            if !present.contains(name) {
                r.add(p, "\(name.rawValue) is not in skeleton \(skeleton.rawValue) and must be null")
                ok = false
                continue
            }
            guard let l = r.object(value, p, keys: ["x", "y", "z", "visibility"]) else { ok = false; continue }
            let x = r.number(l["x"], p + ["x"])
            let y = r.number(l["y"], p + ["y"])
            let z = r.number(l["z"], p + ["z"])
            let vis = r.number(l["visibility"], p + ["visibility"], where: { $0 >= 0 && $0 <= 1 }, "must be between 0 and 1")
            guard let x, let y, let z, let vis else { ok = false; continue }
            out.append(Landmark(x: x, y: y, z: z, visibility: vis))
        }
        return ok ? out : nil
    }
}

public struct SequenceIssues: Error, Sendable, Equatable, CustomStringConvertible {
    public var issues: [SchemaIssue]

    public var description: String {
        "invalid landmark sequence:\n" + issues.map(\.description).joined(separator: "\n")
    }
}

/// `meta` of an exported recording (specs/03, specs/09): no name and no free text.
public struct ExportMeta: Sendable, Equatable {
    public struct Template: Sendable, Equatable {
        public var id: String
        public var version: Int
        public init(id: String, version: Int) { self.id = id; self.version = version }
    }

    public var recordingId: String
    public var participant: String
    public var consentVersion: Int
    public var device: String
    public var osVersion: String
    public var appVersion: String
    public var templates: [Template]

    public init(recordingId: String, participant: String, consentVersion: Int, device: String, osVersion: String, appVersion: String,
                templates: [Template]) {
        self.recordingId = recordingId
        self.participant = participant
        self.consentVersion = consentVersion
        self.device = device
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.templates = templates
    }

    static func read(_ v: JSONValue, _ r: inout SchemaReader) -> ExportMeta? {
        let p = ["meta"]
        guard let o = r.object(v, p, keys: ["recordingId", "participant", "consentVersion", "device", "osVersion", "appVersion", "templates"])
        else { return nil }
        let id = r.nonEmptyString(o["recordingId"], p + ["recordingId"])
        if let id, UUID(uuidString: id) == nil { r.add(p + ["recordingId"], "must be a UUID") }
        let participant = r.nonEmptyString(o["participant"], p + ["participant"])
        if let participant, participant.range(of: #"^P[0-9]{2,}$"#, options: .regularExpression) == nil {
            r.add(p + ["participant"], "must be a participant code (P07)")
        }
        let consent = r.int(o["consentVersion"], p + ["consentVersion"], min: 1)
        let device = r.nonEmptyString(o["device"], p + ["device"])
        let os = r.nonEmptyString(o["osVersion"], p + ["osVersion"])
        let app = r.nonEmptyString(o["appVersion"], p + ["appVersion"])
        let templates = r.array(o["templates"], p + ["templates"], minCount: 1).flatMap {
            r.elements($0, p + ["templates"]) { r, v, path -> Template? in
                guard let t = r.object(v, path, keys: ["id", "version"]), let id = r.identifier(t["id"], path + ["id"]),
                      let ver = r.int(t["version"], path + ["version"], min: 1) else { return nil }
                return Template(id: id, version: ver)
            }
        }
        guard let id, let participant, let consent, let device, let os, let app, let templates else { return nil }
        return ExportMeta(recordingId: id, participant: participant, consentVersion: consent, device: device, osVersion: os,
                          appVersion: app, templates: templates)
    }

    var json: JSONValue {
        var o: JSONValue = ["recordingId": .string(recordingId), "participant": .string(participant),
                            "consentVersion": .number(Double(consentVersion)), "device": .string(device)]
        o["osVersion"] = .string(osVersion)
        o["appVersion"] = .string(appVersion)
        o["templates"] = .array(templates.map { ["id": .string($0.id), "version": .number(Double($0.version))] })
        return o
    }
}

/// `reflex` of an exported reflex recording (specs/03, specs/09): the `app.jsonl` cue and trial lines.
public struct ReflexLines: Sendable, Equatable {
    public struct Cue: Sendable, Equatable {
        public var t: Double
        public var key: String
        public var plannedAt: Double
        public init(t: Double, key: String, plannedAt: Double) { self.t = t; self.key = key; self.plannedAt = plannedAt }
    }

    public struct Trial: Sendable, Equatable {
        public var t: Double
        public var strike: String
        public var feint: Bool
        public var cueAt: Double
        public var result: ReflexResult
        public var response: String?
        public var reactionMs: Double?
        public var approximate: Bool
        /// The coach's label: nil when unlabelled, `.some(nil)` for "no response" (a feint).
        public var expected: String??

        public init(t: Double, strike: String, feint: Bool, cueAt: Double, result: ReflexResult, response: String?, reactionMs: Double?,
                    approximate: Bool, expected: String?? = nil) {
            self.t = t
            self.strike = strike
            self.feint = feint
            self.cueAt = cueAt
            self.result = result
            self.response = response
            self.reactionMs = reactionMs
            self.approximate = approximate
            self.expected = expected
        }
    }

    public var catalogId: String
    public var level: Int
    public var stance: Stance
    public var cues: [Cue]
    public var trials: [Trial]

    public init(catalogId: String, level: Int, stance: Stance, cues: [Cue], trials: [Trial]) {
        self.catalogId = catalogId
        self.level = level
        self.stance = stance
        self.cues = cues
        self.trials = trials
    }

    static func read(_ v: JSONValue, _ r: inout SchemaReader) -> ReflexLines? {
        let p = ["reflex"]
        guard let o = r.object(v, p, keys: ["catalogId", "level", "stance", "cues", "trials"]) else { return nil }
        let catalog = r.identifier(o["catalogId"], p + ["catalogId"])
        let level = r.int(o["level"], p + ["level"], min: 1)
        let stance = r.enumValue(o["stance"], p + ["stance"], Stance.self, options: ["orthodox", "southpaw"])
        let cues = r.array(o["cues"], p + ["cues"]).flatMap {
            r.elements($0, p + ["cues"]) { r, v, path -> Cue? in
                guard let c = r.object(v, path, keys: ["t", "key", "plannedAt"]), let t = r.number(c["t"], path + ["t"]),
                      let key = r.nonEmptyString(c["key"], path + ["key"]), let at = r.number(c["plannedAt"], path + ["plannedAt"]) else { return nil }
                return Cue(t: t, key: key, plannedAt: at)
            }
        }
        let trials = r.array(o["trials"], p + ["trials"]).flatMap {
            r.elements($0, p + ["trials"]) { r, v, path -> Trial? in
                guard let x = r.object(v, path, keys: ["t", "strike", "feint", "cueAt", "result", "response", "reactionMs", "approximate",
                                                     "expected"]) else { return nil }
                let t = r.number(x["t"], path + ["t"])
                let strike = r.identifier(x["strike"], path + ["strike"])
                let feint = r.bool(x["feint"], path + ["feint"])
                let cueAt = r.number(x["cueAt"], path + ["cueAt"])
                let result = r.enumValue(x["result"], path + ["result"], ReflexResult.self, options: ReflexResult.allCases.map(\.rawValue))
                let approximate = r.bool(x["approximate"], path + ["approximate"])
                func nullableId(_ key: String) -> String?? {
                    guard let v = x[key] else { r.add(path + [key], "Invalid input: expected string or null, received undefined"); return nil }
                    if v == .null { return .some(nil) }
                    return r.identifier(v, path + [key]).map { .some($0) }
                }
                let response = nullableId("response")
                var reaction: Double??
                if let rv = x["reactionMs"] {
                    reaction = rv == .null ? .some(nil) : r.number(rv, path + ["reactionMs"], where: { $0 >= 0 }, "must be non-negative").map { .some($0) }
                } else {
                    r.add(path + ["reactionMs"], "Invalid input: expected number or null, received undefined")
                }
                let expected: String?? = x["expected"] == nil ? nil : nullableId("expected")
                if x["expected"] != nil, expected == nil { return nil }
                guard let t, let strike, let feint, let cueAt, let result, let approximate, let response, let reaction else { return nil }
                return Trial(t: t, strike: strike, feint: feint, cueAt: cueAt, result: result, response: response, reactionMs: reaction,
                             approximate: approximate, expected: expected)
            }
        }
        guard let catalog, let level, let stance, let cues, let trials else { return nil }
        return ReflexLines(catalogId: catalog, level: level, stance: stance, cues: cues, trials: trials)
    }

    var json: JSONValue {
        func id(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }
        var o: JSONValue = ["catalogId": .string(catalogId), "level": .number(Double(level)), "stance": .string(stance.rawValue)]
        o["cues"] = .array(cues.map { ["t": .number($0.t), "key": .string($0.key), "plannedAt": .number($0.plannedAt)] })
        o["trials"] = .array(trials.map { x in
            var e: JSONValue = ["t": .number(x.t), "strike": .string(x.strike), "feint": .bool(x.feint), "cueAt": .number(x.cueAt)]
            e["result"] = .string(x.result.rawValue)
            e["response"] = id(x.response)
            e["reactionMs"] = x.reactionMs.map { .number($0) } ?? .null
            e["approximate"] = .bool(x.approximate)
            if let ex = x.expected { e["expected"] = id(ex) }
            return e
        })
        return o
    }
}
