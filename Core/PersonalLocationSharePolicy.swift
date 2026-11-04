import Foundation

/// No runtime business defaults. The server supplies an approved, versioned choice set.
public struct PersonalLocationSharePolicy: Codable, Equatable, Sendable {
    public struct ModeChoice: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let mode: PersonalLocationShareMode
        public let datum: String
        public let latitudeStep: Double?
        public let longitudeStep: Double?
    }
    public struct DurationChoice: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let seconds: Int64
    }
    public let policyId: String
    public let version: Int64
    public let digest: String
    public let approvalRef: String
    public let foregroundOnly: Bool
    public let requiresRecipientAcceptance: Bool
    public let modeChoices: [ModeChoice]
    public let durationChoices: [DurationChoice]
    public let refreshAfterMs: Int64
    public let staleAfterMs: Int64
    public let displayLeaseMs: Int64
    public let ownerLeaseMs: Int64
    public func validate() throws {
        guard !policyId.isEmpty, version > 0, digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, !approvalRef.isEmpty, foregroundOnly,
              !modeChoices.isEmpty, !durationChoices.isEmpty,
              refreshAfterMs > 0, UInt64(refreshAfterMs) <= UInt64.max / 1_000_000,
              staleAfterMs >= refreshAfterMs, displayLeaseMs >= refreshAfterMs, ownerLeaseMs >= refreshAfterMs,
              Set(modeChoices.map(\.id)).count == modeChoices.count,
              Set(durationChoices.map(\.id)).count == durationChoices.count else { throw PersonalLocationShareFailure.invalidContract }
        guard !requiresRecipientAcceptance else { throw PersonalLocationShareFailure.acceptanceUnavailable }
        for mode in modeChoices {
            guard !mode.id.isEmpty, mode.datum == "WGS84" else { throw PersonalLocationShareFailure.invalidContract }
            if mode.mode == .coarse {
                guard let lat = mode.latitudeStep, let lon = mode.longitudeStep,
                      lat.isFinite, lon.isFinite, lat > 0, lat <= 180, lon > 0, lon <= 360 else { throw PersonalLocationShareFailure.invalidContract }
            } else if mode.latitudeStep != nil || mode.longitudeStep != nil { throw PersonalLocationShareFailure.invalidContract }
        }
        guard durationChoices.allSatisfy({ !$0.id.isEmpty && $0.seconds > 0 && $0.seconds <= Int64.max / 1000 }) else { throw PersonalLocationShareFailure.invalidContract }
    }
}

/// Separate endpoint approval, pinned to an origin and a review record. Defaults remain nil at every host.
public struct PersonalLocationShareEndpointApproval: Equatable, Sendable {
    public let origin: URL
    public let approvalReference: String
    public let operations: Set<PersonalLocationShareOperation>
    public init(origin: URL, approvalReference: String, operations: Set<PersonalLocationShareOperation>) throws {
        guard origin.scheme == "https", origin.host != nil, origin.user == nil, origin.password == nil,
              origin.query == nil, origin.fragment == nil, !approvalReference.isEmpty else { throw PersonalLocationShareFailure.invalidContract }
        self.origin = origin; self.approvalReference = approvalReference; self.operations = operations
    }
    public func permits(_ operation: PersonalLocationShareOperation, baseURL: URL) -> Bool {
        origin.standardized == baseURL.standardized && operations.contains(operation)
    }
}
public enum PersonalLocationShareOperation: String, Hashable, Sendable {
    case context, requestStatus, owned, received, events, create, revoke, publish
    public var isRead: Bool { [.context, .requestStatus, .owned, .received, .events].contains(self) }
}

/// Independent, reviewed personal-sharing collection purpose. Other app uses never imply this consent.
/// Approval pins the exact OS disclosure in the installed bundle as well as the account/session scope.
public struct PersonalLocationShareCaptureApproval: Equatable, Sendable {
    public let scope: PersonalLocationShareScope
    public let approvalReference: String
    public let usageDescription: String
    public let purpose: String
    public init(scope: PersonalLocationShareScope, approvalReference: String, usageDescription: String) throws {
        guard !approvalReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !usageDescription.lowercased().contains("not shared with other people") else {
            throw PersonalLocationShareFailure.invalidContract
        }
        self.scope = scope; self.approvalReference = approvalReference; self.usageDescription = usageDescription
        purpose = "PERSONAL_LOCATION_SHARING_FOREGROUND"
    }
    public func permits(scope: PersonalLocationShareScope, installedUsageDescription: String?) -> Bool {
        self.scope == scope && installedUsageDescription == usageDescription && purpose == "PERSONAL_LOCATION_SHARING_FOREGROUND"
    }
}
