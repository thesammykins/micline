import SwiftUI
import MicLineCore

struct MonitorButton: View {
    @ObservedObject var graph: AudioGraph
    var allowsMonitoring = true
    @AppStorage("monitorOutputUID") private var outputUID = ""
    @State private var confirm = false

    private var selected: AudioDevice? {
        graph.outputs.first { $0.uid == outputUID && !$0.isVirtual }
    }

    private var supported: Bool {
        guard let selected else { return false }
        return graph.canMonitor(on: selected)
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
        .disabled(!allowsMonitoring || graph.setupActive || graph.loading || (!graph.monitoring && !supported))
        .help(helpText)
        .accessibilityLabel(graph.monitoring ? "Stop monitoring" : "Monitor processed microphone")
        .accessibilityHint(graph.monitoring
            ? "Stops all processing. Start again to continue without physical monitoring."
            : "Requires confirmation before sending microphone audio to the selected physical output.")
        .confirmationDialog("Monitor on \(selected?.name ?? "selected output")?", isPresented: $confirm) {
            if let selected {
                Button("Monitor on \(selected.name)") {
                    Task { await graph.startMonitoring(outputUID: selected.uid) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MicLine will restart processing and send your live microphone to both \(graph.selectedOutput?.name ?? "the virtual output") and \(selected?.name ?? "the selected output"). Speakers can cause loud feedback. Use headphones and lower the device's listening volume first. Monitoring follows the main gain.")
        }
    }

    private var helpText: String {
        if graph.monitoring { return "Stop physical monitoring. Processing stops; press Start to continue to the virtual output only." }
        if selected == nil { return "Choose a physical monitor output in Settings → Audio Setup." }
        if !supported { return "Choose a distinct physical stereo monitor and an available microphone/output channel pair." }
        return "Monitor through \(selected!.name). Explicit confirmation is required."
    }
}
