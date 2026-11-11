// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "artMouse",
    platforms: [.macOS(.v14)],
    products: [
        // Lets external tools (settings converters, future helper targets)
        // link the engine. The app target is intentionally not a product.
        .library(name: "ArtMouseCore", targets: ["ArtMouseCore"]),
    ],
    targets: [
        .target(name: "ArtMouseCore"),
        .executableTarget(name: "artMouse", dependencies: ["ArtMouseCore"]),
        .testTarget(name: "ArtMouseCoreTests", dependencies: ["ArtMouseCore"]),
    ]
)
