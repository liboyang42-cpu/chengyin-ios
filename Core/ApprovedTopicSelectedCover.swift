import Foundation

/// Exact server-selected asset metadata. Its AUTHOR_ONLY locator is not a player grant or an arbitrary image URL.
public struct ApprovedTopicSelectedCover: Equatable, Sendable {
    public let topicID: Int, topicConfigVersion: Int, selectionVersion: Int, contentSlotID: Int, ownerMemberID: Int
    public let assetID: String, sourceVersion: String, contentHash: String, authorContentPath: String
    public let legacyImageReference: String?
    public enum Binding: String, Equatable, Sendable {
        case authorPreviewOnly = "AUTHOR_PREVIEW_ONLY"
        case frozenReleaseReplacement = "REPLACE_LEGACY_IMAGE_IN_W02_RELEASE"
    }
    public let binding: Binding
    private let rawFields: ProjectEditJSON
    private let identityBytes: Data
    var persistedFields: ProjectEditJSON { rawFields }
    /// This validates a server capture profile only; ordinary endpoint capabilities and the real audit still apply.
    public var permitsReviewRequest: Bool { binding == .frozenReleaseReplacement }
    static func decode(_ value: ProjectEditJSON, topicID: Int, sourceConfigVersion: Int, legacyReference: String?) throws -> Self {
        guard let row = value.object, let state = row["bindingState"]?.text,
              let binding = Binding(rawValue: state) else { throw ApprovedTopicReleaseError.invalidResponse }
        var expectedKeys: Set<String> = ["kind", "schemaVersion", "topicId", "topicConfigVersion", "selectionVersion", "contentSlotId", "assetReference", "authorDisplayReference", "legacyTopicImageReference", "bindingState", "legacyImageBindingVerified", "publicPlayerReadable", "approvalProof"]
        if binding == .frozenReleaseReplacement { expectedKeys.insert("playerReadContract") }
        guard Set(row.keys) == expectedKeys,
              binding != .frozenReleaseReplacement || row["playerReadContract"]?.text == "PLAYER_PINNED_RUN_ONLY",
              row["kind"]?.text == "OWNED_TOPIC_COVER_REVIEW_INPUT_V1", row["schemaVersion"]?.integer == 1,
              row["topicId"]?.integer == topicID, row["topicConfigVersion"]?.integer == sourceConfigVersion,
              let selection = row["selectionVersion"]?.integer, selection > 0,
              let slot = row["contentSlotId"]?.integer, slot > 0,
              row["legacyImageBindingVerified"] == .bool(false),
              row["publicPlayerReadable"] == .bool(false), row["approvalProof"] == .bool(false),
              let asset = row["assetReference"]?.object,
              Set(asset.keys) == ["kind", "id", "assetId", "sourceVersion", "contentHash", "owner", "ownerMemberId", "policyVersion"],
              asset["kind"]?.text == "OWNED_TOPIC_COVER_V1", asset["policyVersion"]?.text == "OWNED_TOPIC_COVER_V1",
              let id = asset["id"]?.text, validUUID(id), asset["assetId"]?.text == id,
              let version = asset["sourceVersion"]?.text, validUUID(version),
              let hash = asset["contentHash"]?.text, ApprovedTopicReleasePreparation.validHash(hash),
              let owner = asset["owner"]?.integer, owner > 0, asset["ownerMemberId"]?.integer == owner,
              let display = row["authorDisplayReference"]?.object,
              Set(display.keys) == ["kind", "audience", "path", "contentHash"],
              display["kind"]?.text == "OWNED_TOPIC_COVER_AUTHENTICATED_CONTENT_V1", display["audience"]?.text == "AUTHOR_ONLY",
              display["contentHash"]?.text == hash,
              let path = display["path"]?.text,
              path == "/api/topic/cover/\(id)/content?sourceVersion=\(version)&contentHash=\(hash)" else { throw ApprovedTopicReleaseError.invalidResponse }
        let legacy: String?
        if row["legacyTopicImageReference"] == .null { legacy = nil }
        else { guard let text = row["legacyTopicImageReference"]?.text else { throw ApprovedTopicReleaseError.invalidResponse }; legacy = text }
        guard legacy.map({ Data($0.utf8) }) == legacyReference.map({ Data($0.utf8) }) else { throw ApprovedTopicReleaseError.invalidResponse }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let identityBytes = try encoder.encode(value)
        return .init(topicID: topicID, topicConfigVersion: sourceConfigVersion, selectionVersion: selection, contentSlotID: slot, ownerMemberID: owner,
                     assetID: id, sourceVersion: version, contentHash: hash, authorContentPath: path, legacyImageReference: legacy, binding: binding, rawFields: value, identityBytes: identityBytes)
    }
    private static func validUUID(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
}
