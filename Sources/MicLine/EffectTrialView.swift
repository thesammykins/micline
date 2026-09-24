import SwiftUI
import MicLineCore

struct EffectTrialView: View {
    @ObservedObject var graph: AudioGraph
    let effect: SetupEffect
    var onKeep: () -> Void = {}
    @StateObject private var preview = AudioGraph(persistsSettings: false)
    @Environment(\.dismiss) private var dismiss
    @State private var selection: EffectSelection?
    @State private var originalEffects: [EffectSelection] = []
    @State private var error: String?
    @State private var confirming = false
    @State private var operation: Task<Void, Never>?
    @State private var preparing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Try \(effect.title)").font(.title2.bold())
            Text(effect == .isolation
                ? "Speak, then pause. Listen for less room noise while your voice still sounds natural."
                : "Try a quiet sentence, then a louder one. Keep the compressor only if you prefer how they sit together.")
                .foregroundStyle(.secondary)
            Picker("Headphones", selection: Binding(get: { preview.settings.outputUID }, set: { preview.selectOutput($0) })) {
                Text("Choose a physical output...").tag("")
                ForEach(preview.outputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
            }
            Text("Use headphones, not speakers. No audio goes to your call app during this preview.")
                .font(.callout).foregroundStyle(.secondary)
            if preparing { ProgressView("Preparing Apple's effect...") }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if selection != nil {
                Picker("Compare", selection: Binding(get: { isEffectEnabled }, set: { enabled in
                    guard let id = selection?.id, let index = preview.settings.effects.firstIndex(where: { $0.id == id }) else { return }
                    preview.settings.effects[index].bypassed = !enabled
                })) {
                    Text("Before this effect").tag(false)
                    Text("With \(effect.title)").tag(true)
                }.pickerStyle(.segmented)
                LiveMeterPanel(display: preview.meterDisplay, compact: true)
                Text("Compare tone as well as loudness. This preset adds no make-up gain. Preview stops after 30 seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if preview.status != "Choose an input and output, then start." {
                Text(preview.status).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Undo") { stop(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if preview.running || preview.loading {
                    Button("Stop Preview", action: stop)
                } else {
                    Button("Listen...") { confirming = true }
                        .disabled(preparing || selection == nil || !preview.canStart || preview.routeIssue != nil)
                }
                Button("Keep \(effect.title)", action: keep)
                    .buttonStyle(.borderedProminent).disabled(selection == nil || preparing || preview.loading)
            }
        }
        .padding(24).frame(width: 552)
        .task {
            preview.settings = graph.settings
            originalEffects = graph.settings.effects
            // Never carry a call output or a previously confirmed headphone route
            // into a new lesson. Each listening session has its own named consent.
            preview.settings.outputUID = ""
            preview.settings.outputChannel = 0
            do {
                guard let plugin = effect.plugin(in: graph.plugins),
                      !originalEffects.contains(where: { $0.pluginID == plugin.id }) else {
                    throw TrialError.message("This effect is already in your chain, or isn't available. Use its Controls in the main window.")
                }
                guard originalEffects.count < 16 else { throw TrialError.message("Your chain is full. Remove an effect before adding another.") }
                let prepared = try await effect.selection(in: graph.plugins)
                try Task.checkCancellation()
                selection = prepared
                preview.settings.effects.append(prepared)
            } catch is CancellationError { /* Dismissal cancels preparation without changing the saved chain. */ }
            catch { self.error = error.localizedDescription }
            preparing = false
        }
        .confirmationDialog("Listen on \(preview.selectedOutput?.name ?? "this output")?", isPresented: $confirming) {
            if let output = preview.selectedOutput {
                Button("Start on \(output.name)") {
                    operation?.cancel()
                    operation = Task {
                        await preview.start(maximumDuration: .seconds(30))
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Confirm that \(preview.selectedOutput?.name ?? "the selected output") is connected to headphones. Lower its listening volume first. Speakers near your microphone can cause loud feedback.")
        }
        .onDisappear(perform: stop)
        .onChange(of: graph.settings.inputUID) { _, _ in invalidateInput() }
        .onChange(of: graph.settings.inputChannel) { _, _ in invalidateInput() }
    }

    private var isEffectEnabled: Bool {
        guard let id = selection?.id else { return false }
        return preview.settings.effects.first(where: { $0.id == id })?.bypassed == false
    }

    private func stop() { operation?.cancel(); operation = nil; preview.stop() }

    private func invalidateInput() {
        stop()
        selection = nil
        error = "Your microphone changed. Close this preview and try again with the new input."
    }

    private func keep() {
        stop()
        guard graph.settings.effects == originalEffects, !graph.running, !graph.loading,
              let id = selection?.id, var kept = preview.settings.effects.first(where: { $0.id == id }) else {
            error = "Your chain changed during this preview. Close it and try again."
            return
        }
        kept.bypassed = false
        graph.settings.effects.append(kept)
        onKeep()
        dismiss()
    }
}

private enum TrialError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
