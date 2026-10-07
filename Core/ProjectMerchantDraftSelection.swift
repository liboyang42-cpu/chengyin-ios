import Foundation

public enum ProjectMerchantDraftError: Error, Equatable {
    case notConfigured, invalidResponse, changedContext, forbidden, unavailable, sourceChanged
}
public enum ProjectMerchantDraftPath {
    public static let list = "api/merchant/authoring/draft-selection/list"
    public static let resolve = "api/merchant/authoring/draft-selection/resolve"
}

/// Existing W05 source namespace. A reference conveys no ownership or publication grant.
public struct ProjectMerchantDraftSource: Equatable {
    public let sourceID: Int
    public let contentHash: String
    public var fields: [String: ProjectEditJSON] {
        ["kind": .string("MERCHANT_AI_TEMPLATE_SOURCE_V1"), "sourceId": .number(Decimal(sourceID)),
         "sourceVersion": .number(1), "contentHash": .string(contentHash)]
    }
    static func decode(_ value: ProjectEditJSON) throws -> Self {
        guard let v = value.object, Set(v.keys) == ["kind", "sourceId", "sourceVersion", "contentHash"],
              v["kind"] == .string("MERCHANT_AI_TEMPLATE_SOURCE_V1"), v["sourceVersion"] == .number(1),
              let id = v["sourceId"]?.integer, id > 0, let hash = v["contentHash"]?.text,
              ProjectMerchantDraftWire.validHash(hash) else { throw ProjectMerchantDraftError.invalidResponse }
        return .init(sourceID: id, contentHash: hash)
    }
}

/// A current, owner-read title/reference projection; no body, answers or business facts.
public struct ProjectMerchantDraftChoice: Equatable {
    public let memberTemplateID: Int
    public let title: String
    public let source: ProjectMerchantDraftSource
    public let templateContentHash: String
    public var resolveFields: [String: ProjectEditJSON] {
        ["source": .object(source.fields), "memberTemplateId": .number(Decimal(memberTemplateID)),
         "templateContentHash": .string(templateContentHash)]
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.memberTemplateID == rhs.memberTemplateID && lhs.source == rhs.source &&
        lhs.templateContentHash == rhs.templateContentHash && lhs.title.utf8.elementsEqual(rhs.title.utf8)
    }
}
public struct ProjectMerchantDraftRow: Equatable, Identifiable {
    public let sourceID: Int
    public let memberTemplateID: Int
    public let choice: ProjectMerchantDraftChoice?
    public var id: Int { sourceID }
    static func decode(_ value: ProjectEditJSON) throws -> Self {
        guard let v = value.object, let sourceID = v["sourceId"]?.integer, sourceID > 0,
              let templateID = v["memberTemplateId"]?.integer, templateID > 0 else { throw ProjectMerchantDraftError.invalidResponse }
        let basic: Set<String> = ["sourceId", "memberTemplateId", "state"]
        if v["state"] == .string("UNAVAILABLE") {
            guard Set(v.keys) == basic else { throw ProjectMerchantDraftError.invalidResponse }
            return .init(sourceID: sourceID, memberTemplateID: templateID, choice: nil)
        }
        guard v["state"] == .string("READY"), Set(v.keys) == basic.union(["source", "templateTitle", "templateContentHash"]),
              let rawSource = v["source"], let title = v["templateTitle"]?.text, title.utf16.count <= 512,
              let hash = v["templateContentHash"]?.text, ProjectMerchantDraftWire.validHash(hash) else { throw ProjectMerchantDraftError.invalidResponse }
        let source = try ProjectMerchantDraftSource.decode(rawSource)
        guard source.sourceID == sourceID else { throw ProjectMerchantDraftError.invalidResponse }
        return .init(sourceID: sourceID, memberTemplateID: templateID,
                     choice: .init(memberTemplateID: templateID, title: title, source: source, templateContentHash: hash))
    }
}

