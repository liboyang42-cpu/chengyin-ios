import Foundation
import CoreFoundation

/// P38 ACCOUNT4 is the existing member-authorization identity realm. Channel grants
/// bind here and never to a friend-graph edge. WAITING_SOURCE: D5 native 43/45/46/47
/// adapters; this exclusive projection consumes the named backend contract as a fact.
public struct ChannelAccount4Identity: Hashable, Sendable {
    public static let realm = "ACCOUNT4"
    public let accountID: Int
    public let epoch: UInt64
    public init(accountID: Int, epoch: UInt64) throws {
        guard accountID > 0 else { throw ChannelAuthorizationError.account4Mismatch }
        self.accountID = accountID
        self.epoch = epoch
    }
    public var messagingIdentity: MessagingReadIdentity {
        MessagingReadIdentity(accountID: accountID, epoch: epoch)
    }
}

/// P04 dual-version CAS on channel rules: published is joinable, pending is not.
/// expectedVersion is the catalog snapshot the client must present; a mismatch is
/// a CAS conflict against the existing P04 writer.
public struct ChannelRulesCAS: Equatable, Sendable {
    public let publishedVersion: Int
    public let pendingVersion: Int?
    public let expectedVersion: Int
    public init(publishedVersion: Int, pendingVersion: Int?, expectedVersion: Int) throws {
        guard publishedVersion > 0, expectedVersion > 0,
              pendingVersion.map({ $0 > publishedVersion }) ?? true else {
            throw ChannelAuthorizationError.rulesCASConflict
        }
        self.publishedVersion = publishedVersion
        self.pendingVersion = pendingVersion
        self.expectedVersion = expectedVersion
    }
    public var isCurrent: Bool { expectedVersion == publishedVersion }
}

public enum ChannelRole: String, Equatable, Sendable {
    case none, applicant, member, moderator, owner
    public var capabilities: Set<ChannelCapability> {
        switch self {
        case .none: return []
        case .applicant: return [.apply]
        case .member: return [.read, .write, .leave]
        case .moderator: return [.read, .write, .leave, .invite, .ban, .govern]
        case .owner: return [.read, .write, .leave, .invite, .ban, .govern, .appeal]
        }
    }
}

public enum ChannelCapability: String, Equatable, Sendable {
    case read, write, govern, invite, apply, leave, ban, appeal
}

public enum ChannelGovernancePhase: String, Equatable, Sendable {
    case cataloged
    case rulesConsentRequired
    case inviteOrApply
    case memberRoleAssigned
    case authorizedReadWrite
    case governing
    case left
    case banned
    case appealing
    case isolated
}

public enum ChannelAuthorizationError: Error, Equatable, Sendable {
    case rulesConsentRequired
    case rulesCASConflict
    case notMember
    case revoked
    case isolatedLateRequest
    case friendPermissionRequired
    case channelPermissionRequired
    case progressPrivacyDenied
    case account4Mismatch
    case historicalVoteWriteDenied
    case invalidCatalog
    case roleRequired
    case waitingSource
    case waitingListMessages
}

public enum ChannelRevokeReason: String, Equatable, Sendable { case leave, ban, membershipRevoked }

/// Catalog surface reuses existing IM group conversations. Direct/system/merchant
/// rows cannot become a channel catalog entry.
public struct ChannelCatalogEntry: Equatable, Sendable {
    public let channelID: Int
    public let conversationID: Int
    public let kind: MessagingConversationKind
    public let rules: ChannelRulesCAS
    public init(channelID: Int, conversationID: Int, kind: MessagingConversationKind, rules: ChannelRulesCAS) throws {
        guard channelID > 0, conversationID > 0, kind == .group else { throw ChannelAuthorizationError.invalidCatalog }
        self.channelID = channelID
        self.conversationID = conversationID
        self.kind = kind
        self.rules = rules
    }
}

