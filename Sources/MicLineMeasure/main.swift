import Foundation
import MicLineCore

@main
struct Measure {
    static func main() throws {
        let args = CommandLine.arguments
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        if args.contains("--devices") {
            data = try encoder.encode(DeviceRegistry.devices())
        } else if args.contains("--plugins") {
            data = try encoder.encode(PluginRegistry.scan())
        } else if args.contains("--offline") {
            data = try encoder.encode([
                LatencyAnalysis.offline(highPass: false, frames: 128),
                LatencyAnalysis.offline(highPass: true, frames: 128),
                LatencyAnalysis.offline(highPass: true, frames: 512)
            ])
        } else {
            print("Usage: swift run -c release MicLineMeasure --offline | --devices | --plugins")
            print("Offline results are DSP timing, NOT end-to-end microphone latency.")
            return
        }
        print(String(decoding: data, as: UTF8.self))
    }
}
