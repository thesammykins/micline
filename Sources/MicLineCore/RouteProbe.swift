import AVFoundation
import AudioSupport
import Foundation
import CoreAudio

public final class ProbeCapture: @unchecked Sendable {
    private let capture: OpaquePointer
    public let sampleRate: Double
    public init(sampleRate: Double, seconds: Double = 16) throws {
        guard sampleRate >= 8_000, sampleRate <= 96_000, seconds > 0, seconds <= 30,
              let pointer = ml_capture_create(UInt32(sampleRate * seconds), sampleRate) else {
            throw GraphError.message("Capture supports 8–96 kHz and at most 30 seconds.")
        }
        capture = pointer; self.sampleRate = sampleRate
    }
    deinit { ml_capture_destroy(capture) }
    func write(_ buffer: AVReadOnlyAudioPCMBuffer, time: AVAudioTime) {
        guard buffer.format.commonFormat == .pcmFormatFloat32, time.isSampleTimeValid, time.isHostTimeValid else { return }
        buffer.withUnsafeAudioBufferList {
            ml_capture_write(capture, $0, UInt32(buffer.frameLength), AVAudioTime.seconds(forHostTime: time.hostTime), time.sampleTime)
        }
    }
    public var samples: [Float] {
        let count = Int(ml_capture_count(capture))
        return Array(UnsafeBufferPointer(start: ml_capture_samples(capture), count: count))
    }
    public var startSeconds: Double { ml_capture_start(capture) }
    public var discontinuities: UInt32 { ml_capture_discontinuities(capture) }
}

public struct RouteProbeReport: Codable {
    public var scope = "Experimental timestamp-aligned waveform lag: raw microphone → effect chain → separate loopback capture. Audio timestamps are not callback arrival times. NOT delivery or end-to-end latency."
    public var input: AudioDevice
    public var output: AudioDevice
    public var consumer: AudioDevice
    public var stimulusOutput: AudioDevice
    public var settings: SessionSettings
    public var bypassed: Bool
    public var acceptedTrials: Int
    public var rejectedTrials: Int
    public var timestampAlignedLagMilliseconds: TimingSummary
    public var correlations: [Double]
}

@MainActor
public enum RouteProbe {
    public struct IsolationReport: Encodable {
        public let scope = "Digital marker detection control, not a proof of zero leakage. Small leaks below the correlation threshold may be undetected."
        public let virtualMarkerCorrelation: Double
        public let rawMicrophoneRMS: Double
        public let rawBestCorrelation: Double
        public let rawRejectionReason: String?
        public let detectionThreshold = 0.7
        public let markerNotDetectedAboveThreshold: Bool
    }

