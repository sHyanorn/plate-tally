// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlateTallyKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Cost", targets: ["Cost"]),
        .library(name: "Energy", targets: ["Energy"]),
        .library(name: "Estimation", targets: ["Estimation"]),
        .library(name: "Ledger", targets: ["Ledger"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Cost", dependencies: ["Core"]),
        .target(name: "Energy", dependencies: ["Core"]),
        .target(name: "Estimation", dependencies: ["Core"]),
        .target(name: "Ledger", dependencies: ["Core"]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "CostTests", dependencies: ["Cost", "Core", "Estimation"]),
        .testTarget(name: "EnergyTests", dependencies: ["Energy"]),
        .testTarget(name: "EstimationTests", dependencies: ["Estimation", "Core"]),
        .testTarget(name: "LedgerTests", dependencies: ["Ledger", "Core"]),
    ],
    swiftLanguageModes: [.v6]
)
