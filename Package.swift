// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "agent-swift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "agent-swift",
            targets: ["agent-swift"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "agent-swift",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "AgentSwiftLib"
            ]
        ),
        .target(
            name: "AgentSwiftLib",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "agent-swiftTests",
            dependencies: ["AgentSwiftLib"]
        )
    ]
)
