import SoloEngine
import SwiftUI

/// Target circle, balloons, dashed lines, target line and arrows (ref 08 A5,
/// specs/12 T2). Same transform as the preview and the skeleton; drawn even
/// with the skeleton off.
struct GuideOverlay: SwiftUI.View {
    let guide: HeadGuide?
    var line: TargetLineGuide? = nil
    let aspect: Double
    let mirrored: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some SwiftUI.View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                let rect = SkeletonOverlay.contentRect(size: size, aspect: aspect)
                let map = GuideDrawing.Map(mirrored: mirrored) { p in
                    CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
                } unit: { rect.height }
                let blink = GuideDrawing.blink(context.date, reduceMotion: reduceMotion)
                if let guide { GuideDrawing.head(guide, &ctx, map, blink: blink) }
                if let line { GuideDrawing.line(line, &ctx, map, blink: blink) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The guide marks, drawn through any image → view mapping (live image or demo panel).
enum GuideDrawing {
    struct Map {
        let mirrored: Bool
        /// Unmirrored image point (x right, y down, normalized) → view point.
        let place: (GuidePoint) -> CGPoint
        /// View points per image height.
        let unit: () -> CGFloat
        var scale: CGFloat = 1

        init(mirrored: Bool, scale: CGFloat = 1, place: @escaping (GuidePoint) -> CGPoint, unit: @escaping () -> CGFloat) {
            self.mirrored = mirrored
            self.scale = scale
            self.place = place
            self.unit = unit
        }

        func pt(_ p: GuidePoint) -> CGPoint { place(GuidePoint(x: mirrored ? 1 - p.x : p.x, y: p.y)) }
    }

    /// "go": the next mark blinks; "Hareketi azalt" → steady.
    static func blink(_ date: Date, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
        return phase < 0.5 ? 1 : 0.35
    }

    static func head(_ g: HeadGuide, _ ctx: inout GraphicsContext, _ m: Map, blink: Double) {
        let s = m.scale
        let r = max(g.radius * m.unit(), 24 * s)
        let center = m.pt(g.center)
        let going = g.mode == .go
        let dash = StrokeStyle(lineWidth: 4 * s, lineCap: .round, dash: [14 * s, 10 * s])

        if let y = g.duckLineY {
            let py = m.pt(GuidePoint(x: g.center.x, y: y)).y
            var line = Path()
            line.move(to: CGPoint(x: center.x - 3 * r, y: py))
            line.addLine(to: CGPoint(x: center.x + 3 * r, y: py))
            ctx.stroke(line, with: .color(.white.opacity(0.9)), style: dash)
        }
        if let x = g.backLineX {
            let px = m.pt(GuidePoint(x: x, y: g.center.y)).x
            var line = Path()
            line.move(to: CGPoint(x: px, y: center.y - 1.5 * r))
            line.addLine(to: CGPoint(x: px, y: center.y + 4 * r))
            ctx.stroke(line, with: .color(.white.opacity(0.9)), style: dash)
        }

        // target circle with a cross; green once the head passed the threshold
        let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        ctx.stroke(circle, with: .color(going ? .white : .green), lineWidth: 5 * s)
        let c = 12 * s
        var cross = Path()
        cross.move(to: CGPoint(x: center.x - c, y: center.y))
        cross.addLine(to: CGPoint(x: center.x + c, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - c))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + c))
        ctx.stroke(cross, with: .color(.white), lineWidth: 3 * s)
        if !going {
            let d = 14 * s
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - d, y: center.y - d, width: 2 * d, height: 2 * d)), with: .color(.yellow.opacity(blink)))
        }

        let br = max(r * 0.45, 20 * s)
        for b in g.balloons {
            let p = m.pt(b.point)
            let shape = Path(ellipseIn: CGRect(x: p.x - br, y: p.y - br, width: 2 * br, height: 2 * br))
            if b.next {
                ctx.fill(shape, with: .color((going ? Color.yellow : .green).opacity(going ? blink : 0.9)))
                ctx.stroke(shape, with: .color(.black.opacity(0.6)), lineWidth: 2 * s)
            } else {
                ctx.stroke(shape, with: .color(.white.opacity(0.6)), lineWidth: 3 * s)
            }
        }
        arrow(from: m.pt(g.head), to: m.pt(g.arrowTo), color: .yellow, scale: s, &ctx)
    }

    /// Conditioning target line (specs/04 `overlay.targetLine`).
    static func line(_ g: TargetLineGuide, _ ctx: inout GraphicsContext, _ m: Map, blink: Double) {
        let s = m.scale
        let going = g.mode == .go
        let color: Color = going ? .yellow : .green
        let half = m.unit() * 0.18
        for l in g.lines {
            let c = m.pt(GuidePoint(x: l.x, y: l.y))
            let xs = l.movers.map { m.pt($0).x } + [c.x]
            var path = Path()
            path.move(to: CGPoint(x: (xs.min() ?? c.x) - half, y: c.y))
            path.addLine(to: CGPoint(x: (xs.max() ?? c.x) + half, y: c.y))
            ctx.stroke(path, with: .color(color.opacity(going ? blink : 1)),
                       style: StrokeStyle(lineWidth: 6 * s, lineCap: .round, dash: [16 * s, 10 * s]))
            for mover in l.movers {
                let p = m.pt(mover)
                let d = 12 * s
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d)), with: .color(color))
                if going { arrow(from: p, to: CGPoint(x: p.x, y: c.y), color: .yellow, scale: s, &ctx) }
            }
        }
    }

    static func arrow(from a: CGPoint, to b: CGPoint, color: Color, scale s: CGFloat, _ ctx: inout GraphicsContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 30 * s else { return }
        let ux = dx / len, uy = dy / len
        let head: CGFloat = 26 * s
        let tip = CGPoint(x: b.x - ux * 8 * s, y: b.y - uy * 8 * s)
        let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
        var shaft = Path()
        shaft.move(to: CGPoint(x: a.x + ux * 10 * s, y: a.y + uy * 10 * s))
        shaft.addLine(to: base)
        ctx.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 7 * s, lineCap: .round))
        var tri = Path()
        tri.move(to: tip)
        tri.addLine(to: CGPoint(x: base.x - uy * head * 0.6, y: base.y + ux * head * 0.6))
        tri.addLine(to: CGPoint(x: base.x + uy * head * 0.6, y: base.y - ux * head * 0.6))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(color))
    }
}
