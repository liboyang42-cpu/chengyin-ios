import Foundation

/// Permission domains are not interchangeable. Channel grants cannot satisfy
/// friend remarks/DM, and friend grants cannot satisfy channel rw or governance.
public enum SocialPermissionDomain: String, Equatable, Sendable {
    case channel, friend, progressPrivacy
}

public enum FriendOnlyAction: String, Equatable, Sendable {
    case remarks, directMessage
}

public enum ChannelOnlyAction: String, Equatable, Sendable {
    case channelRead, channelWrite, governance, invite, apply, ban, leave, appeal
}

/// P44 effective progress privacy is a dedicated projection. Remarks and existing
/// DMs cannot disclose it.
public enum ProgressPrivacySurface: String, Equatable, Sendable {
    case progressPrivacy, remarks, directMessage, channelMessage
}

public enum FriendPermissionGrant: Equatable, Sendable {
    case none
    case friend(accountID: Int)
}

public enum FriendPermissionDistinctFromChannel {
    public static func authorize(channel: ChannelAuthorizationGrant?, friend: FriendPermissionGrant,
                                 action: FriendOnlyAction) throws {
        _ = channel
        switch action {
        case .remarks, .directMessage:
            guard case .friend(let accountID) = friend, accountID > 0 else {
                throw ChannelAuthorizationError.friendPermissionRequired
            }
        }
    }

    public static func authorize(channel: ChannelAuthorizationGrant?, friend: FriendPermissionGrant,
                                 action: ChannelOnlyAction) throws {
        _ = friend
        guard let channel else { throw ChannelAuthorizationError.channelPermissionRequired }
        let capability: ChannelCapability
        switch action {
        case .channelRead: capability = .read
        case .channelWrite: capability = .write
        case .governance: capability = .govern
        case .invite: capability = .invite
        case .apply: capability = .apply
        case .ban: capability = .ban
        case .leave: capability = .leave
        case .appeal: capability = .appeal
        }
        guard channel.permits(capability) else { throw ChannelAuthorizationError.channelPermissionRequired }
    }

    /// P44: progress privacy ≠ remarks/DM. A channel or friend grant on those
    /// surfaces cannot disclose effective progress.
    public static func discloseProgress(channel: ChannelAuthorizationGrant?, friend: FriendPermissionGrant,
                                        surface: ProgressPrivacySurface) throws {
        switch surface {
        case .remarks, .directMessage:
            throw ChannelAuthorizationError.progressPrivacyDenied
        case .channelMessage:
            _ = channel
            throw ChannelAuthorizationError.progressPrivacyDenied
        case .progressPrivacy:
            _ = friend
            guard channel?.permits(.read) == true else { throw ChannelAuthorizationError.progressPrivacyDenied }
        }
    }

    public static func domain(for mutation: IMMutation) -> SocialPermissionDomain {
        switch mutation {
        case .start: return .friend
        case .read, .readCursor, .mute, .send: return .channel
        }
    }
}
