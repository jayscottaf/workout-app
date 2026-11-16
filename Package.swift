// swift-tools-version:5.9
// This package exists only so the app's rules (NextUp/Core and Shared/Plates.swift) can be unit-tested
// from the command line with `swift test`, on a Mac or on Linux.
// The iPhone app itself is built from NextUp.xcodeproj.
import PackageDescription

let package = Package(
    name: "WorkoutCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "WorkoutCore", targets: ["WorkoutCore"])],
    targets: [
        .target(name: "WorkoutCore", path: ".", sources: ["NextUp/Core", "Shared/Plates.swift"]),
        .testTarget(name: "WorkoutCoreTests", dependencies: ["WorkoutCore"], path: "Tests/WorkoutCoreTests"),
    ]
)
