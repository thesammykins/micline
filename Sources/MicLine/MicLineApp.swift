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
        // Accessory apps keep their windows and menu-bar item, but leave the Dock
        // and Command-Tab switcher. Never use .prohibited: it would hide our UI.
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
    @StateObject private var graph = AudioGraph(defaults: CommandLine.arguments.contains("--probe") ? UserDefaults(suiteName: "com.sammy.micline.probe")! : .standard)
    @State private var didProbe = false
    @State private var didAttemptStartup = false

    var body: some Scene {
        Window("MicLine", id: "main") {
            if CommandLine.arguments.contains("--preview-missing-blackhole") {
                VStack(alignment: .leading) {
                    Text("Setup preview · simulated missing device").font(.caption).foregroundStyle(.secondary)
                    ScrollView { AudioSetupView(graph: graph, previewMissing: true) }
                }.padding(24).frame(width: 520, height: 600)
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
        .defaultSize(width: 680, height: 570)
        .defaultLaunchBehavior(.presented)
        // A restored closed window can skip its startup task, including the
        // user's automatic-processing opt-in. Present a fresh main scene.
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)

        Settings { SettingsView(graph: graph) }

        MenuBarExtra("MicLine", systemImage: graph.running ? "waveform.circle.fill" : "waveform.circle") {
            MenuView(graph: graph)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MicLine").font(.headline)
                Spacer()
                ProcessingState(graph: graph)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(graph.selectedInput?.name ?? "Choose a microphone", systemImage: "mic")
                Label(graph.selectedOutput?.name ?? "Choose an output", systemImage: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
            }.lineLimit(1).font(.callout)
            LevelMeter(title: "Input", db: graph.inputDB)
            LevelMeter(title: "Output", db: graph.outputDB, peak: graph.outputPeak)
            HStack {
                Text("Gain")
                Slider(value: $graph.settings.gainDB, in: -24...12, step: 0.5).accessibilityLabel("Input gain")
                Text(String(format: "%+.1f dB", graph.settings.gainDB)).monospacedDigit().frame(width: 64)
            }.font(.caption)
            Toggle("Bypass effects", isOn: $graph.bypass)
            if graph.monitoring {
                Label("Monitoring is on", systemImage: "headphones").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                StartButton(graph: graph)
                Spacer()
                Button("Open MicLine") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { graph.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }.padding(20).frame(width: 300)
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
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Microphone", selection: Binding(get: { graph.settings.inputUID }, set: { graph.selectInput($0) })) {
                            Text("Choose microphone…").tag("")
                            ForEach(graph.inputs) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().accessibilityLabel("Microphone input")
                        LevelMeter(title: "Input", db: graph.inputDB)
                    }
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Output", selection: Binding(get: { graph.settings.outputUID }, set: { graph.selectOutput($0) })) {
                            Text("Choose output…").tag("")
                            ForEach(graph.outputs) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().accessibilityLabel("Processed output device")
                        LevelMeter(title: "Output", db: graph.outputDB, peak: graph.outputPeak)
                    }
                }
                if let output = graph.selectedOutput, output.isVirtual {
                    Text("In your call or recording app, choose **\(output.name)** as the microphone.")
                        .font(.callout).foregroundStyle(.secondary)
                } else if graph.selectedOutput != nil {
                    Label("Use headphones to avoid microphone feedback.", systemImage: "headphones")
                        .font(.callout).foregroundStyle(.orange)
                } else {
                    Button("Set up BlackHole output…") { setup = true }.font(.callout)
                }
                if let issue = graph.routeIssue {
                    Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
                if graph.running && graph.inputFrames > 48_000 && graph.inputDB <= -90 {
                    Label("No microphone signal. If your MacBook lid is closed, open it.", systemImage: "mic.slash")
                        .font(.callout).foregroundStyle(.orange)
                }
                GroupBox {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Gain").frame(width: 80, alignment: .leading)
                            Slider(value: $graph.settings.gainDB, in: -24...12, step: 0.5).accessibilityLabel("Input gain")
                            Text(String(format: "%+.1f dB", graph.settings.gainDB)).monospacedDigit().frame(width: 72, alignment: .trailing)
                        }
                        HStack {
                            Toggle("Low cut", isOn: $graph.settings.highPassEnabled).frame(width: 80, alignment: .leading)
                            Slider(value: $graph.settings.highPassHz, in: 20...300, step: 1).accessibilityLabel("Low-cut frequency")
                                .disabled(!graph.settings.highPassEnabled)
                            Text("\(Int(graph.settings.highPassHz)) Hz").monospacedDigit().frame(width: 72, alignment: .trailing)
                        }.help("Reduce low-frequency rumble before the effects chain.")
                    }.padding(6)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Effects").font(.headline)
                        Spacer()
                        Toggle("Bypass", isOn: $graph.bypass).toggleStyle(.switch).controlSize(.small)
                            .accessibilityLabel("Bypass effects")
                        Button { addingEffect = true } label: { Label("Add Effect", systemImage: "plus") }
                            .disabled(graph.loading || graph.settings.effects.count >= 16)
                    }
                    if graph.settings.effects.isEmpty {
                        HStack {
                            Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("No effects added")
                                Text("Gain and low cut work on their own.").font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(graph.settings.effects.enumerated()), id: \.element.id) { index, effect in
                                EffectRow(graph: graph, index: index, effect: effect)
                                if index < graph.settings.effects.count - 1 { Divider() }
                            }
                        }.padding(.horizontal, 12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Effects run top to bottom. Adding, removing or reordering stops processing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                MonitorView(graph: graph)
                Text(graph.status == "Choose an input and output, then start." && graph.canStart
                     ? "Ready. Press Start to process your microphone." : graph.status)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(24)
        }
        .frame(minWidth: 620, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .automatic) { ProcessingState(graph: graph).labelStyle(.titleAndIcon).fixedSize() }
            ToolbarItem(placement: .primaryAction) { StartButton(graph: graph).labelStyle(.titleAndIcon).fixedSize() }
            ToolbarItem { SettingsLink { Image(systemName: "gearshape") }.help("Settings") }
        }
        .task { if !completedSetup && !CommandLine.arguments.contains("--probe") { setup = true } }
        .sheet(isPresented: $setup) {
            VStack(alignment: .leading, spacing: 20) {
                ScrollView { AudioSetupView(graph: graph) }.frame(height: 580)
                HStack {
                    Spacer()
                    Button("Continue") {
                        completedSetup = true
                        setup = false
                        if UserDefaults.standard.bool(forKey: "startProcessingOnLaunch"),
                           graph.selectedOutput?.isVirtual == true, graph.routeIssue == nil {
                            Task { await graph.start() }
                        }
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 520)
        }
        .sheet(isPresented: $addingEffect) { EffectLibraryView(graph: graph) }
        .sheet(isPresented: Binding(get: { graph.genericEditorID != nil }, set: { if !$0 { graph.genericEditorID = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Effect parameters").font(.title2); Spacer(); Button("Done") { graph.genericEditorID = nil } }
                Text("This effect does not provide a native editor.").foregroundStyle(.secondary)
                ScrollView {
                    ForEach(graph.parameters, id: \.address) { parameter in
                        VStack(alignment: .leading) {
                            Text(parameter.displayName)
                            if parameter.maxValue > parameter.minValue {
                                Slider(value: Binding(get: { parameter.value }, set: { parameter.value = $0 }), in: parameter.minValue...parameter.maxValue)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }.padding(24).frame(width: 520, height: 450)
        }
    }
}

struct ProcessingState: View {
    @ObservedObject var graph: AudioGraph
    var body: some View {
        Label(graph.loading ? "Starting…" : graph.running ? (graph.bypass ? "Bypassed" : "Processing") : "Stopped",
              systemImage: graph.running ? "circle.fill" : "circle")
            .font(.callout).foregroundStyle(graph.running ? Color.green : Color.secondary)
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
        .disabled(!graph.running && !graph.loading && (!graph.canStart || graph.routeIssue != nil))
        .confirmationDialog("Send microphone audio to a physical output?", isPresented: $confirm) {
            Button("Start with headphones") { Task { await graph.start() } }
        } message: { Text("Speakers near the microphone can create loud feedback. Use BlackHole for calls, or headphones for monitoring.") }
    }
}

struct LevelMeter: View {
    let title: String
    let db: Double
    var peak: Float = 0
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(db <= -90 ? "−∞ dBFS" : String(format: "%.1f dBFS", db)).monospacedDigit()
                    .foregroundStyle(peak >= 1 ? Color.red : Color.primary)
            }.font(.caption)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(peak >= 1 ? Color.red : Color.green)
                        .frame(width: proxy.size.width * min(1, max(0, (db + 60) / 60)))
                }
            }.frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) RMS level")
        .accessibilityValue(db <= -90 ? "Silent" : "\(Int(db)) decibels full scale")
    }
}
