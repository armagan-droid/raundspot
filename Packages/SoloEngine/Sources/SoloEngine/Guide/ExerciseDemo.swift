import Foundation

/// Looping stick-figure demo of a template (specs/04 "Gösterim animasyonu"):
/// `exercises/demos/<id>.json`. Image coordinates (y down, unmirrored), the 17
/// `vision19` joints with MediaPipe names.
public struct ExerciseDemo: Sendable, Equatable {
    public var exercise: String
    public var view: CameraView
    public var aspect: Double
    public var frameMs: Int
    public var frames: [[LandmarkName: GuidePoint]]
    /// The same movement from a second angle, same timing (specs/04).
    public var extra: Extra?

    public struct Extra: Sendable, Equatable {
        public var view: CameraView
        public var frames: [[LandmarkName: GuidePoint]]

        public init(view: CameraView, frames: [[LandmarkName: GuidePoint]]) {
            self.view = view
            self.frames = frames
        }
    }

    public static let joints: [LandmarkName] = LandmarkName.allCases.filter { Skeleton.vision19Landmarks.contains($0) }

    public init(exercise: String, view: CameraView, aspect: Double, frameMs: Int, frames: [[LandmarkName: GuidePoint]],
                extra: Extra? = nil) {
        self.extra = extra
        self.exercise = exercise
        self.view = view
        self.aspect = aspect
        self.frameMs = frameMs
        self.frames = frames
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case invalid(String)
        public var description: String { if case .invalid(let s) = self { s } else { "" } }
    }

    public static func parse(_ json: JSONValue) throws(ParseError) -> ExerciseDemo {
        guard let o = json.objectValue else { throw .invalid("not an object") }
        let allowed: Set<String> = ["formatVersion", "exercise", "view", "aspect", "frameMs", "frames", "extra"]
        if let extra = o.keys.first(where: { !allowed.contains($0) }) { throw .invalid("unknown field '\(extra)'") }
        guard o["formatVersion"]?.numberValue == 1 else { throw .invalid("formatVersion must be 1") }
        guard let exercise = o["exercise"]?.stringValue, !exercise.isEmpty else { throw .invalid("exercise must be a template id") }
        guard let v = o["view"]?.stringValue, let view = CameraView(rawValue: v) else { throw .invalid("view must be front or side") }
        guard let aspect = o["aspect"]?.numberValue, aspect > 0 else { throw .invalid("aspect must be positive") }
        guard let ms = o["frameMs"]?.numberValue, ms > 0, ms == ms.rounded() else { throw .invalid("frameMs must be a positive integer") }
        guard let list = o["frames"]?.arrayValue, list.count >= 2 else { throw .invalid("frames needs at least 2 frames") }
        let frames = try parseFrames(list, "frames")
        var extra: Extra?
        if let e = o["extra"] {
            guard let eo = e.objectValue else { throw .invalid("extra must be an object") }
            if let k = eo.keys.first(where: { $0 != "view" && $0 != "frames" }) { throw .invalid("extra: unknown field '\(k)'") }
            guard let ev = eo["view"]?.stringValue, let eview = CameraView(rawValue: ev) else { throw .invalid("extra.view must be front or side") }
            guard let el = eo["frames"]?.arrayValue, el.count == list.count else { throw .invalid("extra.frames must have as many frames as frames") }
            extra = Extra(view: eview, frames: try parseFrames(el, "extra.frames"))
        }
        return ExerciseDemo(exercise: exercise, view: view, aspect: aspect, frameMs: Int(ms), frames: frames, extra: extra)
    }

    private static func parseFrames(_ list: [JSONValue], _ field: String) throws(ParseError) -> [[LandmarkName: GuidePoint]] {
        var frames: [[LandmarkName: GuidePoint]] = []
        for (i, f) in list.enumerated() {
            guard let fo = f.objectValue else { throw .invalid("\(field)[\(i)] must be an object") }
            var pose: [LandmarkName: GuidePoint] = [:]
            for (key, value) in fo.entries {
                guard let name = LandmarkName(rawValue: key), Skeleton.vision19Landmarks.contains(name) else {
                    throw .invalid("\(field)[\(i)]: '\(key)' is not a vision19 joint")
                }
                guard let xy = value.arrayValue, xy.count == 2, let x = xy[0].numberValue, let y = xy[1].numberValue,
                      x.isFinite, y.isFinite else { throw .invalid("\(field)[\(i)].\(key) must be [x, y]") }
                pose[name] = GuidePoint(x: x, y: y)
            }
            guard pose.count == joints.count else { throw .invalid("\(field)[\(i)] needs all 17 joints") }
            frames.append(pose)
        }
        return frames
    }

