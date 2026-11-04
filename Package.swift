// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoHands",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.2"),
    ],
    targets: [
        .target(name: "NoHandsCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "NoHandsMac",
            dependencies: [
                "NoHandsCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(name: "NoHands", dependencies: ["NoHandsMac"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "nohands-cli", dependencies: ["NoHandsMac"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "NoHandsCoreTests", dependencies: ["NoHandsCore"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
