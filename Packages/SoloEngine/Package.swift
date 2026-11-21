// swift-tools-version: 6.2
// SoloEngine: pure Swift rule engine. Foundation only (specs/02, AC-2.1).
// Must build and test on Linux; never import UIKit, AVFoundation or Vision here.
import PackageDescription

let package = Package(
    name: "SoloEngine",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "SoloEngine", targets: ["SoloEngine"]),
    ],
    targets: [
        .target(name: "SoloEngine"),
        .testTarget(name: "SoloEngineTests", dependencies: ["SoloEngine"]),
    ],
    swiftLanguageModes: [.v6]
)
