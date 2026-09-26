// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicLine",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "MicLine", targets: ["MicLine"]),
        .executable(name: "MicLineMeasure", targets: ["MicLineMeasure"]),
        .library(name: "MicLineUpdater", targets: ["MicLineUpdater"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "AudioSupport", publicHeadersPath: "include"),
        .target(name: "MicLineCore", dependencies: ["AudioSupport"]),
        .target(name: "MicLineUI"),
        .target(name: "MicLineUpdaterSupport"),
        .target(
            name: "MicLineUpdater",
            dependencies: [
                "MicLineUpdaterSupport",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "MicLine",
            dependencies: ["MicLineCore", "MicLineUI", "MicLineUpdater"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(name: "MicLineMeasure", dependencies: ["MicLineCore"]),
        .testTarget(name: "MicLineCoreTests", dependencies: ["MicLineCore", "AudioSupport"]),
        .testTarget(name: "MicLineAppTests", dependencies: ["MicLine", "MicLineCore"]),
        .testTarget(name: "MicLineUITests", dependencies: ["MicLineUI"]),
        .testTarget(name: "MicLineUpdaterSupportTests", dependencies: ["MicLineUpdaterSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
