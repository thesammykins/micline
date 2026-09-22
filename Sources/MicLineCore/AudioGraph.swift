import AppKit
import AVFoundation
import AudioSupport
import CoreAudio
import Combine
import CoreAudioKit

@MainActor
public final class AudioGraph: ObservableObject {
    @Published public var devices: [AudioDevice] = []
    @Published public var plugins: [PluginRecord] = []
    @Published public var settings: SessionSettings { didSet { save(); applyControls() } }
    @Published public private(set) var running = false
    @Published public private(set) var monitoring = false
    @Published public private(set) var loading = false
    @Published public var bypass = false { didSet { applyControls() } }
    @Published public private(set) var status = "Choose an input and output, then start."
    @Published public private(set) var inputDB: Double = -90
    @Published public private(set) var outputDB: Double = -90
    @Published public private(set) var outputPeak: Float = 0
    @Published public private(set) var inputLevel = MeterReading.silence
    @Published public private(set) var outputLevel = MeterReading.silence
    @Published public private(set) var formatDescription = "Audio is stopped"
    @Published public var genericEditorID: UUID?

    private var engine: AVAudioEngine?
    private var privateRoute: PrivateAudioRoute?
    private var gain: AVAudioMixerNode?
    private var meteredOutput: AVAudioMixerNode?
    private var highPass: AVAudioUnitEQ?
    private var units: [UUID: AVAudioUnit] = [:]
    private var editors: [UUID: NSWindow] = [:]
    private let inputMeter = MeterState()
    private let outputMeter = MeterState()
    private var inputBallistics = MeterBallistics()
    private var outputBallistics = MeterBallistics()
    private var lastMeterPoll = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var generation = 0
    private let defaults: UserDefaults
    private var pollCount = 0
    private var usesDefaultRoute = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "session"), var value = try? JSONDecoder().decode(SessionSettings.self, from: data) {
            value.validate()
            settings = value
        } else { settings = SessionSettings() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    deinit {
        timer?.invalidate()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        meteredOutput?.removeTap(onBus: 0)
    }

    public var inputs: [AudioDevice] { devices.filter { $0.inputChannels > 0 } }
    public var outputs: [AudioDevice] { devices.filter { $0.outputChannels > 0 } }
    public var selectedInput: AudioDevice? { inputs.first { $0.uid == settings.inputUID } }
    public var selectedOutput: AudioDevice? { outputs.first { $0.uid == settings.outputUID } }
    public var canStart: Bool { selectedInput != nil && selectedOutput != nil && !loading }
    public var routeIssue: String? {
        guard let input = selectedInput, let output = selectedOutput else { return nil }
        let direct = DeviceRegistry.supportsRoute(input: input.id, output: output.id,
            defaultInput: DeviceRegistry.defaultDevice(input: true), defaultOutput: DeviceRegistry.defaultDevice(input: false))
        return direct || PrivateAudioRoute.supports(input: input, output: output)
            ? nil : "Choose the current default pair, one duplex device, or an input-only mono microphone and two-channel virtual output at the same sample rate. Other split routes are not supported."
    }
    public var inputFrames: UInt64 { inputMeter.frames }
    public var outputFrames: UInt64 { outputMeter.frames }
    public var parameters: [AUParameter] {
        guard let id = genericEditorID else { return [] }
        return units[id]?.withAUAudioUnit { $0.parameterTree?.allParameters ?? [] } ?? []
    }

    public func refresh() {
        devices = DeviceRegistry.devices()
        plugins = PluginRegistry.scan()
    }

    public func selectInput(_ uid: String) { guard uid != settings.inputUID else { return }; stop(); settings.inputUID = uid }
    public func selectOutput(_ uid: String) { guard uid != settings.outputUID else { return }; stop(); settings.outputUID = uid }

    public func add(_ plugin: PluginRecord) {
        guard plugin.hostable, settings.effects.count < 16 else { return }
        stop()
        settings.effects.append(EffectSelection(pluginID: plugin.id))
        status = "Effect added. Start to load its controls."
    }

    public func remove(_ id: UUID) { stop(); settings.effects.removeAll { $0.id == id } }
    public func move(_ id: UUID, by offset: Int) {
        guard let from = settings.effects.firstIndex(where: { $0.id == id }),
              settings.effects.indices.contains(from + offset) else { return }
        stop()
        settings.effects.swapAt(from, from + offset)
    }

    public func stop(message: String = "Stopped. Your settings are saved.") {
        generation += 1
        loading = false
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            meteredOutput?.removeTap(onBus: 0)
        }
        var stateError: String?
        for i in settings.effects.indices {
            guard let unit = units[settings.effects[i].id] else { continue }
            do {
                if let state = unit.withAUAudioUnit({ $0.fullStateForDocument }) {
                    let data = try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
                    guard data.count <= 1_048_576 else { throw GraphError.message("Plugin state exceeds the 1 MB limit.") }
                    settings.effects[i].state = data
                }
            } catch { stateError = "Effect settings could not be saved: \(error.localizedDescription)" }
        }
        engine = nil
        privateRoute = nil
        gain = nil
        meteredOutput = nil
        highPass = nil
        units.removeAll()
        editors.values.forEach { $0.close() }
        editors.removeAll()
        genericEditorID = nil
        running = false
        monitoring = false
        inputMeter.reset()
        outputMeter.reset()
        inputBallistics.reset()
        outputBallistics.reset()
        inputLevel = .silence
        outputLevel = .silence
        lastMeterPoll = ProcessInfo.processInfo.systemUptime
        inputDB = -90; outputDB = -90; outputPeak = 0
        formatDescription = "Audio is stopped"
        status = stateError ?? message
    }

    public func start(mutePhysicalOutput: Bool = false, referenceCapture: ProbeCapture? = nil) async {
        guard canStart, !running, !Task.isCancelled else { return }
        await startGraph(mutePhysicalOutput: mutePhysicalOutput, referenceCapture: referenceCapture, monitor: nil)
    }

    // The caller must obtain explicit user confirmation for the named physical
    // output immediately before invoking this method because acoustic feedback
    // is possible. Monitoring is never restored by normal start or persistence.
    public func startMonitoring(outputUID: String) async {
        guard !loading, let input = selectedInput, let output = selectedOutput,
              let monitor = devices.first(where: { $0.uid == outputUID }) else {
            status = "The selected monitoring output is unavailable."
            return
        }
        do { _ = try PrivateAudioRoutePlan(input: input, output: output, monitor: monitor) }
        catch { status = error.localizedDescription; return }
        stop(message: "Restarting with monitoring…")
        await startGraph(mutePhysicalOutput: false, referenceCapture: nil, monitor: monitor)
    }

    public func stopMonitoring() {
        guard monitoring || loading else { return }
        stop(message: "Monitoring stopped. Start processing again when ready.")
    }

    private func startGraph(mutePhysicalOutput: Bool, referenceCapture: ProbeCapture?, monitor: AudioDevice?) async {
        guard canStart, !running, !Task.isCancelled else { return }
        if let routeIssue { status = routeIssue; return }
        stop()
        loading = true
        generation += 1
        let token = generation
        status = "Waiting for microphone permission…"
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard token == generation else { return }
        guard !Task.isCancelled else { stop(message: "Start cancelled."); return }
        guard allowed else {
            loading = false
            status = "Microphone access is denied. Enable MicLine in System Settings → Privacy & Security → Microphone."
            return
        }
        guard let input = selectedInput, let output = selectedOutput else { loading = false; return }
        do {
            let defaultInput = DeviceRegistry.defaultDevice(input: true)
            let defaultOutput = DeviceRegistry.defaultDevice(input: false)
            guard (monitor == nil && DeviceRegistry.supportsRoute(input: input.id, output: output.id,
                defaultInput: defaultInput, defaultOutput: defaultOutput)) ||
                PrivateAudioRoute.supports(input: input, output: output) else {
                throw GraphError.message("Audio defaults changed. Choose the current default pair or one duplex device.")
            }
            let graph = AVAudioEngine()
            var route: PrivateAudioRoute?
            // A cancelled AU load can outlive stop(). Keep its aggregate alive
            // until this local engine has been stopped, even before publication.
            defer { withExtendedLifetime(route) { if !graph.isRunning { graph.stop() } } }
            // The default engine can use Apple's private aggregate for the default I/O pair.
            // Reassigning that AUHAL to a one-direction-only device is invalid (-10851).
            usesDefaultRoute = monitor == nil && input.id == defaultInput && output.id == defaultOutput
            if !usesDefaultRoute {
                _ = graph.inputNode
                if input.id != output.id || monitor != nil {
                    let aggregate = try PrivateAudioRoute(input: input, output: output, monitor: monitor)
                    route = aggregate
                    try graph.inputNode.withAudioUnit {
                        try setDevice(aggregate.id, on: $0)
                        try aggregate.configureMicrophone(on: $0)
                    }
                } else {
                    // Set the shared AUHAL once for a same-device duplex route.
                    try graph.outputNode.withAudioUnit { try setDevice(output.id, on: $0) }
                }
            }
            let hardwareFormat = graph.inputNode.inputFormat(forBus: 0)
            guard let format = route == nil ? graph.inputNode.outputFormat(forBus: 0)
                : AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: 1) else {
                throw GraphError.message("Input has no valid mono audio format.")
            }
            guard format.sampleRate > 0, format.channelCount > 0 else { throw GraphError.message("Input has no active audio stream.") }
            let gainNode = AVAudioMixerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            graph.attach(gainNode); graph.attach(eq)
            try graph.connectNode(graph.inputNode, to: gainNode, format: format)
            try graph.connectNode(gainNode, to: eq, format: format)
            var previous: AVAudioNode = eq
            var loaded: [UUID: AVAudioUnit] = [:]
            for selection in settings.effects {
                guard let plugin = plugins.first(where: { $0.id == selection.pluginID }), plugin.hostable else {
                    throw GraphError.message("An effect is missing or unsupported. Remove it before starting.")
                }
                status = "Loading \(plugin.name)…"
                let unit = try await instantiate(plugin.componentDescription)
                guard token == generation else { return }
                try Task.checkCancellation()
                if let data = selection.state {
                    guard let state = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                        throw GraphError.message("Saved plugin state is invalid. Remove and add the effect again.")
                    }
                    unit.withAUAudioUnit { $0.fullStateForDocument = state }
                }
                graph.attach(unit)
                try graph.connectNode(previous, to: unit, format: format)
                loaded[selection.id] = unit
                previous = unit
            }
            let outputMeterNode = AVAudioMixerNode()
            graph.attach(outputMeterNode)
            try graph.connectNode(previous, to: outputMeterNode, format: format)
            try graph.connectNode(outputMeterNode, to: graph.mainMixerNode, format: format)
            if monitor != nil {
                guard let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2) else {
                    throw GraphError.message("Monitoring has no valid stereo client format.")
                }
                try graph.connectNode(graph.mainMixerNode, to: graph.outputNode, format: stereo)
                try graph.outputNode.withAudioUnit { try route?.configureOutputs(on: $0) }
            }
            graph.mainMixerNode.outputVolume = mutePhysicalOutput ? 0 : 1
            let inMeter = inputMeter, outMeter = outputMeter
            try graph.inputNode.installAudioTap(onBus: 0, bufferSize: 256, format: format) { buffer, time in
                inMeter.write(buffer)
                referenceCapture?.write(buffer, time: time)
            }
            try outputMeterNode.installAudioTap(onBus: 0, bufferSize: 256, format: nil) { buffer, _ in
                outMeter.write(buffer)
            }
            engine = graph; privateRoute = route
            gain = gainNode; highPass = eq; units = loaded; meteredOutput = outputMeterNode
            applyControls()
            graph.prepare()
            if let privateRoute {
                try graph.inputNode.withAudioUnit { inputUnit in
                    try graph.outputNode.withAudioUnit { outputUnit in
                        try privateRoute.verifyMaps(inputUnit: inputUnit, outputUnit: outputUnit)
                    }
                }
            }
            try Task.checkCancellation()
            if usesDefaultRoute && (input.id != DeviceRegistry.defaultDevice(input: true) || output.id != DeviceRegistry.defaultDevice(input: false)) {
                throw GraphError.message("Audio defaults changed while loading effects. Check devices and start again.")
            }
            try graph.start()
            running = true; loading = false
            monitoring = monitor != nil
            formatDescription = "\(Int(format.sampleRate)) Hz · input buffer \(input.bufferFrames) frames · \(format.channelCount) ch"
            status = mutePhysicalOutput ? "Diagnostic processing · physical output muted" : monitor.map {
                "Processing to \(output.name) and monitoring on \($0.name). Use headphones to avoid feedback."
            } ?? (output.isVirtual ? "Processing to \(output.name). Verify its loopback input in your call app." : "Monitoring to \(output.name). Use headphones to avoid feedback.")
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: graph, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if self.monitoring, graph.isRunning, let privateRoute = self.privateRoute {
                        do {
                            try graph.inputNode.withAudioUnit { inputUnit in
                                try graph.outputNode.withAudioUnit { outputUnit in
                                    try privateRoute.verifyMaps(inputUnit: inputUnit, outputUnit: outputUnit)
                                }
                            }
                            return
                        } catch {
                            // A genuine route change falls through to the same
                            // fail-closed stop used by every other configuration change.
                        }
                    }
                    self.stop(message: "Audio configuration changed. Check devices and start again.")
                    self.refresh()
                }
            }
        } catch {
            guard token == generation else { return }
            stop(message: "Could not start: \(error.localizedDescription)")
        }
    }

    public func openEditor(_ id: UUID) {
        guard let unit = units[id] else {
            guard !loading, let selection = settings.effects.first(where: { $0.id == id }),
                  let plugin = plugins.first(where: { $0.id == selection.pluginID }), plugin.hostable else { return }
            loading = true
            status = "Loading \(plugin.name) controls…"
            let token = generation
            Task {
                do {
                    let unit = try await instantiate(plugin.componentDescription)
                    guard token == generation else { return }
                    if let data = selection.state, let state = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                        unit.withAUAudioUnit { $0.fullStateForDocument = state }
                    }
                    units[id] = unit
                    loading = false
                    status = "Effect controls loaded. Audio remains stopped."
                    openEditor(id)
                } catch {
                    guard token == generation else { return }
                    loading = false
                    status = "Could not load controls: \(error.localizedDescription)"
                }
            }
            return
        }
        if let window = editors[id] { window.makeKeyAndOrderFront(nil); return }
        unit.withAUAudioUnit { $0.requestViewController { [weak self, weak unit] controller in
            Task { @MainActor in
                guard let self, let unit, self.units[id] === unit else { return }
                guard let controller else { self.genericEditorID = id; return }
                let window = NSWindow(contentViewController: controller)
                window.title = unit.name
                window.styleMask.formUnion([.titled, .closable, .resizable])
                window.setContentSize(NSSize(width: max(480, controller.preferredContentSize.width), height: max(320, controller.preferredContentSize.height)))
                window.isReleasedWhenClosed = false
                self.editors[id] = window
                window.center(); window.makeKeyAndOrderFront(nil)
            }
        } }
    }

    private func applyControls() {
        gain?.outputVolume = Float(pow(10, settings.gainDB / 20))
        highPass?.bands.first?.filterType = .highPass
        highPass?.bands.first?.frequency = Float(settings.highPassHz)
        highPass?.bands.first?.bypass = bypass || !settings.highPassEnabled
        for effect in settings.effects { units[effect.id]?.withAUAudioUnit { $0.shouldBypassEffect = bypass || effect.bypassed } }
    }

    private func poll() {
        let now = ProcessInfo.processInfo.systemUptime
        if running {
            let elapsed = max(0, now - lastMeterPoll)
            inputLevel = inputBallistics.update(rms: inputMeter.rms,
                samplePeak: inputMeter.takePeak(), elapsed: elapsed)
            outputLevel = outputBallistics.update(rms: outputMeter.rms,
                samplePeak: outputMeter.takePeak(), elapsed: elapsed)
            inputDB = inputLevel.rmsDBFS
            outputDB = outputLevel.rmsDBFS
            outputPeak = outputLevel.samplePeakDBFS <= -90
                ? 0 : Float(pow(10, outputLevel.samplePeakDBFS / 20))
        }
        lastMeterPoll = now
        pollCount += 1
        if pollCount % 20 == 0 {
            let updated = DeviceRegistry.devices()
            if running && usesDefaultRoute && (selectedInput?.id != DeviceRegistry.defaultDevice(input: true) || selectedOutput?.id != DeviceRegistry.defaultDevice(input: false)) {
                stop(message: "System audio defaults changed. Check your selected devices and start again.")
            }
            if running && (!updated.contains { $0.uid == settings.inputUID && $0.inputChannels > 0 } || !updated.contains { $0.uid == settings.outputUID && $0.outputChannels > 0 }) {
                stop(message: "A selected device disconnected. Reconnect it or choose another device.")
            }
            if running, let monitorUID = privateRoute?.monitorUID,
               !updated.contains(where: { $0.uid == monitorUID && !$0.isVirtual && $0.outputChannels == 2 }) {
                stop(message: "The monitoring output disconnected. Check devices and start again.")
            }
            if updated != devices { devices = updated }
        }
    }

    private func save() {
        do { defaults.set(try JSONEncoder().encode(settings), forKey: "session") }
        catch { status = "Could not save settings: \(error.localizedDescription)" }
    }

    private func setDevice(_ id: AudioDeviceID, on unit: AudioUnit?) throws {
        guard let unit else { throw GraphError.message("Audio device unit is unavailable.") }
        var current: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let readResult = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size)
        if readResult == noErr && current == id { return }
        var value = id
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &value, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard result == noErr else { throw GraphError.message("Device selection \(id) failed (Core Audio \(result), current \(current), read \(readResult)). This route may require an aggregate device.") }
    }

    private func instantiate(_ description: AudioComponentDescription) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: .loadOutOfProcess) { unit, error in
                if let unit { continuation.resume(returning: unit) }
                else { continuation.resume(throwing: error ?? GraphError.message("Plugin did not load.")) }
            }
        }
    }
}

enum GraphError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
