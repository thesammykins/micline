import CoreAudio
import Foundation

public struct AudioDevice: Identifiable, Codable, Hashable {
    public var id: AudioDeviceID
    public var uid: String
    public var name: String
    public var inputChannels: Int
    public var outputChannels: Int
    public var sampleRate: Double
    public var bufferFrames: UInt32
    public var isVirtual: Bool
}

public enum DeviceRegistry {
    // AVAudioEngine's I/O nodes share an AUHAL. Independent devices need a
    // real split-I/O transport; Apple's default pair is its own aggregate.
    public static func supportsRoute(input: AudioDeviceID, output: AudioDeviceID,
                                     defaultInput: AudioDeviceID, defaultOutput: AudioDeviceID) -> Bool {
        input == output || (input == defaultInput && output == defaultOutput)
    }

    public static func defaultDevice(input: Bool) -> AudioDeviceID {
        scalar(AudioObjectID(kAudioObjectSystemObject), input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, fallback: AudioDeviceID(0))
    }

    public static func devices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            guard !uid.hasPrefix("com.sammy.micline.route.") else { return nil }
            let rate: Double = scalar(id, kAudioDevicePropertyNominalSampleRate, fallback: 0)
            let buffer: UInt32 = scalar(id, kAudioDevicePropertyBufferFrameSize, fallback: 0)
            let transport: UInt32 = scalar(id, kAudioDevicePropertyTransportType, fallback: 0)
            return AudioDevice(id: id, uid: uid, name: name,
                inputChannels: channels(id, scope: kAudioDevicePropertyScopeInput),
                outputChannels: channels(id, scope: kAudioDevicePropertyScopeOutput),
                sampleRate: rate, bufferFrames: buffer, isVirtual: transport == kAudioDeviceTransportTypeVirtual)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        guard status == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }

    private static func scalar<T>(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, fallback: T) -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
        return status == noErr ? value : fallback
    }

    private static func channels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
