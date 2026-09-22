import AudioToolbox
import SwiftUI
import MicLineCore
import MicLineUI

struct EffectChainView: View {
    @ObservedObject var graph: AudioGraph
    @State private var dragSessionID = UUID()
    @State private var draggingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(graph.settings.effects.enumerated()), id: \.element.id) { index, effect in
                EffectRow(graph: graph, index: index, effect: effect,
                    dragSessionID: dragSessionID, draggingID: $draggingID)
                if index < graph.settings.effects.count - 1 { Divider() }
            }
        }
    }
}

struct EffectRow: View {
    @ObservedObject var graph: AudioGraph
    let index: Int
    let effect: EffectSelection
    let dragSessionID: UUID
    @Binding var draggingID: UUID?
    @State private var dropEdge: EffectDropEdge?
    @State private var rowHeight: CGFloat = 1

    private var name: String { graph.plugins.first { $0.id == effect.pluginID }?.name ?? "Missing effect" }
    private var payload: EffectDragPayload { EffectDragPayload(effectID: effect.id, sessionID: dragSessionID) }

    var body: some View {
        HStack(spacing: 12) {
            reorderGrip
            Text(String(format: "%02d", index + 1)).monospacedDigit().foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1).foregroundStyle(effect.bypassed || graph.bypass ? .secondary : .primary)
                Text(statusText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle("Enable \(name)", isOn: Binding(get: { !effect.bypassed }, set: { enabled in
                if let i = graph.settings.effects.firstIndex(where: { $0.id == effect.id }) {
                    graph.settings.effects[i].bypassed = !enabled
                }
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .help("Include or bypass \(name) without removing it from the chain.")
            .accessibilityHint("Turns this effect on or bypasses it.")
            Button("Controls") { graph.openEditor(effect.id) }
                .disabled(graph.loading)
                .help("Open the controls supplied by \(name).")
            Button(role: .destructive) { graph.remove(effect.id) } label: {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.borderless)
                .help("Remove \(name) from the effects chain. Processing stops before the chain changes.")
                .accessibilityLabel("Remove \(name)")
                .accessibilityHint("Stops processing and removes this effect from the chain.")
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 10)
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { rowHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in rowHeight = height }
            }
        }
        .overlay(alignment: dropEdge == .after ? .bottom : .top) {
            if dropEdge != nil {
                Capsule().fill(Color.accentColor).frame(height: 3).padding(.horizontal, 2)
                    .accessibilityHidden(true)
            }
        }
        .dropDestination(for: EffectDragPayload.self) { items, session in
            guard let item = items.first, items.count == 1 else { return }
            performDrop(item, edge: edge(for: session.location.y))
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                guard draggingID != nil, draggingID != effect.id else { dropEdge = nil; return }
                dropEdge = edge(for: session.location.y)
            case .exiting, .ended, .dataTransferCompleted:
                dropEdge = nil
            @unknown default:
                dropEdge = nil
            }
        }
        .dropConfiguration { _ in
            DropConfiguration(operation: draggingID == nil ? .forbidden : .move)
        }
    }