/// Exclusive create/catalog/rules-consent/invite-apply/member-role → rw + governance
/// → leave/ban/appeal projection. Does not own public IM send/receipt, journal, or
/// native 43/45/46/47 adapters.
public struct ChannelGovernanceProjection: Equatable, Sendable {
    public static let imActiveGroupMember = "im.isActiveGroupMember"
    public static let imListMessages = "im.listMessages"
    public let catalog: ChannelCatalogEntry
    public let identity: ChannelAccount4Identity
    public private(set) var phase: ChannelGovernancePhase
    public private(set) var generation: UInt64
    public private(set) var consentedRulesVersion: Int?
    public private(set) var role: ChannelRole
    public private(set) var revokeReason: ChannelRevokeReason?
    public var grant: ChannelAuthorizationGrant? {
        guard role != .none, phase == .authorizedReadWrite || phase == .governing else { return nil }
        return ChannelAuthorizationGrant(identity: identity, channelID: catalog.channelID,
                                         conversationID: catalog.conversationID, role: role,
                                         consentedRulesVersion: consentedRulesVersion,
                                         generation: generation)
    }

    public init(catalog: ChannelCatalogEntry, identity: ChannelAccount4Identity) {
        self.catalog = catalog
        self.identity = identity
        phase = .cataloged
        generation = 1
        consentedRulesVersion = nil
        role = .none
        revokeReason = nil
    }

    public mutating func requireRulesConsent() throws {
        try ensureActive()
        guard phase == .cataloged || phase == .rulesConsentRequired else { throw ChannelAuthorizationError.invalidCatalog }
        phase = .rulesConsentRequired
        bump()
    }

    public mutating func consentToPublishedRules(_ admission: ChannelRulesAdmission) throws {
        try ensureActive()
        guard phase == .rulesConsentRequired || phase == .cataloged else { throw ChannelAuthorizationError.invalidCatalog }
        consentedRulesVersion = try admission.admit(identity: identity, catalog: catalog)
        phase = .inviteOrApply
        bump()
    }

    public mutating func submitInviteOrApply() throws {
        try ensureActive()
        guard phase == .inviteOrApply, consentedRulesVersion != nil else { throw ChannelAuthorizationError.rulesConsentRequired }
        role = .applicant
        bump()
    }

    public mutating func assignMemberRole(_ role: ChannelRole) throws {
        try ensureActive()
        guard phase == .inviteOrApply, self.role == .applicant else { throw ChannelAuthorizationError.roleRequired }
        guard role == .member || role == .moderator || role == .owner else { throw ChannelAuthorizationError.roleRequired }
        self.role = role
        phase = .memberRoleAssigned
        bump()
    }

    public mutating func authorizeReadWrite() throws -> ChannelAuthorizationGrant {
        try ensureActive()
        guard role.capabilities.contains(.read), role.capabilities.contains(.write) else {
            throw ChannelAuthorizationError.roleRequired
        }
        guard phase == .memberRoleAssigned || phase == .authorizedReadWrite || phase == .governing else {
            throw ChannelAuthorizationError.notMember
        }
        try ChannelMemberAuthorizationProjection.authorize(identity: identity, catalog: catalog,
                                                           role: role, consentedRulesVersion: consentedRulesVersion,
                                                           capability: .write)
        phase = .authorizedReadWrite
        bump()
        return grant!
    }

    public mutating func authorizeFromMembership(memberID: Int64,
                                                 isActiveGroupMember: ((Int64, Int64) -> Bool)?) throws -> ChannelAuthorizationGrant {
        guard let isActiveGroupMember else { throw ChannelAuthorizationError.waitingSource }
        guard isActiveGroupMember(memberID, Int64(catalog.conversationID)) else {
            throw ChannelAuthorizationError.notMember
        }
        return try authorizeReadWrite()
    }

