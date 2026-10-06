import Foundation
import CryptoKit

extension WorkshopPaidProfessionalCommand {
    /// Exact new server digest: UTF-8 values, 4-byte big-endian length prefixes, fixed field order.
    /// This binds an operation response to a local intent; it is not a payment or permission proof.
    public var commandHash: String {
        let fields = [schema, requestId, installationRequestId, String(ownedDraftId), licenseId, moduleId, purchasedVersionId,
                      contentHash, termsHash, componentHash, String(currentDraftRevision), currentDraftPayloadHash,
                      String(targetTopicId), targetOwnerModeFingerprint, confirmedMode.rawValue]
        var data = Data()
        for field in fields {
            let bytes = Array(field.utf8), size = UInt32(bytes.count)
            data.append(contentsOf: [UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
            data.append(contentsOf: bytes)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
public struct WorkshopPaidProfessionalOperation: Decodable, Equatable {
    public enum State: String, Decodable {
        case notFound = "NOT_FOUND", prepared = "PREPARED", created = "CREATED", rejected = "REJECTED", cancelled = "CANCELLED"
        public var terminal: Bool { self == .created || self == .rejected || self == .cancelled }
    }
    public let requestId: String
    public let state: State
    public let safeToReplace: Bool
    public let commandHash, createdAt, updatedAt, rejectionCode: String?
    public let creation: WorkshopPaidProfessionalHistory?
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schema, scope, requestId, state, safeToReplace, commandHash, createdAt, updatedAt, rejectionCode, creation
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-professional-operation-v1",
              try c.decode(String.self, forKey: .scope) == "OWNER_OPERATION_METADATA_ONLY" else { throw WorkshopPaidProfessionalIssue.malformed }
        requestId = try c.decode(String.self, forKey: .requestId); state = try c.decode(State.self, forKey: .state)
        safeToReplace = try c.decode(Bool.self, forKey: .safeToReplace)
        guard WorkshopPaidInstallWire.requestID(requestId), safeToReplace == (state == .rejected || state == .cancelled) else { throw WorkshopPaidProfessionalIssue.malformed }
        if state == .notFound {
            try WorkshopPaidInstallWire.keys(decoder, ["schema", "scope", "requestId", "state", "safeToReplace"])
            commandHash = nil; createdAt = nil; updatedAt = nil; rejectionCode = nil; creation = nil
        } else {
            try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
            let hash = try c.decode(String.self, forKey: .commandHash), created = try c.decode(String.self, forKey: .createdAt), updated = try c.decode(String.self, forKey: .updatedAt)
            guard WorkshopPurchasedWire.hash(hash), let start = Self.timestamp(created), let last = Self.timestamp(updated), last >= start else { throw WorkshopPaidProfessionalIssue.malformed }
            commandHash = hash; createdAt = created; updatedAt = updated
            rejectionCode = try c.decodeIfPresent(String.self, forKey: .rejectionCode)
            creation = try c.decodeIfPresent(WorkshopPaidProfessionalHistory.self, forKey: .creation)
            if state == .created {
                guard let creation, creation.state == .committed, creation.requestId == requestId, rejectionCode == nil else { throw WorkshopPaidProfessionalIssue.malformed }
            } else { guard creation == nil else { throw WorkshopPaidProfessionalIssue.malformed } }
            if state == .rejected { guard let rejectionCode, Self.rejection(rejectionCode) else { throw WorkshopPaidProfessionalIssue.malformed } }
            else { guard rejectionCode == nil else { throw WorkshopPaidProfessionalIssue.malformed } }
        }
    }
    func matches(_ command: WorkshopPaidProfessionalCommand) -> Bool {
        guard requestId == command.requestId else { return false }
        if state == .notFound { return true } // Still NOT safe to clear/replace this intent.
        guard commandHash == command.commandHash else { return false }
        return creation == nil || creation?.matches(command) == true
    }
    private static func rejection(_ value: String) -> Bool {
        if value == "CURRENT_SOURCE_OR_TARGET_UNAVAILABLE" { return true }
        return WorkshopPaidInstalledTextFields.names.contains { value == "SOURCE_FIELD_REJECTED_" + $0 }
    }
    private static func timestamp(_ value: String) -> Date? {
        guard WorkshopPurchasedWire.timestamp(value) else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: value)
    }
}
/// A discovery page is a list of the owner's prior intents. It never grants use or proves an
/// operation absent/terminal. A separately fenced status read follows selection.
public struct WorkshopPaidProfessionalOperationReference: Decodable, Identifiable {
    public let operationKey, commandHash, createdAt: String
    public let command: WorkshopPaidProfessionalCommand
    public var id: String { operationKey }
    private enum CodingKeys: String, CodingKey, CaseIterable { case operationKey, commandHash, createdAt, command }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationKey = try c.decode(String.self, forKey: .operationKey); commandHash = try c.decode(String.self, forKey: .commandHash)
        createdAt = try c.decode(String.self, forKey: .createdAt); command = try c.decode(WorkshopPaidProfessionalCommand.self, forKey: .command)
        guard WorkshopPurchasedWire.hash(operationKey), WorkshopPurchasedWire.hash(commandHash), commandHash == command.commandHash,
              WorkshopPurchasedWire.timestamp(createdAt) else { throw WorkshopPaidProfessionalIssue.malformed }
    }
}
public struct WorkshopPaidProfessionalOperationHistory: Decodable {
    public let licenseId: String
    public let items: [WorkshopPaidProfessionalOperationReference]
    public let scannedCount: Int
    public let hasMore: Bool
    public let nextBeforeOperationKey: String?
    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, scope, licenseId, items, scannedCount, hasMore, nextBeforeOperationKey }
    public init(from decoder: Decoder) throws {
        try WorkshopPaidInstallWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-paid-professional-operation-history-v1",
              try c.decode(String.self, forKey: .scope) == "OWNER_OPERATION_INTENT_REFERENCES_ONLY" else { throw WorkshopPaidProfessionalIssue.malformed }
        licenseId = try c.decode(String.self, forKey: .licenseId); items = try WorkshopPaidInstallWire.items(c.superDecoder(forKey: .items))
        scannedCount = try c.decode(Int.self, forKey: .scannedCount); hasMore = try c.decode(Bool.self, forKey: .hasMore)
        nextBeforeOperationKey = try c.decodeIfPresent(String.self, forKey: .nextBeforeOperationKey)
        guard WorkshopPurchasedWire.license(licenseId), (0...50).contains(scannedCount), items.count <= scannedCount,
              Set(items.map(\.id)).count == items.count, items.allSatisfy({ $0.command.licenseId == licenseId }),
              zip(items, items.dropFirst()).allSatisfy({ $0.0.operationKey > $0.1.operationKey }),
              hasMore == (nextBeforeOperationKey != nil) else { throw WorkshopPaidProfessionalIssue.malformed }
        if let nextBeforeOperationKey {
            guard scannedCount == 50, WorkshopPurchasedWire.hash(nextBeforeOperationKey), items.allSatisfy({ $0.operationKey >= nextBeforeOperationKey }) else { throw WorkshopPaidProfessionalIssue.malformed }
        }
    }
}
