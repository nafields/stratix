// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StratixModels",
    platforms: [
        .macOS(.v14),
        .tvOS(.v26),
        .iOS(.v17)
    ],
    products: [
        .library(name: "StratixModels", targets: ["StratixModels"])
    ],
    targets: [
        .target(name: "StratixModels"),
        .testTarget(name: "StratixModelsTests", dependencies: ["StratixModels"])
    ]
)
