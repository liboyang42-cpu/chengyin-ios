import Foundation

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
