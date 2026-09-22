import SwiftUI
import MicLineCore

struct EffectRow: View {
    @ObservedObject var graph: AudioGraph
    let index: Int
    let effect: EffectSelection

    private var name: String { graph.plugins.first { $0.id == effect.pluginID }?.name ?? "Missing effect" }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)").monospacedDigit().foregroundStyle(.tertiary).frame(width: 16)
            Toggle("Enable \(name)", isOn: Binding(get: { !effect.bypassed }, set: { enabled in
                if let i = graph.settings.effects.firstIndex(where: { $0.id == effect.id }) { graph.settings.effects[i].bypassed = !enabled }
            })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Text(name).lineLimit(1).foregroundStyle(effect.bypassed || graph.bypass ? .secondary : .primary)
            Spacer(minLength: 4)
            Button("Controls") { graph.openEditor(effect.id) }.disabled(graph.loading)
            Menu {
                Button("Move Up") { graph.move(effect.id, by: -1) }.disabled(index == 0)
                Button("Move Down") { graph.move(effect.id, by: 1) }.disabled(index == graph.settings.effects.count - 1)
                Divider()
                Button("Remove Effect", role: .destructive) { graph.remove(effect.id) }
            } label: { Image(systemName: "ellipsis") }
                .menuIndicator(.hidden).fixedSize().accessibilityLabel("Actions for \(name)")
        }.padding(.vertical, 10)
    }
}

struct EffectLibraryView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [PluginRecord] {
        graph.plugins.filter { $0.hostable && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Add Effect").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            TextField("Search Audio Units", text: $search).textFieldStyle(.roundedBorder)
            List(matches) { plugin in
                HStack {
                    Text(plugin.name)
                    Spacer()
                    Button("Add") { graph.add(plugin); dismiss() }.disabled(graph.loading || graph.settings.effects.count >= 16)
                        .accessibilityLabel("Add \(plugin.name)")
                }.padding(.vertical, 4)
            }.overlay { if matches.isEmpty { Text("No matching Audio Units").foregroundStyle(.secondary) } }
            HStack {
                Text("Audio Units only. VST hosting is not supported.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") { graph.refresh() }
            }
        }.padding(24).frame(width: 460, height: 420)
    }
}