public struct ProjectMerchantDraftPage: Equatable {
    public static let pageSize = 20
    public let ownerMemberID: Int
    public let merchantRowID: Int
    public let rows: [ProjectMerchantDraftRow]
    public let nextBeforeSourceID: Int?
    public static func decode(_ value: ProjectEditJSON, accountID: Int, beforeSourceID: Int?) throws -> Self {
        let v = try ProjectMerchantDraftWire.common(value, accountID: accountID,
            profile: "MERCHANT_AUTHORING_DRAFT_SELECTION_PAGE_V1", currentness: "PAGE_CURRENT_NOT_SNAPSHOT",
            extraKeys: ["rows", "nextBeforeSourceId"])
        guard let raw = v["rows"]?.array, raw.count <= pageSize, beforeSourceID == nil || beforeSourceID! > 0,
              let cursor = v["nextBeforeSourceId"] else { throw ProjectMerchantDraftError.invalidResponse }
        let rows = try raw.map(ProjectMerchantDraftRow.decode)
        guard Set(rows.map(\.sourceID)).count == rows.count,
              Set(rows.map(\.memberTemplateID)).count == rows.count else { throw ProjectMerchantDraftError.invalidResponse }
        var previous = beforeSourceID
        for row in rows {
            guard previous == nil || row.sourceID < previous! else { throw ProjectMerchantDraftError.invalidResponse }
            previous = row.sourceID
        }
        let next: Int?
        if cursor == .null { next = nil }
        else {
            guard let id = cursor.integer, id > 0, rows.count == pageSize, rows.last?.sourceID == id else { throw ProjectMerchantDraftError.invalidResponse }
            next = id
        }
        return .init(ownerMemberID: accountID, merchantRowID: v["merchantRowId"]!.integer!, rows: rows, nextBeforeSourceID: next)
    }
}

public struct ProjectMerchantDraftResolution: Equatable {
    public let ownerMemberID: Int
    public let merchantRowID: Int
    public let choice: ProjectMerchantDraftChoice
    public static func decode(_ value: ProjectEditJSON, accountID: Int, merchantRowID: Int,
                              expected: ProjectMerchantDraftChoice) throws -> Self {
        let v = try ProjectMerchantDraftWire.common(value, accountID: accountID,
            profile: "MERCHANT_AUTHORING_DRAFT_SELECTION_RESOLVE_V1", currentness: "CURRENT_AT_READ_ONLY", extraKeys: ["row"])
        guard v["merchantRowId"]?.integer == merchantRowID, let raw = v["row"],
              let choice = try ProjectMerchantDraftRow.decode(raw).choice, choice == expected else { throw ProjectMerchantDraftError.sourceChanged }
        return .init(ownerMemberID: accountID, merchantRowID: merchantRowID, choice: choice)
    }
    /// Only changes the existing CMS template reference. The node's title and all other
    /// local fields stay exact. Existing save/prepare/publish remain authoritative.
    public func applying(to node: ProjectEditNode) -> ProjectEditNode {
        var result = node; result.templateID = choice.memberTemplateID; return result
    }
}

enum ProjectMerchantDraftWire {
    static func validHash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func common(_ value: ProjectEditJSON, accountID: Int, profile: String, currentness: String,
                       extraKeys: Set<String>) throws -> [String: ProjectEditJSON] {
        let basic: Set<String> = ["profile", "ownerMemberId", "merchantRowId", "templateIdNamespace", "currentness", "merchantFactsFreshness", "approvalProof", "usageRightsProof", "publicationAuthority"]
        guard let v = value.object, Set(v.keys) == basic.union(extraKeys), accountID > 0,
              v["profile"] == .string(profile), v["ownerMemberId"]?.integer == accountID,
              let merchant = v["merchantRowId"]?.integer, merchant > 0,
              v["templateIdNamespace"] == .string("CMS_MEMBER_TEMPLATE"), v["currentness"] == .string(currentness),
              v["merchantFactsFreshness"] == .string("HISTORICAL_INPUT_ONLY"),
              v["approvalProof"] == .bool(false), v["usageRightsProof"] == .bool(false),
              v["publicationAuthority"] == .bool(false) else { throw ProjectMerchantDraftError.invalidResponse }
        return v
    }
    static func listFields(beforeSourceID: Int?) throws -> [String: ProjectEditJSON] {
        guard beforeSourceID == nil || beforeSourceID! > 0 else { throw ProjectMerchantDraftError.invalidResponse }
        return ["beforeSourceId": beforeSourceID.map { .number(Decimal($0)) } ?? .null]
    }
    static func permitsRequest(_ fields: [String: ProjectEditJSON], path: String) -> Bool {
        if path == ProjectMerchantDraftPath.list {
            return Set(fields.keys) == ["beforeSourceId"] && (fields["beforeSourceId"] == .null || (fields["beforeSourceId"]?.integer ?? 0) > 0)
        }
        guard path == ProjectMerchantDraftPath.resolve,
              Set(fields.keys) == ["source", "memberTemplateId", "templateContentHash"],
              let source = fields["source"], (try? ProjectMerchantDraftSource.decode(source)) != nil,
              let id = fields["memberTemplateId"]?.integer, id > 0,
              let hash = fields["templateContentHash"]?.text else { return false }
        return validHash(hash)
    }
}
