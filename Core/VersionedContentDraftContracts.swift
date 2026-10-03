import Foundation
import CryptoKit

public enum ContentDraftBusinessType: String, Codable { case activity = "ACTIVITY", topic = "TOPIC" }
public enum ContentDraftOwnerScope: String, Codable { case personal = "", merchant = "MERCHANT", club = "CLUB" }
public enum ContentDraftIssue: String, Error { case disabled, staleSession, invalid, malformed, unauthorized, forbidden, notFound, conflict, rejected, unavailable, unknownOutcome, storageUnavailable, busy }

/// A content_draft key is not a topic ID, publication bundle ID or merchant registration ID.
public struct ContentDraftIdentity: Codable, Equatable {
    public let ownerMemberID: Int64
    public let businessType: ContentDraftBusinessType
    public let clientDraftKey: String
    public let scope: ContentDraftOwnerScope
    public init(ownerMemberID: Int64, businessType: ContentDraftBusinessType, clientDraftKey: String,
                scope: ContentDraftOwnerScope = .personal) throws {
        self.ownerMemberID = ownerMemberID; self.businessType = businessType
        self.clientDraftKey = clientDraftKey; self.scope = scope; try validate()
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ownerMemberID == rhs.ownerMemberID && lhs.businessType == rhs.businessType &&
        lhs.scope == rhs.scope && lhs.clientDraftKey.utf8.elementsEqual(rhs.clientDraftKey.utf8)
    }
    func validate() throws {
        guard ownerMemberID > 0, Self.validKey(clientDraftKey) else { throw ContentDraftIssue.invalid }
    }
    static func validKey(_ key: String) -> Bool {
        // The server applies Java String.trim(): every leading/trailing UTF-16 code
        // unit <= U+0020 is removed, including NUL/ESC that Foundation does not trim.
        guard let first = key.utf16.first, let last = key.utf16.last,
              first > 0x20, last > 0x20 else { return false }
        return key == key.trimmingCharacters(in: .whitespacesAndNewlines) && key.utf16.count <= 64
    }
}

