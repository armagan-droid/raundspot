import AVFoundation
import SoloEngine
import SoloCapture
import SwiftUI

/// Full-screen camera preview, `contain` (no cropping, ref 08). AVFoundation
/// mirrors the front-camera preview (specs/02: shown mirrored, engine gets it unmirrored).
struct CameraPreview: UIViewRepresentable {
    let camera: CameraSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = camera.session
        v.previewLayer.videoGravity = .resizeAspect
        camera.attach(previewLayer: v.previewLayer)
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Skeleton over the preview, with the same transform (mirrored on the front camera).
struct SkeletonOverlay: SwiftUI.View {
    let frame: Frame?
    let aspect: Double
    let mirrored: Bool
    let minVisibility: Double

    private static let bones: [(LandmarkName, LandmarkName)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        (.leftEar, .leftEye), (.leftEye, .nose), (.nose, .rightEye), (.rightEye, .rightEar),
    ]

    var body: some SwiftUI.View {
        Canvas { ctx, size in
            guard let frame else { return }
            let rect = Self.contentRect(size: size, aspect: aspect)
            func point(_ n: LandmarkName) -> CGPoint? {
                let l = frame[image: n]
                guard l.visibility >= minVisibility, l.x.isFinite, l.y.isFinite else { return nil }
                let x = mirrored ? 1 - l.x : l.x
                return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + l.y * rect.height)
            }
            var path = Path()
            for (a, b) in Self.bones {
                if let p = point(a), let q = point(b) {
                    path.move(to: p)
                    path.addLine(to: q)
                }
            }
            ctx.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for n in Skeleton.vision19Landmarks {
                if let p = point(n) {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.cyan))
                }
            }
        }
        .allowsHitTesting(false)
    }

    static func contentRect(size: CGSize, aspect: Double) -> CGRect {
        let viewAspect = size.width / max(size.height, 1)
        if viewAspect > aspect {
            let w = size.height * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
        let h = size.width / aspect
        return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }
}
