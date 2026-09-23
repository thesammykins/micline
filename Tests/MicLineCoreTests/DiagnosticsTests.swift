import Foundation
import Testing
@testable import MicLineCore

@Test @MainActor func diagnosticLogIsBoundedAndHasNoFreeTextInput() {
    let log = DiagnosticLog()
    for code in 0..<70 { log.record(.startFailed, code: code) }
    #expect(log.entries.count == 64)
    #expect(log.entries.first?.code == 6)
    #expect(log.entries.last?.code == 69)
    log.clear()
    #expect(log.entries.isEmpty)
}

@Test func diagnosticsExcludePrivateSourceFieldsAndBoundIssueURL() throws {
    let privateText = "/Users/private-person/secret-token@example.invalid"
    var settings = SessionSettings()
    settings.inputUID = privateText
    settings.effects = [EffectSelection(pluginID: privateText)]
    settings.effects[0].state = Data(privateText.utf8)
    let device = AudioDevice(id: 999, uid: privateText, name: privateText,
        inputChannels: 1, outputChannels: 0, sampleRate: 48_000,
        bufferFrames: 512, isVirtual: false)
    let monitor = AudioDevice(id: 998, uid: privateText, name: privateText,
        inputChannels: 0, outputChannels: 2, sampleRate: 48_000,
        bufferFrames: 256, isVirtual: false)
    let plugin = PluginRecord(id: privateText, name: privateText, format: .au,
        location: privateText, type: 1, subtype: 2, manufacturer: 3)
    let report = DiagnosticReport(appVersion: privateText, buildVersion: "12",
        osVersion: .init(majorVersion: 27, minorVersion: 0, patchVersion: 1),
        settings: settings, input: device, output: nil, monitor: monitor, plugins: [plugin],
        running: false, monitoring: false, events: [])
    let text = try report.json()
    #expect(!text.contains(privateText))
    #expect(!text.contains(Data(privateText.utf8).base64EncodedString()))
    #expect(!text.contains("private-person"))
    #expect(!text.contains("location"))
    #expect(report.appVersion == "unavailable")
    #expect(report.input?.sampleRate == 48_000)
    #expect(report.monitor?.outputChannels == 2)
    #expect(report.monitor?.bufferFrames == 256)
    #expect(report.effects.first?.subtype == 2)
    let url = try #require(report.issueURL)
    #expect(url.absoluteString.utf8.count < 2_000)
    #expect(url.host == "github.com")
    #expect(!url.absoluteString.contains("events"))
    #expect(url.path == "/thesammykins/micline/issues/new")
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.count == 2)
    #expect(query.first(where: { $0.name == "template" })?.value == "bug_report.yml")
    #expect(query.first(where: { $0.name == "environment" })?.value ==
        "MicLine unavailable (12); macOS 27.0.1.\nSelected AU effects: 1.\nDiagnostic export: review locally, then attach manually if needed.")
}

@Test func diagnosticsRejectUntrustedVersionTextAndNonfiniteNumbers() throws {
    var settings = SessionSettings()
    settings.gainDB = .nan
    settings.highPassHz = .infinity
    let device = AudioDevice(id: 1, uid: "ignored", name: "ignored",
        inputChannels: 1, outputChannels: 0, sampleRate: .nan,
        bufferFrames: 512, isVirtual: false)
    let report = DiagnosticReport(appVersion: "1.2.3\ncredential", buildVersion: String(repeating: "9", count: 100),
        osVersion: .init(majorVersion: 27, minorVersion: 0, patchVersion: 0),
        settings: settings, input: device, output: nil, plugins: [],
        running: false, monitoring: false, events: [])
    #expect(report.appVersion == "unavailable")
    #expect(report.buildVersion == "unavailable")
    #expect(report.input?.sampleRate == nil)
    #expect(report.gainDB == 0)
    #expect(report.lowCutHz == 80)
    #expect(!(try report.json()).contains("credential"))
}

@Test @MainActor func graphDiagnosticsUseOnlySelectedCapabilitiesAndControlEvents() throws {
    let suite = "MicLine.DiagnosticsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let graph = AudioGraph(defaults: defaults)
    let privateText = "/Users/private-person/device-secret"
    graph.devices = [AudioDevice(id: 999, uid: privateText, name: privateText,
        inputChannels: 0, outputChannels: 2, sampleRate: 44_100,
        bufferFrames: 256, isVirtual: false)]
    defaults.set(privateText, forKey: "monitorOutputUID")
    let plugin = PluginRecord(id: privateText, name: privateText, format: .au,
        location: privateText, type: 1, subtype: 2, manufacturer: 3)
    graph.plugins = [plugin]
    graph.add(plugin)
    let report = graph.diagnosticReport()
    #expect(report.monitor?.sampleRate == 44_100)
    #expect(report.input == nil)
    #expect(report.events.map(\.event) == [.appOpened, .effectAdded])
    #expect(report.effects.first?.subtype == 2)
    #expect(!(try report.json()).contains(privateText))
    graph.diagnostics.clear()
    #expect(graph.diagnosticReport().events.isEmpty)
}
