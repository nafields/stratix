// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XCloudAPI",
    platforms: [.macOS(.v14), .tvOS(.v26), .iOS(.v17)],
    products: [
        .library(name: "XCloudAPI", targets: ["XCloudAPI"])
    ],
    dependencies: [
        .package(path: "../StratixModels"),
        .package(path: "../DiagnosticsKit")
    ],
    targets: [
        .target(name: "XCloudAPI", dependencies: [
            .product(name: "StratixModels", package: "StratixModels"),
            .product(name: "DiagnosticsKit", package: "DiagnosticsKit")
        ]),
        .testTarget(name: "XCloudAPITests", dependencies: ["XCloudAPI"])
    ]
)
