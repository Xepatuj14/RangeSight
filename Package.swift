// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RangeSight",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RangeSightCore",
            targets: ["RangeSightCore"]
        )
    ],
    targets: [
        .target(
            name: "RangeSightCore",
            path: "RangeSight",
            exclude: [
                "App",
                "Audio/AudioCaptureService.swift",
                "Camera/CameraPreviewSession.swift",
                "Camera/CameraService.swift",
                "Features",
                "Resources"
            ]
        ),
        .testTarget(
            name: "RangeSightTests",
            dependencies: ["RangeSightCore"],
            path: "RangeSightTests"
        )
    ]
)
