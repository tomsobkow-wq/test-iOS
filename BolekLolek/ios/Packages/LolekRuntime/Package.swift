// swift-tools-version: 5.10
import Foundation
import PackageDescription

// The official release zip has no iOS Simulator slice, so the app cannot build for the simulator
// with it. If Tools/build-llama-xcframework.sh has produced Vendor/llama.xcframework (device,
// simulator and macOS), use that; otherwise fall back to the pinned official zip (device + macOS).
let localFramework = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Vendor/llama.xcframework")
let llamaTarget: Target = FileManager.default.fileExists(atPath: localFramework.path)
    ? .binaryTarget(name: "llama", path: "Vendor/llama.xcframework")
    : .binaryTarget(
        name: "llama",
        url: "https://github.com/ggml-org/llama.cpp/releases/download/b11388/llama-b11388-xcframework.zip",
        checksum: "905aa1a4248cda558a13160d1221ce3c05f7877f96ed028cb8cc7dda28baf2e7"
    )

let package = Package(
    name: "LolekRuntime",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LolekRuntime", targets: ["LolekRuntime"]),
    ],
    dependencies: [
        .package(path: "../AgentCore"),
        .package(path: "../DocumentKit"),
    ],
    targets: [
        llamaTarget,
        .target(
            name: "LolekRuntime",
            dependencies: [.product(name: "AgentCore", package: "AgentCore"), .product(name: "DocumentKit", package: "DocumentKit"), "llama"]
        ),
        .testTarget(
            name: "LolekRuntimeTests",
            dependencies: ["LolekRuntime"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
