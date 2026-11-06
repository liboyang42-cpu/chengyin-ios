import Foundation

// Candidate wire v1. Owner is always the authenticated subject, never a request body field.
public enum PersonalLocationShareMode: String, Codable, Sendable { case exact = "EXACT", coarse = "COARSE" }
public enum PersonalLocationShareStatus: String, Codable, Sendable {
    case notFound = "NOT_FOUND", active = "ACTIVE", stopped = "STOPPED", revoked = "REVOKED", expired = "EXPIRED"
    public var isTerminal: Bool { self == .stopped || self == .revoked || self == .expired }
}
public enum PersonalLocationShareDisclosure: String, Codable, CaseIterable, Sendable {
    case audience, precision, duration, foregroundOnly, stopAnytime, alreadySeenCannotBeRecalled
}
public struct PersonalLocationShareContext: Codable, Equatable, Sendable {
    public let ownerId: Int64
    public let recipientId: Int64
    public let eligible: Bool
    public let unavailableReason: String?
    public let policy: PersonalLocationSharePolicy?
}
public struct PersonalLocationShareCreate: Codable, Equatable, Sendable {
    public let requestKey: String
    public let recipientId: Int64
    public let policyId: String
    public let policyVersion: Int64
    public let policyDigest: String
    public let modeChoiceId: String
    public let durationChoiceId: String
    public let foregroundOnly: Bool
    public let acknowledgedDisclosures: [PersonalLocationShareDisclosure]
}
public struct PersonalLocationShareGrant: Codable, Equatable, Identifiable, Sendable {
    public var id: String { grantId }
    public let grantId: String
    public let requestKey: String
    public let ownerId: Int64
    public let recipientId: Int64
    public let policyId: String
    public let policyVersion: Int64
    public let policyDigest: String
    public let modeChoiceId: String
    public let mode: PersonalLocationShareMode
    public let durationChoiceId: String
    public let createdAtMs: Int64
    public let expiresAtMs: Int64
    public let ownerLeaseUntilMs: Int64
    public let version: Int64
    public let watermark: Int64
    public let status: PersonalLocationShareStatus
    public let reason: String?
    public var structurallyValid: Bool {
        UUID(uuidString: grantId) != nil && UUID(uuidString: requestKey) != nil && ownerId > 0 && recipientId > 0 &&
        ownerId != recipientId && !policyId.isEmpty && policyVersion > 0 && !policyDigest.isEmpty &&
        !modeChoiceId.isEmpty && !durationChoiceId.isEmpty && createdAtMs > 0 && expiresAtMs > createdAtMs &&
        ownerLeaseUntilMs > 0 && version > 0 && watermark > 0 && status != .notFound
    }
    public func matches(_ request: PersonalLocationShareCreate, ownerId: Int64) -> Bool {
        structurallyValid && self.ownerId == ownerId && recipientId == request.recipientId && requestKey == request.requestKey &&
        policyId == request.policyId && policyVersion == request.policyVersion && policyDigest == request.policyDigest &&
        modeChoiceId == request.modeChoiceId && durationChoiceId == request.durationChoiceId
    }
}
public struct PersonalLocationShareReceipt: Codable, Equatable, Sendable {
    public let requestKey: String
    public let known: Bool
    public let state: PersonalLocationShareStatus
    public let requestHash: String?
    public let grant: PersonalLocationShareGrant?
    public let serverNowMs: Int64
    public let watermark: Int64
}
public struct PersonalLocationShareOwned: Codable, Equatable, Sendable {
    public let ownerId: Int64
    public let serverNowMs: Int64
    public let grants: [PersonalLocationShareGrant]
}
public struct PersonalLocationSharePublish: Codable, Equatable, Sendable {
    public let sequence: Int64
    public let observedAtMs: Int64
    public let datum: String
    public let latitude: Double
    public let longitude: Double
    public let foreground: Bool
    public var valid: Bool { sequence > 0 && observedAtMs > 0 && datum == "WGS84" && foreground && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}
public struct PersonalLocationSharePublished: Codable, Equatable, Sendable {
    public let grantId: String
    public let sequence: Int64
    public let version: Int64
    public let watermark: Int64
    public let observedAtMs: Int64
    public let ownerLeaseUntilMs: Int64
}
public struct PersonalLocationShareObservation: Codable, Equatable, Sendable {
    public let grantId: String
    public let ownerId: Int64
    public let recipientId: Int64
    public let sequence: Int64
    public let observedAtMs: Int64
    public let datum: String
    public let mode: PersonalLocationShareMode
    public let latitude: Double
    public let longitude: Double
    public let stale: Bool
    public let version: Int64
    public let watermark: Int64
    public func matches(_ grant: PersonalLocationShareGrant, serverNowMs: Int64) -> Bool {
        grantId == grant.grantId && ownerId == grant.ownerId && recipientId == grant.recipientId && mode == grant.mode &&
        sequence > 0 && observedAtMs >= grant.createdAtMs && observedAtMs <= serverNowMs && datum == "WGS84" &&
        version == grant.version && watermark == grant.watermark && latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}
public struct PersonalLocationShareSnapshot: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let grant: PersonalLocationShareGrant
        public let observation: PersonalLocationShareObservation?
    }
    public let recipientId: Int64
    public let serverNowMs: Int64
    public let cursor: Int64
    public let displayLeaseUntilMs: Int64
    public let refreshAfterMs: Int64
    public let staleAfterMs: Int64
    public let policyId: String
    public let policyVersion: Int64
    public let policyDigest: String
    public let entries: [Entry]
}
public struct PersonalLocationShareEventBatch: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case invalidated = "INVALIDATED", updated = "UPDATED" }
    public struct Event: Codable, Equatable, Sendable {
        public let grantId: String
        public let version: Int64
        public let watermark: Int64
        public let kind: Kind
    }
    public let recipientId: Int64
    public let serverNowMs: Int64
    public let cursor: Int64
    public let resetRequired: Bool
    public let refreshAfterMs: Int64
    public let events: [Event]
}
public struct PersonalLocationShareScope: Hashable, Sendable {
    public let namespace: String
    public let accountId: Int64
    public let epoch: UInt64
    public init(namespace: String, accountId: Int64, epoch: UInt64) throws {
        guard !namespace.isEmpty, accountId > 0 else { throw PersonalLocationShareFailure.invalidContract }
        self.namespace = namespace; self.accountId = accountId; self.epoch = epoch
    }
}
public enum PersonalLocationShareFailure: Error, Equatable {
    case unavailable, unapprovedRead, unapprovedWrite, invalidContract, staleSession, ineligible
    case acceptanceUnavailable, providerUnavailable, syntheticTransportForbidden, incompleteConsent
    case authorizationRejected(status: Int, errorCode: String?)
    case retiredResponse
    case expiredConfirmation
    case journalUnavailable, unknownOutcome, existingLocationPermissionRequired, reducedAccuracyUnavailable, capturePurposeUnavailable, server(String)
}
