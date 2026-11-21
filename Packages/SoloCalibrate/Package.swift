// swift-tools-version: 6.2
// solo-calibrate: command line tool for template validation and calibration
// reports (specs/03, specs/09). Runs on macOS and Linux. No third-party dependencies
// (specs/10): arguments are parsed by hand.
import PackageDescription

let package = Package(
    name: "SoloCalibrate",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "solo-calibrate", targets: ["solo-calibrate"]),
    ],
    dependencies: [
        .package(path: "../SoloEngine"),
    ],
    targets: [
        .target(name: "SoloCalibrateKit", dependencies: ["SoloEngine"]),
        .executableTarget(name: "solo-calibrate", dependencies: ["SoloCalibrateKit"]),
        .testTarget(name: "SoloCalibrateKitTests", dependencies: ["SoloCalibrateKit"]),
    ],
    swiftLanguageModes: [.v6]
)
