import AVFoundation
import SwiftUI
import MicLineCore

/// Shared by first-run setup and the repeatable microphone check.
struct InputCheckView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.dismiss) private var dismiss
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var checkTask: Task<Void, Never>?
    @State private var attemptedCheck = false
    @State private var ownsSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Find your microphone level").font(.title2.bold())
            Text("Speak as you would on a call. Adjust your microphone's own gain or your distance from it while watching the peak.")
                .foregroundStyle(.secondary)
            Picker("Microphone", selection: Binding(
                get: { graph.settings.inputUID }, set: { graph.selectInput($0) })) {
                Text("Choose...").tag("")
                ForEach(graph.inputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
            }
            Picker("Input channel", selection: Binding(
                get: { graph.selectedInputChannel }, set: { graph.selectInputChannel($0) })) {
                ForEach(0..<max(1, graph.selectedInput?.inputChannels ?? 0), id: \.self) {
                    Text("Input \($0 + 1) · Mono").tag($0)
                }
            }
            .disabled(graph.selectedInput == nil)
            InputCheckMeter(display: graph.meterDisplay, listening: graph.checkingInput)
                .id("\(graph.settings.inputUID):\(graph.selectedInputChannel)")
            Text("Try speaking peaks around −18 to −6 dBFS. Leave room for a laugh or a louder sentence. Adjust for your normal speaking volume.")
                .font(.callout)
            DisclosureGroup("What does this check change?") {
                Text("Nothing: MicLine's gain and effects are skipped. Your microphone or macOS may still apply their own processing. No audio is sent to an output or saved. Lowering MicLine's gain cannot repair clipping that already happened at the microphone.")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
            }
            if attemptedCheck {
                Text(graph.status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Done") { stop(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if graph.checkingInput || graph.loading {
                    Button("Stop Check", action: stop).buttonStyle(.borderedProminent)
                } else if permission == .notDetermined {
                    Button("Allow Microphone") {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            permission = AVCaptureDevice.authorizationStatus(for: .audio)
                        }
                    }.buttonStyle(.borderedProminent)
                } else if permission == .denied || permission == .restricted {
                    Text("Allow MicLine in System Settings → Privacy & Security → Microphone.")
                        .font(.callout).frame(maxWidth: 340, alignment: .trailing)
                } else {
                    Button("Listen for 5 Seconds") {
                        listen()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(graph.selectedInput?.isVirtual != false || graph.running)
                }
            }
        }
        .padding(24).frame(width: 552)
        .task {
            if !graph.setupActive { ownsSetup = graph.beginSetup() }
            if permission == .authorized { listen() }
        }
        .onChange(of: permission) { _, value in
            if value == .authorized { listen() }
        }
        .onChange(of: graph.settings.inputUID) { _, _ in
            if permission == .authorized { listen() }
        }
        .onChange(of: graph.selectedInputChannel) { _, _ in
            if permission == .authorized { listen() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        .onDisappear { stop(); if ownsSetup { graph.endSetup() } }
    }

    private func listen() {
        stop()
        attemptedCheck = true
        checkTask = Task { await graph.startInputCheck() }
    }

    private func stop() {
        let ownedCheck = checkTask != nil
        checkTask?.cancel()
        checkTask = nil
        if ownedCheck && (graph.checkingInput || graph.loading) { graph.stop() }
    }
}

private struct InputCheckMeter: View {
    @ObservedObject var display: MeterDisplay
    let listening: Bool
    @State private var highestPeak = -90.0
    @State private var clipped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LevelMeterView(title: "Microphone", reading: display.readings.input, compact: true)
            if listening {
                Text("Peak \(display.readings.input.heldSamplePeakDBFS <= -90 ? "−∞" : String(format: "%.1f", display.readings.input.heldSamplePeakDBFS)) dBFS")
                    .font(.title3.monospacedDigit())
                if display.readings.input.clipped {
                    Label("Turn down the microphone's gain, then try again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if display.readings.inputSignalMissing {
                    Text("Check the microphone's mute switch and input channel.").foregroundStyle(.secondary)
                }
            } else {
                Text(highestPeak > -90
                    ? "Highest peak: \(String(format: "%.1f", highestPeak)) dBFS\(clipped ? " · Clipping detected" : "")"
                    : "Start when you're ready. You won't hear yourself through speakers.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: listening) { _, started in
            if started { highestPeak = -90; clipped = false }
        }
        .onChange(of: display.readings) { _, readings in
            guard listening else { return }
            highestPeak = max(highestPeak, readings.input.samplePeakDBFS)
            clipped = clipped || readings.input.clipped
        }
    }
}
