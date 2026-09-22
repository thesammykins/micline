import Foundation
import Testing
import AudioSupport
import AVFoundation
@testable import MicLineCore

@Test func meterReadsRMSAndPeakNotAverage() {
    let meter = ml_meter_create()!
    defer { ml_meter_destroy(meter) }
    let samples: [Float] = [-0.5, 0, 1, -0.25]
    samples.withUnsafeBufferPointer { buffer in
        var channel = buffer.baseAddress
        ml_meter_write(meter, &channel, 1, 4)
    }
    #expect(abs(ml_meter_rms(meter) - sqrt(1.3125 / 4)) < 0.00001)
    #expect(ml_meter_peak(meter) == 1)
    ml_meter_reset(meter)
    #expect(ml_meter_rms(meter) == 0)
    samples.withUnsafeBufferPointer { data in
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
            mDataByteSize: UInt32(data.count * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(mutating: data.baseAddress)))
        ml_meter_write_buffers(meter, &list, 2)
    }
    #expect(abs(ml_meter_rms(meter) - sqrt(1.3125 / 4)) < 0.00001)
    #expect(ml_meter_peak(meter) == 1)
    #expect(ml_meter_frames(meter) == 2)
    #expect(LevelMath.decibels(0) == -90)
    #expect(abs(LevelMath.decibels(0.5) + 6.0206) < 0.001)
}

@Test func settingsRoundTripAndBounds() throws {
    var settings = SessionSettings()
    settings.inputUID = "stable-input"
    settings.outputUID = "stable-output"
    settings.gainDB = 45
    settings.highPassHz = 2
    settings.effects = [EffectSelection(pluginID: "first"), EffectSelection(pluginID: "second")]
    settings.effects[1].bypassed = true
    settings.validate()
    #expect(settings.gainDB == 12)
    #expect(settings.highPassHz == 20)
    let restored = try JSONDecoder().decode(SessionSettings.self, from: JSONEncoder().encode(settings))
    #expect(restored == settings)
    #expect(restored.effects.map(\.pluginID) == ["first", "second"])
}

@Test func filesystemCandidatesDistinguishFormatsWithoutLoadingCode() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for path in ["VST/Legacy.vst", "VST3/Vendor/Modern.vst3", "VST3/Ignore.component"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    let plugins = PluginRegistry.scanBundles(roots: [root])
    #expect(plugins.count == 2)
    #expect(Set(plugins.map(\.format)) == Set([.vst2, .vst3]))
    #expect(plugins.allSatisfy { !$0.hostable })
}

@Test func sharedHALRejectsNonDefaultSplitDevices() {
    #expect(DeviceRegistry.supportsRoute(input: 17, output: 29, defaultInput: 17, defaultOutput: 29))
    #expect(DeviceRegistry.supportsRoute(input: 41, output: 41, defaultInput: 17, defaultOutput: 29))
    #expect(!DeviceRegistry.supportsRoute(input: 17, output: 41, defaultInput: 17, defaultOutput: 29))
    #expect(!DeviceRegistry.supportsRoute(input: 41, output: 29, defaultInput: 17, defaultOutput: 29))
    #expect(!DeviceRegistry.supportsRoute(input: 29, output: 17, defaultInput: 17, defaultOutput: 29))
}

@Test func privateRouteRejectsAmbiguousChannelsAndClocks() {
    var mic = AudioDevice(id: 17, uid: "mic", name: "Mic", inputChannels: 1,
        outputChannels: 0, sampleRate: 48_000, bufferFrames: 512, isVirtual: false)
    var loopback = AudioDevice(id: 41, uid: "loopback", name: "Loopback", inputChannels: 2,
        outputChannels: 2, sampleRate: 48_000, bufferFrames: 512, isVirtual: true)
    #expect(PrivateAudioRoute.supports(input: mic, output: loopback))
    #expect(!PrivateAudioRoute.supports(input: loopback, output: mic))
    mic.outputChannels = 2
    #expect(!PrivateAudioRoute.supports(input: mic, output: loopback))
    mic.outputChannels = 0
    mic.inputChannels = 2
    #expect(!PrivateAudioRoute.supports(input: mic, output: loopback))
    mic.inputChannels = 1
    loopback.sampleRate = 44_100
    #expect(!PrivateAudioRoute.supports(input: mic, output: loopback))
    loopback.sampleRate = 48_000
    loopback.isVirtual = false
    #expect(!PrivateAudioRoute.supports(input: mic, output: loopback))
}

@Test func captureBoundsInterleavedChannelAndDetectsGap() throws {
    let capture = try #require(ml_capture_create(5, 48_000))
    defer { ml_capture_destroy(capture) }
    func write(_ samples: [Float], time: Int64) {
        samples.withUnsafeBufferPointer { data in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
                mDataByteSize: UInt32(data.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(mutating: data.baseAddress)))
            ml_capture_write(capture, &list, 3, 1, time)
        }
    }
    write([1, 99, 2, 98, 3, 97], time: 100)
    write([4, 96, 5, 95, 6, 94], time: 104)
    #expect(ml_capture_count(capture) == 5)
    #expect(Array(UnsafeBufferPointer(start: ml_capture_samples(capture), count: 5)) == [1, 2, 3, 4, 5])
    #expect(ml_capture_discontinuities(capture) == 1)
    #expect(ml_capture_start(capture) == 1)
}

