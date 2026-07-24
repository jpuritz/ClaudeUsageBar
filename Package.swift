// swift-tools-version: 5.9
import PackageDescription

// This package exists ONLY to unit-test the pure code in Shared/. The shipping
// app and widget are built by XcodeGen from project.yml (or by build.sh), which
// compile Shared/*.swift directly into each target — SwiftPM is not part of the
// release path. Run the tests with `swift test`.
let package = Package(
    name: "ClaudarCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudarCore", path: "Shared"),
        .testTarget(
            name: "ClaudarCoreTests",
            dependencies: ["ClaudarCore"],
            path: "Tests/ClaudarCoreTests"
        ),
    ]
)
