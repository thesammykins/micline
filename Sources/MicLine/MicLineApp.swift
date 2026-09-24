import AppKit
import SwiftUI
import MicLineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        UserDefaults.standard.register(defaults: ["showInDock": true])
        Self.setDockVisible(UserDefaults.standard.bool(forKey: "showInDock"))
    }

    static func setDockVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil) }
        return true
    }
}

@main
struct MicLineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var graph: AudioGraph
    @State private var didProbe = false
    @State private var didAttemptStartup = false
    private let fixture = PresentationFixture.current
    private let presentationDefaults = UserDefaults(suiteName: "com.sammy.micline.presentation")!

    init() {
        let defaults: UserDefaults
        if CommandLine.arguments.contains("--probe") {
            defaults = UserDefaults(suiteName: "com.sammy.micline.probe")!
        } else if PresentationFixture.current != nil {
            defaults = UserDefaults(suiteName: "com.sammy.micline.presentation")!
        } else {
            defaults = .standard
        }
        _graph = StateObject(wrappedValue: AudioGraph(defaults: defaults))
    }

    var body: some Scene {
        Window("MicLine", id: "main") {
            if let fixture {
                if fixture == .stopped {
                    ProductionStoppedFixtureView(graph: graph)
                        .defaultAppStorage(presentationDefaults)
                } else if fixture == .effects {
                    ProductionEffectsFixtureView(graph: graph)
                        .defaultAppStorage(presentationDefaults)
                } else if fixture == .onboarding {
                    ProductionOnboardingFixtureView(graph: graph)
                        .defaultAppStorage(presentationDefaults)
                } else if fixture == .measurement {
                    ProductionMeasurementFixtureView(graph: graph)
                        .defaultAppStorage(presentationDefaults)
                } else if fixture == .genericControls {
                    ProductionGenericControlsFixtureView(graph: graph)
                        .defaultAppStorage(presentationDefaults)
                } else {
                    PresentationFixtureView(fixture: fixture)
                }
            } else if CommandLine.arguments.contains("--preview-missing-blackhole") {
                VStack(alignment: .leading) {
                    Text("Setup preview · simulated missing device").font(.caption).foregroundStyle(.secondary)
                    ScrollView { AudioSetupView(graph: graph, previewMissing: true) }
                }.padding(24).frame(width: 620, height: 650)
            } else {
                MainView(graph: graph)
                    .task {
                        NSApp.activate(ignoringOtherApps: true)
                        if CommandLine.arguments.contains("--probe"), !didProbe {
                            didProbe = true
                            Task { await runProbe(graph) }
                        } else if !CommandLine.arguments.contains("--probe"), !didAttemptStartup {
                            didAttemptStartup = true
                            if UserDefaults.standard.bool(forKey: "completedSetup"),
                               UserDefaults.standard.bool(forKey: "startProcessingOnLaunch"),
                               graph.selectedOutput?.isVirtual == true, graph.routeIssue == nil {
                                await graph.start()
                            }
                        }
                    }
            }
        }
        .defaultSize(width: 720, height: 680)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)

        Settings {
            if fixture == nil { SettingsRootView(graph: graph) }
            else { FixtureSettingsUnavailableView() }
        }

        MenuBarExtra("MicLine", systemImage: fixture == nil && graph.running ? "waveform.circle.fill" : "waveform.circle") {
            if fixture == nil {
                MenuView(graph: graph)
            } else {
                FixtureMenuView()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("MicLine").font(.headline); Spacer(); ProcessingState(graph: graph) }
            Text("\(graph.selectedInput?.name ?? "Choose a microphone") · Input \(graph.selectedInputChannel + 1)")
                .font(.callout).lineLimit(2)
            Text("→ \(graph.selectedOutput?.name ?? "Choose an output") · \(outputChannels)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            MenuOutputMeter(display: graph.meterDisplay)
            HStack {
                StartButton(graph: graph)
                Spacer()
                Toggle("Bypass effects", isOn: $graph.bypass).toggleStyle(.switch).controlSize(.small)
                    .help("Skip low cut and effects. Gain remains active.")
                MonitorButton(graph: graph)
            }
            if let issue = graph.routeIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                Button("Open MicLine") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
                Button("Quit") { graph.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .padding(16).frame(width: 360)
    }

    private var outputChannels: String {
        graph.selectedOutput?.outputChannels == 1 ? "Channel 1"
            : "Channels \(graph.selectedOutputChannel + 1)-\(graph.selectedOutputChannel + 2)"
    }
}

struct MainView: View {
    @ObservedObject var graph: AudioGraph
    var allowsAudioActions = true
    var showsOnboarding = true
    @AppStorage("completedSetup") private var completedSetup = false
    @State private var addingEffect = false
    @State private var setup = false
    @State private var checkingMicrophone = false
    @State private var screenHeight = NSScreen.main?.visibleFrame.height ?? 900

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                routeSection
                LiveMeterPanel(display: graph.meterDisplay)
                controlsSection
                effectsSection
                if let issue = graph.routeIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                MeterSignalWarning(display: graph.meterDisplay, running: graph.running)
                Text(displayStatus)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(20)
        }
        .frame(width: 720, height: min(650 + CGFloat(min(graph.settings.effects.count, 4)) * 56, max(400, screenHeight - 90)))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            if let window = note.object as? NSWindow, window.identifier?.rawValue == "main",
               let screen = window.screen { screenHeight = screen.visibleFrame.height }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) { ProcessingState(graph: graph).fixedSize() }
            ToolbarItem(placement: .primaryAction) {
                if allowsAudioActions {
                    StartButton(graph: graph).fixedSize()
                } else {
                    Label("Start unavailable", systemImage: "play.fill")
                        .foregroundStyle(.tertiary).padding(.horizontal, 10).fixedSize()
                }
            }
        }
        .task { if showsOnboarding && !completedSetup && !CommandLine.arguments.contains("--probe") { setup = true } }
        .sheet(isPresented: $setup) { OnboardingView(graph: graph, isPresented: $setup, completedSetup: $completedSetup) }
        .sheet(isPresented: $addingEffect) { EffectLibraryView(graph: graph) }
        .sheet(isPresented: $checkingMicrophone) { InputCheckView(graph: graph) }
        .sheet(isPresented: Binding(get: { graph.genericEditorID != nil }, set: { if !$0 { graph.genericEditorID = nil } })) {
            GenericAUControlsView(graph: graph)
        }
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ROUTE").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button("Check Microphone...") { checkingMicrophone = true }
                    .disabled(graph.setupActive)
                    .help("Check your microphone level before effects, without sending audio anywhere.")
                Text(graph.formatDescription).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 12) {
                routePicker(title: "MICROPHONE", icon: "mic", selection: Binding(
                    get: { graph.settings.inputUID }, set: { graph.selectInput($0) }), devices: graph.inputs.filter { !$0.isVirtual })
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                routePicker(title: "PROCESSED OUTPUT", icon: "waveform", selection: Binding(
                    get: { graph.settings.outputUID }, set: { graph.selectOutput($0) }), devices: graph.outputs)
                MonitorButton(graph: graph, allowsMonitoring: allowsAudioActions)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            RouteChannelPickers(graph: graph)
        }
    }

    private func routePicker(title: String, icon: String, selection: Binding<String>, devices: [AudioDevice]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.green).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                Picker(title, selection: selection) {
                    Text("Choose...").tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize(horizontal: false, vertical: true)
                .help("Choose the \(title.lowercased()). Changing the route stops processing.")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsSection: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Gain")
                    Spacer()
                    TextField("Gain", value: gainBinding, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 70)
                        .accessibilityLabel("Gain in decibels")
                        .help("Enter gain from −24 to +12 decibels.")
                    Text("dB").foregroundStyle(.secondary)
                    Button("Reset") { graph.settings.gainDB = 0 }
                        .buttonStyle(.link)
                        .help("Reset gain to 0 decibels.")
                }
                Slider(value: $graph.settings.gainDB, in: -24...12, step: 0.5) {
                    Text("Gain")
                } minimumValueLabel: { Text("−24") } maximumValueLabel: { Text("+12") }
                .help("Adjust the level entering your effects. This cannot repair clipping at the microphone.")
            }
            Divider().frame(height: 80)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("Low cut", isOn: $graph.settings.highPassEnabled)
                        .toggleStyle(.switch)
                        .help("Reduce low-frequency rumble below the selected frequency.")
                    Spacer()
                    Button("Reset") { graph.settings.highPassHz = 80 }
                        .buttonStyle(.link)
                        .help("Reset the low-cut frequency to 80 hertz.")
                }
                HStack {
                    TextField("Low-cut frequency", value: lowCutBinding, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 76)
                        .disabled(!graph.settings.highPassEnabled)
                        .help("Enter a low-cut frequency from 20 to 300 hertz.")
                    Text("Hz").foregroundStyle(.secondary)
                    Stepper("Low-cut frequency", value: $graph.settings.highPassHz, in: 20...300, step: 1)
                        .labelsHidden()
                        .accessibilityLabel("Low-cut frequency")
                        .accessibilityValue("\(Int(graph.settings.highPassHz)) hertz")
                        .accessibilityHint("Adjusts the low-cut frequency by one hertz.")
                        .help("Adjust the low-cut frequency by one hertz.")
                }
            }
            .frame(width: 220)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EFFECTS · TOP TO BOTTOM").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Toggle("Bypass", isOn: $graph.bypass).toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Bypass effects")
                    .accessibilityHint("Bypasses low cut and Audio Unit effects while retaining gain.")
                    .help("Bypass low cut and all Audio Unit effects. Gain remains active.")
            }
            if graph.settings.effects.isEmpty {
                Label("No effects added. Gain and low cut are ready to use.", systemImage: "slider.horizontal.3")
                    .font(.callout).foregroundStyle(.secondary).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    EffectChainView(graph: graph).padding(.horizontal, 14)
                }
                .frame(height: CGFloat(min(graph.settings.effects.count, 4)) * 56 + 20)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }
            HStack {
                Text("Adding, removing or moving an effect briefly pauses audio, then resumes it.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add Effect...") { addingEffect = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(graph.setupActive || graph.loading || graph.settings.effects.count >= 16)
                    .help("Browse registered Audio Unit effects to add to the end of the chain.")
            }
        }
    }

    private var displayStatus: String {
        graph.status == "Choose an input and output, then start." && graph.canStart
            ? "Ready. Press Start to process your microphone." : graph.status
    }

    private var gainBinding: Binding<Double> {
        Binding(get: { graph.settings.gainDB }, set: { value in
            graph.settings.gainDB = value.isFinite ? min(12, max(-24, value)) : 0
        })
    }

    private var lowCutBinding: Binding<Double> {
        Binding(get: { graph.settings.highPassHz }, set: { value in
            graph.settings.highPassHz = value.isFinite ? min(300, max(20, value)) : 80
        })
    }
}

