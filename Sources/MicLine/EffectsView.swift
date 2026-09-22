import AudioToolbox
import SwiftUI
import MicLineCore

struct EffectRow: View {
    @ObservedObject var graph: AudioGraph
    let index: Int
    let effect: EffectSelection

    private var name: String { graph.plugins.first { $0.id == effect.pluginID }?.name ?? "Missing effect" }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1)).monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1).foregroundStyle(effect.bypassed || graph.bypass ? .secondary : .primary)
                Text(effect.bypassed ? "Audio Unit · Bypassed" : "Audio Unit · Enabled")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle("Enable \(name)", isOn: Binding(get: { !effect.bypassed }, set: { enabled in
                if let i = graph.settings.effects.firstIndex(where: { $0.id == effect.id }) {
                    graph.settings.effects[i].bypassed = !enabled
                }
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button { graph.move(effect.id, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0).help("Move up")
            Button { graph.move(effect.id, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == graph.settings.effects.count - 1).help("Move down")
            Button("Controls") { graph.openEditor(effect.id) }.disabled(graph.loading)
            Button(role: .destructive) { graph.remove(effect.id) } label: { Image(systemName: "minus") }
                .help("Remove \(name)")
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 10)
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
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Audio Unit Effect").font(.title2.bold())
                    Text("Registered Audio Unit effects only. Effects run top to bottom.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Search Audio Units", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("effect-search")
            if graph.plugins.isEmpty {
                ContentUnavailableView("No Audio Units found", systemImage: "puzzlepiece.extension",
                    description: Text("Rescan after installing an Audio Unit effect."))
            } else if matches.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(matches) { plugin in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name)
                            Text("Audio Unit").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") {
                            graph.add(plugin)
                            dismiss()
                        }
                        .disabled(graph.loading || graph.settings.effects.count >= 16)
                        .accessibilityLabel("Add \(plugin.name)")
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Text("VST2 and VST3 hosting is unavailable. Filesystem candidates are not loaded or validated.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") { graph.refresh() }
            }
        }
        .padding(24).frame(width: 520, height: 480)
    }
}

struct GenericAUControlsView: View {
    @ObservedObject var graph: AudioGraph
    @State private var openingValues: [AUParameterAddress: AUValue] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Generic Audio Unit Controls").font(.title2.bold())
                    Text("Names, ranges, units and choices are supplied by the Audio Unit.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { graph.genericEditorID = nil }.keyboardShortcut(.defaultAction)
            }
            Divider()
            if graph.parameters.isEmpty {
                ContentUnavailableView("No editable parameters", systemImage: "slider.horizontal.3",
                    description: Text("This Audio Unit did not publish generic controls."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(graph.parameters, id: \.address) { parameter in
                            parameterCard(parameter)
                        }
                    }
                }
            }
        }
        .padding(24).frame(width: 620, height: 560)
        .task {
            openingValues = Dictionary(uniqueKeysWithValues: graph.parameters.map { ($0.address, $0.value) })
        }
    }

    @ViewBuilder
    private func parameterCard(_ parameter: AUParameter) -> some View {
        let finiteRange = parameter.minValue.isFinite && parameter.maxValue.isFinite && parameter.maxValue > parameter.minValue
        let writable = parameter.flags.contains(.flag_IsWritable)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(parameter.displayName).font(.headline)
                Spacer()
                if finiteRange && writable {
                    Button("Reset") {
                        if let value = openingValues[parameter.address] { parameter.value = value }
                    }
                    .buttonStyle(.link)
                    .disabled(openingValues[parameter.address] == nil)
                }
            }
            if !finiteRange {
                LabeledContent("Value", value: "Unavailable")
                    .foregroundStyle(.secondary)
                Text("The Audio Unit supplied no finite editable range.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let choices = parameter.valueStrings, !choices.isEmpty {
                Picker(parameter.displayName, selection: valueBinding(parameter)) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                        Text(choice).tag(AUValue(index) + parameter.minValue)
                    }
                }
                .labelsHidden().disabled(!writable)
                Text("Choices and labels are supplied by the Audio Unit.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(format(parameter.minValue, parameter: parameter)).font(.caption).foregroundStyle(.secondary)
                    Slider(value: valueBinding(parameter), in: parameter.minValue...parameter.maxValue)
                        .disabled(!writable)
                    Text(format(parameter.maxValue, parameter: parameter)).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Current value")
                    Spacer()
                    Text(format(parameter.value, parameter: parameter))
                        .monospacedDigit().textSelection(.enabled)
                }
                .font(.callout)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }

    private func valueBinding(_ parameter: AUParameter) -> Binding<AUValue> {
        Binding(get: { parameter.value }, set: { parameter.value = $0 })
    }

    private func format(_ value: AUValue, parameter: AUParameter) -> String {
        let suffix = parameter.unitName.map { " \($0)" } ?? ""
        return String(format: "%+.3f", value) + suffix
    }
}
