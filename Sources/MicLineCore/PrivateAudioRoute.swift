import AVFoundation
import CoreAudio

// One HAL, two devices: Core Audio owns clock drift correction. Restrict the
// first supported route to input-only mono microphones so aggregate outputs
// cannot accidentally include a microphone's physical monitor/speaker outputs.
final class PrivateAudioRoute {
    let id: AudioDeviceID
    private var microphoneChannel: Int32 = -1
    private let input: AudioDevice
    private let output: AudioDevice

    static func supports(input: AudioDevice, output: AudioDevice) -> Bool {
        !input.isVirtual && input.inputChannels == 1 && input.outputChannels == 0 &&
        output.isVirtual && output.outputChannels == 2 && input.sampleRate == output.sampleRate
    }

    init(input: AudioDevice, output: AudioDevice) throws {
        self.input = input
        self.output = output
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MicLine private route",
            kAudioAggregateDeviceUIDKey: "com.sammy.micline.route.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: input.uid, kAudioSubDeviceDriftCompensationKey: 1,
                 kAudioSubDeviceDriftCompensationQualityKey: kAudioAggregateDriftCompensationHighQuality] as [String: Any],
                [kAudioSubDeviceUIDKey: output.uid, kAudioSubDeviceDriftCompensationKey: 0] as [String: Any]
            ]
        ]
        var device: AudioDeviceID = 0
        let result = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        guard result == noErr else { throw GraphError.message("Could not create private audio route: \(result)") }
        id = device
    }

    deinit { AudioHardwareDestroyAggregateDevice(id) }

    // Fail closed: the first mono source must be the selected physical mic, not
    // the virtual device's loopback inputs. Read back both membership and clocking.
    func verifyDevices() throws {
        let members = try object(id, kAudioAggregateDevicePropertyFullSubDeviceList) as? [String]
        let main = try object(id, kAudioAggregateDevicePropertyMainSubDevice) as? String
        guard members == [input.uid, output.uid], main == output.uid else {
            throw GraphError.message("Private-route device order or clock source differs from the selected route.")
        }
        let active = try subdevices(kAudioAggregateDevicePropertyActiveSubDeviceList)
        var activeUIDs = Set<String>()
        for subdevice in active {
            guard let uid = try object(subdevice, kAudioDevicePropertyDeviceUID) as? String else {
                throw GraphError.message("Private-route subdevice identity is unavailable.")
            }
            activeUIDs.insert(uid)
        }
        let owned = try subdevices(kAudioObjectPropertyOwnedObjects, classID: kAudioSubDeviceClassID)
        var ownedUIDs = Set<String>()
        for subdevice in owned {
            guard let uid = try object(subdevice, kAudioDevicePropertyDeviceUID) as? String else {
                throw GraphError.message("Private-route clock object identity is unavailable.")
            }
            ownedUIDs.insert(uid)
            let drift: UInt32 = try scalar(subdevice, kAudioSubDevicePropertyDriftCompensation, initial: 0)
            guard drift == (uid == input.uid ? 1 : 0) else {
                throw GraphError.message("Private-route clock drift compensation is not configured.")
            }
        }
        let devices = DeviceRegistry.devices()
        guard activeUIDs == Set([input.uid, output.uid]), ownedUIDs == activeUIDs,
              let currentInput = devices.first(where: { $0.uid == input.uid }),
              let currentOutput = devices.first(where: { $0.uid == output.uid }),
              currentInput == input, currentOutput == output,
              Self.supports(input: currentInput, output: currentOutput) else {
            throw GraphError.message("Selected devices changed while configuring the private route.")
        }
        // FullSubDeviceList defines flattened stream order. The verified first
        // subdevice has exactly one input and no output, hence mic offset zero.
        microphoneChannel = 0
    }

    private func subdevices(_ selector: AudioObjectPropertySelector, classID: AudioClassID? = nil) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var filter = classID ?? 0
        let qualifierSize = classID == nil ? 0 : UInt32(MemoryLayout<AudioClassID>.size)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, qualifierSize, &filter, &size) == noErr,
              size == 2 * MemoryLayout<AudioObjectID>.size else {
            throw GraphError.message("Private route requires exactly two available subdevices.")
        }
        var values = [AudioObjectID](repeating: 0, count: 2)
        guard AudioObjectGetPropertyData(id, &address, qualifierSize, &filter, &size, &values) == noErr else {
            throw GraphError.message("Could not read private-route subdevices.")
        }
        return values
    }

    private func scalar<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let result = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard result == noErr, size == MemoryLayout<T>.size else {
            throw GraphError.message("Private-route property \(String(selector, radix: 16)) on device \(device) failed: \(result).")
        }
        return value
    }

    private func object(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> AnyObject? {
        let value: Unmanaged<CFTypeRef>? = try scalar(device, selector, initial: nil as Unmanaged<CFTypeRef>?)
        return value?.takeRetainedValue()
    }

    func configureMicrophone(on unit: AudioUnit?) throws {
        guard let unit else { throw GraphError.message("Private-route audio unit is unavailable.") }
        try verifyDevices()
        // AVAudioEngine owns its client format; the graph connection establishes mono.
        var channel = microphoneChannel
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Input, 1,
            &channel, UInt32(MemoryLayout<Int32>.size))
        guard result == noErr else { throw GraphError.message("Could not isolate microphone channel: \(result)") }
    }

    func verifyMicrophone(on unit: AudioUnit?) throws {
        guard let unit else { throw GraphError.message("Private-route audio unit is unavailable.") }
        try verifyDevices()
        var channel: Int32 = -1
        var size = UInt32(MemoryLayout<Int32>.size)
        let result = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Input, 1, &channel, &size)
        guard result == noErr, size == MemoryLayout<Int32>.size, channel == microphoneChannel else {
            throw GraphError.message("Microphone channel mapping was not preserved; refusing possible loopback feedback.")
        }
    }
}
