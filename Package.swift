// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RecoveryCapture",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "RecoveryCore", targets: ["RecoveryCore"]),
        .library(name: "RecoveryWatchTransport", targets: ["RecoveryWatchTransport"]),
        .executable(name: "recovery-demo", targets: ["RecoveryDemo"]),
    ],
    targets: [
        .target(name: "RecoveryCore"),
        .target(name: "RecoveryWatchTransport", dependencies: ["RecoveryCore"]),
        .executableTarget(name: "RecoveryDemo", dependencies: ["RecoveryCore"]),
        .testTarget(name: "RecoveryCoreTests", dependencies: ["RecoveryCore"]),
    ]
)