/// Public wire schema only. Optional server time is display metadata; unknown extensions remain ignored.
/// payloadHash authenticates no license or entitlement; it is an integrity/CAS readback field.
public struct ContentDraftRecord: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Status: String, Codable { case draft = "DRAFT", published = "PUBLISHED", deleted = "DELETED" }
    public let id: Int64
    public let ownerMemberId: Int64
    public let businessType: ContentDraftBusinessType
    public let clientDraftKey: String
    public let subjectId: Int64?
    public let payloadJson: String
    public let payloadHash: String
    public let status: Status
    public let version: Int64
    public let updatedByDevice: String
    public let publishedResourceId: Int64?
    // Display-only metadata is excluded from the existing mutation/journal integrity identity.
    public let updateTime: ContentDraftServerTime?
    // Restore-only metadata. Omission differs from a present but unsupported response.
    public let installedModules: InstalledDraftModules?
    public let installedModulesInvalid: Bool
    private enum CodingKeys: String, CodingKey {
        case installedModules
        case id, ownerMemberId, businessType, clientDraftKey, subjectId, payloadJson, payloadHash
        case status, version, updatedByDevice, publishedResourceId, updateTime
    }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(Int64.self, forKey: .id)
        ownerMemberId = try box.decode(Int64.self, forKey: .ownerMemberId)
        businessType = try box.decode(ContentDraftBusinessType.self, forKey: .businessType)
        clientDraftKey = try box.decode(String.self, forKey: .clientDraftKey)
        subjectId = try box.decodeIfPresent(Int64.self, forKey: .subjectId)
        payloadJson = try box.decode(String.self, forKey: .payloadJson)
        payloadHash = try box.decode(String.self, forKey: .payloadHash)
        status = try box.decode(Status.self, forKey: .status)
        version = try box.decode(Int64.self, forKey: .version)
        updatedByDevice = try box.decode(String.self, forKey: .updatedByDevice)
        publishedResourceId = try box.decodeIfPresent(Int64.self, forKey: .publishedResourceId)
        // Unsupported display metadata stays absent, preserving stable Codable journal round trips.
        // Identity/payload fields above remain strict; they never use this optional fallback.
        updateTime = try? box.decode(ContentDraftServerTime.self, forKey: .updateTime)
        installedModules = try? box.decode(InstalledDraftModules.self, forKey: .installedModules)
        installedModulesInvalid = box.contains(.installedModules) && installedModules == nil
    }
    public func encode(to encoder: Encoder) throws {
        // Preserve the pre-extension encoding exactly: receipts are transient restore metadata,
        // never journal material. Do not add them to Codable equality or mutation fingerprints.
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(ownerMemberId, forKey: .ownerMemberId)
        try box.encode(businessType, forKey: .businessType)
        try box.encode(clientDraftKey, forKey: .clientDraftKey)
        try box.encodeIfPresent(subjectId, forKey: .subjectId)
        try box.encode(payloadJson, forKey: .payloadJson)
        try box.encode(payloadHash, forKey: .payloadHash)
        try box.encode(status, forKey: .status)
        try box.encode(version, forKey: .version)
        try box.encode(updatedByDevice, forKey: .updatedByDevice)
        try box.encodeIfPresent(publishedResourceId, forKey: .publishedResourceId)
        try box.encodeIfPresent(updateTime, forKey: .updateTime)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.ownerMemberId == rhs.ownerMemberId && lhs.businessType == rhs.businessType &&
        lhs.clientDraftKey.utf8.elementsEqual(rhs.clientDraftKey.utf8) && lhs.subjectId == rhs.subjectId &&
        lhs.payloadJson.utf8.elementsEqual(rhs.payloadJson.utf8) && lhs.payloadHash.utf8.elementsEqual(rhs.payloadHash.utf8) &&
        lhs.status == rhs.status && lhs.version == rhs.version &&
        lhs.updatedByDevice.utf8.elementsEqual(rhs.updatedByDevice.utf8) && lhs.publishedResourceId == rhs.publishedResourceId
    }
    public func validate(identity: ContentDraftIdentity) throws {
        try identity.validate()
        guard id > 0, ownerMemberId == identity.ownerMemberID, businessType == identity.businessType,
              clientDraftKey.utf8.elementsEqual(identity.clientDraftKey.utf8), version > 0,
              ContentDraftIdentity.validKey(updatedByDevice), payloadJson.utf8.count <= 524_288,
              payloadHash == Self.hash(payloadJson) else { throw ContentDraftIssue.malformed }
        _ = try Self.json(payloadJson)
        if status == .published {
            guard let publishedResourceId, publishedResourceId > 0 else { throw ContentDraftIssue.malformed }
        } else if publishedResourceId != nil { throw ContentDraftIssue.malformed }
    }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func json(_ text: String) throws -> ContentDraftJSON {
        guard text.utf8.count <= 524_288 else { throw ContentDraftIssue.malformed }
        do { return try ContentDraftJSON.parse(text) }
        catch { throw ContentDraftIssue.malformed }
    }
    public var description: String { "ContentDraft[redacted]" }
    public var debugDescription: String { description }
}

/// Typed entry seam: a caller must provide its reviewed, lossless Codable payload schema.
/// This intentionally supplies no guessed ProjectEdit conversion or raw-JSON editor.
public struct ContentDraftDocument<Payload: Codable & Equatable>: Equatable {
    public let record: ContentDraftRecord
    public let payload: Payload
    public init(record: ContentDraftRecord, identity: ContentDraftIdentity) throws {
        try record.validate(identity: identity)
        do {
            let value = try JSONDecoder().decode(Payload.self, from: Data(record.payloadJson.utf8))
            // Refuse a decoder that silently discards unknown fields. A later save must not lose them.
            guard try ContentDraftRecord.json(Self.encode(value)) == ContentDraftRecord.json(record.payloadJson) else {
                throw ContentDraftIssue.malformed
            }
            self.record = record; payload = value
        } catch { throw ContentDraftIssue.malformed }
    }
    static func encode(_ value: Payload) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= 524_288, let text = String(data: data, encoding: .utf8) else { throw ContentDraftIssue.invalid }
        return text
    }
}

