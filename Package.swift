// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentLight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AgentStatusCore", targets: ["AgentStatusCore"]),
        .executable(name: "agent-status-daemon", targets: ["AgentStatusDaemon"]),
        .executable(name: "AgentLightMenuBar", targets: ["AgentLightMenuBar"])
    ],
    targets: [
        .target(name: "AgentStatusCore"),
        .executableTarget(name: "AgentStatusDaemon", dependencies: ["AgentStatusCore"]),
        .executableTarget(name: "AgentLightMenuBar", dependencies: ["AgentStatusCore"]),
        .testTarget(name: "AgentStatusCoreTests", dependencies: ["AgentStatusCore"])
    ]
)
