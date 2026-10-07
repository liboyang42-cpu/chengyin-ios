import Foundation
import CryptoKit

/// Staged creator declaration protocol. A declaration is pending package review, not a listing,
/// buyer entitlement, payment, or permission to publish an existing purchased source.
public enum WorkshopCreatorConsentIssue: Error, Equatable {
    case disabled, invalid, malformed, unavailable, unauthorized, stale, storage, pending, unknown
}
public enum WorkshopCreatorDisclosure {
    public static let version = "w18-creator-public-theme-use-disclosure-v1"
    public static let text = "我允许购买本版本的买家，在原授权主体、地域、项目数量、商用及其他限制范围内，将该版本内容用于买家自己公开发布和运营的主题。此授权不包含转售或再分发原包，不自动包含未来版本，也不改变已有购买的冻结条款。"
    public static var hash: String { WorkshopCreatorWire.sha(Data(text.utf8)) }
}
/// A separately supplied intended package/version and complete terms for review. Merely constructing
/// this value grants nothing. There is currently no deployed package-catalog producer for this seam.
public struct WorkshopCreatorDeclarationTarget: Equatable, Identifiable {
    public let id: UUID
    public let sourceTemplateId: Int64
    public let moduleId, versionId, offerVersion, termsVersion, termsDocument, termsDocumentHash: String
    public let expiresAt: Date
    public init(sourceTemplateId: Int64, moduleId: String, versionId: String, offerVersion: String,
                termsVersion: String, termsDocument: String, termsDocumentHash: String, expiresAt: Date, revision: UUID = UUID()) throws {
        guard sourceTemplateId > 0, [moduleId, versionId, offerVersion, termsVersion].allSatisfy(WorkshopCreatorWire.identifier),
              !termsDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, termsDocument.utf8.count <= 262_144,
              WorkshopCreatorWire.hash(termsDocumentHash), WorkshopCreatorWire.sha(Data(termsDocument.utf8)) == termsDocumentHash,
              expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopCreatorConsentIssue.invalid }
        id = revision; self.sourceTemplateId = sourceTemplateId; self.moduleId = moduleId; self.versionId = versionId
        self.offerVersion = offerVersion; self.termsVersion = termsVersion; self.termsDocument = termsDocument
        self.termsDocumentHash = termsDocumentHash; self.expiresAt = expiresAt
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.sourceTemplateId == b.sourceTemplateId && a.expiresAt == b.expiresAt &&
        zip([a.moduleId, a.versionId, a.offerVersion, a.termsVersion, a.termsDocument, a.termsDocumentHash],
            [b.moduleId, b.versionId, b.offerVersion, b.termsVersion, b.termsDocument, b.termsDocumentHash]).allSatisfy { WorkshopCreatorWire.same($0.0, $0.1) }
    }
}
public struct WorkshopCreatorPreview: Decodable, Equatable {
    public let sourceTemplateId: Int64
    public let templateHash, packageContentHash, packageSourceJson, disclosureVersion, disclosureHash, disclosureText: String
    public let omittedPlanningMetadata: [String]
    public let textFields: [String: String]
    public static let fieldOrder = ["title", "description", "ruleInstructions", "merchantGuide", "questionName", "questionAnswer", "hint1", "hint2", "answerReveal"]
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, sourceTemplateId, templateHash, packageContentHash, packageSourceJson, omittedPlanningMetadata
        case disclosureVersion, disclosureHash, disclosureText, state, packageReviewed
    }
    public init(from decoder: Decoder) throws {
        try WorkshopCreatorWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-creator-public-use-preview-v1",
              try c.decode(String.self, forKey: .state) == "EXPLICIT_CREATOR_CONFIRMATION_REQUIRED",
              try c.decode(Bool.self, forKey: .packageReviewed) == false else { throw WorkshopCreatorConsentIssue.malformed }
        sourceTemplateId = try c.decode(Int64.self, forKey: .sourceTemplateId)
        templateHash = try c.decode(String.self, forKey: .templateHash); packageContentHash = try c.decode(String.self, forKey: .packageContentHash)
        packageSourceJson = try c.decode(String.self, forKey: .packageSourceJson)
        disclosureVersion = try c.decode(String.self, forKey: .disclosureVersion); disclosureHash = try c.decode(String.self, forKey: .disclosureHash)
        disclosureText = try c.decode(String.self, forKey: .disclosureText)
        omittedPlanningMetadata = try c.decode([String].self, forKey: .omittedPlanningMetadata)
        let allowedOmissions: Set<String> = ["categoryId", "activityCategoryids", "players", "usageLocation", "requiredMaterials", "duration", "difficulty"]
        guard sourceTemplateId > 0, WorkshopCreatorWire.hash(templateHash), WorkshopCreatorWire.hash(packageContentHash),
              packageSourceJson.utf8.count <= 262_144, WorkshopCreatorWire.sha(Data(packageSourceJson.utf8)) == packageContentHash,
              disclosureVersion == WorkshopCreatorDisclosure.version, disclosureHash == WorkshopCreatorDisclosure.hash,
              WorkshopCreatorWire.same(disclosureText, WorkshopCreatorDisclosure.text),
              Set(omittedPlanningMetadata).count == omittedPlanningMetadata.count, Set(omittedPlanningMetadata).isSubset(of: allowedOmissions),
              case let .object(object) = try ContentDraftJSON.parse(packageSourceJson),
              object[Data("schema".utf8)] == .string(Data("w18-member-text-v1".utf8)),
              object[Data("bindings".utf8)] == .object([:]) else { throw WorkshopCreatorConsentIssue.malformed }
        let allowed = Set(Self.fieldOrder + ["schema", "bindings"])
        var fields: [String: String] = [:]
        for (key, value) in object {
            guard let name = String(data: key, encoding: .utf8), allowed.contains(name) else { throw WorkshopCreatorConsentIssue.malformed }
            if ["schema", "bindings"].contains(name) { continue }
            guard case let .string(bytes) = value, let text = String(data: bytes, encoding: .utf8) else { throw WorkshopCreatorConsentIssue.malformed }
            fields[name] = text
        }
        guard let title = fields["title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (fields["description"]?.utf16.count ?? 0) <= 30 else { throw WorkshopCreatorConsentIssue.malformed }
        textFields = fields
    }
}
/// Durable metadata only. No protected source body, full terms, credential or automatic consent.
public struct WorkshopCreatorDeclarationCommand: Codable, Equatable {
    public let requestId: String, sourceTemplateId: Int64
    public let expectedTemplateHash, expectedPackageContentHash, moduleId, versionId, offerVersion, termsVersion, termsDocumentHash, displayedScopeHash: String
    public let acknowledgeExactTextPackage, allowUseInBuyersOwnPublishedThemes, prohibitPackageResaleAndRedistribution: Bool
    enum CodingKeys: String, CodingKey, CaseIterable {
        case requestId, sourceTemplateId, expectedTemplateHash, expectedPackageContentHash, moduleId, versionId, offerVersion
        case termsVersion, termsDocumentHash, displayedScopeHash, acknowledgeExactTextPackage, allowUseInBuyersOwnPublishedThemes, prohibitPackageResaleAndRedistribution
    }
    init(preview: WorkshopCreatorPreview, target: WorkshopCreatorDeclarationTarget, requestId: String = UUID().uuidString.lowercased()) throws {
        guard preview.sourceTemplateId == target.sourceTemplateId, WorkshopCreatorWire.uuid(requestId) else { throw WorkshopCreatorConsentIssue.invalid }
        self.requestId = requestId; sourceTemplateId = preview.sourceTemplateId; expectedTemplateHash = preview.templateHash
        expectedPackageContentHash = preview.packageContentHash; moduleId = target.moduleId; versionId = target.versionId
        offerVersion = target.offerVersion; termsVersion = target.termsVersion; termsDocumentHash = target.termsDocumentHash
        displayedScopeHash = preview.disclosureHash; acknowledgeExactTextPackage = true; allowUseInBuyersOwnPublishedThemes = true; prohibitPackageResaleAndRedistribution = true
    }
    public init(from decoder: Decoder) throws {
        try WorkshopCreatorWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decode(String.self, forKey: .requestId); sourceTemplateId = try c.decode(Int64.self, forKey: .sourceTemplateId)
        expectedTemplateHash = try c.decode(String.self, forKey: .expectedTemplateHash); expectedPackageContentHash = try c.decode(String.self, forKey: .expectedPackageContentHash)
        moduleId = try c.decode(String.self, forKey: .moduleId); versionId = try c.decode(String.self, forKey: .versionId)
        offerVersion = try c.decode(String.self, forKey: .offerVersion); termsVersion = try c.decode(String.self, forKey: .termsVersion)
        termsDocumentHash = try c.decode(String.self, forKey: .termsDocumentHash); displayedScopeHash = try c.decode(String.self, forKey: .displayedScopeHash)
        acknowledgeExactTextPackage = try c.decode(Bool.self, forKey: .acknowledgeExactTextPackage)
        allowUseInBuyersOwnPublishedThemes = try c.decode(Bool.self, forKey: .allowUseInBuyersOwnPublishedThemes)
        prohibitPackageResaleAndRedistribution = try c.decode(Bool.self, forKey: .prohibitPackageResaleAndRedistribution)
        guard sourceTemplateId > 0, WorkshopCreatorWire.uuid(requestId), [moduleId, versionId, offerVersion, termsVersion].allSatisfy(WorkshopCreatorWire.identifier),
              [expectedTemplateHash, expectedPackageContentHash, termsDocumentHash].allSatisfy(WorkshopCreatorWire.hash), displayedScopeHash == WorkshopCreatorDisclosure.hash,
              acknowledgeExactTextPackage, allowUseInBuyersOwnPublishedThemes, prohibitPackageResaleAndRedistribution else { throw WorkshopCreatorConsentIssue.malformed }
    }
    func data() throws -> Data { try WorkshopCreatorWire.encode(self) }
}
public struct WorkshopCreatorDeclarationReceipt: Decodable, Equatable {
    public struct Reference: Decodable, Equatable {
        public let scope, consentId: String
        public let creatorMemberId: Int64
        public let moduleId, versionId, contentHash, termsDocumentHash, recordHash: String
        enum CodingKeys: String, CodingKey, CaseIterable { case scope, consentId, creatorMemberId, moduleId, versionId, contentHash, termsDocumentHash, recordHash }
        public init(from decoder: Decoder) throws {
            try WorkshopCreatorWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            scope = try c.decode(String.self, forKey: .scope); consentId = try c.decode(String.self, forKey: .consentId)
            creatorMemberId = try c.decode(Int64.self, forKey: .creatorMemberId); moduleId = try c.decode(String.self, forKey: .moduleId)
            versionId = try c.decode(String.self, forKey: .versionId); contentHash = try c.decode(String.self, forKey: .contentHash)
            termsDocumentHash = try c.decode(String.self, forKey: .termsDocumentHash); recordHash = try c.decode(String.self, forKey: .recordHash)
            guard scope == "BUYER_OWN_PUBLISHED_THEMES", WorkshopCreatorWire.uuid(consentId), creatorMemberId > 0,
                  [moduleId, versionId].allSatisfy(WorkshopCreatorWire.identifier), [contentHash, termsDocumentHash, recordHash].allSatisfy(WorkshopCreatorWire.hash) else { throw WorkshopCreatorConsentIssue.malformed }
        }
    }
    public let consentReference: Reference
    public let sourceTemplateId: Int64
    public let templateHash, offerVersion, termsVersion, declaredAt, disclosureVersion, disclosureHash: String
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, state, consentReference, sourceTemplateId, templateHash, offerVersion, termsVersion, declaredAt
        case disclosureVersion, disclosureHash, packageReviewed, listed, licenseIssued
    }
    public init(from decoder: Decoder) throws {
        try WorkshopCreatorWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-creator-public-use-declaration-receipt-v1",
              try c.decode(String.self, forKey: .state) == "CREATOR_DECLARED_PENDING_PACKAGE_REVIEW",
              try c.decode(Bool.self, forKey: .packageReviewed) == false, try c.decode(Bool.self, forKey: .listed) == false,
              try c.decode(Bool.self, forKey: .licenseIssued) == false else { throw WorkshopCreatorConsentIssue.malformed }
        consentReference = try c.decode(Reference.self, forKey: .consentReference); sourceTemplateId = try c.decode(Int64.self, forKey: .sourceTemplateId)
        templateHash = try c.decode(String.self, forKey: .templateHash); offerVersion = try c.decode(String.self, forKey: .offerVersion)
        termsVersion = try c.decode(String.self, forKey: .termsVersion); declaredAt = try c.decode(String.self, forKey: .declaredAt)
        disclosureVersion = try c.decode(String.self, forKey: .disclosureVersion); disclosureHash = try c.decode(String.self, forKey: .disclosureHash)
        guard sourceTemplateId > 0, WorkshopCreatorWire.hash(templateHash), [offerVersion, termsVersion].allSatisfy(WorkshopCreatorWire.identifier),
              WorkshopPurchasedWire.timestamp(declaredAt), disclosureVersion == WorkshopCreatorDisclosure.version,
              disclosureHash == WorkshopCreatorDisclosure.hash else { throw WorkshopCreatorConsentIssue.malformed }
    }
    func matches(_ command: WorkshopCreatorDeclarationCommand, owner: Int64) -> Bool {
        let r = consentReference
        return r.creatorMemberId == owner && sourceTemplateId == command.sourceTemplateId && templateHash == command.expectedTemplateHash &&
            WorkshopCreatorWire.same(r.moduleId, command.moduleId) && WorkshopCreatorWire.same(r.versionId, command.versionId) &&
            r.contentHash == command.expectedPackageContentHash && r.termsDocumentHash == command.termsDocumentHash &&
            WorkshopCreatorWire.same(offerVersion, command.offerVersion) && WorkshopCreatorWire.same(termsVersion, command.termsVersion)
    }
}
public enum WorkshopCreatorDeclarationStatus: Decodable, Equatable {
    case notFound(String), recorded(WorkshopCreatorDeclarationReceipt)
    private enum CodingKeys: String, CodingKey { case schema, state, requestId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decode(String.self, forKey: .schema) == "w18-creator-public-use-declaration-status-v1" {
            try WorkshopCreatorWire.keys(decoder, ["schema", "state", "requestId"])
            let id = try c.decode(String.self, forKey: .requestId)
            guard WorkshopCreatorWire.uuid(id), try c.decode(String.self, forKey: .state) == "NOT_FOUND" else { throw WorkshopCreatorConsentIssue.malformed }
            self = .notFound(id)
        } else { self = .recorded(try WorkshopCreatorDeclarationReceipt(from: decoder)) }
    }
}
enum WorkshopCreatorWire {
    private struct Key: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    static func keys(_ decoder: Decoder, _ expected: Set<String>) throws {
        guard Set(try decoder.container(keyedBy: Key.self).allKeys.map(\.stringValue)) == expected else { throw WorkshopCreatorConsentIssue.malformed }
    }
    static func hash(_ s: String) -> Bool { s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func uuid(_ s: String) -> Bool { UUID(uuidString: s)?.uuidString.lowercased() == s }
    static func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    static func identifier(_ s: String) -> Bool { !s.isEmpty && s.utf8.count <= 128 && same(s, s.trimmingCharacters(in: .whitespacesAndNewlines)) && !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
    static func sha(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func encode<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(value) }
    static func decode<T: Decodable>(_ type: T.Type, data: Data, maximum: Int = 1_048_576) throws -> T {
        guard data.count <= maximum, let text = String(data: data, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil else { throw WorkshopCreatorConsentIssue.malformed }
        do { return try JSONDecoder().decode(type, from: data) } catch { throw WorkshopCreatorConsentIssue.malformed }
    }
}
