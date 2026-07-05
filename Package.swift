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
    targets: [
        .executableTarget(
            name: "FitbitAirMoodBar",
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