/// Immutable exact command. The local UUID is a journal identity and is NEVER sent to the server.
public struct ContentDraftMutation: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Kind: String, Codable { case save, delete }
    public struct Command: Codable, Equatable {
        public let id: Int64?
        public let businessType: ContentDraftBusinessType?
        public let clientDraftKey: String?
        public let subjectId: Int64?
        public let payloadJson: String?
        public let expectedVersion: Int64
        public let deviceId: String?
        public let scope: ContentDraftOwnerScope
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.businessType == rhs.businessType && lhs.subjectId == rhs.subjectId &&
            lhs.expectedVersion == rhs.expectedVersion && lhs.scope == rhs.scope &&
            lhs.clientDraftKey.map { Data($0.utf8) } == rhs.clientDraftKey.map { Data($0.utf8) } &&
            lhs.payloadJson.map { Data($0.utf8) } == rhs.payloadJson.map { Data($0.utf8) } &&
            lhs.deviceId.map { Data($0.utf8) } == rhs.deviceId.map { Data($0.utf8) }
        }
    }
    public let operationID: UUID
    public let identity: ContentDraftIdentity
    public let kind: Kind
    public let command: Command
    public let baseline: ContentDraftRecord?
    public static func save<Payload: Codable & Equatable>(payload: Payload, identity: ContentDraftIdentity,
        subjectID: Int64?, deviceID: String, baseline: ContentDraftRecord?) throws -> Self {
        let value = Self(operationID: UUID(), identity: identity, kind: .save,
            command: .init(id: baseline?.id, businessType: identity.businessType, clientDraftKey: identity.clientDraftKey,
                subjectId: subjectID, payloadJson: try ContentDraftDocument<Payload>.encode(payload),
                expectedVersion: baseline?.version ?? 0, deviceId: deviceID, scope: identity.scope), baseline: baseline)
        try value.validate(); return value
    }
    public static func delete(identity: ContentDraftIdentity, baseline: ContentDraftRecord) throws -> Self {
        let value = Self(operationID: UUID(), identity: identity, kind: .delete,
            command: .init(id: baseline.id, businessType: nil, clientDraftKey: nil, subjectId: nil,
                payloadJson: nil, expectedVersion: baseline.version, deviceId: nil, scope: identity.scope), baseline: baseline)
        try value.validate(); return value
    }
    public func validate() throws {
        try identity.validate()
        guard command.scope == identity.scope, command.expectedVersion >= 0,
              command.expectedVersion < Int64.max else { throw ContentDraftIssue.invalid }
        if let baseline {
            try baseline.validate(identity: identity)
            guard baseline.status == .draft, baseline.id == command.id,
                  baseline.version == command.expectedVersion else { throw ContentDraftIssue.invalid }
        } else if command.id != nil || command.expectedVersion != 0 { throw ContentDraftIssue.invalid }
        switch kind {
        case .save:
            guard command.businessType == identity.businessType, let key = command.clientDraftKey,
                  key.utf8.elementsEqual(identity.clientDraftKey.utf8),
                  let device = command.deviceId, ContentDraftIdentity.validKey(device), let payload = command.payloadJson else { throw ContentDraftIssue.invalid }
            _ = try ContentDraftRecord.json(payload)
        case .delete:
            guard baseline != nil, command.businessType == nil, command.clientDraftKey == nil,
                  command.subjectId == nil, command.payloadJson == nil, command.deviceId == nil else { throw ContentDraftIssue.invalid }
        }
    }
    public func validate(receipt: ContentDraftRecord) throws {
        try validate(); try receipt.validate(identity: identity)
        if let id = command.id, receipt.id != id { throw ContentDraftIssue.malformed }
        switch kind {
        case .save:
            guard receipt.status == .draft, receipt.subjectId == command.subjectId,
                  let payload = command.payloadJson,
                  try ContentDraftRecord.json(receipt.payloadJson) == ContentDraftRecord.json(payload) else { throw ContentDraftIssue.malformed }
            // An identical create key may return a later still-active version. Update retries require exactly N+1.
            guard command.expectedVersion == 0 || receipt.version == command.expectedVersion + 1 else { throw ContentDraftIssue.malformed }
        case .delete:
            guard let baseline, receipt.status == .deleted, receipt.version == command.expectedVersion + 1,
                  receipt.payloadJson == baseline.payloadJson, receipt.payloadHash == baseline.payloadHash,
                  receipt.subjectId == baseline.subjectId else { throw ContentDraftIssue.malformed }
        }
    }
    public var description: String { "ContentDraftMutation[redacted]" }
    public var debugDescription: String { description }
}

