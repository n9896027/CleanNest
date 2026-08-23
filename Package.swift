// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CleanNest", targets: ["CleanNest"]),
        .executable(name: "CleanNestSelfTest", targets: ["CleanNestSelfTest"]),
        .executable(name: "CleanNestMCP", targets: ["CleanNestMCP"])
    ],
    targets: [
        .target(
            name: "CleanNestCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "CleanNest",
            dependencies: ["CleanNestCore"]
        ),
        .executableTarget(
            name: "CleanNestSelfTest",
            dependencies: ["CleanNestCore"]
        ),
        .executableTarget(
            name: "CleanNestMCP",
            dependencies: ["CleanNestCore"]
        ),
        .testTarget(
            name: "CleanNestCoreTests",
            dependencies: ["CleanNestCore"]
        )
    ]
)
