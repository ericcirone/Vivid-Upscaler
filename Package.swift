// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VividUpscaler",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VividUpscaler", targets: ["VividUpscaler"])
    ],
    targets: [
        .executableTarget(
            name: "VividUpscaler",
            path: "Sources/VividUpscaler"
        ),
        .testTarget(
            name: "VividUpscalerTests",
            dependencies: ["VividUpscaler"],
            path: "Tests/VividUpscalerTests"
        )
    ]
)
