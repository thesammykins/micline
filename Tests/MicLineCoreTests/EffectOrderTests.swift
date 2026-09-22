import Foundation
import Testing
@testable import MicLineCore

@Test @MainActor func effectMoveInsertsAndPersistsWithoutSwappingInterveningEffects() throws {
    let suite = "MicLine.EffectOrderTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let graph = AudioGraph(defaults: defaults)
    var effects = ["first", "second", "third", "fourth"].map { EffectSelection(pluginID: $0) }
    effects[1].state = Data([1, 7, 3])
    effects[2].bypassed = true

    for (source, offset, order) in [
        (1, 2, [0, 2, 3, 1]),
        (3, -2, [0, 3, 1, 2]),
        (0, 3, [1, 2, 3, 0]),
        (3, -3, [3, 0, 1, 2]),
        (1, -1, [1, 0, 2, 3])
    ] {
        graph.settings.effects = effects
        graph.diagnostics.clear()
        graph.move(effects[source].id, by: offset)
        let expected = order.map { effects[$0] }
        #expect(graph.settings.effects == expected)
        let persisted = try #require(defaults.data(forKey: "session"))
        #expect(try JSONDecoder().decode(SessionSettings.self, from: persisted).effects == expected)
        #expect(graph.diagnostics.entries.map(\.event) == [.effectReordered])
        #expect(!graph.running)
    }
}

@Test @MainActor func ineffectiveEffectMovesDoNotStopOrPersist() throws {
    let suite = "MicLine.EffectOrderTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let graph = AudioGraph(defaults: defaults)
    let effects = ["first", "second", "third"].map { EffectSelection(pluginID: $0) }
    graph.settings.effects = effects
    graph.diagnostics.clear()
    let status = graph.status
    let persisted = defaults.data(forKey: "session")

    for (id, offset) in [(effects[0].id, -1), (effects[2].id, 1), (UUID(), 1), (effects[1].id, 0)] {
        graph.move(id, by: offset)
        #expect(graph.settings.effects == effects)
        #expect(graph.status == status)
        #expect(defaults.data(forKey: "session") == persisted)
        #expect(graph.diagnostics.entries.isEmpty)
    }
}
