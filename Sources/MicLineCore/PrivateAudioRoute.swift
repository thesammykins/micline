import AVFoundation
import CoreAudio

struct PrivateAudioRoutePlan {
    let monitor: AudioDevice?
    let members: [AudioDevice]
    let memberUIDs: [String]
    let mainUID: String
    let driftByUID: [String: UInt32]
    let microphoneChannel: Int32
    let outputChannelMap: [Int32]

    init(input: AudioDevice, output: AudioDevice, monitor: AudioDevice?,
         inputChannel: Int = 0, outputChannel: Int = 0) throws {
        guard PrivateAudioRoute.supports(input: input, output: output),
              (0..<input.inputChannels).contains(inputChannel),
              outputChannel >= 0, outputChannel < output.outputChannels,
              output.outputChannels == 1 || outputChannel + 1 < output.outputChannels else {
            throw GraphError.message("Choose an available microphone channel and output channel pair.")
        }
        if let monitor {
            guard !monitor.isVirtual, monitor.outputChannels == 2,
                  monitor.sampleRate.isFinite, monitor.sampleRate > 0,
                  monitor.uid != input.uid, monitor.uid != output.uid else {
                throw GraphError.message("Monitoring requires a distinct physical stereo output.")
            }
        }
        self.monitor = monitor
        // A duplex device appears once. Stream offsets include every member's
        // channels, including the microphone interface's unused outputs.
        members = [input] + (input.uid == output.uid ? [] : [output]) + (monitor.map { [$0] } ?? [])
        memberUIDs = members.map(\.uid)
        mainUID = output.uid
        driftByUID = Dictionary(uniqueKeysWithValues: members.map { ($0.uid, $0.uid == output.uid ? 0 : 1) })
        microphoneChannel = Int32(inputChannel)
        let outputOffset = members.prefix { $0.uid != output.uid }.reduce(0) { $0 + $1.outputChannels }
        var map = [Int32](repeating: -1, count: members.reduce(0) { $0 + $1.outputChannels })
        map[outputOffset + outputChannel] = 0
        if output.outputChannels > 1 { map[outputOffset + outputChannel + 1] = 1 }
        if let monitor {
            let monitorOffset = members.prefix { $0.uid != monitor.uid }.reduce(0) { $0 + $1.outputChannels }
            map[monitorOffset] = 0
            map[monitorOffset + 1] = 1
        }
        outputChannelMap = map
    }
}

// One HAL with an optional third output device. Core Audio owns clock drift
// correction; explicit channel maps keep aggregate loopback inputs out of the
// microphone path and make monitoring an opt-in stereo fan-out.
final class PrivateAudioRoute {
    let id: AudioDeviceID
    private let plan: PrivateAudioRoutePlan

    static func supports(input: AudioDevice, output: AudioDevice) -> Bool {
        !input.isVirtual && input.inputChannels > 0 && input.inputChannels <= 256 &&
        input.outputChannels >= 0 && input.outputChannels <= 256 &&
        output.outputChannels > 0 && output.outputChannels <= 256 &&
        input.sampleRate.isFinite && input.sampleRate > 0 &&
        output.sampleRate.isFinite && output.sampleRate > 0
    }

    init(input: AudioDevice, output: AudioDevice, monitor: AudioDevice? = nil,
         inputChannel: Int = 0, outputChannel: Int = 0) throws {
        let plan = try PrivateAudioRoutePlan(input: input, output: output, monitor: monitor,
            inputChannel: inputChannel, outputChannel: outputChannel)
        self.plan = plan
        let subdevices: [[String: Any]] = plan.members.map { device in
            var description: [String: Any] = [
                kAudioSubDeviceUIDKey: device.uid,
                kAudioSubDeviceDriftCompensationKey: plan.driftByUID[device.uid] ?? 0
            ]
            if device.uid != plan.mainUID {
                description[kAudioSubDeviceDriftCompensationQualityKey] = kAudioAggregateDriftCompensationHighQuality
            }
            return description
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MicLine private route",
            kAudioAggregateDeviceUIDKey: "com.sammy.micline.route.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: plan.mainUID,
            kAudioAggregateDeviceSubDeviceListKey: subdevices
        ]
        var device: AudioDeviceID = 0
        let result = AudioHardwareCreateAggregateDevice(description as CFDictionary, &device)
        guard result == noErr else { throw GraphError.message("Could not create private audio route: \(result)") }
        id = device
    }

    deinit { AudioHardwareDestroyAggregateDevice(id) }

    var monitorUID: String? { plan.monitor?.uid }