    /// Read the existing message page under the current revoke fact, then the group-member gate.
    /// Revoked or non-member callers do not call listMessages and do not change phase.
    /// A pure read does not require WRITE. Does not send or mark read.
    public func readMessages(memberID: Int64, cursorID: Int64?, size: Int, afterID: Int64?,
                             isActiveGroupMember: ((Int64, Int64) -> Bool)?,
                             listMessages: ((Int64, Int64, Int64?, Int, Int64?) -> [String: String])?) throws -> [String: String]? {
        guard let isActiveGroupMember else { throw ChannelAuthorizationError.waitingSource }
        guard let listMessages else { throw ChannelAuthorizationError.waitingListMessages }
        guard size > 0 else { throw ChannelAuthorizationError.invalidCatalog }
        try ensureActive()
        guard isActiveGroupMember(memberID, Int64(catalog.conversationID)) else {
            throw ChannelAuthorizationError.notMember
        }
        let page = listMessages(memberID, Int64(catalog.conversationID), cursorID, size, afterID)
        if let echoed = page["conversationId"], echoed != String(catalog.conversationID) {
            return nil
        }
        return page
    }

    public mutating func govern() throws {
        _ = try authorizeReadWrite()
        try ChannelMemberAuthorizationProjection.authorize(identity: identity, catalog: catalog,
                                                           role: role, consentedRulesVersion: consentedRulesVersion,
                                                           capability: .govern)
        phase = .governing
        bump()
    }

    public mutating func leave() throws {
        try ensureActive()
        guard role.capabilities.contains(.leave) else { throw ChannelAuthorizationError.roleRequired }
        isolate(reason: .leave, phase: .left)
    }

    public mutating func ban() throws {
        try ensureActive()
        isolate(reason: .ban, phase: .banned)
    }

    public mutating func appeal() throws {
        guard phase == .banned || phase == .appealing else { throw ChannelAuthorizationError.revoked }
        phase = .appealing
        bump()
    }

    public func pageLease() throws -> ChannelPageLease {
        guard let grant else { throw ChannelAuthorizationError.notMember }
        return ChannelPageLease(channelID: catalog.channelID, conversationID: catalog.conversationID,
                                generation: generation, identity: identity, capabilities: role.capabilities,
                                consentedRulesVersion: grant.consentedRulesVersion)
    }

    public func admit(_ request: ChannelIsolatedRequest) throws -> ChannelIsolatedAdmission {
        ChannelRevokeIsolation(channelID: catalog.channelID, identity: identity,
                               revokedAtGeneration: revokeReason == nil ? nil : generation,
                               reason: revokeReason, phase: phase).admit(request)
    }

    private mutating func isolate(reason: ChannelRevokeReason, phase: ChannelGovernancePhase) {
        revokeReason = reason
        role = .none
        self.phase = .isolated
        bump()
        self.phase = phase
    }

    public func commitUnsignedOriginal(capability: String) throws -> Never {
        _ = capability
        throw ChannelAuthorizationError.waitingSource
    }

    private mutating func bump() { generation &+= 1 }

    private func ensureActive() throws {
        if revokeReason != nil || phase == .isolated || phase == .left || phase == .banned {
            throw ChannelAuthorizationError.revoked
        }
    }
}

/// Type 5 stays type 5. Channel kind is not the container type. Missing read state is unknown.
public struct MessageContainerProjection: Equatable, Sendable {
    public static let readStateUnknown = "UNKNOWN"
    public let id: String
    public let conversationType: String
    public let kind: String
    public let guildKind: String
    public let readState: String
    public let grantsSend: Bool

    public static func project(id: String, conversationType: Int, kind: Int, guildKind: Int,
                               readState: String?) -> MessageContainerProjection? {
        guard conversationType == 5, (1...2).contains(kind), (1...3).contains(guildKind),
              !id.isEmpty, id.allSatisfy({ $0.isNumber }) else { return nil }
        return MessageContainerProjection(id: id, conversationType: "5", kind: String(kind),
                                          guildKind: String(guildKind),
                                          readState: readState ?? readStateUnknown, grantsSend: false)
    }

    /// Directory detail only. A legacy group or club bizKey is not a type 5 container.
    public static func consumeAuthorizedDetail(_ detail: [String: Any]) -> MessageContainerProjection? {
        guard let nested = detail["message_container"] as? [String: Any],
              let id = nested["id"] as? String,
              let kind = Int(nested["kind"] as? String ?? ""),
              let guildKind = Int(nested["guild_kind"] as? String ?? ""),
              (nested["conversation_type"] as? String) == "5" else { return nil }
        return project(id: id, conversationType: 5, kind: kind, guildKind: guildKind, readState: nil)
    }
}

