import Foundation

// Camera setup checks (ref 08 "A3 kurulum kontrolleri"; source
// `setup/assess-setup.ts`) with the S1 additions of specs/12 "S1 hesapları":
// distance, phone tilt, phone rotation and several rule packs at once.

public enum SetupHint: String, Sendable, Equatable, CaseIterable {
    case rotatePhone = "setup.hint.rotate_phone"
    case phoneUpright = "setup.hint.phone_upright"
    case multiplePeople = "setup.hint.multiple_people"
    case showFullBody = "setup.hint.show_full_body"
    case stepBack = "setup.hint.step_back"
    case moveCloser = "setup.hint.move_closer"
    case turnSide = "setup.hint.turn_side"
    case faceCamera = "setup.hint.face_camera"
    case adjustAngle = "setup.hint.adjust_angle"
}

public enum Edge: String, Sendable, Equatable, CaseIterable {
    case top, bottom, left, right
}

public struct SetupSample: Sendable, Equatable {
    /// Selected person's frame, or nil (nobody / ambiguous selection).
    public var frame: Frame?
    public var ambiguous: Bool

    public init(frame: Frame?, ambiguous: Bool = false) {
        self.frame = frame
        self.ambiguous = ambiguous
    }
}

public enum SetupChecks {
    public static let passRatio = 0.8
    public static let edgeMargin = 0.02
    public static let minSpread = 0.45
    /// specs/12 S1: 2–3 m from the camera.
    public static let minDistanceM = 2.0
    public static let maxDistanceM = 3.0
    /// Real height of the eye–ankle span over the body height.
    public static let headToAnkleRatio = 0.90
    public static let defaultHeightM = 1.70
    public static let maxTiltDegrees = 10.0
}

/// What the app knows beyond the frames (specs/12 S1).
public struct SetupContext: Sendable, Equatable {
    /// Vertical field of view of the upright image, degrees (`SoloCapture`); nil = unknown.
    public var verticalFOVDegrees: Double?
    /// From the profile; nil = 1.70 m.
    public var heightM: Double?
    /// Latest phone deviation from vertical, degrees (CoreMotion); nil = unknown.
    public var deviceTiltDegrees: Double?

    public init(verticalFOVDegrees: Double? = nil, heightM: Double? = nil, deviceTiltDegrees: Double? = nil) {
        self.verticalFOVDegrees = verticalFOVDegrees
        self.heightM = heightM
        self.deviceTiltDegrees = deviceTiltDegrees
    }
}

public struct SetupAssessment: Sendable, Equatable {
    public var ready: Bool
    public var view: View
    public var nearSide: PersonSide
    public var hints: [SetupHint]
    /// Fault ids evaluated in the detected view, per rule pack id, in rule pack order.
    public var activeFaults: [String: [String]]
    /// Landmark indices that must be visible (for the S1 overlay).
    public var requiredLandmarks: [Int]
    /// Picture edges where required landmarks are outside the margin.
    public var edges: [Edge]
    /// Distance estimate of the latest frame, when it can be computed.
    public var distanceM: Double?
}

/// Estimated camera distance (specs/12 S1), or nil when the posture is not
/// standing-compatible, the field of view is unknown, or the head or ankles are not seen.
public func estimateDistance(_ frame: Frame, minVisibility: Double, verticalFOVDegrees: Double, heightM: Double) -> Double? {
    let head: [LandmarkName] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
    let ankles: [LandmarkName] = [.leftAnkle, .rightAnkle]
    let top = head.map { frame[image: $0] }.filter { $0.visibility >= minVisibility }.map(\.y).min()
    let bottom = ankles.map { frame[image: $0] }.filter { $0.visibility >= minVisibility }.map(\.y).max()
    guard let top, let bottom, bottom > top, verticalFOVDegrees > 0, verticalFOVDegrees < 180 else { return nil }
    let h = bottom - top
    return SetupChecks.headToAnkleRatio * heightM / (2 * tan(verticalFOVDegrees * Double.pi / 360) * h)
}

/// The combined requirements of the rule packs the setup is for (specs/12 S1:
/// landmark union, view intersection, highest `minVisibility`).
private struct SetupRequirements {
    var packs: [RulePack]
    var views: [CameraView]
    var minVisibility: Double
    var standing: Bool

    init(_ packs: [RulePack]) {
        self.packs = packs
        let first = packs.first?.camera.views ?? []
        views = first.filter { v in packs.allSatisfy { $0.camera.views.contains(v) } }
        minVisibility = packs.map(\.camera.minVisibility).max() ?? 0
        standing = packs.allSatisfy { $0.camera.posture == .standing }
    }

    func required(near: PersonSide) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        for p in packs {
            for r in p.camera.minVisibleLandmarks {
                let i = r.resolve(near: near).index
                if seen.insert(i).inserted { out.append(i) }
            }
        }
        return out
    }
}

private let ratioHintOrder: [SetupHint] = [.multiplePeople, .showFullBody, .stepBack, .moveCloser]

public func assessSetup(_ samples: [SetupSample], pack: RulePack, context: SetupContext = .init()) -> SetupAssessment {
    assessSetup(samples, packs: [pack], context: context)
}

