// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StratixCore",
    platforms: [.macOS(.v14), .tvOS(.v26), .iOS(.v17)],
    products: [
        .library(name: "StratixCore", targets: ["StratixCore"])
    ],
    dependencies: [
        .package(path: "../StratixModels"),
        .package(path: "../XCloudAPI"),
        .package(path: "../StreamingCore"),
        .package(path: "../DiagnosticsKit"),
        .package(path: "../InputBridge"),
        .package(path: "../VideoRenderingKit")
    ],
    targets: [
        .target(name: "StratixCore", dependencies: [
            .product(name: "StratixModels", package: "StratixModels"),
            .product(name: "XCloudAPI", package: "XCloudAPI"),
            .product(name: "StreamingCore", package: "StreamingCore"),
            .product(name: "DiagnosticsKit", package: "DiagnosticsKit"),
            .product(name: "InputBridge", package: "InputBridge"),
            .product(name: "VideoRenderingKit", package: "VideoRenderingKit")
        ]),
        .testTarget(
            name: "StratixCoreTests",
            dependencies: [
                "StratixCore",
                .product(name: "XCloudAPI", package: "XCloudAPI")
            ]
        )
    ]
)