    // A digital-only marker on both loopback channels must not enter the raw
    // microphone tap. Mute our output to break any possible feedback path.
    public static func verifyIsolation(graph: AudioGraph, consumer: AudioDevice) async throws -> IsolationReport {
        try Task.checkCancellation()
        guard !graph.running, !graph.loading, let input = graph.selectedInput,
              graph.selectedOutput?.uid == consumer.uid, consumer.isVirtual, !input.isVirtual,
              input.sampleRate == consumer.sampleRate else {
            throw GraphError.message("Isolation test requires a stopped physical-mic to virtual-loopback route.")
        }
        let rate = input.sampleRate
        let raw = try ProbeCapture(sampleRate: rate, seconds: 5)
        let received = try ProbeCapture(sampleRate: rate, seconds: 5)
        let reader = AVAudioEngine(), writer = AVAudioEngine()
        let player = AVAudioPlayerNode()
        writer.attach(player)
        defer { graph.stop(); reader.stop(); writer.stop() }
        await graph.start(mutePhysicalOutput: true, referenceCapture: raw)
        try Task.checkCancellation()
        guard graph.running else { throw GraphError.message(graph.status) }
        try reader.inputNode.withAudioUnit { try select(consumer.id, unit: $0) }
        let format = reader.inputNode.outputFormat(forBus: 0)
        try reader.inputNode.installAudioTap(onBus: 0, bufferSize: 256, format: format) { buffer, time in received.write(buffer, time: time) }
        try writer.outputNode.withAudioUnit { try select(consumer.id, unit: $0) }
        let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        try writer.connectNode(player, to: writer.mainMixerNode, format: mono)
        let marker = LatencyAnalysis.probe(frames: 4096, seed: 813)
        let signal = [Float](repeating: 0, count: Int(rate)) + marker + [Float](repeating: 0, count: Int(rate))
        let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: UInt32(signal.count))!
        buffer.frameLength = buffer.frameCapacity
        signal.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: signal.count) }
        try writer.start()
        // Configuring the second HAL client can reconfigure the virtual device.
        // Start its reader only after the writer's format is established.
        try reader.start()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        try player.playAudio()
        try await Task.sleep(for: .seconds(3))
        graph.stop(); reader.stop(); writer.stop()
        let microphone = raw.samples, loopback = received.samples
        let consumerAnalysis = LatencyAnalysis.analyze(reference: marker, received: loopback, maximumLag: loopback.count - marker.count)
        guard raw.discontinuities == 0, received.discontinuities == 0,
              microphone.count > Int(rate * 2), loopback.count > Int(rate * 2),
              let delivered = consumerAnalysis.accepted,
              abs(delivered.correlation) > 0.95 else {
            throw GraphError.message("Isolation control rejected: raw/consumer frames \(microphone.count)/\(loopback.count), gaps \(raw.discontinuities)/\(received.discontinuities), consumer correlation \(consumerAnalysis.best?.correlation ?? 0), \(consumerAnalysis.rejectionReason ?? "below 0.95 control threshold").")
        }
        let rms = sqrt(microphone.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(microphone.count))
        let rawAnalysis = LatencyAnalysis.analyze(reference: marker, received: microphone, maximumLag: microphone.count - marker.count)
        guard rms > 0.00001, let rawBest = rawAnalysis.best, abs(rawBest.correlation) < 0.7 else {
            throw GraphError.message("Microphone isolation control failed: raw capture was silent, invalid, or correlated with the loopback-only marker above threshold.")
        }
        return IsolationReport(virtualMarkerCorrelation: delivered.correlation, rawMicrophoneRMS: rms,
            rawBestCorrelation: rawBest.correlation, rawRejectionReason: rawAnalysis.rejectionReason,
            markerNotDetectedAboveThreshold: true)
    }

    // Deliberate acoustic stimulus, never live microphone monitoring to the speaker.
    // All PCM remains in bounded memory; the returned report contains only metrics.
    public static func run(graph: AudioGraph, consumer: AudioDevice, speaker: AudioDevice) async throws -> RouteProbeReport {
        try await withTaskCancellationHandler {
            try await capture(graph: graph, consumer: consumer, speaker: speaker)
        } onCancel: {
            Task { @MainActor in graph.stop(message: "Measurement cancelled.") }
        }
    }

    private static func capture(graph: AudioGraph, consumer: AudioDevice, speaker: AudioDevice) async throws -> RouteProbeReport {
        try Task.checkCancellation()
        guard !graph.running, !graph.loading, let input = graph.selectedInput, let output = graph.selectedOutput,
              !input.isVirtual, output.isVirtual, consumer.isVirtual, consumer.inputChannels > 0,
              consumer.uid == output.uid,
              !speaker.isVirtual, speaker.outputChannels > 0 else {
            throw GraphError.message("Choose a physical microphone, virtual output, matching virtual consumer input, and physical stimulus output. Stop processing first.")
        }
        if let issue = graph.routeIssue { throw GraphError.message(issue) }
        let rate = input.sampleRate
        guard rate == consumer.sampleRate else { throw GraphError.message("Measurement requires matching microphone and consumer sample rates.") }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw GraphError.message("Microphone permission is required.") }
        try Task.checkCancellation()
        let reference = try ProbeCapture(sampleRate: rate)
        let received = try ProbeCapture(sampleRate: rate)
        let consumerEngine = AVAudioEngine()
        let stimulusEngine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        stimulusEngine.attach(player)
        defer {
            graph.stop()
            consumerEngine.stop(); consumerEngine.inputNode.removeTap(onBus: 0)
            stimulusEngine.stop()
        }
        try consumerEngine.inputNode.withAudioUnit { try select(consumer.id, unit: $0) }
        let captureFormat = consumerEngine.inputNode.outputFormat(forBus: 0)
        guard captureFormat.sampleRate == rate else { throw GraphError.message("Consumer format does not match the measurement rate.") }
        try consumerEngine.inputNode.installAudioTap(onBus: 0, bufferSize: 256, format: captureFormat) { buffer, time in received.write(buffer, time: time) }
        await graph.start(referenceCapture: reference)
        try Task.checkCancellation()
        guard graph.running else { throw GraphError.message(graph.status) }
        try consumerEngine.start()
        try stimulusEngine.outputNode.withAudioUnit { try select(speaker.id, unit: $0) }
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        try stimulusEngine.connectNode(player, to: stimulusEngine.mainMixerNode, format: format)
        try stimulusEngine.start()
        // Distinct deterministic probes with silence between them, peak -26 dBFS.
        var stimulus = [Float](repeating: 0, count: Int(rate))
        let probeSize = 2048
        for trial in 0..<20 {
            stimulus += LatencyAnalysis.probe(frames: probeSize, seed: UInt64(trial + 11)).map { $0 * 0.5 }
            stimulus += [Float](repeating: 0, count: Int(rate / 2) - probeSize)
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(stimulus.count))!
        buffer.frameLength = buffer.frameCapacity
        stimulus.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: stimulus.count) }
        // Queue before play; awaiting the async overload would wait for playback completion.
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        try player.playAudio()
        for _ in 0..<130 {
            try await Task.sleep(for: .milliseconds(100))
            guard graph.running else { throw GraphError.message("Audio route changed or stopped during measurement.") }
        }
        graph.stop(); consumerEngine.stop(); stimulusEngine.stop()
        guard reference.discontinuities == 0, received.discontinuities == 0 else { throw GraphError.message("Capture had discontinuities; reject this run.") }
        let raw = reference.samples, processed = received.samples
        guard raw.count > Int(rate * 10), processed.count > Int(rate * 10) else { throw GraphError.message("Not enough captured audio. Check the loopback route and permissions.") }
        var delays: [Double] = [], correlations: [Double] = []
        // Use raw mic waveform as reference, not generated stimulus: excludes speaker/room delay.
        let epochOffset = Int(((reference.startSeconds - received.startSeconds) * rate).rounded())
        for trial in 0..<20 {
            let regionStart = Int(rate * (1 + Double(trial) * 0.5))
            let regionEnd = min(raw.count - probeSize, regionStart + Int(rate * 0.5))
            guard regionStart < regionEnd else { continue }
            // Pick the highest-energy raw window in each stimulus interval, not its silent tail.
            let start = stride(from: regionStart, to: regionEnd, by: 128).max { left, right in
                raw[left..<(left + probeSize)].reduce(0.0) { $0 + Double($1 * $1) } < raw[right..<(right + probeSize)].reduce(0.0) { $0 + Double($1 * $1) }
            }!
            let window = Array(raw[start..<(start + probeSize)])
            let maximumLag = Int(rate * 0.25)
            let consumerStart = start + epochOffset - maximumLag
            let consumerEnd = consumerStart + probeSize + 2 * maximumLag
            guard consumerStart >= 0, consumerEnd <= processed.count,
                  window.allSatisfy({ abs($0) < 0.99 }),
                  processed[consumerStart..<consumerEnd].allSatisfy({ abs($0) < 0.99 }),
                  let match = LatencyAnalysis.match(reference: window, received: Array(processed[consumerStart..<consumerEnd]), maximumLag: 2 * maximumLag) else { continue }
            delays.append(Double(match.lagFrames - maximumLag) / rate * 1000)
            correlations.append(match.correlation)
        }
        guard delays.count >= 16 else { throw GraphError.message("Only \(delays.count)/20 unique correlations; no waveform-lag result. Check stimulus audibility, periodic noise, loopback routing, nonlinear plugins and clock drift.") }
        return RouteProbeReport(input: input, output: output, consumer: consumer, stimulusOutput: speaker,
            settings: graph.settings, bypassed: graph.bypass, acceptedTrials: delays.count, rejectedTrials: 20 - delays.count,
            timestampAlignedLagMilliseconds: TimingSummary(delays), correlations: correlations)
    }

    private static func select(_ id: AudioDeviceID, unit: AudioUnit?) throws {
        guard let unit else { throw GraphError.message("No audio unit for measurement device.") }
        var value = id
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &value, UInt32(MemoryLayout.size(ofValue: value)))
        guard result == noErr else { throw GraphError.message("Measurement device selection failed: \(result)") }
    }
}
