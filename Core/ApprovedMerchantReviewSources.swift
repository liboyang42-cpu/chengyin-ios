import Foundation

/// Exact server references chosen for a new review. They confer no approval or usage right.
public struct ApprovedMerchantReviewSource: Equatable, Sendable, Identifiable {
    public struct Reference: Equatable, Sendable {
        public let kind: String, contentHash: String
        public let sourceID: Int, sourceVersion: Int
        var fields: ProjectEditJSON { .object(["kind": .string(kind), "sourceId": .number(Decimal(sourceID)), "sourceVersion": .number(Decimal(sourceVersion)), "contentHash": .string(contentHash)]) }
        static func decode(_ value: ProjectEditJSON?, kind: String) throws -> Self {
            guard let row = value?.object, Set(row.keys) == ["kind", "sourceId", "sourceVersion", "contentHash"], row["kind"]?.text == kind,
                  let id = row["sourceId"]?.integer, id > 0, row["sourceVersion"]?.integer == 1,
                  let hash = row["contentHash"]?.text, ApprovedTopicReleasePreparation.validHash(hash) else { throw ApprovedTopicReleaseError.invalidResponse }
            return .init(kind: kind, contentHash: hash, sourceID: id, sourceVersion: 1)
        }
    }
    public let memberTemplateID: Int
    public let source: Reference, merchantConfirmation: Reference
    public var id: String { "\(memberTemplateID):\(source.sourceID):\(merchantConfirmation.sourceID):\(merchantConfirmation.contentHash)" }
    var fields: ProjectEditJSON { .object(["memberTemplateId": .number(Decimal(memberTemplateID)), "source": source.fields, "merchantConfirmation": merchantConfirmation.fields]) }
    static func decode(_ value: ProjectEditJSON) throws -> Self {
        guard let row = value.object, Set(row.keys) == ["memberTemplateId", "source", "merchantConfirmation"], let id = row["memberTemplateId"]?.integer, id > 0 else { throw ApprovedTopicReleaseError.invalidResponse }
        return try .init(memberTemplateID: id, source: .decode(row["source"], kind: "MERCHANT_AI_TEMPLATE_SOURCE_V1"), merchantConfirmation: .decode(row["merchantConfirmation"], kind: "MERCHANT_STORE_FACTS_CONFIRMATION_V1"))
    }
    static func decodeSelections(_ value: ProjectEditJSON) throws -> [Self] {
        guard let rows = value.array, !rows.isEmpty, rows.count <= 32 else { throw ApprovedTopicReleaseError.invalidResponse }
        let selections = try rows.map(decode)
        guard Set(selections.map(\.memberTemplateID)).count == selections.count, Set(selections.map { $0.source.sourceID }).count == selections.count,
              Set(selections.map { $0.merchantConfirmation.sourceID }).count == selections.count,
              selections.map(\.memberTemplateID) == selections.map(\.memberTemplateID).sorted() else { throw ApprovedTopicReleaseError.invalidResponse }
        return selections
    }
}

public struct ApprovedMerchantReviewChoices: Equatable, Sendable {
    public struct Choice: Equatable, Sendable, Identifiable {
        public let selection: ApprovedMerchantReviewSource
        public let title: String?, templateContentHash: String
        public let confirmedAtEpochMillis: Int
        public var id: String { selection.id }
    }
    public struct Group: Equatable, Sendable, Identifiable {
        public let memberTemplateID: Int, confirmations: [Choice], hasOlderConfirmations: Bool
        public var id: Int { memberTemplateID }
    }
    public let ownerMemberID: Int, topicID: Int, observedAuditTaskID: Int, observedAuditTaskVersion: Int, sourceConfigVersion: Int
    public let groups: [Group]
    private let identity: Data
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    public static func decode(_ value: ProjectEditJSON, origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) throws -> Self {
        guard origin.ownerKey == session.ownerKey, let row = value.object,
              Set(row.keys) == ["contract", "templateIdNamespace", "currentness", "ownerMemberId", "topicId", "observedAuditTaskId", "sourceConfigVersion", "observedAuditTaskVersion", "approvalProof", "publicationAuthority", "sources"],
              row["contract"]?.text == "questify.topic-release.merchant-source-choices.v1", row["templateIdNamespace"]?.text == "CMS_MEMBER_TEMPLATE",
              row["currentness"]?.text == "CONFIRMED_HISTORICAL_INPUTS", row["ownerMemberId"]?.integer == session.accountID,
              row["topicId"]?.integer == origin.topicID, row["observedAuditTaskId"]?.integer == origin.auditTaskID,
              let version = row["observedAuditTaskVersion"]?.integer, version >= 0, version <= Int(Int32.max),
              let config = row["sourceConfigVersion"]?.integer, config >= 0,
              row["approvalProof"] == .bool(false), row["publicationAuthority"] == .bool(false),
              let groups = row["sources"]?.array, groups.count <= 32 else { throw ApprovedTopicReleaseError.invalidResponse }
        var templateIDs = Set<Int>(), confirmationIDs = Set<Int>()
        let decoded = try groups.map { value -> Group in
            guard let group = value.object, Set(group.keys) == ["memberTemplateId", "confirmations", "hasOlderConfirmations"],
                  let template = group["memberTemplateId"]?.integer, template > 0, templateIDs.insert(template).inserted,
                  let choices = group["confirmations"]?.array, choices.count <= 8,
                  case .bool(let more)? = group["hasOlderConfirmations"] else { throw ApprovedTopicReleaseError.invalidResponse }
            var sourceID: Int?
            let confirmed = try choices.map { value -> Choice in
                guard let choice = value.object, Set(choice.keys).isSubset(of: ["selection", "templateTitle", "templateContentHash", "confirmedAtEpochMillis"]),
                      let selectionValue = choice["selection"], let hash = choice["templateContentHash"]?.text, ApprovedTopicReleasePreparation.validHash(hash),
                      let at = choice["confirmedAtEpochMillis"]?.integer, at >= 0 else { throw ApprovedTopicReleaseError.invalidResponse }
                let selection = try ApprovedMerchantReviewSource.decode(selectionValue)
                guard selection.memberTemplateID == template, confirmationIDs.insert(selection.merchantConfirmation.sourceID).inserted,
                      sourceID == nil || sourceID == selection.source.sourceID else { throw ApprovedTopicReleaseError.invalidResponse }
                sourceID = selection.source.sourceID
                let title: String?
                if choice["templateTitle"] == nil || choice["templateTitle"] == .null { title = nil }
                else { guard let text = choice["templateTitle"]?.text, text.utf16.count <= 512 else { throw ApprovedTopicReleaseError.invalidResponse }; title = text }
                return .init(selection: selection, title: title, templateContentHash: hash, confirmedAtEpochMillis: at)
            }
            return .init(memberTemplateID: template, confirmations: confirmed, hasOlderConfirmations: more)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let bytes = try encoder.encode(value)
        guard bytes.count <= 256 * 1024 else { throw ApprovedTopicReleaseError.invalidResponse }
        return .init(ownerMemberID: session.accountID, topicID: origin.topicID, observedAuditTaskID: origin.auditTaskID, observedAuditTaskVersion: version, sourceConfigVersion: config, groups: decoded, identity: bytes)
    }
}

@MainActor public protocol ApprovedTopicReviewSourceChoosing: AnyObject {
    func canReadSources(session: ProjectEditSession) -> Bool
    func sources(_ origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedMerchantReviewChoices
    func prepare(_ origin: ApprovedTopicReleaseReadTarget, selections: [ApprovedMerchantReviewSource], session: ProjectEditSession) async throws -> ApprovedTopicReviewCapture
}
