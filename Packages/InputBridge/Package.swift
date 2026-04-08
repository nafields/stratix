// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InputBridge",
    platforms: [.macOS(.v14), .tvOS(.v26), .iOS(.v17)],
    products: [
        .library(name: "InputBridge", targets: ["InputBridge"])
    ],
    dependencies: [
        .package(path: "../StratixModels")
    ],
    targets: [
        .target(name: "InputBridge", dependencies: [
            .product(name: "StratixModels", package: "StratixModels")
        ]),
        .testTarget(name: "InputBridgeTests", dependencies: ["InputBridge"])
    ]
)
