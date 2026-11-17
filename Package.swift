// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PickPlan",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "PickPlanCore",
            targets: ["PickPlanCore"]
        ),
        .library(
            name: "PickPlanUI",
            targets: ["PickPlanUI"]
        ),
        .executable(
            name: "PickPlanPreviewApp",
            targets: ["PickPlanPreviewApp"]
        )
    ],
    targets: [
        .target(
            name: "PickPlanCore",
            path: "Sources/PickPlanCore"
        ),
        .target(
            name: "PickPlanUI",
            dependencies: ["PickPlanCore"],
            path: "Sources/PickPlanUI"
        ),
        .executableTarget(
            name: "PickPlanPreviewApp",
            dependencies: ["PickPlanCore", "PickPlanUI"],
            path: "Sources/PickPlanPreviewApp"
        ),
        .testTarget(
            name: "PickPlanCoreTests",
            dependencies: ["PickPlanCore"],
            path: "Tests/PickPlanCoreTests"
        )
    ]
)