    // Fail closed: membership order determines flattened channels, while drift
    // properties live on aggregate-owned AudioSubDevice objects.
    func verifyDevices() throws {
        let members = try object(id, kAudioAggregateDevicePropertyFullSubDeviceList) as? [String]
        let main = try object(id, kAudioAggregateDevicePropertyMainSubDevice) as? String
        guard members == plan.memberUIDs, main == plan.mainUID else {
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
            guard let uid = try object(subdevice, kAudioDevicePropertyDeviceUID) as? String,
                  let expectedDrift = plan.driftByUID[uid] else {
                throw GraphError.message("Private-route clock object identity is unavailable.")
            }
            ownedUIDs.insert(uid)
            let drift: UInt32 = try scalar(subdevice, kAudioSubDevicePropertyDriftCompensation, initial: 0)
            guard drift == expectedDrift else {
                throw GraphError.message("Private-route clock drift compensation is not configured.")
            }
        }
        let devices = DeviceRegistry.devices()
        let current = plan.memberUIDs.compactMap { uid in devices.first { $0.uid == uid } }
        guard activeUIDs == Set(plan.memberUIDs), ownedUIDs == activeUIDs,
              current.count == plan.members.count, current == plan.members else {
            throw GraphError.message("Selected devices changed while configuring the private route.")
        }
        let expectedOutputs = plan.members.reduce(0) { $0 + $1.outputChannels }
        let expectedInputs = plan.members.reduce(0) { $0 + $1.inputChannels }
        guard channels(id, scope: kAudioDevicePropertyScopeOutput) == expectedOutputs,
              channels(id, scope: kAudioDevicePropertyScopeInput) == expectedInputs else {
            throw GraphError.message("Private-route output topology differs from the selected devices.")
        }
    }

    func configureMicrophone(on unit: AudioUnit?) throws {
        guard let unit else { throw GraphError.message("Private-route audio unit is unavailable.") }
        try verifyDevices()
        var channel = plan.microphoneChannel
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Input, 1,
            &channel, UInt32(MemoryLayout<Int32>.size))
        guard result == noErr else { throw GraphError.message("Could not isolate microphone channel: \(result)") }
    }

    func configureOutputs(on unit: AudioUnit?) throws {
        let map = plan.outputChannelMap
        guard let unit else { throw GraphError.message("Private-route output audio unit is unavailable.") }
        try verifyDevices()
        let result = map.withUnsafeBytes {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 0,
                $0.baseAddress, UInt32($0.count))
        }
        guard result == noErr else { throw GraphError.message("Could not isolate the selected output channels: \(result)") }
    }

    func verifyMaps(inputUnit: AudioUnit?, outputUnit: AudioUnit?) throws {
        guard let inputUnit else { throw GraphError.message("Private-route input audio unit is unavailable.") }
        try verifyDevices()
        var channel: Int32 = -1
        var inputSize = UInt32(MemoryLayout<Int32>.size)
        let inputResult = AudioUnitGetProperty(inputUnit, kAudioOutputUnitProperty_ChannelMap,
            kAudioUnitScope_Input, 1, &channel, &inputSize)
        guard inputResult == noErr, inputSize == MemoryLayout<Int32>.size,
              channel == plan.microphoneChannel else {
            throw GraphError.message("Microphone channel mapping was not preserved; refusing possible loopback feedback.")
        }
        let expected = plan.outputChannelMap
        guard let outputUnit else { throw GraphError.message("Private-route output audio unit is unavailable.") }
        var actual = [Int32](repeating: -1, count: expected.count)
        var outputSize = UInt32(actual.count * MemoryLayout<Int32>.size)
        let outputResult = actual.withUnsafeMutableBytes {
            AudioUnitGetProperty(outputUnit, kAudioOutputUnitProperty_ChannelMap,
                kAudioUnitScope_Output, 0, $0.baseAddress!, &outputSize)
        }
        guard outputResult == noErr, outputSize == actual.count * MemoryLayout<Int32>.size,
              actual == expected else {
            throw GraphError.message("Output channel mapping was not preserved; refusing to start.")
        }
    }

    private func subdevices(_ selector: AudioObjectPropertySelector, classID: AudioClassID? = nil) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var filter = classID ?? 0
        let qualifierSize = classID == nil ? 0 : UInt32(MemoryLayout<AudioClassID>.size)
        var size: UInt32 = 0
        let expectedSize = plan.members.count * MemoryLayout<AudioObjectID>.size
        guard AudioObjectGetPropertyDataSize(id, &address, qualifierSize, &filter, &size) == noErr,
              size == expectedSize else {
            throw GraphError.message("Private route has an unexpected number of available subdevices.")
        }
        var values = [AudioObjectID](repeating: 0, count: plan.members.count)
        guard AudioObjectGetPropertyData(id, &address, qualifierSize, &filter, &size, &values) == noErr else {
            throw GraphError.message("Could not read private-route subdevices.")
        }
        return values
    }

    private func channels(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return -1 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, memory) == noErr else { return -1 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
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
}
