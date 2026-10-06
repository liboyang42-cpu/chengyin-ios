import Foundation
import CryptoKit

/// NEW protected read contract. Metadata and an installation receipt are references, not body-read
/// approval. This model is deliberately not Encodable or a TemplateAuthoringDraft.
public enum WorkshopPaidInstalledTextIssue: Error, Equatable {
    case disabled, invalid, malformed, unavailable, unauthorized, staleSession, staleAction
}
public struct WorkshopPaidInstalledTextReference: Equatable {
    public let item: WorkshopPurchasedItem
    public let receipt: WorkshopPaidInstallOutcome
    public let command: WorkshopPaidInstallCommand
    public let ownedDraftID: Int64
    public init(item: WorkshopPurchasedItem, receipt: WorkshopPaidInstallOutcome) throws {
        guard receipt.state == .installed, let command = receipt.command, command.belongs(to: item),
              let owned = receipt.ownedDraftId, owned > 0, receipt.installedAt != nil else { throw WorkshopPaidInstalledTextIssue.invalid }
        self.item = item; self.receipt = receipt; self.command = command; ownedDraftID = owned
    }
}
public struct WorkshopPaidInstalledTextFields: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let names = ["title", "description", "ruleInstructions", "merchantGuide", "questionName", "questionAnswer", "hint1", "hint2", "answerReveal"]
    private let values: [String: Data]
    public subscript(_ name: String) -> String? { values[name].flatMap { String(data: $0, encoding: .utf8) } }
    public var description: String { "WorkshopPaidInstalledTextFields[redacted]" }
    public var debugDescription: String { description }
    static func decode(_ text: String, component: Bool) throws -> Self {
        guard text.utf8.count <= (component ? 266_240 : 262_144),
              case .object(let fields) = try ContentDraftJSON.parse(text),
              fields[Data("schema".utf8)] == .string(Data("w18-member-text-v1".utf8)),
              fields[Data("bindings".utf8)] == .object([:]) else { throw WorkshopPaidInstalledTextIssue.malformed }
        let expected = Set((names + ["schema", "bindings"] + (component ? ["validationMethod"] : [])).map { Data($0.utf8) })
        guard Set(fields.keys).isSubset(of: expected), fields[Data("title".utf8)] != nil else { throw WorkshopPaidInstalledTextIssue.malformed }
        if component {
            guard fields[Data("validationMethod".utf8)] == .number(negative: false, digits: "1", exponent: 0) else { throw WorkshopPaidInstalledTextIssue.malformed }
        }
        var values: [String: Data] = [:]
        for name in names {
            if let value = fields[Data(name.utf8)] {
                guard case .string(let bytes) = value, String(data: bytes, encoding: .utf8) != nil else { throw WorkshopPaidInstalledTextIssue.malformed }
                values[name] = bytes
            }
        }
        guard let title = values["title"].flatMap({ String(data: $0, encoding: .utf8) }), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkshopPaidInstalledTextIssue.malformed }
        return Self(values: values)
    }
}
public struct WorkshopPaidInstalledTextRights: Decodable, Equatable {
    public let commercialUse, translation: WorkshopPurchasedItem.Permission
    public let adaptation: WorkshopPurchasedItem.Adaptation
    public let allowedRegions: [String]
    public let themeLimit, merchantLimit, runLimit: WorkshopPurchasedItem.Limit
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case useDuration, commercialUse, adaptation, translation, updates, redistribution, allowedRegions, themeLimit, merchantLimit, runLimit
    }
    public init(from decoder: Decoder) throws {
        try WorkshopPurchasedWire.exactKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .useDuration) == "PERPETUAL_PURCHASED_VERSION",
              try c.decode(String.self, forKey: .updates) == "EXACT_PURCHASED_VERSION",
              try c.decode(String.self, forKey: .redistribution) == "PROHIBITED" else { throw WorkshopPaidInstalledTextIssue.malformed }
        commercialUse = try c.decode(WorkshopPurchasedItem.Permission.self, forKey: .commercialUse)
        translation = try c.decode(WorkshopPurchasedItem.Permission.self, forKey: .translation)
        adaptation = try c.decode(WorkshopPurchasedItem.Adaptation.self, forKey: .adaptation)
        allowedRegions = try c.decode([String].self, forKey: .allowedRegions)
        themeLimit = try c.decode(WorkshopPurchasedItem.Limit.self, forKey: .themeLimit)
        merchantLimit = try c.decode(WorkshopPurchasedItem.Limit.self, forKey: .merchantLimit)
        runLimit = try c.decode(WorkshopPurchasedItem.Limit.self, forKey: .runLimit)
        guard !allowedRegions.isEmpty, allowedRegions.count <= 32,
              Set(allowedRegions.map { Data($0.utf8) }).count == allowedRegions.count,
              allowedRegions.allSatisfy({ WorkshopPurchasedWire.bounded($0, 128) }) else { throw WorkshopPaidInstalledTextIssue.malformed }
    }
    func matches(_ item: WorkshopPurchasedItem) -> Bool {
        commercialUse == item.commercialUse && translation == item.translation && adaptation == item.adaptation &&
        Set(allowedRegions.map { Data($0.utf8) }) == Set(item.allowedRegions.map { Data($0.utf8) }) &&
        themeLimit == item.themeLimit && merchantLimit == item.merchantLimit && runLimit == item.runLimit
    }
}
/// Transient protected data. No generic save, share, editor export or publication representation.
public struct WorkshopPaidInstalledText: Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    public let requestID, licenseID, moduleID, purchasedVersionID, version: String
    public let contentHash, componentHash, installedAt, checkedAt: String
    public let ownedDraftID, ownedDraftRevision, originalTargetDraftID, originalTargetRevision: Int64
    public let originalTargetPayloadHash, originalBusinessType: String
    public let sourceJSON, componentJSON: String
    public let sourceFields, installedFields: WorkshopPaidInstalledTextFields
    public let termsVersion, termsHash, termsDocumentHash: String
    public let termsDocument: Data
    public let rights: WorkshopPaidInstalledTextRights
    public var description: String { "WorkshopPaidInstalledText[redacted]" }
    public var debugDescription: String { description }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, scope, requestId, licenseId, moduleId, purchasedVersionId, version, contentHash, componentHash
        case ownedDraftId, ownedDraftRevision, installedAt, checkedAt, originalTargetDraftId, originalTargetRevision, originalTargetPayloadHash, originalBusinessType
        case mode, sourceJson, componentJson, termsVersion, termsHash, termsDocumentHash, termsDocumentBase64, rights, professionalTemplateStatus, published, executable
    }
    public init(from decoder: Decoder) throws {
        try WorkshopPurchasedWire.exactKeys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-installed-text-v1",
              try c.decode(String.self, forKey: .scope) == "OWNER_PAID_INSTALLED_TEXT_PROTECTED_READ_ONLY",
              try c.decode(String.self, forKey: .mode) == "UNRESOLVED",
              try c.decode(String.self, forKey: .professionalTemplateStatus) == "MATERIALIZATION_REQUIRED",
              try c.decode(Bool.self, forKey: .published) == false, try c.decode(Bool.self, forKey: .executable) == false else { throw WorkshopPaidInstalledTextIssue.malformed }
        requestID = try c.decode(String.self, forKey: .requestId); licenseID = try c.decode(String.self, forKey: .licenseId)
        moduleID = try c.decode(String.self, forKey: .moduleId); purchasedVersionID = try c.decode(String.self, forKey: .purchasedVersionId)
        version = try c.decode(String.self, forKey: .version); contentHash = try c.decode(String.self, forKey: .contentHash)
        componentHash = try c.decode(String.self, forKey: .componentHash); installedAt = try c.decode(String.self, forKey: .installedAt)
        checkedAt = try c.decode(String.self, forKey: .checkedAt); ownedDraftID = try c.decode(Int64.self, forKey: .ownedDraftId)
        ownedDraftRevision = try c.decode(Int64.self, forKey: .ownedDraftRevision); originalTargetDraftID = try c.decode(Int64.self, forKey: .originalTargetDraftId)
        originalTargetRevision = try c.decode(Int64.self, forKey: .originalTargetRevision)
        originalTargetPayloadHash = try c.decode(String.self, forKey: .originalTargetPayloadHash); originalBusinessType = try c.decode(String.self, forKey: .originalBusinessType)
        sourceJSON = try c.decode(String.self, forKey: .sourceJson); componentJSON = try c.decode(String.self, forKey: .componentJson)
        termsVersion = try c.decode(String.self, forKey: .termsVersion); termsHash = try c.decode(String.self, forKey: .termsHash)
        termsDocumentHash = try c.decode(String.self, forKey: .termsDocumentHash); rights = try c.decode(WorkshopPaidInstalledTextRights.self, forKey: .rights)
        let encoded = try c.decode(String.self, forKey: .termsDocumentBase64)
        guard encoded.utf8.count <= 87_380, let document = Data(base64Encoded: encoded), !document.isEmpty, document.count <= 65_535,
              document.base64EncodedString().utf8.elementsEqual(encoded.utf8) else { throw WorkshopPaidInstalledTextIssue.malformed }
        termsDocument = document
        sourceFields = try WorkshopPaidInstalledTextFields.decode(sourceJSON, component: false)
        installedFields = try WorkshopPaidInstalledTextFields.decode(componentJSON, component: true)
        guard sourceFields == installedFields, WorkshopPaidInstallWire.requestID(requestID), WorkshopPurchasedWire.license(licenseID),
              [moduleID, purchasedVersionID, termsVersion].allSatisfy({ WorkshopPurchasedWire.bounded($0, 128) }), WorkshopPurchasedWire.bounded(version, 65_536),
              [contentHash, componentHash, termsHash, termsDocumentHash, originalTargetPayloadHash].allSatisfy(WorkshopPurchasedWire.hash),
              WorkshopPurchasedWire.timestamp(installedAt), WorkshopPurchasedWire.timestamp(checkedAt), ownedDraftID > 0, ownedDraftRevision == 1,
              originalTargetDraftID > 0, originalTargetRevision > 0, ["TOPIC", "ACTIVITY"].contains(originalBusinessType),
              ContentDraftRecord.hash(sourceJSON) == contentHash, ContentDraftRecord.hash(componentJSON) == componentHash,
              SHA256.hash(data: document).map({ String(format: "%02x", $0) }).joined() == termsDocumentHash else { throw WorkshopPaidInstalledTextIssue.malformed }
    }
    func matches(_ reference: WorkshopPaidInstalledTextReference) -> Bool {
        let c = reference.command
        return WorkshopPaidInstallWire.same(requestID, c.requestId) && WorkshopPaidInstallWire.same(licenseID, c.licenseId) &&
        WorkshopPaidInstallWire.same(moduleID, c.moduleId) && WorkshopPaidInstallWire.same(purchasedVersionID, c.purchasedVersionId) &&
        contentHash == c.contentHash && termsHash == c.termsHash && ownedDraftID == reference.ownedDraftID &&
        originalTargetDraftID == c.targetDraftId && originalTargetRevision == c.targetRevision && originalTargetPayloadHash == c.targetPayloadHash &&
        originalBusinessType == c.businessType && installedAt == reference.receipt.installedAt &&
        WorkshopPaidInstallWire.same(termsVersion, reference.item.termsVersion) && rights.matches(reference.item)
    }
}
