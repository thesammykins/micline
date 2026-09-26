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
    @StateObject private var menuBar: MenuBarController
    @AppStorage("appearance") private var appearance = "system"
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
        let graph = AudioGraph(defaults: defaults)
        _graph = StateObject(wrappedValue: graph)
        _menuBar = StateObject(wrappedValue: MenuBarController(graph: graph,
            fixture: PresentationFixture.current, defaults: defaults))
    }

    var body: some Scene {
        Window("MicLine", id: "main") {
            Group {
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
                        .onChange(of: appearance, initial: true) { _, value in
                            NSApp.appearance = value == "dark" ? NSAppearance(named: .darkAqua)
                                : value == "light" ? NSAppearance(named: .aqua) : nil
                        }
                        .task {
                            NSApp.activate(ignoringOtherApps: true)
                            if CommandLine.arguments.contains("--probe"), !didProbe {
                                didProbe = true
                                Task { await runProbe(graph) }
                            } else if !CommandLine.arguments.contains("--probe"), !didAttemptStartup {
                                didAttemptStartup = true
                                if UserDefaults.standard.bool(forKey: "completedSetup"),
                                   (UserDefaults.standard.object(forKey: "startProcessingOnLaunch") as? Bool ?? true) {
                                    graph.enableAutomaticProcessing()
                                }
                            }
                        }
                }
            }
            .background(MenuBarActions(controller: menuBar))
        }
        .defaultSize(width: 720, height: 680)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { menuBar.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            Group {
                if fixture == nil { SettingsRootView(graph: graph) }
                else { FixtureSettingsUnavailableView() }
            }
            .background(SettingsWindowRegistration(controller: menuBar))
        }
    }
}

struct MenuView: View {
    @ObservedObject var graph: AudioGraph
    let openMain: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("MicLine").font(.headline); Spacer(); ProcessingState(graph: graph) }
            HStack {
                Image(systemName: "mic").frame(width: 24)
                Picker("Microphone", selection: Binding(get: { graph.settings.inputUID }, set: { graph.selectInput($0) })) {
                    Text("Choose a microphone…").tag("")
                    ForEach(graph.inputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
                }.labelsHidden().help("Choose the microphone to process")
            }
            HStack {
                HStack(spacing: 1) {
                    Image(systemName: "mic")
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .semibold))
                }.frame(width: 24)
                Picker("Processed output", selection: Binding(get: { graph.settings.outputUID }, set: { graph.selectOutput($0) })) {
                    Text("Choose an output…").tag("")
                    ForEach(graph.outputs) { Text($0.name).tag($0.uid) }
                }.labelsHidden().help("Choose where processed audio goes. Physical output requires confirmation.")
            }
            Text("Input \(graph.selectedInputChannel + 1) · \(outputChannels)")
                .font(.caption).foregroundStyle(.secondary)
            MenuOutputMeter(display: graph.meterDisplay)
            HStack {
                StartButton(graph: graph)
                Spacer()
                Toggle(isOn: $graph.bypass) {
                    Text("Bypass\neffects").fixedSize().font(.callout)
                }.toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Bypass effects")
                    .help("Skip low cut and effects. Gain remains active.")
                MonitorButton(graph: graph)
            }
            if let issue = graph.routeIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                Button(action: openMain) {
                    Image(systemName: "macwindow")
                }.help("Open MicLine").accessibilityLabel("Open MicLine")
                Spacer()
                OpenSettingsButton(action: openSettings)
                Button { graph.shutdown(); NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit MicLine and stop microphone access").accessibilityLabel("Quit MicLine")
                    .keyboardShortcut("q")
            }
        }
        .padding(16).frame(width: 360)
    }

    private var outputChannels: String {
        graph.selectedOutput?.outputChannels == 1 ? "Channel 1"
            : "Channels \(graph.selectedOutputChannel + 1)-\(graph.selectedOutputChannel + 2)"
    }
}

struct OpenSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
        }
        .help("Settings")
        .accessibilityLabel("Settings")
    }
}

