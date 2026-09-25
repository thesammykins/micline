import Foundation
import WinSDK

@main
enum Application {
    static func main() {
        // The first CI increment proves the official native Swift/WinSDK toolchain.
        // No microphone is opened by build or startup checks.
        guard GetCurrentProcessId() != 0 else { fatalError("WinSDK interop failed") }
        print("MicLine Windows x64 toolchain check passed")
    }
}
