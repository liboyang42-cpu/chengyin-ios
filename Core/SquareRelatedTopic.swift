import Foundation

/// A related topic is a read destination, never a post-ID crosswalk or play grant.
public struct SquareRelatedTopicRoute: Hashable {
    public let source: SquareContentRoute
    public let topicID: Int

    public init?(post: SquarePost, source: SquareContentRoute) {
        guard source.valid, source.id == post.id, source.generation == post.generation else { return nil }
        let topicID: Int?
        switch source.generation {
        case .legacySquare: topicID = post.relatedTopicIDs.legacy
        case .communityV1: topicID = post.relatedTopicIDs.community
        case .unknown: return nil
        }
        guard let topicID else { return nil }
        self.source = source; self.topicID = topicID
    }
}

/// Capture both read scopes at selection; an account or credential change cannot
/// carry a previous post's association into the replacement topic reader.
public struct SquareRelatedTopicSelection: Hashable, Identifiable {
    public let route: SquareRelatedTopicRoute
    public let squareScope: UUID
    public let topicScope: UUID
    public var id: Self { self }
    public init(route: SquareRelatedTopicRoute, squareScope: UUID, topicScope: UUID) {
        self.route = route; self.squareScope = squareScope; self.topicScope = topicScope
    }
    public func isCurrent(squareScope: UUID, topicScope: UUID) -> Bool {
        self.squareScope == squareScope && self.topicScope == topicScope
    }
}

struct SquareRelatedTopicIDs: Equatable {
    let legacy: Int?
    let community: Int?
    init(root: SquareValue, reference: SquareValue) {
        // Each namespace uses its own authoritative association. Activity IDs,
        // route IDs, titles, snapshots and generic data IDs are not topic IDs.
        legacy = Self.positiveID(root["sportTopicId"])
        community = reference.first("reference_type", "referenceType").string == "TOPIC"
            ? Self.positiveID(reference.first("reference_id", "referenceId")) : nil
    }
    private static func positiveID(_ value: SquareValue) -> Int? {
        let id: Int?
        switch value {
        case .integer(let number): id = number
        case .string(let string):
            let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            id = Int(text)
        default: return nil
        }
        guard let id, id > 0 else { return nil }
        return id
    }
}
