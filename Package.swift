// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PlateTallyKit",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
    ],
    swiftLanguageModes: [.v6]
)
