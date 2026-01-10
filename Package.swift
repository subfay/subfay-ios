// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InAppSDK",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "InAppSDK",
            targets: ["InAppSDK"]
        ),
    ],
    targets: [
        .target(
            name: "InAppSDK",
            path: ".",
            exclude: ["examples", "README.md"]
        ),
        .testTarget(
            name: "InAppSDKTests",
            dependencies: ["InAppSDK"]
        ),
    ]
)
