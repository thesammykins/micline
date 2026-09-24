import AudioToolbox
import AppKit
import SwiftUI
import MicLineCore
import MicLineUI

struct EffectChainView: View {
    @ObservedObject var graph: AudioGraph
    @State private var dragSessionID = UUID()
    @State private var draggingID: UUID?
    @State private var dropTarget: UUID?
    @State private var dropEdge: EffectDropEdge?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(graph.settings.effects.enumerated()), id: \.element.id) { index, effect in
                EffectRow(graph: graph, index: index, effect: effect,
                    dragSessionID: dragSessionID, draggingID: $draggingID,
                    dropTarget: $dropTarget, dropEdge: $dropEdge)
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
    @Binding var dropTarget: UUID?
    @Binding var dropEdge: EffectDropEdge?
    @State private var rowHeight: CGFloat = 1
    @State private var rowWidth: CGFloat = 1

    private var name: String { graph.plugins.first { $0.id == effect.pluginID }?.name ?? "Missing effect" }
    private var payload: EffectDragPayload { EffectDragPayload(effectID: effect.id, sessionID: dragSessionID) }
    private var activeEdge: EffectDropEdge? { dropTarget == effect.id ? dropEdge : nil }

    var body: some View {
        rowContent
        .opacity(draggingID == effect.id ? 0.42 : 1)
        .disabled(graph.loading || graph.setupActive)
        .padding(.vertical, 10)
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear {
                    rowHeight = geometry.size.height
                    rowWidth = geometry.size.width
                }
                .onChange(of: geometry.size) { _, size in
                    rowHeight = size.height
                    rowWidth = size.width
                }
            }
        }
        .overlay(alignment: activeEdge == .after ? .bottom : .top) {
            if let activeEdge {
                HStack(spacing: 0) {
                    Circle().frame(width: 6, height: 6)
                    Rectangle().frame(height: 2)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 2)
                .offset(y: activeEdge == .after ? 3 : -3)
                .accessibilityHidden(true)
            }
        }
        .dropDestination(for: EffectDragPayload.self) { items, session in
            guard session.localSession != nil, items.count == 1,
                  let item = items.first else { return }
            // Transfer completion may outlive the source's visual drag state.
            // performDrop validates the payload's session and current effect IDs.
            performDrop(item, edge: edge(for: session.location.y))
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                let candidate = edge(for: session.location.y)
                if session.localSession != nil, session.itemsCount == 1,
                   validOffset(edge: candidate) != nil {
                    dropTarget = effect.id
                    dropEdge = candidate
                } else if dropTarget == effect.id {
                    clearDropTarget()
                }
            case .exiting, .ended, .dataTransferCompleted:
                if dropTarget == effect.id { clearDropTarget() }
            @unknown default:
                if dropTarget == effect.id { clearDropTarget() }
            }
        }
        .dropConfiguration { session in
            DropConfiguration(operation: session.localSession != nil && session.itemsCount == 1 &&
                validOffset(edge: edge(for: session.location.y)) != nil ? .move : .forbidden)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            reorderGrip
            Text(String(format: "%02d", index + 1)).monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
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
                .help("Remove \(name) from the effects chain. Processing resumes after the chain changes.")
                .accessibilityLabel("Remove \(name)")
                .accessibilityHint("Removes this effect and resumes processing if it was running.")
        }
        .buttonStyle(.bordered)
    }

    private var reorderGrip: some View {
        EffectReorderGrip(name: name, position: index + 1, total: graph.settings.effects.count,
            canMoveEarlier: index > 0,
            canMoveLater: index < graph.settings.effects.count - 1,
            dragging: draggingID == effect.id,
            moveEarlier: { graph.move(effect.id, by: -1) },
            moveLater: { graph.move(effect.id, by: 1) })
            .draggable(payload) {
                HStack(spacing: 10) {
                    EffectGripDots().frame(width: 28, height: 32)
                    Text(String(format: "%02d", index + 1))
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).lineLimit(1)
                        Text(statusText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Toggle("Enable \(name)", isOn: .constant(!effect.bypassed))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Text("Controls").padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "xmark").frame(width: 32, height: 32)
                }
                    .padding(.vertical, 10)
                    .frame(width: rowWidth)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                    .opacity(0.85)
                    .allowsHitTesting(false)
            }
            .dragConfiguration(DragConfiguration(allowMove: true))
            .onDragSessionUpdated { session in
                switch session.phase {
                case .initial, .active: draggingID = effect.id
                case .ended, .dataTransferCompleted:
                    draggingID = nil
                    clearDropTarget()
                @unknown default:
                    draggingID = nil
                    clearDropTarget()
                }
            }
    }

    private func edge(for y: CGFloat) -> EffectDropEdge {
        y < rowHeight / 2 ? .before : .after
    }

    private func validOffset(edge: EffectDropEdge) -> Int? {
        guard let draggingID else { return nil }
        return EffectReordering.offset(ids: graph.settings.effects.map(\.id),
            payload: EffectDragPayload(effectID: draggingID, sessionID: dragSessionID),
            sessionID: dragSessionID, destinationID: effect.id, edge: edge)
    }

    private func clearDropTarget() {
        dropTarget = nil
        dropEdge = nil
    }

    private func performDrop(_ item: EffectDragPayload, edge: EffectDropEdge) {
        let ids = graph.settings.effects.map(\.id)
        if let offset = EffectReordering.offset(ids: ids, payload: item, sessionID: dragSessionID,
                                                destinationID: effect.id, edge: edge),
           let sourceIndex = ids.firstIndex(of: item.effectID) {
            let movedEffect = graph.settings.effects[sourceIndex]
            let movedName = graph.plugins.first { $0.id == movedEffect.pluginID }?.name ?? "Effect"
            graph.move(item.effectID, by: offset)
            NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                userInfo: [.announcement: "\(movedName), position \(sourceIndex + offset + 1) of \(ids.count)",
                           .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        clearDropTarget()
        draggingID = nil
    }

    private var statusText: String {
        if graph.bypass { return "Audio Unit · Bypassed by chain" }
        return effect.bypassed ? "Audio Unit · Bypassed" : "Audio Unit · Enabled"
    }
}

private struct EffectGripDots: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct EffectReorderGrip: View {
    let name: String
    let position: Int
    let total: Int
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let dragging: Bool
    let moveEarlier: () -> Void
    let moveLater: () -> Void
    @State private var hovered = false
    @FocusState private var keyboardFocused: Bool
    @AccessibilityFocusState private var voiceOverFocused: Bool

    var body: some View {
        EffectGripDots()
        .frame(width: 28, height: 32)
        .background(Color.secondary.opacity(dragging ? 0.22 : hovered ? 0.10 : 0),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .focusable(true, interactions: .edit)
        .focused($keyboardFocused)
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            if press.key == .upArrow, canMoveEarlier { move(-1); return .handled }
            if press.key == .downArrow, canMoveLater { move(1); return .handled }
            return .ignored
        }
        .contextMenu {
            Button("Move Earlier") { move(-1) }.disabled(!canMoveEarlier)
            Button("Move Later") { move(1) }.disabled(!canMoveLater)
        }
        .help("Drag to reorder \(name). When focused, press Option-Up or Option-Down.")
        .accessibilityElement()
        .accessibilityLabel("Reorder \(name)")
        .accessibilityValue("Position \(position) of \(total)")
        .accessibilityFocused($voiceOverFocused)
        .accessibilityHint("Drag to a new position, or use the Move Earlier and Move Later actions.")
        .accessibilityAction(named: "Move \(name) earlier") {
            if canMoveEarlier { move(-1) }
        }
        .accessibilityAction(named: "Move \(name) later") {
            if canMoveLater { move(1) }
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canMoveLater { move(1) }
            case .decrement: if canMoveEarlier { move(-1) }
            @unknown default: break
            }
        }
    }

    private func move(_ offset: Int) {
        if offset < 0 { moveEarlier() } else { moveLater() }
        keyboardFocused = true
        voiceOverFocused = true
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: "\(name), position \(position + offset) of \(total)",
                       .priority: NSAccessibilityPriorityLevel.medium.rawValue])
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
                        .accessibilityHint("Adds this effect at the end of the chain and resumes processing if it was running.")
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