/// Original directory read facts. Counts stay nil unless `read_state_available` is 1.
/// `perm_version` is not an authority revision. Last-read cursors are not unread counts.
public struct DirectoryMyState: Equatable, Sendable {
    public let pinned: Int
    public let hidden: Int
    public let muted: Int
    public let permanentMuted: Bool
    public let effectiveLevel: Int
    public let mutedUntil: String?
    public let readStateAvailable: Int
    public let indexed: Bool
    public let readState: String?
    public let lastReadMessageID: String?
    public let lastReadVisibleAt: String?
    public let unreadCount: Int?
    public let unreadMentionCount: Int?
    public let grantsSend: Bool
    public let grantsReceiptWrite: Bool

    public static func read(_ myState: [String: Any]?) -> DirectoryMyState? {
        guard let myState else { return unavailable }
        guard let pinned = bit(myState["pinned"]), let hidden = bit(myState["hidden"]),
              let muted = bit(myState["muted"]), let level = level(myState["effective_level"]),
              let permanent = jsonBool(myState["permanent_muted"]) else { return nil }
        let category = (myState["read_state"] as? String) == "NOT_APPLICABLE"
        let readable = exactInt(myState["read_state_available"]) == 1 && !category && jsonBool(myState["indexed"]) == true
        return DirectoryMyState(pinned: pinned, hidden: hidden, muted: muted, permanentMuted: permanent,
            effectiveLevel: level, mutedUntil: optionalText(myState["muted_until"]),
            readStateAvailable: readable ? 1 : 0, indexed: readable,
            readState: category ? "NOT_APPLICABLE" : nil,
            lastReadMessageID: readable ? decimal(myState["last_read_msg_id"]) : nil,
            lastReadVisibleAt: readable ? optionalText(myState["last_read_visible_at"]) : nil,
            unreadCount: readable ? count(myState["unread_count"]) : nil,
            unreadMentionCount: readable ? count(myState["unread_mention_count"]) : nil,
            grantsSend: false, grantsReceiptWrite: false)
    }

    public static let unavailable = DirectoryMyState(pinned: 0, hidden: 0, muted: 0, permanentMuted: false,
        effectiveLevel: 0, mutedUntil: nil, readStateAvailable: 0, indexed: false, readState: nil,
        lastReadMessageID: nil, lastReadVisibleAt: nil, unreadCount: nil, unreadMentionCount: nil,
        grantsSend: false, grantsReceiptWrite: false)

    private static func bit(_ value: Any?) -> Int? {
        guard let number = exactInt(value), number == 0 || number == 1 else { return nil }
        return number
    }
    private static func level(_ value: Any?) -> Int? {
        guard let number = exactInt(value), (0...2).contains(number) else { return nil }
        return number
    }
    fileprivate static func jsonBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    fileprivate static func exactInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(number.intValue), number.stringValue == String(number.intValue) else { return nil }
        return number.intValue
    }
    private static func decimal(_ value: Any?) -> String? {
        if let text = value as? String {
            guard !text.isEmpty, text.count <= 19, text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
                  let number = Int64(text), String(number) == text, number >= 0 else { return nil }
            return text
        }
        guard let number = exactInt(value), number >= 0 else { return nil }
        return String(number)
    }
    private static func count(_ value: Any?) -> Int? {
        guard let number = exactInt(value), number >= 0 else { return nil }
        return number
    }
    private static func optionalText(_ value: Any?) -> String? {
        value as? String
    }
}

/// Type 5 read surface. History and ack stay on the original notification service.
/// A caller cannot pass a bare true to invent either grant, and loading does not mark read.
public struct MessageContainerReadHost: Equatable, Sendable {
    public let container: MessageContainerProjection
    public let state: DirectoryMyState
    public var grantsSend: Bool { false }
    public var grantsReceiptWrite: Bool { false }
    public var unreadCount: Int? { state.readStateAvailable == 1 && state.indexed ? state.unreadCount : nil }
    public init?(container: MessageContainerProjection, state: DirectoryMyState) {
        guard container.conversationType == "5", container.grantsSend == false else { return nil }
        self.container = container
        self.state = state
    }
    public func acknowledge() throws {
        throw ChannelAuthorizationError.waitingSource
    }
}

