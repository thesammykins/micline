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
                Button("Done") { dismiss() }
                    .disabled(task != nil)
                    .help("Close this measurement check.")
            }
            Text("MicLine plays 20 quiet noise probes through the chosen speaker and captures the raw microphone plus the virtual consumer input. It aligns their audio timestamps, then correlates the waveforms.")
            Label("The result is timestamp-aligned waveform lag. It is not speaker-to-microphone delay, callback delivery latency, live monitoring latency, end-to-end latency, or call-app latency.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            Text("Measurement JSON is not sanitized: it includes device names, identifiers and saved Audio Unit state. Review the exported file before sharing.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Consumer input", selection: $consumerUID) {
                Text("Choose virtual input...").tag("")
                ForEach(matchingConsumers) { Text($0.name).tag($0.uid) }
            }
            .disabled(task != nil)
            .help("Choose the virtual input that matches the processed output.")
            Picker("Stimulus speaker", selection: $speakerUID) {
                Text("Choose speaker...").tag("")
                ForEach(physicalSpeakers) { Text($0.name).tag($0.uid) }
            }
            .disabled(task != nil)
            .help("Choose the physical speaker that will play the audible probes.")
            if let issue = routeConfigurationIssue {
                VStack(alignment: .leading, spacing: 10) {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    HStack {
                        Button("Cancel") { dismiss() }
                            .help("Close the measurement check.")
                        Button("Open Audio Setup...") { openAudioSetup() }
                            .buttonStyle(.borderedProminent)
                            .help("Close this check and open Audio Setup to fix the route.")
                    }
                }
                .padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else if graph.running || graph.loading {
                Label("Stop processing and wait for audio changes to finish before measuring.", systemImage: "pause.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(message).textSelection(.enabled).font(.callout)
            if let report {
                Text(String(format: "Aligned lag: p50 %.3f ms · p95 %.3f ms · max %.3f ms", report.timestampAlignedLagMilliseconds.p50, report.timestampAlignedLagMilliseconds.p95, report.timestampAlignedLagMilliseconds.max)).monospacedDigit()
                Text("Accepted \(report.acceptedTrials) of 20 probes; rejected \(20 - report.acceptedTrials).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save measurement report...") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "micline-signal-alignment.json"
                    if panel.runModal() == .OK, let url = panel.url {
                        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(report).write(to: url) }
                        catch { message = "Could not save report: \(error.localizedDescription)" }
                    }
                }
                .help("Save the unsanitized measurement JSON for local review.")
            }
            HStack {
                Spacer()
                if task != nil {
                    ProgressView().controlSize(.small)
                    Button("Cancel measurement") { task?.cancel() }
                        .help("Stop the current probe sequence without saving a report.")
                } else {
                    Button("Play bursts and measure") {
                        guard preflightIssue == nil, let consumer = selectedConsumer, let speaker = selectedSpeaker else { return }
                        report = nil
                        message = "Running 20 probes... Keep other audio quiet. You can cancel at any time."
                        task = Task {
                            do { report = try await RouteProbe.run(graph: graph, consumer: consumer, speaker: speaker); message = "Measured \(report!.acceptedTrials)/20 valid trials." }
                            catch { message = "No result: \(error.localizedDescription)" }
                            task = nil
                        }
                    }.buttonStyle(.borderedProminent)
                        .disabled(preflightIssue != nil)
                        .help("Play 20 quiet noise probes and measure timestamp-aligned waveform lag.")
                }
            }
        }.padding(28).frame(width: 580)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { graph.suspendAutomaticProcessing(); selectMatchingConsumerIfNeeded() }
            .onChange(of: graph.settings.outputUID) { _, _ in selectMatchingConsumerIfNeeded() }
            .onChange(of: graph.inputs) { _, _ in selectMatchingConsumerIfNeeded() }
            .onDisappear {
                let finishing = task
                finishing?.cancel()
                graph.stop()
                Task { await finishing?.value; graph.restoreAutomaticProcessing() }
            }
    }

    private var matchingConsumers: [AudioDevice] {
        guard let output = graph.selectedOutput else { return [] }
        return graph.inputs.filter { $0.isVirtual && $0.inputChannels > 0 && $0.uid == output.uid }
    }

    private var physicalSpeakers: [AudioDevice] {
        graph.outputs.filter { !$0.isVirtual && $0.outputChannels > 0 }
    }

    private var selectedConsumer: AudioDevice? {
        matchingConsumers.first { $0.uid == consumerUID }
    }

    private var selectedSpeaker: AudioDevice? {
        physicalSpeakers.first { $0.uid == speakerUID }
    }

    private var routeConfigurationIssue: String? {
        guard let input = graph.selectedInput else { return "Choose a microphone in Audio Setup." }
        guard !input.isVirtual else { return "Measurement requires a physical microphone." }
        guard let output = graph.selectedOutput else { return "Choose a processed output in Audio Setup." }
        guard output.isVirtual else { return "Measurement requires a virtual processed output." }
        if let issue = graph.routeIssue { return issue }
        guard let consumer = selectedConsumer else {
            return matchingConsumers.isEmpty
                ? "The selected virtual output has no matching consumer input. Check Audio Setup."
                : "Choose the matching virtual consumer input."
        }
        guard input.sampleRate == consumer.sampleRate else {
            return "The microphone and virtual consumer sample rates must match. Check Audio Setup."
        }
        guard selectedSpeaker != nil else { return "Choose a physical stimulus speaker." }
        return nil
    }

    private var preflightIssue: String? {
        if graph.running || graph.loading { return "Stop processing before measuring." }
        return routeConfigurationIssue
    }

    private func selectMatchingConsumerIfNeeded() {
        guard selectedConsumer == nil else { return }
        consumerUID = matchingConsumers.first?.uid ?? ""
    }
}
