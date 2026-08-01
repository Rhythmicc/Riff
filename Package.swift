// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Riff",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Riff", targets: ["PersonalLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "PersonalLauncher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "PersonalLauncherTests",
            dependencies: ["PersonalLauncher"]
        )
    ]
)