struct MainView: View {
    @ObservedObject var graph: AudioGraph
    var allowsAudioActions = true
    var showsOnboarding = true
    @AppStorage("completedSetup") private var completedSetup = false
    @AppStorage("compactMode") private var compactMode = false
    @AppStorage("gainControlStyle") private var gainControlStyle = "dial"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addingEffect = false
    @State private var setup = false
    @State private var checkingMicrophone = false
    @State private var screenHeight = NSScreen.main?.visibleFrame.height ?? 900

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if compactMode {
                    Text("\(graph.selectedInput?.name ?? "Choose a microphone") → \(graph.selectedOutput?.name ?? "Choose an output")")
                        .font(.callout).lineLimit(2)
                } else { routeSection }
                LiveMeterPanel(display: graph.meterDisplay)
                if !compactMode {
                    controlsSection.transition(.opacity)
                    effectsSection.transition(.opacity)
                }
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
        .frame(width: 720)
        .frame(minHeight: 340, maxHeight: .infinity, alignment: .top)
        .background(MainWindowSize(height: min(compactMode ? 340 : 670 + CGFloat(min(graph.settings.effects.count, 4)) * 56, max(400, screenHeight - 90)), reduceMotion: reduceMotion))
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 1), value: compactMode)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { note in
            if let window = note.object as? NSWindow, window.identifier?.rawValue == "main",
               let screen = window.screen { screenHeight = screen.visibleFrame.height }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) { ProcessingState(graph: graph).fixedSize() }
            ToolbarItem(placement: .primaryAction) {
                Button { compactMode.toggle() } label: {
                    Image(systemName: compactMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                }
                .help(compactMode ? "Expand controls" : "Compact mode")
                .accessibilityLabel(compactMode ? "Expand controls" : "Compact mode")
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
                Button { checkingMicrophone = true } label: { Image(systemName: "mic.badge.plus") }
                    .accessibilityLabel("Check microphone")
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
                .help("Choose the \(title.lowercased()). A virtual route resumes after the change; physical output requires confirmation.")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsSection: some View {
        HStack(alignment: .top, spacing: 20) {
            HStack(spacing: 12) {
                if gainControlStyle == "dial" {
                    GainDial(value: gainBinding, range: graph.settings.gainRange)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Gain")
                        ControlHelp(title: "Gain", explanation: "Changes the level entering your effects, including background noise. It does not adjust the microphone itself or repair clipping that happened there.")
                        Spacer()
                        Picker("Gain control", selection: $gainControlStyle) {
                            Image(systemName: "dial.low").accessibilityLabel("Dial").tag("dial")
                            Image(systemName: "slider.horizontal.3").accessibilityLabel("Slider").tag("slider")
                        }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 106)
                    }
                    HStack {
                        TextField("Gain", value: gainBinding, format: .number.precision(.fractionLength(1)))
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 70)
                            .monospacedDigit().accessibilityLabel("Gain in decibels")
                            .help("Enter gain within the range configured in Settings.")
                        Text("dB").foregroundStyle(.secondary)
                        Spacer()
                        Button { graph.settings.gainDB = 0 } label: { Image(systemName: "arrow.counterclockwise") }
                            .accessibilityLabel("Reset gain")
                            .buttonStyle(.link).help("Reset gain to 0 decibels.")
                    }
                    if gainControlStyle == "slider" {
                        Slider(value: gainBinding, in: graph.settings.gainRange, step: 0.5) {
                            Text("Gain")
                        } minimumValueLabel: { Text(graph.settings.gainRange.lowerBound, format: .number) }
                          maximumValueLabel: { Text(graph.settings.gainRange.upperBound, format: .number) }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            Divider().frame(height: gainControlStyle == "dial" ? 52 : 76)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LowCutHelp(graph: graph, allowsMonitoring: allowsAudioActions)
                    Toggle("Low cut", isOn: $graph.settings.highPassEnabled)
                        .toggleStyle(.switch)
                        .help("Reduce low-frequency rumble below the selected frequency.")
                    Spacer()
                    Button { graph.settings.highPassHz = 80 } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Reset low cut")
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
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.9), value: gainControlStyle)
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EFFECTS · TOP TO BOTTOM").font(.headline).foregroundStyle(.secondary)
                ControlHelp(title: "Effect order", explanation: "Your voice passes through effects from top to bottom. Try noise reduction, then tone shaping, then gentle compression. EQ before a compressor changes what it reacts to; EQ after it shapes the compressed sound. Neither order is always right. Bypass compares at the same gain, but effects can still change loudness.")
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
                Button { addingEffect = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add effect")
                    .buttonStyle(.borderedProminent)
                    .disabled(graph.setupActive || graph.loading || graph.settings.effects.count >= 16)
                    .help("Browse registered Audio Unit effects to add to the end of the chain.")
            }
        }
    }

    private var displayStatus: String {
        graph.status == "Choose an input and output, then start." && graph.canStart
            ? "Ready. Resume microphone access from the menu bar." : graph.status
    }

    private var gainBinding: Binding<Double> {
        Binding(get: { graph.settings.gainDB }, set: { value in
            graph.settings.gainDB = value.isFinite ? min(graph.settings.gainRange.upperBound, max(graph.settings.gainRange.lowerBound, value)) : 0
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
        Label(graph.loading ? "Starting..." : graph.checkingInput ? "Sound check" : graph.running ? (graph.bypass ? "Bypassed" : "Processing") : graph.wantsProcessing ? "Waiting for audio" : "Paused",
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
            if graph.running || graph.loading || graph.checkingInput || graph.wantsProcessing { graph.pauseProcessing() }
            else if graph.selectedOutput?.isVirtual == false { confirm = true }
            else { Task { await graph.start() } }
        } label: {
            Image(systemName: graph.loading || graph.running || graph.checkingInput || graph.wantsProcessing ? "pause.fill" : "play.fill")
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(graph.wantsProcessing || graph.running ? "Pause microphone" : "Resume microphone")
        .disabled(graph.setupActive || (!graph.wantsProcessing && !graph.running && !graph.loading && !graph.checkingInput && (!graph.canStart || graph.routeIssue != nil)))
        .help(graph.running || graph.loading || graph.checkingInput || graph.wantsProcessing ? "Pause microphone access" : "Resume microphone processing")
        .confirmationDialog("Send microphone audio to \(graph.selectedOutput?.name ?? "this physical output")?", isPresented: $confirm) {
            Button("Start on \(graph.selectedOutput?.name ?? "selected output")") { Task { await graph.start() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Speakers near the microphone can create loud feedback. Use a virtual audio device for calls, or headphones for physical listening.")
        }
    }
}
