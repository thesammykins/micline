import AppKit
import SwiftUI
import MicLineCore

@main
struct MicLineApp: App {
    @StateObject private var graph = AudioGraph(defaults: CommandLine.arguments.contains("--probe") ? UserDefaults(suiteName: "com.sammy.micline.probe")! : .standard)
    @State private var didProbe = false
    var body: some Scene {
        Window("MicLine", id: "main") {
            MainView(graph: graph)
                .task {
                    NSApp.activate(ignoringOtherApps: true)
                    if CommandLine.arguments.contains("--probe"), !didProbe {
                        didProbe = true
                        Task { await runProbe(graph) }
                    }
                }
        }
        .defaultSize(width: 1040, height: 820)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        MenuBarExtra("MicLine", systemImage: graph.running ? "waveform.circle.fill" : "waveform.circle") {
            MenuView(graph: graph)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var graph: AudioGraph
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("MicLine", systemImage: "waveform").font(.headline)
                Spacer()
                Text(graph.running ? "LIVE" : "STOPPED").font(.caption).foregroundStyle(graph.running ? .green : .secondary)
            }
            Text(graph.selectedInput?.name ?? "No microphone selected").lineLimit(1)
            LevelMeter(title: "Input", db: graph.inputDB)
            LevelMeter(title: "Output", db: graph.outputDB, peak: graph.outputPeak)
            HStack {
                Text("Gain").font(.caption)
                Slider(value: $graph.settings.gainDB, in: -24...12, step: 0.5).accessibilityLabel("Input gain")
                Text(String(format: "%+.1f dB", graph.settings.gainDB)).font(.caption.monospacedDigit())
            }
            Toggle("Bypass effects", isOn: $graph.bypass)
            HStack {
                StartButton(graph: graph)
                Button("Open MicLine") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            }
            Divider()
            Button("Quit MicLine", role: .destructive) { graph.stop(); NSApp.terminate(nil) }
        }
        .padding(20).frame(width: 320)
    }
}

