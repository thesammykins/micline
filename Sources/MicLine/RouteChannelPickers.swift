import SwiftUI
import MicLineCore

struct RouteChannelPickers: View {
    @ObservedObject var graph: AudioGraph

    var body: some View {
        HStack(spacing: 24) {
            Picker("Input channel", selection: Binding(
                get: { graph.selectedInputChannel }, set: { graph.selectInputChannel($0) })) {
                ForEach(0..<max(1, graph.selectedInput?.inputChannels ?? 0), id: \.self) {
                    Text("Input \($0 + 1) · Mono").tag($0)
                }
            }
            .help("Choose the channel connected to your microphone. Only this channel enters the effects.")
            .disabled(graph.selectedInput == nil)
            Picker("Output channels", selection: Binding(
                get: { graph.selectedOutputChannel }, set: { graph.selectOutputChannel($0) })) {
                if graph.selectedOutput?.outputChannels == 1 { Text("Output 1 · Mono").tag(0) }
                else {
                    ForEach(Array(stride(from: 0, to: max(1, (graph.selectedOutput?.outputChannels ?? 2) - 1), by: 2)), id: \.self) {
                        Text("Outputs \($0 + 1)-\($0 + 2)").tag($0)
                    }
                }
            }
            .help("Send your processed voice only to this pair. Other output channels stay silent.")
            .disabled(graph.selectedOutput == nil)
        }
        .font(.caption).controlSize(.small)
    }
}
