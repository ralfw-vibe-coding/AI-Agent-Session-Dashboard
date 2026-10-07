// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentSessions",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AgentSessions", path: "Sources/AgentSessions")
    ]
)