@Test func actualDeviceAndAUEnumeration() {
    let devices = DeviceRegistry.devices()
    #expect(Set(devices.map(\.uid)).count == devices.count)
    let plugins = PluginRegistry.scan()
    #expect(plugins.contains { $0.format == .au && $0.name.contains("High") })
}

@Test func correlationFindsAsymmetricDelayAndRejectsSilence() {
    let reference = LatencyAnalysis.probe(frames: 127)
    let received = [Float](repeating: 0, count: 317) + reference.map { $0 * 0.27 } + [Float](repeating: 0, count: 43)
    let match = LatencyAnalysis.match(reference: reference, received: received, maximumLag: 350)
    #expect(match?.lagFrames == 317)
    #expect((match?.correlation ?? 0) > 0.99)
    #expect(LatencyAnalysis.match(reference: reference, received: [Float](repeating: 0, count: 512), maximumLag: 350) == nil)
    #expect(LatencyAnalysis.match(reference: reference, received: received, maximumLag: 300) == nil)
}

@Test func correlationDetectsPolarityInversion() throws {
    let marker = LatencyAnalysis.probe(frames: 127)
    let inverted = [Float](repeating: 0, count: 317) + marker.map { -0.27 * $0 } + [Float](repeating: 0, count: 43)
    let analysis = LatencyAnalysis.analyze(reference: marker, received: inverted, maximumLag: 350)
    let detected = try #require(analysis.accepted)
    #expect(detected.lagFrames == 317)
    #expect(detected.correlation < -0.99)
    #expect(abs(try #require(analysis.best).correlation) >= 0.7)
}

@Test func correlationRejectsDCAndAmbiguousPeriodicMatches() {
    let constant = [Float](repeating: 0.05, count: 127)
    #expect(LatencyAnalysis.match(reference: constant, received: constant + constant, maximumLag: 127) == nil)
    let periodic = (0..<512).map { Float(sin(Double($0) * 2 * .pi / 32)) }
    let ambiguous = LatencyAnalysis.analyze(reference: Array(periodic.prefix(128)), received: periodic, maximumLag: 256)
    #expect(ambiguous.accepted == nil)
    #expect(abs(ambiguous.best?.correlation ?? 0) > 0.99)
    #expect(ambiguous.rejectionReason == "Competing separated correlation peaks")
    let marker = LatencyAnalysis.probe(frames: 127)
    let biased = ([Float](repeating: 0, count: 83) + marker + [Float](repeating: 0, count: 59)).map { $0 + 0.25 }
    #expect(LatencyAnalysis.match(reference: marker, received: biased, maximumLag: 120)?.lagFrames == 83)
}

@Test func statisticsUseNearestRank() {
    let summary = TimingSummary([9, 1, 2, 4, 3, 5, 100, 8, 7, 6])
    #expect(summary.count == 10)
    #expect(summary.p50 == 5)
    #expect(summary.p95 == 100)
    #expect(summary.max == 100)
}

@Test func actualOfflineGraphAppliesGainAndBypass() throws {
    let dry = try LatencyAnalysis.offline(highPass: false)
    let quieter = try LatencyAnalysis.offline(highPass: false, gainDB: -12)
    let louder = try LatencyAnalysis.offline(highPass: false, gainDB: 6)
    #expect(dry.signalDelayFrames == 0)
    #expect(dry.outputRMS > 0)
    #expect(abs(quieter.outputRMS / dry.outputRMS - 0.2511886) < 0.001)
    #expect(abs(louder.outputRMS / dry.outputRMS - 1.9952623) < 0.001)
    #expect(dry.renderMilliseconds.count == 400)
}

@Test func installedAppleAUInstantiatesAndPersistsParameterState() async throws {
    let plugin = try #require(PluginRegistry.scan().first { $0.name == "AUHipass" })
    let unit = try await AVAudioUnit.instantiate(with: plugin.componentDescription, options: .loadOutOfProcess)
    let parameter = try #require(unit.withAUAudioUnit { $0.parameterTree?.allParameters.first })
    parameter.value = parameter.minValue + (parameter.maxValue - parameter.minValue) * 0.37
    let expected = parameter.value
    let state = try #require(unit.withAUAudioUnit { $0.fullStateForDocument })
    let encoded = try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
    let restored = try await AVAudioUnit.instantiate(with: plugin.componentDescription, options: .loadOutOfProcess)
    let decoded = try #require(PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
    restored.withAUAudioUnit { $0.fullStateForDocument = decoded }
    let actual = try #require(restored.withAUAudioUnit { $0.parameterTree?.parameter(withAddress: parameter.address)?.value })
    #expect(abs(actual - expected) < 0.01)
}
