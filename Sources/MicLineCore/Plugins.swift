import AVFoundation
import Foundation

public enum PluginFormat: String, Codable, CaseIterable { case au = "AU", vst2 = "VST2", vst3 = "VST3" }

public struct PluginRecord: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var format: PluginFormat
    public var location: String?
    public var type: UInt32 = 0
    public var subtype: UInt32 = 0
    public var manufacturer: UInt32 = 0
    public var hostable: Bool { format == .au }
    public var componentDescription: AudioComponentDescription {
        AudioComponentDescription(componentType: type, componentSubType: subtype,
            componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)
    }
}

public enum PluginRegistry {
    public static func scan() -> [PluginRecord] {
        let manager = AVAudioUnitComponentManager.shared()
        let aus = [kAudioUnitType_Effect].flatMap { type in
            manager.components(matching: AudioComponentDescription(componentType: type, componentSubType: 0,
                componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)).map { component in
                let d = component.audioComponentDescription
                return PluginRecord(id: "au:\(d.componentType):\(d.componentSubType):\(d.componentManufacturer)",
                    name: component.name, format: .au, type: d.componentType,
                    subtype: d.componentSubType, manufacturer: d.componentManufacturer)
            }
        }
        let roots = [URL(fileURLWithPath: "/Library/Audio/Plug-Ins"),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Audio/Plug-Ins")]
        return (aus + scanBundles(roots: roots)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // Unvalidated filesystem candidates, not proof of installed/loadable plugins.
    // Never dlopen a third-party binary in the scanner.
    public static func scanBundles(roots: [URL]) -> [PluginRecord] {
        var records: [PluginRecord] = []
        for root in roots {
            for (folder, ext, format) in [("VST", "vst", PluginFormat.vst2), ("VST3", "vst3", .vst3)] {
                guard let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(folder),
                    includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in enumerator where url.pathExtension.lowercased() == ext {
                    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                    records.append(PluginRecord(id: url.path, name: url.deletingPathExtension().lastPathComponent,
                        format: format, location: url.path))
                    enumerator.skipDescendants()
                }
            }
        }
        return records
    }
}

public struct EffectSelection: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var pluginID: String
    public var bypassed = false
    public var state: Data?
    public init(pluginID: String) { self.pluginID = pluginID }
}

public struct SessionSettings: Codable, Equatable {
    public var inputUID = ""
    public var outputUID = ""
    // Optional keys preserve sessions saved before explicit channel selection.
    public var inputChannel: Int?
    public var outputChannel: Int?
    public var gainDB: Double = 0
    public var highPassHz: Double = 80
    public var highPassEnabled = true
    public var effects: [EffectSelection] = []
    public init() {}
    public mutating func validate() {
        inputChannel = min(255, max(0, inputChannel ?? 0))
        outputChannel = min(255, max(0, outputChannel ?? 0))
        gainDB = gainDB.isFinite ? min(12, max(-24, gainDB)) : 0
        highPassHz = highPassHz.isFinite ? min(300, max(20, highPassHz)) : 80
        effects = Array(effects.prefix(16))
        var seen = Set<UUID>()
        effects = effects.filter { seen.insert($0.id).inserted }
        for i in effects.indices where (effects[i].state?.count ?? 0) > 1_048_576 { effects[i].state = nil }
    }
}

public enum LevelMath {
    public static func decibels(_ amplitude: Float) -> Double {
        samplePeakDBFS(amplitude)
    }

    public static func samplePeakDBFS(_ amplitude: Float) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return -90 }
        return max(-90, 20 * log10(Double(amplitude)))
    }

    public static func rmsDBFS(_ rms: Float) -> Double {
        guard rms.isFinite, rms > 0 else { return -90 }
        return max(-90, 20 * log10(Double(rms) * sqrt(2)))
    }
}
