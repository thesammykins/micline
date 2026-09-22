import AudioSupport
import Foundation
import Testing
@testable import MicLineCore

@Test func meterUsesHottestChannelAndRetainsTransientUntilConsumed() {
    let meter = ml_meter_create()!
    defer { ml_meter_destroy(meter) }
    let hot: [Float] = [1, -1, 1, -1]
    let silent = [Float](repeating: 0, count: 4)
    hot.withUnsafeBufferPointer { hotBuffer in
        silent.withUnsafeBufferPointer { silentBuffer in
            var channels = [hotBuffer.baseAddress, silentBuffer.baseAddress]
            ml_meter_write(meter, &channels, 2, 4)
        }
    }
    #expect(ml_meter_rms(meter) == 1)
    #expect(ml_meter_peak(meter) == 1)

    let quiet = [Float](repeating: 0.01, count: 4)
    quiet.withUnsafeBufferPointer { buffer in
        var channel = buffer.baseAddress
        ml_meter_write(meter, &channel, 1, 4)
    }
    #expect(abs(ml_meter_rms(meter) - 0.01) < 0.000_001)
    #expect(ml_meter_take_peak(meter) == 1)
    #expect(ml_meter_take_peak(meter) == 0)
}

@Test func interleavedMeterUsesHottestChannel() {
    let meter = ml_meter_create()!
    defer { ml_meter_destroy(meter) }
    let samples: [Float] = [1, 0, -1, 0]
    samples.withUnsafeBufferPointer { data in
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
            mDataByteSize: UInt32(data.count * MemoryLayout<Float>.size),
            mData: UnsafeMutableRawPointer(mutating: data.baseAddress)))
        ml_meter_write_buffers(meter, &list, 2)
    }
    #expect(ml_meter_rms(meter) == 1)
    #expect(ml_meter_take_peak(meter) == 1)
}

@Test func meterIgnoresNonfiniteSamplesAndResetClearsAllState() {
    let meter = ml_meter_create()!
    defer { ml_meter_destroy(meter) }
    let samples: [Float] = [.nan, .infinity, -.infinity]
    samples.withUnsafeBufferPointer { buffer in
        var channel = buffer.baseAddress
        ml_meter_write(meter, &channel, 1, 3)
    }
    #expect(ml_meter_rms(meter) == 0)
    #expect(ml_meter_take_peak(meter) == 0)
    #expect(ml_meter_frames(meter) == 3)

    let clipped: [Float] = [1]
    clipped.withUnsafeBufferPointer { buffer in
        var channel = buffer.baseAddress
        ml_meter_write(meter, &channel, 1, 1)
    }
    ml_meter_reset(meter)
    #expect(ml_meter_rms(meter) == 0)
    #expect(ml_meter_take_peak(meter) == 0)
    #expect(ml_meter_frames(meter) == 0)
}

@Test func meterDBFSUsesSamplePeakAndAES17RMSReferences() {
    #expect(LevelMath.samplePeakDBFS(1) == 0)
    #expect(abs(LevelMath.samplePeakDBFS(0.5) + 6.020_599_913) < 0.000_001)
    #expect(abs(LevelMath.rmsDBFS(Float(1 / sqrt(2.0)))) < 0.000_001)
    #expect(abs(LevelMath.rmsDBFS(1) - 3.010_299_957) < 0.000_001)
    #expect(LevelMath.samplePeakDBFS(0) == -90)
    #expect(LevelMath.rmsDBFS(.nan) == -90)
}

@Test func meterBandsUseExplicitHeadroomBoundaries() {
    #expect(MeterBand.forSamplePeak(-18.000_001) == .green)
    #expect(MeterBand.forSamplePeak(-18) == .orange)
    #expect(MeterBand.forSamplePeak(-9.000_001) == .orange)
    #expect(MeterBand.forSamplePeak(-9) == .red)
    #expect(MeterBand.forSamplePeak(0) == .red)
}

@Test func meterBallisticsAttackHoldReleaseAndClipBoundaries() {
    var meter = MeterBallistics()
    var reading = meter.update(rms: Float(1 / sqrt(2.0)), samplePeak: Float(1).nextDown, elapsed: 0.1)
    #expect(abs(reading.rmsDBFS) < 0.000_001)
    #expect(reading.samplePeakDBFS < 0)
    #expect(!reading.clipped)

    reading = meter.update(rms: 1, samplePeak: 1, elapsed: 0.1)
    #expect(abs(reading.rmsDBFS - 3.010_299_957) < 0.000_001)
    #expect(reading.samplePeakDBFS == 0)
    #expect(reading.heldSamplePeakDBFS == 0)
    #expect(reading.clipped)

    reading = meter.update(rms: 0, samplePeak: 0, elapsed: 1.0)
    #expect(abs(reading.rmsDBFS - (3.010_299_957 - 11.76)) < 0.000_001)
    #expect(abs(reading.samplePeakDBFS + 11.76) < 0.000_001)
    #expect(reading.heldSamplePeakDBFS == 0)
    #expect(reading.clipped)

    reading = meter.update(rms: 0, samplePeak: 0, elapsed: 0.1)
    #expect(abs(reading.heldSamplePeakDBFS + 1.176) < 0.000_001)
    #expect(!reading.clipped)

    reading = meter.update(rms: Float(1 / sqrt(2.0)), samplePeak: 0.5, elapsed: 0.1)
    #expect(abs(reading.rmsDBFS) < 0.000_001)
    #expect(abs(reading.samplePeakDBFS + 6.020_599_913) < 0.000_001)

    meter.reset()
    #expect(meter.reading == .silence)
}
