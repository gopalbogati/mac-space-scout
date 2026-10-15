// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceScout",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SpaceScoutCore", targets: ["SpaceScoutCore"])],
    targets: [
        .target(name: "SpaceScoutCore"),
        .testTarget(name: "SpaceScoutCoreTests", dependencies: ["SpaceScoutCore"])
    ]
)
