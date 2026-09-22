import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI
import MicLineCore

struct SettingsView: View {
    @ObservedObject var graph: AudioGraph
    @AppStorage("showInDock") private var showInDock = true
    @State private var measuring = false

    var body: some View {
        TabView {
            Form {
                Section {
                    LoginItemToggle()
                    AutomaticProcessingToggle()
                    Toggle("Show MicLine in the Dock", isOn: $showInDock)
                        .onChange(of: showInDock) { _, visible in AppDelegate.setDockVisible(visible) }
                    Text("When hidden, MicLine also leaves Command-Tab. Use the waveform in the menu bar to reopen it. Closing a window does not stop processing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("About MicLine") {
                    Text("A microphone processor for Audio Unit effects.")
                    Text("Processing stays on this Mac. MicLine saves settings, not microphone recordings. Third-party effects run their own code.")
                        .font(.callout).foregroundStyle(.secondary)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }

            ScrollView { AudioSetupView(graph: graph).padding(24) }
                .tabItem { Label("Audio Setup", systemImage: "cable.connector") }

            Form {
                Section("Audio status") {
                    Text(graph.status).textSelection(.enabled)
                    Text(graph.formatDescription).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Rescan devices and effects") { graph.refresh() }
                }
                Section("Diagnostics") {
                    Button("Test microphone with output muted") { Task { await graph.start(mutePhysicalOutput: true) } }
                        .disabled(!graph.canStart || graph.running || graph.loading || graph.routeIssue != nil)
                    if graph.running || graph.loading { Button("Stop test / processing") { graph.stop() } }
                    Button("Check loopback signal alignment…") { measuring = true }.disabled(graph.running || graph.loading)
                    Text("The alignment test plays audible bursts. It measures timestamp-aligned waveform lag, not call-app delivery latency.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Plug-in support") {
                    Text("Audio Units: \(graph.plugins.filter(\.hostable).count) available")
                    Text("VST2 and VST3 hosting is not implemented. Files found on disk are not validated or loaded.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(graph.plugins.filter { !$0.hostable }) { plugin in
                        LabeledContent(plugin.name, value: "\(plugin.format.rawValue) · unsupported")
                    }
                }
            }.formStyle(.grouped).tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 580, height: 500)
        .sheet(isPresented: $measuring) { MeasurementView(graph: graph) }
    }
}

struct AudioSetupView: View {
    @ObservedObject var graph: AudioGraph
    var previewMissing = false
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)

    private var blackHole: AudioDevice? {
        previewMissing ? nil : graph.outputs.first { $0.uid == "BlackHole2ch_UID" && $0.isVirtual && $0.outputChannels == 2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Set up your microphone", systemImage: "mic").font(.title2.bold())
            Text("MicLine filters your voice. BlackHole carries the result to your call or recording app.").foregroundStyle(.secondary)
            LoginItemToggle().disabled(previewMissing)
            AutomaticProcessingToggle().disabled(previewMissing)
            Picker("Microphone", selection: Binding(get: { graph.settings.inputUID }, set: { graph.selectInput($0) })) {
                Text("Choose microphone…").tag("")
                ForEach(graph.inputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
            }.disabled(previewMissing)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(blackHole == nil ? "BlackHole 2ch not detected" : "BlackHole 2ch is ready",
                          systemImage: blackHole == nil ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(blackHole == nil ? Color.orange : Color.green).font(.headline)
                    if let blackHole {
                        Text("Select your microphone in the main window, use BlackHole as the output, then choose BlackHole 2ch as the microphone in your other app.")
                        Button(graph.settings.outputUID == blackHole.uid ? "BlackHole output selected" : "Use BlackHole output") {
                            graph.selectOutput(blackHole.uid)
                        }.disabled(graph.settings.outputUID == blackHole.uid)
                    } else {
                        Text("1. Download and install BlackHole 2ch from its developer.\n2. Follow the installer’s restart instructions.\n3. Reopen MicLine and your audio apps, then check again.")
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Get BlackHole 2ch ↗", destination: URL(string: "https://existential.audio/blackhole/")!)
                    }
                    Button("Check again") { graph.refresh(); permission = AVCaptureDevice.authorizationStatus(for: .audio) }
                        .disabled(previewMissing)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Microphone permission", systemImage: "hand.raised").font(.headline)
                Text(permission == .authorized ? "Allowed. Use Start, or opt in to automatic processing above." : "Starting processing requests access. If access was denied, allow MicLine in System Settings → Privacy & Security → Microphone.")
                Button("Open Microphone Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }.font(.callout)
            DisclosureGroup("Installation and restart details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Follow the installer’s restart prompt. A CoreAudio reload can make a driver available without rebooting in some sessions, but it is not a guaranteed substitute. It interrupts all audio and may end calls. MicLine never reloads CoreAudio automatically. Reopen audio apps afterward; if BlackHole is still missing, restart macOS.")
                    Link("BlackHole installation help ↗", destination: URL(string: "https://github.com/ExistentialAudio/BlackHole/wiki/Installation")!)
                    Text("BlackHole is installed separately from its developer. Its source is GPLv3; vendor binaries have separate terms. MicLine does not bundle or install it and never changes system audio defaults.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct LoginItemToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch MicLine at login", isOn: Binding(
                get: { status == .enabled || status == .requiresApproval },
                set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch { self.error = "Could not change login setting: \(error.localizedDescription)" }
                    status = SMAppService.mainApp.status
                }))
            Text("Open MicLine automatically after you sign in.")
                .font(.caption).foregroundStyle(.secondary)
            if status == .requiresApproval {
                Button("Allow in Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }
}

struct AutomaticProcessingToggle: View {
    @AppStorage("startProcessingOnLaunch") private var enabled = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Start processing when MicLine opens", isOn: $enabled)
            Text("Opens your saved microphone and sends audio to the saved virtual output. Missing devices leave audio stopped. Physical monitoring always requires your confirmation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
