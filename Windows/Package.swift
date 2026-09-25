// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicLineWindows",
    products: [.executable(name: "MicLine", targets: ["MicLineWindows"])],
    targets: [
        .target(name: "WindowsAudio", publicHeadersPath: "include", linkerSettings: [
            .linkedLibrary("ole32"), .linkedLibrary("uuid"), .linkedLibrary("avrt"),
        ]),
        .executableTarget(name: "MicLineWindows", dependencies: ["WindowsAudio"], linkerSettings: [
            .linkedLibrary("user32"), .linkedLibrary("gdi32"),
            .linkedLibrary("shell32"), .linkedLibrary("comctl32"),
        ]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
