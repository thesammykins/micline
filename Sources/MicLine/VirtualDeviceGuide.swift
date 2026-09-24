import SwiftUI
import MicLineCore

struct VirtualDeviceGuide: View {
    @ObservedObject var graph: AudioGraph
    @State private var showsRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BlackHole is an optional virtual audio device. If you already use another device, select it as the processed output.")
            Link("Get BlackHole from its developer...", destination: URL(string: "https://existential.audio/blackhole/")!)
            Text("Finish the developer's installer, then check again. MicLine does not install drivers or change your system audio defaults.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check for New Devices") { graph.refresh() }
            DisclosureGroup("Installed, but not showing up?", isExpanded: $showsRestart) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Save recordings and close call/audio apps first. Restarting Core Audio interrupts all audio and may require your administrator password.")
                    Text("If you're comfortable using Terminal, the developer documents this command:")
                    Text("sudo killall -9 coreaudiod").font(.body.monospaced()).textSelection(.enabled)
                    Text("Run it yourself, then check devices again. MicLine never runs this command. If the device is still missing, follow the installer's Mac restart guidance.")
                    Link("Read the developer's guidance...", destination: URL(string: "https://github.com/ExistentialAudio/BlackHole#installation-instructions")!)
                }
                .font(.caption).padding(.top, 8)
            }
        }
        .padding(.vertical, 12)
    }
}