    private var reorderGrip: some View {
        EffectReorderGrip(name: name, position: index + 1,
            canMoveEarlier: index > 0,
            canMoveLater: index < graph.settings.effects.count - 1,
            dragging: draggingID == effect.id,
            moveEarlier: { graph.move(effect.id, by: -1) },
            moveLater: { graph.move(effect.id, by: 1) })
            .draggable(payload) {
                Label(name, systemImage: "slider.horizontal.3")
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .onDragSessionUpdated { session in
                switch session.phase {
                case .initial, .active: draggingID = effect.id
                case .ended, .dataTransferCompleted: draggingID = nil
                @unknown default: draggingID = nil
                }
            }
    }

    private func edge(for y: CGFloat) -> EffectDropEdge {
        y < rowHeight / 2 ? .before : .after
    }

    private func performDrop(_ item: EffectDragPayload, edge: EffectDropEdge) {
        let ids = graph.settings.effects.map(\.id)
        if let offset = EffectReordering.offset(ids: ids, payload: item, sessionID: dragSessionID,
                                                destinationID: effect.id, edge: edge) {
            graph.move(item.effectID, by: offset)
        }
        dropEdge = nil
        draggingID = nil
    }

    private var statusText: String {
        if graph.bypass { return "Audio Unit · Bypassed by chain" }
        return effect.bypassed ? "Audio Unit · Bypassed" : "Audio Unit · Enabled"
    }
}

private struct EffectReorderGrip: View {
    let name: String
    let position: Int
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let dragging: Bool
    let moveEarlier: () -> Void
    let moveLater: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(dragging ? Color.accentColor : .secondary)
        .frame(width: 28, height: 32)
        .background((dragging ? Color.accentColor : Color.secondary).opacity(dragging ? 0.18 : hovered ? 0.10 : 0),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .focusable(true, interactions: .edit)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            if press.key == .upArrow, canMoveEarlier { moveEarlier(); return .handled }
            if press.key == .downArrow, canMoveLater { moveLater(); return .handled }
            return .ignored
        }
        .help("Drag to reorder \(name). When focused, press Option–Up or Option–Down.")
        .accessibilityElement()
        .accessibilityLabel("Reorder \(name)")
        .accessibilityValue("Position \(position)")
        .accessibilityHint("Drag to a new position, or use the Move Earlier and Move Later actions.")
        .accessibilityAction(named: "Move \(name) earlier") {
            if canMoveEarlier { moveEarlier() }
        }
        .accessibilityAction(named: "Move \(name) later") {
            if canMoveLater { moveLater() }
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canMoveLater { moveLater() }
            case .decrement: if canMoveEarlier { moveEarlier() }
            @unknown default: break
            }
        }
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
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Close the Audio Unit library without adding another effect.")
            }
            TextField("Search Audio Units", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("effect-search")
                .help("Filter the registered Audio Unit effects by name.")
            if graph.plugins.isEmpty {
                ContentUnavailableView("No Audio Units found", systemImage: "puzzlepiece.extension",
                    description: Text("Rescan after installing an Audio Unit effect."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matches.isEmpty {
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .accessibilityHint("Stops processing and adds this effect at the end of the chain.")
                        .help("Add \(plugin.name) at the end of the effects chain.")
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Text("VST2 and VST3 hosting is unavailable. Filesystem candidates are not loaded or validated.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") { graph.refresh() }
                    .help("Scan the system again for registered Audio Unit effects.")
            }
        }
        .padding(24).frame(width: 520, height: 480)
    }
}

struct GenericAUControlsView: View {
    @ObservedObject var graph: AudioGraph
    var presentedParameters: [AUParameter]? = nil
    @State private var openingValues: [AUParameterAddress: AUValue] = [:]

    private var parameters: [AUParameter] { presentedParameters ?? graph.parameters }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Generic Audio Unit Controls").font(.title2.bold())
                    Text("Names, ranges, units and choices are supplied by the Audio Unit.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { graph.genericEditorID = nil }
                    .keyboardShortcut(.defaultAction)
                    .help("Close these generic Audio Unit controls.")
            }
            Divider()
            if parameters.isEmpty {
                ContentUnavailableView("No editable parameters", systemImage: "slider.horizontal.3",
                    description: Text("This Audio Unit did not publish generic controls."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(parameters, id: \.address) { parameter in
                            parameterCard(parameter)
                        }
                    }
                }
            }
        }
        .padding(24).frame(width: 620, height: 560)
        .task {
            openingValues = Dictionary(uniqueKeysWithValues: parameters.map { ($0.address, $0.value) })
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
                    .help("Restore \(parameter.displayName) to the value it had when these controls opened.")
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
                .help("Choose the \(parameter.displayName) value supplied by the Audio Unit.")
                Text("Choices and labels are supplied by the Audio Unit.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(format(parameter.minValue, parameter: parameter)).font(.caption).foregroundStyle(.secondary)
                    Slider(value: displayBinding(parameter), in: 0...1)
                        .disabled(!writable)
                        .help("Adjust \(parameter.displayName) within the range supplied by the Audio Unit.")
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
        AUParameterPresentation.string(value, parameter: parameter)
    }

    private func displayBinding(_ parameter: AUParameter) -> Binding<Double> {
        Binding(get: {
            AUParameterPresentation.linearPosition(
                for: Double(parameter.value),
                minimum: Double(parameter.minValue),
                maximum: Double(parameter.maxValue),
                flags: parameter.flags
            )
        }, set: { position in
            parameter.value = AUValue(AUParameterPresentation.parameterValue(
                at: position,
                minimum: Double(parameter.minValue),
                maximum: Double(parameter.maxValue),
                flags: parameter.flags
            ))
        })
    }
}
