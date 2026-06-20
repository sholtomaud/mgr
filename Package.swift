// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mgr",
    platforms: [.macOS(.v14)],
    targets: [
        // Library target — all Commands and Core helpers, importable by tests
        .target(
            name: "mgrLib",
            path: "Sources/mgrLib"
        ),
        // Executable — thin entry point only
        .executableTarget(
            name: "mgr",
            dependencies: ["mgrLib"],
            path: "Sources/mgr"
        ),
        .testTarget(
            name: "mgrTests",
            dependencies: ["mgrLib"],
            path: "Tests/mgrTests"
        )
    ]
)
