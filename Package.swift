// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicLine",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "MicLine", targets: ["MicLine"]), .executable(name: "MicLineMeasure", targets: ["MicLineMeasure"])],
    targets: [
        .target(name: "AudioSupport", publicHeadersPath: "include"),
        .target(name: "MicLineCore", dependencies: ["AudioSupport"]),
        .executableTarget(name: "MicLine", dependencies: ["MicLineCore"]),
        .executableTarget(name: "MicLineMeasure", dependencies: ["MicLineCore"]),
        .testTarget(name: "MicLineCoreTests", dependencies: ["MicLineCore", "AudioSupport"])
    ],
    swiftLanguageModes: [.v5]
)
