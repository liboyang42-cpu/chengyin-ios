import Foundation

/// Issued channel authorization. Bound to P38 ACCOUNT4, a cataloged group
/// conversation, and the exact consented P04 published rules version.
public struct ChannelAuthorizationGrant: Equatable, Sendable {
    public let identity: ChannelAccount4Identity
    public let channelID: Int
    public let conversationID: Int
    public let role: ChannelRole
    public let consentedRulesVersion: Int?
    public let generation: UInt64
    public init(identity: ChannelAccount4Identity, channelID: Int, conversationID: Int, role: ChannelRole,
                consentedRulesVersion: Int?, generation: UInt64) {
        self.identity = identity
        self.channelID = channelID
        self.conversationID = conversationID
        self.role = role
        self.consentedRulesVersion = consentedRulesVersion
        self.generation = generation
    }
    public var capabilities: Set<ChannelCapability> { role.capabilities }
    public func permits(_ capability: ChannelCapability) -> Bool { capabilities.contains(capability) }
}

public enum ChannelMemberAuthorizationProjection {
    public static func authorize(identity: ChannelAccount4Identity, catalog: ChannelCatalogEntry,
                                 role: ChannelRole, consentedRulesVersion: Int?,
                                 capability: ChannelCapability) throws {
        guard catalog.kind == .group else { throw ChannelAuthorizationError.invalidCatalog }
        guard role != .none else { throw ChannelAuthorizationError.notMember }
        guard let consentedRulesVersion, consentedRulesVersion == catalog.rules.publishedVersion,
              catalog.rules.isCurrent else { throw ChannelAuthorizationError.rulesConsentRequired }
        guard role.capabilities.contains(capability) else { throw ChannelAuthorizationError.roleRequired }
        _ = identity
    }

    /// Channel rw never becomes a friend grant. Friend-only mutations keep a distinct error.
    public static func denyFriendImpersonation(_ grant: ChannelAuthorizationGrant,
                                               mutation: IMMutation) throws {
        switch mutation {
        case .start:
            throw ChannelAuthorizationError.friendPermissionRequired
        case .read, .mute:
            guard grant.permits(.read) else { throw ChannelAuthorizationError.channelPermissionRequired }
        case .send:
            guard grant.permits(.write) else { throw ChannelAuthorizationError.channelPermissionRequired }
        }
    }
}
