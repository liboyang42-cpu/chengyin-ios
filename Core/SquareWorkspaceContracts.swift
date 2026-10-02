import Foundation

public struct SquareWorkspaceSession: Codable, Equatable, Hashable {
    public let accountID: Int
    public let namespace: String
    public let epoch: UInt64
    public init(accountID: Int, namespace: String, epoch: UInt64) throws {
        guard accountID > 0, !namespace.isEmpty else { throw SquareWorkspaceFailure.sessionChanged }
        self.accountID = accountID; self.namespace = namespace; self.epoch = epoch
    }
    public var ownerKey: String { "\(namespace.utf8.count):\(namespace):\(accountID)" }
}
public enum SquareWorkspaceFailure: Error, Equatable {
    case disabled, invalid, sessionChanged, staleReview, missingMediaProof, rejected(Int), unknown, pending, ownerRequired, malformed
}
public enum SquareWorkspaceLane: String, Codable, CaseIterable { case legacy, communityV1 }
public struct SquareWorkspaceReference: Codable, Equatable {
    public var type: String
    public var id: Int
    public init(type: String, id: Int) { self.type = type; self.id = id }
    public var valid: Bool { ["ACTIVITY", "TOPIC", "ROUTE", "CLUB", "POI"].contains(type) && id > 0 }
    public var legacyType: Int { ["ACTIVITY": 1, "TOPIC": 2, "ROUTE": 3, "CLUB": 4, "POI": 5][type] ?? 0 }
}
public struct SquareWorkspaceMedia: Codable, Equatable, Identifiable {
    public let id: UUID
    public var objectKey: String
    public var existingMediaID: Int?
    public var byteSize: Int?
    public var mimeType: String?
    public var uploadReceipt: String?
    public init(id: UUID = UUID(), objectKey: String, existingMediaID: Int? = nil, byteSize: Int? = nil, mimeType: String? = nil, uploadReceipt: String? = nil) {
        self.id = id; self.objectKey = objectKey; self.existingMediaID = existingMediaID; self.byteSize = byteSize; self.mimeType = mimeType; self.uploadReceipt = uploadReceipt
    }
    public var hasProof: Bool { !objectKey.isEmpty && (byteSize ?? 0) > 0 && !(mimeType ?? "").isEmpty && !(uploadReceipt ?? "").isEmpty }
}
public struct SquareWorkspaceDraft: Codable, Equatable, Identifiable {
    public var id: String { workflowID }
    public var workflowID: String
    public var postID: Int?
    public var expectedVersion: Int
    public var sourceLifecycle: String
    public var body: String
    public var media: [SquareWorkspaceMedia]
    public var retainedMediaIDs: [Int]
    public var address: String?
    public var cityCode: String?
    public var reference: SquareWorkspaceReference?
    /// Community IDs are not club IDs. Never infer this from a CLUB reference.
    public var communityID: Int?
    public var audience: String
    public var commentPolicy: String
    public var replyApprovalEnabled: Bool
    public var slowModeSeconds: Int
    public var disclosureType: String
    public var mentionedMemberIDs: [Int]
    public var safetyLabels: [String]
    public init(workflowID: String = UUID().uuidString, postID: Int? = nil, expectedVersion: Int = 0, sourceLifecycle: String = "DRAFT", body: String = "") {
        self.workflowID = workflowID; self.postID = postID; self.expectedVersion = expectedVersion; self.sourceLifecycle = sourceLifecycle; self.body = body
        media = []; retainedMediaIDs = []; audience = "PUBLIC"; commentPolicy = "EVERYONE"; replyApprovalEnabled = false; slowModeSeconds = 0; disclosureType = "NONE"; mentionedMemberIDs = []; safetyLabels = []
    }
    public mutating func removeReference() {
        reference = nil; communityID = nil
        if audience == "COMMUNITY" { audience = "PUBLIC" }
        if commentPolicy == "MEMBERS" { commentPolicy = "EVERYONE" }
    }
    public func validate(publishing: Bool, lane: SquareWorkspaceLane) throws {
        guard workflowID.count >= 8, media.count <= 6, postID.map({ $0 > 0 }) ?? true, expectedVersion >= 0,
              reference?.valid ?? true, media.allSatisfy({ !$0.objectKey.isEmpty && !$0.objectKey.contains(";") }),
              Set(media.map(\.id)).count == media.count, retainedMediaIDs.allSatisfy({ $0 > 0 }), media.allSatisfy({ $0.existingMediaID.map { $0 > 0 } ?? true }) else { throw SquareWorkspaceFailure.invalid }
        if publishing { guard (1...5000).contains(body.trimmingCharacters(in: .whitespacesAndNewlines).count) else { throw SquareWorkspaceFailure.invalid } }
        if lane == .communityV1 {
            guard ["PUBLIC", "FOLLOWERS", "COMMUNITY", "PRIVATE"].contains(audience),
                  ["EVERYONE", "FOLLOWERS", "MEMBERS", "MENTIONED", "OFF"].contains(commentPolicy),
                  slowModeSeconds >= 0, ["NONE", "SPONSORED", "GIFTED", "MERCHANT_OWNER", "MERCHANT_EMPLOYEE"].contains(disclosureType), safetyLabels.count <= 5, safetyLabels.allSatisfy({ ["DANGEROUS_ACTIVITY", "SENSITIVE_CONTENT", "FLASHING_IMAGES", "SPOILER", "TEMPORARY_CLOSURE", "ACCESSIBILITY_LIMIT", "WEATHER_RISK"].contains($0) }), mentionedMemberIDs.allSatisfy({ $0 > 0 }),
                  (audience != "COMMUNITY" && commentPolicy != "MEMBERS") || (communityID ?? 0) > 0,
                  !publishing || commentPolicy != "MENTIONED" || !mentionedMemberIDs.isEmpty else { throw SquareWorkspaceFailure.invalid }
            guard media.allSatisfy({ ($0.existingMediaID ?? 0) > 0 || $0.hasProof }) else { throw SquareWorkspaceFailure.missingMediaProof }
        } else {
            // Visible Flutter submit omits these v1 controls. Refuse silent loss.
            guard audience == "PUBLIC", commentPolicy == "EVERYONE", !replyApprovalEnabled, slowModeSeconds == 0,
                  disclosureType == "NONE", safetyLabels.isEmpty, mentionedMemberIDs.isEmpty, communityID == nil else { throw SquareWorkspaceFailure.invalid }
        }
    }
}
public struct SquareWorkspaceGuideline: Codable, Equatable {
    public let id: Int
    public let raw: Data
    public init(id: Int, raw: Data) { self.id = id; self.raw = raw }
}
public struct SquareWorkspacePost: Codable, Equatable, Identifiable {
    public let id: Int
    public let authorID: Int
    public let version: Int
    public let lifecycle: String
    public let raw: Data
    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SquareWorkspaceFailure.malformed }
        let p = (root["post"] as? [String: Any]) ?? root
        guard let id = p["id"] as? Int, id > 0, let version = p["version"] as? Int, version >= 0,
              let lifecycle = p["lifecycle"] as? String, !lifecycle.isEmpty,
              let author = (p["authorId"] ?? p["memberId"]) as? Int, author > 0 else { throw SquareWorkspaceFailure.malformed }
        self.id = id; authorID = author; self.version = version; self.lifecycle = lifecycle; raw = data
    }
}
public struct SquareWorkspaceOption: Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let cityCode: String?
}
public struct SquareWorkspacePage: Equatable {
    public let items: [SquareWorkspacePost]
    public let nextCursor: Int?
    public let hasMore: Bool
}
public struct SquareWorkspaceGrants: Equatable {
    public var live = false
    public var media = false
    public var legal = false
    public init() {}
}

