import Foundation

/// Rules-consent gate over existing P04 dual-version CAS. Join is admitted only
/// against the published rules version captured by the catalog snapshot.
public struct ChannelRulesAdmission: Equatable, Sendable {
    public let identity: ChannelAccount4Identity
    public let consentedVersion: Int
    public init(identity: ChannelAccount4Identity, consentedVersion: Int) throws {
        guard consentedVersion > 0 else { throw ChannelAuthorizationError.rulesCASConflict }
        self.identity = identity
        self.consentedVersion = consentedVersion
    }

    /// Pending rules cannot admit a member. A stale expectedVersion is a CAS
    /// conflict against the existing P04 writer, not a missing contract.
    public func admit(identity: ChannelAccount4Identity, catalog: ChannelCatalogEntry) throws -> Int {
        guard identity == self.identity else { throw ChannelAuthorizationError.account4Mismatch }
        let cas = catalog.rules
        guard cas.isCurrent else { throw ChannelAuthorizationError.rulesCASConflict }
        if let pending = cas.pendingVersion, consentedVersion == pending {
            throw ChannelAuthorizationError.rulesCASConflict
        }
        guard consentedVersion == cas.publishedVersion else { throw ChannelAuthorizationError.rulesConsentRequired }
        return cas.publishedVersion
    }

    /// Original `ChannelAdmissionService.submit`. Rules are checked before the port is called.
    /// Nil keeps the application closed. One call, no local receipt store.
    public typealias OriginalAdmissionSubmit = (
        _ actorID: Int64, _ kind: Int, _ spaceID: Int64, _ inviteID: Int64?, _ message: String?, _ requestID: String
    ) throws -> [String: Any]

    public func submitOriginal(catalog: ChannelCatalogEntry, kind: Int, spaceID: Int64, inviteID: Int64?,
                               message: String?, requestID: String, channel: OriginalAdmissionSubmit? = nil) throws -> [String: Any] {
        _ = try admit(identity: identity, catalog: catalog)
        let note = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = (note?.isEmpty == false) ? note : nil
        guard (kind == 1 || kind == 3), spaceID > 0, Self.validRequestID(requestID),
              inviteID == nil || inviteID! > 0, (trimmed?.count ?? 0) <= 60 else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard let channel else { throw ChannelAuthorizationError.waitingSource }
        let sent = try channel(Int64(identity.accountID), kind, spaceID, inviteID, trimmed, requestID)
        if let echoed = sent["request_id"] as? String, echoed != requestID {
            throw ChannelAuthorizationError.invalidCatalog
        }
        return sent
    }

    /// Original `receipt`. It does not submit again. A missing row stays UNKNOWN on the same request id.
    public func recoverOriginal(requestID: String, receipt: (Int64, String) throws -> [String: Any]) throws -> [String: Any] {
        guard Self.validRequestID(requestID) else { throw ChannelAuthorizationError.invalidCatalog }
        let row = try receipt(Int64(identity.accountID), requestID)
        guard row["request_id"] as? String == requestID else { throw ChannelAuthorizationError.invalidCatalog }
        if row["state"] as? String == "UNKNOWN" {
            guard row["operation"] == nil, row["result"] == nil else { throw ChannelAuthorizationError.invalidCatalog }
        }
        return row
    }

    private static func validRequestID(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
                || scalar.value == 58 || scalar.value == 46 || scalar.value == 95 || scalar.value == 45
        }
    }
}
