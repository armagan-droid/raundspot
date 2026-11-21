// swift-tools-version: 6.2
// SoloCapture: AVFoundation camera, audio output and host clock mapping (specs/02; T3.1, T3.3).
import PackageDescription

let package = Package(
    name: "SoloCapture",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SoloCapture", targets: ["SoloCapture"]),
    ],
    targets: [
        .target(name: "SoloCapture"),
        .testTarget(name: "SoloCaptureTests", dependencies: ["SoloCapture"]),
    ],
    swiftLanguageModes: [.v6]
)
