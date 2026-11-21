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

    public init(t: Double, image: [Landmark], world: [Landmark]) {
        self.t = t
        self.image = image
        self.world = world
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

    public init(formatVersion: Int, skeleton: Skeleton, exerciseId: String, source: Source, view: CameraView,
                fps: Double, labels: [RepLabel]?, frames: [Frame], hasWorld: Bool) {
        self.formatVersion = formatVersion
        self.skeleton = skeleton
        self.exerciseId = exerciseId
        self.source = source
        self.view = view
        self.fps = fps
        self.labels = labels
        self.frames = frames
        self.hasWorld = hasWorld
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
        // The version decides the allowed keys, so read it first.
        let version = json["formatVersion"]?.numberValue
        guard version == 1 || version == 2 else {
            r.add(["formatVersion"], "Invalid input: expected 1 or 2")
            return nil
        }
        let v2 = version == 2
        guard let o = r.object(json, [], keys: v2 ? common + ["skeleton"] : common) else { return nil }

        var skeleton: Skeleton? = .mediapipe33
        if v2 {
            skeleton = o["skeleton"] == nil
                ? { r.add(["skeleton"], "skeleton is required in formatVersion 2"); return nil }()
                : r.enumValue(o["skeleton"], ["skeleton"], Skeleton.self, options: ["mediapipe33", "vision19"])
        }
        let exerciseId = r.identifier(o["exerciseId"], ["exerciseId"])
        let source = r.enumValue(o["source"], ["source"], Source.self, options: ["synthetic", "calibration", "team"])
        let view = r.enumValue(o["view"], ["view"], CameraView.self, options: ["front", "side"])
        let fps = r.number(o["fps"], ["fps"], where: { $0 > 0 }, "must be positive")
        let labels = o["labels"] == nil ? .some(nil) : readLabels(o["labels"], &r).map { Optional($0) }

        guard let skeleton else { return nil }
        var hasWorld = true
        let frames: [Frame]? = r.array(o["frames"], ["frames"], minCount: 1).flatMap { values in
            r.elements(values, ["frames"]) { r, value, path in
                readFrame(value, path, skeleton: skeleton, v2: v2, hasWorld: &hasWorld, &r)
            }
        }
        if let frames {
            for i in frames.indices.dropFirst() where !(frames[i].t > frames[i - 1].t) {
                r.add(["frames"], "frame timestamps must be strictly increasing")
                break
            }
        }
        guard let exerciseId, let source, let view, let fps, let labels, let frames else { return nil }
        return LandmarkSequence(
            formatVersion: v2 ? 2 : 1, skeleton: skeleton, exerciseId: exerciseId, source: source, view: view,
            fps: fps, labels: labels, frames: frames, hasWorld: hasWorld)
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
        _ v: JSONValue, _ path: [String], skeleton: Skeleton, v2: Bool, hasWorld: inout Bool, _ r: inout SchemaReader
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
        return Frame(t: t, image: image, world: world)
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
