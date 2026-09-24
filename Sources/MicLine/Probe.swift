import AppKit
import Foundation
import MicLineCore

// Explicit launch-only diagnostics use a separate preferences domain and never write microphone samples.
@MainActor
func runProbe(_ graph: AudioGraph) async {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: "--report"), args.indices.contains(index + 1) else { return }
    graph.suspendAutomaticProcessing()
    defer { graph.shutdown() }
    let path = URL(fileURLWithPath: args[index + 1])
    var report: [String: Any] = ["scope": "Real microphone; physical output muted or explicitly selected virtual output. Loopback reports experimental timestamp-aligned waveform lag, NOT delivery or end-to-end latency.", "startedAt": ISO8601DateFormatter().string(from: Date())]
    report["devices"] = graph.devices.map { ["name": $0.name, "uid": $0.uid, "rate": $0.sampleRate, "bufferFrames": $0.bufferFrames] as [String: Any] }
    report["plugins"] = graph.plugins.map { ["name": $0.name, "format": $0.format.rawValue] }
    do {
        guard let input = graph.inputs.first(where: { $0.id == DeviceRegistry.defaultDevice(input: true) }),
              let output = graph.outputs.first(where: { args.contains("--virtual-output") ? $0.isVirtual : $0.id == DeviceRegistry.defaultDevice(input: false) }) else {
            throw NSError(domain: "Probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "No input/output device"])
        }
        report["selectedInputUID"] = input.uid
        report["selectedOutputUID"] = output.uid
        graph.settings.effects = []
        graph.settings.gainDB = -6
        graph.bypass = false
        graph.selectInput(input.uid); graph.selectOutput(output.uid)
        if let effectIndex = args.firstIndex(of: "--effect") {
            guard args.indices.contains(effectIndex + 1),
                  let effect = graph.plugins.first(where: { $0.hostable && $0.name == args[effectIndex + 1] }) else {
                throw NSError(domain: "Probe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Requested AU effect is not registered."])
            }
            graph.add(effect)
            report["selectedEffect"] = effect.name
        } else if !args.contains("--loopback"), !args.contains("--isolation"), let effect = graph.plugins.first(where: { $0.name == "AUHipass" }) {
            graph.add(effect)
        }
        if args.contains("--isolation") {
            guard let consumer = graph.inputs.first(where: { $0.uid == output.uid && $0.isVirtual }) else {
                throw NSError(domain: "Probe", code: 4, userInfo: [NSLocalizedDescriptionKey: "Isolation needs --virtual-output with a loopback input."])
            }
            let isolation = try await RouteProbe.verifyIsolation(graph: graph, consumer: consumer)
            report["isolation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(isolation))
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
            graph.stop(message: "Microphone isolation control passed; see \(path.lastPathComponent).")
            return
        }
        if args.contains("--loopback") {
            guard output.isVirtual, let consumer = graph.inputs.first(where: { $0.uid == output.uid }),
                  let speaker = graph.outputs.first(where: { !$0.isVirtual }) else {
                throw NSError(domain: "Probe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Loopback needs --virtual-output and a physical speaker."])
            }
            var runs: [RouteProbeReport] = []
            for bypass in [true, false] {
                graph.bypass = bypass
                runs.append(try await RouteProbe.run(graph: graph, consumer: consumer, speaker: speaker))
                report["loopback"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(runs))
                report["consumerVisibleOutputVerified"] = true
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
            }
            graph.stop(message: "Loopback measurements complete; see \(path.lastPathComponent).")
            return
        }
        await graph.start(mutePhysicalOutput: !output.isVirtual)
        report["running"] = graph.running
        report["status"] = graph.status
        report["format"] = graph.formatDescription
        var levels: [[String: Any]] = []
        if graph.running {
            for trial in 0..<30 {
                if trial == 10 { graph.bypass = true }
                if trial == 20 { graph.bypass = false; graph.settings.gainDB = -12 }
                try await Task.sleep(for: .milliseconds(200))
                levels.append(["trial": trial, "bypass": graph.bypass, "gainDB": graph.settings.gainDB,
                    "inputFrames": graph.inputFrames, "outputFrames": graph.outputFrames,
                    "inputRMSdBFS": graph.inputDB, "outputRMSdBFS": graph.outputDB])
            }
            if let id = graph.settings.effects.first?.id { graph.openEditor(id) }
        }
        report["levels"] = levels
        report["consumerVisibleOutputVerified"] = false
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
        // Keep the editor visible briefly for inspection, but never leave a diagnostic mic session running.
        try await Task.sleep(for: .seconds(20))
        graph.stop(message: "Diagnostic finished; see \(path.lastPathComponent).")
    } catch {
        report["error"] = error.localizedDescription
        graph.stop()
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path) }
        catch { NSLog("Could not save diagnostic report: %@", error.localizedDescription) }
    }
}