struct MainView: View {
    @ObservedObject var graph: AudioGraph
    @State private var search = ""
    @State private var measuring = false
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Label("MicLine", systemImage: "waveform.circle.fill").font(.title2.bold())
                Text("YOUR MICROPHONE, REFINED").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Divider()
                Label("Signal chain", systemImage: "slider.horizontal.3").font(.headline).foregroundStyle(.tint)
                Label("Local processing", systemImage: "lock.shield").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Output routing", systemImage: "arrow.triangle.branch").font(.headline)
                    Text("Choose an existing loopback device, then select its input in your call app.").font(.caption).foregroundStyle(.secondary)
                    Text("No virtual driver is installed by MicLine.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text("macOS 27 · Native audio").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24).frame(width: 210).frame(maxHeight: .infinity).background(.thinMaterial)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Signal chain").font(.largeTitle.bold())
                            Text("A clearer voice, from input to output.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        StartButton(graph: graph)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Picker("Microphone", selection: Binding(get: { graph.settings.inputUID }, set: { graph.selectInput($0) })) {
                                    Text("Choose input…").tag("")
                                    ForEach(graph.inputs) { Text($0.name).tag($0.uid) }
                                }.labelsHidden().accessibilityLabel("Microphone input")
                                LevelMeter(title: "Input", db: graph.inputDB)
                            }.padding(8)
                        } label: { Label("Input", systemImage: "mic") }
                        Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 45)
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Picker("Output", selection: Binding(get: { graph.settings.outputUID }, set: { graph.selectOutput($0) })) {
                                    Text("Choose output…").tag("")
                                    ForEach(graph.outputs) { Text($0.name + ($0.isVirtual ? " · Virtual" : "")).tag($0.uid) }
                                }.labelsHidden().accessibilityLabel("Processed output device")
                                LevelMeter(title: "Output", db: graph.outputDB, peak: graph.outputPeak)
                            }.padding(8)
                        } label: { Label("Output", systemImage: "waveform.path") }
                    }
                    if let issue = graph.routeIssue {
                        Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    if graph.running && graph.inputFrames > 48_000 && graph.inputDB <= -90 {
                        Label("No input signal. If using a MacBook’s built-in microphone, open the lid.", systemImage: "mic.slash")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if let output = graph.selectedOutput, !output.isVirtual {
                        Label("Physical output selected. Use headphones to prevent microphone feedback.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    GroupBox {
                        VStack(spacing: 18) {
                            HStack {
                                Label("Input gain", systemImage: "dial.low")
                                Slider(value: $graph.settings.gainDB, in: -24...12, step: 0.5).accessibilityLabel("Input gain")
                                Text(String(format: "%+.1f dB", graph.settings.gainDB)).monospacedDigit().frame(width: 75, alignment: .trailing)
                            }
                            HStack {
                                Toggle("Low cut", isOn: $graph.settings.highPassEnabled).frame(width: 140, alignment: .leading)
                                Slider(value: $graph.settings.highPassHz, in: 20...300, step: 1).accessibilityLabel("Low-cut frequency")
                                    .disabled(!graph.settings.highPassEnabled)
                                Text("\(Int(graph.settings.highPassHz)) Hz").monospacedDigit().frame(width: 75, alignment: .trailing)
                            }
                        }.padding(10)
                    } label: { Text("Voice fundamentals") }
                    HStack {
                        Text("Effects").font(.title2.bold())
                        Text("\(graph.settings.effects.count)").foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Bypass effects", isOn: $graph.bypass).toggleStyle(.switch).controlSize(.small)
                    }
                    if graph.settings.effects.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle").font(.largeTitle).foregroundStyle(.secondary)
                            Text("Make room for your voice").font(.headline)
                            Text("Add an Audio Unit below. Effects run from top to bottom.").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(22).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(graph.settings.effects.enumerated()), id: \.element.id) { index, effect in
                                HStack(spacing: 12) {
                                    Text(String(format: "%02d", index + 1)).monospacedDigit().foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(graph.plugins.first { $0.id == effect.pluginID }?.name ?? "Missing effect").font(.headline)
                                        Text(effect.bypassed || graph.bypass ? "Bypassed" : "Audio Unit").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("Enabled", isOn: Binding(get: { !effect.bypassed }, set: { enabled in
                                        if let i = graph.settings.effects.firstIndex(where: { $0.id == effect.id }) { graph.settings.effects[i].bypassed = !enabled }
                                    })).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel("Enable effect \(index + 1)")
                                    Button { graph.move(effect.id, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move earlier")
                                    Button { graph.move(effect.id, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == graph.settings.effects.count - 1).help("Move later")
                                    Button("Controls") { graph.openEditor(effect.id) }.disabled(graph.loading)
                                    Button { graph.remove(effect.id) } label: { Image(systemName: "minus.circle") }.help("Remove effect")
                                }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    DisclosureGroup("Plugin library · \(graph.plugins.count) entries") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Search installed effects", text: $search).textFieldStyle(.roundedBorder)
                            Text("AU effects are registered with macOS. VST2 / VST3 entries are unvalidated filesystem candidates, not confirmed plugins; their host bridge is not yet integrated.").font(.caption).foregroundStyle(.secondary)
                            ForEach(graph.plugins.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { plugin in
                                HStack {
                                    Text(plugin.name)
                                    Spacer()
                                    Text(plugin.format.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Button(plugin.hostable ? "Add" : "Unvalidated · host unavailable") { graph.add(plugin) }.disabled(!plugin.hostable || graph.loading)
                                }
                            }
                            if graph.plugins.isEmpty { Text("No installed effects found. Low cut and gain still work.").foregroundStyle(.secondary) }
                            Button("Rescan plugins and devices") { graph.refresh() }
                        }.padding(.top, 12)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label(graph.status, systemImage: graph.running ? "checkmark.circle.fill" : "info.circle")
                            .foregroundStyle(graph.running ? Color.green : Color.secondary)
                        Text(graph.formatDescription).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("Latency has not been measured for this route. Effect settings save when processing stops.").font(.caption).foregroundStyle(.secondary)
                        Button("Test microphone with output muted") { Task { await graph.start(mutePhysicalOutput: true) } }
                            .disabled(!graph.canStart || graph.running)
                        Button("Check loopback signal alignment…") { measuring = true }
                            .disabled(graph.running || graph.loading)
                    }
                }.padding(28)
            }
        }
        .frame(minWidth: 930, minHeight: 650)
        .sheet(isPresented: $measuring) { MeasurementView(graph: graph) }
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
        .disabled(!graph.running && !graph.loading && !graph.canStart)
        .confirmationDialog("Send microphone audio to a physical output?", isPresented: $confirm) {
            Button("Start with headphones") { Task { await graph.start() } }
        } message: { Text("Speakers near the microphone can create loud feedback. An existing virtual loopback output is recommended for calls.") }
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
            }.frame(height: 8)
            HStack { Text("−60"); Spacer(); Text("−24"); Spacer(); Text("0") }.font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) RMS level")
        .accessibilityValue(db <= -90 ? "Silent" : "\(Int(db)) decibels full scale")
    }
}
