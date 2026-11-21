// swift-tools-version: 6.2
// SoloPose: Vision -> Frame adapter, person selection, coordinate transform (specs/03; T3.2).
import PackageDescription

let package = Package(
    name: "SoloPose",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SoloPose", targets: ["SoloPose"]),
    ],
    dependencies: [
        .package(path: "../SoloEngine"),
    ],
    targets: [
        .target(name: "SoloPose", dependencies: [.product(name: "SoloEngine", package: "SoloEngine")]),
        .testTarget(name: "SoloPoseTests", dependencies: ["SoloPose"]),
    ],
    swiftLanguageModes: [.v6]
)
