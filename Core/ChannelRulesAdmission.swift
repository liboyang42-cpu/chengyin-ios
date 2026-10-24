import Foundation
import CoreFoundation

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

    /// Original `ChannelAdmissionService.cancel`. Current rules are not rechecked. One call, no local store.
    public typealias OriginalAdmissionCancel = (
        _ actorID: Int64, _ applicationID: Int64, _ requestID: String
    ) throws -> [String: Any]

    public func cancelOriginal(applicationID: Int64, requestID: String,
                               channel: OriginalAdmissionCancel? = nil) throws -> [String: Any] {
        guard applicationID > 0, Self.validRequestID(requestID) else { throw ChannelAuthorizationError.invalidCatalog }
        guard let channel else { throw ChannelAuthorizationError.waitingSource }
        let sent = try channel(Int64(identity.accountID), applicationID, requestID)
        if let echoed = sent["request_id"] as? String, echoed != requestID {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard Self.positiveID(sent["id"]) == applicationID, Self.exactInt(sent["status"]) == 3 else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        return sent
    }

    /// Original `ChannelAdmissionService.leave`. Current rules are not rechecked. One call, no local store.
    public typealias OriginalAdmissionLeave = (
        _ actorID: Int64, _ kind: Int, _ spaceID: Int64, _ requestID: String
    ) throws -> [String: Any]

    public func leaveOriginal(kind: Int, spaceID: Int64, requestID: String,
                              channel: OriginalAdmissionLeave? = nil) throws -> [String: Any] {
        guard (kind == 1 || kind == 3), spaceID > 0, Self.validRequestID(requestID) else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard let channel else { throw ChannelAuthorizationError.waitingSource }
        let sent = try channel(Int64(identity.accountID), kind, spaceID, requestID)
        if let echoed = sent["request_id"] as? String, echoed != requestID {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard (sent["left"] as? Bool) == true else { throw ChannelAuthorizationError.invalidCatalog }
        if let echoedKind = Self.exactInt(sent["guild_kind"]), echoedKind != kind {
            throw ChannelAuthorizationError.invalidCatalog
        }
        if let echoedSpace = Self.positiveID(sent["guild_id"]), echoedSpace != spaceID {
            throw ChannelAuthorizationError.invalidCatalog
        }
        return sent
    }

    /// Original `ChannelAdmissionService.review`. Approval carries no reject reason.
    /// A reject uses reason 1, 2, 3, 4, 5, or 9. Reason 9 needs a note. One call, no local store.
    public typealias OriginalAdmissionReview = (
        _ actorID: Int64, _ applicationID: Int64, _ approve: Bool, _ reasonCode: Int?, _ note: String?, _ requestID: String
    ) throws -> [String: Any]

    public func reviewOriginal(applicationID: Int64, approve: Bool, reasonCode: Int?, note: String?, requestID: String,
                               channel: OriginalAdmissionReview? = nil) throws -> [String: Any] {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (trimmed?.isEmpty == false) ? trimmed : nil
        guard applicationID > 0, Self.validRequestID(requestID), (text?.count ?? 0) <= 200 else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        if approve {
            guard reasonCode == nil else { throw ChannelAuthorizationError.invalidCatalog }
        } else {
            guard let reasonCode, [1, 2, 3, 4, 5, 9].contains(reasonCode) else {
                throw ChannelAuthorizationError.invalidCatalog
            }
            if reasonCode == 9, text == nil { throw ChannelAuthorizationError.invalidCatalog }
        }
        guard let channel else { throw ChannelAuthorizationError.waitingSource }
        let sent = try channel(Int64(identity.accountID), applicationID, approve, reasonCode, text, requestID)
        if let echoed = sent["request_id"] as? String, echoed != requestID {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard Self.positiveID(sent["id"]) == applicationID, Self.exactInt(sent["status"]) == (approve ? 1 : 2) else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        if !approve, sent["join_state"] as? String != "REJECTED" {
            throw ChannelAuthorizationError.invalidCatalog
        }
        return sent
    }

    /// Original `ChannelAdmissionService.pause`. A reason is required and stays within 120 characters.
    /// Unpausing does not keep an until time. One call, no local store.
    public typealias OriginalAdmissionPause = (
        _ actorID: Int64, _ kind: Int, _ spaceID: Int64, _ paused: Bool, _ until: String?, _ reason: String, _ requestID: String
    ) throws -> [String: Any]

    public func pauseOriginal(kind: Int, spaceID: Int64, paused: Bool, until: String?, reason: String, requestID: String,
                              channel: OriginalAdmissionPause? = nil) throws -> [String: Any] {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUntil = until?.trimmingCharacters(in: .whitespacesAndNewlines)
        let untilValue = (paused && trimmedUntil?.isEmpty == false) ? trimmedUntil : nil
        guard (kind == 1 || kind == 3), spaceID > 0, Self.validRequestID(requestID),
              !trimmedReason.isEmpty, trimmedReason.count <= 120 else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard let channel else { throw ChannelAuthorizationError.waitingSource }
        let sent = try channel(Int64(identity.accountID), kind, spaceID, paused, untilValue, trimmedReason, requestID)
        if let echoed = sent["request_id"] as? String, echoed != requestID {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard (sent["join_paused"] as? Bool) == paused else { throw ChannelAuthorizationError.invalidCatalog }
        if let echoedKind = Self.exactInt(sent["guild_kind"]), echoedKind != kind {
            throw ChannelAuthorizationError.invalidCatalog
        }
        if let echoedSpace = Self.positiveID(sent["guild_id"]), echoedSpace != spaceID {
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

    private static func positiveID(_ value: Any?) -> Int64? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let int = number.int64Value
            if int > 0, number.doubleValue == Double(int) { return int }
        }
        if let text = value as? String, let int = Int64(text), int > 0, String(int) == text { return int }
        return nil
    }

    private static func exactInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let int = number.intValue
        guard number.doubleValue == Double(int) else { return nil }
        return int
    }

    private static func validRequestID(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
                || scalar.value == 58 || scalar.value == 46 || scalar.value == 95 || scalar.value == 45
        }
    }
}
