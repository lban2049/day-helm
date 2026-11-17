// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DayHelm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DayHelmCore", targets: ["DayHelmCore"]),
        .library(name: "DayHelmCapture", targets: ["DayHelmCapture"]),
        .executable(name: "DayHelmApp", targets: ["DayHelmApp"]),
        .executable(name: "DayHelmChecks", targets: ["DayHelmChecks"])
    ],
    targets: [
        .target(
            name: "DayHelmCore",
            dependencies: []
        ),
        .target(
            name: "DayHelmCapture",
            dependencies: ["DayHelmCore"]
        ),
        .executableTarget(
            name: "DayHelmApp",
            dependencies: ["DayHelmCore", "DayHelmCapture"]
        ),
        .executableTarget(
            name: "DayHelmChecks",
            dependencies: ["DayHelmCore", "DayHelmCapture"]
        ),
        .testTarget(
            name: "DayHelmCoreTests",
            dependencies: ["DayHelmCore", "DayHelmCapture"]
        )
    ]
)
