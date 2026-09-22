import AppKit
import SwiftUI
import MicLineCore

struct MeasurementView: View {
    @ObservedObject var graph: AudioGraph
    let openAudioSetup: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var consumerUID = ""
    @State private var speakerUID = ""
    @State private var report: RouteProbeReport?
    @State private var message = "Requires an installed virtual loopback device. No audio is saved."
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Check Loopback Signal Alignment").font(.title2.bold())
                    Text("Experimental diagnostic · no microphone audio is saved")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.disabled(task != nil)
            }
            Text("MicLine plays 20 quiet noise probes through the chosen speaker and captures the raw microphone plus the virtual consumer input. It aligns their audio timestamps, then correlates the waveforms.")
            Label("The result is timestamp-aligned waveform lag. It is not speaker-to-microphone delay, callback delivery latency, live monitoring latency, end-to-end latency, or call-app latency.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Consumer input", selection: $consumerUID) {
                Text("Choose virtual input…").tag("")
                ForEach(graph.inputs.filter(\.isVirtual)) { Text($0.name).tag($0.uid) }
            }
            Picker("Stimulus speaker", selection: $speakerUID) {
                Text("Choose speaker…").tag("")
                ForEach(graph.outputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
            }
            if graph.selectedOutput?.isVirtual != true {
                VStack(alignment: .leading, spacing: 10) {
                    Label("A virtual processed output must be selected before this check can run.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    HStack {
                        Button("Cancel") { dismiss() }
                        Button("Open Audio Setup…") { openAudioSetup() }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Text(message).textSelection(.enabled).font(.callout)
            if let report {
                Text(String(format: "Aligned lag: p50 %.3f ms · p95 %.3f ms · max %.3f ms", report.timestampAlignedLagMilliseconds.p50, report.timestampAlignedLagMilliseconds.p95, report.timestampAlignedLagMilliseconds.max)).monospacedDigit()
                Text("Accepted \(report.acceptedTrials) of 20 probes; rejected \(20 - report.acceptedTrials).")
                    .font(.caption).foregroundStyle(.secondary)
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
                        message = "Running 20 probes… Keep other audio quiet. You can cancel at any time."
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
