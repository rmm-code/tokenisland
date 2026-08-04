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
    dependencies: [
        // In-place updates. Deliberately linked by the executable only: the
        // library stays free of it so `swift test` needs no embedded framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "TokenIsland",
            dependencies: [
                "TokenIslandKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                // Sparkle.framework is embedded in Contents/Frameworks by
                // Scripts/build_app_bundle.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
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
