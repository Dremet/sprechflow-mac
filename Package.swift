// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sprechflow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sprechflow", targets: ["Sprechflow"])],
    targets: [
        .target(name: "SprechflowCore"),
        .executableTarget(name: "Sprechflow", dependencies: ["SprechflowCore"]),
        .testTarget(name: "SprechflowCoreTests", dependencies: ["SprechflowCore"])
    ]
)
