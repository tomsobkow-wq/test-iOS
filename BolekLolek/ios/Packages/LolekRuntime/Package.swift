// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LolekRuntime",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LolekRuntime", targets: ["LolekRuntime"]),
    ],
    dependencies: [
        .package(path: "../AgentCore"),
    ],
    targets: [
        // Prebuilt llama.cpp (Metal) from the official release. Pinned by checksum.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11388/llama-b11388-xcframework.zip",
            checksum: "905aa1a4248cda558a13160d1221ce3c05f7877f96ed028cb8cc7dda28baf2e7"
        ),
        .target(
            name: "LolekRuntime",
            dependencies: [.product(name: "AgentCore", package: "AgentCore"), "llama"]
        ),
        .testTarget(
            name: "LolekRuntimeTests",
            dependencies: ["LolekRuntime"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
