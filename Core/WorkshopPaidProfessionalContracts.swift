import Foundation

/// NEW staged owner professional-target/materialization contract. No purchased metadata grant,
/// body-read grant, historical receipt or local value authorizes a CMS write or publication.
public enum WorkshopPaidProfessionalIssue: Error, Equatable {
    case disabled, invalid, malformed, unavailable, unauthorized, staleSession, staleAction
    case storageUnavailable, pendingConflict, outcomeUnknown
}
public struct WorkshopPaidProfessionalTarget: Decodable, Equatable, Identifiable {
    public enum Mode: String, Codable { case city = "CITY_ORIENTATION", free = "FREE_EXPLORATION", unresolved = "UNRESOLVED" }
    public let topicId: Int64
    public let name: String
    public let productType, routeConfigVersion: Int64?
    public let mode: Mode
    public let ownerModeFingerprint: String
    public var id: Int64 { topicId }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case topicId, name, productType, mode, routeConfigVersion, ownerModeFingerprint, fingerprintProfile, materializationStatus
    }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topicId = try c.decode(Int64.self, forKey: .topicId); name = try c.decode(String.self, forKey: .name)
        productType = try c.decodeIfPresent(Int64.self, forKey: .productType); routeConfigVersion = try c.decodeIfPresent(Int64.self, forKey: .routeConfigVersion)
        mode = try c.decode(Mode.self, forKey: .mode); ownerModeFingerprint = try c.decode(String.self, forKey: .ownerModeFingerprint)
        let expected: Mode = productType == 1 ? .city : productType == 2 ? .free : .unresolved
        guard topicId > 0, name.utf16.count <= 256, name.utf8.count <= 1_024, mode == expected,
              routeConfigVersion == nil || routeConfigVersion! >= 0, WorkshopPurchasedWire.hash(ownerModeFingerprint),
              try c.decode(String.self, forKey: .fingerprintProfile) == "W18_CONTENT_OWNER_MODE_V1",
              try c.decode(String.self, forKey: .materializationStatus) == "PROTECTED_TEMPLATE_ADAPTER_REQUIRED" else { throw WorkshopPaidProfessionalIssue.malformed }
    }
}
public struct WorkshopPaidProfessionalTargets: Decodable {
    public let licenseId, checkedAt: String
    public let items: [WorkshopPaidProfessionalTarget]
    public let hasMore: Bool
    public let nextBeforeTopicId: Int64?
    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, scope, licenseId, checkedAt, items, hasMore, nextBeforeTopicId }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-owned-professional-topic-targets-v1",
              try c.decode(String.self, forKey: .scope) == "INDIVIDUAL_CONTENT_OWNER_AND_PUBLISHER_METADATA_ONLY" else { throw WorkshopPaidProfessionalIssue.malformed }
        licenseId = try c.decode(String.self, forKey: .licenseId); checkedAt = try c.decode(String.self, forKey: .checkedAt)
        items = try WorkshopPaidInstallWire.items(c.superDecoder(forKey: .items))
        hasMore = try c.decode(Bool.self, forKey: .hasMore); nextBeforeTopicId = try c.decodeIfPresent(Int64.self, forKey: .nextBeforeTopicId)
        guard WorkshopPurchasedWire.license(licenseId), WorkshopPurchasedWire.timestamp(checkedAt), Set(items.map(\.id)).count == items.count,
              zip(items, items.dropFirst()).allSatisfy({ $0.0.id > $0.1.id }), hasMore == (nextBeforeTopicId != nil),
              !hasMore || (items.count == 50 && nextBeforeTopicId == items.last?.id) else { throw WorkshopPaidProfessionalIssue.malformed }
    }
}
/// Only IDs, frozen hashes and explicit target confirmation are serialized. Protected content,
/// terms, credentials and any client-made owner/paid/permission flags are intentionally absent.
public struct WorkshopPaidProfessionalCommand: Codable, Equatable, Identifiable {
    public static let schemaValue = "w18-paid-professional-text-materialization-command-v1"
    public let schema, requestId, installationRequestId, licenseId, moduleId, purchasedVersionId, contentHash, termsHash, componentHash: String
    public let ownedDraftId, currentDraftRevision, targetTopicId: Int64
    public let currentDraftPayloadHash, targetOwnerModeFingerprint: String
    public let confirmedMode: WorkshopPaidProfessionalTarget.Mode
    public var id: String { requestId }
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, requestId, installationRequestId, licenseId, moduleId, purchasedVersionId, contentHash, termsHash, componentHash
        case ownedDraftId, currentDraftRevision, currentDraftPayloadHash, targetTopicId, targetOwnerModeFingerprint, confirmedMode
    }
    public init(reference: WorkshopPaidInstalledTextReference, body: WorkshopPaidInstalledText,
                currentDraft: WorkshopPaidInstallTarget, target: WorkshopPaidProfessionalTarget,
                confirmedMode: WorkshopPaidProfessionalTarget.Mode, requestID: UUID = UUID()) throws {
        guard body.matches(reference), body.originalBusinessType == "TOPIC", currentDraft.businessType == "TOPIC",
              currentDraft.targetDraftId == body.originalTargetDraftID, confirmedMode == target.mode, confirmedMode != .unresolved,
              reference.item.status == .active, body.rights.adaptation.rawValue == "LOCAL_ADAPTATION" else { throw WorkshopPaidProfessionalIssue.invalid }
        try self.init(requestId: requestID.uuidString.lowercased(), installationRequestId: body.requestID, licenseId: body.licenseID,
            moduleId: body.moduleID, purchasedVersionId: body.purchasedVersionID, contentHash: body.contentHash, termsHash: body.termsHash,
            componentHash: body.componentHash, ownedDraftId: body.ownedDraftID, currentDraftRevision: currentDraft.targetRevision,
            currentDraftPayloadHash: currentDraft.targetPayloadHash, targetTopicId: target.topicId, targetOwnerModeFingerprint: target.ownerModeFingerprint, confirmedMode: confirmedMode)
    }
    private init(requestId: String, installationRequestId: String, licenseId: String, moduleId: String, purchasedVersionId: String,
                 contentHash: String, termsHash: String, componentHash: String, ownedDraftId: Int64, currentDraftRevision: Int64,
                 currentDraftPayloadHash: String, targetTopicId: Int64, targetOwnerModeFingerprint: String, confirmedMode: WorkshopPaidProfessionalTarget.Mode) throws {
        guard WorkshopPaidInstallWire.requestID(requestId), WorkshopPaidInstallWire.requestID(installationRequestId), WorkshopPurchasedWire.license(licenseId),
              [moduleId, purchasedVersionId].allSatisfy({ WorkshopPaidInstallWire.text($0, 128) }),
              [contentHash, termsHash, componentHash, currentDraftPayloadHash, targetOwnerModeFingerprint].allSatisfy(WorkshopPurchasedWire.hash),
              ownedDraftId > 0, currentDraftRevision > 0, targetTopicId > 0, confirmedMode != .unresolved else { throw WorkshopPaidProfessionalIssue.invalid }
        schema = Self.schemaValue; self.requestId = requestId; self.installationRequestId = installationRequestId; self.licenseId = licenseId
        self.moduleId = moduleId; self.purchasedVersionId = purchasedVersionId; self.contentHash = contentHash; self.termsHash = termsHash
        self.componentHash = componentHash; self.ownedDraftId = ownedDraftId; self.currentDraftRevision = currentDraftRevision
        self.currentDraftPayloadHash = currentDraftPayloadHash; self.targetTopicId = targetTopicId
        self.targetOwnerModeFingerprint = targetOwnerModeFingerprint; self.confirmedMode = confirmedMode
    }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == Self.schemaValue else { throw WorkshopPaidProfessionalIssue.malformed }
        try self.init(requestId: c.decode(String.self, forKey: .requestId), installationRequestId: c.decode(String.self, forKey: .installationRequestId), licenseId: c.decode(String.self, forKey: .licenseId),
            moduleId: c.decode(String.self, forKey: .moduleId), purchasedVersionId: c.decode(String.self, forKey: .purchasedVersionId), contentHash: c.decode(String.self, forKey: .contentHash),
            termsHash: c.decode(String.self, forKey: .termsHash), componentHash: c.decode(String.self, forKey: .componentHash), ownedDraftId: c.decode(Int64.self, forKey: .ownedDraftId),
            currentDraftRevision: c.decode(Int64.self, forKey: .currentDraftRevision), currentDraftPayloadHash: c.decode(String.self, forKey: .currentDraftPayloadHash), targetTopicId: c.decode(Int64.self, forKey: .targetTopicId),
            targetOwnerModeFingerprint: c.decode(String.self, forKey: .targetOwnerModeFingerprint), confirmedMode: c.decode(WorkshopPaidProfessionalTarget.Mode.self, forKey: .confirmedMode))
    }
    func wireData() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; let data = try e.encode(self); guard data.count <= 4_096 else { throw WorkshopPaidProfessionalIssue.invalid }; return data }
    func matches(_ reference: WorkshopPaidInstalledTextReference) -> Bool {
        let c = reference.command
        return installationRequestId == c.requestId && licenseId == c.licenseId && WorkshopPaidInstallWire.same(moduleId, c.moduleId) && WorkshopPaidInstallWire.same(purchasedVersionId, c.purchasedVersionId) &&
            contentHash == c.contentHash && termsHash == c.termsHash && ownedDraftId == reference.ownedDraftID
    }
}
public struct WorkshopPaidProfessionalReceipt: Decodable, Equatable {
    public let templateId, targetTopicId, ownedDraftId: Int64
    public let confirmedMode: WorkshopPaidProfessionalTarget.Mode
    public let licenseId, purchasedVersionId, templateContentHash, createdAt: String
    public let missingProfessionalInputs: [String]
    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, templateId, targetTopicId, confirmedMode, ownedDraftId, licenseId, purchasedVersionId, templateContentHash, createdAt, state, missingProfessionalInputs, nodeAttached, published, executable }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templateId = try c.decode(Int64.self, forKey: .templateId); targetTopicId = try c.decode(Int64.self, forKey: .targetTopicId); ownedDraftId = try c.decode(Int64.self, forKey: .ownedDraftId)
        confirmedMode = try c.decode(WorkshopPaidProfessionalTarget.Mode.self, forKey: .confirmedMode); licenseId = try c.decode(String.self, forKey: .licenseId)
        purchasedVersionId = try c.decode(String.self, forKey: .purchasedVersionId); templateContentHash = try c.decode(String.self, forKey: .templateContentHash); createdAt = try c.decode(String.self, forKey: .createdAt)
        missingProfessionalInputs = try c.decode([String].self, forKey: .missingProfessionalInputs)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-professional-materialization-receipt-v1",
              try c.decode(String.self, forKey: .state) == "GUARDED_PRIVATE_TEMPLATE_CREATED",
              try c.decode(Bool.self, forKey: .nodeAttached) == false, try c.decode(Bool.self, forKey: .published) == false, try c.decode(Bool.self, forKey: .executable) == false,
              templateId > 0, targetTopicId > 0, ownedDraftId > 0, confirmedMode != .unresolved, WorkshopPurchasedWire.license(licenseId),
              WorkshopPaidInstallWire.text(purchasedVersionId, 128), WorkshopPurchasedWire.hash(templateContentHash), WorkshopPurchasedWire.timestamp(createdAt),
              Set(missingProfessionalInputs).count == missingProfessionalInputs.count,
              Set(missingProfessionalInputs).isSubset(of: ["description", "players", "duration", "category", "questionName", "questionAnswer"]),
              Set(["players", "duration", "category"]).isSubset(of: Set(missingProfessionalInputs)) else { throw WorkshopPaidProfessionalIssue.malformed }
    }
    func matches(_ command: WorkshopPaidProfessionalCommand) -> Bool {
        targetTopicId == command.targetTopicId && confirmedMode == command.confirmedMode && ownedDraftId == command.ownedDraftId &&
            licenseId == command.licenseId && WorkshopPaidInstallWire.same(purchasedVersionId, command.purchasedVersionId)
    }
}
/// Recovery metadata is explicitly historical. Never turn it into a current template, a body-read
/// reference, an editable draft or a publish/run approval.
public struct WorkshopPaidProfessionalHistory: Decodable, Equatable {
    public enum State: String, Decodable { case notFound = "NOT_FOUND", committed = "CREATION_COMMITTED" }
    public let requestId: String
    public let state: State
    public let templateId, targetTopicId, ownedDraftId: Int64?
    public let confirmedMode: WorkshopPaidProfessionalTarget.Mode?
    public let licenseId, purchasedVersionId, templateContentHash, createdAt: String?
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, scope, requestId, state, templateId, targetTopicId, ownedDraftId, confirmedMode, licenseId, purchasedVersionId, templateContentHash, createdAt, currentTemplateState, currentUseAuthority
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-professional-materialization-status-v1",
              try c.decode(String.self, forKey: .scope) == "OWNER_HISTORICAL_CREATION_REFERENCE_ONLY" else { throw WorkshopPaidProfessionalIssue.malformed }
        requestId = try c.decode(String.self, forKey: .requestId); state = try c.decode(State.self, forKey: .state)
        guard WorkshopPaidInstallWire.requestID(requestId) else { throw WorkshopPaidProfessionalIssue.malformed }
        if state == .notFound {
            try WorkshopPaidInstallWire.keys(decoder, ["schema", "scope", "requestId", "state"])
            templateId = nil; targetTopicId = nil; ownedDraftId = nil; confirmedMode = nil
            licenseId = nil; purchasedVersionId = nil; templateContentHash = nil; createdAt = nil
        } else {
            try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
            let template = try c.decode(Int64.self, forKey: .templateId), target = try c.decode(Int64.self, forKey: .targetTopicId), owned = try c.decode(Int64.self, forKey: .ownedDraftId)
            let mode = try c.decode(WorkshopPaidProfessionalTarget.Mode.self, forKey: .confirmedMode)
            let license = try c.decode(String.self, forKey: .licenseId), version = try c.decode(String.self, forKey: .purchasedVersionId)
            let hash = try c.decode(String.self, forKey: .templateContentHash), created = try c.decode(String.self, forKey: .createdAt)
            guard template > 0, target > 0, owned > 0, mode != .unresolved, WorkshopPurchasedWire.license(license), WorkshopPaidInstallWire.text(version, 128),
                  WorkshopPurchasedWire.hash(hash), WorkshopPurchasedWire.timestamp(created),
                  try c.decode(String.self, forKey: .currentTemplateState) == "NOT_CHECKED",
                  try c.decode(String.self, forKey: .currentUseAuthority) == "NOT_GRANTED_BY_HISTORY" else { throw WorkshopPaidProfessionalIssue.malformed }
            templateId = template; targetTopicId = target; ownedDraftId = owned; confirmedMode = mode
            licenseId = license; purchasedVersionId = version; templateContentHash = hash; createdAt = created
        }
    }
    func matches(_ command: WorkshopPaidProfessionalCommand) -> Bool {
        guard requestId == command.requestId else { return false }
        if state == .notFound { return true }
        return targetTopicId == command.targetTopicId && ownedDraftId == command.ownedDraftId && confirmedMode == command.confirmedMode &&
            licenseId == command.licenseId && purchasedVersionId.map { WorkshopPaidInstallWire.same($0, command.purchasedVersionId) } == true
    }
    func confirms(_ receipt: WorkshopPaidProfessionalReceipt) -> Bool {
        state == .committed && templateId == receipt.templateId && targetTopicId == receipt.targetTopicId && ownedDraftId == receipt.ownedDraftId &&
            confirmedMode == receipt.confirmedMode && licenseId == receipt.licenseId && templateContentHash == receipt.templateContentHash && createdAt == receipt.createdAt &&
            purchasedVersionId.map { WorkshopPaidInstallWire.same($0, receipt.purchasedVersionId) } == true
    }
}
