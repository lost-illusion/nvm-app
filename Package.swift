// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "nvm-app",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NVMCore", targets: ["NVMCore"]),
        .executable(name: "NVMApp", targets: ["NVMApp"]),
    ],
    targets: [
        .target(name: "NVMCore"),
        .executableTarget(name: "NVMApp", dependencies: ["NVMCore"]),
        .testTarget(name: "NVMCoreTests", dependencies: ["NVMCore"]),
    ]
)
