// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceScout",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SpaceScoutCore", targets: ["SpaceScoutCore"]),
               .executable(name: "SpaceScout", targets: ["SpaceScout"])],
    targets: [
        .target(name: "SpaceScoutCore"),
        .executableTarget(name: "SpaceScout", dependencies: ["SpaceScoutCore"]),
        .testTarget(name: "SpaceScoutAppTests", dependencies: ["SpaceScout"]),
        .testTarget(name: "SpaceScoutCoreTests", dependencies: ["SpaceScoutCore"])
    ]
)
