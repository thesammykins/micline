import Foundation
import Testing
import MicLineUI

@Suite("Effect reordering")
struct EffectReorderingTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let third = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let fourth = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    @Test("Plans asymmetric moves to exact insertion edges")
    func asymmetricMoves() {
        let ids = [first, second, third, fourth]

        #expect(offset(ids, effect: first, destination: third, edge: .after) == 2)
        #expect(offset(ids, effect: fourth, destination: second, edge: .before) == -2)
        #expect(apply(offset(ids, effect: first, destination: third, edge: .after), to: ids, effect: first)
            == [second, third, first, fourth])
        #expect(apply(offset(ids, effect: fourth, destination: second, edge: .before), to: ids, effect: fourth)
            == [first, fourth, second, third])
    }

    @Test("Plans first and last positions without off-by-one errors")
    func boundaryMoves() {
        let ids = [first, second, third, fourth]

        #expect(apply(offset(ids, effect: fourth, destination: first, edge: .before), to: ids, effect: fourth)
            == [fourth, first, second, third])
        #expect(apply(offset(ids, effect: first, destination: fourth, edge: .after), to: ids, effect: first)
            == [second, third, fourth, first])
        #expect(offset(ids, effect: second, destination: first, edge: .after) == nil)
        #expect(offset(ids, effect: third, destination: fourth, edge: .before) == nil)
    }

    @Test("Rejects foreign sessions, stale IDs, and duplicate persisted IDs")
    func rejectsInvalidDrops() {
        let ids = [first, second, third, fourth]
        let foreign = EffectDragPayload(effectID: first, sessionID: UUID())
        let stale = EffectDragPayload(effectID: UUID(), sessionID: sessionID)

        #expect(EffectReordering.offset(ids: ids, payload: foreign, sessionID: sessionID,
            destinationID: third, edge: .after) == nil)
        #expect(EffectReordering.offset(ids: ids, payload: stale, sessionID: sessionID,
            destinationID: third, edge: .after) == nil)
        #expect(EffectReordering.offset(ids: ids, payload: payload(first), sessionID: sessionID,
            destinationID: UUID(), edge: .after) == nil)
        #expect(EffectReordering.offset(ids: [first, second, second], payload: payload(first),
            sessionID: sessionID, destinationID: second, edge: .after) == nil)
    }

    @Test("Payload round trip preserves the stable effect and drag session IDs")
    func payloadRoundTrip() throws {
        let original = payload(third)
        let decoded = try JSONDecoder().decode(EffectDragPayload.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    private func payload(_ effect: UUID) -> EffectDragPayload {
        EffectDragPayload(effectID: effect, sessionID: sessionID)
    }

    private func offset(_ ids: [UUID], effect: UUID, destination: UUID, edge: EffectDropEdge) -> Int? {
        EffectReordering.offset(ids: ids, payload: payload(effect), sessionID: sessionID,
            destinationID: destination, edge: edge)
    }

    private func apply(_ offset: Int?, to ids: [UUID], effect: UUID) -> [UUID] {
        var result = ids
        guard let offset, let index = result.firstIndex(of: effect) else { return result }
        let item = result.remove(at: index)
        result.insert(item, at: index + offset)
        return result
    }
}
