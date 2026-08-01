// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Riff",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Riff", targets: ["Riff"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/nodes-app/swift-markdown-engine.git",
            exact: "0.11.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "Riff",
            dependencies: [
                .product(name: "MarkdownEngine", package: "swift-markdown-engine")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "RiffTests",
            dependencies: ["Riff"]
        )
    ]
)
