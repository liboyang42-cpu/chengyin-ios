import Foundation

/// Existing runtime producer reference. A logical UUID is never an OSS locator or a public URL.
public struct OwnedTopicCoverAsset: Equatable, Sendable {
    public let assetID: String, sourceVersion: String, contentHash: String
    public let ownerMemberID: Int
    public static func decode(_ value: ProjectEditJSON, owner: Int) throws -> Self {
        guard let row = value.object,
              Set(row.keys) == ["kind", "id", "assetId", "sourceVersion", "contentHash", "owner", "ownerMemberId", "policyVersion"],
              row["kind"]?.text == "OWNED_TOPIC_COVER_V1", row["policyVersion"]?.text == "OWNED_TOPIC_COVER_V1",
              let id = row["id"]?.text, uuid(id), row["assetId"]?.text == id,
              let version = row["sourceVersion"]?.text, uuid(version),
              let hash = row["contentHash"]?.text, ApprovedTopicReleasePreparation.validHash(hash),
              owner > 0, row["owner"]?.integer == owner, row["ownerMemberId"]?.integer == owner else { throw OwnedTopicCoverFailure.invalidResponse }
        return .init(assetID: id, sourceVersion: version, contentHash: hash, ownerMemberID: owner)
    }
    static func uuid(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
    var fields: ProjectEditJSON {
        .object(["kind": .string("OWNED_TOPIC_COVER_V1"), "id": .string(assetID), "assetId": .string(assetID), "sourceVersion": .string(sourceVersion), "contentHash": .string(contentHash),
                 "owner": .number(Decimal(ownerMemberID)), "ownerMemberId": .number(Decimal(ownerMemberID)), "policyVersion": .string("OWNED_TOPIC_COVER_V1")])
    }
    public var contentPath: String { "api/topic/cover/\(assetID)/content" }
    static func decodeDisplay(_ value: ProjectEditJSON, owner: Int) throws -> Self {
        guard let row = value.object, Set(row.keys) == ["assetReference", "displayReference"], let raw = row["assetReference"],
              let display = row["displayReference"]?.object, Set(display.keys) == ["kind", "audience", "path", "contentHash"] else { throw OwnedTopicCoverFailure.invalidResponse }
        let asset = try decode(raw, owner: owner)
        guard display["kind"]?.text == "OWNED_TOPIC_COVER_AUTHENTICATED_CONTENT_V1", display["audience"]?.text == "AUTHOR_ONLY",
              display["contentHash"]?.text == asset.contentHash,
              display["path"]?.text == "/\(asset.contentPath)?sourceVersion=\(asset.sourceVersion)&contentHash=\(asset.contentHash)" else { throw OwnedTopicCoverFailure.invalidResponse }
        return asset
    }
}

/// Current producer CAS values. STALE/UNAVAILABLE still do not resolve an earlier unknown write.
public struct OwnedTopicCoverCurrent: Equatable, Sendable {
    public enum Selection: String, Sendable { case none = "NONE", current = "CURRENT", stale = "STALE" }
    public enum Availability: String, Sendable { case none = "NONE", available = "AVAILABLE", unavailable = "UNAVAILABLE" }
    public let topicID: Int, configVersion: Int, selectionVersion: Int, contentSlotID: Int
    public let selectedAtConfigVersion: Int?
    public let selection: Selection, availability: Availability
    public let asset: OwnedTopicCoverAsset?
    static func decode(_ value: ProjectEditJSON, topicID: Int, owner: Int) throws -> Self {
        guard let row = value.object, Set(row.keys) == ["topicId", "topicConfigVersion", "selectionVersion", "contentSlotId", "selectedAtConfigVersion", "selectionState", "assetAvailability", "display"],
              topicID > 0, row["topicId"]?.integer == topicID,
              let config = row["topicConfigVersion"]?.integer, config >= 0, config < Int.max,
              let version = row["selectionVersion"]?.integer, version >= 0, version < Int.max,
              let slot = row["contentSlotId"]?.integer, slot > 0,
              let state = row["selectionState"]?.text.flatMap(Selection.init(rawValue:)),
              let availability = row["assetAvailability"]?.text.flatMap(Availability.init(rawValue:)) else { throw OwnedTopicCoverFailure.invalidResponse }
        let selected: Int?
        if row["selectedAtConfigVersion"] == .null { selected = nil }
        else { guard let n = row["selectedAtConfigVersion"]?.integer, n >= 0, n <= config else { throw OwnedTopicCoverFailure.invalidResponse }; selected = n }
        let asset: OwnedTopicCoverAsset?
        if availability == .available {
            guard let display = row["display"], display != .null else { throw OwnedTopicCoverFailure.invalidResponse }
            asset = try .decodeDisplay(display, owner: owner)
        } else { guard row["display"] == .null else { throw OwnedTopicCoverFailure.invalidResponse }; asset = nil }
        switch state {
        case .none: guard version == 0, selected == nil, availability == .none else { throw OwnedTopicCoverFailure.invalidResponse }
        case .current: guard version > 0, selected == config, availability != .none else { throw OwnedTopicCoverFailure.invalidResponse }
        case .stale: guard version > 0, selected != nil, availability != .none else { throw OwnedTopicCoverFailure.invalidResponse }
        }
        return .init(topicID: topicID, configVersion: config, selectionVersion: version, contentSlotID: slot, selectedAtConfigVersion: selected, selection: state, availability: availability, asset: asset)
    }
}

public struct OwnedTopicCoverSelectionCommand: Equatable, Sendable {
    public let topicID: Int, expectedConfigVersion: Int, expectedSelectionVersion: Int, expectedContentSlotID: Int
    public let requestID: String
    public let asset: OwnedTopicCoverAsset
    public init(current: OwnedTopicCoverCurrent, asset: OwnedTopicCoverAsset, requestID: UUID = UUID()) {
        topicID = current.topicID; expectedConfigVersion = current.configVersion; expectedSelectionVersion = current.selectionVersion
        expectedContentSlotID = current.contentSlotID; self.asset = asset; self.requestID = requestID.uuidString
    }
    public var fields: [String: ProjectEditJSON] {
        ["topicId": .number(Decimal(topicID)), "expectedConfigVersion": .number(Decimal(expectedConfigVersion)), "expectedSelectionVersion": .number(Decimal(expectedSelectionVersion)),
         "expectedContentSlotId": .number(Decimal(expectedContentSlotID)), "requestId": .string(requestID), "assetId": .string(asset.assetID), "sourceVersion": .string(asset.sourceVersion), "contentHash": .string(asset.contentHash)]
    }
    static func decode(_ value: ProjectEditJSON, owner: Int) throws -> Self {
        guard let row = value.object, Set(row.keys) == ["topicId", "expectedConfigVersion", "expectedSelectionVersion", "expectedContentSlotId", "requestId", "assetId", "sourceVersion", "contentHash"],
              let topic = row["topicId"]?.integer, topic > 0, let config = row["expectedConfigVersion"]?.integer, config >= 0, config < Int.max,
              let selection = row["expectedSelectionVersion"]?.integer, selection >= 0, selection < Int.max, let slot = row["expectedContentSlotId"]?.integer, slot > 0,
              let idText = row["requestId"]?.text, let id = UUID(uuidString: idText), id.uuidString == idText,
              let asset = row["assetId"]?.text, let version = row["sourceVersion"]?.text, let hash = row["contentHash"]?.text else { throw OwnedTopicCoverFailure.invalidResponse }
        let reference = try OwnedTopicCoverAsset.decode(.object(["kind":.string("OWNED_TOPIC_COVER_V1"),"id":.string(asset),"assetId":.string(asset),"sourceVersion":.string(version),"contentHash":.string(hash),"owner":.number(Decimal(owner)),"ownerMemberId":.number(Decimal(owner)),"policyVersion":.string("OWNED_TOPIC_COVER_V1")]), owner: owner)
        let current = OwnedTopicCoverCurrent(topicID: topic, configVersion: config, selectionVersion: selection, contentSlotID: slot, selectedAtConfigVersion: nil, selection: .none, availability: .none, asset: nil)
        return .init(current: current, asset: reference, requestID: id)
    }
}
public struct OwnedTopicCoverSelectionReceipt: Equatable, Sendable {
    public let topicID: Int, configVersion: Int, selectionVersion: Int, contentSlotID: Int
    public let asset: OwnedTopicCoverAsset
    var fields: ProjectEditJSON {
        .object(["topicId":.number(Decimal(topicID)),"topicConfigVersion":.number(Decimal(configVersion)),"selectionVersion":.number(Decimal(selectionVersion)),"contentSlotId":.number(Decimal(contentSlotID)),"cover":asset.fields])
    }
    static func decode(_ value: ProjectEditJSON, command: OwnedTopicCoverSelectionCommand) throws -> Self {
        guard let row = value.object, Set(row.keys) == ["topicId", "topicConfigVersion", "selectionVersion", "contentSlotId", "cover"],
              row["topicId"]?.integer == command.topicID, row["topicConfigVersion"]?.integer == command.expectedConfigVersion + 1,
              row["selectionVersion"]?.integer == command.expectedSelectionVersion + 1, row["contentSlotId"]?.integer == command.expectedContentSlotID,
              let cover = row["cover"] else { throw OwnedTopicCoverFailure.invalidResponse }
        let asset = try OwnedTopicCoverAsset.decode(cover, owner: command.asset.ownerMemberID)
        guard asset == command.asset else { throw OwnedTopicCoverFailure.invalidResponse }
        return .init(topicID: command.topicID, configVersion: command.expectedConfigVersion + 1, selectionVersion: command.expectedSelectionVersion + 1, contentSlotID: command.expectedContentSlotID, asset: asset)
    }
}
public enum OwnedTopicCoverFailure: Error, Equatable {
    case notConfigured, changedContext, invalidResponse, unavailable, forbidden, outcomeUnknown, persistenceUnavailable
}
