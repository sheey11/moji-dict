// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MojiQuickLook",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MojiQuickLook", targets: ["MojiQuickLook"])
    ],
    targets: [
        .executableTarget(
            name: "MojiQuickLook"
        ),
        .testTarget(
            name: "MojiQuickLookTests",
            dependencies: ["MojiQuickLook"]
        )
    ]
)
