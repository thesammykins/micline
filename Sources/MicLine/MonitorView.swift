import SwiftUI
import MicLineCore

struct MonitorButton: View {
    @ObservedObject var graph: AudioGraph
    @AppStorage("monitorOutputUID") private var outputUID = ""
    @State private var confirm = false

    private var selected: AudioDevice? {
        graph.outputs.first { $0.uid == outputUID && !$0.isVirtual }
    }

    private var supported: Bool {
        guard let input = graph.selectedInput, let output = graph.selectedOutput, let monitor = selected else { return false }
        return !input.isVirtual && input.inputChannels == 1 && input.outputChannels == 0 &&
            output.isVirtual && output.outputChannels == 2 && input.sampleRate == output.sampleRate &&
            monitor.outputChannels == 2 && monitor.sampleRate == output.sampleRate && monitor.uid != input.uid
    }

    var body: some View {
        Button {
            if graph.monitoring { graph.stopMonitoring() }
            else { confirm = true }
        } label: {
            Image(systemName: graph.monitoring ? "ear.fill" : "ear")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(graph.loading || (!graph.monitoring && !supported))
        .help(helpText)
        .accessibilityLabel(graph.monitoring ? "Stop monitoring" : "Monitor processed microphone")
        .confirmationDialog("Monitor on \(selected?.name ?? "selected output")?", isPresented: $confirm) {
            if let selected {
                Button("Monitor on \(selected.name)") {
                    Task { await graph.startMonitoring(outputUID: selected.uid) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MicLine will restart processing and send your live microphone to both \(graph.selectedOutput?.name ?? "the virtual output") and \(selected?.name ?? "the selected output"). Speakers can cause loud feedback. Use headphones and lower the device’s listening volume first. Monitoring follows the main gain.")
        }
    }

    private var helpText: String {
        if graph.monitoring { return "Stop physical monitoring. Processing stops; press Start to continue to the virtual output only." }
        if selected == nil { return "Choose a physical monitor output in Settings → Audio Setup." }
        if !supported { return "The selected monitor must be stereo and use the same sample rate as the microphone and virtual output." }
        return "Monitor through \(selected!.name). Explicit confirmation is required."
    }
}
