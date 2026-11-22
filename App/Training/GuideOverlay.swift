import SoloEngine
import SwiftUI

/// Target circle, balloons, dashed lines and arrow (ref 08 A5, specs/12 T2).
/// Same transform as the preview and the skeleton; drawn even with the skeleton off.
struct GuideOverlay: SwiftUI.View {
    let guide: HeadGuide?
    var line: TargetLineGuide? = nil
    let aspect: Double
    let mirrored: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some SwiftUI.View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                // "go": the next balloon blinks yellow; "Hareketi azalt" → steady
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
                let blink = reduceMotion ? 1 : (phase < 0.5 ? 1.0 : 0.35)
                if let guide { draw(guide, in: &ctx, size: size, blink: blink) }
                if let line { draw(line, in: &ctx, size: size, blink: blink) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ g: HeadGuide, in ctx: inout GraphicsContext, size: CGSize, blink: Double) {
        let rect = SkeletonOverlay.contentRect(size: size, aspect: aspect)
        func pt(_ p: GuidePoint) -> CGPoint {
            CGPoint(x: rect.minX + (mirrored ? 1 - p.x : p.x) * rect.width, y: rect.minY + p.y * rect.height)
        }
        let r = max(g.radius * rect.height, 24)
        let center = pt(g.center)
        let going = g.mode == .go
        let yellow = Color.yellow, green = Color.green
        let dash = StrokeStyle(lineWidth: 4, lineCap: .round, dash: [14, 10])

        if let y = g.duckLineY {
            let py = rect.minY + y * rect.height
            var line = Path()
            line.move(to: CGPoint(x: center.x - 3 * r, y: py))
            line.addLine(to: CGPoint(x: center.x + 3 * r, y: py))
            ctx.stroke(line, with: .color(.white.opacity(0.9)), style: dash)
        }
        if let x = g.backLineX {
            let px = rect.minX + (mirrored ? 1 - x : x) * rect.width
            var line = Path()
            line.move(to: CGPoint(x: px, y: center.y - 1.5 * r))
            line.addLine(to: CGPoint(x: px, y: center.y + 4 * r))
            ctx.stroke(line, with: .color(.white.opacity(0.9)), style: dash)
        }

        // target circle with a cross; green once the head passed the threshold
        let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        ctx.stroke(circle, with: .color(going ? .white : green), lineWidth: 5)
        var cross = Path()
        cross.move(to: CGPoint(x: center.x - 12, y: center.y))
        cross.addLine(to: CGPoint(x: center.x + 12, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - 12))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + 12))
        ctx.stroke(cross, with: .color(.white), lineWidth: 3)
        if !going {
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28)), with: .color(yellow.opacity(blink)))
        }

        // balloons
        let br = max(r * 0.45, 20)
        for b in g.balloons {
            let p = pt(b.point)
            let shape = Path(ellipseIn: CGRect(x: p.x - br, y: p.y - br, width: 2 * br, height: 2 * br))
            if b.next {
                ctx.fill(shape, with: .color((going ? yellow : green).opacity(going ? blink : 0.9)))
                ctx.stroke(shape, with: .color(.black.opacity(0.6)), lineWidth: 2)
            } else {
                ctx.stroke(shape, with: .color(.white.opacity(0.6)), lineWidth: 3)
            }
        }

        // arrow from the head: to the balloon ("go") or back to the center ("back")
        arrow(from: pt(g.head), to: pt(g.arrowTo), color: yellow, in: &ctx)
    }

    /// Conditioning target line (specs/04 `overlay.targetLine`, specs/12 T2).
    private func draw(_ g: TargetLineGuide, in ctx: inout GraphicsContext, size: CGSize, blink: Double) {
        let rect = SkeletonOverlay.contentRect(size: size, aspect: aspect)
        func pt(_ p: GuidePoint) -> CGPoint {
            CGPoint(x: rect.minX + (mirrored ? 1 - p.x : p.x) * rect.width, y: rect.minY + p.y * rect.height)
        }
        let going = g.mode == .go
        let color: Color = going ? .yellow : .green
        let half = rect.height * 0.18
        for l in g.lines {
            let c = pt(GuidePoint(x: l.x, y: l.y))
            let xs = l.movers.map { pt($0).x } + [c.x]
            var path = Path()
            path.move(to: CGPoint(x: (xs.min() ?? c.x) - half, y: c.y))
            path.addLine(to: CGPoint(x: (xs.max() ?? c.x) + half, y: c.y))
            ctx.stroke(path, with: .color(color.opacity(going ? blink : 1)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [16, 10]))
            for m in l.movers {
                let p = pt(m)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)), with: .color(color))
                if going { arrow(from: p, to: CGPoint(x: p.x, y: c.y), color: .yellow, in: &ctx) }
            }
        }
    }

    private func arrow(from a: CGPoint, to b: CGPoint, color: Color, in ctx: inout GraphicsContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 30 else { return }
        let ux = dx / len, uy = dy / len
        let head: CGFloat = 26
        let tip = CGPoint(x: b.x - ux * 8, y: b.y - uy * 8)
        let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
        var shaft = Path()
        shaft.move(to: CGPoint(x: a.x + ux * 10, y: a.y + uy * 10))
        shaft.addLine(to: base)
        ctx.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        var tri = Path()
        tri.move(to: tip)
        tri.addLine(to: CGPoint(x: base.x - uy * head * 0.6, y: base.y + ux * head * 0.6))
        tri.addLine(to: CGPoint(x: base.x + uy * head * 0.6, y: base.y - ux * head * 0.6))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(color))
    }
}
