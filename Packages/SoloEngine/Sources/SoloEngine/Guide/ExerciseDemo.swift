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

    public static let joints: [LandmarkName] = LandmarkName.allCases.filter { Skeleton.vision19Landmarks.contains($0) }

    public init(exercise: String, view: CameraView, aspect: Double, frameMs: Int, frames: [[LandmarkName: GuidePoint]]) {
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
        let allowed: Set<String> = ["formatVersion", "exercise", "view", "aspect", "frameMs", "frames"]
        if let extra = o.keys.first(where: { !allowed.contains($0) }) { throw .invalid("unknown field '\(extra)'") }
        guard o["formatVersion"]?.numberValue == 1 else { throw .invalid("formatVersion must be 1") }
        guard let exercise = o["exercise"]?.stringValue, !exercise.isEmpty else { throw .invalid("exercise must be a template id") }
        guard let v = o["view"]?.stringValue, let view = CameraView(rawValue: v) else { throw .invalid("view must be front or side") }
        guard let aspect = o["aspect"]?.numberValue, aspect > 0 else { throw .invalid("aspect must be positive") }
        guard let ms = o["frameMs"]?.numberValue, ms > 0, ms == ms.rounded() else { throw .invalid("frameMs must be a positive integer") }
        guard let list = o["frames"]?.arrayValue, list.count >= 2 else { throw .invalid("frames needs at least 2 frames") }
        var frames: [[LandmarkName: GuidePoint]] = []
        for (i, f) in list.enumerated() {
            guard let fo = f.objectValue else { throw .invalid("frames[\(i)] must be an object") }
            var pose: [LandmarkName: GuidePoint] = [:]
            for (key, value) in fo.entries {
                guard let name = LandmarkName(rawValue: key), Skeleton.vision19Landmarks.contains(name) else {
                    throw .invalid("frames[\(i)]: '\(key)' is not a vision19 joint")
                }
                guard let xy = value.arrayValue, xy.count == 2, let x = xy[0].numberValue, let y = xy[1].numberValue,
                      x.isFinite, y.isFinite else { throw .invalid("frames[\(i)].\(key) must be [x, y]") }
                pose[name] = GuidePoint(x: x, y: y)
            }
            guard pose.count == joints.count else { throw .invalid("frames[\(i)] needs all 17 joints") }
            frames.append(pose)
        }
        return ExerciseDemo(exercise: exercise, view: view, aspect: aspect, frameMs: Int(ms), frames: frames)
    }

    public var json: JSONValue {
        func r(_ x: Double) -> JSONValue { .number((x * 1000).rounded() / 1000) }
        return .object(JSONObject([
            ("formatVersion", 1), ("exercise", .string(exercise)), ("view", .string(view.rawValue)),
            ("aspect", .number(aspect)), ("frameMs", .number(Double(frameMs))),
            ("frames", .array(frames.map { pose in
                .object(JSONObject(Self.joints.map { n in (n.rawValue, .array([r(pose[n]!.x), r(pose[n]!.y)])) }))
            })),
        ]))
    }

    public var loopMs: Double { Double(frames.count * frameMs) }

    /// The pose at `t` ms, looping, linearly interpolated between frames.
    public func pose(atMs t: Double) -> [LandmarkName: GuidePoint] {
        let pos = (t.truncatingRemainder(dividingBy: loopMs) + loopMs).truncatingRemainder(dividingBy: loopMs) / Double(frameMs)
        let i = Int(pos) % frames.count, j = (i + 1) % frames.count
        let s = pos - Double(Int(pos))
        var out: [LandmarkName: GuidePoint] = [:]
        for n in Self.joints {
            let a = frames[i][n]!, b = frames[j][n]!
            out[n] = GuidePoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
        }
        return out
    }

    /// Frame `i` as engine input (visibility 1, no world), at time `t`.
    public func frame(_ i: Int, t: Double) -> Frame {
        var image = Array(repeating: Landmark.missing, count: LandmarkName.count)
        for (n, p) in frames[i] { image[n.index] = Landmark(x: p.x, y: p.y, z: 0, visibility: 1) }
        return Frame(t: t, image: image, world: Array(repeating: .missing, count: LandmarkName.count), imageAspect: aspect)
    }
}
