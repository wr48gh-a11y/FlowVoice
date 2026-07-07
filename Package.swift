// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlowVoice",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FlowVoice",
            path: "Sources/FlowVoice"
        ),
        .testTarget(
            name: "FlowVoiceTests",
            dependencies: ["FlowVoice"],
            path: "Tests/FlowVoiceTests"
        )
    ]
)