/// Assesses the last ~1 s of samples for the given rule packs.
public func assessSetup(_ samples: [SetupSample], packs: [RulePack], context: SetupContext = .init()) -> SetupAssessment {
    let req = SetupRequirements(packs)
    let frames = samples.compactMap(\.frame)
    let nearSide = chooseNearSide(frames)
    let view = frames.isEmpty ? View.ambiguous : dominantView(frames.map { detectView($0) })
    let required = req.required(near: nearSide)
    let m = SetupChecks.edgeMargin
    let minVis = req.minVisibility
    let height = context.heightM ?? SetupChecks.defaultHeightM

    func distance(_ f: Frame) -> Double? {
        guard req.standing, let fov = context.verticalFOVDegrees else { return nil }
        return estimateDistance(f, minVisibility: minVis, verticalFOVDegrees: fov, heightM: height)
    }

    var failures: [SetupHint: Int] = [:]
    var passed = 0
    for s in samples {
        var hints = Set<SetupHint>()
        if let frame = s.frame {
            for i in required {
                let p = frame.image[i]
                if p.visibility < minVis {
                    hints.insert(.showFullBody)
                } else if p.x < m || p.x > 1 - m || p.y < m || p.y > 1 - m {
                    hints.insert(.stepBack)
                }
            }
            if let d = distance(frame) {
                if d < SetupChecks.minDistanceM { hints.insert(.stepBack) }
                if d > SetupChecks.maxDistanceM { hints.insert(.moveCloser) }
            } else {
                // long side of the visible box: horizontal exercises (push-up) are short vertically
                let vis = frame.image.filter { $0.visibility >= minVis }
                func span(_ vals: [Double]) -> Double { vals.reduce(-.infinity, JSMath.max) - vals.reduce(.infinity, JSMath.min) }
                if vis.count < 2 || JSMath.max(span(vis.map(\.x)), span(vis.map(\.y))) < SetupChecks.minSpread {
                    hints.insert(.moveCloser)
                }
            }
        } else {
            hints.insert(s.ambiguous ? .multiplePeople : .showFullBody)
        }
        if hints.isEmpty { passed += 1 }
        for h in hints { failures[h, default: 0] += 1 }
    }

    let framesOk = !samples.isEmpty && Double(passed) / Double(samples.count) >= SetupChecks.passRatio
    let viewOk: Bool
    switch view {
    case .front: viewOk = req.views.contains(.front)
    case .side: viewOk = req.views.contains(.side)
    case .ambiguous: viewOk = false
    }

    var hints: [SetupHint] = []
    if !framesOk {
        // hints that block the pass ratio, most important first
        let limit = Double(samples.count) * (1 - SetupChecks.passRatio)
        if samples.isEmpty {
            hints = [.showFullBody]
        } else {
            hints = ratioHintOrder.filter { Double(failures[$0] ?? 0) > limit }
            // mixed causes can fail the ratio while each stays under its own limit: name the most frequent
            if hints.isEmpty {
                hints = [ratioHintOrder.reduce(ratioHintOrder[0]) { (failures[$1] ?? 0) > (failures[$0] ?? 0) ? $1 : $0 }]
            }
        }
    }
    if !frames.isEmpty, !viewOk {
        if view == .ambiguous || req.views.isEmpty {
            hints.append(.adjustAngle)
        } else {
            hints.append(req.views.contains(.side) ? .turnSide : .faceCamera)
        }
    }

    var blockers: [SetupHint] = []
    if packs.contains(where: { $0.camera.posture == .horizontal }), let last = frames.last, last.imageAspect < 1 {
        blockers.append(.rotatePhone)
    }
    if let tilt = context.deviceTiltDegrees, Swift.abs(tilt) > SetupChecks.maxTiltDegrees {
        blockers.append(.phoneUpright)
    }

    var active: [String: [String]] = [:]
    for p in packs {
        active[p.id] = p.faults.filter { faultEnabledInView($0.views ?? p.camera.views, view) }.map(\.id)
    }

    return SetupAssessment(
        ready: framesOk && viewOk && blockers.isEmpty,
        view: view,
        nearSide: nearSide,
        hints: blockers + hints,
        activeFaults: active,
        requiredLandmarks: required,
        edges: problemEdges(frames.last, required: required, margin: m),
        distanceM: frames.last.flatMap(distance))
}

/// Edges that required landmarks of the latest frame stick out of.
public func problemEdges(_ frame: Frame?, required: [Int], margin m: Double) -> [Edge] {
    guard let frame else { return [] }
    var out = Set<Edge>()
    for i in required {
        let p = frame.image[i]
        if p.y > 1 - m { out.insert(.bottom) }
        if p.y < m { out.insert(.top) }
        if p.x < m { out.insert(.left) }
        if p.x > 1 - m { out.insert(.right) }
    }
    return Edge.allCases.filter(out.contains)
}

/// Landmark indices a fault's check depends on, through its metrics (T2 highlight), sorted.
public func faultLandmarks(_ loaded: LoadedRulePack, faultId: String, nearSide: PersonSide) -> [Int] {
    guard let fault = loaded.faults.first(where: { $0.fault.id == faultId }),
          let computer = try? MetricComputer(pack: loaded.pack) else { return [] }
    var out = Set<Int>()
    for name in fault.expr.metricNames {
        for l in computer.landmarks(of: name, near: nearSide) { out.insert(l.index) }
    }
    return out.sorted()
}
