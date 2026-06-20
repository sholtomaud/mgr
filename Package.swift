// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mgr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "mgr",
            path: "Sources/mgr"
        ),
        .testTarget(
            name: "mgrTests",
            dependencies: ["mgr"],
            path: "Tests/mgrTests"
        )
    ]
)
