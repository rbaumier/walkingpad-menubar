// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WalkingPad",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(name: "WalkingPad", dependencies: ["KeyboardShortcuts"]),
        .testTarget(name: "WalkingPadTests", dependencies: ["WalkingPad"]),
    ]
)
