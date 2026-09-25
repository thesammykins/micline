// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicLineWindows",
    products: [.executable(name: "MicLine", targets: ["MicLineWindows"])],
    targets: [
        .executableTarget(name: "MicLineWindows", linkerSettings: [
            .linkedLibrary("user32"), .linkedLibrary("gdi32"),
            .linkedLibrary("shell32"), .linkedLibrary("comctl32"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