extension SquareWorkspacePost {
    public func editableDraft() throws -> SquareWorkspaceDraft {
        guard let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else { throw SquareWorkspaceFailure.malformed }
        let p = (root["post"] as? [String: Any]) ?? root
        var d = SquareWorkspaceDraft(postID: id, expectedVersion: version, sourceLifecycle: lifecycle, body: ((p["body"] ?? p["contents"]) as? String) ?? "")
        d.address = (p["poiName"] ?? p["address"]) as? String; d.cityCode = p["cityCode"] as? String
        d.communityID = p["communityId"] as? Int; d.audience = (p["audience"] as? String) ?? "PUBLIC"
        d.commentPolicy = (p["commentPolicy"] as? String) ?? "EVERYONE"; d.replyApprovalEnabled = (p["replyApprovalEnabled"] as? Int) == 1
        d.slowModeSeconds = (p["slowModeSeconds"] as? Int) ?? 0; d.disclosureType = (p["disclosureType"] as? String) ?? "NONE"
        d.mentionedMemberIDs = (p["mentionedMemberIds"] as? [Int]) ?? []; d.safetyLabels = (p["safetyLabels"] as? [String]) ?? []
        let rows = (root["media"] as? [[String: Any]]) ?? []
        for row in rows {
            guard let mediaID = (row["id"] ?? row["mediaId"]) as? Int, mediaID > 0 else { throw SquareWorkspaceFailure.malformed }
            let type = ((row["media_type"] ?? row["mediaType"]) as? String) ?? "IMAGE"
            if type == "IMAGE", let url = (row["derived_object_key"] ?? row["derivedObjectKey"]) as? String, !url.isEmpty {
                d.media.append(.init(objectKey: url, existingMediaID: mediaID))
            } else { d.retainedMediaIDs.append(mediaID) }
        }
        if rows.isEmpty {
            let pictures = (p["pics"] as? String)?.split(separator: ";").map(String.init) ?? (p["pics"] as? [String]) ?? []
            d.media = pictures.map { .init(objectKey: $0) }
        }
        if let r = (root["references"] as? [[String: Any]])?.first,
           let type = (r["reference_type"] ?? r["referenceType"]) as? String,
           let id = (r["reference_id"] ?? r["referenceId"]) as? Int { d.reference = .init(type: type, id: id) }
        else if let id = (p["dataId"] ?? p["data_id"]) as? Int, id > 0,
                let kind = (p["dataType"] ?? p["data_type"]) as? Int,
                let type = [1: "ACTIVITY", 2: "TOPIC", 3: "ROUTE", 4: "CLUB", 5: "POI"][kind] { d.reference = .init(type: type, id: id) }
        return d
    }
}
