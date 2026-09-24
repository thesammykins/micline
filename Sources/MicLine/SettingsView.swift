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
    @State private var setup = false
    @AppStorage("completedSetup") private var completedSetup = false

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(updater: updater)
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }.tag(Pane.general)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button("Run Guided Setup...") { setup = true }.disabled(graph.setupActive)
                    AudioSetupView(graph: graph)
                }.padding(24)
            }
                .tabItem { Label("Audio Setup", systemImage: "waveform") }.tag(Pane.audio)
            AdvancedSettingsView(graph: graph, measuring: $measuring)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }.tag(Pane.advanced)
            AboutSettingsView(updater: updater)
                .tabItem { Label("About", systemImage: "info.circle") }.tag(Pane.about)
        }
        .frame(width: 640, height: 560)
        .sheet(isPresented: $setup) { OnboardingView(graph: graph, isPresented: $setup, completedSetup: $completedSetup) }
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
                    .help("Show or hide MicLine's Dock icon. The menu-bar icon remains available.")
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
                    .help("Periodically check the configured signed update feed.")
                Toggle("Automatically download updates", isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.automaticallyDownloadsUpdates = $0 }))
                    .disabled(updater.availability != .ready || !updater.automaticallyChecksForUpdates)
                    .help("Download available signed updates after an automatic check.")
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MicLine \(appVersion)")
                        Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates...") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                        .help("Check the configured signed update feed now.")
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
    @State private var checkingMicrophone = false

    var body: some View {
        Form {
            Section("Audio Status") {
                HStack {
                    Text(graph.status).textSelection(.enabled)
                    Spacer()
                    Button("Rescan") { graph.refresh() }
                        .help("Refresh audio devices and registered Audio Unit effects.")
                }
                Text(graph.formatDescription).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("Diagnostics") {
                Text("The report excludes device names and identifiers, but device capabilities and Audio Unit codes may still identify your setup. Review it before sharing.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Review Diagnostic Report...") { diagnostics = true }
                    .help("Preview the exact diagnostic JSON before choosing whether to export it.")
            }
            Section("Audio Checks") {
                LabeledContent {
                    Button("Run Check...") { checkingMicrophone = true }
                        .disabled(graph.setupActive || graph.selectedInput == nil)
                        .help("Check only the selected microphone channel. No output device or effects are used.")
                } label: {
                    VStack(alignment: .leading) {
                        Text("Check microphone path")
                        Text("No output device is needed; microphone audio is not saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if graph.running || graph.loading || graph.checkingInput {
                    Button("Stop check or processing") { graph.stop() }
                        .help("Stop the current audio check or processing session.")
                }
                LabeledContent {
                    Button("Measure...") { measuring = true }
                        .disabled(graph.setupActive || graph.running || graph.loading || graph.checkingInput)
                        .help("Open the audible loopback signal-alignment check.")
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
                ForEach(graph.plugins.filter { !$0.hostable }) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.name)
                        Text("\(candidate.format.rawValue) · Unvalidated · Cannot be hosted")
                            .font(.caption).foregroundStyle(.secondary)
                        if let location = candidate.location {
                            Text(location).font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped).padding(.top, 8)
        .sheet(isPresented: $diagnostics) { DiagnosticsView(graph: graph) }
        .sheet(isPresented: $checkingMicrophone) { InputCheckView(graph: graph) }
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
                        Link("Privacy Details...", destination: URL(string: "https://github.com/thesammykins/micline#privacy")!)
                        Link("Acknowledgements...", destination: URL(string: "https://github.com/thesammykins/micline/blob/main/NOTICE")!)
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
    @State private var requestingPermission = false

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
                            Text("Choose...").tag("")
                            ForEach(graph.inputs.filter { !$0.isVirtual }) { Text($0.name).tag($0.uid) }
                        }
                        .labelsHidden().disabled(previewMissing)
                        .help("Choose the physical microphone MicLine processes.")
                    }
                    Divider()
                    deviceRow(title: "PROCESSED OUTPUT", value: graph.selectedOutput?.name ?? "Not selected") {
                        Picker("Processed output", selection: Binding(get: { graph.settings.outputUID }, set: { graph.selectOutput($0) })) {
                            Text("Choose...").tag("")
                            ForEach(graph.outputs) { Text($0.name).tag($0.uid) }
                        }
                        .labelsHidden().disabled(previewMissing)
                        .help("Choose a virtual output for calls, or a physical output for confirmed listening.")
                    }
                    Divider()
                    deviceRow(title: "PHYSICAL MONITOR OUTPUT", value: monitorName) {
                        Picker("Monitor output", selection: $monitorOutputUID) {
                            Text("None").tag("")
                            ForEach(monitorOutputs) { Text($0.name).tag($0.uid) }
                        }
                        .labelsHidden().disabled(previewMissing || graph.loading)
                        .help("Choose an optional physical output. Monitoring remains off until confirmed in the main window.")
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
                    if permission == .notDetermined {
                        HStack {
                            Text("Allow access to check your microphone. This does not start listening.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Allow Microphone") {
                                requestingPermission = true
                                Task {
                                    _ = await AVCaptureDevice.requestAccess(for: .audio)
                                    permission = AVCaptureDevice.authorizationStatus(for: .audio)
                                    requestingPermission = false
                                }
                            }
                            .disabled(requestingPermission || previewMissing)
                        }
                    }
                    if permission == .denied || permission == .restricted {
                        HStack {
                            Text("Allow MicLine in System Settings → Privacy & Security → Microphone.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Privacy Settings...") { openMicrophoneSettings() }
                                .help("Open macOS Microphone privacy settings.")
                        }
                    }
                }.padding(8)
            }
            DisclosureGroup("Need a virtual audio device?") {
                VirtualDeviceGuide(graph: graph)
            }
            Button("Check Devices Again") {
                graph.refresh()
                permission = AVCaptureDevice.authorizationStatus(for: .audio)
            }
            .disabled(previewMissing)
            Text("Physical monitoring follows the main gain and hardware output volume. It is off by default and always requires explicit confirmation in the main window.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission = AVCaptureDevice.authorizationStatus(for: .audio)
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

    private var monitorName: String {
        guard let device = monitorOutputs.first(where: { $0.uid == monitorOutputUID }) else { return "None · Monitor off" }
        return "\(device.name) · \(graph.monitoring ? "Monitor on" : "Monitor off")"
    }

    private var permissionLabel: String {
        switch permission {
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
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
                .help("Register or unregister MicLine as a macOS login item.")
            Text("Opens the app after you sign in.").font(.caption).foregroundStyle(.secondary)
            if status == .requiresApproval {
                Button("Allow in Login Items Settings...") { SMAppService.openSystemSettingsLoginItems() }
                    .help("Open macOS Login Items settings to approve MicLine.")
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
                .help("Automatically start only a saved virtual-output route. Physical monitoring stays off.")
            Text("Uses the saved virtual output only and fails stopped if unavailable. Physical monitoring always stays off.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
