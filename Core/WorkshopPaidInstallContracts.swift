import Foundation

/// NEW staged private-install protocol. None of these values prove payment or authorize publishing.
public enum WorkshopPaidInstallIssue: Error, Equatable {
    case disabled, invalid, malformed, unavailable, unauthorized, staleSession, staleAction
    case storageUnavailable, pendingConflict, outcomeUnknown
}
public struct WorkshopPaidInstallTarget: Codable, Equatable, Identifiable {
    public let targetDraftId, targetRevision: Int64
    public let businessType, targetPayloadHash: String
    public var id: Int64 { targetDraftId }
    public var mode: String { "UNRESOLVED" }
    public var destinationKind: String { "W18_PRIVATE_COMPONENT_ONLY" }
    private enum CodingKeys: String, CodingKey, CaseIterable { case targetDraftId, targetRevision, businessType, targetPayloadHash, mode, destinationKind }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetDraftId = try c.decode(Int64.self, forKey: .targetDraftId); targetRevision = try c.decode(Int64.self, forKey: .targetRevision)
        businessType = try c.decode(String.self, forKey: .businessType); targetPayloadHash = try c.decode(String.self, forKey: .targetPayloadHash)
        guard targetDraftId > 0, targetRevision > 0, ["TOPIC", "ACTIVITY"].contains(businessType), WorkshopPurchasedWire.hash(targetPayloadHash),
              try c.decode(String.self, forKey: .mode) == mode, try c.decode(String.self, forKey: .destinationKind) == destinationKind else { throw WorkshopPaidInstallIssue.malformed }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(targetDraftId, forKey: .targetDraftId); try c.encode(targetRevision, forKey: .targetRevision)
        try c.encode(businessType, forKey: .businessType); try c.encode(targetPayloadHash, forKey: .targetPayloadHash)
        try c.encode(mode, forKey: .mode); try c.encode(destinationKind, forKey: .destinationKind)
    }
}
public struct WorkshopPaidInstallCommand: Codable, Equatable, Identifiable {
    public let schema: String
    public let requestId, licenseId, moduleId, purchasedVersionId, contentHash, termsHash: String
    public let targetDraftId, targetRevision: Int64
    public let businessType, targetPayloadHash, planningRegion: String
    public let commercialUse: Bool
    public var id: String { requestId }
    static let schemaValue = "w18-paid-private-text-install-command-v1"
    enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, requestId, licenseId, moduleId, purchasedVersionId, contentHash, termsHash
        case targetDraftId, targetRevision, businessType, targetPayloadHash, planningRegion, commercialUse
    }
    public init(item: WorkshopPurchasedItem, target: WorkshopPaidInstallTarget, region: String, commercialUse: Bool, requestID: UUID = UUID()) throws {
        guard item.status == .active, item.allowedRegions.contains(where: { WorkshopPaidInstallWire.same($0, region) }),
              !commercialUse || item.commercialUse == .allowed else { throw WorkshopPaidInstallIssue.invalid }
        try self.init(requestId: requestID.uuidString.lowercased(), licenseId: item.licenseId, moduleId: item.moduleId,
            purchasedVersionId: item.purchasedVersionId, contentHash: item.contentHash, termsHash: item.termsHash,
            targetDraftId: target.targetDraftId, targetRevision: target.targetRevision, businessType: target.businessType,
            targetPayloadHash: target.targetPayloadHash, planningRegion: region, commercialUse: commercialUse)
    }
    init(requestId: String, licenseId: String, moduleId: String, purchasedVersionId: String, contentHash: String, termsHash: String,
         targetDraftId: Int64, targetRevision: Int64, businessType: String, targetPayloadHash: String, planningRegion: String, commercialUse: Bool) throws {
        guard WorkshopPaidInstallWire.requestID(requestId), WorkshopPurchasedWire.license(licenseId),
              [moduleId, purchasedVersionId, planningRegion].allSatisfy({ WorkshopPaidInstallWire.text($0, 128) }),
              [contentHash, termsHash, targetPayloadHash].allSatisfy(WorkshopPurchasedWire.hash), targetDraftId > 0, targetRevision > 0,
              ["TOPIC", "ACTIVITY"].contains(businessType) else { throw WorkshopPaidInstallIssue.invalid }
        schema = Self.schemaValue; self.requestId = requestId; self.licenseId = licenseId; self.moduleId = moduleId
        self.purchasedVersionId = purchasedVersionId; self.contentHash = contentHash; self.termsHash = termsHash
        self.targetDraftId = targetDraftId; self.targetRevision = targetRevision; self.businessType = businessType
        self.targetPayloadHash = targetPayloadHash; self.planningRegion = planningRegion; self.commercialUse = commercialUse
    }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == Self.schemaValue else { throw WorkshopPaidInstallIssue.malformed }
        try self.init(requestId: c.decode(String.self, forKey: .requestId), licenseId: c.decode(String.self, forKey: .licenseId), moduleId: c.decode(String.self, forKey: .moduleId),
            purchasedVersionId: c.decode(String.self, forKey: .purchasedVersionId), contentHash: c.decode(String.self, forKey: .contentHash), termsHash: c.decode(String.self, forKey: .termsHash),
            targetDraftId: c.decode(Int64.self, forKey: .targetDraftId), targetRevision: c.decode(Int64.self, forKey: .targetRevision), businessType: c.decode(String.self, forKey: .businessType),
            targetPayloadHash: c.decode(String.self, forKey: .targetPayloadHash), planningRegion: c.decode(String.self, forKey: .planningRegion), commercialUse: c.decode(Bool.self, forKey: .commercialUse))
    }
    public func belongs(to item: WorkshopPurchasedItem) -> Bool {
        WorkshopPaidInstallWire.same(licenseId, item.licenseId) && WorkshopPaidInstallWire.same(moduleId, item.moduleId) &&
        WorkshopPaidInstallWire.same(purchasedVersionId, item.purchasedVersionId) && contentHash == item.contentHash && termsHash == item.termsHash
    }
    func wireData() throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(self) }
}
public struct WorkshopPaidInstallOutcome: Decodable, Equatable, Identifiable {
    public enum State: String, Decodable {
        case notFound = "NOT_FOUND", prepared = "PREPARED", reserved = "RESERVED", expired = "EXPIRED"
        case cancelled = "CANCELLED", failed = "FAILED", installed = "INSTALLED_PRIVATE_DRAFT"
        public var terminal: Bool { [.expired, .cancelled, .failed, .installed].contains(self) }
    }
    public let requestId: String
    public let state: State
    public let command: WorkshopPaidInstallCommand?
    public let holdDeadline: String?
    public let ownedDraftId: Int64?
    public let installedAt: String?
    public var id: String { requestId }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, requestId, state, licenseId, moduleId, purchasedVersionId, contentHash, termsHash
        case targetDraftId, targetRevision, targetPayloadHash, businessType, planningRegion, commercialUse
        case mode, holdDeadline, ownedDraftId, installedAt, professionalTemplateStatus, published, executable
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-install-outcome-v1" else { throw WorkshopPaidInstallIssue.malformed }
        requestId = try c.decode(String.self, forKey: .requestId); state = try c.decode(State.self, forKey: .state)
        guard WorkshopPaidInstallWire.requestID(requestId) else { throw WorkshopPaidInstallIssue.malformed }
        if state == .notFound {
            try WorkshopPaidInstallWire.keys(decoder, ["schema", "requestId", "state"])
            command = nil; holdDeadline = nil; ownedDraftId = nil; installedAt = nil; return
        }
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        command = try WorkshopPaidInstallCommand(requestId: requestId, licenseId: c.decode(String.self, forKey: .licenseId), moduleId: c.decode(String.self, forKey: .moduleId),
            purchasedVersionId: c.decode(String.self, forKey: .purchasedVersionId), contentHash: c.decode(String.self, forKey: .contentHash), termsHash: c.decode(String.self, forKey: .termsHash),
            targetDraftId: c.decode(Int64.self, forKey: .targetDraftId), targetRevision: c.decode(Int64.self, forKey: .targetRevision), businessType: c.decode(String.self, forKey: .businessType),
            targetPayloadHash: c.decode(String.self, forKey: .targetPayloadHash), planningRegion: c.decode(String.self, forKey: .planningRegion), commercialUse: c.decode(Bool.self, forKey: .commercialUse))
        holdDeadline = try c.decode(String.self, forKey: .holdDeadline); ownedDraftId = try c.decodeIfPresent(Int64.self, forKey: .ownedDraftId); installedAt = try c.decodeIfPresent(String.self, forKey: .installedAt)
        guard WorkshopPurchasedWire.timestamp(holdDeadline!), try c.decode(String.self, forKey: .mode) == "UNRESOLVED",
              try c.decode(String.self, forKey: .professionalTemplateStatus) == "MATERIALIZATION_REQUIRED",
              try c.decode(Bool.self, forKey: .published) == false, try c.decode(Bool.self, forKey: .executable) == false else { throw WorkshopPaidInstallIssue.malformed }
        if state == .installed { guard let ownedDraftId, ownedDraftId > 0, let installedAt, WorkshopPurchasedWire.timestamp(installedAt) else { throw WorkshopPaidInstallIssue.malformed } }
        else { guard ownedDraftId == nil, installedAt == nil else { throw WorkshopPaidInstallIssue.malformed } }
    }
    func matches(_ expected: WorkshopPaidInstallCommand) -> Bool {
        guard requestId == expected.requestId else { return false }
        if state == .notFound { return true }
        guard let command, let actual = try? command.wireData(), let wanted = try? expected.wireData() else { return false }; return actual == wanted
    }
}
public struct WorkshopPaidInstallTargets: Decodable {
    public let licenseId: String, checkedAt: String
    public let items: [WorkshopPaidInstallTarget]
    public let nextBeforeDraftId: Int64?
    public let hasMore: Bool
    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, scope, licenseId, checkedAt, items, nextBeforeDraftId, hasMore }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-install-targets-v1", try c.decode(String.self, forKey: .scope) == "OWNER_DRAFT_METADATA_ONLY" else { throw WorkshopPaidInstallIssue.malformed }
        licenseId = try c.decode(String.self, forKey: .licenseId); checkedAt = try c.decode(String.self, forKey: .checkedAt)
        hasMore = try c.decode(Bool.self, forKey: .hasMore); nextBeforeDraftId = try c.decodeIfPresent(Int64.self, forKey: .nextBeforeDraftId)
        items = try WorkshopPaidInstallWire.items(c.superDecoder(forKey: .items))
        guard WorkshopPurchasedWire.license(licenseId), WorkshopPurchasedWire.timestamp(checkedAt), Set(items.map(\.id)).count == items.count,
              zip(items, items.dropFirst()).allSatisfy({ $0.0.id > $0.1.id }), hasMore == (nextBeforeDraftId != nil),
              !hasMore || (items.count == 50 && nextBeforeDraftId == items.last?.id) else { throw WorkshopPaidInstallIssue.malformed }
    }
}
public struct WorkshopPaidInstallHistory: Decodable {
    public let licenseId: String, checkedAt: String
    public let items: [WorkshopPaidInstallOutcome]
    public let nextBeforeCommandKey: String?
    public let hasMore: Bool
    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, scope, licenseId, checkedAt, items, nextBeforeCommandKey, hasMore }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-install-history-v1", try c.decode(String.self, forKey: .scope) == "OWNER_COMMAND_RECEIPTS_ONLY" else { throw WorkshopPaidInstallIssue.malformed }
        licenseId = try c.decode(String.self, forKey: .licenseId); checkedAt = try c.decode(String.self, forKey: .checkedAt)
        hasMore = try c.decode(Bool.self, forKey: .hasMore); nextBeforeCommandKey = try c.decodeIfPresent(String.self, forKey: .nextBeforeCommandKey)
        items = try WorkshopPaidInstallWire.items(c.superDecoder(forKey: .items))
        guard WorkshopPurchasedWire.license(licenseId), WorkshopPurchasedWire.timestamp(checkedAt), Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ $0.state != .notFound && $0.command?.licenseId == licenseId }), hasMore == (nextBeforeCommandKey != nil),
              nextBeforeCommandKey.map(WorkshopPurchasedWire.hash) != false, !hasMore || items.count == 50 else { throw WorkshopPaidInstallIssue.malformed }
    }
}
enum WorkshopPaidInstallWire {
    static func keys(_ decoder: Decoder, _ expected: Set<String>) throws { do { try WorkshopPurchasedWire.exactKeys(decoder, expected) } catch { throw WorkshopPaidInstallIssue.malformed } }
    static func same(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    static func requestID(_ s: String) -> Bool { s.range(of: #"\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z"#, options: .regularExpression) != nil }
    static func text(_ s: String, _ limit: Int) -> Bool { !s.isEmpty && s.utf8.count <= limit && s == s.trimmingCharacters(in: .whitespacesAndNewlines) && !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
    static func items<T: Decodable>(_ decoder: Decoder) throws -> [T] { var c = try decoder.unkeyedContainer(), values: [T] = []; while !c.isAtEnd { guard values.count < 50 else { throw WorkshopPaidInstallIssue.malformed }; values.append(try c.decode(T.self)) }; return values }
    static func decode<T: Decodable>(_ type: T.Type, data: Data, maximum: Int = 524_288) throws -> T {
        guard data.count <= maximum, let text = String(data: data, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil else { throw WorkshopPaidInstallIssue.malformed }
        do { return try JSONDecoder().decode(type, from: data) } catch { throw WorkshopPaidInstallIssue.malformed }
    }
}
