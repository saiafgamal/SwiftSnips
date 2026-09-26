// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftSnips",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftSnips", targets: ["SwiftSnips"]),
        .library(name: "SwiftSnipsCore", targets: ["SwiftSnipsCore"])
    ],
    dependencies: [],
    targets: [
        .target(name: "SwiftSnipsCore"),
        .executableTarget(name: "SwiftSnips", dependencies: ["SwiftSnipsCore"]),
        .testTarget(name: "SwiftSnipsCoreTests", dependencies: ["SwiftSnipsCore"])
    ]
)
