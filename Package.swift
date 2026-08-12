// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CleanNest", targets: ["CleanNest"]),
        .executable(name: "CleanNestSelfTest", targets: ["CleanNestSelfTest"])
    ],
    targets: [
        .target(
            name: "CleanNestCore"
        ),
        .executableTarget(
            name: "CleanNest",
            dependencies: ["CleanNestCore"]
        ),
        .executableTarget(
            name: "CleanNestSelfTest",
            dependencies: ["CleanNestCore"]
        ),
        .testTarget(
            name: "CleanNestCoreTests",
            dependencies: ["CleanNestCore"]
        )
    ]
)
