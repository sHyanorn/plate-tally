// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlateTallyKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Energy", targets: ["Energy"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Energy", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "EnergyTests", dependencies: ["Energy"]),
    ],
    swiftLanguageModes: [.v6]
)
