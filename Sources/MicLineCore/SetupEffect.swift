import AVFoundation

public enum SetupEffect: CaseIterable {
    case isolation, compression

    public var title: String { self == .isolation ? "Sound Isolation" : "Compression" }
    public var subtype: OSType {
        self == .isolation ? kAudioUnitSubType_AUSoundIsolation : kAudioUnitSubType_DynamicsProcessor
    }

    public func plugin(in plugins: [PluginRecord]) -> PluginRecord? {
        plugins.first { $0.hostable && $0.type == kAudioUnitType_Effect &&
            $0.manufacturer == kAudioUnitManufacturer_Apple && $0.subtype == subtype }
    }

    /// Prepare only an Apple component. Loading never starts an audio engine.
    @MainActor public func selection(in plugins: [PluginRecord]) async throws -> EffectSelection {
        guard let plugin = plugin(in: plugins) else {
            throw GraphError.message("Apple’s \(title) isn’t available. You can skip this effect.")
        }
        let unit: AVAudioUnit = try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: plugin.componentDescription, options: .loadOutOfProcess) { unit, error in
                if let unit { continuation.resume(returning: unit) }
                else { continuation.resume(throwing: error ?? GraphError.message("The effect could not load.")) }
            }
        }
        try Task.checkCancellation()
        return try unit.withAUAudioUnit { audioUnit in
            // Apple parameter addresses from AudioUnitParameters.h. Verify their
            // ranges on this instance before offering a preset on a newer OS.
            let values: [(AUParameterAddress, AUValue)] = self == .isolation
                ? [(0, 100), (1, 1)]
                : [(0, -18), (1, 12), (2, 1), (3, -100), (4, 0.01), (5, 0.15), (6, 0)]
            for (address, value) in values {
                guard let parameter = audioUnit.parameterTree?.parameter(withAddress: address),
                      parameter.minValue <= value, parameter.maxValue >= value else {
                    throw GraphError.message("This effect’s controls differ from the supported setup. Use its own controls or skip it.")
                }
                parameter.value = value
                guard abs(parameter.value - value) < 0.001 else {
                    throw GraphError.message("The effect did not accept its setup value.")
                }
            }
            guard let state = audioUnit.fullStateForDocument else {
                throw GraphError.message("The effect cannot save its settings.")
            }
            let data = try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
            guard data.count <= 1_048_576 else { throw GraphError.message("Effect settings exceed the supported size.") }
            var selection = EffectSelection(pluginID: plugin.id)
            selection.state = data
            return selection
        }
    }
}
