// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PathBridge",
    platforms: [.macOS("15.7")],
    products: [.library(name: "PathBridgeCore", targets: ["PathBridgeCore"])],
    targets: [
        .target(name: "PathBridgeCore"),
        .testTarget(name: "PathBridgeCoreTests", dependencies: ["PathBridgeCore"])
    ],
    swiftLanguageModes: [.v6]
)
