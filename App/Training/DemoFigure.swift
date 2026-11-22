import SoloEngine
import SwiftUI

/// Looping stick-figure demo (specs/04 "Gösterim animasyonu", specs/12 S1 and T1).
/// Same transform as the preview: mirrored on the front camera.
struct DemoFigure: SwiftUI.View {
    let demo: ExerciseDemo
    let mirrored: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bones: [(LandmarkName, LandmarkName)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some SwiftUI.View {
        // "Hareketi azalt": still slower, never a flicker; the motion itself is the content
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate * 1000 * (reduceMotion ? 0.6 : 1)
                draw(demo.pose(atMs: t), in: &ctx, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text("demo.accessibility"))
    }

    private func draw(_ pose: [LandmarkName: GuidePoint], in ctx: inout GraphicsContext, size: CGSize) {
        // fit the whole loop's body box, so the figure does not jump
        let box = bounds
        let scale = min(size.width / max(box.width * demo.aspect, 1e-6), size.height / max(box.height, 1e-6)) * 0.9
        let ox = (size.width - box.width * demo.aspect * scale) / 2, oy = (size.height - box.height * scale) / 2
        func pt(_ n: LandmarkName) -> CGPoint {
            let p = pose[n]!
            let x = mirrored ? box.maxX - p.x : p.x - box.minX
            return CGPoint(x: ox + x * demo.aspect * scale, y: oy + (p.y - box.minY) * scale)
        }
        var path = Path()
        for (a, b) in Self.bones {
            path.move(to: pt(a))
            path.addLine(to: pt(b))
        }
        let shoulders = CGPoint(x: (pt(.leftShoulder).x + pt(.rightShoulder).x) / 2, y: (pt(.leftShoulder).y + pt(.rightShoulder).y) / 2)
        path.move(to: shoulders)
        path.addLine(to: pt(.nose))
        ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        let head = pt(.nose), r = max(size.height * 0.05, 6)
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
    }

    private var bounds: CGRect {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for f in demo.frames {
            for p in f.values {
                minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        let pad = 0.04
        return CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + 2 * pad, height: maxY - minY + 2 * pad)
    }
}
