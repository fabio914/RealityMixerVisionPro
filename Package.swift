// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "RealityMixerVisionPro",
    platforms: [
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "MixedRealityCapture",
            targets: [
                "MixedRealityCapture"
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/fabio914/SwiftSocket", from: "2.1.1")
    ],
    targets: [
        .target(
            name: "MixedRealityCapture",
            dependencies: [
                "SwiftSocket"
            ],
            path: "Sources",
            exclude: [],
            resources: [
                .copy("Assets.xcassets"),
                .process("Renderer/Shaders/AlphaExtractor.metal")
            ]
        )
    ]
)
