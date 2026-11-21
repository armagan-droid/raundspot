// swift-tools-version: 6.2
// SoloRecording: Recording mode, Beta only (specs/09; T5.x). Linked only by the GymSpotSoloBeta target (specs/02).
import PackageDescription

let package = Package(
    name: "SoloRecording",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SoloRecording", targets: ["SoloRecording"]),
    ],
    dependencies: [
        .package(path: "../SoloEngine"),
    ],
    targets: [
        .target(name: "SoloRecording", dependencies: [.product(name: "SoloEngine", package: "SoloEngine")]),
        .testTarget(name: "SoloRecordingTests", dependencies: ["SoloRecording"]),
    ],
    swiftLanguageModes: [.v6]
)
