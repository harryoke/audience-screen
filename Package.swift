// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudienceScreen",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AudienceScreen", targets: ["AudienceScreen"])],
    targets: [
        .target(name: "PlaybackCore"),
        .executableTarget(name: "AudienceScreen", dependencies: ["PlaybackCore"]),
        .testTarget(name: "PlaybackCoreTests", dependencies: ["PlaybackCore"])
    ]
)
