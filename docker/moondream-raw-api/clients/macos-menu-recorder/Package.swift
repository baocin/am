// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoondreamRecorder",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "MoondreamRecorder", targets: ["MoondreamRecorder"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MoondreamRecorder",
            dependencies: [],
            path: ".",
            sources: ["MoondreamRecorder.swift"]
        )
    ]
)