/// Calls the original `ChannelNotificationService.acknowledge` and `receipt`.
/// Page load does not mark read. A missing receipt stays UNKNOWN on the same request id.
public struct MessageContainerOriginalAck: Equatable, Sendable {
    public struct Receipt: Equatable, Sendable {
        public let requestID: String
        public let operation: String?
        public let scopeType: Int?
        public let scopeID: String?
        public let status: String
        public let outcome: String
        public let replayed: Bool
        public let resumeSameRequest: Bool
        public let resultRedacted: Bool?
        public let mustRefreshState: Bool?
        public var markedReadOnLoad: Bool { false }
        public var grantsSend: Bool { false }
    }

    /// Original write is POST `api/im/read`. Original readback is GET `api/im/notification-requests/{requestId}`.
    /// This value does not send either call. Page load does not mark read.
    public static let readPath = "api/im/read"
    public static let receiptPathPrefix = "api/im/notification-requests/"

    public init() {}

    public func acknowledge(actor: Int64, channelID: Int64, lastMessageID: Int64, requestID: String,
                            channelKind: Int, sameScope: (Int64, Int64) -> Bool,
                            writer: (Int64, Int64, Int64, String) throws -> [String: Any]) throws -> Receipt {
        try gate(actor: actor, channelID: channelID, requestID: requestID, channelKind: channelKind, sameScope: sameScope)
        guard lastMessageID >= 0 else { throw ChannelAuthorizationError.invalidCatalog }
        let body = try writer(actor, channelID, lastMessageID, requestID)
        return try applied(body, channelID: channelID, requestID: requestID)
    }

    /// Explicit ack only. A late lease does not call the writer. Page load does not use this.
    public func acknowledgeExplicit(actor: Int64, channelID: Int64, lastMessageID: Int64, requestID: String,
                                    channelKind: Int, lease: ChannelPageLease, isolation: ChannelRevokeIsolation,
                                    sameScope: (Int64, Int64) -> Bool,
                                    writer: (Int64, Int64, Int64, String) throws -> [String: Any]) throws -> Receipt {
        guard Int64(lease.identity.accountID) == actor, Int64(lease.conversationID) == channelID else {
            throw ChannelAuthorizationError.account4Mismatch
        }
        _ = try isolation.admit(ChannelIsolatedRequest(lease: lease, action: .channelWrite))
        let receipt = try acknowledge(actor: actor, channelID: channelID, lastMessageID: lastMessageID,
                                      requestID: requestID, channelKind: channelKind, sameScope: sameScope, writer: writer)
        guard sameScope(actor, channelID) else { throw ChannelAuthorizationError.notMember }
        guard Int64(lease.identity.accountID) == actor, Int64(lease.conversationID) == channelID else {
            throw ChannelAuthorizationError.account4Mismatch
        }
        _ = try isolation.admit(ChannelIsolatedRequest(lease: lease, action: .channelWrite))
        return receipt
    }

    /// Current membership is not this gate. The original account can read a redacted receipt after revoke.
    public func recover(actor: Int64, channelID: Int64, requestID: String, channelKind: Int,
                        originalAccount: (Int64, String) -> Bool,
                        receipt: (Int64, String) throws -> [String: Any]) throws -> Receipt {
        guard actor > 0, channelID > 0, requestOK(requestID), channelKind != 0 else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        guard originalAccount(actor, requestID) else { throw ChannelAuthorizationError.notMember }
        let body = try receipt(actor, requestID)
        guard originalAccount(actor, requestID) else { throw ChannelAuthorizationError.notMember }
        if body["status"] as? String == "NOT_FOUND" {
            guard body["request_id"] as? String == requestID,
                  body["outcome"] as? String == "UNKNOWN",
                  DirectoryMyState.jsonBool(body["resume_with_same_request"]) == true,
                  body["result"] == nil else {
                throw ChannelAuthorizationError.invalidCatalog
            }
            return Receipt(requestID: requestID, operation: nil, scopeType: nil, scopeID: nil,
                           status: "NOT_FOUND", outcome: "UNKNOWN", replayed: false, resumeSameRequest: true,
                           resultRedacted: nil, mustRefreshState: nil)
        }
        return try applied(body, channelID: channelID, requestID: requestID)
    }

