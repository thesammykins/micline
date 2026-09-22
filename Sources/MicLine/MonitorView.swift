import SwiftUI
import MicLineCore

struct MonitorView: View {
    @ObservedObject var graph: AudioGraph
    @AppStorage("monitorOutputUID") private var outputUID = ""
    @State private var confirm = false

    private var outputs: [AudioDevice] { graph.outputs.filter { !$0.isVirtual && $0.outputChannels == 2 } }
    private var selected: AudioDevice? { outputs.first { $0.uid == outputUID } }
    private var supported: Bool {
        guard let input = graph.selectedInput, let output = graph.selectedOutput, let monitor = selected else { return false }
        return !input.isVirtual && input.inputChannels == 1 && input.outputChannels == 0 &&
            output.isVirtual && output.outputChannels == 2 && input.sampleRate == output.sampleRate &&
            monitor.sampleRate == output.sampleRate && monitor.uid != input.uid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Monitor", isOn: Binding(get: { graph.monitoring }, set: { enabled in
                    if enabled { confirm = true } else { graph.stopMonitoring() }
                })).toggleStyle(.switch).controlSize(.small)
                    .disabled(graph.loading || (!graph.monitoring && !supported))
                Picker("Monitor output", selection: $outputUID) {
                    Text("Choose listening output…").tag("")
                    ForEach(outputs) { Text($0.name).tag($0.uid) }
                }.labelsHidden().accessibilityLabel("Monitor output").disabled(graph.loading)
                    .onChange(of: outputUID) { _, _ in if graph.monitoring { graph.stopMonitoring() } }
            }
            Text(graph.monitoring ? "Monitoring follows the main gain. Turning it off stops both outputs; press Start to continue with BlackHole only."
                 : "Listen through headphones while sending to BlackHole. Requires a stereo output at the same sample rate; monitoring stays off until you enable it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Monitor on \(selected?.name ?? "this output")?", isPresented: $confirm) {
            Button("Start monitoring on \(selected?.name ?? "selected output")") {
                Task { await graph.startMonitoring(outputUID: outputUID) }
            }
        } message: {
            Text("This restarts the route and sends your live microphone to both BlackHole and this device. Speakers can cause loud feedback. Use headphones and lower your device’s listening volume first. Monitoring follows the main gain.")
        }
    }
}
