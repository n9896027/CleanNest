// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CleanNest", targets: ["CleanNest"]),
        .executable(name: "CleanNestLoginItem", targets: ["CleanNestLoginItem"]),
        .executable(name: "CleanNestSelfTest", targets: ["CleanNestSelfTest"]),
        .executable(name: "CleanNestMCP", targets: ["CleanNestMCP"]),
        .executable(name: "CleanNestScanner", targets: ["CleanNestScanner"])
    ],
    targets: [
        .target(
            name: "CleanNestCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .target(
            name: "CleanNestMutation",
            dependencies: ["CleanNestCore"]
        ),
        .executableTarget(
            name: "CleanNest",
            dependencies: ["CleanNestCore", "CleanNestMutation"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "CleanNestSelfTest",
            dependencies: ["CleanNestCore"]
        ),
        .executableTarget(
            name: "CleanNestLoginItem",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "CleanNestMCP",
            dependencies: ["CleanNestCore"]
        ),
        .executableTarget(
            name: "CleanNestScanner",
            dependencies: ["CleanNestCore"]
        ),
        .testTarget(
            name: "CleanNestCoreTests",
            dependencies: ["CleanNestCore", "CleanNestMutation"]
        )
    ]
)
