// swift-tools-version: 6.2
import PackageDescription

// UI code runs on the main actor unless it says otherwise; CareCore stays nonisolated.
let ui: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "MacCare",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CareCore"),
        .target(name: "CareUI", dependencies: ["CareCore"], swiftSettings: ui),
        .executableTarget(name: "Tidy", dependencies: ["CareCore", "CareUI"], swiftSettings: ui),
        .executableTarget(name: "Ward", dependencies: ["CareCore", "CareUI"], swiftSettings: ui),
        .executableTarget(name: "carectl", dependencies: ["CareCore"]),
        .testTarget(name: "CareCoreTests", dependencies: ["CareCore"]),
        .testTarget(name: "CareUITests", dependencies: ["CareUI"]),
        .testTarget(name: "ConventionTests"),
    ]
)
