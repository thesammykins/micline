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
    @Published public private(set) var checkingInput = false
    @Published public private(set) var setupActive = false
    @Published public private(set) var loading = false
    @Published public var bypass = false { didSet { applyControls() } }
    @Published public private(set) var status = "Choose an input and output, then start."
    public let meterDisplay = MeterDisplay()
    public var inputDB: Double { meterDisplay.readings.input.rmsDBFS }
    public var outputDB: Double { meterDisplay.readings.output.rmsDBFS }
    public var outputPeak: Float {
        let peak = meterDisplay.readings.output.samplePeakDBFS
        return peak <= -90 ? 0 : Float(pow(10, peak / 20))
    }
    public var inputLevel: MeterReading { meterDisplay.readings.input }
    public var outputLevel: MeterReading { meterDisplay.readings.output }
    @Published public private(set) var formatDescription = "Audio is stopped"
    @Published public var genericEditorID: UUID?
    public let diagnostics = DiagnosticLog()

    private var engine: AVAudioEngine?
    private var privateRoute: PrivateAudioRoute?
    private var gain: AVAudioMixerNode?
    private var meteredOutput: AVAudioMixerNode?
    private var highPass: AVAudioUnitEQ?
    private var units: [UUID: AVAudioUnit] = [:]
    private var editors: [UUID: NSWindow] = [:]
    private var editorRequests = EditorRequestTracker()
    private let inputMeter = MeterState()
    private let outputMeter = MeterState()
    private var inputBallistics = MeterBallistics()
    private var outputBallistics = MeterBallistics()
    private var lastMeterPoll = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var generation = 0
    private var checkDeadline: Task<Void, Never>?
    private var resumesAfterEffectEdit = false
    private let defaults: UserDefaults
    private let persistsSettings: Bool
    private var deviceScan = DeviceScanSchedule(now: ProcessInfo.processInfo.systemUptime)

    public init(defaults: UserDefaults = .standard, persistsSettings: Bool = true) {
        self.defaults = defaults
        self.persistsSettings = persistsSettings
        if let data = defaults.data(forKey: "session"), var value = try? JSONDecoder().decode(SessionSettings.self, from: data) {
            value.validate()
            settings = value
        } else { settings = SessionSettings() }
        refresh()
        diagnostics.record(.appOpened)
        let meterTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        Self.scheduleMeterTimer(meterTimer)
        timer = meterTimer
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    static func scheduleMeterTimer(_ timer: Timer) {
        RunLoop.main.add(timer, forMode: .common)
        // Event tracking is not guaranteed to be a common mode in every run loop.
        RunLoop.main.add(timer, forMode: .eventTracking)
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
    public var canStart: Bool { selectedInput != nil && selectedOutput != nil && !loading && !checkingInput }
    public var routeIssue: String? {
        guard let input = selectedInput, let output = selectedOutput else { return nil }
        do {
            _ = try PrivateAudioRoutePlan(input: input, output: output, monitor: nil,
                inputChannel: selectedInputChannel, outputChannel: selectedOutputChannel)
            return nil
        } catch { return error.localizedDescription }
    }
    public var selectedInputChannel: Int { settings.inputChannel ?? 0 }
    public var selectedOutputChannel: Int { settings.outputChannel ?? 0 }
    public func canMonitor(on device: AudioDevice) -> Bool {
        guard let input = selectedInput, let output = selectedOutput, output.isVirtual else { return false }
        return (try? PrivateAudioRoutePlan(input: input, output: output, monitor: device,
            inputChannel: selectedInputChannel, outputChannel: selectedOutputChannel)) != nil
    }

    public var inputFrames: UInt64 { inputMeter.frames }
    public var outputFrames: UInt64 { outputMeter.frames }
    public var parameters: [AUParameter] {
        guard let id = genericEditorID else { return [] }
        return units[id]?.withAUAudioUnit { $0.parameterTree?.allParameters ?? [] } ?? []
    }

    public func beginSetup() -> Bool {
        guard !setupActive else { return false }
        // Setup takes ownership of capture; users should not have to stop a call
        // route manually before checking the raw microphone or trying an effect.
        stop()
        setupActive = true
        return true
    }

    public func endSetup() { stop(); setupActive = false }

    public func startSetupOutputCheck() async {
        guard setupActive, selectedOutput?.isVirtual == true, canStart, !running else { return }
        await startGraph(mutePhysicalOutput: false, referenceCapture: nil, monitor: nil,
            checkDuration: .seconds(30), checkMessage: "Output check finished. Start it again if you need more time.")
    }

    public func refresh() {
        devices = DeviceRegistry.devices()
        plugins = PluginRegistry.scan()
    }

    public func diagnosticReport(bundle: Bundle = .main) -> DiagnosticReport {
        let monitorUID = privateRoute?.monitorUID ?? defaults.string(forKey: "monitorOutputUID")
        return DiagnosticReport(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unavailable",
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unavailable",
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            settings: settings, input: selectedInput, output: selectedOutput,
            monitor: devices.first { $0.uid == monitorUID }, plugins: plugins,
            running: running, monitoring: monitoring, events: diagnostics.entries)
    }

    public func selectInput(_ uid: String) { guard uid != settings.inputUID else { return }; stop(); settings.inputUID = uid; settings.inputChannel = 0 }
    public func selectOutput(_ uid: String) { guard uid != settings.outputUID else { return }; stop(); settings.outputUID = uid; settings.outputChannel = 0 }

    public func selectInputChannel(_ channel: Int) {
        guard channel != selectedInputChannel else { return }
        stop(); settings.inputChannel = channel
    }

    public func selectOutputChannel(_ channel: Int) {
        guard channel != selectedOutputChannel else { return }
        stop(); settings.outputChannel = channel
    }

    public func add(_ plugin: PluginRecord) {
        guard !loading, plugin.hostable, settings.effects.count < 16 else { return }
        editEffects { settings.effects.append(EffectSelection(pluginID: plugin.id)) }
        if !loading { status = "Effect added. Choose Controls to edit its settings." }
        diagnostics.record(.effectAdded)
    }

    public func remove(_ id: UUID) {
        guard !loading, settings.effects.contains(where: { $0.id == id }) else { return }
        editEffects { settings.effects.removeAll { $0.id == id } }
        diagnostics.record(.effectRemoved)
    }
    public func move(_ id: UUID, by offset: Int) {
        guard !loading, offset != 0, let from = settings.effects.firstIndex(where: { $0.id == id }),
              settings.effects.indices.contains(from + offset) else { return }
        editEffects {
            var effects = settings.effects
            effects.insert(effects.remove(at: from), at: from + offset)
            settings.effects = effects
        }
        diagnostics.record(.effectReordered)
    }

    // Preserve only the currently active session's route. Explicit Stop, device
    // changes and setup invalidate the generation before a queued restart runs.
    // Bounded checks must never become an unbounded processing session.
    private func editEffects(_ edit: () -> Void) {
        let resume = running && resumesAfterEffectEdit && !setupActive && checkDeadline == nil
        let monitorUID = privateRoute?.monitorUID
        let monitor = monitorUID.flatMap { uid in devices.first { $0.uid == uid } }
        stop()
        edit()
        guard resume else { return }
        guard monitorUID == nil || monitor != nil else {
            status = "The monitoring output is unavailable. Check devices before starting again."
            return
        }
        let token = generation
        loading = true
        status = "Updating effects..."
        Task { [weak self] in
            guard let self, self.generation == token else { return }
            self.loading = false
            await self.startGraph(mutePhysicalOutput: false, referenceCapture: nil, monitor: monitor)
        }
    }

    public func stop(message: String = "Stopped. Your settings are saved.") {
        checkDeadline?.cancel()
        checkDeadline = nil
        resumesAfterEffectEdit = false
        if running || loading || checkingInput { diagnostics.record(.processingStopped) }
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
            } catch {
                diagnostics.record(.stateSaveFailed, code: (error as NSError).code)
                stateError = "Effect settings could not be saved: \(error.localizedDescription)"
            }
        }
        engine = nil
        privateRoute = nil
        gain = nil
        meteredOutput = nil
        highPass = nil
        units.removeAll()
        editors.values.forEach { $0.close() }
        editors.removeAll()
        editorRequests.clear()
        genericEditorID = nil
        running = false
        checkingInput = false
        monitoring = false
        inputMeter.reset()
        outputMeter.reset()
        inputBallistics.reset()
        outputBallistics.reset()
        meterDisplay.update(.silence)
        lastMeterPoll = ProcessInfo.processInfo.systemUptime
        formatDescription = "Audio is stopped"
        status = stateError ?? message
    }

    // A sound check needs only the selected input. Disable output I/O before
    // assigning the device: no virtual driver, effects or physical output are
    // involved, and an input-only microphone never becomes an output device.
    public func startInputCheck() async {
        guard !running, !loading, !checkingInput, !Task.isCancelled,
              let input = selectedInput, !input.isVirtual,
              (0..<input.inputChannels).contains(selectedInputChannel) else { return }
        stop()
        loading = true
        let token = generation
        let channel = Int32(selectedInputChannel)
        status = "Waiting for microphone permission…"
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard token == generation else { return }
        guard allowed, !Task.isCancelled else {
            stop(message: allowed ? "Sound check cancelled." : "Allow microphone access in Privacy & Security → Microphone.")
            return
        }
        let check = AVAudioEngine()
        do {
            try check.inputNode.withAudioUnit { unit in
                guard let unit else { throw GraphError.message("Microphone audio unit is unavailable.") }
                var disabled: UInt32 = 0
                let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Output, 0, &disabled, UInt32(MemoryLayout<UInt32>.size))
                guard result == noErr else { throw GraphError.message("Could not disable output for the sound check: \(result)") }
                try setDevice(input.id, on: unit)
                var map = channel
                guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Input, 1,
                    &map, UInt32(MemoryLayout<Int32>.size)) == noErr else {
                    throw GraphError.message("Could not select the microphone channel.")
                }
            }
            let hardware = check.inputNode.inputFormat(forBus: 0)
            guard hardware.sampleRate > 0,
                  let format = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: 1) else {
                throw GraphError.message("The microphone has no active audio stream.")
            }
            let meter = inputMeter
            try check.inputNode.installAudioTap(onBus: 0, bufferSize: 256, format: format) { buffer, _ in
                meter.write(buffer)
            }
            check.prepare()
            try verifyInputCheck(check, input: input, channel: channel)
            try Task.checkCancellation()
            try check.start()
            engine = check
            checkingInput = true
            loading = false
            formatDescription = "Raw input · \(Int(format.sampleRate)) Hz · Channel \(channel + 1)"
            status = "Listening for your sound check. No output or recording."
            stopCheck(after: .seconds(5), message: "Five-second microphone check finished. Check again when you’re ready.")
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: check, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    // Selecting the HAL device can enqueue a startup notification.
                    // Keep the check only if the running engine still has the exact
                    // input, channel, rate and disabled output that were verified.
                    do {
                        try self.verifyInputCheck(check, input: input, channel: channel)
                        if check.isRunning { return }
                        self.stop(message: "The microphone engine stopped during configuration. Start the sound check again when ready.")
                    } catch {
                        self.stop(message: "Microphone configuration changed: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            check.stop()
            check.inputNode.removeTap(onBus: 0)
            guard token == generation else { return }
            stop(message: "Could not start sound check: \(error.localizedDescription)")
        }
    }

    private func verifyInputCheck(_ check: AVAudioEngine, input: AudioDevice, channel: Int32) throws {
        try check.inputNode.withAudioUnit { unit in
            guard let unit else { throw GraphError.message("Microphone audio unit is unavailable.") }
            var outputEnabled: UInt32 = 1
            var size = UInt32(MemoryLayout<UInt32>.size)
            let result = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output, 0, &outputEnabled, &size)
            var map: Int32 = -1
            var mapSize = UInt32(MemoryLayout<Int32>.size)
            let mapResult = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_ChannelMap,
                kAudioUnitScope_Input, 1, &map, &mapSize)
            var currentDevice: AudioDeviceID = 0
            var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let deviceResult = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &currentDevice, &deviceSize)
            guard deviceResult == noErr, deviceSize == MemoryLayout<AudioDeviceID>.size,
                  result == noErr, size == MemoryLayout<UInt32>.size,
                  mapResult == noErr, mapSize == MemoryLayout<Int32>.size else {
                throw GraphError.message("Could not verify the microphone route. Check the device and try again.")
            }
            guard outputEnabled == 0 else {
                throw GraphError.message("Output became enabled. The input-only check cannot continue.")
            }
            let client = check.inputNode.outputFormat(forBus: 0)
            guard currentDevice == input.id, map == channel,
                  client.channelCount == 1, client.sampleRate == input.sampleRate,
                  DeviceRegistry.devices().contains(input) else {
                throw GraphError.message("The microphone, channel or format changed. Choose the input again.")
            }
        }
    }

    public func start(mutePhysicalOutput: Bool = false, referenceCapture: ProbeCapture? = nil,
                      maximumDuration: Duration? = nil) async {
        guard !setupActive, canStart, !running, !Task.isCancelled else { return }
        await startGraph(mutePhysicalOutput: mutePhysicalOutput, referenceCapture: referenceCapture, monitor: nil,
            checkDuration: maximumDuration)
    }

    private func stopCheck(after duration: Duration, message: String) {
        checkDeadline?.cancel()
        let token = generation
        checkDeadline = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.generation == token else { return }
            self.stop(message: message)
        }
    }

    // The caller must obtain explicit user confirmation for the named physical
    // output immediately before invoking this method because acoustic feedback
    // is possible. Monitoring is never restored by normal start or persistence.
    public func startMonitoring(outputUID: String) async {
        diagnostics.record(.monitoringRequested)
        guard !setupActive, !loading, let input = selectedInput, let output = selectedOutput,
              let monitor = devices.first(where: { $0.uid == outputUID }) else {
            status = "The selected monitoring output is unavailable."
            return
        }
        do { _ = try PrivateAudioRoutePlan(input: input, output: output, monitor: monitor,
            inputChannel: selectedInputChannel, outputChannel: selectedOutputChannel) }
        catch { status = error.localizedDescription; return }
        stop(message: "Restarting with monitoring…")
        await startGraph(mutePhysicalOutput: false, referenceCapture: nil, monitor: monitor)
    }

    public func stopMonitoring() {
        guard monitoring || loading else { return }
        stop(message: "Monitoring stopped. Start processing again when ready.")
    }

    private func startGraph(mutePhysicalOutput: Bool, referenceCapture: ProbeCapture?, monitor: AudioDevice?,
                            checkDuration: Duration? = nil,
                            checkMessage: String = "Preview finished. Listen again when you’re ready.") async {
        guard canStart, !running, !Task.isCancelled else { return }
        if let routeIssue { status = routeIssue; return }
        stop()
        diagnostics.record(.startRequested)
        loading = true
        generation += 1
        let token = generation
        status = "Waiting for microphone permission…"
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard token == generation else { return }
        guard !Task.isCancelled else { stop(message: "Start cancelled."); return }
        guard allowed else {
            loading = false
            diagnostics.record(.permissionDenied)
            status = "Microphone access is denied. Enable MicLine in System Settings → Privacy & Security → Microphone."
            return
        }
        guard let input = selectedInput, let output = selectedOutput else { loading = false; return }
        do {
            let graph = AVAudioEngine()
            // Every route has explicit maps, including a same-device duplex
            // route. Never rely on whichever channels the system defaults expose.
            let route = try PrivateAudioRoute(input: input, output: output, monitor: monitor,
                inputChannel: selectedInputChannel, outputChannel: selectedOutputChannel)
            defer { withExtendedLifetime(route) { if !graph.isRunning { graph.stop() } } }
            _ = graph.inputNode
            try graph.inputNode.withAudioUnit {
                try setDevice(route.id, on: $0)
                try route.configureMicrophone(on: $0)
            }
            let hardwareFormat = graph.inputNode.inputFormat(forBus: 0)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: 1) else {
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
            do {
                guard let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2) else {
                    throw GraphError.message("Monitoring has no valid stereo client format.")
                }
                try graph.connectNode(graph.mainMixerNode, to: graph.outputNode, format: stereo)
                try graph.outputNode.withAudioUnit { try route.configureOutputs(on: $0) }
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
            try graph.start()
            // Measurement sessions must not be restarted as audible routes.
            resumesAfterEffectEdit = !mutePhysicalOutput && referenceCapture == nil && checkDuration == nil
            running = true; loading = false
            if let checkDuration { stopCheck(after: checkDuration, message: checkMessage) }
            monitoring = monitor != nil
            diagnostics.record(.processingStarted)
            formatDescription = "\(Int(format.sampleRate)) Hz · input buffer \(input.bufferFrames) frames · \(format.channelCount) ch"
            status = mutePhysicalOutput ? "Diagnostic processing · physical output muted" : monitor.map {
                "Processing to \(output.name) and monitoring on \($0.name). Use headphones to avoid feedback."
            } ?? (output.isVirtual ? "Processing to \(output.name). Verify its loopback input in your call app." : "Monitoring to \(output.name). Use headphones to avoid feedback.")
            observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: graph, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.diagnostics.record(.configurationChanged)
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
            diagnostics.record(.startFailed, code: (error as NSError).code)
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
        guard let request = editorRequests.begin(id) else { return }
        do {
            try Self.prepareForEditor(unit)
        } catch {
            _ = editorRequests.finish(request, for: id)
            genericEditorID = id
            status = "Native controls could not be prepared. Showing generic controls."
            return
        }
        unit.withAUAudioUnit { $0.requestViewController { [weak self, weak unit] controller in
            Task { @MainActor in
                guard let self, let unit, self.units[id] === unit,
                      self.editorRequests.finish(request, for: id) else { return }
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
        Task { [weak self, weak unit] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, let unit, self.units[id] === unit,
                  self.editorRequests.finish(request, for: id) else { return }
            self.genericEditorID = id
            self.status = "Native controls did not respond. Showing generic controls."
        }
    }

    static func prepareForEditor(_ unit: AVAudioUnit) throws {
        // Detached stopped units have not been prepared by an engine. Native
        // editors can depend on render resources even when no audio is running.
        try unit.withAUAudioUnit {
            if !$0.renderResourcesAllocated { try $0.allocateRenderResources() }
        }
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
        if running || checkingInput {
            let elapsed = max(0, now - lastMeterPoll)
            let input = inputBallistics.update(rms: inputMeter.rms,
                samplePeak: inputMeter.takePeak(), elapsed: elapsed)
            let output = outputBallistics.update(rms: outputMeter.rms,
                samplePeak: outputMeter.takePeak(), elapsed: elapsed)
            meterDisplay.update(MeterReadings(input: input, output: output,
                inputSignalMissing: inputMeter.frames > 48_000 && input.rmsDBFS <= -90))
        }
        lastMeterPoll = now
        if deviceScan.isDue(now: now) {
            let updated = DeviceRegistry.devices()
            if running && (!updated.contains { $0.uid == settings.inputUID && $0.inputChannels > 0 } || !updated.contains { $0.uid == settings.outputUID && $0.outputChannels > 0 }) {
                diagnostics.record(.deviceDisconnected)
                stop(message: "A selected device disconnected. Reconnect it or choose another device.")
            }
            if running, let monitorUID = privateRoute?.monitorUID,
               !updated.contains(where: { $0.uid == monitorUID && !$0.isVirtual && $0.outputChannels == 2 }) {
                diagnostics.record(.deviceDisconnected)
                stop(message: "The monitoring output disconnected. Check devices and start again.")
            }
            if checkingInput && !updated.contains(where: {
                $0.uid == settings.inputUID && $0.inputChannels > selectedInputChannel &&
                $0 == selectedInput
            }) {
                stop(message: "Microphone disconnected or changed. Choose an input and check again.")
            }
            if updated != devices {
                if running, let privateRoute {
                    do { try privateRoute.verifyDevices() }
                    catch { stop(message: "Selected audio topology changed. Check channels and start again.") }
                }
                devices = updated
            }
        }
    }

    private func save() {
        guard persistsSettings else { return }
        do { defaults.set(try JSONEncoder().encode(settings), forKey: "session") }
        catch {
            diagnostics.record(.stateSaveFailed, code: (error as NSError).code)
            status = "Could not save settings: \(error.localizedDescription)"
        }
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
        do {
            return try await withCheckedThrowingContinuation { continuation in
                AVAudioUnit.instantiate(with: description, options: .loadOutOfProcess) { unit, error in
                    if let unit { continuation.resume(returning: unit) }
                    else { continuation.resume(throwing: error ?? GraphError.message("Plugin did not load.")) }
                }
            }
        } catch {
            diagnostics.record(.pluginLoadFailed, code: (error as NSError).code)
            throw error
        }
    }
}

enum GraphError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct EditorRequestTracker {
    private var requests: [UUID: UUID] = [:]

    mutating func begin(_ id: UUID) -> UUID? {
        guard requests[id] == nil else { return nil }
        let request = UUID()
        requests[id] = request
        return request
    }

    mutating func finish(_ request: UUID, for id: UUID) -> Bool {
        guard requests[id] == request else { return false }
        requests[id] = nil
        return true
    }

    mutating func clear() { requests.removeAll() }
}
