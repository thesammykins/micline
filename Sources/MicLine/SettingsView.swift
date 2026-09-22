import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI
import MicLineCore
import MicLineUpdater

struct SettingsRootView: View {
    @ObservedObject var graph: AudioGraph
    @StateObject private var updater = MicLineUpdater()

    var body: some View {
        SettingsView(graph: graph, updater: updater)
    }
}

struct SettingsView: View {
    enum Pane: Hashable { case general, audio, advanced, about }

    @ObservedObject var graph: AudioGraph
    @ObservedObject var updater: MicLineUpdater
    @State private var selection: Pane = .general
    @State private var measuring = false

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(updater: updater)
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }.tag(Pane.general)
            ScrollView { AudioSetupView(graph: graph).padding(24) }
                .tabItem { Label("Audio Setup", systemImage: "waveform") }.tag(Pane.audio)
            AdvancedSettingsView(graph: graph, measuring: $measuring)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }.tag(Pane.advanced)
            AboutSettingsView(updater: updater)
                .tabItem { Label("About", systemImage: "info.circle") }.tag(Pane.about)
        }
        .frame(width: 640, height: 560)
        .sheet(isPresented: $measuring) {
            MeasurementView(graph: graph) {
                measuring = false
                selection = .audio
            }
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var updater: MicLineUpdater
    @AppStorage("showInDock") private var showInDock = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show MicLine in the Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, visible in AppDelegate.setDockVisible(visible) }
                Text("The menu-bar icon remains available when the Dock icon is hidden. Closing a window does not stop processing.")
                    .font(.caption).foregroundStyle(.secondary)
                LoginItemToggle()
                AutomaticProcessingToggle()
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }))
                    .disabled(updater.availability != .ready)
                Toggle("Automatically download updates", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.automaticallyDownloadsUpdates = $0 }))
                    .disabled(updater.availability != .ready || !updater.automaticallyChecksForUpdates)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MicLine \(appVersion)")
                        Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped).padding(.top, 8)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var updateStatus: String {
        switch updater.availability {
        case .ready: return "Signed update checking is configured."
        case .unavailable: return "Secure update checking is unavailable in this build."
        }
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject var graph: AudioGraph
    @Binding var measuring: Bool
    @State private var diagnostics = false

    var body: some View {
        Form {
            Section("Audio Status") {
                HStack {
                    Text(graph.status).textSelection(.enabled)
                    Spacer()
                    Button("Rescan") { graph.refresh() }
                }
                Text(graph.formatDescription).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("Diagnostics") {
                Text("Reviewed and sanitized, not anonymous. Device capabilities and public Audio Unit codes can fingerprint a selected setup.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Review Diagnostic Report…") { diagnostics = true }
            }
            Section("Audio Checks") {
                LabeledContent {
                    Button("Run Check…") { Task { await graph.start(mutePhysicalOutput: true) } }
                        .disabled(!graph.canStart || graph.running || graph.loading || graph.routeIssue != nil)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Check microphone path")
                        Text("The physical output stays muted; microphone audio is not saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if graph.running || graph.loading {
                    Button("Stop check or processing") { graph.stop() }
                }
                LabeledContent {
                    Button("Measure…") { measuring = true }.disabled(graph.running || graph.loading)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Check loopback signal alignment")
                        Text("Audible probes; timestamp-aligned waveform lag only, not live delivery latency.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Plug-in Support") {
                Text("Audio Units: \(graph.plugins.filter(\.hostable).count) registered")
                Text("VST2 and VST3 filesystem candidates are unvalidated and cannot be hosted in this version.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding(.top, 8)
        .sheet(isPresented: $diagnostics) { DiagnosticsView(graph: graph) }
    }
}

struct AboutSettingsView: View {
    @ObservedObject var updater: MicLineUpdater

    var body: some View {
        VStack(spacing: 18) {
            if let image = NSApp.applicationIconImage {
                Image(nsImage: image).resizable().frame(width: 96, height: 96)
            } else {
                Image(systemName: "mic.badge.plus").font(.system(size: 64)).frame(width: 96, height: 96)
            }
            Text("MicLine").font(.largeTitle.bold())
            Text("Version \(version) (\(build))").foregroundStyle(.secondary)
            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MicLine processes audio locally without recording it. Only Review Diagnostic Report offers a sanitized JSON preview. Measurement and command-line reports are not sanitized; review them before sharing.")
                    HStack {
                        Link("Privacy Details…", destination: URL(string: "https://github.com/thesammykins/micline#privacy")!)
                        Link("Acknowledgements…", destination: URL(string: "https://github.com/thesammykins/micline/blob/main/NOTICE")!)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Updates") {
                HStack {
                    Text(updater.availability == .ready ? "Secure automatic update checking is configured." : "Secure automatic updates are unavailable until a signed feed is configured.")
                    Spacer()
                }.padding(8)
            }
            Spacer()
            Text("Copyright 2026 Sammykins").foregroundStyle(.secondary)
        }
        .padding(28)
    }

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Development" }
}

struct AudioSetupView: View {
    @ObservedObject var graph: AudioGraph
    var previewMissing = false
    @AppStorage("monitorOutputUID") private var monitorOutputUID = ""
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .audio)

    private var blackHole: AudioDevice? {
        previewMissing ? nil : graph.outputs.first { $0.uid == "BlackHole2ch_UID" && $0.isVirtual && $0.outputChannels == 2 }
    }

    private var monitorOutputs: [AudioDevice] {
        graph.outputs.filter { !$0.isVirtual && $0.outputChannels == 2 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Audio Setup").font(.largeTitle.bold())
            GroupBox {
                VStack(spacing: 0) {
                    deviceRow(title: "MICROPHONE", value: graph.selectedInput?.name ?? "Not selected") {
                        Picker("Microphone", selection: Binding(get: { graph.settings.inputUID }, set: { graph.selectInput($0) })) {
                            Text("Choose…").tag("")
                            ForEach(graph.inputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().disabled(previewMissing)
                    }
                    Divider()
                    deviceRow(title: "VIRTUAL PROCESSED OUTPUT", value: blackHoleStatus) {
                        Picker("Processed output", selection: Binding(get: { graph.settings.outputUID }, set: { graph.selectOutput($0) })) {
                            Text("Choose…").tag("")
                            ForEach(graph.outputs.filter(\.isVirtual)) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().disabled(previewMissing)
                    }
                    Divider()
                    deviceRow(title: "PHYSICAL MONITOR OUTPUT", value: monitorName) {
                        Picker("Monitor output", selection: $monitorOutputUID) {
                            Text("None").tag("")
                            ForEach(monitorOutputs) { Text($0.name).tag($0.uid) }
                        }
                        .labelsHidden().disabled(previewMissing || graph.loading)
                        .onChange(of: monitorOutputUID) { _, _ in
                            if graph.monitoring { graph.stopMonitoring() }
                        }
                    }
                }
            }
            GroupBox {
                VStack(spacing: 12) {
                    HStack {
                        Text("Microphone permission")
                        Spacer()
                        Label(permission == .authorized ? "Allowed" : permissionLabel, systemImage: permission == .authorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(permission == .authorized ? Color.green : Color.orange)
                    }
                    if permission == .denied || permission == .restricted {
                        HStack {
                            Text("Allow MicLine in System Settings → Privacy & Security → Microphone.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Privacy Settings…") { openMicrophoneSettings() }
                        }
                    }
                }.padding(8)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(blackHole == nil ? "BlackHole setup and recovery" : "BlackHole 2ch is ready",
                          systemImage: blackHole == nil ? "questionmark.circle" : "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(blackHole == nil ? Color.orange : Color.green)
                    if blackHole == nil {
                        Text("Install BlackHole 2ch from its developer, follow the installer’s restart guidance, then reopen MicLine and other audio apps. A CoreAudio reload may work in some sessions but interrupts all audio and is not a guaranteed substitute for restart.")
                            .font(.callout)
                    } else {
                        Text("Choose BlackHole 2ch as the microphone in your call or recording app. MicLine never changes system audio defaults.")
                            .font(.callout)
                    }
                    HStack {
                        Link("BlackHole Setup Help…", destination: URL(string: "https://github.com/ExistentialAudio/BlackHole/wiki/Installation")!)
                        Spacer()
                        Button("Check Again") {
                            graph.refresh()
                            permission = AVCaptureDevice.authorizationStatus(for: .audio)
                        }.disabled(previewMissing)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Text("Physical monitoring follows the main gain and hardware output volume. It is off by default and always requires explicit confirmation in the main window.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func deviceRow<Content: View>(title: String, value: String, @ViewBuilder control: () -> Content) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                Text(value).lineLimit(1)
            }
            Spacer()
            control().frame(width: 150)
        }.padding(10)
    }

    private var blackHoleStatus: String {
        if let selected = graph.selectedOutput, selected.isVirtual { return "\(selected.name) · Ready" }
        return blackHole == nil ? "BlackHole 2ch not detected" : "Not selected"
    }

    private var monitorName: String {
        guard let device = monitorOutputs.first(where: { $0.uid == monitorOutputUID }) else { return "None · Monitor off" }
        return "\(device.name) · \(graph.monitoring ? "Monitor on" : "Monitor off")"
    }

    private var permissionLabel: String {
        switch permission {
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Requested when processing starts"
        default: return "Unavailable"
        }
    }

    private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
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
            Text("Opens the app after you sign in.").font(.caption).foregroundStyle(.secondary)
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
            Text("Uses the saved virtual output only and fails stopped if unavailable. Physical monitoring always stays off.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
