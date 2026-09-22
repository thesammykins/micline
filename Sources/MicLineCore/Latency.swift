import Accelerate
import AVFoundation
import Foundation

public struct TimingSummary: Codable {
    public let count: Int
    public let p50: Double
    public let p95: Double
    public let max: Double
    public init(_ values: [Double]) {
        let sorted = values.sorted()
        count = sorted.count
        func percentile(_ fraction: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[Swift.max(0, Int(ceil(fraction * Double(sorted.count))) - 1)]
        }
        p50 = percentile(0.5); p95 = percentile(0.95); max = sorted.last ?? 0
    }
}

public enum LatencyAnalysis {
    public struct Match: Codable {
        public let lagFrames: Int
        public let correlation: Double
    }

    public struct CorrelationAnalysis {
        public let best: Match?
        public let rejectionReason: String?
        public var accepted: Match? { rejectionReason == nil ? best : nil }
    }

    public static func match(reference: [Float], received: [Float], maximumLag: Int) -> Match? {
        analyze(reference: reference, received: received, maximumLag: maximumLag).accepted
    }

    // Offline only. Reject silence, DC, and competing peaks from periodic sound.
    public static func analyze(reference: [Float], received: [Float], maximumLag: Int) -> CorrelationAnalysis {
        guard reference.count >= 16, received.count >= reference.count, maximumLag >= 0,
              reference.allSatisfy(\.isFinite), received.allSatisfy(\.isFinite) else {
            return CorrelationAnalysis(best: nil, rejectionReason: "Invalid samples or search bounds")
        }
        let count = reference.count
        let limit = min(maximumLag, received.count - count)
        let mean = reference.reduce(0.0) { $0 + Double($1) } / Double(count)
        let centered = reference.map { $0 - Float(mean) }
        var energy: Float = 0
        vDSP_svesq(centered, 1, &energy, vDSP_Length(count))
        guard energy > 0.000001 else { return CorrelationAnalysis(best: nil, rejectionReason: "Reference is silent or DC") }
        var products = [Float](repeating: 0, count: limit + 1)
        vDSP_conv(received, 1, centered, 1, &products, 1, vDSP_Length(limit + 1), vDSP_Length(count))
        var windowEnergy = received.prefix(count).reduce(0.0) { $0 + Double($1) * Double($1) }
        var windowSum = received.prefix(count).reduce(0.0) { $0 + Double($1) }
        var scores = [Double](repeating: 0, count: limit + 1)
        var best: Match?
        for lag in 0...limit {
            if lag > 0 {
                windowEnergy += Double(received[lag + count - 1]) * Double(received[lag + count - 1]) - Double(received[lag - 1]) * Double(received[lag - 1])
                windowSum += Double(received[lag + count - 1]) - Double(received[lag - 1])
            }
            let variance = max(0, windowEnergy - windowSum * windowSum / Double(count))
            let score = Double(products[lag]) / sqrt(max(1e-20, Double(energy) * variance))
            scores[lag] = min(1, max(-1, score))
            if abs(score) > abs(best?.correlation ?? 0) { best = Match(lagFrames: lag, correlation: scores[lag]) }
        }
        guard let best, abs(best.correlation) >= 0.7 else {
            return CorrelationAnalysis(best: best, rejectionReason: "Best correlation magnitude below 0.7")
        }
        // Nearby samples can form one broad peak; a similarly strong separated
        // peak is ambiguous and cannot support a delay claim.
        let exclusion = max(1, count / 16)
        guard !scores.enumerated().contains(where: {
            abs($0.offset - best.lagFrames) > exclusion && abs($0.element) >= abs(best.correlation) * 0.95
        }) else { return CorrelationAnalysis(best: best, rejectionReason: "Competing separated correlation peaks") }
        return CorrelationAnalysis(best: best, rejectionReason: nil)
    }

    public static func probe(frames: Int = 2048, seed: UInt64 = 7) -> [Float] {
        var state = seed
        return (0..<frames).map { i in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let noise: Float = state >> 63 == 0 ? -0.1 : 0.1
            let envelope = sin(.pi * Double(i) / Double(max(1, frames - 1)))
            return noise * Float(envelope)
        }
    }

    public struct OfflineReport: Codable {
        public let scope: String
        public let sampleRate: Double
        public let bufferFrames: UInt32
        public let chain: [String]
        public let renderMilliseconds: TimingSummary
        public let signalDelayFrames: Int?
        public let outputRMS: Double
    }

    // Measures actual Apple DSP in manual rendering, never substitutes for hardware latency.
    public static func offline(highPass: Bool = true, gainDB: Double = 0, frames: UInt32 = 128) throws -> OfflineReport {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let gain = AVAudioMixerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        engine.attach(player); engine.attach(gain); engine.attach(eq)
        try engine.connectNode(player, to: gain, format: format)
        try engine.connectNode(gain, to: eq, format: format)
        try engine.connectNode(eq, to: engine.mainMixerNode, format: format)
        gain.outputVolume = Float(pow(10, gainDB / 20))
        eq.bands[0].filterType = .highPass
        eq.bands[0].frequency = 80
        eq.bands[0].bypass = !highPass
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: frames)
        let signal = probe(frames: 48_000)
        let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(signal.count))!
        source.frameLength = source.frameCapacity
        signal.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: signal.count) }
        player.scheduleBuffer(source, at: nil, options: .loops)
        try engine.start(); try player.playAudio()
        defer { engine.stop() }
        let destination = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        var timings: [Double] = []
        var captured: [Float] = []
        for iteration in 0..<420 {
            let start = DispatchTime.now().uptimeNanoseconds
            let status = try engine.renderOffline(frames, to: destination)
            let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            guard status == .success else { throw GraphError.message("Offline render returned \(status.rawValue)") }
            if iteration >= 20 { timings.append(duration) }
            if captured.count < 8192 {
                captured.append(contentsOf: UnsafeBufferPointer(start: destination.floatChannelData![0], count: Int(destination.frameLength)))
            }
        }
        let sum = captured.reduce(0.0) { $0 + Double($1) * Double($1) }
        return OfflineReport(scope: "OFFLINE DSP ONLY; excludes microphone, HAL, driver and consumer", sampleRate: 48_000,
            bufferFrames: frames, chain: ["gain \(gainDB) dB", highPass ? "Apple EQ high-pass 80 Hz" : "EQ bypass"],
            renderMilliseconds: TimingSummary(timings),
            signalDelayFrames: match(reference: Array(signal.prefix(2048)), received: captured, maximumLag: 2048)?.lagFrames,
            outputRMS: sqrt(sum / Double(captured.count)))
    }
}
