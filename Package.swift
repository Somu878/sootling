// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Sootling",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sootling", targets: ["Sootling"]),
        .library(name: "SootlingCore", targets: ["SootlingCore"])
    ],
    targets: [
        .target(
            name: "SootlingCore",
            path: "Sootling",
            exclude: ["App"],
            resources: [
                .process("Emissions/Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "Sootling",
            dependencies: ["SootlingCore"],
            path: "Sootling/App",
            exclude: ["Info.plist", "Resources"]
        ),
        .testTarget(
            name: "SootlingTests",
            dependencies: ["SootlingCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
