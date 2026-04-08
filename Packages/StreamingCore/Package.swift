// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StreamingCore",
    platforms: [.macOS(.v14), .tvOS(.v26), .iOS(.v17)],
    products: [
        .library(name: "StreamingCore", targets: ["StreamingCore"])
    ],
    dependencies: [
        .package(path: "../DiagnosticsKit"),
        .package(path: "../StratixModels"),
        .package(path: "../InputBridge"),
        .package(path: "../XCloudAPI")
    ],
    targets: [
        .target(name: "StreamingCore", dependencies: [
            .product(name: "DiagnosticsKit", package: "DiagnosticsKit"),
            .product(name: "StratixModels", package: "StratixModels"),
            .product(name: "InputBridge", package: "InputBridge"),
            .product(name: "XCloudAPI", package: "XCloudAPI")
        ]),
        .testTarget(name: "StreamingCoreTests", dependencies: ["StreamingCore"])
    ]
)
