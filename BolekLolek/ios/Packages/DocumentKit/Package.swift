// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DocumentKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DocumentKit", targets: ["DocumentKit"]),
    ],
    dependencies: [
        .package(path: "../AgentCore"),
    ],
    targets: [
        .target(name: "DocumentKit", dependencies: [.product(name: "AgentCore", package: "AgentCore")]),
        .testTarget(name: "DocumentKitTests", dependencies: ["DocumentKit"]),
    ]
)
