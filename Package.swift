// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FitbitAirMoodBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "FitbitAirMoodBar", targets: ["FitbitAirMoodBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "FitbitAirMoodBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "FitbitAirMoodBarTests",
            dependencies: ["FitbitAirMoodBar"]
        ),
    ]
)
