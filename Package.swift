// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlateTallyKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Energy", targets: ["Energy"]),
        .library(name: "Estimation", targets: ["Estimation"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Energy", dependencies: ["Core"]),
        .target(name: "Estimation", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "EnergyTests", dependencies: ["Energy"]),
        .testTarget(name: "EstimationTests", dependencies: ["Estimation", "Core"]),
    ],
    swiftLanguageModes: [.v6]
)
