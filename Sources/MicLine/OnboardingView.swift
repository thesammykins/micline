import AVFoundation
import SwiftUI
import MicLineCore

struct OnboardingView: View {
    enum Step: String, CaseIterable {
        case welcome, permission, microphone, level, isolation, compression, output, handoff, verify, ready
        var title: String {
            switch self {
            case .welcome: "Set up your microphone"
            case .permission: "Allow microphone access"
            case .microphone: "Choose your microphone"
            case .level: "Set your microphone gain"
            case .isolation: "Reduce background noise"
            case .compression: "Control loud peaks"
            case .output: "Choose a virtual output"
            case .handoff: "Select the input in your call app"
            case .verify: "Check your call app receives audio"
            case .ready: "Setup complete"
            }
        }
        var chapter: String {
            switch self {
            case .welcome, .permission, .microphone, .level: "Microphone"
            case .isolation, .compression: "Your sound"
            default: "Your app"
            }
        }
    }

    @ObservedObject var graph: AudioGraph
    @Binding var isPresented: Bool
    @Binding var completedSetup: Bool
    var height: CGFloat = 520
    @AppStorage("soundCheckCheckpoint") private var checkpoint = ""
    @State private var step: Step = .welcome
    @State private var ownsSetup = false
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var requesting = false
    @State private var inputCheck = false
    @State private var trial: SetupEffect?
    @State private var operation: Task<Void, Never>?
    @State private var help = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(step.chapter).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { help.toggle() } label: { Label("Watch Guide", systemImage: "play.rectangle") }
                    .sheet(isPresented: $help) {
                        SetupLessonView(lesson: lesson)
                    }
            }
            Text(step.title).font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if ownsSetup {
                        if needsMicrophoneRecovery {
                            Label("Your microphone is unavailable.", systemImage: "mic.slash")
                            Text("Reconnect it or choose another input. Listening stays stopped.")
                            Button("Choose a Microphone") { advance(.microphone) }
                        } else { content }
                    }
                    else {
                        Text("Another microphone check is open. Close it to continue setup.")
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Finish Later") { finish(completed: false) }.keyboardShortcut(.cancelAction)
                Spacer()
                if ownsSetup {
                    if let index = Step.allCases.firstIndex(of: step), index > 0 {
                        Button("Back") { advance(Step.allCases[index - 1]) }
                    }
                    navigation.disabled(needsMicrophoneRecovery)
                }
            }
        }
        .padding(24).frame(width: 552, height: height)
        .task { ownsSetup = graph.beginSetup() }
        .sheet(isPresented: $inputCheck) { InputCheckView(graph: graph) }
        .sheet(isPresented: Binding(get: { trial != nil }, set: { if !$0 { trial = nil } })) {
            if let trial { EffectTrialView(graph: graph, effect: trial) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission = AVCaptureDevice.authorizationStatus(for: .audio)
        }
        .onChange(of: graph.settings.inputUID) { _, _ in checkpoint = Step.microphone.rawValue }
        .onChange(of: graph.settings.inputChannel) { _, _ in checkpoint = Step.microphone.rawValue }
        .onChange(of: graph.settings.outputUID) { _, _ in
            if step == .verify || step == .ready { advance(.output) }
        }
        .onChange(of: graph.settings.outputChannel) { _, _ in
            if step == .verify || step == .ready { advance(.output) }
        }
        .onDisappear {
            operation?.cancel()
            if ownsSetup { graph.endSetup() }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            if SetupLesson.welcome.recordingURL != nil {
                SetupLessonMovie(lesson: .welcome).frame(height: 220)
            }
            Text("Set your input level, try optional effects, then connect your call app.")
            if !checkpoint.isEmpty {
                Button("Resume \(resumeStep.chapter.lowercased()) setup") { advance(resumeStep) }
            }
        case .permission:
            Text("Microphone access lets us check your level. Allowing it doesn't start listening.")
            if permission == .authorized { Label("Microphone access is allowed", systemImage: "checkmark.circle") }
            else if permission == .denied || permission == .restricted {
                Text("Enable MicLine in System Settings → Privacy & Security → Microphone, then return here.")
                Button("Check Access Again") { permission = AVCaptureDevice.authorizationStatus(for: .audio) }
            }
        case .microphone:
            Text("Choose the microphone you speak into. The output comes later.")
            Picker("Microphone", selection: Binding(get: { graph.settings.inputUID }, set: { graph.selectInput($0) })) {
                Text("Choose...").tag("")
                ForEach(graph.inputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
            }
            Picker("Input channel", selection: Binding(get: { graph.selectedInputChannel }, set: { graph.selectInputChannel($0) })) {
                ForEach(0..<max(1, graph.selectedInput?.inputChannels ?? 0), id: \.self) { Text("Input \($0 + 1)").tag($0) }
            }.disabled(graph.selectedInput == nil)
            Button("Check Devices Again") { graph.refresh() }
        case .level:
            Text("Speak as you would on a call, then try a louder sentence. Adjust your microphone's own gain or your distance from it.")
            Button("Open Sound Check...") { inputCheck = true }.buttonStyle(.borderedProminent)
            Text("This check measures the microphone before MicLine applies gain or effects. Start with speaking peaks around −18 to −6 dBFS; audio is not sent to an output or saved.")
                .font(.callout).foregroundStyle(.secondary)
        case .isolation, .compression:
            let effect: SetupEffect = step == .isolation ? .isolation : .compression
            Text(step == .isolation
                ? "Apple's Sound Isolation can soften background noise. Try it through headphones and keep it only if your voice still sounds natural."
                : "A gentle compressor brings louder and quieter phrases closer together, without automatically boosting the output.")
            if let plugin = effect.plugin(in: graph.plugins) {
                if graph.settings.effects.contains(where: { $0.pluginID == plugin.id }) {
                    Label("Already in your chain", systemImage: "checkmark.circle")
                    Text("Use Controls in the main window to adjust it. Setup won't add a second copy.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Button("Try \(effect.title)...") { trial = effect }.buttonStyle(.borderedProminent)
                }
            } else {
                Text("This Apple effect isn't available here. You can continue without it and choose another installed Audio Unit later.")
            }
            Text("Effects are optional. Avoid stacking multiple noise-removal effects in MicLine and your call app.")
                .font(.callout).foregroundStyle(.secondary)
        case .output:
            Text("A virtual audio device carries your processed voice into other apps. BlackHole is one option; other installed virtual devices work too.")
            Picker("Processed output", selection: Binding(get: { graph.settings.outputUID }, set: { graph.selectOutput($0) })) {
                Text("Choose...").tag("")
                ForEach(graph.outputs) { Text($0.name).tag($0.uid) }
            }
            RouteChannelPickers(graph: graph)
            if graph.selectedOutput?.isVirtual == false {
                Text("This is a physical output. You can use it with explicit listening confirmation in the main window; choose a virtual device to connect a call app.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup("Need a virtual microphone?") { VirtualDeviceGuide(graph: graph) }
        case .handoff:
            Text("In your call app's microphone menu, choose **\(graph.selectedOutput?.name ?? "your virtual device")**.")
            Text("Keep the call app's speaker output on your usual headphones. Start the check when you're ready to send microphone audio to the virtual device.")
                .foregroundStyle(.secondary)
        case .verify:
            Text("Speak and look for a moving input meter in your call app. MicLine can't see whether that app is receiving your voice.")
            MenuOutputMeter(display: graph.meterDisplay)
            Text(graph.status).font(.callout).foregroundStyle(.secondary)
            Button("I don't see a signal") {
                message = "Choose \(graph.selectedOutput?.name ?? "the virtual device") as the call app's microphone, check its mute button and input permission, then start the output check again."
                advance(.handoff, clearMessage: false)
            }
            if graph.running { Button("Stop Output Check") { stop() } }
        case .ready:
            if SetupLesson.ready.recordingURL != nil {
                SetupLessonMovie(lesson: .ready).frame(height: 220)
            }
            Label("You confirmed reception in your app.", systemImage: "checkmark.circle")
            Text("Your settings are saved and the check is stopped. Start processing from MicLine when you want to use this sound.")
            Text("Repeat setup from Settings → Audio Setup. Automatic processing and login launch remain separate choices.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var navigation: some View {
        switch step {
        case .welcome: next("Set Up My Mic", .permission)
        case .permission:
            if permission == .authorized { next("Choose Microphone", .microphone) }
            else if permission == .notDetermined {
                Button("Allow Microphone") {
                    requesting = true
                    operation = Task {
                        _ = await AVCaptureDevice.requestAccess(for: .audio)
                        guard !Task.isCancelled else { return }
                        permission = AVCaptureDevice.authorizationStatus(for: .audio)
                        requesting = false
                        if permission == .authorized { advance(.microphone) }
                    }
                }.buttonStyle(.borderedProminent).disabled(requesting)
            }
        case .microphone: next("Use This Microphone", .level).disabled(graph.selectedInput?.isVirtual != false)
        case .level: next("Continue to Effects", .isolation)
        case .isolation: next("Continue", .compression)
        case .compression: next("Choose Output", .output)
        case .output: next("Use This Output", .handoff).disabled(graph.selectedOutput?.isVirtual != true || graph.routeIssue != nil)
        case .handoff:
            Button("Start Output Check") {
                operation = Task {
                    await graph.startSetupOutputCheck()
                    guard !Task.isCancelled else { return }
                    if graph.running {
                        step = .verify
                    } else { message = graph.status }
                }
            }.buttonStyle(.borderedProminent).disabled(graph.loading || graph.selectedInput == nil || graph.selectedOutput?.isVirtual != true)
        case .verify:
            if graph.running { next("My App Receives Audio", .ready) }
            else { next("Check Again", .handoff) }
        case .ready: Button("Open MicLine") { finish(completed: true) }.buttonStyle(.borderedProminent)
        }
    }

    private func next(_ title: String, _ next: Step) -> some View {
        Button(title) { advance(next) }.buttonStyle(.borderedProminent)
    }
    private var resumeStep: Step {
        guard let saved = Step(rawValue: checkpoint) else { return .permission }
        return [.verify, .ready, .handoff].contains(saved) ? .output : saved
    }
    private var needsMicrophoneRecovery: Bool {
        ![.welcome, .permission, .microphone].contains(step) && graph.selectedInput?.isVirtual != false
    }
    private var lesson: SetupLesson {
        switch step {
        case .welcome: .welcome
        case .permission: .permission
        case .microphone: .microphone
        case .level: .gain
        case .isolation: .isolation
        case .compression: .compression
        case .output: .output
        case .handoff: .handoff
        case .verify: .verify
        case .ready: .ready
        }
    }
    private func stop() { operation?.cancel(); operation = nil; graph.stop() }
    private func advance(_ next: Step, clearMessage: Bool = true) {
        stop(); help = false; step = next; checkpoint = next.rawValue
        if clearMessage { message = nil }
    }
    private func finish(completed: Bool) {
        if ownsSetup { stop() }
        if completed { checkpoint = "" }
        completedSetup = true
        isPresented = false
    }
}
