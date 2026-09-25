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
            // Link a desktop image directly; post-link PE rewriting can corrupt
            // the Swift/LLVM-produced executable's import table.
            .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup",
                          // Keep the explicit asInvoker manifest; LLVM's generated
                          // UAC fragment mismerges its XML namespaces with ours.
                          "-Xlinker", "/MANIFESTUAC:NO", "-Xlinker", "/MANIFEST:EMBED",
                          "-Xlinker", "/MANIFESTINPUT:MicLine.manifest"]),
        ]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