/// Authority strings are opaque wire/storage identifiers. Swift's canonical Unicode
/// String equality must not make distinct realm or role bytes share a lifetime.
enum ContentDraftContextFence {
    static func matches(_ lhs: RuntimeDependencyContext?, _ rhs: RuntimeDependencyContext) -> Bool {
        guard let lhs else { return false }
        return lhs.market == rhs.market &&
            lhs.baseURL.absoluteString.utf8.elementsEqual(rhs.baseURL.absoluteString.utf8) &&
            lhs.role.utf8.elementsEqual(rhs.role.utf8) &&
            lhs.session.accountID == rhs.session.accountID && lhs.session.epoch == rhs.session.epoch &&
            lhs.session.namespace.utf8.elementsEqual(rhs.session.namespace.utf8) &&
            lhs.session.token.utf8.elementsEqual(rhs.session.token.utf8)
    }
}

public struct ContentDraftJournalScope: Equatable {
    public let market: RegionalMarket
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    // Request scope is deliberately absent: PERSONAL/CLUB/MERCHANT can resolve
    // to the same owner/business/key. They must share one uncertainty lock.
    public let ownerMemberID: Int64
    public let businessType: ContentDraftBusinessType
    public let clientDraftKey: String
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.market == rhs.market &&
        lhs.baseURL.absoluteString.utf8.elementsEqual(rhs.baseURL.absoluteString.utf8) &&
        lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) &&
        lhs.accountID == rhs.accountID && lhs.ownerMemberID == rhs.ownerMemberID &&
        lhs.businessType == rhs.businessType && lhs.clientDraftKey.utf8.elementsEqual(rhs.clientDraftKey.utf8)
    }
    public init(context: RuntimeDependencyContext, identity: ContentDraftIdentity) {
        market = context.market; baseURL = context.baseURL; namespace = context.session.namespace
        accountID = context.session.accountID; ownerMemberID = identity.ownerMemberID
        businessType = identity.businessType; clientDraftKey = identity.clientDraftKey
    }
}
public struct ContentDraftPending: Codable, Equatable {
    public let mutation: ContentDraftMutation
    public let dispatched: Bool
    public init(mutation: ContentDraftMutation, dispatched: Bool = false) { self.mutation = mutation; self.dispatched = dispatched }
}
/// Caller-held generation identity. A coordinator must retain its own snapshot through HTTP;
/// another reader or coordinator may not silently substitute a newer generation for it.
public struct ContentDraftJournalSnapshot: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let value: ContentDraftPending
    public let generation: Data
    public init(value: ContentDraftPending, generation: Data) { self.value = value; self.generation = generation }
    public var description: String { "ContentDraftJournalSnapshot[redacted]" }
    public var debugDescription: String { description }
}
/// Mandatory only for writes. Confidential, durable, atomic compare-and-swap storage.
/// Scope includes realm/account/resolved owner/business/key; excludes request scope, token and epoch.
/// read errors throw. insert accepts empty/identical only; replace/clear compare the FULL value AND
/// caller-held generation. Retain uncertainty across crashes/logout. Never reacquire a clear ticket
/// from a new read after HTTP; a different generation belongs to a different attempt.
@MainActor public protocol ContentDraftSecureJournal: AnyObject {
    var scope: ContentDraftJournalScope { get }
    func read() async throws -> ContentDraftJournalSnapshot?
    func insert(_ value: ContentDraftPending) async throws -> ContentDraftJournalSnapshot
    func replace(_ old: ContentDraftJournalSnapshot, with new: ContentDraftPending) async throws -> ContentDraftJournalSnapshot
    func clear(matching snapshot: ContentDraftJournalSnapshot) async throws
}
@MainActor public protocol ContentDraftReading {
    func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord
    func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord]
}
@MainActor public protocol ContentDraftServing: ContentDraftReading {
    func mutate(_ attempt: ContentDraftPreparedDispatch) async throws -> ContentDraftRecord
}
