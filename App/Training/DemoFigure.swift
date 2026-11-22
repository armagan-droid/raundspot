import SoloEngine
import SwiftUI

/// Looping stick-figure demo (specs/04 "Gösterim animasyonu", specs/12 S1 and T1):
/// the template's live marks on the main figure, the start pose as a faint
/// outline, and a second (side) figure for movements in depth. Same transform
/// as the preview: mirrored on the front camera.
struct DemoPanel: SwiftUI.View {
    let demo: ExerciseDemo
    let guides: [(head: HeadGuide?, line: TargetLineGuide?)]
    let mirrored: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some SwiftUI.View {
        // "Hareketi azalt": slower; the motion itself is the content
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 1000 * (reduceMotion ? 0.6 : 1)
            let blink = GuideDrawing.blink(context.date, reduceMotion: reduceMotion)
            HStack(spacing: 8) {
                figure(demo.frames, pose: demo.pose(atMs: t), marks: guides.isEmpty ? nil : guides[demo.position(atMs: t).index],
                       blink: blink, label: demo.extra == nil ? nil : "demo.view.front")
                if let extra = demo.extra, let pose = demo.extraPose(atMs: t) {
                    // the side figure faces right; mirroring it would only swap the facing
                    figure(extra.frames, pose: pose, marks: nil, blink: blink, label: "demo.view.side", mirror: false)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("demo.accessibility"))
    }

    private func figure(_ frames: [[LandmarkName: GuidePoint]], pose: [LandmarkName: GuidePoint],
                        marks: (head: HeadGuide?, line: TargetLineGuide?)?, blink: Double,
                        label: LocalizedStringKey?, mirror: Bool? = nil) -> some SwiftUI.View {
        let mirrored = mirror ?? self.mirrored
        let box = Self.bounds(frames)
        return VStack(spacing: 2) {
            Canvas { ctx, size in
                let aspect = CGFloat(demo.aspect)
                let k: CGFloat = Swift.min(size.width / Swift.max(box.width * aspect, 1e-6), size.height / Swift.max(box.height, 1e-6))
                let ox = (size.width - box.width * aspect * k) / 2, oy = (size.height - box.height * k) / 2
                // `place` receives an already-mirrored point; mirror within the box so the figure stays centered
                let place: (GuidePoint) -> CGPoint = { p in
                    let x: CGFloat = mirrored ? box.maxX + box.minX - p.x : p.x
                    return CGPoint(x: ox + (x - box.minX) * aspect * k, y: oy + (p.y - box.minY) * k)
                }
                let unit: () -> CGFloat = { k }
                let map = GuideDrawing.Map(mirrored: false, scale: 0.35, place: place, unit: unit)
                Self.stick(frames[0], &ctx, map, color: .white.opacity(0.22), width: 4)
                Self.stick(pose, &ctx, map, color: .white, width: 5)
                if let marks {
                    if let h = marks.head { GuideDrawing.head(h, &ctx, map, blink: blink) }
                    if let l = marks.line { GuideDrawing.line(l, &ctx, map, blink: blink) }
                }
            }
            .aspectRatio(max(box.width * demo.aspect / box.height, 0.4), contentMode: .fit)
            if let label { Text(label).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private static let bones: [(LandmarkName, LandmarkName)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    private static func stick(_ pose: [LandmarkName: GuidePoint], _ ctx: inout GraphicsContext, _ m: GuideDrawing.Map,
                              color: Color, width: CGFloat) {
        func pt(_ n: LandmarkName) -> CGPoint { m.pt(pose[n]!) }
        var path = Path()
        for (a, b) in bones {
            path.move(to: pt(a))
            path.addLine(to: pt(b))
        }
        let neck = CGPoint(x: (pt(.leftShoulder).x + pt(.rightShoulder).x) / 2, y: (pt(.leftShoulder).y + pt(.rightShoulder).y) / 2)
        path.move(to: neck)
        path.addLine(to: pt(.nose))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        let head = pt(.nose), r = max(m.unit() * 0.045, 5)
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
    }

    /// The whole loop's box, so the figure does not jump; room for the marks.
    static func bounds(_ frames: [[LandmarkName: GuidePoint]]) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for f in frames {
            for p in f.values {
                minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        let pad = 0.08
        return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
    }
}
