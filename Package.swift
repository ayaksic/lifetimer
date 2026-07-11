// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LifeTimerCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LifeTimerCore", targets: ["LifeTimerCore"]),
    ],
    targets: [
        .target(name: "LifeTimerCore"),
        .testTarget(
            name: "LifeTimerCoreTests",
            dependencies: ["LifeTimerCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
