import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public extension UTType {
    static let micLineEffect = UTType(exportedAs: "com.sammy.micline.effect", conformingTo: .data)
}

public enum EffectDropEdge: String, Codable, Sendable {
    case before
    case after
}

public struct EffectDragPayload: Codable, Equatable, Sendable, Transferable {
    public let effectID: UUID
    public let sessionID: UUID

    public init(effectID: UUID, sessionID: UUID) {
        self.effectID = effectID
        self.sessionID = sessionID
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .micLineEffect)
    }
}

public enum EffectReordering {
    /// Returns the insertion offset suitable for `AudioGraph.move(_:by:)`.
    /// Invalid, stale, foreign-session, and no-op drops return `nil`.
    public static func offset(
        ids: [UUID],
        payload: EffectDragPayload,
        sessionID: UUID,
        destinationID: UUID,
        edge: EffectDropEdge
    ) -> Int? {
        guard payload.sessionID == sessionID,
              Set(ids).count == ids.count,
              let sourceIndex = ids.firstIndex(of: payload.effectID),
              ids.contains(destinationID) else { return nil }

        var order = ids
        order.remove(at: sourceIndex)
        guard let destinationAfterRemoval = order.firstIndex(of: destinationID) else { return nil }
        let insertionIndex = destinationAfterRemoval + (edge == .after ? 1 : 0)
        let offset = insertionIndex - sourceIndex
        return offset == 0 ? nil : offset
    }
}
