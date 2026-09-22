import Foundation

/// Fixed events prevent third-party error strings, paths or audio from entering logs.
public enum DiagnosticEvent: String, Codable {
    case appOpened, startRequested, permissionDenied, processingStarted, processingStopped
    case startFailed, monitoringRequested, configurationChanged, deviceDisconnected
    case effectAdded, effectRemoved, effectReordered, pluginLoadFailed, stateSaveFailed
}

@MainActor
public final class DiagnosticLog {
    public struct Entry: Encodable {
        public let elapsedSeconds: Int
        public let event: DiagnosticEvent
        public let code: Int?
    }

    public private(set) var entries: [Entry] = []
    private var started = ProcessInfo.processInfo.systemUptime

    public init() {}

    // Main-actor control events only. Never call from an audio render callback.
    public func record(_ event: DiagnosticEvent, code: Int? = nil) {
        if entries.count == 64 { entries.removeFirst() }
        entries.append(Entry(elapsedSeconds: Int(max(0, ProcessInfo.processInfo.systemUptime - started)),
            event: event, code: code))
    }

    public func clear() {
        entries.removeAll(keepingCapacity: true)
        started = ProcessInfo.processInfo.systemUptime
    }
}

/// This is an allowlisted projection, deliberately not an encoded SessionSettings,
/// AudioDevice or PluginRecord. Adding a field requires a privacy review.
public struct DiagnosticReport: Encodable {
    public struct Device: Encodable {
        public let inputChannels: Int
        public let outputChannels: Int
        public let sampleRate: Double?
        public let bufferFrames: UInt32
        public let virtual: Bool

        init(_ device: AudioDevice) {
            inputChannels = device.inputChannels
            outputChannels = device.outputChannels
            sampleRate = device.sampleRate.isFinite ? device.sampleRate : nil
            bufferFrames = device.bufferFrames
            virtual = device.isVirtual
        }
    }

    public struct Effect: Encodable {
        public let type: UInt32
        public let subtype: UInt32
        public let manufacturer: UInt32
        public let bypassed: Bool
    }

    public let schema = 1
    public let appVersion: String
    public let buildVersion: String
    public let macOS: String
    public let input: Device?
    public let output: Device?
    public let effects: [Effect]
    public let running: Bool
    public let monitoring: Bool
    public let gainDB: Double
    public let lowCutHz: Double
    public let lowCutEnabled: Bool
    public let events: [DiagnosticLog.Entry]

    public init(appVersion: String, buildVersion: String, osVersion: OperatingSystemVersion,
                settings: SessionSettings, input: AudioDevice?, output: AudioDevice?,
                plugins: [PluginRecord], running: Bool, monitoring: Bool,
                events: [DiagnosticLog.Entry]) {
        self.appVersion = Self.numericVersion(appVersion)
        self.buildVersion = Self.numericVersion(buildVersion)
        macOS = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        self.input = input.map(Device.init)
        self.output = output.map(Device.init)
        self.running = running
        self.monitoring = monitoring
        var safeSettings = settings
        safeSettings.validate()
        gainDB = safeSettings.gainDB
        lowCutHz = safeSettings.highPassHz
        lowCutEnabled = safeSettings.highPassEnabled
        effects = safeSettings.effects.compactMap { selection in
            guard let plugin = plugins.first(where: { $0.hostable && $0.id == selection.pluginID }) else { return nil }
            return Effect(type: plugin.type, subtype: plugin.subtype,
                manufacturer: plugin.manufacturer, bypassed: selection.bypassed)
        }
        self.events = Array(events.suffix(64))
    }

    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// No logs enter browser history, query strings or referrers. The user may
    /// attach their reviewed export manually; this URL never submits an issue.
    public var issueURL: URL? {
        var url = URLComponents(string: "https://github.com/thesammykins/micline/issues/new")!
        url.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "environment", value: "MicLine \(appVersion) (\(buildVersion)); macOS \(macOS).\nSelected AU effects: \(effects.count).\nDiagnostic export: review locally, then attach manually if needed.")
        ]
        return url.url
    }

    private static func numericVersion(_ value: String) -> String {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard value.utf8.count <= 32, (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return "unavailable" }
        return value
    }
}
