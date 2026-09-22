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

    init() {
        let isolated = CommandLine.arguments.contains("--probe") || PresentationFixture.current != nil
        let defaults = isolated ? UserDefaults(suiteName: "com.sammy.micline.presentation")! : .standard
        _graph = StateObject(wrappedValue: AudioGraph(defaults: defaults))
    }

    var body: some Scene {
        Window("MicLine", id: "main") {
            if let fixture {
                PresentationFixtureView(fixture: fixture)
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
        .defaultSize(width: 760, height: 690)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)

        Settings { SettingsRootView(graph: graph) }

        MenuBarExtra("MicLine", systemImage: graph.running ? "waveform.circle.fill" : "waveform.circle") {
            MenuView(graph: graph)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(graph.running ? "●  \(graph.bypass ? "Bypassed" : "Processing")" : "○  Stopped")
            .foregroundStyle(graph.running ? .green : .secondary)
        Text(routeSummary).foregroundStyle(.secondary)
        Divider()
        Button(graph.running || graph.loading ? "Stop Processing" : "Start Processing") {
            if graph.running || graph.loading { graph.stop() }
            else { Task { await graph.start() } }
        }
        .disabled(!graph.running && !graph.loading && (!graph.canStart || graph.routeIssue != nil))
        .keyboardShortcut("s", modifiers: [.command, .shift])
        Divider()
        Button("Open MicLine") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")
        SettingsLink { Text("Settings…") }.keyboardShortcut(",")
        Divider()
        Button("Quit MicLine") {
            graph.stop()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
        Text("Monitor \(graph.monitoring ? "on" : "off") · \(activeEffectCount) effect\(activeEffectCount == 1 ? "" : "s") active")
            .foregroundStyle(.secondary)
    }

    private var routeSummary: String {
        "\(graph.selectedInput?.name ?? "No microphone") → \(graph.selectedOutput?.name ?? "No output")"
    }

    private var activeEffectCount: Int {
        graph.bypass ? 0 : graph.settings.effects.filter { !$0.bypassed }.count
    }
}

struct MainView: View {
    @ObservedObject var graph: AudioGraph
    @AppStorage("completedSetup") private var completedSetup = false
    @State private var addingEffect = false
    @State private var setup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                routeSection
                MeterPanel(input: graph.inputLevel, output: graph.outputLevel)
                controlsSection
                effectsSection
                if let issue = graph.routeIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
                if graph.running && graph.inputFrames > 48_000 && graph.inputLevel.rmsDBFS <= -90 {
                    Label("No microphone signal. If your MacBook lid is closed, open it.", systemImage: "mic.slash")
                        .font(.callout).foregroundStyle(.orange)
                }
                Text(displayStatus)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(24)
        }
        .frame(minWidth: 680, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .automatic) { ProcessingState(graph: graph).fixedSize() }
            ToolbarItem(placement: .primaryAction) { StartButton(graph: graph).fixedSize() }
        }
        .task { if !completedSetup && !CommandLine.arguments.contains("--probe") { setup = true } }
        .sheet(isPresented: $setup) { OnboardingView(graph: graph, isPresented: $setup, completedSetup: $completedSetup) }
        .sheet(isPresented: $addingEffect) { EffectLibraryView(graph: graph) }
        .sheet(isPresented: Binding(get: { graph.genericEditorID != nil }, set: { if !$0 { graph.genericEditorID = nil } })) {
            GenericAUControlsView(graph: graph)
        }
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ROUTE").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(graph.formatDescription).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 12) {
                routePicker(title: "MICROPHONE", icon: "mic", selection: Binding(
                    get: { graph.settings.inputUID }, set: { graph.selectInput($0) }), devices: graph.inputs)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                routePicker(title: "PROCESSED OUTPUT", icon: "waveform", selection: Binding(
                    get: { graph.settings.outputUID }, set: { graph.selectOutput($0) }), devices: graph.outputs)
                MonitorButton(graph: graph)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
        }
    }

    private func routePicker(title: String, icon: String, selection: Binding<String>, devices: [AudioDevice]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.green).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                Picker(title, selection: selection) {
                    Text("Choose…").tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize(horizontal: false, vertical: true)
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
                    TextField("Gain", value: $graph.settings.gainDB, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 70)
                        .accessibilityLabel("Gain in decibels")
                    Text("dB").foregroundStyle(.secondary)
                    Button("Reset") { graph.settings.gainDB = 0 }.buttonStyle(.link)
                }
                Slider(value: $graph.settings.gainDB, in: -24...12, step: 0.5) {
                    Text("Gain")
                } minimumValueLabel: { Text("−24") } maximumValueLabel: { Text("+12") }
            }
            Divider().frame(height: 80)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("Low cut", isOn: $graph.settings.highPassEnabled).toggleStyle(.switch)
                    Spacer()
                    Button("Reset") { graph.settings.highPassHz = 80 }.buttonStyle(.link)
                }
                HStack {
                    TextField("Low-cut frequency", value: $graph.settings.highPassHz, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 76)
                        .disabled(!graph.settings.highPassEnabled)
                    Text("Hz").foregroundStyle(.secondary)
                    Stepper("", value: $graph.settings.highPassHz, in: 20...300, step: 1).labelsHidden()
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
            }
            if graph.settings.effects.isEmpty {
                ContentUnavailableView("No effects added", systemImage: "slider.horizontal.3",
                    description: Text("Gain and low cut work without an Audio Unit."))
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(graph.settings.effects.enumerated()), id: \.element.id) { index, effect in
                        EffectRow(graph: graph, index: index, effect: effect)
                        if index < graph.settings.effects.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }
            HStack {
                Text("Structural changes stop processing before rebuilding the chain.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Add Effect…") { addingEffect = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(graph.loading || graph.settings.effects.count >= 16)
            }
        }
    }

    private var displayStatus: String {
        graph.status == "Choose an input and output, then start." && graph.canStart
            ? "Ready. Press Start to process your microphone." : graph.status
    }
}

struct ProcessingState: View {
    @ObservedObject var graph: AudioGraph

    var body: some View {
        Label(graph.loading ? "Starting…" : graph.running ? (graph.bypass ? "Bypassed" : "Processing") : "Stopped",
              systemImage: graph.running ? "circle.fill" : "circle")
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
            if graph.running || graph.loading { graph.stop() }
            else if graph.selectedOutput?.isVirtual == false { confirm = true }
            else { Task { await graph.start() } }
        } label: {
            Label(graph.loading ? "Cancel" : graph.running ? "Stop" : "Start", systemImage: graph.running ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(graph.running ? .red : .accentColor)
        .disabled(!graph.running && !graph.loading && (!graph.canStart || graph.routeIssue != nil))
        .confirmationDialog("Send microphone audio to \(graph.selectedOutput?.name ?? "this physical output")?", isPresented: $confirm) {
            Button("Start on \(graph.selectedOutput?.name ?? "selected output")") { Task { await graph.start() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Speakers near the microphone can create loud feedback. Use BlackHole for calls, or headphones for physical listening.")
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var graph: AudioGraph
    @Binding var isPresented: Bool
    @Binding var completedSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set up MicLine").font(.largeTitle.bold())
            Text("Choose a microphone and a virtual processed output. MicLine will request microphone access when processing starts.")
                .foregroundStyle(.secondary)
            ScrollView { AudioSetupView(graph: graph) }
            HStack {
                Spacer()
                Button("Continue") {
                    completedSetup = true
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(graph.selectedInput == nil || graph.selectedOutput?.isVirtual != true)
            }
        }
        .padding(28).frame(width: 620, height: 680)
    }
}