    private func gate(actor: Int64, channelID: Int64, requestID: String, channelKind: Int,
                      sameScope: (Int64, Int64) -> Bool) throws {
        guard actor > 0, channelID > 0, requestOK(requestID) else { throw ChannelAuthorizationError.invalidCatalog }
        guard channelKind != 0 else { throw ChannelAuthorizationError.invalidCatalog }
        guard sameScope(actor, channelID) else { throw ChannelAuthorizationError.notMember }
    }

    private func applied(_ body: [String: Any], channelID: Int64, requestID: String) throws -> Receipt {
        guard body["request_id"] as? String == requestID,
              body["operation"] as? String == "ACK",
              DirectoryMyState.exactInt(body["scope_type"]) == 1,
              body["scope_id"] as? String == String(channelID),
              let status = body["status"] as? String, status == "APPLIED" || status == "PENDING",
              let replayed = DirectoryMyState.jsonBool(body["replayed"]),
              let refresh = DirectoryMyState.jsonBool(body["must_refresh_state"]), refresh == replayed,
              let redacted = DirectoryMyState.jsonBool(body["result_redacted"]) else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        if redacted && body["result"] != nil { throw ChannelAuthorizationError.invalidCatalog }
        if status == "PENDING" {
            guard body["outcome"] as? String == "UNKNOWN",
                  DirectoryMyState.jsonBool(body["resume_with_same_request"]) == true else {
                throw ChannelAuthorizationError.invalidCatalog
            }
            return Receipt(requestID: requestID, operation: "ACK", scopeType: 1, scopeID: String(channelID),
                           status: "PENDING", outcome: "UNKNOWN", replayed: replayed, resumeSameRequest: true,
                           resultRedacted: redacted, mustRefreshState: refresh)
        }
        return Receipt(requestID: requestID, operation: "ACK", scopeType: 1, scopeID: String(channelID),
                       status: "APPLIED", outcome: "APPLIED", replayed: replayed, resumeSameRequest: false,
                       resultRedacted: redacted, mustRefreshState: refresh)
    }

    private func requestOK(_ value: String) -> Bool {
        guard (16...96).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value) || scalar.value == 95 || scalar.value == 45
        }
    }
}

/// Original `ChannelMessageService.history(actor, channel, before, after, limit)`.
/// The inner read is `listMessages(actor, channel, before, clampedLimit, after)`.
/// A history read does not acknowledge and does not mark the page read.
public struct MessageContainerHistory: Equatable, Sendable {
    public init() {}

    public func read(actor: Int64, channelID: Int64, before: Int64?, after: Int64?, limit: Int,
                     conversationType: Int, channelKind: Int,
                     canReadHistory: (Int64, Int64) -> Bool,
                     listMessages: ((Int64, Int64, Int64?, Int, Int64?) -> [String: Any])?) throws -> [String: Any] {
        guard conversationType == 5, channelKind != 0, actor > 0, channelID > 0 else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        if let before, before < 0 { throw ChannelAuthorizationError.invalidCatalog }
        if let after, after < 0 { throw ChannelAuthorizationError.invalidCatalog }
        if let before, before > 0, after != nil { throw ChannelAuthorizationError.invalidCatalog }
        guard canReadHistory(actor, channelID) else { throw ChannelAuthorizationError.notMember }
        guard let listMessages else { throw ChannelAuthorizationError.waitingListMessages }
        let clamped = limit <= 0 ? 20 : min(limit, 50)
        let page = listMessages(actor, channelID, before, clamped, after)
        guard page["sync_contract"] as? String == "VISIBLE_ORDER_PLUS_MUTATIONS_V1",
              page["legacy_cache_action"] as? String == "RELOAD_ON_RESUME",
              page["list"] is [Any],
              exactCursor(page["mutation_cursor"]) != nil,
              exactBool(page["has_more"]) != nil || exactBool(page["hasMore"]) != nil,
              aliasesAgree(page["has_more"], page["hasMore"], exactBool),
              aliasesAgree(page["next_cursor"], page["nextCursor"], exactCursor),
              aliasesAgree(page["next_after"], page["nextAfter"], exactCursor),
              page["operation"] as? String != "ACK" else {
            throw ChannelAuthorizationError.invalidCatalog
        }
        return page
    }