struct ProcessingState: View {
    @ObservedObject var graph: AudioGraph

    var body: some View {
        Label(graph.loading ? "Starting..." : graph.checkingInput ? "Sound check" : graph.running ? (graph.bypass ? "Bypassed" : "Processing") : "Stopped",
              systemImage: graph.running ? "circle.fill" : "circle")
            .labelStyle(.titleAndIcon)
            .font(.callout)
            .foregroundStyle(graph.running ? Color.green : Color.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background((graph.running ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
            .accessibilityIdentifier("processing-state")
    }
}

struct StartButton: View {
    @ObservedObject var graph: AudioGraph
    @State private var confirm = false

    var body: some View {
        Button {
            if graph.running || graph.loading || graph.checkingInput { graph.stop() }
            else if graph.selectedOutput?.isVirtual == false { confirm = true }
            else { Task { await graph.start() } }
        } label: {
            Label(graph.loading ? "Cancel" : (graph.running || graph.checkingInput) ? "Stop" : "Start", systemImage: (graph.running || graph.checkingInput) ? "stop.fill" : "play.fill")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(graph.running ? .red : .accentColor)
        .disabled(graph.setupActive || (!graph.running && !graph.loading && !graph.checkingInput && (!graph.canStart || graph.routeIssue != nil)))
        .help(graph.running || graph.loading || graph.checkingInput ? "Stop processing and save effect state." : "Start the selected processing route.")
        .confirmationDialog("Send microphone audio to \(graph.selectedOutput?.name ?? "this physical output")?", isPresented: $confirm) {
            Button("Start on \(graph.selectedOutput?.name ?? "selected output")") { Task { await graph.start() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Speakers near the microphone can create loud feedback. Use a virtual audio device for calls, or headphones for physical listening.")
        }
    }
}
