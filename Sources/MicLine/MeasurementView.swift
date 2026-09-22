import AppKit
import SwiftUI
import MicLineCore

struct MeasurementView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.dismiss) var dismiss
    @State private var consumerUID = ""
    @State private var speakerUID = ""
    @State private var report: RouteProbeReport?
    @State private var message = "Requires an installed virtual loopback device. No audio is saved."
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Check loopback signal alignment").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.disabled(task != nil) }
            Text("Plays 20 quiet noise bursts through your chosen speaker. Captures the raw microphone and the loopback input, then compares their timestamps and waveforms.")
            Text("Experimental waveform lag after aligning audio timestamps. This is not live delivery latency: timestamps exclude callback scheduling, and no call app is measured.").font(.callout).foregroundStyle(.secondary)
            Picker("Consumer input", selection: $consumerUID) {
                Text("Choose virtual input…").tag("")
                ForEach(graph.inputs.filter(\.isVirtual)) { Text($0.name).tag($0.uid) }
            }
            Picker("Stimulus speaker", selection: $speakerUID) {
                Text("Choose speaker…").tag("")
                ForEach(graph.outputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
            }
            if graph.selectedOutput?.isVirtual != true {
                Label("Choose a virtual output in the main window first.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Text(message).textSelection(.enabled).font(.callout)
            if let report {
                Text(String(format: "Aligned lag: p50 %.3f ms · p95 %.3f ms · max %.3f ms", report.timestampAlignedLagMilliseconds.p50, report.timestampAlignedLagMilliseconds.p95, report.timestampAlignedLagMilliseconds.max)).monospacedDigit()
                Button("Save measurement report…") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "micline-signal-alignment.json"
                    if panel.runModal() == .OK, let url = panel.url {
                        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(report).write(to: url) }
                        catch { message = "Could not save report: \(error.localizedDescription)" }
                    }
                }
            }
            HStack {
                Spacer()
                if task != nil {
                    ProgressView().controlSize(.small)
                    Button("Cancel measurement") { task?.cancel() }
                } else {
                    Button("Play bursts and measure") {
                        guard let consumer = graph.inputs.first(where: { $0.uid == consumerUID }), let speaker = graph.outputs.first(where: { $0.uid == speakerUID }) else { return }
                        report = nil
                        message = "Measuring for 13 seconds… Keep other audio quiet."
                        task = Task {
                            do { report = try await RouteProbe.run(graph: graph, consumer: consumer, speaker: speaker); message = "Measured \(report!.acceptedTrials)/20 valid trials." }
                            catch { message = "No result: \(error.localizedDescription)" }
                            task = nil
                        }
                    }.buttonStyle(.borderedProminent)
                        .disabled(graph.running || graph.loading || graph.selectedOutput?.isVirtual != true || consumerUID.isEmpty || speakerUID.isEmpty)
                }
            }
        }.padding(28).frame(width: 580)
            .onDisappear { task?.cancel() }
    }
}
