import AVFoundation
import AudioSupport

// The only cross-thread state is C11 atomics. A tap retains this owner until teardown.
final class MeterState: @unchecked Sendable {
    private let pointer = ml_meter_create()!
    deinit { ml_meter_destroy(pointer) }
    var rms: Float { ml_meter_rms(pointer) }
    var peak: Float { ml_meter_peak(pointer) }
    var frames: UInt64 { ml_meter_frames(pointer) }
    func reset() { ml_meter_reset(pointer) }
    func write(_ buffer: AVReadOnlyAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32 else { return }
        buffer.withUnsafeAudioBufferList { ml_meter_write_buffers(pointer, $0, UInt32(buffer.frameLength)) }
    }
}