    private func exactBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private func exactCursor(_ value: Any?) -> String? {
        if value is NSNull { return nil }
        if let text = value as? String {
            guard !text.isEmpty, text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else { return nil }
            return text
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
           number.doubleValue == Double(number.int64Value), number.int64Value >= 0,
           number.stringValue == String(number.int64Value) {
            return String(number.int64Value)
        }
        return nil
    }

    private func aliasesAgree(_ left: Any?, _ right: Any?, _ parse: (Any?) -> String?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case (nil, _): return parse(right) != nil || right is NSNull
        case (_, nil): return parse(left) != nil || left is NSNull
        default:
            if left is NSNull && right is NSNull { return true }
            return parse(left) != nil && parse(left) == parse(right)
        }
    }

    private func aliasesAgree(_ left: Any?, _ right: Any?, _ parse: (Any?) -> Bool?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case (nil, _): return parse(right) != nil
        case (_, nil): return parse(left) != nil
        default: return parse(left) != nil && parse(left) == parse(right)
        }
    }

    /// A late or revoked lease never reaches `listMessages`. Rows keep the original viewer projection:
    /// another conversation is dropped, and a non-normal status keeps empty content.
    public func readIsolated(actor: Int64, channelID: Int64, before: Int64?, after: Int64?, limit: Int,
                             conversationType: Int, channelKind: Int, lease: ChannelPageLease,
                             isolation: ChannelRevokeIsolation, canReadHistory: (Int64, Int64) -> Bool,
                             listMessages: ((Int64, Int64, Int64?, Int, Int64?) -> [String: Any])?) throws -> [String: Any] {
        guard Int64(lease.identity.accountID) == actor, Int64(lease.conversationID) == channelID else {
            throw ChannelAuthorizationError.account4Mismatch
        }
        guard canReadHistory(actor, channelID) else { throw ChannelAuthorizationError.notMember }
        _ = try isolation.admit(ChannelIsolatedRequest(lease: lease, action: .channelRead))
        var page = try read(actor: actor, channelID: channelID, before: before, after: after, limit: limit,
                            conversationType: conversationType, channelKind: channelKind,
                            canReadHistory: canReadHistory, listMessages: listMessages)
        guard canReadHistory(actor, channelID) else { throw ChannelAuthorizationError.notMember }
        guard Int64(lease.identity.accountID) == actor, Int64(lease.conversationID) == channelID else {
            throw ChannelAuthorizationError.account4Mismatch
        }
        page["list"] = try projectList(page["list"], channelID: channelID)
        guard canReadHistory(actor, channelID) else { throw ChannelAuthorizationError.notMember }
        return page
    }

    func projectList(_ raw: Any?, channelID: Int64) throws -> [[String: Any]] {
        guard let rows = raw as? [Any] else { throw ChannelAuthorizationError.invalidCatalog }
        let channel = String(channelID)
        var projected: [[String: Any]] = []
        for row in rows {
            guard let row = row as? [String: Any] else { throw ChannelAuthorizationError.invalidCatalog }
            guard let conversation = text(row["conversationId"]), conversation == channel,
                  text(row["id"]) != nil, text(row["senderId"]) != nil else { continue }
            var copy = row
            if DirectoryMyState.exactInt(row["status"]) != 0 {
                copy["content"] = ""
                copy["extraJson"] = NSNull()
            }
            projected.append(copy)
        }
        return projected
    }

    private func text(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = DirectoryMyState.exactInt(value), number >= 0 { return String(number) }
        return nil
    }
}
