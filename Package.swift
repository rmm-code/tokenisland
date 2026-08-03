// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TokenIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenIsland", targets: ["TokenIsland"]),
        .library(name: "TokenIslandKit", targets: ["TokenIslandKit"])
    ],
    targets: [
        .executableTarget(
            name: "TokenIsland",
            dependencies: ["TokenIslandKit"]
        ),
        .target(
            name: "TokenIslandKit",
            dependencies: [],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TokenIslandKitTests",
            dependencies: ["TokenIslandKit"]
        )
    ]
)
