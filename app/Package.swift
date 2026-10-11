// swift-tools-version: 6.2
// The rules of the game as a package, so that they build and test on the Mac in seconds and without a simulator.
// The app target of the Xcode project compiles the very same files from the same folder, so nothing here is a
// second copy. The settings mirror the app target's, main actor by default, which is why every type in Core says
// that it is nonisolated.

import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "InfrastructureGOCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    targets: [
        .target(name: "InfrastructureGO", path: "InfrastructureGO/Core", swiftSettings: settings),
        .testTarget(name: "InfrastructureGOCoreTests", dependencies: ["InfrastructureGO"], path: "InfrastructureGOTests/Core", swiftSettings: settings),
    ]
)
