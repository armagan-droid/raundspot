// swift-tools-version: 6.2
// SoloHealth: HealthKit workout session and energy samples (specs/08; T6.2).
import PackageDescription

let package = Package(
    name: "SoloHealth",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SoloHealth", targets: ["SoloHealth"]),
    ],
    targets: [
        .target(name: "SoloHealth"),
        .testTarget(name: "SoloHealthTests", dependencies: ["SoloHealth"]),
    ],
    swiftLanguageModes: [.v6]
)