    public var json: JSONValue {
        func r(_ x: Double) -> JSONValue { .number((x * 1000).rounded() / 1000) }
        func list(_ frames: [[LandmarkName: GuidePoint]]) -> JSONValue {
            .array(frames.map { pose in
                .object(JSONObject(Self.joints.map { n in (n.rawValue, .array([r(pose[n]!.x), r(pose[n]!.y)])) }))
            })
        }
        var pairs: [(String, JSONValue)] = [
            ("formatVersion", 1), ("exercise", .string(exercise)), ("view", .string(view.rawValue)),
            ("aspect", .number(aspect)), ("frameMs", .number(Double(frameMs))), ("frames", list(frames)),
        ]
        if let extra { pairs.append(("extra", .object(JSONObject([("view", .string(extra.view.rawValue)), ("frames", list(extra.frames))])))) }
        return .object(JSONObject(pairs))
    }

    public var loopMs: Double { Double(frames.count * frameMs) }

    /// Frame index and fraction toward the next one at `t` ms, looping.
    public func position(atMs t: Double) -> (index: Int, next: Int, fraction: Double) {
        let pos = (t.truncatingRemainder(dividingBy: loopMs) + loopMs).truncatingRemainder(dividingBy: loopMs) / Double(frameMs)
        let i = Int(pos) % frames.count
        return (i, (i + 1) % frames.count, pos - Double(Int(pos)))
    }

    /// The pose at `t` ms, looping, linearly interpolated between frames.
    public func pose(atMs t: Double) -> [LandmarkName: GuidePoint] { pose(atMs: t, in: frames) }

    /// The `extra` view's pose at `t` ms.
    public func extraPose(atMs t: Double) -> [LandmarkName: GuidePoint]? { extra.map { pose(atMs: t, in: $0.frames) } }

    private func pose(atMs t: Double, in frames: [[LandmarkName: GuidePoint]]) -> [LandmarkName: GuidePoint] {
        let (i, j, s) = position(atMs: t)
        var out: [LandmarkName: GuidePoint] = [:]
        for n in Self.joints {
            let a = frames[i][n]!, b = frames[j][n]!
            out[n] = GuidePoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
        }
        return out
    }

    /// The template's live marks on each demo frame (specs/04): the frames
    /// looped twice through the engine and the trackers, second loop kept.
    public func guides(_ loaded: LoadedRulePack) -> [(head: HeadGuide?, line: TargetLineGuide?)] {
        let n = frames.count
        let all = (0..<(2 * n)).map { frame($0 % n, t: Double($0 * frameMs)) }
        let near: PersonSide = view == .side ? chooseNearSide(all) : .left
        let engine = ExerciseEngine(loaded, setup: ExerciseSetup(view: View(view), nearSide: near))
        var head = HeadGuideTracker(loaded.pack, nearSide: near)
        var line = TargetLineTracker(loaded.pack, nearSide: near)
        var out: [(head: HeadGuide?, line: TargetLineGuide?)] = []
        for f in all {
            _ = engine.push(f)
            let m = engine.metrics[loaded.pack.rep.metric]
            let h = head?.update(f, repMetric: m, inRep: engine.repState == .inRep, minVisibility: loaded.pack.camera.minVisibility)
            let l = line?.update(f, repMetric: m, minVisibility: loaded.pack.camera.minVisibility)
            out.append((h, l))
        }
        return Array(out.suffix(n))
    }

    /// Frame `i` as engine input (visibility 1, no world), at time `t`.
    public func frame(_ i: Int, t: Double) -> Frame {
        var image = Array(repeating: Landmark.missing, count: LandmarkName.count)
        for (n, p) in frames[i] { image[n.index] = Landmark(x: p.x, y: p.y, z: 0, visibility: 1) }
        return Frame(t: t, image: image, world: Array(repeating: .missing, count: LandmarkName.count), imageAspect: aspect)
    }
}
