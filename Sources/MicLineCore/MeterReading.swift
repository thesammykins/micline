import Foundation

public enum MeterBand: Sendable {
    case green
    case orange
    case red

    // MicLine headroom policy using EBU's -18 dBFS alignment and -9 dBFS
    // permitted-maximum landmarks; this is not an EBU compliance claim.
    public static func forSamplePeak(_ dbFS: Double) -> MeterBand {
        if dbFS >= -9 { return .red }
        if dbFS >= -18 { return .orange }
        return .green
    }
}

public struct MeterReading: Equatable, Sendable {
    // RMS follows AES17 sine calibration. Peak values are sample peaks, not
    // oversampled true-peak measurements and must not be labelled dBTP.
    public let rmsDBFS: Double
    public let samplePeakDBFS: Double
    public let heldSamplePeakDBFS: Double
    public let clipped: Bool
    public let band: MeterBand

    public init(rmsDBFS: Double, samplePeakDBFS: Double, heldSamplePeakDBFS: Double, clipped: Bool) {
        self.rmsDBFS = rmsDBFS.isFinite ? max(-90, rmsDBFS) : -90
        self.samplePeakDBFS = samplePeakDBFS.isFinite ? max(-90, samplePeakDBFS) : -90
        self.heldSamplePeakDBFS = heldSamplePeakDBFS.isFinite ? max(-90, heldSamplePeakDBFS) : -90
        self.clipped = clipped
        band = .forSamplePeak(self.samplePeakDBFS)
    }

    public static let silence = MeterReading(rmsDBFS: -90, samplePeakDBFS: -90,
        heldSamplePeakDBFS: -90, clipped: false)
}

struct MeterBallistics {
    // IEC 60268-18's 20 dB return in 1.7 seconds, expressed as dB/second.
    static let releaseDBPerSecond = 11.76
    static let holdSeconds = 1.0

    private(set) var reading = MeterReading.silence
    private var holdRemaining = 0.0
    private var clipRemaining = 0.0

    mutating func update(rms: Float, samplePeak: Float, elapsed: Double) -> MeterReading {
        let interval = elapsed.isFinite ? max(0, elapsed) : 0
        let rmsDBFS = LevelMath.rmsDBFS(rms)
        let peakDBFS = LevelMath.samplePeakDBFS(samplePeak)
        let displayedRMS = released(reading.rmsDBFS, toward: rmsDBFS, elapsed: interval)
        let displayedPeak = released(reading.samplePeakDBFS, toward: peakDBFS, elapsed: interval)

        var heldPeak = reading.heldSamplePeakDBFS
        if samplePeak.isFinite, samplePeak > 0, peakDBFS >= heldPeak {
            heldPeak = peakDBFS
            holdRemaining = Self.holdSeconds
        } else {
            let releaseTime = max(0, interval - holdRemaining)
            holdRemaining = max(0, holdRemaining - interval)
            if releaseTime > 0 {
                heldPeak = max(displayedPeak, heldPeak - Self.releaseDBPerSecond * releaseTime)
            }
        }

        var clipped = reading.clipped
        if samplePeak.isFinite, samplePeak >= 1 {
            clipped = true
            clipRemaining = Self.holdSeconds
        } else if clipped {
            if interval > clipRemaining {
                clipped = false
                clipRemaining = 0
            } else {
                clipRemaining -= interval
            }
        }

        reading = MeterReading(rmsDBFS: displayedRMS, samplePeakDBFS: displayedPeak,
            heldSamplePeakDBFS: heldPeak, clipped: clipped)
        return reading
    }

    mutating func reset() {
        reading = .silence
        holdRemaining = 0
        clipRemaining = 0
    }

    private func released(_ current: Double, toward target: Double, elapsed: Double) -> Double {
        guard target < current else { return target }
        return max(target, current - Self.releaseDBPerSecond * elapsed)
    }
}
